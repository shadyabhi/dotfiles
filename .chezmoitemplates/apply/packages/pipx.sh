#!/bin/bash

# .chezmoidata/pipx.yaml hash: {{ include ".chezmoidata/pipx.yaml" | sha256sum }}

set -euo pipefail

echo "Running run_onchange_install-pipx-packages.sh..."

{{ range .pipx.items -}}
if ! pipx list | grep -q {{ .name | quote }}; then
    echo "Installing {{ .name }}..."
    pipx install {{ .name | quote }}
    echo "{{ .name }} installed successfully."
else
    echo "{{ .name }} already installed, skipping."
fi

{{ end -}}
