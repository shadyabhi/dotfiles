#!/usr/bin/env python3
"""Exercise the Codex TOML chezmoi modify script end to end.

Every scenario uses a synthetic source tree and destination. The helper and
template are copied from the adjacent chezmoi source tree, then applied with
the real chezmoi CLI. Runtime pipx cache is shared so the production template
uses its normal tomlkit invocation without reaching the user's config files.

Running this file writes report.txt and sample.diff beside it. The report is
repeatable and the diff shows a representative safe merge.
"""

from __future__ import annotations

import difflib
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path


TEST_DIR = Path(__file__).resolve().parent
MERGE_DIR = TEST_DIR.parent
SOURCE_DIR = MERGE_DIR.parent
HELPER = MERGE_DIR / "merge.py"
OVERLAY = MERGE_DIR / "codex" / "config.toml"
TEMPLATE = SOURCE_DIR / "private_dot_codex" / "modify_config.toml.tmpl"
REPORT = TEST_DIR / "report.txt"
SAMPLE_DIFF = TEST_DIR / "sample.diff"
CHEZMOI = shutil.which("chezmoi")

BASE_LIVE = '''# Existing Codex preferences stay intact.
model = "fixture-model"
tool_output_token_limit = 12000

[mcp_servers.fixture]
url = "https://example.invalid/mcp"
args = ["--mode", "fixture"]

[mcp_servers.fixture.headers]
"X-Fixture" = "kept"

[mcp_servers.fixture."routing.mode"]
"literal.dot" = "keep this quoted dotted key"

[[profiles]]
name = "fixture"
enabled = true

[profiles.options]
quoted_key = "dotted key remains a plain key"
'''

NO_SECTION_LIVE = '''# Keep this hand-maintained comment.
model = "fixture-model"
"literal.dot" = "stay at the root"

[mcp_servers.fixture]
url = "https://example.invalid/mcp"
allowed_tools = ["read", "list"]

[[profiles]]
name = "fixture"
enabled = true
'''

WRONG_VALUE_LIVE = '''# Root comment stays byte-for-byte when possible.
model = "fixture-model"

[computer_use]
# Keep this app-specific setting and comment.
default_app_access = "deny" # replace only the managed value
custom_note = "preserve"

[mcp_servers.fixture]
url = "https://example.invalid/mcp"
'''

EXISTING_SECTION_MISSING_VALUE_LIVE = '''# Existing section and unrelated key remain in place.
model = "fixture-model"

[computer_use]
custom_note = "preserve"

[mcp_servers.fixture]
url = "https://example.invalid/mcp"
'''

ALREADY_ALLOWED_LIVE = '''# No-op should preserve every byte, including spacing.
model    = "fixture-model"

[computer_use]
default_app_access = "allow" # user's comment
custom_note = "preserve"
'''

INVALID_LIVE = 'model = "fixture-model"\ninvalid = [\n'
TYPE_CONFLICT_LIVE = 'computer_use = "keep this scalar"\nmodel = "fixture-model"\n'


class CheckFailure(Exception):
    pass


def check(condition: bool, message: str) -> None:
    if not condition:
        raise CheckFailure(message)


def run_chezmoi_case(
    name: str,
    live_text: str | None,
    *,
    omit_overlay: bool = False,
    overlay_text: str | None = None,
) -> tuple[subprocess.CompletedProcess[str], str | None]:
    """Apply the production modify template in a fully isolated destination."""
    check(CHEZMOI is not None, "chezmoi executable is not on PATH")
    check(HELPER.is_file(), f"merge helper is missing: {HELPER}")
    check(TEMPLATE.is_file(), f"modify template is missing: {TEMPLATE}")
    check(OVERLAY.is_file(), f"TOML overlay is missing: {OVERLAY}")

    with tempfile.TemporaryDirectory(prefix=f"codex-toml-{name}-") as tmp:
        root = Path(tmp)
        source = root / "source"
        destination = root / "destination"
        codex_dir = destination / ".codex"
        source.mkdir()
        codex_dir.mkdir(parents=True)

        helper_target = source / ".toml_merges" / "merge.py"
        template_target = source / "private_dot_codex" / "modify_config.toml.tmpl"
        helper_target.parent.mkdir(parents=True)
        template_target.parent.mkdir(parents=True)
        shutil.copy2(HELPER, helper_target)
        shutil.copy2(TEMPLATE, template_target)
        overlay = source / ".toml_merges" / "codex" / "config.toml"
        if not omit_overlay:
            overlay.parent.mkdir(parents=True, exist_ok=True)
            if overlay_text is None:
                shutil.copy2(OVERLAY, overlay)
            else:
                overlay.write_bytes(overlay_text.encode("utf-8"))

        target = codex_dir / "config.toml"
        if live_text is not None:
            target.write_bytes(live_text.encode("utf-8"))

        config = root / "chezmoi.toml"
        config.write_text("")
        command = [
            CHEZMOI,
            "--source", str(source),
            "--destination", str(destination),
            "--config", str(config),
            "--cache", str(root / "cache"),
            "--persistent-state", str(root / "state.json"),
            "--no-pager",
            "--no-tty",
            "apply",
            "--force",
            str(target),
        ]
        env = os.environ.copy()
        # Leave HOME and pipx cache intact for the provisioned tomlkit runtime;
        # all chezmoi-managed files, state, and cache are rooted in this tempdir.
        proc = subprocess.run(command, capture_output=True, text=True, env=env)
        result = target.read_bytes().decode("utf-8") if target.exists() else None
        return proc, result


def parse_toml(text: str | None, scenario: str) -> dict:
    check(text is not None, f"{scenario}: chezmoi did not create config.toml")
    try:
        return tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        raise CheckFailure(f"{scenario}: merged output is invalid TOML: {exc}") from exc


def test_merge_and_idempotence(name: str, live: str | None, *, check_comments: tuple[str, ...] = ()) -> tuple[str, str]:
    proc, output = run_chezmoi_case(name, live)
    check(proc.returncode == 0, f"{name}: chezmoi apply exited {proc.returncode}: {proc.stderr.strip()}")
    parsed = parse_toml(output, name)
    check(parsed.get("computer_use", {}).get("default_app_access") == "allow", f"{name}: allow policy not set")

    if live is not None:
        before = tomllib.loads(live)
        for key, value in before.items():
            if key == "computer_use":
                for nested_key, nested_value in value.items():
                    if nested_key != "default_app_access":
                        check(parsed["computer_use"].get(nested_key) == nested_value, f"{name}: lost computer_use.{nested_key}")
            else:
                check(parsed.get(key) == value, f"{name}: changed unrelated TOML key {key}")

    for text in check_comments:
        check(output is not None and text in output, f"{name}: comment/text not preserved: {text!r}")

    second, output2 = run_chezmoi_case(f"{name}-second-apply", output)
    check(second.returncode == 0, f"{name}: second apply exited {second.returncode}: {second.stderr.strip()}")
    check(output2 == output, f"{name}: second apply changed output")
    return live or "", output or ""


def test_noop_bytes() -> None:
    proc, output = run_chezmoi_case("already-allowed", ALREADY_ALLOWED_LIVE)
    check(proc.returncode == 0, f"already-allowed: chezmoi apply exited {proc.returncode}: {proc.stderr.strip()}")
    check(output == ALREADY_ALLOWED_LIVE, "already-allowed: no-op rewrote TOML bytes")


def test_invalid_live() -> None:
    proc, output = run_chezmoi_case("invalid-live", INVALID_LIVE)
    check(proc.returncode != 0, "invalid-live: malformed TOML unexpectedly succeeded")
    check("merge.py:" in proc.stderr, "invalid-live: failure did not come from the merge helper")
    check(output == INVALID_LIVE, "invalid-live: malformed input replaced the existing file")


def test_missing_overlay() -> None:
    proc, output = run_chezmoi_case("missing-overlay", BASE_LIVE, omit_overlay=True)
    check(proc.returncode != 0, "missing-overlay: missing managed overlay unexpectedly succeeded")
    check("merge.py:" in proc.stderr, "missing-overlay: failure did not come from the merge helper")
    check(output == BASE_LIVE, "missing-overlay: missing overlay replaced the existing file")


def test_invalid_overlay() -> None:
    proc, output = run_chezmoi_case(
        "invalid-overlay",
        BASE_LIVE,
        overlay_text='[computer_use\ndefault_app_access = "allow"\n',
    )
    check(proc.returncode != 0, "invalid-overlay: malformed overlay unexpectedly succeeded")
    check("merge.py:" in proc.stderr, "invalid-overlay: failure did not come from the merge helper")
    check(output == BASE_LIVE, "invalid-overlay: malformed overlay replaced the existing file")


def test_type_conflict() -> None:
    proc, output = run_chezmoi_case("type-conflict", TYPE_CONFLICT_LIVE)
    check(proc.returncode != 0, "type-conflict: incompatible computer_use value unexpectedly succeeded")
    check("merge.py:" in proc.stderr, "type-conflict: failure did not come from the merge helper")
    check(output == TYPE_CONFLICT_LIVE, "type-conflict: incompatible overlay deleted existing data")


def test_newline_conventions() -> None:
    no_final_newline = 'model = "fixture-model"'
    proc, output = run_chezmoi_case("no-final-newline", no_final_newline)
    check(proc.returncode == 0, f"no-final-newline: apply failed: {proc.stderr.strip()}")
    check(output is not None and not output.endswith("\n"), "no-final-newline: added a trailing newline")
    check(parse_toml(output, "no-final-newline").get("computer_use", {}).get("default_app_access") == "allow", "no-final-newline: allow policy not set")

    crlf = '# CRLF fixture\r\nmodel = "fixture-model"\r\n'
    proc, output = run_chezmoi_case("crlf", crlf)
    check(proc.returncode == 0, f"crlf: apply failed: {proc.stderr.strip()}")
    check(output is not None and output.endswith("\r\n"), "crlf: trailing CRLF was not preserved")
    check(output is not None and all(output[i - 1] == "\r" for i, char in enumerate(output) if char == "\n" and i > 0), "crlf: line endings were normalized")
    check(parse_toml(output, "crlf").get("computer_use", {}).get("default_app_access") == "allow", "crlf: allow policy not set")


def main() -> int:
    results: list[tuple[str, bool, str]] = []
    sample_before = ""
    sample_after = ""

    cases = [
        ("add-missing-section", NO_SECTION_LIVE, ("# Keep this hand-maintained comment.", '"literal.dot" = "stay at the root"')),
        ("replace-existing-value", WRONG_VALUE_LIVE, ("# Root comment stays byte-for-byte when possible.", "# Keep this app-specific setting and comment.", 'default_app_access = "allow"', 'custom_note = "preserve"')),
        ("add-value-to-existing-section", EXISTING_SECTION_MISSING_VALUE_LIVE, ("# Existing section and unrelated key remain in place.", 'custom_note = "preserve"')),
        ("create-empty-config", None, ()),
        ("create-empty-file", "", ()),
        ("preserve-nested-tables-and-arrays", BASE_LIVE, ("[[profiles]]", '[mcp_servers.fixture.headers]', '"X-Fixture" = "kept"', '[mcp_servers.fixture."routing.mode"]', '"literal.dot" = "keep this quoted dotted key"')),
    ]

    for name, live, comments in cases:
        try:
            before, after = test_merge_and_idempotence(name, live, check_comments=comments)
            results.append((name, True, ""))
            if name == "replace-existing-value":
                sample_before, sample_after = before, after
        except Exception as exc:  # accumulate independent E2E results
            results.append((name, False, str(exc)))

    for name, test in [
        ("already-allowed-byte-noop", test_noop_bytes),
        ("malformed-live-keeps-target", test_invalid_live),
        ("missing-overlay-keeps-target", test_missing_overlay),
        ("malformed-overlay-keeps-target", test_invalid_overlay),
        ("table-type-conflict-keeps-target", test_type_conflict),
        ("newline-conventions", test_newline_conventions),
    ]:
        try:
            test()
            results.append((name, True, ""))
        except Exception as exc:
            results.append((name, False, str(exc)))

    report_lines = ["Codex chezmoi TOML merge E2E", "", f"chezmoi: {CHEZMOI or 'not found'}", f"python: {sys.version.split()[0]}", ""]
    report_lines.extend(f"{'PASS' if ok else 'FAIL'} {name}{': ' + detail if detail else ''}" for name, ok, detail in results)
    passed = sum(ok for _, ok, _ in results)
    failed = len(results) - passed
    report_lines.extend(["", f"Result: {passed} passed, {failed} failed"])
    report = "\n".join(report_lines) + "\n"
    REPORT.write_text(report)

    diff = "".join(difflib.unified_diff(
        sample_before.splitlines(keepends=True),
        sample_after.splitlines(keepends=True),
        fromfile="before/config.toml",
        tofile="after/config.toml",
        n=0,
    ))
    SAMPLE_DIFF.write_text(diff or "No change in representative fixture.\n")
    print(report, end="")
    print(f"Artifacts: {REPORT} and {SAMPLE_DIFF}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
