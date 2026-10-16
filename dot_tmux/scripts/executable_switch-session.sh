#!/bin/sh

current=$(tmux display-message -p '#{session_name}') || exit 1
selected=$(
    tmux list-sessions -F '#{session_name}' |
        grep -Fvx -- "$current" |
        fzf --reverse
) || exit 0

[ -n "$selected" ] || exit 0
tmux switch-client -t "=$selected"
