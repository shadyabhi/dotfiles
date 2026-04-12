#!/bin/sh

# LaunchAgents hash: {{ range (glob "private_Library/private_LaunchAgents/*") }}{{ . | include | sha256sum }}{{ end }}

set -eu

launch_agents_dir="$HOME/Library/LaunchAgents"

for plist in "$launch_agents_dir"/com.shadyabhi.*.plist; do
    [ -f "$plist" ] || continue
    label=$(basename "$plist" .plist)
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "Reloaded $label"
done
