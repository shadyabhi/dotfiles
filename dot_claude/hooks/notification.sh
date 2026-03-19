#!/bin/bash
INPUT=$(cat)
PROJECT=$(basename "$(echo "$INPUT" | jq -r '.cwd')")
TITLE=$(echo "$INPUT" | jq -r '.title // empty')
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty')

BODY="$PROJECT"
if [[ -n "$TITLE" && -n "$MESSAGE" ]]; then
  BODY="$PROJECT: $MESSAGE"
elif [[ -n "$TITLE" ]]; then
  BODY="$PROJECT: $TITLE"
fi

FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
PANE_ACTIVE=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_active}' 2>/dev/null)
WINDOW_ACTIVE=$(tmux display-message -p -t "$TMUX_PANE" '#{window_active}' 2>/dev/null)
TMUX_VISIBLE="false"
if [[ "$PANE_ACTIVE" == "1" && "$WINDOW_ACTIVE" == "1" ]]; then
  TMUX_VISIBLE="true"
fi

if [[ "$FRONTMOST" != "iTerm2" || "$TMUX_VISIBLE" != "true" ]]; then
  terminal-notifier \
    -title "🔔 Claude Code" \
    -message "$BODY" \
    -sender com.apple.Terminal
fi
