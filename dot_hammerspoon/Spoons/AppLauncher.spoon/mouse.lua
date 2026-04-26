local M = {}

local _circle = nil
local _timer = nil

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
    M.highlight()
end

return M
