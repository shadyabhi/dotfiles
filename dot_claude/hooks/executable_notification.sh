#!/bin/bash
# Claude Code "Notification" hook — fires when Claude wants user attention.
# Debug:  /usr/bin/log show --predicate 'process == "logger"' --last 5m --info --debug
DIR="$(dirname "$0")"
INPUT=$(cat)
/usr/bin/logger -t "claude-hook-notification" "raw input: $INPUT"

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
