#!/bin/bash
INPUT=$(cat)
PROJECT=$(basename "$(echo "$INPUT" | jq -r '.cwd')")
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' | head -c 120 | tr '\n' ' ')

BODY="$PROJECT"
if [[ -n "$LAST_MSG" ]]; then
  BODY="$PROJECT: $LAST_MSG"
fi

terminal-notifier \
  -title "✅ Claude Code" \
  -message "$BODY" \
  -sender com.apple.Terminal
