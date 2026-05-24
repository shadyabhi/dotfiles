--- === Crons ===
---
--- Small cron-like runner for Hammerspoon-managed jobs.
--- Usage:
---     hs.loadSpoon("Crons")
---     spoon.Crons
---         :configure({
---             jobs = {
---                 { name = "Example", at = "09:00", command = "/path/to/script" },
---                 { name = "Poll", every = 300, command = "/path/to/script" },
---             },
---         })
---         :start()

local obj = {}
obj.__index = obj

obj.name = "Crons"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

obj.jobs = {}
obj._timers = {}
obj._lastRunDay = {}

local log = hs.logger.new("Crons", "info")

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function buildCmd(job)
    if job.command then return job.command end
    if not job.script then return nil end

    local cmd = shellQuote(job.script)
    for _, arg in ipairs(job.args or {}) do
        cmd = cmd .. " " .. shellQuote(arg)
    end
    return cmd
end

local function parseAt(at)
    if type(at) == "table" then
        return tonumber(at.hour), tonumber(at.min or at.minute or 0)
    end
    if type(at) ~= "string" then return nil, nil end
    local hour, min = at:match("^(%d%d?):(%d%d)$")
    return tonumber(hour), tonumber(min)
end

function obj:_run(job)
    local cmd = buildCmd(job)
    if not cmd then
        log.wf("job %s has no command or script", job.name or "<unnamed>")
        return
    end

    hs.task.new("/bin/sh", function(_, stdout, stderr)
        local name = job.name or cmd
        local out = (stdout or ""):gsub("%s+$", "")
        local err = (stderr or ""):gsub("%s+$", "")
        if out ~= "" then log.f("%s: %s", name, out) end
        if err ~= "" then log.wf("%s: %s", name, err) end
    end, { "-lc", cmd }):start()
end

local function dayKey(now)
    return string.format("%04d-%02d-%02d", now.year, now.month, now.day)
end

function obj:_tickDaily(job)
    local hour, min = parseAt(job.at)
    if not hour or not min then
        log.wf("job %s has invalid at value", job.name or "<unnamed>")
        return
    end

    local now = os.date("*t")
    if now.hour ~= hour or now.min ~= min then return end

    local key = (job.name or buildCmd(job) or tostring(job)) .. ":" .. dayKey(now)
    if self._lastRunDay[key] then return end

    self._lastRunDay[key] = true
    self:_run(job)
end

function obj:configure(opts)
    opts = opts or {}
    if opts.jobs then self.jobs = opts.jobs end
    return self
end

function obj:add(job)
    table.insert(self.jobs, job)
    return self
end

function obj:start()
    self:stop()

    for _, job in ipairs(self.jobs or {}) do
        if job.every or job.intervalSec then
            local interval = job.every or job.intervalSec
            self:_run(job)
            table.insert(self._timers, hs.timer.doEvery(interval, function() self:_run(job) end))
        elseif job.at then
            self:_tickDaily(job)
            table.insert(self._timers, hs.timer.doEvery(60, function() self:_tickDaily(job) end))
        else
            log.wf("job %s has no every/intervalSec or at schedule", job.name or "<unnamed>")
        end
    end

    return self
end

function obj:stop()
    for _, timer in ipairs(self._timers or {}) do timer:stop() end
    self._timers = {}
    return self
end

return obj
