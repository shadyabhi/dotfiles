-- Run in Hammerspoon with dofile. Exercises the real status script and canvas.
local root = hs.configdir .. "/Spoons/AgentSessions.spoon/"
local artifact = os.tmpname() .. "-workmux-source"
assert(hs.fs.mkdir(artifact))

local function write(path, contents)
    local file = assert(io.open(path, "w"))
    file:write(contents)
    file:close()
end

local workmux = artifact .. "/workmux"
local payload = artifact .. "/workmux.json"
local feed = artifact .. "/feed"
write(workmux, "#!/bin/sh\n[ \"$*\" = 'status --all --json' ] || exit 1\ncat '" .. payload .. "'\n")
write(feed, "#!/bin/sh\nexport WORKMUX_BIN='" .. workmux
    .. "' TMUX_BIN=/usr/bin/false\nexec '" .. root .. "scripts/menubar.py'\n")
hs.execute("chmod +x '" .. workmux .. "' '" .. feed .. "'")

local original = spoon.AgentSessions
local original_focus = hs.settings.get("AgentSessions.autoFocus")
local subject = dofile(root .. "init.lua")
local results = {}
local started = false
local fresh = { agent_kind = "claude", status = "waiting", pane_id = "%999998",
    project = "still-in-grace-period", updated_ts = 101, elapsed_secs = 59 }
local waiting = {
    { agent_kind = "claude", status = "waiting", pane_id = "%999999",
      project = "workmux-only", branch = "audit-slowness", updated_ts = 100, elapsed_secs = 59 },
    fresh,
}
local steps = {
    { "waiting request has a one-minute grace period", waiting, function()
        assert(not _agent_sessions_state.panel, "request opened before one minute")
    end },
    { "workmux owns the displayed session identity", waiting, function()
        local panel = assert(_agent_sessions_state.panel, "workmux waiting session did not open panel")
        local texts = {}
        for i = 1, #panel do
            if panel[i].type == "text" then texts[#texts + 1] = tostring(panel[i].text) end
        end
        local text = table.concat(texts, "\n")
        panel:imageFromCanvas():saveToFile(artifact .. "/popup.png")
        write(artifact .. "/panel.txt", text)
        assert(text:find("Workmux", 1, true), "panel still labels a workmux session by agent_kind")
        assert(not text:lower():find("claude", 1, true), "Claude identity leaked into panel")
        assert(text:find("workmux-only", 1, true), "workmux project missing")
        assert(not text:find("still-in-grace-period", 1, true), "fresh request appeared alongside overdue request")
        _agent_sessions_state.hide_panel("user_dismiss")
    end, age = 60 },
    { "dismissing an overdue request preserves unseen requests", { fresh }, function()
        assert(_agent_sessions_state.panel, "unseen request was dismissed with another session")
    end, age = 60 },
    { "empty workmux result clears the popup", {}, function()
        assert(not _agent_sessions_state.panel, "non-workmux session kept popup open")
    end },
}

local function finish()
    hs.settings.set("AgentSessions.autoFocus", original_focus)
    original:start()
    write(artifact .. "/results.json", hs.json.encode(results, true))
    print("Workmux source E2E artifacts: " .. artifact)
end

local function run(index)
    local step = steps[index]
    if not step then finish(); return end
    if step.age then step[2][1].elapsed_secs = step.age end
    write(payload, hs.json.encode({ agents = step[2] }))
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
    poll = hs.timer.doEvery(0.1, function()
        if _agent_sessions_state.in_flight and hs.timer.secondsSinceEpoch() < deadline then return end
        if hs.timer.secondsSinceEpoch() < ready_at then subject:refresh(); return end
        poll:stop()
        local ok, err = xpcall(function()
            assert(not _agent_sessions_state.in_flight, "status fetch timed out")
            step[3]()
        end, debug.traceback)
        results[#results + 1] = { name = step[1], passed = ok, error = err }
        if not ok then finish(); return end
        run(index + 1)
    end)
end

run(1)
return artifact
