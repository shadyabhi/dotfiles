#!/usr/bin/env python3
"""E2E harness for merge.py: invokes it as a real subprocess (no mocking of
its internals), the same way the chezmoi modify scripts do.

Each cases/<name>/ holds live.json (the live file's content before merge;
omitted means empty/missing stdin) and expected.json (the required output,
compared structurally). Writes test/report.txt as a repeatable artifact.
"""
import json
import subprocess
import sys
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parent
MERGE_PY = TEST_DIR.parent / "merge.py"
FIXTURES = TEST_DIR / "fixtures"
CASES = TEST_DIR / "cases"
REPORT = TEST_DIR / "report.txt"

BASE_ARGS = [
    "--defaults", str(FIXTURES / "defaults.json"),
    "--merge", str(FIXTURES / "base.json"),
    "--merge", str(FIXTURES / "device.json"),
]


def run_merge(stdin_text, args):
    return subprocess.run(
        [sys.executable, str(MERGE_PY), *args],
        input=stdin_text, capture_output=True, text=True,
    )


def check_case(name, case_dir, log):
    live = case_dir / "live.json"
    expected = case_dir / "expected.json"
    stdin_text = live.read_text() if live.is_file() else ""

    proc = run_merge(stdin_text, BASE_ARGS)
    if proc.returncode != 0:
        log(f"FAIL {name}: merge.py exited {proc.returncode}: {proc.stderr.strip()}")
        return False

    actual, want = proc.stdout, json.loads(expected.read_text())
    if json.loads(actual) != want:
        log(f"FAIL {name}: output does not match expected.json\n  got:      {actual!r}\n  expected: {json.dumps(want)!r}")
        return False

    if name == "html-escape":
        for esc in ("\\u003c", "\\u003e", "\\u0026"):
            if esc not in actual:
                log(f"FAIL {name}: expected Go-style {esc} escaping in raw output")
                return False

    # Idempotence: feeding the output back through the same layers must not change it.
    rerun = run_merge(actual, BASE_ARGS)
    if rerun.returncode != 0 or rerun.stdout != actual:
        log(f"FAIL {name}: not idempotent (re-merge changed output)")
        return False

    log(f"PASS {name}")
    return True


def check_error_paths(log):
    results = []

    proc = run_merge("not json", ["--merge", str(FIXTURES / "base.json")])
    if proc.returncode == 0:
        log("FAIL invalid-live-json: merge.py should have exited non-zero")
        results.append(False)
    else:
        log("PASS invalid-live-json")
        results.append(True)

    proc = run_merge("{}", ["--merge", str(TEST_DIR / "does-not-exist.json")])
    if proc.returncode != 0:
        log("FAIL missing-merge-file-skipped: a missing (optional) layer file should be skipped, not fail")
        results.append(False)
    else:
        log("PASS missing-merge-file-skipped")
        results.append(True)

    proc = run_merge("{}", ["--not-a-real-flag"])
    if proc.returncode == 0:
        log("FAIL unknown-argument: merge.py should reject an unrecognized flag")
        results.append(False)
    else:
        log("PASS unknown-argument")
        results.append(True)

    return results


def main():
    lines = []
    log = lines.append

    results = [check_case(d.name, d, log) for d in sorted(CASES.iterdir()) if d.is_dir()]
    results.extend(check_error_paths(log))

    passed, failed = results.count(True), results.count(False)
    log("")
    log(f"== {passed} passed, {failed} failed ==")

    report_text = "\n".join(lines)
    REPORT.write_text(report_text + "\n")
    print(report_text)
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
