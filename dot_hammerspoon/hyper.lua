--[[
    Define all prefix hyper keys
]]

local hyper = {"cmd", "alt", "ctrl"}
local hypershift = {"cmd", "alt", "ctrl", "shift"}
local hyper_cmd_alt = {"cmd", "alt"}

local hca_hotkeys = {}
local hca_disable_timer = nil

function h_bind(key, func)
    hs.hotkey.bind(hyper, key, func)
end

function hs_bind(key, func)
    hs.hotkey.bind(hypershift, key, func)
end

function hca_bind(key, func)
    local hk = hs.hotkey.bind(hyper_cmd_alt, key, func)
    table.insert(hca_hotkeys, hk)
    return hk
end

hs.hotkey.bind(hyper_cmd_alt, "delete", function()
    if hca_disable_timer then hca_disable_timer:stop() end
    for _, hk in ipairs(hca_hotkeys) do hk:disable() end
    require("notify").alert("Cmd+Opt disabled", "Re-enabling in 3s", 3)
    hca_disable_timer = hs.timer.doAfter(3, function()
        for _, hk in ipairs(hca_hotkeys) do hk:enable() end
        hca_disable_timer = nil
        require("notify").info("Cmd+Opt re-enabled")
    end)
end)
