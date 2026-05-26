--- === AppLauncher ===
---
--- App launcher with multi-window chooser + mouse utilities.
--- Usage:
---   spoon.AppLauncher:setApps({ {"j","Emdash Beta"}, ... })
---       :bindHotkeys({ launchPrefix="h", chooserPrefix="hs" })

local obj = {}
obj.__index = obj

obj.name = "AppLauncher"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

obj.mouse = dofile(hs.spoons.resourcePath("mouse.lua"))

local HOME = os.getenv("HOME")

obj.apps = {}
obj.searchPaths = {
    "/Applications",
    HOME .. "/Applications/Edge Apps.localized",
    "/System/Library/CoreServices",
    "/System/Applications",
    HOME .. "/Applications/Chrome Apps.localized",
    HOME .. "/Applications/Chrome Apps",
    HOME .. "/Applications/Edge Apps",
}

obj.hyperkey = nil
obj.launchPrefix  = "h"
obj.chooserPrefix = "hs"

local chooserLog = hs.logger.new("AppLauncher", "info")

local function file_exists(path)
    local f = io.open(path, "r")
    if f then io.close(f); return true end
    return false
end

local function activeScreen()
    local fw = hs.window.focusedWindow()
    return (fw and fw:screen()) or hs.screen.mainScreen()
end

local function windowsOnActiveScreen(app)
    local screenId = activeScreen():getUUID()
    local windows = app and app:allWindows() or {}
    return hs.fnutils.filter(windows, function(w)
        if not (w:isStandard() and w:id() ~= nil) then return false end
        local s = w:screen()
        return s and s:getUUID() == screenId
    end)
end

local function launchAndCenter(self, path)
    hs.application.launchOrFocus(path)
    hs.timer.doAfter(0.3, function() self.mouse.toCenter() end)
end

local lastPress = {}
local DOUBLE_PRESS_WINDOW = 0.6

local function launchApp(self, name)
    return function()
        local app = hs.application.find(name)
        local now = hs.timer.secondsSinceEpoch()
        local prev = lastPress[name]
        lastPress[name] = now
        if app then
            local windows = windowsOnActiveScreen(app)
            -- Stable order so successive presses cycle deterministically.
            table.sort(windows, function(a, b) return a:id() < b:id() end)
            if #windows > 0 then
                local focused = hs.window.focusedWindow()
                local curId = focused and focused:id()
                if #windows == 1 and curId == windows[1]:id()
                    and prev and (now - prev) <= DOUBLE_PRESS_WINDOW then
                    local win = windows[1]
                    local screen = win:screen()
                    local g = hs.grid.getGrid(screen)
                    hs.grid.set(win, { x = math.floor(g.w / 2), y = 0, w = 1, h = 1 }, screen)
                    hs.timer.doAfter(0.15, function() self.mouse.toCenter() end)
                    return
                end
                local idx = 0
                for i, w in ipairs(windows) do
                    if w:id() == curId then idx = i; break end
                end
                local next = windows[(idx % #windows) + 1]
                next:focus()
                hs.timer.doAfter(0.15, function() self.mouse.toCenter() end)
                return
            end
        end
        for _, base in ipairs(self.searchPaths) do
            local path = base .. "/" .. name .. ".app"
            if file_exists(path) then
                launchAndCenter(self, path)
                return
            end
        end
    end
end

local function launchAppChooser(self, name)
    return function()
        local app = hs.application.find(name)
        local windows = windowsOnActiveScreen(app)

        if #windows == 0 then launchApp(self, name)(); return end
        if #windows == 1 then
            windows[1]:focus()
            hs.timer.doAfter(0.15, function() self.mouse.toCenter() end)
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
            local pad, labelH = 24, 32
            local maxW, maxH = screen.w * 0.9, screen.h * 0.9
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
                return pad + col * (cellW + pad), pad + row * (cellH + labelH + pad)
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
                    hs.timer.doAfter(0.15, function() self.mouse.toCenter() end)
                end
            end

            modal:bind({}, "escape", function() cleanup() end)
            modal:bind({}, "return", function() pick(selected) end)
            modal:bind({}, "space", function() pick(selected) end)
            modal:bind({}, "right", function() selected = selected % n + 1; render() end)
            modal:bind({}, "left", function() selected = (selected - 2) % n + 1; render() end)
            modal:bind({}, "down", function()
                local nxt = selected + cols
                if nxt > n then nxt = ((selected - 1) % cols) + 1 end
                selected = nxt; render()
            end)
            modal:bind({}, "up", function()
                local nxt = selected - cols
                if nxt < 1 then
                    nxt = selected + cols * (rows_n - 1)
                    while nxt > n do nxt = nxt - cols end
                end
                selected = nxt; render()
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
                function(exitCode, _, stdErr)
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
                { "-l" .. w:id(), "-x", path }
            ):start()
        end
    end
end

function obj:setApps(list)
    self.apps = list
    return self
end

function obj:bindHotkeys(opts)
    opts = opts or {}
    if opts.launchPrefix then self.launchPrefix = opts.launchPrefix end
    if opts.chooserPrefix then self.chooserPrefix = opts.chooserPrefix end
    if not self.hyperkey then error("AppLauncher requires .hyperkey to be set before bindHotkeys") end
    for _, s in ipairs(self.apps) do
        local key, name = s[1], s[2]
        self.hyperkey:bind(self.launchPrefix,  key, launchApp(self, name))
        self.hyperkey:bind(self.chooserPrefix, key, launchAppChooser(self, name))
    end
    return self
end

return obj
