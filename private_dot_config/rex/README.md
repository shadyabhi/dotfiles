# Rex configuration

The configuration is organized by responsibility under `mods/`. The root
[`init.lua`](init.lua) loads the pane, prompt, and Git modules in that order.

| Module | Contents | Guide |
| --- | --- | --- |
| `mods/pane.lua` | Ctrl+A followed by c creates a new tab; h/j/k/l focuses left/down/up/right without wrapping; s splits horizontally with a new pane below; v splits vertically with a new pane on the right; b breaks the focused pane into its own window (tab) in the same session. | |
| `mods/prompt/` | Shell word movement and the previous-argument picker. | [Prompt controls and setup](mods/prompt/README.md) |
| `mods/process-directory.lua`, `mods/agent-cwd.rb` | Shared directory lookup: active Codex or Claude session directory when available, otherwise foreground process cwd. | |
| `mods/git/` | `revdiff --untracked` action and Ctrl+Cmd+D shortcut, using the shared directory lookup. | |

For Codex and Claude, splits and the Git action read root session logs held
open by that pane’s process. Codex uses the latest turn directory; Claude uses
the latest root record's cwd matching the transcript's session ID. Delegated
agent records are excluded. Missing, ambiguous, or unavailable session metadata
falls back to process cwd. It uses macOS’s Ruby and `lsof`.
Run `ruby mods/git/verify-codex-cwd.rb` to verify resolution with real open logs.

When a review finishes, its annotations are printed and copied to the macOS
clipboard. Empty reviews and failed commands leave the clipboard unchanged.
The helper also preserves revdiff's optional exit code 10 for annotations.

After changing the configuration, use Rex's config check and reload commands.
The pane module uses `require` so Rex includes it in the configuration hash
and clients refresh their shortcuts when it changes.
See the Rex [configuration documentation](https://www.superlogical.com/rex/docs/customize/config).

The s/v splits query the existing pane's foreground process at keypress time,
resolve its agent worktree or process directory, and open the new shell there.
They report an error if no directory can be read. A shell's last reported
directory does not override the live lookup.

Run `ruby mods/verify-pane-cwd.rb` against the running Rex server after reloading
the config. It sends both shortcuts in disposable sessions for shells, ordinary
commands, and agent fixtures that hold session logs open with a different
worktree directory. Fixtures include delegated records, incomplete log writes,
stale reported directories, spaces, and quotes. It checks directory, split
orientation, anchor, and focus, then removes its sessions. The agent fixtures
use Homebrew's `gsleep`. Optional `SESSION SOURCE_BLOCK EXPECTED_DIRECTORY`
arguments also verify an existing agent pane, closing test splits and restoring
focus afterward. Claude session parsing is covered by fixtures; no live Claude
CLI was available during verification.
The readable verification report is `/tmp/rex-split-cwd-verification.md`.
