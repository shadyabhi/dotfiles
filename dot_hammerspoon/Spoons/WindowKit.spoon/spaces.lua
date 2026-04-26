local M = {}

local spaces = require "hs.spaces"
local window = require "hs.window"

local MC = nil

local function flashScreen(screen)
    local flash = hs.canvas.new(screen:fullFrame()):appendElements({
        action = "fill",
        fillColor = { alpha = 0.35, red = 1 },
        type = "rectangle",
    })
    flash:show()
    hs.timer.doAfter(0.25, function() flash:delete() end)
end

local function getGoodFocusedWindow(nofull)
    local win = window.focusedWindow()
    if not win or not win:isStandard() then return end
    if nofull and win:isFullScreen() then return end
    return win
end

function M.moveWindowOneSpace(dir, parent)
    if not MC or not MC.moveWindowToSpace then
        if parent and parent.alertFn then parent.alertFn("Spaces", "PaperWM not loaded", 1.5) end
        return
    end

    local win = getGoodFocusedWindow(true)
    if not win then return end

    local screen = win:screen()
    local uuid = screen:getUUID()
    local screenSpaces = spaces.allSpaces()[uuid]
    if not screenSpaces then return end

    local userSpaces = {}
    for _, spc in ipairs(screenSpaces) do
        if spaces.spaceType(spc) == "user" then
            userSpaces[#userSpaces + 1] = spc
        end
    end

    if #userSpaces <= 1 then
        if parent and parent.alertFn then parent.alertFn("Spaces", "Only one space available", 1.5) end
        return
    end

    local currentSpace = spaces.windowSpaces(win)
    if not currentSpace then return end
    currentSpace = currentSpace[1]

    local currentIdx
    for i, spc in ipairs(userSpaces) do
        if spc == currentSpace then currentIdx = i; break end
    end
    if not currentIdx then return end

    local targetIdx = dir == "right" and currentIdx + 1 or currentIdx - 1
    if targetIdx < 1 or targetIdx > #userSpaces then
        flashScreen(screen)
        return
    end

    local ok, err = MC:moveWindowToSpace(win, userSpaces[targetIdx])
    if not ok and parent and parent.alertFn then
        parent.alertFn("Spaces", err or "moveWindowToSpace failed", 2)
    end
end

function M.bind(parent)
    local path = parent.spaces and parent.spaces.paperwmPath
        or (hs.configdir .. "/Spoons/PaperWM.spoon/mission_control.lua")
    local f = io.open(path, "r")
    if f then
        f:close()
        MC = dofile(path)
    else
        hs.logger.new("WindowKit.spaces", "info").f("PaperWM not found at %s; spaces hotkeys disabled", path)
        return
    end

    parent.hyperkey:bind("h", "[", function() M.moveWindowOneSpace("left", parent) end)
    parent.hyperkey:bind("h", "]", function() M.moveWindowOneSpace("right", parent) end)
end

return M
