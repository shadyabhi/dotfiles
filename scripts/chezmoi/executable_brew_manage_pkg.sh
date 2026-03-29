#!/bin/bash
set -euo pipefail

PACKAGES_FILE="$HOME/.local/share/chezmoi/.chezmoidata/packages.yaml"

# Ensure fzf is available
if ! command -v fzf &>/dev/null; then
    echo "Error: fzf is required but not installed."
    exit 1
fi

# Step 1: Pick action
ACTION=$(printf "add\nremove" | fzf --prompt="Action: " --height=~10 --no-info --layout=reverse) || exit 0

# Step 2: Pick package type
TYPE=$(printf "tap\nbrew\npersonal_brew\nwork_brew\ncask\npersonal_cask\nwork_cask" \
    | fzf --prompt="Package type: " --height=~10 --no-info --layout=reverse) || exit 0

# Map type to YAML key
case "$TYPE" in
    tap)           YAML_KEY="taps" ;;
    brew)          YAML_KEY="brews" ;;
    personal_brew) YAML_KEY="personal_brews" ;;
    work_brew)     YAML_KEY="work_brews" ;;
    cask)          YAML_KEY="casks" ;;
    personal_cask) YAML_KEY="personal_casks" ;;
    work_cask)     YAML_KEY="work_casks" ;;
esac

# Step 3: Pick or enter package name
if [[ "$ACTION" == "remove" ]]; then
    # For remove, select from existing packages in that category
    EXISTING=$(yq -r ".packages.${YAML_KEY}[]" "$PACKAGES_FILE" 2>/dev/null)
    if [[ -z "$EXISTING" ]]; then
        echo "No packages found in $YAML_KEY"
        exit 0
    fi
    PACKAGE=$(echo "$EXISTING" | fzf --prompt="Remove from ${YAML_KEY}: " --height=~20 --no-info --layout=reverse) || exit 0
else
    # For add, type the package name with fzf as a fuzzy filter over brew search results
    read -rp "Enter package name to add to ${YAML_KEY}: " PACKAGE
    if [[ -z "$PACKAGE" ]]; then
        echo "No package name provided"
        exit 1
    fi
fi

# Execute the action
case "$ACTION" in
    add)
        if yq ".packages.${YAML_KEY}[] | select(. == \"${PACKAGE}\")" "$PACKAGES_FILE" | grep -q .; then
            echo "'$PACKAGE' already exists in $YAML_KEY"
            exit 0
        fi
        yq -i ".packages.${YAML_KEY} += [\"${PACKAGE}\"] | .packages.${YAML_KEY} |= sort" "$PACKAGES_FILE"
        echo "Added '$PACKAGE' to $YAML_KEY (sorted)"
        ;;
    remove)
        yq -i "del(.packages.${YAML_KEY}[] | select(. == \"${PACKAGE}\"))" "$PACKAGES_FILE"
        echo "Removed '$PACKAGE' from $YAML_KEY"
        ;;
esac
