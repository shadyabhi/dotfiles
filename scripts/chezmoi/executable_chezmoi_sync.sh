#!/usr/bin/env bash
set -e

cd "$(chezmoi source-path)"

git add -A
git commit -v
git pull --rebase
git push
