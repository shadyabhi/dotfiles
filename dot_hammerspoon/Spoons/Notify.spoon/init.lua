--- === Notify ===
---
--- On-screen notification widget with three presentation styles, all driven by
--- a single entry point:
---
---     spoon.Notify:show{ title = "Saved", body = "3 files" }
---     spoon.Notify:show{ style = "notch", level = "alert", title = "Failed" }
---     local h = spoon.Notify:show{ style = "banner", title = "Uptime",
---                                  rows = { "Restart?" }, onClick = fn }
---     h:hide()
---
--- Options:
---  * style     - "toast" (default, centred), "notch" (grows from the top edge
---                of the screen), or "banner" (draggable list, sticky)
---  * level     - "info" (default) or "alert"; selects the accent colour
---  * title     - headline string
---  * body      - secondary line. toast and notch only
---  * rows      - list of clickable strings. banner only
---  * duration  - seconds before auto-dismiss. Defaults to defaultDuration for
---                toast and notch; omit on banner to make it sticky
---  * onClick   - fn(row, index) for banner rows
---  * width     - banner width override
---  * yFraction - banner vertical position, 0..1
---
--- Every style returns a handle with :hide() and :update(opts). toast and notch
--- are singletons, so only one of each is on screen at a time and :hide()
--- dismisses whichever is current.

local obj = {}
obj.__index = obj

obj.name = "Notify"
obj.version = "2.0"
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

obj.notchStyle = {
    maxWidth      = 560,
    sideMargin    = 40,     -- how far the panel extends past the notch edges
    bottomRadius  = 22,
    pad           = 14,
    gap           = 12,
    iconSize      = 40,
    dotLane       = 20,     -- right gutter reserved for the accent dot
    expandTime    = 0.34,
    collapseTime  = 0.24,
    fps           = 1 / 60,
    fillColor     = { red = 0.04, green = 0.04, blue = 0.05, alpha = 1 },
}

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

local function focusedAppIcon()
    local win = hs.window.focusedWindow()
    if win and win:application() then
        return hs.image.imageFromAppBundle(win:application():bundleID())
    end
end

-- ---------------------------------------------------------------------------
-- toast: centred, fades in and out
-- ---------------------------------------------------------------------------

local canvas, timer, fadeTimer

local function hideToast()
    if fadeTimer then fadeTimer:stop(); fadeTimer = nil end
    if timer then timer:stop(); timer = nil end
    if canvas then canvas:delete(); canvas = nil end
end

local function showToast(self, o)
    hideToast()

    local theme = self.themes[o.level] or self.themes.info
    local duration = o.duration or self.defaultDuration

    local bgColor    = { red = 0.12, green = 0.12, blue = 0.14, alpha = 0.95 }
    local strokeColor = { red = 0.25, green = 0.25, blue = 0.28, alpha = 0.6 }
    local titleColor = { white = 1, alpha = 0.95 }
    local subColor   = { white = 1, alpha = 0.55 }

    local pad, gap, iconSize = 14, 12, 36
    local titleFont = { name = hs.styledtext.defaultFonts.boldSystem, size = 15 }
    local subFont   = { name = hs.styledtext.defaultFonts.system, size = 13 }

    local styledTitle = hs.styledtext.new(o.title or "", { font = titleFont, color = titleColor })
    local titleDims = hs.drawing.getTextDrawingSize(styledTitle)

    local styledSub, subDims
    if o.body and o.body ~= "" then
        styledSub = hs.styledtext.new(o.body, { font = subFont, color = subColor })
        subDims = hs.drawing.getTextDrawingSize(styledSub)
    end

    local iconImage = focusedAppIcon()

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

    return {
        hide   = function() hideToast() end,
        update = function(_, opts) showToast(self, opts or o) end,
    }
end

-- ---------------------------------------------------------------------------
-- notch: grows out of the top edge of the screen
-- ---------------------------------------------------------------------------

local notchCanvas, notchAnim, notchHold
local notchInsets = {}
local KAPPA = 0.5523 -- bezier constant for a quarter circle

-- The notch is physical hardware: invisible to screencapture, but it hides
-- anything drawn under it. Treat it as a reserved top inset so content always
-- lands below it. NSScreen has the exact geometry; auxiliaryTopLeftArea is the
-- menubar strip left of the notch, so notchWidth = screenWidth - 2 * itsWidth.
-- Both values are zero on notchless screens, where we reserve the menubar
-- instead so the panel does not cover the clock.
local function notchInset(screen)
    local id = screen:getUUID() or "main"
    if notchInsets[id] then return notchInsets[id] end

    local full = screen:fullFrame()
    local out = hs.execute([[osascript -l JavaScript -e '
ObjC.import("AppKit");
var s = $.NSScreen.mainScreen, a = s.auxiliaryTopLeftArea;
JSON.stringify({top: s.safeAreaInsets.top, aux: a.size.width})']])

    local top = tonumber(out:match('"top":([%d%.]+)') or "")
    local aux = tonumber(out:match('"aux":([%d%.]+)') or "")

    local inset
    if top and aux and top > 0 and aux > 0 then
        inset = { h = top, w = full.w - aux * 2 }
    else
        inset = { h = screen:frame().y - full.y, w = 150 }
    end
    notchInsets[id] = inset
    return inset
end

-- ease-out-back overshoots slightly then settles, which reads as a container
-- opening rather than an image being scaled up
local function easeOutBack(t, s)
    s = s or 1.20
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

local function easeInCubic(t) return t * t * t end

-- Square top flush with the screen edge, rounded bottom corners only.
-- roundedRectRadii is uniform across corners, so the silhouette is an
-- explicit path. Note hs.canvas wants flat c1x/c1y/c2x/c2y keys here, not
-- nested point tables.
local function notchPath(x, w, h, r)
    local x1, y1 = x + w, h
    local k = r * KAPPA
    return {
        { x = x,      y = 0 },
        { x = x1,     y = 0 },
        { x = x1,     y = y1 - r },
        { x = x1 - r, y = y1,     c1x = x1,         c1y = y1 - r + k,
                                  c2x = x1 - r + k, c2y = y1 },
        { x = x + r,  y = y1 },
        { x = x,      y = y1 - r, c1x = x + r - k,  c1y = y1,
                                  c2x = x,          c2y = y1 - r + k },
    }
end

-- Measures text and geometry once per notification; the animation only
-- reinterpolates numbers, so no text is re-measured per frame.
local function notchLayout(self, o, inset)
    local st = self.notchStyle
    local theme = self.themes[o.level] or self.themes.info

    local titleSt = hs.styledtext.new(o.title or "", {
        font  = { name = hs.styledtext.defaultFonts.boldSystem, size = 15 },
        color = { white = 1, alpha = 0.96 },
    })
    local titleDims = hs.drawing.getTextDrawingSize(titleSt)

    local subSt, subDims
    if o.body and o.body ~= "" then
        subSt = hs.styledtext.new(o.body, {
            font  = { name = hs.styledtext.defaultFonts.system, size = 13 },
            color = { white = 1, alpha = 0.58 },
        })
        subDims = hs.drawing.getTextDrawingSize(subSt)
    end

    local textW = math.min(self.maxTextWidth,
        math.max(titleDims.w, subDims and subDims.w or 0))
    local contentH = titleDims.h + (subDims and (3 + subDims.h) or 0)
    local rowH = st.pad + math.max(st.iconSize, contentH) + st.pad

    return {
        -- content sits below the notch, so the inset adds to the panel height
        -- rather than eating into it
        w = math.max(inset.w + st.sideMargin, math.min(st.maxWidth,
            st.pad + st.iconSize + st.gap + textW + st.dotLane + st.pad)),
        h = inset.h + rowH,
        titleSt = titleSt, titleDims = titleDims,
        subSt = subSt, subDims = subDims,
        iconImage = focusedAppIcon(),
        contentH = contentH,
        accent = theme.accent,
    }
end

-- The canvas never resizes during animation; the shape drawn inside it does.
-- Resizing the canvas window per frame causes visible jitter and shadow tear.
local function ensureNotchCanvas(self, screen, panelW, panelH)
    local st = self.notchStyle
    local shadowPad = 24
    local needH = panelH + shadowPad
    local full = screen:fullFrame()

    if notchCanvas then
        local size = notchCanvas:size()
        if size.h >= needH and size.w >= panelW then
            notchCanvas:topLeft({ x = full.x + (full.w - size.w) / 2, y = full.y })
            return size.w
        end
        notchCanvas:delete()
        notchCanvas = nil
    end

    local w = math.max(panelW, st.maxWidth)
    notchCanvas = hs.canvas.new({
        x = full.x + (full.w - w) / 2, y = full.y, w = w, h = needH,
    })
    notchCanvas:level(hs.canvas.windowLevels.overlay)
    notchCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                       + hs.canvas.windowBehaviors.stationary)
    return w
end

local function notchRender(self, L, inset, canvasW, p)
    local st = self.notchStyle
    local shape = easeOutBack(clamp01(p))

    -- p=0 is exactly the notch footprint, so the panel appears to grow out of
    -- the hardware instead of appearing beside it
    local w = inset.w + (L.w - inset.w) * shape
    local h = inset.h + (L.h - inset.h) * shape
    local x = (canvasW - w) / 2
    local r = math.min(st.bottomRadius, h / 2, w / 2)

    -- content lags the shape, otherwise the panel reads as a scaling screenshot
    local fade = clamp01((p - 0.45) / 0.45)

    notchCanvas:replaceElements({
        type = "segments",
        action = "fill",
        closed = true,
        coordinates = notchPath(x, w, h, r),
        fillColor = st.fillColor,
        withShadow = true,
        shadow = { blurRadius = 18, offset = { h = -4, w = 0 },
                   color = { alpha = 0.45 } },
    })

    if fade <= 0 then return end

    -- everything is centred in the strip below the notch, never behind it
    local rowH = h - inset.h
    local contentTop = inset.h + (rowH - L.contentH) / 2
    local textX = x + st.pad + st.iconSize + st.gap
    local textW = (x + w - st.pad - st.dotLane) - textX

    if L.iconImage then
        local size = st.iconSize * (0.75 + 0.25 * fade)
        notchCanvas:appendElements({
            type = "image",
            image = L.iconImage,
            imageAlpha = fade,
            imageScaling = "scaleProportionally",
            frame = { x = x + st.pad + (st.iconSize - size) / 2,
                      y = inset.h + (rowH - size) / 2, w = size, h = size },
        })
    end

    notchCanvas:appendElements({
        type = "text",
        text = L.titleSt:setStyle({ color = { white = 1, alpha = 0.96 * fade } }),
        frame = { x = textX, y = contentTop, w = textW, h = L.titleDims.h },
    })

    if L.subSt then
        notchCanvas:appendElements({
            type = "text",
            text = L.subSt:setStyle({ color = { white = 1, alpha = 0.58 * fade } }),
            frame = { x = textX, y = contentTop + L.titleDims.h + 3,
                      w = textW, h = L.subDims.h },
        })
    end

    notchCanvas:appendElements({
        type = "rectangle",
        action = "fill",
        frame = { x = x + w - st.pad - 6, y = inset.h + rowH / 2 - 3, w = 6, h = 6 },
        roundedRectRadii = { xRadius = 3, yRadius = 3 },
        fillColor = { red = L.accent.red, green = L.accent.green,
                      blue = L.accent.blue, alpha = fade },
    })
end

local function notchAnimate(self, L, inset, canvasW, from, to, dur, ease, done)
    local st = self.notchStyle
    if notchAnim then notchAnim:stop() end
    local elapsed = 0
    notchAnim = hs.timer.doEvery(st.fps, function()
        elapsed = elapsed + st.fps
        local t = clamp01(elapsed / dur)
        notchRender(self, L, inset, canvasW, from + (to - from) * (ease and ease(t) or t))
        if t >= 1 then
            notchAnim:stop(); notchAnim = nil
            if done then done() end
        end
    end)
end

local function showNotch(self, o)
    if notchHold then notchHold:stop(); notchHold = nil end
    if notchAnim then notchAnim:stop(); notchAnim = nil end

    local st = self.notchStyle
    local screen = hs.screen.mainScreen()
    local inset = notchInset(screen)
    local L = notchLayout(self, o, inset)
    local canvasW = ensureNotchCanvas(self, screen, L.w, L.h)

    notchRender(self, L, inset, canvasW, 0)
    notchCanvas:show()

    -- collapse is quicker than the open, matching the system animation
    local function collapse()
        notchAnimate(self, L, inset, canvasW, 1, 0, st.collapseTime, easeInCubic,
            function()
                if notchCanvas then notchCanvas:hide() end
            end)
    end

    notchAnimate(self, L, inset, canvasW, 0, 1, st.expandTime, nil, function()
        notchHold = hs.timer.doAfter(o.duration or self.defaultDuration, function()
            notchHold = nil
            collapse()
        end)
    end)

    return {
        hide = function()
            if notchHold then notchHold:stop(); notchHold = nil end
            collapse()
        end,
        update = function(_, opts) showNotch(self, opts or o) end,
    }
end

-- ---------------------------------------------------------------------------
-- banner: draggable row list, sticky unless a duration is given
-- ---------------------------------------------------------------------------

local function showBanner(self, o)
    local handle = { _opts = o, _canvas = nil, _timer = nil }

    local function render(opts)
        local theme = self.themes[opts.level] or self.themes.info
        local pad, lineH = 16, 24
        local title = opts.title or ""
        local rows = opts.rows or {}
        local w = opts.width or 360
        local h = pad * 2 + lineH + (#rows > 0 and (4 + #rows * lineH) or 0)

        local sf = hs.screen.mainScreen():frame()
        local yFrac = opts.yFraction or 0.5
        local x = sf.x + (sf.w - w) / 2
        local y = sf.y + sf.h * yFrac

        if handle._canvas then
            local tl = handle._canvas:topLeft()
            x, y = tl.x, tl.y
            handle._canvas:delete()
        end
        local c = hs.canvas.new({ x = x, y = y, w = w, h = h })
        c:level(hs.canvas.windowLevels.overlay)
        c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                 + hs.canvas.windowBehaviors.stationary)

        c[1] = {
            type = "rectangle",
            id   = "bg",
            trackMouseDown = true,
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
            id        = "title",
            trackMouseDown = true,
            text      = title,
            textColor = theme.accent,
            textSize  = 18,
            textFont  = "Menlo",
            frame     = { x = pad, y = pad, w = w - pad * 2, h = lineH },
        }

        local hlIdx = {}
        for i, row in ipairs(rows) do
            local lineY = pad + lineH + 4 + (i - 1) * lineH
            local hi = #c + 1
            c[hi] = {
                type = "rectangle",
                action = "fill",
                frame = { x = pad - 6, y = lineY - 2, w = w - (pad - 6) * 2, h = lineH + 2 },
                roundedRectRadii = { xRadius = 4, yRadius = 4 },
                fillColor = { white = 1, alpha = 0 },
                strokeWidth = 0,
            }
            hlIdx[i] = hi
            c[#c + 1] = {
                type      = "text",
                id        = "line_" .. i,
                trackMouseDown      = true,
                trackMouseEnterExit = true,
                text      = "  " .. row,
                textColor = { white = 1, alpha = 0.85 },
                textSize  = 16,
                textFont  = "Menlo",
                frame     = { x = pad, y = lineY, w = w - pad * 2, h = lineH },
            }
        end

        local dragTap = nil
        local function startDrag()
            if dragTap then return end
            local origin = c:topLeft()
            local startMouse = hs.mouse.absolutePosition()
            local dx = startMouse.x - origin.x
            local dy = startMouse.y - origin.y
            dragTap = hs.eventtap.new({
                hs.eventtap.event.types.mouseMoved,
                hs.eventtap.event.types.leftMouseDragged,
                hs.eventtap.event.types.leftMouseUp,
            }, function(e)
                local t = e:getType()
                if t == hs.eventtap.event.types.leftMouseUp then
                    if dragTap then dragTap:stop(); dragTap = nil end
                    return false
                end
                local p = hs.mouse.absolutePosition()
                c:topLeft({ x = p.x - dx, y = p.y - dy })
                return false
            end)
            dragTap:start()
        end

        c:mouseCallback(function(_, evt, elemId)
            if type(elemId) ~= "string" then return end
            if elemId == "bg" or elemId == "title" then
                if evt == "mouseDown" then startDrag() end
                return
            end
            local idx = tonumber(elemId:match("^line_(%d+)$"))
            if not idx then return end
            local hi = hlIdx[idx]
            if evt == "mouseEnter" and hi then
                c[hi].fillColor = { white = 1, alpha = 0.12 }
            elseif evt == "mouseExit" and hi then
                c[hi].fillColor = { white = 1, alpha = 0 }
            elseif evt == "mouseDown" and opts.onClick then
                opts.onClick(rows[idx], idx)
            end
        end)

        c:show()
        handle._canvas = c
    end

    function handle:hide()
        if self._timer then self._timer:stop(); self._timer = nil end
        if self._canvas then self._canvas:delete(); self._canvas = nil end
    end

    function handle:update(opts)
        self._opts = opts or self._opts
        render(self._opts)
        if self._timer then self._timer:stop(); self._timer = nil end
        if self._opts.duration then
            self._timer = hs.timer.doAfter(self._opts.duration, function() self:hide() end)
        end
    end

    handle:update(o)
    return handle
end

-- ---------------------------------------------------------------------------

local STYLES = { toast = showToast, notch = showNotch, banner = showBanner }

--- Notify:show(opts) -> handle
--- Method
--- Shows a notification. See the module header for the full option list.
---
--- Parameters:
---  * opts - table of options; `style` selects the presentation
---
--- Returns:
---  * a handle with :hide() and :update(opts)
function obj:show(opts)
    opts = opts or {}
    local render = STYLES[opts.style or "toast"]
    if not render then
        hs.printf("[Notify] unknown style %q; using toast", tostring(opts.style))
        render = STYLES.toast
    end
    return render(self, opts)
end

return obj
