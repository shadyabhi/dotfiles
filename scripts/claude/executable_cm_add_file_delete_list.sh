#!/usr/bin/env bash
# Add a path to chezmoi's .chezmoiremove.tmpl so it gets deleted from every
# machine that applies this dotfiles repo, then commit the change.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $(basename "$0") <path under \$HOME>" >&2
    exit 1
fi

target_path=$(realpath -m "$1")

case "$target_path" in
    "$HOME"/*) target="${target_path#"$HOME"/}" ;;
    *)
        echo "Path must be under \$HOME: $target_path" >&2
        exit 1
        ;;
esac

source_dir=$(chezmoi source-path)
remove_file="$source_dir/.chezmoiremove.tmpl"

if [[ -f "$remove_file" ]] && grep -qxF "$target" "$remove_file"; then
    echo "Already in delete list: $target"
    exit 0
fi

printf '%s\n' "$target" >> "$remove_file"
echo "Added to delete list: $target"

git -C "$source_dir" add "$remove_file"
git -C "$source_dir" commit -q -m "chezmoi: add $target to delete list"
echo "Committed. Run cm_sync.sh (or chezmoi apply) to push and remove it everywhere."
