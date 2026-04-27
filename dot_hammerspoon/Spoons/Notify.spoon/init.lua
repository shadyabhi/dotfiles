--- === Notify ===
---
--- Lightweight on-screen notification widget with info/alert variants.
--- Usage: spoon.Notify:info("Title", "subtitle"); spoon.Notify:alert("Title", "sub", 3)

local obj = {}
obj.__index = obj

obj.name = "Notify"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

obj.themes = {
    info  = { accent = { red = 0.3,  green = 0.75, blue = 0.35, alpha = 1 } },
    alert = { accent = { red = 0.85, green = 0.25, blue = 0.25, alpha = 1 } },
}

obj.maxTextWidth = 350
obj.cornerRadius = 14
obj.minWidth = 220
obj.defaultDuration = 1.5

local canvas, timer, fadeTimer = nil, nil, nil

local function show(self, level, title, subtitle, duration)
    if fadeTimer then fadeTimer:stop(); fadeTimer = nil end
    if timer then timer:stop(); timer = nil end
    if canvas then canvas:delete(); canvas = nil end

    local theme = self.themes[level] or self.themes.info
    duration = duration or self.defaultDuration

    local bgColor    = { red = 0.12, green = 0.12, blue = 0.14, alpha = 0.95 }
    local strokeColor = { red = 0.25, green = 0.25, blue = 0.28, alpha = 0.6 }
    local titleColor = { white = 1, alpha = 0.95 }
    local subColor   = { white = 1, alpha = 0.55 }

    local pad, gap, iconSize = 14, 12, 36
    local titleFont = { name = hs.styledtext.defaultFonts.boldSystem, size = 15 }
    local subFont   = { name = hs.styledtext.defaultFonts.system, size = 13 }

    local styledTitle = hs.styledtext.new(title or "", { font = titleFont, color = titleColor })
    local titleDims = hs.drawing.getTextDrawingSize(styledTitle)

    local styledSub, subDims
    if subtitle and subtitle ~= "" then
        styledSub = hs.styledtext.new(subtitle, { font = subFont, color = subColor })
        subDims = hs.drawing.getTextDrawingSize(styledSub)
    end

    local iconImage = nil
    local focusedWin = hs.window.focusedWindow()
    if focusedWin and focusedWin:application() then
        iconImage = hs.image.imageFromAppBundle(focusedWin:application():bundleID())
    end

    local hasIcon = iconImage ~= nil
    local textW = titleDims.w
    if subDims then textW = math.max(textW, subDims.w) end
    if textW > self.maxTextWidth then textW = self.maxTextWidth end

    local contentH = titleDims.h
    if subDims then contentH = contentH + 3 + subDims.h end

    local totalW, totalH
    if hasIcon then
        totalW = pad + iconSize + gap + textW + pad
        totalH = pad + math.max(iconSize, contentH) + pad
    else
        totalW = pad + textW + pad
        totalH = pad + contentH + pad
    end
    if totalW < self.minWidth then totalW = self.minWidth end

    local screen = hs.screen.mainScreen():frame()
    local x = screen.x + (screen.w - totalW) / 2
    local y = screen.y + math.floor((screen.h - totalH) / 2)

    canvas = hs.canvas.new({ x = x, y = y, w = totalW, h = totalH })

    canvas[1] = {
        type = "rectangle",
        roundedRectRadii = { xRadius = self.cornerRadius, yRadius = self.cornerRadius },
        fillColor = bgColor,
        strokeColor = strokeColor,
        strokeWidth = 0.5,
    }
    canvas[2] = {
        type = "rectangle",
        frame = { x = 0, y = 6, w = 3, h = totalH - 12 },
        roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 },
        fillColor = theme.accent,
        strokeWidth = 0,
    }

    local nextIdx = 3
    local textX = pad
    if hasIcon then
        canvas[nextIdx] = {
            type = "image",
            image = iconImage,
            frame = { x = pad, y = (totalH - iconSize) / 2, w = iconSize, h = iconSize },
            imageScaling = "scaleProportionally",
        }
        nextIdx = nextIdx + 1
        textX = pad + iconSize + gap
    end

    local textY = hasIcon and (totalH - contentH) / 2 or pad
    canvas[nextIdx] = {
        type = "text",
        text = styledTitle,
        frame = { x = textX, y = textY, w = textW, h = titleDims.h },
    }
    nextIdx = nextIdx + 1

    if styledSub then
        canvas[nextIdx] = {
            type = "text",
            text = styledSub,
            frame = { x = textX, y = textY + titleDims.h + 3, w = textW, h = subDims.h },
        }
    end

    canvas:level("overlay")
    canvas:alpha(0)
    canvas:show()

    local fadeInTimer
    fadeInTimer = hs.timer.doEvery(0.015, function()
        local a = canvas:alpha()
        if a >= 0.95 then
            canvas:alpha(1); fadeInTimer:stop()
        else
            canvas:alpha(a + 0.12)
        end
    end)

    timer = hs.timer.doAfter(duration, function()
        fadeTimer = hs.timer.doEvery(0.02, function()
            local a = canvas:alpha()
            if a <= 0.05 then
                fadeTimer:stop(); fadeTimer = nil
                canvas:delete(); canvas = nil
            else
                canvas:alpha(a - 0.06)
            end
        end)
    end)
end

function obj:info(title, subtitle, duration)
    show(self, "info", title, subtitle, duration)
end

function obj:alert(title, subtitle, duration)
    show(self, "alert", title, subtitle, duration)
end

function obj:banner(opts)
    local handle = { _opts = opts or {}, _canvas = nil }

    local function render(o)
        local theme = self.themes[o.level or "alert"] or self.themes.alert
        local pad, lineH = 16, 24
        local title = o.title or ""
        local lines = o.lines or {}
        local w = o.width or 360
        local h = pad * 2 + lineH + (#lines > 0 and (4 + #lines * lineH) or 0)

        local sf = hs.screen.mainScreen():frame()
        local yFrac = o.yFraction or 0.5
        local x = sf.x + (sf.w - w) / 2
        local y = sf.y + sf.h * yFrac

        if handle._canvas then handle._canvas:delete() end
        local c = hs.canvas.new({ x = x, y = y, w = w, h = h })
        c:level(hs.canvas.windowLevels.overlay)
        c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                 + hs.canvas.windowBehaviors.stationary)

        c[1] = {
            type = "rectangle",
            roundedRectRadii = { xRadius = self.cornerRadius, yRadius = self.cornerRadius },
            fillColor   = { red = 0.12, green = 0.12, blue = 0.14, alpha = 0.95 },
            strokeColor = { red = 0.25, green = 0.25, blue = 0.28, alpha = 0.6 },
            strokeWidth = 0.5,
        }
        c[2] = {
            type = "rectangle",
            frame = { x = 0, y = 6, w = 3, h = h - 12 },
            roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 },
            fillColor = theme.accent,
            strokeWidth = 0,
        }
        c[3] = {
            type      = "text",
            text      = title,
            textColor = theme.accent,
            textSize  = 18,
            textFont  = "Menlo",
            frame     = { x = pad, y = pad, w = w - pad * 2, h = lineH },
        }
        for i, line in ipairs(lines) do
            c[3 + i] = {
                type      = "text",
                text      = "  " .. line,
                textColor = { white = 1, alpha = 0.85 },
                textSize  = 16,
                textFont  = "Menlo",
                frame     = {
                    x = pad,
                    y = pad + lineH + 4 + (i - 1) * lineH,
                    w = w - pad * 2,
                    h = lineH,
                },
            }
        end
        c:show()
        handle._canvas = c
    end

    function handle:update(o)
        self._opts = o or self._opts
        render(self._opts)
    end

    function handle:hide()
        if self._canvas then self._canvas:delete(); self._canvas = nil end
    end

    render(handle._opts)
    return handle
end

return obj
