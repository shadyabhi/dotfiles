--[[
    Process monitor: runs a Python script at a configurable interval
    to ensure required apps are always running.
]]

local M = {}

local SCRIPT = hs.configdir .. "/process_monitor.py"
local INTERVAL = 5 -- seconds

local timer = nil
local currentTask = nil

local notify = require("notify")

local function check()
    currentTask = hs.task.new("/usr/bin/python3", function(exitCode, stdout, stderr)
        currentTask = nil
        if stdout then
            local trimmed = stdout:gsub("%s+$", "")
            if trimmed ~= "" then
                notify.alert("Process Monitor", trimmed, 5)
            end
        end
    end, {SCRIPT})
    currentTask:start()
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
