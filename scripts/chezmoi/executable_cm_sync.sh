#!/usr/bin/env bash
set -e

WORK_REPO="$HOME/coder/abhijeetr/dotfiles"

cd "$(chezmoi source-path)"

git add -A
git commit -v
git pull --rebase
git push

# Mirror the same commit (subject + body) into the work dotfiles repo,
# which receives a sanitized export via run_after_apply_export-work.sh.tmpl.
MSG=$(git log -1 --pretty=%B)

if [ -d "$WORK_REPO/.git" ]; then
  cd "$WORK_REPO"
  if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "$MSG"
    git pull --rebase
    git push
  else
    echo "work repo: no changes to sync"
  fi
else
  echo "work repo not found at $WORK_REPO; skipping mirror"
fi
