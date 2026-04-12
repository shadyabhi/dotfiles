#!/bin/bash

KEYCHAIN_SERVICE="bw-session"
KEYCHAIN_ACCOUNT="$USER"

# Try session from: keychain > prompt
get_bw_session() {
    # Try keychain
    local stored
    if stored=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null); then
        if BW_SESSION="$stored" bw unlock --check &>/dev/null; then
            BW_SESSION="$stored"
            return 0
        fi
    fi

    # Prompt for password
    if BW_SESSION=$(bw unlock --raw); then
        security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$BW_SESSION"
        return 0
    fi

    return 1
}

if ! get_bw_session; then
    echo "Failed to unlock Bitwarden vault"
    exit 1
fi

export BW_SESSION
bw sync && chezmoi update --interactive
