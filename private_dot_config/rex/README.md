# Rex configuration

The configuration is organized by responsibility under `mods/`. The root
[`init.lua`](init.lua) loads the prompt and Git modules in that order.

| Module | Contents | Guide |
| --- | --- | --- |
| `mods/prompt/` | Shell word movement and the previous-argument picker. | [Prompt controls and setup](mods/prompt/README.md) |
| `mods/git/` | `rexdiff` action and shortcut. | |

After changing the configuration, use Rex's config check and reload commands.
See the Rex [configuration documentation](https://www.superlogical.com/rex/docs/customize/config).
