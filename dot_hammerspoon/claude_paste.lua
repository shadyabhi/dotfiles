-- Remap Cmd+V to Ctrl+V in terminal apps when clipboard has an image.
-- This lets you paste images into Claude Code with Cmd+V.

local terminalApps = {
    ["com.apple.Terminal"] = true,
    ["com.googlecode.iterm2"] = true,
    ["dev.warp.Warp-Stable"] = true,
    ["io.alacritty"] = true,
    ["com.mitchellh.ghostty"] = true,
    ["net.kovidgoyal.kitty"] = true,
}

local function clipboardHasImage()
    local types = hs.pasteboard.typesAvailable()
    return types.image
end

local function isFocusedTerminal()
    local app = hs.application.frontmostApplication()
    if not app then return false end
    return terminalApps[app:bundleID()] or false
end

local cmdvTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    local flags = event:getFlags()
    local keyCode = event:getKeyCode()

    -- Cmd+V (keyCode 9 = 'v')
    if keyCode == 9 and flags.cmd and not flags.ctrl and not flags.alt and not flags.shift then
        if isFocusedTerminal() and clipboardHasImage() then
            -- Send Ctrl+V instead
            hs.eventtap.keyStroke({ "ctrl" }, "v", 0)
            return true -- suppress original Cmd+V
        end
    end
    return false
end)

cmdvTap:start()
