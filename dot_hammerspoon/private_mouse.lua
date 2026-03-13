-- Shared mouse utilities

local Mouse = {}

local _circle = nil
local _timer = nil

-- highlight mouse with a red circle
function Mouse.highlight()
    -- Clean up previous highlight
    if _timer then _timer:stop() end
    if _circle then _circle:delete() end

    local mousepoint = hs.mouse.absolutePosition()
    _circle = hs.drawing.circle(hs.geometry.rect(mousepoint.x-40, mousepoint.y-40, 80, 80))
    if _circle then
        _circle:setStrokeColor({["red"]=1,["blue"]=0,["green"]=0,["alpha"]=1})
        _circle:setFill(false)
        _circle:setStrokeWidth(5)
        _circle:show()
        _timer = hs.timer.doAfter(1, function()
            if _circle then _circle:delete(); _circle = nil end
            _timer = nil
        end)
    end
end

-- Move mouse to center of focused window and highlight
function Mouse.toCenter()
    local win = hs.window.focusedWindow()
    if not win then return end
    local f = win:frame()
    local center = {
        x = f.x + (f.w / 2),
        y = f.y + (f.h / 2)
    }
    hs.mouse.absolutePosition(center)
    Mouse.highlight()
end

return Mouse
