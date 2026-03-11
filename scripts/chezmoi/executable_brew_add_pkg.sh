#!/bin/bash
set -euo pipefail

PACKAGES_FILE="$HOME/.local/share/chezmoi/.chezmoidata/packages.yaml"

usage() {
    echo "Usage: $(basename "$0") <type> <package>"
    echo ""
    echo "Types: tap, brew, personal_brew, work_brew, cask, personal_cask, work_cask"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") brew ripgrep"
    echo "  $(basename "$0") cask google-chrome"
    echo "  $(basename "$0") tap homebrew/cask-fonts"
    exit 1
}

[[ $# -ne 2 ]] && usage

TYPE="$1"
PACKAGE="$2"

# Map type argument to the YAML key
case "$TYPE" in
    tap)           YAML_KEY="taps" ;;
    brew)          YAML_KEY="brews" ;;
    personal_brew) YAML_KEY="personal_brews" ;;
    work_brew)     YAML_KEY="work_brews" ;;
    cask)          YAML_KEY="casks" ;;
    personal_cask) YAML_KEY="personal_casks" ;;
    work_cask)     YAML_KEY="work_casks" ;;
    *) echo "Error: unknown type '$TYPE'"; usage ;;
esac

# Check if package already exists in that section
if yq ".packages.${YAML_KEY}[] | select(. == \"${PACKAGE}\")" "$PACKAGES_FILE" | grep -q .; then
    echo "'$PACKAGE' already exists in $YAML_KEY"
    exit 0
fi

# Add package and sort the array
yq -i ".packages.${YAML_KEY} += [\"${PACKAGE}\"] | .packages.${YAML_KEY} |= sort" "$PACKAGES_FILE"

echo "Added '$PACKAGE' to $YAML_KEY (sorted)"
