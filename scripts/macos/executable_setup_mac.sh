#!/bin/bash -e

# Faster response time
defaults write com.apple.Accessibility ReduceMotionEnabled -int 1 && echo "✅️ Animation: Reduce motion to make things feel fast"

# Trackpad
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -int 1 && echo "✅️ Trackpad: Allow clicks via tap"
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -int 1 && echo "✅️ Trackpad: Three-finger drag enabled"

# Applications
defaults write com.apple.LaunchServices LSQuarantine -bool false && echo "✅️ Apps: Disable quarantine dialog for new apps"
defaults write -g NSNavPanelExpandedStateForSaveMode -bool true && echo "✅️ Apps: Always show expanded save dialog"
