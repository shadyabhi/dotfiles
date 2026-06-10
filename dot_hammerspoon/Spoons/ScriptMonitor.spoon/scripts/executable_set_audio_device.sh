#!/bin/bash

# Preferred devices passed as args, pipe-delimited (priority order):
#   $1 = output devices, $2 = input devices
# Example: set_audio_device.sh "Bose|Dell|Speakers" "Bose|Mic"
IFS='|' read -r -a PREFERRED_OUTPUT <<< "$1"
IFS='|' read -r -a PREFERRED_INPUT <<< "$2"

AUDIO_SWITCH="/opt/homebrew/bin/SwitchAudioSource"

# Switches to the highest-priority available preferred device.
# Emits "CHANGED:<name>" only when the active device actually differs from the
# current one, "UNCHANGED:<name>" otherwise — so callers can suppress no-op
# notifications (e.g. on screen wake/unlock when nothing changed).
set_audio_device() {
    local type=$1
    shift
    local preferred_list=("$@")

    local current available_devices
    current=$($AUDIO_SWITCH -c -t "$type")
    available_devices=$($AUDIO_SWITCH -a -t "$type")

    for device in "${preferred_list[@]}"; do
        local matched
        matched=$(echo "$available_devices" | grep -F -m1 "$device")
        if [ -n "$matched" ]; then
            if [ "$matched" != "$current" ]; then
                $AUDIO_SWITCH -t "$type" -s "$matched" > /dev/null
                echo "CHANGED:$matched"
            else
                echo "UNCHANGED:$matched"
            fi
            return 0
        fi
    done

    echo "UNCHANGED:Not found"
    return 1
}

result_input=$(set_audio_device "input" "${PREFERRED_INPUT[@]}")
result_output=$(set_audio_device "output" "${PREFERRED_OUTPUT[@]}")

# Notify only when at least one device actually changed.
if [[ "$result_input" == CHANGED:* || "$result_output" == CHANGED:* ]]; then
    osascript -e "set volume input volume 100"
    osascript -e "display notification \"Preferred audio device set: Input: ${result_input#*:}, Output: ${result_output#*:}\" with title \"Audio Devices Set\""
fi
