#!/bin/bash

# .chezmoidata/binaries.yaml hash: {{ include ".chezmoidata/binaries.yaml" | sha256sum }}

set -euo pipefail

echo "Running run_onchange_install-binaries.sh..."

{{ range .binaries.items -}}
if ! command -v {{ .name | quote }} &>/dev/null; then
    echo "Installing {{ .name }}..."
    {{ .install_command }}
    echo "{{ .name }} installed successfully."
else
    echo "{{ .name }} already installed, skipping."
fi

{{ end -}}
