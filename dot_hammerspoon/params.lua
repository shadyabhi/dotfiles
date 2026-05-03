-- Default parameters. Override per-machine in `params.<user>-<hostname>.lua`
-- (e.g. params.shadyabhi-macbook-air.lua). Override file returns a partial
-- table; top-level keys present there fully replace the defaults below.

return {
    apps = {
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
    },

    appLauncher = {
        launchPrefix  = "h",
        chooserPrefix = "hs",
    },

    claudeSessions = {
        hotkey = { { "cmd", "alt", "ctrl" }, "'" },
    },

    windowKit = {
        gridChoices = { "2x1", "2x2", "3x1", "3x2" },
    },

    scriptMonitor = {
        audioScreenDelaySec = 2,
        processPollSec      = 5,
    },

    processMonitor = {
        requiredApps = {
            "Lumesent",
            "Shottr",
            "BetterDisplay",
            "MacWhisper",
            "Alfred",
        },
    },

    audioDevice = {
        preferredOutput = {
            "Bose QC Ultra 2 Earbuds",
            "Abhijeet's EX",
            "Abhijeet's Beoplay H100",
            "DELL U4025QW",
            "MacBook Pro Speakers",
        },
        preferredInput = {
            "Bose QC Ultra 2 Earbuds",
            "Insta360 Link 2 Pro",
            "Abhijeet's EX",
            "Abhijeet's Beoplay H100",
            "Avaya HC020",
            "MacBook Pro Microphone",
        },
    },
}
