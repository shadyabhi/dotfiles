#!/usr/bin/env bash
# One-shot chezmoi workflow:
#   1. commit + push pending changes in the chezmoi source repo
#   2. `chezmoi update` to pull remote, apply templates, and run the
#      run_after_apply_export-work.sh.tmpl hook (which rsyncs into the
#      work dotfiles repo)
#   3. mirror the source-repo commit message into the work repo
set -e

WORK_REPO="$HOME/coder/abhijeetr/dotfiles"
KEYCHAIN_SERVICE="bw-session"
KEYCHAIN_ACCOUNT="$USER"

# --- Bitwarden session: keychain > prompt -----------------------------
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

# --- 1. Commit chezmoi source repo ------------------------------------
cd "$(chezmoi source-path)"

BEFORE=$(git rev-parse HEAD)
git add -A
git commit -v || true
AFTER=$(git rev-parse HEAD)

git pull --rebase
git push

# --- 2. Apply (refreshes $HOME, triggers work-repo export) ------------
bw sync
chezmoi update --interactive

if [ "$BEFORE" = "$AFTER" ]; then
  echo "chezmoi source: no new commit; skipping work-repo mirror"
  exit 0
fi

# --- 3. Mirror commit into work repo ----------------------------------
if [ ! -d "$WORK_REPO/.git" ]; then
  echo "work repo not found at $WORK_REPO; skipping mirror"
  exit 0
fi

MSG=$(git -C "$(chezmoi source-path)" log -1 --pretty=%B)

cd "$WORK_REPO"
if [ -z "$(git status --porcelain)" ]; then
  echo "work repo: export produced no changes to commit"
  exit 0
fi

git add -A
git commit -m "$MSG"
git pull --rebase
git push
