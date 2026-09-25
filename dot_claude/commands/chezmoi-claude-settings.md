---
description: "Manage claude settings (model, permissions, statusLine, etc.) via the JSON merge layers under .json_merges/claude/. Use when: updating claude config, adding allowed permissions, changing model or statusLine, or managing settings.json through chezmoi."
allowed-tools: Read, Edit, Write, Bash(chezmoi *)
---

## Claude Settings via Chezmoi

You manage `~/.claude/settings.json` through chezmoi's modify-script mechanism. The desired state lives in plain JSON files, not a template:

```
~/.local/share/chezmoi/.json_merges/claude/settings.json           # enforced overlay, all devices
~/.local/share/chezmoi/.json_merges/claude/settings.work.json      # enforced overlay, device_type=work only
~/.local/share/chezmoi/.json_merges/claude/settings.personal.json  # enforced overlay, device_type=personal only
~/.local/share/chezmoi/.json_merges/claude/settings.defaults.json  # fill-missing-only (e.g. enabledPlugins)
```

`dot_claude/modify_settings.json.tmpl` just wires these into `.json_merges/merge.py`, which reads the live file on stdin and writes the merged result to stdout. It should not normally need editing.

### How it works

`merge.py` layers the files above onto the live file's current content:

- **defaults**: fills in a path only if the live file doesn't already have it. A plugin the user disabled locally stays disabled.
- **merge** (`settings.json`, then the device-specific file): objects merge recursively; scalars are overwritten by the overlay's value (including `false`/`0`); arrays are unioned — live items keep their position, missing overlay items are appended. This is what makes `permissions.allow` and each `hooks.<Event>` array additive: foreign entries (e.g. the Netflix telemetry hooks written by `/opt/nflx/bin/claude`) survive, and a managed entry already present is never duplicated.
- Key order and formatting always follow the live file, so `chezmoi apply` doesn't create diff churn.

### Your workflow

1. Read the relevant file(s) under `.json_merges/claude/`.
2. Make the requested changes directly as JSON:
   - **Add/update a setting**: add or change the key in `settings.json` (or the device-specific file if it should only apply to `work` or `personal`).
   - **Add a permission**: append the string to `permissions.allow` in `settings.json`.
   - **Add/modify a hook**: edit the relevant `hooks.<Event>` array. Each entry is a hook *group* (`{matcher, hooks: [...]}` or `{hooks: [...]}`); match the live file's shape for that event.
   - **Retire a managed setting/permission/hook**: remove it from `settings.json`, then delete it from the live file yourself (there's no automated remove layer — `merge.py` only fills and merges). Removing it from `settings.json` just stops chezmoi from re-adding it.
3. Verify with `chezmoi cat ~/.claude/settings.json`, then `chezmoi diff` to see exactly what would change.

### Important

- These are plain JSON files — no template syntax, so standard JSON tooling (formatters, linters) works directly on them.
- Never hand-edit `dot_claude/modify_settings.json.tmpl` for a settings change; it's plumbing, not content.
- `scripts/claude/executable_claude_sync_perms.py` appends locally-added permissions from `~/.claude/settings.local.json` straight into `settings.json`'s `permissions.allow` — no more `.chezmoitemplates/claude_allow_permissions` text file.
- After editing, run `.json_merges/test/run.py` if you touched `merge.py`; for a plain content edit, `chezmoi diff` is enough.
