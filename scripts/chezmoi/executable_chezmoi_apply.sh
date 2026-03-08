#!/bin/bash

export BW_SESSION=$(bw unlock --raw)
chezmoi apply --interactive -v

# Check for untracked files in chezmoi source directory
SOURCE_DIR=$(chezmoi source-path)
if ! git -C "$SOURCE_DIR" status --porcelain | grep -q "^??"; then
    # No untracked files, so we can safely commit all changes
    if [[ -n $(git -C "$SOURCE_DIR" status --porcelain) ]]; then
        git -C "$SOURCE_DIR" commit -a -v
    fi
fi
