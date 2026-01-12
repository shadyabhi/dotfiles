#!/bin/bash

# Preferred audio devices (in priority order)
PREFERRED_OUTPUT=("Abhijeet's Beoplay H100" "DELL U4025QW" "MacBook Pro Speakers")
PREFERRED_INPUT=("Abhijeet's Beoplay H100" "Avaya HC020" "MacBook Pro Microphone")

AUDIO_SWITCH="/opt/homebrew/bin/SwitchAudioSource"

# Function to set audio device
set_audio_device() {
    local type=$1
    shift
    local preferred_list=("$@")

    # Get available devices
    local available_devices
    available_devices=$($AUDIO_SWITCH -a -t "$type")

    # Try each preferred device in order
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

# Set output device
output_result=$(set_audio_device "output" "${PREFERRED_OUTPUT[@]}")

# Set input device
input_result=$(set_audio_device "input" "${PREFERRED_INPUT[@]}")

# Send single summary notification
osascript -e "display notification \"Output: $output_result \nInput: $input_result\" with title \"Audio Devices Set\""
