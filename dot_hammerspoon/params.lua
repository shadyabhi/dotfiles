-- Default parameters. Override per-machine in `params.<user>-<hostname>.lua`
-- where <user> = $USER and <hostname> = `hostname -s` (see init.lua).
-- e.g. on host `macbook-air` for user `shadyabhi`, create:
--      params.shadyabhi-macbook-air.lua
--
-- Override file returns a partial table. Top-level keys present in the
-- override REPLACE the matching default whole — no deep merge. To tweak
-- one nested field, copy the whole sub-table from below and edit it.
--
-- Example override (only changes grid + apps, leaves rest as defaults):
--
--     return {
--         apps = {
--             { "b", "Firefox" },
--             { "t", "Ghostty" },
--         },
--         windowKit = {
--             gridDims    = "4x2",
--             gridMargins = "0x0",
--             gridChoices = { "2x1", "4x2" },
--         },
--     }

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

    agentSessions = {
        hotkey = { { "cmd", "alt", "ctrl" }, "'" },
    },

    windowKit = {
        gridDims    = "3x2",
        gridMargins = "1x1",
        gridChoices = { "2x1", "2x2", "3x1", "3x2" },
    },

    scriptMonitor = {
        audioScreenDelaySec = 2,
        processPollSec      = 5,
    },

    uptimeReminder = {
        thresholdDays    = 7,
        hourThreshold    = 17,
        checkIntervalSec = 30 * 60,
        snoozeSec        = 2 * 60 * 60,
    },

    processMonitor = {
        requiredApps = {
            "Lumesent",
            "Shottr",
            "BetterDisplay",
            "FluidVoice",
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
