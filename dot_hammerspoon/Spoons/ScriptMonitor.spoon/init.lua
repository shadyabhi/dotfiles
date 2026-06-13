--- === ScriptMonitor ===
---
--- Generic external-script runner: event-driven (audio/screen) + interval polling.
--- Usage:
---   spoon.ScriptMonitor:addEvent({ on={"audioDevice","screen"}, script=path, delaySec=2 })
---   spoon.ScriptMonitor:addPoll({ script=path, intervalSec=5, onOutput=fn })
---   spoon.ScriptMonitor:start()

local obj = {}
obj.__index = obj

obj.name = "ScriptMonitor"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

local log = hs.logger.new("ScriptMonitor", "info")

local events = {}
local polls = {}
local audioWatcherStarted = false
local screenWatcher = nil

function obj:resource(name)
    return self.spoonPath .. "scripts/" .. name
end

function obj:addEvent(spec)
    table.insert(events, spec)
    return self
end

function obj:addPoll(spec)
    table.insert(polls, spec)
    return self
end

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function buildCmd(spec)
    local cmd = shellQuote(spec.script)
    for _, a in ipairs(spec.args or {}) do
        cmd = cmd .. " " .. shellQuote(a)
    end
    return cmd
end

local function fireEvent(spec)
    -- Cancel any already-pending timer for this spec to debounce rapid events
    if spec._pending then
        spec._pending:stop()
        spec._pending = nil
    end

    local cmd = buildCmd(spec)
    local delay = spec.delaySec or 0
    if delay > 0 then
        spec._pending = hs.timer.doAfter(delay, function()
            spec._pending = nil
            hs.execute(cmd)
            log.f("ran %s after %ds", cmd, delay)
        end)
    else
        hs.execute(cmd)
        log.f("ran %s", cmd)
    end
end

function obj:start()
    local needAudio, needScreen = false, false
    for _, ev in ipairs(events) do
        for _, src in ipairs(ev.on or {}) do
            if src == "audioDevice" then needAudio = true end
            if src == "screen" then needScreen = true end
        end
    end

    if needAudio and not audioWatcherStarted then
        hs.audiodevice.watcher.setCallback(function(event)
            if event ~= "dev#" then return end
            for _, ev in ipairs(events) do
                for _, src in ipairs(ev.on or {}) do
                    if src == "audioDevice" then fireEvent(ev) end
                end
            end
        end)
        hs.audiodevice.watcher.start()
        audioWatcherStarted = true
    end

    if needScreen and not screenWatcher then
        screenWatcher = hs.screen.watcher.new(function()
            for _, ev in ipairs(events) do
                for _, src in ipairs(ev.on or {}) do
                    if src == "screen" then fireEvent(ev) end
                end
            end
        end)
        screenWatcher:start()
    end

    self._pollTimers = self._pollTimers or {}
    for _, poll in ipairs(polls) do
        local function tick()
            local interp = poll.interpreter or "/usr/bin/python3"
            local argv = { poll.script }
            for _, a in ipairs(poll.args or {}) do table.insert(argv, a) end
            local task = hs.task.new(interp, function(_, stdout, _)
                if poll.onOutput and stdout then
                    local trimmed = stdout:gsub("%s+$", "")
                    if trimmed ~= "" then poll.onOutput(trimmed) end
                end
            end, argv)
            if task then task:start() end
        end
        tick()
        local t = hs.timer.doEvery(poll.intervalSec or 5, tick)
        table.insert(self._pollTimers, t)
    end

    return self
end

function obj:fire(source)
    for _, ev in ipairs(events) do
        for _, src in ipairs(ev.on or {}) do
            if src == source then fireEvent(ev) end
        end
    end
    return self
end

function obj:stop()
    if screenWatcher then screenWatcher:stop(); screenWatcher = nil end
    if audioWatcherStarted then
        hs.audiodevice.watcher.stop()
        audioWatcherStarted = false
    end
    for _, t in ipairs(self._pollTimers or {}) do t:stop() end
    self._pollTimers = {}
    return self
end

return obj
