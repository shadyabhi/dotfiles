require "hyper"
require "launch"

require "win/absolute"
require "win/grid"
require "win/switch"
require "win/spaces"
require "win/auto_close"
require "win/fullscreen_notify"
require "audio_watcher"
require "selectcopy"
require "claude_paste"
require "process_monitor"
require "claude_sessions"
require "hs.ipc"

-- Auto-install and load spoons
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall:andUse("EmmyLua")
spoon.SpoonInstall:andUse("ReloadConfiguration", { start = true })

-- Enable Apple Script support
hs.allowAppleScript(true)

require("notify").info("Hammerspoon", "Reload finished successfully!")
