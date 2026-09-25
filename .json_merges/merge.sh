#!/bin/bash
# Generic chezmoi modify-script backend: reads the live file's current
# content on stdin, layers plain-JSON files on top of it, writes the merged
# result to stdout. See the "Readable JSON overlays" plan for the contract.
#
# Usage: merge.sh [--no-trailing-newline] [--defaults FILE] [--merge FILE]... [--remove FILE]
#   --defaults FILE  fill-missing-only layer (optional, applied first)
#   --merge FILE     deep-merge layer, overlay wins on conflicts (repeatable,
#                     applied in the order given; missing files are skipped)
#   --remove FILE     paths to delete after all merges (optional)
#   --no-trailing-newline  omit the trailing newline chezmoi would otherwise get
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v jq >/dev/null 2>&1; then
  echo "merge.sh: jq is required but not found on PATH" >&2
  exit 1
fi

defaults_file=""
merge_files=()
remove_file=""
trailing_newline=1

while [ $# -gt 0 ]; do
  case "$1" in
    --defaults) defaults_file="$2"; shift 2 ;;
    --merge) merge_files+=("$2"); shift 2 ;;
    --remove) remove_file="$2"; shift 2 ;;
    --no-trailing-newline) trailing_newline=0; shift ;;
    *) echo "merge.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
done

live=$(cat)
if [ -z "$live" ]; then
  live="{}"
fi
if ! printf '%s' "$live" | jq empty >/dev/null 2>&1; then
  echo "merge.sh: live input is not valid JSON" >&2
  exit 1
fi

apply() {
  # apply FUNC FILE: result := FUNC(result; contents of FILE)
  local func="$1" file="$2"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    return 0
  fi
  if ! jq empty "$file" >/dev/null 2>&1; then
    echo "merge.sh: $file is not valid JSON" >&2
    exit 1
  fi
  live=$(jq -n -L "$script_dir" --argjson a "$live" --slurpfile b "$file" \
    "include \"merge\"; ${func}(\$a; \$b[0])")
}

apply deepfill "$defaults_file"
for f in "${merge_files[@]}"; do
  apply deepmerge "$f"
done
apply deepremove "$remove_file"

out=$(printf '%s' "$live" | jq '.')
# Match Go's encoding/json HTMLEscape, which chezmoi's toPrettyJson used to
# apply, so re-running apply doesn't reintroduce a diff against what the
# Netflix claude/codex wrapper (also Go's encoding/json) writes back.
out=$(printf '%s' "$out" | sed -e 's/</\\u003c/g' -e 's/>/\\u003e/g' -e 's/\&/\\u0026/g')

if [ "$trailing_newline" -eq 1 ]; then
  printf '%s\n' "$out"
else
  printf '%s' "$out"
fi
