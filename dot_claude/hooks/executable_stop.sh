#!/bin/bash
# Claude Code "Stop" hook — fires when Claude finishes a response/turn.
# Debug:  /usr/bin/log show --predicate 'process == "logger"' --last 5m --info --debug
DIR="$(dirname "$0")"
INPUT=$(cat)
/usr/bin/logger -t "claude-hook-stop" "raw input: $INPUT"

PROJECT=$(basename "$(echo "$INPUT" | jq -r '.cwd')")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PERM_MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty')
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' | head -c 120 | tr '\n' ' ')

TITLE="✅ Claude Code${PERM_MODE:+ [$PERM_MODE]}"
BODY="$PROJECT${LAST_MSG:+: $LAST_MSG}"

"$DIR/notify-if-hidden.sh" "claude-hook-stop" "$TITLE" "$BODY" "claude-${SESSION_ID:-default}"
