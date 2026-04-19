--[[
    Creates shortcuts related to launching apps via shortcuts
]]

local Mouse = require("mouse")

local HOME = os.getenv("HOME")

-- Helper functions
function file_exists(path)
    local f=io.open(path,"r")
    if f~=nil then io.close(f) return true else return false end
    -- ~= is != in other languages
end

local function launchAndCenter(path)
    hs.application.launchOrFocus(path)
    hs.timer.doAfter(0.3, function() Mouse.toCenter() end)
end

local function launchApp(name)
    return function()
        local path = "/Applications/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end
        local path = HOME .. "/Applications/Edge Apps.localized/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end
        local path = "/System/Library/CoreServices/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end
        local path = "/System/Applications/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = "/System/Applications/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = HOME .. "/Applications/Chrome Apps.localized/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = HOME .. "/Applications/Chrome Apps/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = HOME .. "/Applications/Edge Apps.localized/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end

        local path = HOME .. "/Applications/Edge Apps/" .. name .. ".app"
        if file_exists(path) then
            launchAndCenter(path)
            return
        end
    end
end

local chooserLog = hs.logger.new("launchChooser", "info")

local function launchAppChooser(name)
    return function()
        local app = hs.application.find(name)
        local windows = app and app:allWindows() or {}
        windows = hs.fnutils.filter(windows, function(w)
            return w:isStandard() and w:id() ~= nil
        end)

        if #windows == 0 then launchApp(name)(); return end
        if #windows == 1 then
            windows[1]:focus()
            hs.timer.doAfter(0.15, function() Mouse.toCenter() end)
            return
        end

        local tmpDir = hs.fs.temporaryDirectory() .. "hs_winshots_" .. os.time() .. "_" .. math.random(10000)
        hs.fs.mkdir(tmpDir)
        local paths, images, remaining = {}, {}, #windows

        local function showChooser()
            local screen = hs.screen.mainScreen():frame()
            local n = #windows
            local cols = math.min(n, math.max(1, math.floor(math.sqrt(n) + 0.5)))
            if n <= 2 then cols = n end
            if n == 3 then cols = 3 end
            if n >= 4 and n <= 6 then cols = 3 end
            if n >= 7 then cols = 4 end
            local rows_n = math.ceil(n / cols)
            local pad = 24
            local labelH = 32
            local maxW = screen.w * 0.9
            local maxH = screen.h * 0.9
            local cellW = math.floor((maxW - (cols + 1) * pad) / cols)
            local cellH = math.floor((maxH - (rows_n + 1) * pad - rows_n * labelH) / rows_n)
            if cellW > 640 then cellW = 640 end
            if cellH > 400 then cellH = 400 end
            local canvasW = cols * cellW + (cols + 1) * pad
            local canvasH = rows_n * (cellH + labelH) + (rows_n + 1) * pad
            local cx0 = screen.x + (screen.w - canvasW) / 2
            local cy0 = screen.y + (screen.h - canvasH) / 2

            local canvas = hs.canvas.new({ x = cx0, y = cy0, w = canvasW, h = canvasH })
            canvas:level("overlay")
            local selected = 1
            local appIcon = hs.image.imageFromAppBundle(app:bundleID())

            local function cellRect(i)
                local col = (i - 1) % cols
                local row = math.floor((i - 1) / cols)
                local x = pad + col * (cellW + pad)
                local y = pad + row * (cellH + labelH + pad)
                return x, y
            end

            local function render()
                local els = {
                    {
                        type = "rectangle", action = "fill",
                        fillColor = { black = 0, alpha = 0.82 },
                        roundedRectRadii = { xRadius = 16, yRadius = 16 },
                        frame = { x = 0, y = 0, w = canvasW, h = canvasH },
                    },
                }
                for i, w in ipairs(windows) do
                    local x, y = cellRect(i)
                    local isSel = (i == selected)
                    table.insert(els, {
                        type = "rectangle", action = "strokeAndFill",
                        strokeColor = isSel and { red = 0.3, green = 0.7, blue = 1, alpha = 1 } or { white = 1, alpha = 0.15 },
                        strokeWidth = isSel and 4 or 1,
                        fillColor = { white = 0.1, alpha = 1 },
                        roundedRectRadii = { xRadius = 8, yRadius = 8 },
                        frame = { x = x - 2, y = y - 2, w = cellW + 4, h = cellH + 4 },
                    })
                    table.insert(els, {
                        type = "image",
                        image = images[i] or appIcon,
                        imageScaling = "scaleProportionally",
                        frame = { x = x, y = y, w = cellW, h = cellH },
                    })
                    local title = w:title()
                    if title == "" then title = "Window " .. w:id() end
                    if #title > 80 then title = title:sub(1, 77) .. "..." end
                    table.insert(els, {
                        type = "text",
                        text = string.format("%d. %s", i, title),
                        textColor = { white = 1 },
                        textSize = 14,
                        textAlignment = "center",
                        frame = { x = x, y = y + cellH + 4, w = cellW, h = labelH - 4 },
                    })
                end
                canvas:replaceElements(els)
            end

            local modal = hs.hotkey.modal.new()
            local function cleanup()
                modal:exit()
                canvas:delete()
                for _, p in pairs(paths) do os.remove(p) end
                hs.fs.rmdir(tmpDir)
            end
            local function pick(idx)
                local w = windows[idx]
                cleanup()
                if w then
                    w:focus()
                    hs.timer.doAfter(0.15, function() Mouse.toCenter() end)
                end
            end

            modal:bind({}, "escape", function() cleanup() end)
            modal:bind({}, "return", function() pick(selected) end)
            modal:bind({}, "space", function() pick(selected) end)
            modal:bind({}, "right", function() selected = selected % n + 1; render() end)
            modal:bind({}, "left", function() selected = (selected - 2) % n + 1; render() end)
            modal:bind({}, "down", function()
                local next = selected + cols
                if next > n then next = ((selected - 1) % cols) + 1 end
                selected = next; render()
            end)
            modal:bind({}, "up", function()
                local next = selected - cols
                if next < 1 then
                    next = selected + cols * (rows_n - 1)
                    while next > n do next = next - cols end
                end
                selected = next; render()
            end)
            modal:bind({}, "tab", function() selected = selected % n + 1; render() end)
            modal:bind({ "shift" }, "tab", function() selected = (selected - 2) % n + 1; render() end)
            for i = 1, math.min(n, 9) do
                modal:bind({}, tostring(i), function() pick(i) end)
            end

            render()
            canvas:show()
            modal:enter()
        end

        for i, w in ipairs(windows) do
            local path = tmpDir .. "/win_" .. w:id() .. ".png"
            paths[i] = path
            hs.task.new("/usr/sbin/screencapture",
                function(exitCode, stdOut, stdErr)
                    local attr = hs.fs.attributes(path)
                    chooserLog.f("win %s exit=%s size=%s stderr=%q",
                        w:id(), tostring(exitCode), attr and attr.size or "nil", stdErr or "")
                    local img = hs.image.imageFromPath(path)
                    if not img then
                        chooserLog.f("imageFromPath nil for %s; trying window:snapshot()", path)
                        img = w:snapshot()
                    end
                    images[i] = img
                    remaining = remaining - 1
                    if remaining == 0 then showChooser() end
                end,
                {"-l" .. w:id(), "-x", path}
            ):start()
        end
    end
end

-- Shortcuts
local shortcuts = {
    { "j", "Emdash Beta" },
    { "b", "Google Chrome" },
    { "c", "Google Calendar" },
    { "e", "Microsoft Edge" },
    { "g", "Gmail" },
    { "r", "Reclaim" },
    { "s", "Slack" },
    { "t", "iTerm" },
    { "m", "Google Meet" },
    { "w", "Obsidian" },
}

for _, s in ipairs(shortcuts) do
    local key, name = s[1], s[2]
    h_bind(key, launchApp(name))
    hs_bind(key, launchAppChooser(name))
end
