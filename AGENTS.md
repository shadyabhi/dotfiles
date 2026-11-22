# JSON merges

`~/.claude/settings.json` and `~/.codex/hooks.json` are managed by `modify_` scripts calling `.json_merges/merge.py`. Edit the JSON under `.json_merges/{claude,codex}/`, never the live files or the `modify_` templates. Conventions are in `dot_claude/commands/chezmoi-claude-settings.md`. Run `.json_merges/test/run.py` after touching `merge.py`.
