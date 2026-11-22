# Loaded by ~/.zshrc.d/rex-arguments. Cmd+. sends Ctrl+X, then period.
_rex_last_argument() {
  emulate -L zsh
  [[ -n $REX_SESSION && -n $REX_BLOCK ]] || return

  local previous payload reply selected
  local -a argv_words
  previous=$(fc -ln -1 2>/dev/null) || return
  # Lex only, without evaluating expansions; keep quotes around multiword args.
  argv_words=( "${(@z)previous}" )
  if (( $#argv_words < 2 )); then
    zle -M 'The previous command has no arguments.'
    return
  fi

  payload=$(printf '%s\0' "${argv_words[@]:1}" |
    command jq -Rs '{words: split("\u0000")[:-1]}') || return
  reply=$(command rex do pick_last_argument \
    -s "$REX_SESSION" -b "$REX_BLOCK" --args "$payload" --json)
  if (( $? != 0 )); then
    zle -M 'Could not open the argument picker.'
    return
  fi
  if [[ -n $reply ]]; then
    selected=$(print -rn -- "$reply" | command jq -er '.word') || return
    LBUFFER+=$selected
  fi
  zle redisplay
}

zle -N rex-last-argument _rex_last_argument
bindkey -M emacs '^X.' rex-last-argument
bindkey -M viins '^X.' rex-last-argument
