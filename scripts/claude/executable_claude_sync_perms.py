#!/usr/bin/env python3
"""Sync local Claude permissions to chezmoi template via fzf selection."""

import json
import subprocess
import sys
from pathlib import Path

SETTINGS_LOCAL = Path(".claude/settings.local.json")
ALLOW_PERMS = Path.home() / ".local/share/chezmoi/.chezmoitemplates/claude_allow_permissions"

if not SETTINGS_LOCAL.exists():
    print(f"No settings.local.json found at {SETTINGS_LOCAL}")
    sys.exit(1)

local_perms = json.loads(SETTINGS_LOCAL.read_text()).get("permissions", {}).get("allow", [])
if not local_perms:
    print("No permissions found in settings.local.json")
    sys.exit(0)

ALLOW_PERMS.parent.mkdir(parents=True, exist_ok=True)
ALLOW_PERMS.touch()
existing = set(ALLOW_PERMS.read_text().splitlines())

new_perms = [p for p in local_perms if p not in existing]
if not new_perms:
    print("All permissions already present, nothing to add.")
    sys.exit(0)

# Let user select via fzf
result = subprocess.run(
    ["fzf", "--multi", "--header=Select permissions to add (Tab to select, Enter to confirm)"],
    input="\n".join(new_perms),
    capture_output=True,
    text=True,
)
selected = result.stdout.strip().splitlines()
if not selected:
    print("No permissions selected.")
    sys.exit(0)

with ALLOW_PERMS.open("a") as f:
    for perm in selected:
        f.write(perm + "\n")
        print(f"Added: {perm}")

print(f"Added {len(selected)} new permission(s). Run 'chezmoi apply' to update.")
