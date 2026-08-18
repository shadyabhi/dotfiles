local M = {}

local _circle = nil
local _timer = nil

--- Per-window pointer memory.
--- Stored as an offset from the window's top-left so a moved window still
--- restores the pointer to the same spot *inside* the window. Entries are
--- dropped when their window is destroyed.
local positions = {}   -- [windowId] = { dx = <number>, dy = <number> }
local tracker = nil

local function pointInFrame(p, f)
    return p.x >= f.x and p.x <= f.x + f.w
       and p.y >= f.y and p.y <= f.y + f.h
end

function M.highlight()
    if _timer then _timer:stop() end
    if _circle then _circle:delete() end

    local mp = hs.mouse.absolutePosition()
    _circle = hs.drawing.circle(hs.geometry.rect(mp.x - 40, mp.y - 40, 80, 80))
    if _circle then
        _circle:setStrokeColor({ red = 1, blue = 0, green = 0, alpha = 1 })
        _circle:setFill(false)
        _circle:setStrokeWidth(5)
        _circle:show()
        _timer = hs.timer.doAfter(1, function()
            if _circle then _circle:delete(); _circle = nil end
            _timer = nil
        end)
    end
end

function M.toCenter(win)
    win = win or hs.window.focusedWindow()
    if not win then return end
    local f = win:frame()
    hs.mouse.absolutePosition({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
end

--- Remember where the pointer is inside `win` (defaults to the focused window).
--- No-op when the pointer is already outside the window — that means focus was
--- given away by clicking elsewhere, so the current point says nothing about
--- where the user was working in `win`.
function M.save(win)
    win = win or hs.window.focusedWindow()
    if not win then return end
    local id = win:id()
    if not id then return end
    local f = win:frame()
    local p = hs.mouse.absolutePosition()
    if not pointInFrame(p, f) then return end
    positions[id] = { dx = p.x - f.x, dy = p.y - f.y }
end

--- Put the pointer back where it was in `win`, falling back to the window
--- centre when nothing is remembered or the remembered spot no longer fits
--- (window resized smaller, or window is new).
function M.restore(win)
    win = win or hs.window.focusedWindow()
    if not win then return end
    local id = win:id()
    local saved = id and positions[id]
    if not saved then return M.toCenter(win) end

    local f = win:frame()
    if saved.dx < 0 or saved.dy < 0 or saved.dx > f.w or saved.dy > f.h then
        return M.toCenter(win)
    end
    hs.mouse.absolutePosition({ x = f.x + saved.dx, y = f.y + saved.dy })
end

function M.forget(win)
    local id = win and win:id()
    if id then positions[id] = nil end
end

--- Keep the memory current for switches that don't go through AppLauncher
--- (clicking a window, Alt-Tab, Mission Control): record on unfocus, and drop
--- entries for windows that go away.
function M.startTracking()
    if tracker then return M end
    tracker = hs.window.filter.default
    tracker:subscribe(hs.window.filter.windowUnfocused, function(win) M.save(win) end)
    tracker:subscribe(hs.window.filter.windowDestroyed, function(win) M.forget(win) end)
    return M
end

return M
