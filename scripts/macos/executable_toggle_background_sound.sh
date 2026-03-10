#!/bin/bash

# Read the current comfortSoundsEnabled setting (0 = off, 1 = on)
isEnabled=$(defaults read com.apple.ComfortSounds comfortSoundsEnabled 2>/dev/null)

if [[ "$isEnabled" -eq 0 ]]; then
    # --- TURN ON BACKGROUND SOUNDS ---

    # Enable background sounds
    defaults write com.apple.ComfortSounds comfortSoundsEnabled -bool true

    # Record the timestamp of activation
    defaults write com.apple.ComfortSounds lastEnablementTimestamp $(date +%s)

    # Brief delay to allow changes to register
    sleep 0.5

    # Kill existing 'heard' agent (if running)
    killall heard 2>/dev/null

    # Reload the background sound service cleanly
    launchctl kickstart -k gui/$(id -u)/com.apple.accessibility.heard

else
    # --- TURN OFF BACKGROUND SOUNDS ---

    # Disable background sounds
    defaults write com.apple.ComfortSounds comfortSoundsEnabled -bool false

    # Brief delay to allow setting to apply
    sleep 0.5

    # Kill the 'heard' agent to stop playback
    killall heard 2>/dev/null
fi

