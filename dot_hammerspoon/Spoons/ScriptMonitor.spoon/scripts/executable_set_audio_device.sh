#!/bin/bash

# Preferred audio devices (in priority order)
PREFERRED_OUTPUT=("Bose QC Ultra 2 Earbuds" "Abhijeet's EX" "Abhijeet's Beoplay H100" "DELL U4025QW" "MacBook Pro Speakers")
PREFERRED_INPUT=("Bose QC Ultra 2 Earbuds" "Insta360 Link 2 Pro" "Abhijeet's EX" "Abhijeet's Beoplay H100" "Avaya HC020" "MacBook Pro Microphone")

AUDIO_SWITCH="/opt/homebrew/bin/SwitchAudioSource"

set_audio_device() {
    local type=$1
    shift
    local preferred_list=("$@")

    local available_devices
    available_devices=$($AUDIO_SWITCH -a -t "$type")

    for device in "${preferred_list[@]}"; do
        if echo "$available_devices" | grep -Fq "$device"; then
            $AUDIO_SWITCH -t "$type" -s "$device" > /dev/null
            echo "$device"
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
