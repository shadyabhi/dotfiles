#!/bin/bash
# E2E harness for merge.sh. Each cases/<name>/ holds live.json (the "live"
# file content before merge; omitted means empty/missing) and expected.json
# (the required output, compared structurally with jq). remove-layer also
# applies fixtures/remove.json. Produces test/report.txt as a repeatable,
# reviewable artifact.
set -uo pipefail

test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
merge_sh="$test_dir/../merge.sh"
fixtures="$test_dir/fixtures"
report="$test_dir/report.txt"

pass=0
fail=0
: > "$report"

log() { echo "$1" | tee -a "$report"; }

run_case() {
  local name="$1" dir="$2"
  local live="$dir/live.json"
  local expected="$dir/expected.json"
  local args=(--defaults "$fixtures/defaults.json" --merge "$fixtures/base.json" --merge "$fixtures/device.json")
  if [ "$name" = "remove-layer" ]; then
    args+=(--remove "$fixtures/remove.json")
  fi

  local actual rc
  if [ -f "$live" ]; then
    actual=$(cat "$live" | "$merge_sh" "${args[@]}")
  else
    actual=$(printf '' | "$merge_sh" "${args[@]}")
  fi
  rc=$?
  if [ $rc -ne 0 ]; then
    log "FAIL $name: merge.sh exited $rc"
    fail=$((fail + 1))
    return
  fi

  if ! diff -u <(jq -S . "$expected") <(printf '%s' "$actual" | jq -S .) > "$dir/diff.actual"; then
    log "FAIL $name: output does not match expected.json (see $dir/diff.actual)"
    fail=$((fail + 1))
    return
  fi
  rm -f "$dir/diff.actual"

  if [ "$name" = "html-escape" ]; then
    if ! printf '%s' "$actual" | grep -q '\\u003c' || ! printf '%s' "$actual" | grep -q '\\u003e' || ! printf '%s' "$actual" | grep -q '\\u0026'; then
      log "FAIL $name: expected Go-style \\u003c/\\u003e/\\u0026 escaping in raw output"
      fail=$((fail + 1))
      return
    fi
  fi

  # Idempotence: feeding the output back through the same layers must not change it.
  local rerun
  rerun=$(printf '%s' "$actual" | "$merge_sh" "${args[@]}")
  if [ "$rerun" != "$actual" ]; then
    log "FAIL $name: not idempotent (re-merge changed output)"
    fail=$((fail + 1))
    return
  fi

  log "PASS $name"
  pass=$((pass + 1))
}

for dir in "$test_dir"/cases/*/; do
  name=$(basename "$dir")
  run_case "$name" "${dir%/}"
done

# Error-path cases: not fixture-driven, exercised directly.
if printf 'not json' | "$merge_sh" --merge "$fixtures/base.json" > /dev/null 2>&1; then
  log "FAIL invalid-live-json: merge.sh should have exited non-zero"
  fail=$((fail + 1))
else
  log "PASS invalid-live-json"
  pass=$((pass + 1))
fi

if printf '{}' | "$merge_sh" --merge "$test_dir/does-not-exist.json" > /dev/null 2>&1; then
  log "PASS missing-merge-file-skipped"
  pass=$((pass + 1))
else
  log "FAIL missing-merge-file-skipped: a missing (optional) layer file should be skipped, not fail"
  fail=$((fail + 1))
fi

if printf '{}' | env PATH=/nonexistent "$merge_sh" --merge "$fixtures/base.json" > /dev/null 2>&1; then
  log "FAIL missing-jq: merge.sh should have exited non-zero without jq on PATH"
  fail=$((fail + 1))
else
  log "PASS missing-jq"
  pass=$((pass + 1))
fi

log ""
log "== $pass passed, $fail failed =="
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
