-- Load params with optional per-host override (params.<hostname>.lua).
local params = dofile(hs.configdir .. "/params.lua")
local id = hs.execute('printf "%s-%s" "$USER" "$(hostname -s)"'):gsub("%s+$", "")
local overridePath = hs.configdir .. "/params." .. id .. ".lua"
if hs.fs.attributes(overridePath) then
    for k, v in pairs(dofile(overridePath)) do params[k] = v end
end

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
    :setApps(params.apps)
    :bindHotkeys(params.appLauncher)

hs.loadSpoon("ScriptMonitor")
spoon.ScriptMonitor
    :addEvent({
        on       = { "audioDevice", "screen" },
        script   = spoon.ScriptMonitor:resource("set_audio_device.sh"),
        delaySec = params.scriptMonitor.audioScreenDelaySec,
        args     = {
            table.concat(params.audioDevice.preferredOutput, "|"),
            table.concat(params.audioDevice.preferredInput, "|"),
        },
    })
    :addPoll({
        script      = spoon.ScriptMonitor:resource("process_monitor.py"),
        intervalSec = params.scriptMonitor.processPollSec,
        args        = params.processMonitor.requiredApps,
        onOutput    = function(out) spoon.Notify:alert("Process Monitor", out, 5) end,
    })
    :start()

hs.loadSpoon("ClaudeSessions")
spoon.ClaudeSessions
    :configure({ hotkey = params.claudeSessions.hotkey })
    :start()

hs.loadSpoon("WindowKit")
local windowKitOpts = {
    hyperkey = spoon.HyperKey,
    notifyFn = function(t, s, d) spoon.Notify:info(t, s, d) end,
    alertFn  = function(t, s, d) spoon.Notify:alert(t, s, d) end,
}
for k, v in pairs(params.windowKit or {}) do windowKitOpts[k] = v end
spoon.WindowKit:configure(windowKitOpts):start()

hs.allowAppleScript(true)
require "hs.ipc"

spoon.Notify:info("Hammerspoon", "Reload finished successfully!")
