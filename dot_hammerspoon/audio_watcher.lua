local log = hs.logger.new("audio_watcher", "info")

local function runSetAudioDevice()
  -- add a delay to allow the system to fully switch devices
  hs.timer.doAfter(2, function()
    hs.execute("~/scripts/set_audio_device.sh")
    log.i("Script executed and notification sent")
  end)
end

local function audioDeviceWatcherCallback(event)
  if event == "dev#" then
    runSetAudioDevice()
  end
end

local function screenWatcherCallback()
  log.i("Display configuration changed")
  runSetAudioDevice()
end

hs.audiodevice.watcher.setCallback(audioDeviceWatcherCallback)
hs.audiodevice.watcher.start()

local screenWatcher = hs.screen.watcher.new(screenWatcherCallback)
screenWatcher:start()
