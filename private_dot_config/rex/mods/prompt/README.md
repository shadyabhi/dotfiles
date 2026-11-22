# Prompt controls

This module maps Cmd+B and Cmd+F to terminal word movement and provides the
previous-argument picker.
The picker uses Cmd+. at a zsh prompt to open a native
Rex popup containing words from the previous history entry. The rightmost
argument is selected by default. Enter inserts it at the cursor, popup text
filters the choices, and Escape leaves the command line unchanged.

The list runs from right to left and omits the first command token. Duplicate
words remain separate choices. Quotes and escapes from history are retained,
so `"two words"` is one choice. Inserted text goes before the cursor; text after
the cursor stays intact. The widget does not add spaces or submit the command.
The popup is limited to 2,000 choices.

## Setup and requirements

Rex loads the binding and picker action from `mods/prompt/`. A new Rex zsh
terminal loads the widget through the existing `~/.zshrc.d/rex-arguments`
startup loader, which sources `mods/prompt/argument-picker.zsh` directly.
In an already open shell, source the widget once:

```zsh
source ~/.config/rex/mods/prompt/argument-picker.zsh
```

The picker requires zsh, `jq`, and the Rex CLI, with `REX_SESSION` and
`REX_BLOCK` available in the terminal. It supports the Emacs and vi insert
keymaps, but does not add a vi command-mode binding. Cmd+. targets a shell
prompt; another foreground program receives the forwarded control sequence.

## Repeatable verification

In a fresh Rex zsh terminal:

1. Run `: alpha "two words" omega` and submit it.
2. At the next prompt, type `print -r -- ` without submitting it.
3. Press Cmd+. and Enter. The editable line should become
   `print -r -- omega`.
4. Type a space, press Cmd+., type `two`, and press Enter. The line should now
   end with `"two words"`, including its quotes.
5. Press Cmd+. and Escape. The current command line should remain unchanged.

Also check that filtering narrows the popup and that insertion at a cursor in
the middle of a command preserves the text after the cursor. Check shell syntax
with:

```zsh
zsh -n ~/.config/rex/mods/prompt/argument-picker.zsh
```

After editing Lua bindings, run `rex config check --json`, reload the
configuration, and inspect `rex keymap --json` for the Cmd+. binding and
diagnostics.

## Behavior and limits

The zsh widget reads the previous history entry with `fc` and splits it using
zsh lexical rules; it does not evaluate expansions. Variables, globs, and
substitutions remain source text. Compound commands and pipelines can include
operators or later command tokens because only the first token is removed.
Shared zsh history affects which entry is considered previous. A command with
no argument displays a prompt message; missing history opens no popup. A
shortcut set directly in Rex.app takes priority over a config binding. If
multiple Rex apps are connected, the first popup response is used.

Rex's [keyboard shortcuts](https://www.superlogical.com/rex/docs/customize/keyboard-shortcuts),
[custom actions](https://www.superlogical.com/rex/docs/customize/actions), and
[custom UI](https://www.superlogical.com/rex/docs/customize/custom-ui)
documentation describes the APIs used by the picker.
