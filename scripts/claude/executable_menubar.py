#!/usr/bin/env python3
"""Emit JSON describing claude/recon sessions.

Output:
    { "summary": "🔔0 🤔1 💤2",
      "details": [ { project_name, room_id, session_name, status, pane_target, ... }, ... ] }

Usage:
    menubar.py            # full JSON
    menubar.py summary    # just the summary string

Per-session "session_name" is the latest /rename value pulled from
~/.claude/projects/<encoded-cwd>/<session_id>.jsonl (null if unset).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
RECON = os.environ.get("RECON", os.path.join(HOME, ".cargo/bin/recon"))
SOCKET = f"/private/tmp/tmux-{os.getuid()}/default"
CT_RE = re.compile(rb'"customTitle":"([^"]*)"')


def tmux_pid() -> str:
    try:
        out = subprocess.check_output(
            ["lsof", "-Fp", SOCKET], stderr=subprocess.DEVNULL, text=True
        )
        for line in out.splitlines():
            if line.startswith("p"):
                return line[1:]
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return "1"


def run_recon() -> dict:
    env = {
        **os.environ,
        "PATH": "/opt/homebrew/bin:" + os.environ.get("PATH", ""),
        "TMUX": f"{SOCKET},{tmux_pid()},0",
    }
    try:
        out = subprocess.check_output(
            [RECON, "json"], env=env, stderr=subprocess.DEVNULL, text=True
        )
        return json.loads(out)
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        return {}


def encoded_cwd(cwd: str) -> str:
    return re.sub(r"[/.]", "-", cwd)


def session_name(session: dict) -> str | None:
    cwd, sid = session.get("cwd"), session.get("session_id")
    if not cwd or not sid:
        return None
    path = os.path.join(HOME, ".claude", "projects", encoded_cwd(cwd), f"{sid}.jsonl")
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    matches = CT_RE.findall(data)
    return matches[-1].decode("utf-8", "replace") if matches else None


STATUS_ORDER = {"Input": 0, "Working": 1, "Idle": 2}


def build_payload() -> dict:
    sessions = run_recon().get("sessions") or []
    sessions.sort(key=lambda s: (
        STATUS_ORDER.get(s.get("status"), 99),
        s.get("project_name") or "",
    ))
    blocked = sum(1 for s in sessions if s.get("status") == "Input")
    running = sum(1 for s in sessions if s.get("status") == "Working")
    idle = sum(1 for s in sessions if s.get("status") == "Idle")
    details = [
        {
            "project_name": s.get("project_name"),
            "room_id": s.get("room_id"),
            "session_name": session_name(s),
            "status": s.get("status"),
            "pane_target": s.get("pane_target"),
            "session_id": s.get("session_id"),
            "cwd": s.get("cwd"),
            "branch": s.get("branch"),
            "model_display": s.get("model_display"),
            "context_display": s.get("context_display"),
        }
        for s in sessions
    ]
    return {
        "summary": f"🔔{blocked} 🤔{running} 💤{idle}",
        "details": details,
    }


def main() -> None:
    payload = build_payload()
    if len(sys.argv) > 1 and sys.argv[1] == "summary":
        print(payload["summary"])
    else:
        json.dump(payload, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")


if __name__ == "__main__":
    main()
