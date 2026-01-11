-- Shared mouse utilities

local Mouse = {}

-- highlight mouse with a red circle
function Mouse.highlight()
    local mousepoint = hs.mouse.absolutePosition()
    local mouseCircle = hs.drawing.circle(hs.geometry.rect(mousepoint.x-40, mousepoint.y-40, 80, 80))
    if mouseCircle then
        mouseCircle:setStrokeColor({["red"]=1,["blue"]=0,["green"]=0,["alpha"]=1})
        mouseCircle:setFill(false)
        mouseCircle:setStrokeWidth(5)
        mouseCircle:show()
        hs.timer.doAfter(1, function() mouseCircle:delete() end)
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
