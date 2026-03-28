-- Standardized notification module
-- Usage:
--   local notify = require("notify")
--   notify.info("Title", "subtitle")        -- green background
--   notify.alert("Title", "subtitle")       -- red background
--   notify.info("Title")                    -- subtitle is optional
--   notify.alert("Title", "sub", 3)         -- custom duration in seconds

local M = {}

local canvas = nil
local timer = nil
local fadeTimer = nil

local themes = {
    info = {
        fill   = {red = 0.3, green = 0.75, blue = 0.35, alpha = 0.92},
        stroke = {red = 0.4, green = 0.85, blue = 0.45, alpha = 0.5},
    },
    alert = {
        fill   = {red = 0.85, green = 0.25, blue = 0.25, alpha = 0.92},
        stroke = {red = 0.95, green = 0.4, blue = 0.4, alpha = 0.5},
    },
}

local function show(level, title, subtitle, duration)
    -- Tear down previous notification
    if fadeTimer then fadeTimer:stop(); fadeTimer = nil end
    if timer then timer:stop(); timer = nil end
    if canvas then canvas:delete(); canvas = nil end

    local theme = themes[level] or themes.info
    duration = duration or 0.8

    -- Style constants
    local pad = 16
    local gap = 12
    local titleFont = {name = hs.styledtext.defaultFonts.boldSystem, size = 18}
    local subFont   = {name = hs.styledtext.defaultFonts.boldSystem, size = 14}

    local styledTitle = hs.styledtext.new(title or "", {font = titleFont, color = {white = 0, alpha = 0.9}})
    local titleDims = hs.drawing.getTextDrawingSize(styledTitle)

    local styledSub, subDims
    if subtitle and subtitle ~= "" then
        styledSub = hs.styledtext.new(subtitle, {font = subFont, color = {white = 0, alpha = 0.6}})
        subDims = hs.drawing.getTextDrawingSize(styledSub)
    end

    -- Optionally show app icon if the focused window's app matches
    local iconImage = nil
    local iconSize = 40
    local focusedWin = hs.window.focusedWindow()
    if focusedWin and focusedWin:application() then
        iconImage = hs.image.imageFromAppBundle(focusedWin:application():bundleID())
    end

    local hasIcon = iconImage ~= nil
    local textW = titleDims.w
    if subDims then textW = math.max(textW, subDims.w) end
    local maxTextW = 400
    if textW > maxTextW then textW = maxTextW end

    local contentH = titleDims.h
    if subDims then contentH = contentH + 2 + subDims.h end

    local totalW, totalH
    if hasIcon then
        totalW = pad + iconSize + gap + textW + pad
        totalH = pad + math.max(iconSize, contentH) + pad
    else
        totalW = pad + textW + pad
        totalH = pad + contentH + pad
    end

    -- Position: top-center of the focused screen
    local screen = hs.screen.mainScreen():frame()
    local x = screen.x + (screen.w - totalW) / 2
    local y = screen.y + 10

    canvas = hs.canvas.new({x = x, y = y, w = totalW, h = totalH})

    -- Background
    canvas[1] = {
        type = "rectangle",
        roundedRectRadii = {xRadius = 10, yRadius = 10},
        fillColor = theme.fill,
        strokeColor = theme.stroke,
        strokeWidth = 0.5,
    }

    local nextIdx = 2
    local textX = pad

    -- App icon (if available)
    if hasIcon then
        canvas[nextIdx] = {
            type = "image",
            image = iconImage,
            frame = {x = pad, y = (totalH - iconSize) / 2, w = iconSize, h = iconSize},
        }
        nextIdx = nextIdx + 1
        textX = pad + iconSize + gap
    end

    -- Title
    canvas[nextIdx] = {
        type = "text",
        text = styledTitle,
        frame = {x = textX, y = pad, w = textW, h = titleDims.h},
    }
    nextIdx = nextIdx + 1

    -- Subtitle
    if styledSub then
        canvas[nextIdx] = {
            type = "text",
            text = styledSub,
            frame = {x = textX, y = pad + titleDims.h + 2, w = textW, h = subDims.h},
        }
    end

    canvas:level("overlay")
    canvas:alpha(1)
    canvas:show()

    -- Fade out
    timer = hs.timer.doAfter(duration, function()
        fadeTimer = hs.timer.doEvery(0.02, function()
            local a = canvas:alpha()
            if a <= 0.05 then
                fadeTimer:stop(); fadeTimer = nil
                canvas:delete(); canvas = nil
            else
                canvas:alpha(a - 0.08)
            end
        end)
    end)
end

function M.info(title, subtitle, duration)
    show("info", title, subtitle, duration)
end

function M.alert(title, subtitle, duration)
    show("alert", title, subtitle, duration)
end

return M
