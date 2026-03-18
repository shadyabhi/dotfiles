#!/bin/zsh

local tmp=$(mktemp /tmp/starship-minimal.XXXXXX)
sed '/\$fill/d; /\$all/d' ~/.config/starship.toml >| "$tmp"
export STARSHIP_CONFIG="$tmp"
