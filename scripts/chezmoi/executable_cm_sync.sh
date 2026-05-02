#!/usr/bin/env bash
# Sync chezmoi source repo and mirror the same commit into the work
# dotfiles repo, which receives a sanitized export via
# run_after_apply_export-work.sh.tmpl (triggered by `chezmoi apply`).
set -e

WORK_REPO="$HOME/coder/abhijeetr/dotfiles"

cd "$(chezmoi source-path)"

BEFORE=$(git rev-parse HEAD)
git add -A
git commit -v || true
AFTER=$(git rev-parse HEAD)

git pull --rebase
git push

if [ "$BEFORE" = "$AFTER" ]; then
  echo "chezmoi source: no new commit; skipping work-repo mirror"
  exit 0
fi

if [ ! -d "$WORK_REPO/.git" ]; then
  echo "work repo not found at $WORK_REPO; skipping mirror"
  exit 0
fi

MSG=$(git log -1 --pretty=%B)

cd "$WORK_REPO"
if [ -z "$(git status --porcelain)" ]; then
  echo "work repo: no changes (run 'chezmoi apply' first to refresh export)"
  exit 0
fi

git add -A
git commit -m "$MSG"
git pull --rebase
git push
