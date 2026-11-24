# Rex configuration

The configuration is organized by responsibility under `mods/`. The root
[`init.lua`](init.lua) loads the pane, prompt, and Git modules in that order.

| Module | Contents | Guide |
| --- | --- | --- |
| `mods/pane.lua` | Ctrl+A followed by h/j/k/l focuses left/down/up/right without wrapping; s splits horizontally with a new pane below; v splits vertically with a new pane on the right. All operate within the current window. | |
| `mods/prompt/` | Shell word movement and the previous-argument picker. | [Prompt controls and setup](mods/prompt/README.md) |
| `mods/git/` | `revdiff --untracked` action and Ctrl+Cmd+D shortcut, using the focused pane’s foreground process directory. | |

After changing the configuration, use Rex's config check and reload commands.
See the Rex [configuration documentation](https://www.superlogical.com/rex/docs/customize/config).
