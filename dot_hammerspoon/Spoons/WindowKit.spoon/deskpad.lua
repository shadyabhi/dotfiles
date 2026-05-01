-- DeskPad integration.
--
-- Goal: keep DeskPad windows out of the way of WindowKit's move/resize
-- shortcuts. True cross-app always-on-top isn't achievable from Hammerspoon
-- on modern macOS (CGSSetWindowLevel silently no-ops across processes under
-- SIP). For real always-on-top, install Topit (`brew install --cask topit`)
-- which uses ScreenCaptureKit to overlay a mirror of the target window.

local M = {}

M.appName = "DeskPad"

local function isDeskpadWindow(win)
    if not win then return false end
    local app = win:application()
    if not app then return false end
    local name = app:name() or ""
    return name:lower() == M.appName:lower()
end

local function patchSetFrame()
    if M._origSetFrame then return end
    local mt = hs.getObjectMetatable("hs.window")
    M._origSetFrame = mt.setFrame
    mt.setFrame = function(self, ...)
        if isDeskpadWindow(self) then return self end
        return M._origSetFrame(self, ...)
    end
end

local function unpatchSetFrame()
    if not M._origSetFrame then return end
    local mt = hs.getObjectMetatable("hs.window")
    mt.setFrame = M._origSetFrame
    M._origSetFrame = nil
end

function M.start(_parent)
    patchSetFrame()
    return M
end

function M.stop()
    unpatchSetFrame()
end

return M
