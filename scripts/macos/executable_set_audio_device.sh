#!/bin/bash
# Trigger the Hammerspoon ScriptMonitor "audioDevice" event,
# which runs set_audio_device.sh with the configured preferred lists.
exec /opt/homebrew/bin/hs -c 'spoon.ScriptMonitor:fire("audioDevice")'
