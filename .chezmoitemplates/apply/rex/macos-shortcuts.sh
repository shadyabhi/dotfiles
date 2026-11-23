{{ if eq .chezmoi.os "darwin" -}}
#!/bin/sh
set -eu

# Release Ctrl+Cmd+D from macOS Look Up so Rex can open rexdiff.
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 70 '
<dict>
  <key>enabled</key><false/>
  <key>value</key>
  <dict>
    <key>parameters</key>
    <array><integer>100</integer><integer>2</integer><integer>1310720</integer></array>
    <key>type</key><string>standard</string>
  </dict>
</dict>'

activate_settings=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
if [ -x "$activate_settings" ]; then
  "$activate_settings" -u
fi
{{ end -}}
