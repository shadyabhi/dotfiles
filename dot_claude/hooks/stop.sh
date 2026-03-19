#!/bin/bash
INPUT=$(cat)
PROJECT=$(basename "$(echo "$INPUT" | jq -r '.cwd')")
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' | head -c 120 | tr '\n' ' ')

BODY="$PROJECT"
if [[ -n "$LAST_MSG" ]]; then
  BODY="$PROJECT: $LAST_MSG"
fi

FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
if [[ "$FRONTMOST" != "iTerm2" ]]; then
  terminal-notifier \
    -title "✅ Claude Code" \
    -message "$BODY" \
    -sender com.apple.Terminal
fi
