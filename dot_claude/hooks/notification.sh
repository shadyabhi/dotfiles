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

terminal-notifier \
  -title "🔔 Claude Code" \
  -message "$BODY" \
  -sender com.apple.Terminal
