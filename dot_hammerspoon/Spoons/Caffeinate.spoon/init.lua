--- === Caffeinate ===
---
--- Click the menubar item to prevent the display and system from sleeping
--- while idle.
---
--- Usage:
---     hs.loadSpoon("Caffeinate")
---     spoon.Caffeinate:start()

local obj = {}
obj.__index = obj

obj.name = "Caffeinate"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

obj._bar = nil

function obj:_update()
    local enabled = hs.caffeinate.get("displayIdle")
    self._bar:setTitle(enabled and "☕ On" or "☕ Off")
    self._bar:setTooltip(enabled and "Click to allow idle sleep" or "Click to prevent idle sleep")
end

function obj:toggle()
    hs.caffeinate.toggle("displayIdle")
    self:_update()
    return self
end

function obj:start()
    if self._bar then return self end
    self._bar = hs.menubar.new(true, "Caffeinate")
    self._bar:setClickCallback(function() self:toggle() end)
    self:_update()
    return self
end

function obj:stop()
    if self._bar then self._bar:delete(); self._bar = nil end
    return self
end

return obj
