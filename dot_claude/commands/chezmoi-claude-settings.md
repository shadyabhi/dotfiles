---
description: "Manage claude settings (model, permissions, statusLine, etc.) via chezmoi modify template. Use when: updating claude config, adding allowed permissions, changing model or statusLine, or managing settings.local.json through chezmoi."
allowed-tools: Read, Edit, Write, Bash(chezmoi *)
---

## Claude Settings via Chezmoi

You manage `~/.claude/settings.local.json` through chezmoi's modify-template mechanism. The source of truth is:

```
~/.local/share/chezmoi/dot_claude/modify_settings.local.json
```

### How it works

The template reads the existing `settings.local.json` as JSON, sets managed keys to their desired values, and writes the result back. Keys NOT mentioned in the template are preserved as-is (the user can change them freely without chezmoi overwriting them).

There are two types of managed settings:

1. **Simple key-value settings** — use `setValueAtPath`:
   ```
   {{- $data = $data | setValueAtPath "key" "value" -}}
   ```
   For nested values, use `dict`:
   ```
   {{- $data = $data | setValueAtPath "statusLine" (dict "type" "command" "command" "...") -}}
   ```

2. **Permissions (additive list)** — the `$perms` list defines permissions that must be present. The template ensures they exist in `permissions.allow` without removing any permissions the user added locally.

### Your workflow

1. Read the current template at `~/.local/share/chezmoi/dot_claude/modify_settings.local.json`
2. Make the requested changes:
   - **Add/update a setting**: Add or modify a `setValueAtPath` line
   - **Remove a managed setting**: Delete the corresponding `setValueAtPath` line (the key will remain in the actual file but chezmoi will stop managing it)
   - **Add a permission**: Add the permission string to the `$perms` list
   - **Remove a permission**: Remove it from the `$perms` list
3. Verify the output with `chezmoi cat ~/.claude/settings.local.json`

### Important

- Preserve the template structure: the `chezmoi:modify-template` comment, the `fromJson .chezmoi.stdin` line, and the `toPrettyJson` output at the end
- The permissions block (lines handling `$perms`, `hasKey`, `has`, `append`) is additive by design — it never removes permissions the user added outside chezmoi
- Use `false` (not `"false"`) for boolean values, numbers without quotes for numeric values
