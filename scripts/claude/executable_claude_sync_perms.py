#!/usr/bin/env python3
"""Sync local Claude permissions to the chezmoi-managed JSON merge layer via fzf selection."""

import json
import subprocess
import sys
from pathlib import Path

SETTINGS_LOCAL = Path(".claude/settings.local.json")
MANAGED_SETTINGS = Path.home() / ".local/share/chezmoi/.json_merges/claude/settings.json"

if not SETTINGS_LOCAL.exists():
    print(f"No settings.local.json found at {SETTINGS_LOCAL}")
    sys.exit(1)

local_perms = json.loads(SETTINGS_LOCAL.read_text()).get("permissions", {}).get("allow", [])
if not local_perms:
    print("No permissions found in settings.local.json")
    sys.exit(0)

if not MANAGED_SETTINGS.exists():
    print(f"No managed settings file found at {MANAGED_SETTINGS}")
    sys.exit(1)

managed = json.loads(MANAGED_SETTINGS.read_text())
existing = set(managed.get("permissions", {}).get("allow", []))

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

managed.setdefault("permissions", {}).setdefault("allow", []).extend(selected)
MANAGED_SETTINGS.write_text(json.dumps(managed, indent=2) + "\n")

for perm in selected:
    print(f"Added: {perm}")

print(f"Added {len(selected)} new permission(s). Run 'chezmoi apply' to update.")
