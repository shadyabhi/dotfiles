--[[
    Creates shortcuts related to launching apps via shortcuts
]]

local Mouse = require("mouse")

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
        local path = "/Users/arastogi/Applications/Edge Apps.localized/" .. name .. ".app"
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

        local path = "/Users/abhijeetr/Applications/Chrome Apps.localized/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = "/Users/abhijeetr/Applications/Edge Apps.localized/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end
    end
end

-- Shortcuts
h_bind("b", launchApp("Google Chrome"))
h_bind(";", launchApp("Cursor"))
h_bind("t", launchApp("iTerm"))
h_bind("w", launchApp("Obsidian"))
h_bind("s", launchApp("Slack"))
h_bind("o", launchApp("Open WebUI"))
h_bind("c", launchApp("Claude"))
h_bind("d", launchApp("DevDocs"))
h_bind("f", launchApp("Firefox"))
h_bind("r", launchApp("Reclaim"))
h_bind("a", launchApp("Chatbox"))
h_bind("e", launchApp("Microsoft Edge"))
h_bind("/", launchApp("TickTick"))
