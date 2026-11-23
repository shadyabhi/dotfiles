#!/bin/bash
# Claude Code "Stop" hook — fires when Claude finishes a response/turn.
# Debug:  /usr/bin/log show --predicate 'process == "logger"' --last 5m --info --debug
DIR="$(dirname "$0")"
SCRIPT_NAME="$(basename "$0")"
TAG="claude-hook-stop"
INPUT=$(cat)
/usr/bin/logger -t "$TAG" "$SCRIPT_NAME: raw input: $INPUT"
/usr/bin/logger -t "$TAG" "$SCRIPT_NAME: env: $(env | sort | tr '\n' '|')"
/usr/bin/logger -t "$TAG" "$SCRIPT_NAME: parent: $(ps -o command= -p $PPID 2>/dev/null)"
/usr/bin/logger -t "$TAG" "$SCRIPT_NAME: args: $*"

CURSOR_VERSION=$(echo "$INPUT" | jq -r '.cursor_version // empty')
if [[ -n "$CURSOR_VERSION" ]]; then
  /usr/bin/logger -t "$TAG" "$SCRIPT_NAME: skipped (cursor_version=$CURSOR_VERSION)"
  exit 0
fi

PROJECT=$(basename "$(echo "$INPUT" | jq -r '.cwd')")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PERM_MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty')
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')

TITLE="✅ Claude Code${PERM_MODE:+ [$PERM_MODE]}"
BODY="$PROJECT${LAST_MSG:+: $LAST_MSG}"

"$DIR/notify-if-hidden.sh" "claude-hook-stop" "$TITLE" "$BODY" "claude-${SESSION_ID:-default}"
