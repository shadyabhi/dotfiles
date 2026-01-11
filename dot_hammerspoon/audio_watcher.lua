local log = hs.logger.new("audio_watcher", "info")

local function audioDeviceWatcherCallback(event)
  -- trigger the script when an input device changes

  if event == "dev#" then
    -- add a delay to allow the system to fully switch devices
    hs.timer.doAfter(2, function()
      local inputDevice = hs.audiodevice.defaultInputDevice():name()

      local logFile = "~/scripts/audio_input_log.txt"

      hs.execute("~/scripts/set_audio_device.sh")
      log.i("Script executed and notification sent")
    end)
  end
end

hs.audiodevice.watcher.setCallback(audioDeviceWatcherCallback)
hs.audiodevice.watcher.start()
