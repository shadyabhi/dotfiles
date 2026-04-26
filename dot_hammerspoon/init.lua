-- Auto-install and load upstream spoons
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall:andUse("EmmyLua")
spoon.SpoonInstall:andUse("ReloadConfiguration", { start = true })

-- Local spoons
hs.loadSpoon("Notify")

hs.loadSpoon("HyperKey")
spoon.HyperKey.notifyFn = function(t, s, d) spoon.Notify:info(t, s, d) end
spoon.HyperKey:start()

hs.loadSpoon("AppLauncher")
spoon.AppLauncher.hyperkey = spoon.HyperKey
spoon.AppLauncher
    :setApps({
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
    })
    :bindHotkeys({ launchPrefix = "h", chooserPrefix = "hs" })

hs.loadSpoon("ScriptMonitor")
spoon.ScriptMonitor
    :addEvent({
        on       = { "audioDevice", "screen" },
        script   = spoon.ScriptMonitor:resource("set_audio_device.sh"),
        delaySec = 2,
    })
    :addPoll({
        script      = spoon.ScriptMonitor:resource("process_monitor.py"),
        intervalSec = 5,
        onOutput    = function(out) spoon.Notify:alert("Process Monitor", out, 5) end,
    })
    :start()

hs.loadSpoon("ClaudeSessions")
spoon.ClaudeSessions
    :configure({ hotkey = { { "cmd", "alt", "ctrl" }, "'" } })
    :start()

hs.loadSpoon("WindowKit")
spoon.WindowKit
    :configure({
        hyperkey = spoon.HyperKey,
        notifyFn = function(t, s, d) spoon.Notify:info(t, s, d) end,
        alertFn  = function(t, s, d) spoon.Notify:alert(t, s, d) end,
    })
    :start()

hs.allowAppleScript(true)
require "hs.ipc"

spoon.Notify:info("Hammerspoon", "Reload finished successfully!")
