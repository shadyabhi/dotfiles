--- === HyperKey ===
---
--- Hotkey prefix infrastructure: hyper / hypershift / hyper_cmd_alt.
--- Cmd+Opt+Delete temporarily disables all hyper_cmd_alt bindings.
--- Usage: spoon.HyperKey:bind("h", "j", fn) where prefix in {"h","hs","hca"}.

local obj = {}
obj.__index = obj

obj.name = "HyperKey"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

obj.modifiers = {
    h   = { "cmd", "alt", "ctrl" },
    hs  = { "cmd", "alt", "ctrl", "shift" },
    hca = { "cmd", "alt" },
}

obj.panicDuration = 3
obj.exportGlobals = false
obj.notifyFn = function(_, _, _) end

local hca_hotkeys = {}
local disable_timer = nil

function obj:bind(prefix, key, fn)
    local mods = self.modifiers[prefix]
    if not mods then error("HyperKey: unknown prefix " .. tostring(prefix)) end
    local hk = hs.hotkey.bind(mods, key, fn)
    if prefix == "hca" then table.insert(hca_hotkeys, hk) end
    return hk
end

function obj:start()
    hs.hotkey.bind(self.modifiers.hca, "delete", function()
        if disable_timer then disable_timer:stop() end
        for _, hk in ipairs(hca_hotkeys) do hk:disable() end
        self.notifyFn("Cmd+Opt disabled", "Re-enabling in " .. self.panicDuration .. "s", self.panicDuration)
        disable_timer = hs.timer.doAfter(self.panicDuration, function()
            for _, hk in ipairs(hca_hotkeys) do hk:enable() end
            disable_timer = nil
            self.notifyFn("Cmd+Opt re-enabled", nil, 1)
        end)
    end)

    if self.exportGlobals then
        _G.h_bind   = function(k, fn) return self:bind("h", k, fn) end
        _G.hs_bind  = function(k, fn) return self:bind("hs", k, fn) end
        _G.hca_bind = function(k, fn) return self:bind("hca", k, fn) end
    end
    return self
end

return obj
