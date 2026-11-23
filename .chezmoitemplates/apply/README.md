# Apply scripts

Script bodies live in `.chezmoitemplates/apply/<component>/`. The root
`run_*.tmpl` files are one-line entrypoints that render those bodies.
Chezmoi automatically runs the rendered scripts during `chezmoi apply`.

| Component | Script body | Inputs | When it runs |
| --- | --- | --- | --- |
| Packages: Homebrew | [packages/homebrew.sh](packages/homebrew.sh) | `.chezmoidata/packages.yaml` | On change, macOS only |
| Packages: standalone binaries | [packages/binaries.sh](packages/binaries.sh) | `.chezmoidata/binaries.yaml` | On change |
| Packages: pipx | [packages/pipx.sh](packages/pipx.sh) | `.chezmoidata/pipx.yaml` | On change |
| Rex | [rex/macos-shortcuts.sh](rex/macos-shortcuts.sh) | Script body | On change, macOS only |
| LaunchAgents | [launchagents/reload.sh](launchagents/reload.sh) | `private_Library/private_LaunchAgents/*` | On change, after files are applied |
| Zsh | [zsh/zimfw.sh](zsh/zimfw.sh) | `dot_zshrc.zim`, `dot_zimrc.d/*`, `private_dot_zimrc` | On change, after files are applied |

## Execution order

Chezmoi sorts entrypoints by target name within each execution phase.
The current order is Homebrew, Rex shortcuts, standalone binaries, pipx,
then the after scripts: LaunchAgents and zimfw.

Entrypoint paths and rendered contents are preserved when organizing script
bodies. This keeps existing on-change execution history valid. Editing a
body changes the rendered script and causes that entrypoint to run again.
Input hashes embedded in the package, LaunchAgent, and zimfw scripts also
cause them to rerun when their inputs change.

## Editing and validation

Edit the component body. Keep `include` and `glob` paths relative to the
chezmoi source root. Preserve the platform guards and the entrypoint's
`run_onchange_` or `run_onchange_after_` attributes.

Render scripts for inspection without executing installers:

```sh
chezmoi dump --include scripts --format=json
```

Preview a specific entrypoint:

```sh
chezmoi apply --source-path --dry-run --verbose ./run_onchange_darwin_rex-shortcuts.sh.tmpl
```

Add new automatic setup under the relevant component, create a root
entrypoint using the same `template` pattern, and add it to the table above.
Ordinary shell scripts under `scripts/` are installed for manual use;
they do not run automatically during apply.
