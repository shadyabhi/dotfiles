--[[
    Creates shortcuts related to launching apps via shortcuts
]]

local Mouse = require("mouse")

local HOME = os.getenv("HOME")

-- Helper functions
function file_exists(path)
    local f=io.open(path,"r")
    if f~=nil then io.close(f) return true else return false end
    -- ~= is != in other languages
end

local function launchAndCenter(path)
    hs.application.launchOrFocus(path)
    hs.timer.doAfter(0.3, function() Mouse.toCenter() end)
end

local function launchApp(name)
    return function()
        local path = "/Applications/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end
        local path = HOME .. "/Applications/Edge Apps.localized/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end
        local path = "/System/Library/CoreServices/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end
        local path = "/System/Applications/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = "/System/Applications/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = HOME .. "/Applications/Chrome Apps.localized/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = HOME .. "/Applications/Chrome Apps/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = HOME .. "/Applications/Edge Apps.localized/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = HOME .. "/Applications/Edge Apps/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end
    end
end

-- Shortcuts
h_bind("j", launchApp("Emdash Beta"))
h_bind("b", launchApp("Google Chrome"))
h_bind("c", launchApp("Google Calendar"))
h_bind("e", launchApp("Microsoft Edge"))
h_bind("g", launchApp("Gmail"))
h_bind("r", launchApp("Reclaim"))
h_bind("s", launchApp("Slack"))
h_bind("t", launchApp("iTerm"))
h_bind("m", launchApp("Google Meet"))
h_bind("w", launchApp("Obsidian"))
