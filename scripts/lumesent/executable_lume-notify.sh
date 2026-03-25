#!/bin/zsh

LUMESENT=/Applications/Lumesent.app/Contents/MacOS/Lumesent
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

# If first arg looks like a duration (e.g. 5s, 10m, 2h), delay the notification via launchd
if [[ "$1" =~ ^([0-9]+)([smh])$ ]]; then
  delay="$1"
  shift
  num="${match[1]}"
  unit="${match[2]}"
  case "$unit" in
    s) seconds=$num ;;
    m) seconds=$((num * 60)) ;;
    h) seconds=$((num * 3600)) ;;
  esac

  fire_date=$(date -d "+${seconds} seconds" '+%Y-%m-%dT%H:%M:%S')
  fire_month=$(date -d "+${seconds} seconds" '+%-m')
  fire_day=$(date -d "+${seconds} seconds" '+%-d')
  fire_hour=$(date -d "+${seconds} seconds" '+%-H')
  fire_minute=$(date -d "+${seconds} seconds" '+%-M')
  job_id="com.lumesent.notify.$(date +%s).$$"
  plist="$LAUNCH_AGENTS/${job_id}.plist"

  title="$1"
  body="${*:2}"

  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${job_id}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-c</string>
    <string>${LUMESENT} send --title \"\${1}\" --body \"\${2}\"; launchctl remove ${job_id}; rm -f ${plist}</string>
    <string>--</string>
    <string>${title}</string>
    <string>${body}</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Month</key>
    <integer>${fire_month}</integer>
    <key>Day</key>
    <integer>${fire_day}</integer>
    <key>Hour</key>
    <integer>${fire_hour}</integer>
    <key>Minute</key>
    <integer>${fire_minute}</integer>
  </dict>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
EOF

  launchctl load "$plist"
  echo "Notification scheduled in $delay (at ${fire_date})"
  exit 0
fi

$LUMESENT send --title "$1" --body "${@:2}"
