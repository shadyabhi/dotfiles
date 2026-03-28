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
    local ok, types = pcall(hs.pasteboard.typesAvailable)
    if not ok or not types then return false end
    return types.image
end

local function isFocusedTerminal()
    local ok, app = pcall(hs.application.frontmostApplication)
    if not ok or not app then return false end
    local ok2, bid = pcall(function() return app:bundleID() end)
    if not ok2 or not bid then return false end
    return terminalApps[bid] or false
end

-- Track whether we remapped the last keyDown so we can suppress the matching keyUp
local suppressNextKeyUp = false

local cmdvTap = hs.eventtap.new(
    { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp },
    function(event)
        local ok, result, events = pcall(function()
            local flags = event:getFlags()
            local keyCode = event:getKeyCode()
            local eventType = event:getType()

            if keyCode ~= 9 then return false end -- only care about 'v'

            -- Handle keyUp: suppress the orphaned V key-up from the original Cmd+V
            if eventType == hs.eventtap.event.types.keyUp then
                if suppressNextKeyUp then
                    suppressNextKeyUp = false
                    return true -- suppress it
                end
                return false
            end

            -- Handle keyDown: Cmd+V (keyCode 9 = 'v')
            if flags.cmd and not flags.ctrl and not flags.alt and not flags.shift then
                if isFocusedTerminal() and clipboardHasImage() then
                    suppressNextKeyUp = true
                    -- Replace with Ctrl+V down+up, explicit flags to override physical Cmd
                    local ctrlDown = hs.eventtap.event.newKeyEvent({"ctrl"}, "v", true)
                    local ctrlUp   = hs.eventtap.event.newKeyEvent({"ctrl"}, "v", false)
                    ctrlDown:setFlags({ ctrl = true })
                    ctrlUp:setFlags({ ctrl = true })
                    return true, { ctrlDown, ctrlUp }
                end
            end
            return false
        end)

        if ok then
            return result, events
        else
            print("[claude_paste] eventtap callback error: " .. tostring(result))
            return false
        end
    end
)

cmdvTap:start()

-- Force-restart the eventtap to recover from zombie state (enabled but not receiving events)
local function restartTap(reason)
    print("[claude_paste] restarting eventtap: " .. reason)
    cmdvTap:stop()
    cmdvTap:start()
end

-- Periodically force-restart to recover from zombie taps (isEnabled stays true but events stop)
local watchdog = hs.timer.new(30, function()
    restartTap("periodic refresh")
end)
watchdog:start()

-- Also restart on wake from sleep, which commonly kills eventtaps
local caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
        hs.timer.doAfter(2, function()
            restartTap("wake from sleep")
        end)
    end
end)
caffeinateWatcher:start()
