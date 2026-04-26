local M = {}

local letterStyle = {
    font  = { name = hs.styledtext.defaultFonts.boldSystem, size = 36 },
    color = { white = 1, alpha = 1 },
}
local titleStyle = {
    font  = { name = hs.styledtext.defaultFonts.system, size = 16 },
    color = { white = 1, alpha = 0.85 },
}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local targets = {}

local function clearTargetBox(target)
    target.box:setFillColor({ white = 0.125, alpha = 0.8 })
    target.box:hide(0.3); hs.timer.doAfter(0.3, function() target.box:delete() end)
    target.letterBg:hide(0.3); hs.timer.doAfter(0.3, function() target.letterBg:delete() end)
    target.text:hide(0.3); hs.timer.doAfter(0.3, function() target.text:delete() end)
    target.title:hide(0.3); hs.timer.doAfter(0.3, function() target.title:delete() end)
    target.app:hide(0.3); hs.timer.doAfter(0.3, function() target.app:delete() end)
end

local binding = hs.hotkey.modal.new({ "alt" }, "tab")
local bindingSwap = hs.hotkey.modal.new({ "alt", "shift" }, "tab")

local spaceWatcher = hs.spaces.watcher.new(function()
    binding:exit()
    spaceWatcher:stop()
end)

binding:bind({}, "escape", nil, function() binding:exit() end)
bindingSwap:bind({}, "escape", nil, function() bindingSwap:exit() end)

binding:bind({ "alt" }, "tab", nil, function() binding:exit() end)
bindingSwap:bind({ "alt", "shift" }, "tab", nil, function() bindingSwap:exit() end)

for i in alphabet:gmatch(".") do
    local letter = i

    binding:bind({}, letter, nil, function()
        local target = targets[letter]
        if target ~= nil then
            target.window:focus()
            target.window:focus()
            local frame = target.window:frame()
            hs.mouse.setAbsolutePosition(hs.geometry.point(
                frame.x + frame.w / 2,
                frame.y + frame.h / 2))
            clearTargetBox(target)
            targets[letter] = nil
            binding:exit()
        end
    end)

    bindingSwap:bind({}, letter, nil, function()
        local last = hs.window.filter.defaultCurrentSpace:getWindows()[1]
        local target = targets[letter]
        if target ~= nil then
            local lastFrame = last:frame()
            local targetFrame = target.window:frame()
            target.window:setFrame(lastFrame)
            last:setFrame(targetFrame)
            target.window:focus()
            target.window:focus()
            local frame = target.window:frame()
            hs.mouse.setAbsolutePosition(hs.geometry.point(
                frame.x + frame.w / 2,
                frame.y + frame.h / 2))
            clearTargetBox(target)
            targets[letter] = nil
            bindingSwap:exit()
        end
    end)
end

local function buildTargets()
    targets = {}
    spaceWatcher:start()

    local filteredWindows = {}
    local windows = hs.window.orderedWindows()
    for _, window in ipairs(windows) do
        if window:isStandard() and window:isVisible() or
            window:id() == window:application():mainWindow():id() then
            filteredWindows[#filteredWindows + 1] = window
        end
    end
    table.sort(filteredWindows, function(a, b)
        local af, bf = a:frame(), b:frame()
        if af.x ~= bf.x then return af.x < bf.x end
        if af.y ~= bf.y then return af.y < bf.y end
        return nil
    end)

    local entries = {}
    for _, window in ipairs(filteredWindows) do
        local title = window:application():title()
        local appName = nil

        for word in title:gmatch("%S+") do
            local letter = word:sub(1, 1):upper()
            if alphabet:find(letter, 1, true) and not targets[letter] then
                appName = letter; break
            end
        end
        if not appName then
            for ch in title:gmatch("%a") do
                local letter = ch:upper()
                if not targets[letter] then appName = letter; break end
            end
        end
        if not appName then
            for ch in alphabet:gmatch(".") do
                if not targets[ch] then appName = ch; break end
            end
        end
        if not appName then break end

        targets[appName] = { window = window }
        entries[#entries + 1] = { letter = appName, window = window, title = title }
    end

    local pad, iconSize, gap = 12, 28, 8
    local rowH, rowGap = 44, 4
    local maxTitleW, letterColW = 300, 36
    local rowW = pad + iconSize + gap + letterColW + gap + maxTitleW + pad

    local screen = hs.screen.mainScreen():frame()
    local totalH = #entries * rowH + (#entries - 1) * rowGap
    local gridX = screen.x + (screen.w - rowW) / 2
    local gridY = screen.y + (screen.h - totalH) / 2

    for idx, entry in ipairs(entries) do
        local t = targets[entry.letter]
        local y = gridY + (idx - 1) * (rowH + rowGap)

        t.box = hs.drawing.rectangle(hs.geometry.rect(gridX, y, rowW, rowH))
        t.box:setLevel("overlay"); t.box:setFillColor({ white = 0.1, alpha = 0.88 })
        t.box:setFill(true); t.box:setStroke(false); t.box:setRoundedRectRadii(8, 8)

        local iconX = gridX + pad
        local iconY = y + (rowH - iconSize) / 2
        t.app = hs.drawing.appImage(
            hs.geometry.rect(iconX, iconY, iconSize, iconSize),
            entry.window:application():bundleID())
        t.app:setLevel("overlay")

        local lbX = iconX + iconSize + gap
        local lbY = y + (rowH - letterColW) / 2
        t.letterBg = hs.drawing.rectangle(hs.geometry.rect(lbX, lbY, letterColW, letterColW))
        t.letterBg:setLevel("overlay"); t.letterBg:setFillColor({ red = 0.2, green = 0.5, blue = 1, alpha = 0.9 })
        t.letterBg:setFill(true); t.letterBg:setStroke(false); t.letterBg:setRoundedRectRadii(6, 6)

        local styledLetter = hs.styledtext.new(entry.letter, letterStyle)
        local letterDims = hs.drawing.getTextDrawingSize(styledLetter)
        local ltX = lbX + (letterColW - letterDims.w) / 2
        local ltY = lbY + (letterColW - letterDims.h) / 2 - 1
        t.text = hs.drawing.text(hs.geometry.rect(ltX, ltY, letterDims.w + 4, letterDims.h), styledLetter)
        t.text:setLevel("overlay")

        local displayTitle = entry.window:application():title()
        if #displayTitle > 40 then displayTitle = displayTitle:sub(1, 38) .. ".." end
        local styledTitle = hs.styledtext.new(displayTitle, titleStyle)
        local titleDims = hs.drawing.getTextDrawingSize(styledTitle)
        local ttX = lbX + letterColW + gap
        local ttY = y + (rowH - titleDims.h) / 2
        t.title = hs.drawing.text(hs.geometry.rect(ttX, ttY, maxTitleW, titleDims.h), styledTitle)
        t.title:setLevel("overlay")

        t.box:show(); t.app:show(); t.letterBg:show(); t.text:show(); t.title:show()
    end

    return targets
end

local function clearTargets()
    for k in pairs(targets) do
        targets[k].box:delete(); targets[k].letterBg:delete()
        targets[k].text:delete(); targets[k].title:delete(); targets[k].app:delete()
    end
    targets = {}
end

binding.entered = buildTargets
binding.exited = clearTargets
bindingSwap.entered = buildTargets
bindingSwap.exited = clearTargets

function M.bind(_) end -- modal hotkeys self-register on require

return M
