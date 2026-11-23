-- Run in Hammerspoon: dofile(hs.configdir .. "/Spoons/AgentSessions.spoon/tests/action_required_e2e.lua")
-- Exercises real task polling, canvases, and hotkeys with a controlled status feed.
local root = hs.configdir .. "/Spoons/AgentSessions.spoon/"
local artifact = os.tmpname() .. "-agent-sessions"
assert(hs.fs.mkdir(artifact))

local function write(path, contents)
    local file = assert(io.open(path, "w"))
    file:write(contents)
    file:close()
end

local feed = artifact .. "/feed"
local payload = artifact .. "/payload.json"
write(feed, "#!/bin/sh\ncat '" .. payload .. "'\n")
hs.execute("chmod +x '" .. feed .. "'")

local original = spoon.AgentSessions
local original_focus = hs.settings.get("AgentSessions.autoFocus")
local subject = dofile(root .. "init.lua")
local results = {}
local started = false

local function texts()
    local panel = _agent_sessions_state.panel
    local out = {}
    if panel then
        for i = 1, #panel do
            if panel[i].type == "text" then out[#out + 1] = tostring(panel[i].text) end
        end
    end
    return table.concat(out, "\n")
end

local function session(status, name, stamp, age)
    return {
        status = status, session_id = name, project_name = name,
        agent = "Test", updated_at = stamp or 1, elapsed_secs = age,
    }
end

local waiting = session("Input", "needs-permission")
local working = session("Working", "still-working")
local idle = session("Idle", "already-done")
local steps = {
    { "working and idle do not open a popup", { working, idle }, function()
        assert(not _agent_sessions_state.panel, "non-actionable sessions opened a popup")
    end },
    { "new request waits before opening a popup", { waiting, working, idle }, function()
        assert(not _agent_sessions_state.panel, "request opened before one minute")
    end },
    { "automatic chooser contains only waiting agents", { waiting, working, idle }, function()
        assert(_agent_sessions_state.panel, "waiting session did not open a popup")
        local text = texts()
        assert(text:find("needs%-permission"), "waiting agent missing")
        assert(not text:find("still%-working"), "working agent offered as an action")
        assert(not text:find("already%-done"), "finished agent offered as an action")
        _agent_sessions_state.panel:imageFromCanvas():saveToFile(artifact .. "/popup.png")
    end, delay = 61 },
    { "automatic chooser closes when the agent resumes", { working, idle }, function()
        assert(not _agent_sessions_state.panel, "popup remained after action cleared")
    end },
    { "manual overview remains available", { working, idle }, function()
        _agent_sessions_state.toggle_panel()
        assert(texts():find("still%-working"), "manual overview lost working sessions")
        _agent_sessions_state.hide_panel()
    end },
    { "dismissed request stays dismissed", { session("Input", "needs-permission", 1, 60) }, function()
        assert(_agent_sessions_state.panel, "request did not reopen after resuming")
        _agent_sessions_state.hide_panel("user_dismiss")
        subject:refresh()
    end },
    { "same request does not reopen", { waiting }, function()
        assert(not _agent_sessions_state.panel, "dismissed request reopened")
    end },
    { "new request opens again", { session("Input", "needs-permission", 2) }, function()
        assert(not _agent_sessions_state.panel, "new request skipped the one-minute delay")
    end },
    { "new request opens after one minute", { session("Input", "needs-permission", 2, 60) }, function()
        assert(_agent_sessions_state.panel, "new request was suppressed")
    end },
}

local function finish()
    hs.settings.set("AgentSessions.autoFocus", original_focus)
    original:start()
    write(artifact .. "/results.json", hs.json.encode(results, true))
    print("AgentSessions E2E artifacts: " .. artifact)
end

local function run(index)
    local step = steps[index]
    if not step then finish(); return end
    write(payload, hs.json.encode({ details = step[2] }))
    if not started then
        hs.settings.set("AgentSessions.autoFocus", false)
        subject:configure({ script = feed, intervalSec = 3600 }):start()
        started = true
    else
        subject:refresh()
    end
    local ready_at = hs.timer.secondsSinceEpoch() + (step.delay or 0)
    local deadline = ready_at + 10
    local poll
    poll = hs.timer.doEvery(1, function()
        if _agent_sessions_state.in_flight and hs.timer.secondsSinceEpoch() < deadline then return end
        if hs.timer.secondsSinceEpoch() < ready_at then subject:refresh(); return end
        poll:stop()
        local ok, err = xpcall(function()
            assert(not _agent_sessions_state.in_flight, "status fetch timed out")
            step[3]()
        end, debug.traceback)
        results[#results + 1] = {
            name = step[1], passed = ok, error = err,
            title = _agent_sessions_state.bar:title(), panel_text = texts(),
        }
        if not ok then finish(); return end
        run(index + 1)
    end)
end

run(1)
return artifact
