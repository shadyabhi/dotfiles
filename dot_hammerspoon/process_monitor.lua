--[[
    Process monitor: runs a Python script at a configurable interval
    to ensure required apps are always running.
]]

local M = {}

local SCRIPT = hs.configdir .. "/process_monitor.py"
local INTERVAL = 5 -- seconds

local timer = nil
local currentTask = nil

local function check()
    currentTask = hs.task.new("/usr/bin/python3", function(exitCode, stdout, stderr)
        currentTask = nil
        if stdout then
            local trimmed = stdout:gsub("%s+$", "")
            if trimmed ~= "" then
                hs.alert.show(trimmed, {
                    strokeColor = { white = 0, alpha = 0 },
                    fillColor = { red = 0.7, green = 0.1, blue = 0.1, alpha = 0.9 },
                    textColor = { white = 1, alpha = 1 },
                    textFont = ".AppleSystemUIFont",
                    textSize = 16,
                    radius = 10,
                }, 5)
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
