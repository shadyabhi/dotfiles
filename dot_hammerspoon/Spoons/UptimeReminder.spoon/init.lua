--- === UptimeReminder ===
---
--- Suggests a restart via a sticky banner when laptop uptime exceeds a
--- threshold (default 7 days) and the local time is past a configured hour
--- (default 17:00). Banner persists until clicked; clicking snoozes the
--- check for a configurable interval.
---
--- Requires a banner-capable notify provider with this shape:
---     notify:banner({ title=, lines={...}, level=, onClick=fn(line, idx) })
--- returning a handle with :hide() and :update(opts). The bundled
--- Notify spoon satisfies this.
---
--- Usage:
---     hs.loadSpoon("UptimeReminder")
---     spoon.UptimeReminder
---         :configure({ notify = spoon.Notify })
---         :start()

local obj = {}
obj.__index = obj

obj.name = "UptimeReminder"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

obj.thresholdDays    = 7
obj.hourThreshold    = 17
obj.checkIntervalSec = 30 * 60
obj.snoozeSec        = 2 * 60 * 60

obj.notify     = nil
obj._timer     = nil
obj._banner    = nil
obj._snoozeUntil = 0

local function bootEpoch()
    local out = hs.execute("sysctl -n kern.boottime")
    if not out then return nil end
    return tonumber(out:match("sec = (%d+)"))
end

local function uptimeDays()
    local boot = bootEpoch()
    if not boot then return 0 end
    return (os.time() - boot) / 86400
end

function obj:_shouldShow()
    if os.time() < self._snoozeUntil then return false end
    if os.date("*t").hour < self.hourThreshold then return false end
    return uptimeDays() >= self.thresholdDays
end

function obj:_hide()
    if self._banner then
        self._banner:hide()
        self._banner = nil
    end
end

function obj:_show()
    local days = math.floor(uptimeDays())
    local title = string.format("Uptime: %d days", days)
    local lines = {
        "Restart suggested — laptop running too long",
        "Click to snooze " .. math.floor(self.snoozeSec / 3600) .. "h",
    }

    local onClick = function()
        self._snoozeUntil = os.time() + self.snoozeSec
        self:_hide()
    end

    if self._banner then
        self._banner:update({ title = title, lines = lines, level = "alert", onClick = onClick })
    else
        self._banner = self.notify:banner({
            title   = title,
            lines   = lines,
            level   = "alert",
            onClick = onClick,
        })
    end
end

function obj:_tick()
    if self:_shouldShow() then
        self:_show()
    else
        self:_hide()
    end
end

function obj:configure(opts)
    opts = opts or {}
    if opts.notify           then self.notify           = opts.notify           end
    if opts.thresholdDays    then self.thresholdDays    = opts.thresholdDays    end
    if opts.hourThreshold    then self.hourThreshold    = opts.hourThreshold    end
    if opts.checkIntervalSec then self.checkIntervalSec = opts.checkIntervalSec end
    if opts.snoozeSec        then self.snoozeSec        = opts.snoozeSec        end
    return self
end

function obj:start()
    if not self.notify or type(self.notify.banner) ~= "function" then
        hs.printf("[UptimeReminder] notify provider missing :banner(); not starting")
        return self
    end
    if self._timer then self._timer:stop() end
    self:_tick()
    self._timer = hs.timer.doEvery(self.checkIntervalSec, function() self:_tick() end)
    return self
end

function obj:stop()
    if self._timer then self._timer:stop(); self._timer = nil end
    self:_hide()
    return self
end

return obj
