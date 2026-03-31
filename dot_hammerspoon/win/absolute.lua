local logger = hs.logger.new('win_absolute','info')
local Mouse = require("mouse")
local notify = require("notify")

-- Notifications every time a window is changed (helpful for tiling window manager)
hs.window.filter.default:subscribe(hs.window.filter.windowFocused, function(window, appName)
    local app = window:application()
    local appTitle = app and app:title() or ""
    local winTitle = window:title() or ""
    notify.info(appTitle, winTitle, 0.2)
end)

-- vars for window management
hs.window.animationDuration=0


-- Resize window for chunk of screen.
-- For x and y: use 0 to expand fully in that dimension, 0.5 to expand halfway
-- For w and h: use 1 for full, 0.5 for half
local function moveWindow(win, x, y, w, h)
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()

    f.x = max.x + (max.w*x)
    f.y = max.y + (max.h*y)
    f.w = max.w*w
    f.h = max.h*h
    win:setFrame(f)

    Mouse.highlight()
end

-- Resize window width (from both sides)
local function resizeWidth(delta)
    local win = hs.window.focusedWindow()
    if not win then return end
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()

    local step = max.w * 0.1  -- 10% of screen width
    local change = step * delta
    f.w = f.w + change
    f.x = f.x - (change / 2)  -- Adjust x to grow/shrink from center

    -- Keep within screen bounds
    if f.w < max.w * 0.1 then f.w = max.w * 0.1 end
    if f.w > max.w then f.w = max.w end
    if f.x < max.x then f.x = max.x end
    if f.x + f.w > max.x + max.w then f.x = max.x + max.w - f.w end

    win:setFrame(f)
    Mouse.highlight()
end

hca_bind("=", function() resizeWidth(1) end)   -- + key (= is unshifted +)
hca_bind("-", function() resizeWidth(-1) end)

-- 3x2 is most used grid
-- Three columns, full height
hca_bind("1", function() moveWindow(hs.window.focusedWindow(), 0, 0, 1/3, 1) end)
hca_bind("2", function() moveWindow(hs.window.focusedWindow(), 1/3, 0, 1/3, 1) end)
hca_bind("3", function() moveWindow(hs.window.focusedWindow(), 2/3, 0, 1/3, 1) end)

-- Double the width window
hca_bind("4", function() moveWindow(hs.window.focusedWindow(), 0, 0, 2/3, 1) end)
hca_bind("5", function() moveWindow(hs.window.focusedWindow(), 1/3, 0, 2/3, 1) end)

-- Huge window, main, no column sizing
hca_bind("9", function() moveWindow(hs.window.focusedWindow(), 1/5, 0, 3/5, 1) end)
-- Webcam position
hca_bind("0", function() moveWindow(hs.window.focusedWindow(), 1/5, 0, 3/5, 2/3) end)

-- Move mouse to center of focused window
-- h_bind("m", function() Mouse.toCenter() end)
