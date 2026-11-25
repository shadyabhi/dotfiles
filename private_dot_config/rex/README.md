# Rex configuration

The configuration is organized by responsibility under `mods/`. The root
[`init.lua`](init.lua) loads the pane, prompt, and Git modules in that order.

| Module | Contents | Guide |
| --- | --- | --- |
| `mods/pane.lua` | Ctrl+A followed by h/j/k/l focuses left/down/up/right without wrapping; s splits horizontally with a new pane below; v splits vertically with a new pane on the right; b breaks the focused pane into its own window (tab) in the same session. | |
| `mods/prompt/` | Shell word movement and the previous-argument picker. | [Prompt controls and setup](mods/prompt/README.md) |
| `mods/git/` | `revdiff --untracked` action and Ctrl+Cmd+D shortcut, using the focused pane’s Codex worktree when available, otherwise its foreground process directory. | |

For Codex, the Git action reads the root session log held open by that pane’s
process and uses its latest turn directory. Delegated agent logs are excluded.
It uses macOS’s Ruby and `lsof`, without choosing among unrelated worktrees.
Run `ruby mods/git/verify-codex-cwd.rb` to verify resolution with real open logs.

When a review finishes, its annotations are printed and copied to the macOS
clipboard. Empty reviews and failed commands leave the clipboard unchanged.
The helper also preserves revdiff's optional exit code 10 for annotations.

After changing the configuration, use Rex's config check and reload commands.
See the Rex [configuration documentation](https://www.superlogical.com/rex/docs/customize/config).
