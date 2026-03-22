#!/bin/bash
# Claude Code "Notification" hook — fires when Claude wants user attention.
# Debug:  /usr/bin/log show --predicate 'process == "logger"' --last 5m --info --debug
DIR="$(dirname "$0")"
SCRIPT_NAME="$(basename "$0")"
TAG="claude-hook-notification"
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
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty')
NOTIF_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')

case "$NOTIF_TYPE" in
  permission_prompt) TITLE="🔐 Claude Code — Permission" ;;
  idle_prompt)       TITLE="💬 Claude Code — Input Needed" ;;
  *)                 TITLE="🔔 Claude Code" ;;
esac

BODY="$PROJECT${MESSAGE:+: $MESSAGE}"

"$DIR/notify-if-hidden.sh" "claude-hook-notification" "$TITLE" "$BODY" "claude-${SESSION_ID:-default}"
