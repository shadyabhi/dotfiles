--[[
    Process monitor: runs a Python script at a configurable interval
    to ensure required apps are always running.
]]

local M = {}

local SCRIPT = hs.configdir .. "/process_monitor.py"
local INTERVAL = 60 -- seconds

local timer = nil

local function check()
    hs.task.new("/usr/bin/python3", function(exitCode, stdout, stderr)
        if stdout then
            local trimmed = stdout:gsub("%s+$", "")
            if trimmed ~= "" then
                hs.alert.show(trimmed)
            end
        end
    end, {SCRIPT}):start()
end

function M.start()
    check()
    timer = hs.timer.doEvery(INTERVAL, check)
end

function M.stop()
    if timer then
        timer:stop()
        timer = nil
    end
end

M.start()

return M
