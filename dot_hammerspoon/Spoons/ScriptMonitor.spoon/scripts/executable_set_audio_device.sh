#!/bin/bash

# Preferred devices passed as args, pipe-delimited (priority order):
#   $1 = output devices, $2 = input devices
# Example: set_audio_device.sh "Bose|Dell|Speakers" "Bose|Mic"
IFS='|' read -r -a PREFERRED_OUTPUT <<< "$1"
IFS='|' read -r -a PREFERRED_INPUT <<< "$2"

AUDIO_SWITCH="/opt/homebrew/bin/SwitchAudioSource"

set_audio_device() {
    local type=$1
    shift
    local preferred_list=("$@")

    local available_devices
    available_devices=$($AUDIO_SWITCH -a -t "$type")

    for device in "${preferred_list[@]}"; do
        local matched
        matched=$(echo "$available_devices" | grep -F -m1 "$device")
        if [ -n "$matched" ]; then
            $AUDIO_SWITCH -t "$type" -s "$matched" > /dev/null
            echo "$matched"
            return 0
        fi
    done

    echo "Not found"
    return 1
}

result_input=$(set_audio_device "input" "${PREFERRED_INPUT[@]}")
result_output=$(set_audio_device "output" "${PREFERRED_OUTPUT[@]}")

osascript -e "set volume input volume 100"

osascript -e "display notification \"Preferred audio device set: Input: $result_input, Output: $result_output\" with title \"Audio Devices Set\""
