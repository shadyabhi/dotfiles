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
if [[ "$FRONTMOST" != "iTerm2" ]]; then
  terminal-notifier \
    -title "🔔 Claude Code" \
    -message "$BODY" \
    -sender com.apple.Terminal
fi
