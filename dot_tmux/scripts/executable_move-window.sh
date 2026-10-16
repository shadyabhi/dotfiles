#!/usr/bin/env bash
# Window $1 (window id): join its panes into a picked window, or move it to the end of a picked session.
src="$1"
target=$({
  tmux list-windows -a -f "#{!=:#{window_id},$src}" -F '#{session_name}:#{window_index}	#{session_name}:#{window_index} #{window_name} (join as pane)'
  tmux list-sessions -F '#{session_name}:	#{session_name}: (new window at end)'
} | fzf --reverse --delimiter='	' --with-nth=2 --prompt='Move window to> ' | cut -f1)
[ -z "$target" ] && exit 0

if [[ "$target" == *: ]]; then
  tmux move-window -s "$src" -t "$target" || { read -rsn1 -p "move failed"; exit 1; }
  focus="$src"
else
  panes=$(tmux list-panes -t "$src" -F '#{pane_id}')
  for p in $panes; do
    tmux join-pane -d -s "$p" -t "$target" || { read -rsn1 -p "join failed"; exit 1; }
  done
  focus=${panes%%$'\n'*}
fi

tmux switch-client -t "$(tmux display-message -p -t "$focus" '#{session_name}')"
tmux select-window -t "$focus"
tmux select-pane -t "$focus"
