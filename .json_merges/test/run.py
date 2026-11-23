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
import tempfile
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


def run_merge_bytes(stdin_bytes, args):
    return subprocess.run(
        [sys.executable, str(MERGE_PY), *args],
        input=stdin_bytes, capture_output=True,
    )


def check_noop_bytes(name, stdin_bytes, args, log):
    proc = run_merge_bytes(stdin_bytes, args)
    if proc.returncode != 0:
        log(f"FAIL {name}: merge.py exited {proc.returncode}: {proc.stderr.decode().strip()}")
        return False
    if proc.stdout != stdin_bytes:
        log(f"FAIL {name}: unchanged JSON bytes were rewritten\n  got:      {proc.stdout!r}\n  expected: {stdin_bytes!r}")
        return False
    log(f"PASS {name}")
    return True


def check_blank_input(name, stdin_bytes, args, expected, log):
    proc = run_merge_bytes(stdin_bytes, args)
    if proc.returncode != 0:
        log(f"FAIL {name}: merge.py exited {proc.returncode}: {proc.stderr.decode().strip()}")
        return False
    try:
        actual = json.loads(proc.stdout)
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        log(f"FAIL {name}: blank input did not produce valid JSON: {e}; got {proc.stdout!r}")
        return False
    if actual != {} or proc.stdout != expected:
        log(f"FAIL {name}: expected {expected!r}, got {proc.stdout!r}")
        return False
    log(f"PASS {name}")
    return True


def check_typed_overlay(name, live_value, overlay_value, expected_type, expected_value, log):
    with tempfile.TemporaryDirectory() as temp_dir:
        overlay = Path(temp_dir) / "overlay.json"
        overlay.write_text(json.dumps({"value": overlay_value}))
        stdin_bytes = json.dumps({"value": live_value}, separators=(",", ":")).encode()
        proc = run_merge_bytes(stdin_bytes, ["--merge", str(overlay)])

    if proc.returncode != 0:
        log(f"FAIL {name}: merge.py exited {proc.returncode}: {proc.stderr.decode().strip()}")
        return False
    if proc.stdout == stdin_bytes:
        log(f"FAIL {name}: changed overlay was treated as a no-op")
        return False
    try:
        actual = json.loads(proc.stdout)
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        log(f"FAIL {name}: output is not valid JSON: {e}; got {proc.stdout!r}")
        return False
    if type(actual.get("value")) is not expected_type or actual["value"] != expected_value:
        log(f"FAIL {name}: expected {expected_type.__name__} {expected_value!r}, got {type(actual.get('value')).__name__} {actual.get('value')!r}")
        return False
    log(f"PASS {name}")
    return True


def check_noop_preservation(log):
    results = []
    missing_layer = str(TEST_DIR / "does-not-exist-optional-layer.json")
    results.append(check_noop_bytes(
        "noop-compact-json", b'{"z":1,"a":"value"}', [], log,
    ))
    results.append(check_noop_bytes(
        "noop-indented-json", b'{\n  "z": 1,\n  "a": "value"\n}\n', [], log,
    ))
    results.append(check_noop_bytes(
        "noop-unicode-html-literal", '{"text":"café <>&"}\n'.encode(), [], log,
    ))
    results.append(check_noop_bytes(
        "noop-unicode-html-escaped", b'{"text":"caf\\u00e9 \\u003c\\u003e\\u0026"}\n', [], log,
    ))
    results.append(check_noop_bytes(
        "noop-crlf", b'{\r\n  "value": true\r\n}\r\n', [], log,
    ))

    for newline_name, newline in (("without-newline", b""), ("with-newline", b"\n")):
        for flag_name, flag_args in (("default", []), ("no-trailing-newline", ["--no-trailing-newline"])):
            results.append(check_noop_bytes(
                f"noop-eol-{newline_name}-{flag_name}",
                b'{"value":true}' + newline, flag_args, log,
            ))

    results.append(check_noop_bytes(
        "noop-missing-optional-layers",
        b'{\r\n  "foreign": "kept"\r\n}',
        ["--defaults", missing_layer, "--merge", missing_layer], log,
    ))
    results.append(check_noop_bytes(
        "noop-satisfied-defaults",
        b'{\n  "enabledPlugins": {\n    "pluginA": true,\n    "pluginB": true\n  }\n}',
        ["--defaults", str(FIXTURES / "defaults.json")], log,
    ))

    base = json.loads((FIXTURES / "base.json").read_text())
    defaults = json.loads((FIXTURES / "defaults.json").read_text())
    device = json.loads((FIXTURES / "device.json").read_text())
    satisfied = {"foreign": "café <>&", **defaults, **base, **device}
    satisfied["list"] = list(reversed(satisfied["list"]))
    satisfied_bytes = json.dumps(satisfied, indent=1, ensure_ascii=False).replace("\n", "\r\n").encode()
    results.append(check_noop_bytes(
        "noop-satisfied-real-overlays-and-defaults", satisfied_bytes, BASE_ARGS, log,
    ))

    return results


def check_blank_inputs(log):
    results = []
    for suffix, stdin_bytes in (("empty", b""), ("whitespace", b" \r\n\t")):
        results.append(check_blank_input(
            f"blank-{suffix}-default-output", stdin_bytes, [], b"{}\n", log,
        ))
        results.append(check_blank_input(
            f"blank-{suffix}-no-trailing-newline", stdin_bytes,
            ["--no-trailing-newline"], b"{}", log,
        ))
    return results


def check_typed_overlays(log):
    return [
        check_typed_overlay("overlay-zero-over-false", False, 0, int, 0, log),
        check_typed_overlay("overlay-false-over-zero", 0, False, bool, False, log),
    ]


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

    # Style follows the live file: escaping of < > & and the trailing newline.
    for esc in ("\\u003c", "\\u003e", "\\u0026"):
        if (esc in stdin_text) != (esc in actual):
            log(f"FAIL {name}: {esc} escaping does not match the live file's style")
            return False
    if stdin_text.strip() and stdin_text.endswith("\n") != actual.endswith("\n"):
        log(f"FAIL {name}: trailing newline does not match the live file")
        return False
    if "\u2014" in stdin_text and "\\u2014" in actual:
        log(f"FAIL {name}: non-ASCII characters were escaped")
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
    results.extend(check_noop_preservation(log))
    results.extend(check_blank_inputs(log))
    results.extend(check_typed_overlays(log))
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
