#!/bin/bash

if [ -z "$BW_SESSION" ]; then
    echo "Error: BW_SESSION not set. Run 'bw unlock' first." >&2
    exit 1
fi

name="chezmoi_${1#chezmoi_}"
bw get template item | jq -rc --arg name "$name" --arg notes "$2" '.name=$name | .type=2 | .notes=$notes | .secureNote={type:0} | .folderId="2dce60df-7100-4881-b4bc-599b68e6b987"' | bw encode | bw create item

echo ""
echo "Secret created: $name"
echo "Access in chezmoi template: {{ (bitwarden \"item\" \"$name\").notes }}"
