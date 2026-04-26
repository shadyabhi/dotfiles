local M = {}

local function moveWindow(win, x, y, w, h)
    if not win then return end
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()
    f.x = max.x + (max.w * x)
    f.y = max.y + (max.h * y)
    f.w = max.w * w
    f.h = max.h * h
    win:setFrame(f)
end

local function resizeWidth(delta)
    local win = hs.window.focusedWindow()
    if not win then return end
    local f = win:frame()
    local max = win:screen():frame()
    local step = max.w * 0.1
    local change = step * delta
    f.w = f.w + change
    f.x = f.x - (change / 2)
    if f.w < max.w * 0.1 then f.w = max.w * 0.1 end
    if f.w > max.w then f.w = max.w end
    if f.x < max.x then f.x = max.x end
    if f.x + f.w > max.x + max.w then f.x = max.x + max.w - f.w end
    win:setFrame(f)
end

function M.bind(parent)
    hs.window.animationDuration = 0

    if parent.notifyFn then
        hs.window.filter.default:subscribe(hs.window.filter.windowFocused, function(window)
            local app = window:application()
            local appTitle = app and app:title() or ""
            local winTitle = window:title() or ""
            parent.notifyFn(appTitle, winTitle, 0.2)
        end)
    end

    local hk = parent.hyperkey
    hk:bind("hca", "=", function() resizeWidth(1) end)
    hk:bind("hca", "-", function() resizeWidth(-1) end)
    hk:bind("hca", "1", function() moveWindow(hs.window.focusedWindow(), 0,   0, 1/3, 1) end)
    hk:bind("hca", "2", function() moveWindow(hs.window.focusedWindow(), 1/3, 0, 1/3, 1) end)
    hk:bind("hca", "3", function() moveWindow(hs.window.focusedWindow(), 2/3, 0, 1/3, 1) end)
    hk:bind("hca", "4", function() moveWindow(hs.window.focusedWindow(), 0,   0, 2/3, 1) end)
    hk:bind("hca", "5", function() moveWindow(hs.window.focusedWindow(), 1/3, 0, 2/3, 1) end)
    hk:bind("hca", "9", function() moveWindow(hs.window.focusedWindow(), 1/5, 0, 3/5, 1) end)
    hk:bind("hca", "0", function() moveWindow(hs.window.focusedWindow(), 1/5, 0, 3/5, 2/3) end)
end

return M
