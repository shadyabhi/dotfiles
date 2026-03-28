---
name: chezmoi-sync
description: Syncs edited dotfiles to chezmoi and pushes changes with a descriptive commit message. Only trigger when invoked explicitly via /chezmoi-sync. Do NOT trigger automatically or from conversational mentions.
---

# Chezmoi Sync

This skill handles the workflow of tracking edited files, adding them to chezmoi, and pushing changes to the remote repository with a meaningful commit message.

## Why this exists

The user manages dotfiles with chezmoi. After editing config files, they need to:
1. Tell chezmoi about the changes (`chezmoi add`)
2. Commit and push those changes to their dotfiles repo

Doing this manually is tedious and easy to forget. This skill automates the whole flow.

## Workflow

### Step 1: Identify edited files

Look back through the conversation to find all files that were edited or written during this session. Focus on files in the user's home directory that are the kind of thing chezmoi manages (dotfiles, config files, scripts, etc.).

If you're unsure which files were changed, ask the user. Present your best guess first: "I see these files were edited: [list]. Should I sync all of them, or just some?"

### Step 2: Add files to chezmoi

For each file, run:

```bash
chezmoi add <absolute-path>
```

This copies the current state of each file into the chezmoi source directory (`~/.local/share/chezmoi`). Run all the `chezmoi add` commands — if one fails (e.g., the file is outside chezmoi's scope), note it and continue with the rest.

### Step 3: Craft a commit message

Use the format `<component>: <summary>` on the first line, with an optional description body below.

The component is the tool/config area that changed (e.g., `hammerspoon`, `zsh`, `tmux`, `claude`, `brew`, `go`). Derive it from the file paths — e.g., files under `.hammerspoon/` → `hammerspoon`, `.zshrc` or zsh configs → `zsh`, etc.

The summary is a short lowercase description of what changed. Use verbs like `add`, `fix`, `update`, `remove`.

Examples:
- `hammerspoon: add standardized notify module for alerts`
- `zsh(alias): add nvim related, and some comments`
- `tmux: optimize copy/paste workflow`
- `claude: fix CMD+V support`

If multiple components changed, pick the primary one or use a broader term. Add a blank line and a short description body only if the summary alone isn't enough to understand the change.

### Step 4: Sync to remote

Run these commands in the chezmoi source directory (`~/.local/share/chezmoi`):

```bash
cd "$(chezmoi source-path)"
git add -A
git commit -m "<commit message>"
git pull --rebase
git push
```

This mirrors what `chezmoi_sync.sh` does, but with a non-interactive commit message.

### Step 5: Confirm

Tell the user what was synced and show the commit message used. If any files failed to add, mention those too.

## Edge cases

- **File not managed by chezmoi yet**: `chezmoi add` handles this — it starts managing the file. No special treatment needed.
- **No changes to commit**: If `git commit` says there's nothing to commit, tell the user their chezmoi repo is already up to date.
- **Merge conflicts on pull**: If `git pull --rebase` fails, show the error and let the user decide how to resolve it. Don't force-push or auto-resolve.
