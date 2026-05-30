#!/bin/bash
# Shared helper: logs when the Claude tmux pane is not visible.
# (Desktop notification disabled — Lumesent call removed.)
# Usage: notify-if-hidden.sh <tag> <title> <body> <group>
#
# Debug:  /usr/bin/log show --predicate 'process == "logger"' --last 5m --info --debug
SCRIPT_NAME="$(basename "$0")"
TAG="$1" TITLE="$2" BODY="$3" GROUP="$4"

FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
PANE_ACTIVE=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_active}' 2>/dev/null)
WINDOW_ACTIVE=$(tmux display-message -p -t "$TMUX_PANE" '#{window_active}' 2>/dev/null)

if [[ "$FRONTMOST" == "iTerm2" && "$PANE_ACTIVE" == "1" && "$WINDOW_ACTIVE" == "1" ]]; then
  /usr/bin/logger -t "$TAG" "$SCRIPT_NAME: skipped (iTerm2 focused, tmux pane visible)"
else
  /usr/bin/logger -t "$TAG" "$SCRIPT_NAME: would notify (notification disabled): $BODY"
fi
