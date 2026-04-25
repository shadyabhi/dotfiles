#!/usr/bin/env bash
output=$(recon json 2>/dev/null)
[ -z "$output" ] && exit 0

# U+E0B6 = catppuccin left half-circle pill cap
echo "$output" | jq -r '
  [.sessions[] | select(.status == "Idle")
    | (.project_name // (.cwd | split("/") | last))] as $names
  | if ($names | length) == 0 then ""
    else
      "#[fg=#f9e2af,bg=#1e1e2e,nobold,nounderscore,noitalics]" +
      "" +
      "#[fg=#1e1e2e,bg=#f9e2af,bold]" +
      " \(($names | length))? " +
      "#[fg=#cdd6f4,bg=#313244,nobold] " +
      ($names | join(" #[fg=#45475a]·#[fg=#cdd6f4] ")) +
      " "
    end
'
