#!/usr/bin/env bash
# One-shot chezmoi workflow: push local -> pull remote -> apply.
# Bitwarden session is unlocked via macOS keychain so apply can resolve
# `bitwarden` template lookups without prompting.
set -e

KEYCHAIN_SERVICE="bw-session"
KEYCHAIN_ACCOUNT="$USER"

get_bw_session() {
    local stored
    if stored=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null); then
        if BW_SESSION="$stored" bw unlock --check &>/dev/null; then
            BW_SESSION="$stored"
            return 0
        fi
    fi
    if BW_SESSION=$(bw unlock --raw); then
        security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$BW_SESSION"
        return 0
    fi
    return 1
}

if ! get_bw_session; then
    echo "Failed to unlock Bitwarden vault" >&2
    exit 1
fi
export BW_SESSION

cd "$(chezmoi source-path)"

git add -A
git diff --cached --quiet || git commit -v
git pull --rebase
git push

bw sync
chezmoi apply --interactive -v
