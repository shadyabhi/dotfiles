#!/bin/zsh

LUMESENT=/Applications/Lumesent.app/Contents/MacOS/Lumesent
GDATE=/opt/homebrew/opt/coreutils/libexec/gnubin/date
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

  title="$1"
  body="${*:2}"

  # For short delays (under 60s), use sleep directly — launchd only has minute granularity
  if (( seconds < 60 )); then
    ( sleep "$seconds" && $LUMESENT send --title "$title" --body "$body" ) &
    echo "Notification scheduled in $delay (via background sleep)"
    exit 0
  fi

  fire_date=$($GDATE -d "+${seconds} seconds" '+%Y-%m-%dT%H:%M:%S')
  fire_month=$($GDATE -d "+${seconds} seconds" '+%-m')
  fire_day=$($GDATE -d "+${seconds} seconds" '+%-d')
  fire_hour=$($GDATE -d "+${seconds} seconds" '+%-H')
  fire_minute=$($GDATE -d "+${seconds} seconds" '+%-M')
  job_id="com.lumesent.notify.$($GDATE +%s).$$"
  plist="$LAUNCH_AGENTS/${job_id}.plist"

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
