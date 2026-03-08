#!/usr/bin/env bash

# This script synchronizes chezmoi configuration files with a streamlined flow.

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Exit on error
set -e

SOURCE_DIR=$(chezmoi source-path)
cd "${SOURCE_DIR}"

echo -e "${BLUE}=== Chezmoi Sync: ${SOURCE_DIR} ===${NC}"

# Check if there are unstaged changes or untracked files
if [[ -n $(git status --porcelain | grep -E '^.[^ ]|^ \?') ]]; then
    # 1. Automatic Interactive Add
    echo -e "\n${YELLOW}--- Starting Interactive Add (Select files to stage) ---${NC}"
    # git add -i allows selecting files, including untracked/hidden ones
    git add -i
else
    echo -e "\n${BLUE}No unstaged changes or untracked files to add.${NC}"
fi

# 2. Show Staged Changes and Commit
# We check if there are staged changes before attempting commit
if [[ -n $(git status --porcelain | grep -E '^[MADRC]') ]]; then
    echo -e "\n${YELLOW}--- Review Staged Changes and Commit ---${NC}"
    # git commit -v shows the diff in the editor
    if git commit -v; then
        # 3. Push if commit was successful
        echo -e "${GREEN}Pushing to remote...${NC}"
        git push
        echo -e "${GREEN}Successfully synced!${NC}"
    else
        echo -e "${YELLOW}Commit aborted. Skipping push.${NC}"
    fi
else
    echo -e "\n${BLUE}No changes staged for commit.${NC}"
fi
