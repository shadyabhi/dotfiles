--- === CenterNativeNotifications ===
---
--- Move macOS notification banners to the middle of the screen.
--- Port of NotWadeGrimridge/PingPlace using hs.axuielement.
--- Usage: hs.loadSpoon("CenterNativeNotifications"); spoon.CenterNativeNotifications:start()

local obj = {}
obj.__index = obj

obj.name = "CenterNativeNotifications"
obj.version = "1.0"
obj.author = "Abhijeet Rastogi"
obj.license = "MIT"

local NC_BUNDLE_ID = "com.apple.notificationcenterui"
local BANNER_SUBROLES = {
    AXNotificationCenterBanner = true,
    AXNotificationCenterAlert = true,
    AXNotificationCenterNotification = true,
    AXNotificationCenterBannerWindow = true,
}
local WIDGET_EDITOR_ID = "widget-editor-button"
local MAX_DEPTH = 20

obj.app = nil
obj.appElement = nil
obj.observer = nil
obj.appWatcher = nil
obj.screenWatcher = nil
obj.watchedWindowKeys = {}
obj.originalOrigins = {}

--- CenterNativeNotifications.followMouse
--- Variable
--- When true, banners are centered on the screen containing the mouse cursor.
--- When false, banners are centered on the screen they currently appear on.
obj.followMouse = true

local function safeAttr(el, name)
    if not el then return nil end
    local ok, v = pcall(function() return el:attributeValue(name) end)
    if ok then return v end
    return nil
end

local function children(el)
    local direct = safeAttr(el, "AXChildren") or {}
    local ordered = safeAttr(el, "AXOrderedChildren") or {}
    if #ordered == 0 then return direct end
    local seen, out = {}, {}
    for _, list in ipairs({ direct, ordered }) do
        for _, c in ipairs(list) do
            local id = tostring(c)
            if not seen[id] then
                seen[id] = true
                out[#out + 1] = c
            end
        end
    end
    return out
end

local function findDescendant(el, predicate, depth)
    depth = depth or 0
    if not el or depth > MAX_DEPTH then return nil end
    if predicate(el) then return el end
    for _, c in ipairs(children(el)) do
        local m = findDescendant(c, predicate, depth + 1)
        if m then return m end
    end
    return nil
end

local function findBanner(win)
    return findDescendant(win, function(el)
        local sub = safeAttr(el, "AXSubrole")
        return sub and BANNER_SUBROLES[sub] or false
    end)
end

local function ncPanelOpen(win)
    return findDescendant(win, function(el)
        return safeAttr(el, "AXIdentifier") == WIDGET_EDITOR_ID
    end) ~= nil
end

local function screenForCenter(cx, cy)
    for _, s in ipairs(hs.screen.allScreens()) do
        local f = s:frame()
        if cx >= f.x and cx < f.x + f.w and cy >= f.y and cy < f.y + f.h then
            return s
        end
    end
    return hs.screen.mainScreen()
end

local function windowKey(win)
    local pos = safeAttr(win, "AXPosition") or { x = 0, y = 0 }
    local sz = safeAttr(win, "AXSize") or { w = 0, h = 0 }
    return string.format("%.0f|%.0f|%.0f|%.0f", pos.x, pos.y, sz.w, sz.h)
end

function obj:moveWindow(win)
    if not win then return end

    if ncPanelOpen(win) then
        self:restoreWindow(win)
        return
    end

    local banner = findBanner(win)
    if not banner then
        self:restoreWindow(win)
        return
    end

    local bPos = safeAttr(banner, "AXPosition")
    local bSize = safeAttr(banner, "AXSize")
    local wPos = safeAttr(win, "AXPosition")
    if not (bPos and bSize and wPos) then return end

    local screen
    if self.followMouse then
        screen = hs.mouse.getCurrentScreen() or screenForCenter(bPos.x + bSize.w / 2, bPos.y + bSize.h / 2)
    else
        screen = screenForCenter(bPos.x + bSize.w / 2, bPos.y + bSize.h / 2)
    end
    local sf = screen:frame()
    local desiredX = sf.x + (sf.w - bSize.w) / 2
    local desiredY = sf.y + (sf.h - bSize.h) / 2

    local key = tostring(win)
    if not self.originalOrigins[key] then
        self.originalOrigins[key] = { x = wPos.x, y = wPos.y, win = win }
    end

    local newWin = {
        x = wPos.x + (desiredX - bPos.x),
        y = wPos.y + (desiredY - bPos.y),
    }

    if math.abs(newWin.x - wPos.x) < 0.5 and math.abs(newWin.y - wPos.y) < 0.5 then
        return
    end

    pcall(function() win:setAttributeValue("AXPosition", newWin) end)
end

function obj:restoreWindow(win)
    local key = tostring(win)
    local orig = self.originalOrigins[key]
    if not orig then return end
    pcall(function() win:setAttributeValue("AXPosition", { x = orig.x, y = orig.y }) end)
    self.originalOrigins[key] = nil
end

function obj:moveAll()
    if not self.appElement then return end
    local wins = safeAttr(self.appElement, "AXWindows") or {}
    for _, w in ipairs(wins) do self:moveWindow(w) end
end

function obj:refreshWindowWatchers()
    if not (self.observer and self.appElement) then return end
    local wins = safeAttr(self.appElement, "AXWindows") or {}
    for _, w in ipairs(wins) do
        local key = windowKey(w)
        if not self.watchedWindowKeys[key] then
            self.watchedWindowKeys[key] = true
            pcall(function() self.observer:addWatcher(w, "AXChildrenChanged") end)
            pcall(function() self.observer:addWatcher(w, "AXCreated") end)
            pcall(function() self.observer:addWatcher(w, "AXUIElementDestroyed") end)
        end
    end
end

function obj:setupObserver()
    local apps = hs.application.applicationsForBundleID(NC_BUNDLE_ID)
    if #apps == 0 then return false end

    self.app = apps[1]
    self.appElement = hs.axuielement.applicationElement(self.app)
    if not self.appElement then return false end

    local obs = hs.axuielement.observer.new(self.app:pid())
    if not obs then return false end
    self.observer = obs

    obs:callback(function()
        self:refreshWindowWatchers()
        self:moveAll()
    end)

    pcall(function() obs:addWatcher(self.appElement, "AXWindowCreated") end)
    pcall(function() obs:addWatcher(self.appElement, "AXChildrenChanged") end)
    obs:start()

    self:refreshWindowWatchers()
    self:moveAll()
    return true
end

function obj:teardownObserver()
    if self.observer then
        pcall(function() self.observer:stop() end)
        self.observer = nil
    end
    self.app = nil
    self.appElement = nil
    self.watchedWindowKeys = {}
    self.originalOrigins = {}
end

function obj:start()
    if not hs.axuielement then
        hs.printf("[PingPlace] hs.axuielement unavailable")
        return self
    end
    if not hs.accessibilityState() then
        hs.printf("[PingPlace] Accessibility not granted to Hammerspoon")
        return self
    end

    self:setupObserver()

    self.appWatcher = hs.application.watcher.new(function(_, ev, app)
        if not app or app:bundleID() ~= NC_BUNDLE_ID then return end
        if ev == hs.application.watcher.launched then
            self:setupObserver()
        elseif ev == hs.application.watcher.terminated then
            self:teardownObserver()
        end
    end)
    self.appWatcher:start()

    self.screenWatcher = hs.screen.watcher.new(function()
        self:teardownObserver()
        self:setupObserver()
    end)
    self.screenWatcher:start()

    return self
end

function obj:stop()
    self:teardownObserver()
    if self.appWatcher then
        self.appWatcher:stop()
        self.appWatcher = nil
    end
    if self.screenWatcher then
        self.screenWatcher:stop()
        self.screenWatcher = nil
    end
    return self
end

return obj
