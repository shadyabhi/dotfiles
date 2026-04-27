#!/usr/bin/env python3
"""Emit JSON describing claude sessions read directly from ~/.claude/sessions/.

Output:
    { "summary": "🔔0 🤔1 💤2",
      "details": [ { project_name, session_name, status, pane_target, ... }, ... ] }

Usage:
    menubar.py            # full JSON
    menubar.py summary    # just the summary string
"""

from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
SESSIONS_DIR = os.path.join(HOME, ".claude", "sessions")
PROJECTS_DIR = os.path.join(HOME, ".claude", "projects")
SOCKET = f"/private/tmp/tmux-{os.getuid()}/default"
TMUX_BIN = "/opt/homebrew/bin/tmux"
CT_RE = re.compile(rb'"customTitle":"([^"]*)"')

# Map raw status from session file to display bucket.
STATUS_MAP = {
    "busy": "Working",
    "working": "Working",
    "running": "Working",
    "idle": "Idle",
    "ready": "Idle",
    "input": "Input",
    "waiting": "Input",
    "waiting_for_input": "Input",
    "blocked": "Input",
    "needs_input": "Input",
}
STATUS_ORDER = {"Input": 0, "Working": 1, "Idle": 2}


def normalize_status(raw: str | None) -> str:
    if not raw:
        return "Idle"
    return STATUS_MAP.get(raw.lower(), "Idle")


def load_sessions() -> list[dict]:
    out = []
    for path in glob.glob(os.path.join(SESSIONS_DIR, "*.json")):
        try:
            with open(path, "rb") as f:
                out.append(json.loads(f.read()))
        except (OSError, json.JSONDecodeError):
            continue
    return out


def pid_ppid_map() -> dict[int, int]:
    try:
        out = subprocess.check_output(
            ["ps", "-Aco", "pid=,ppid="], text=True, stderr=subprocess.DEVNULL
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {}
    m = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            try:
                m[int(parts[0])] = int(parts[1])
            except ValueError:
                pass
    return m


def tmux_pane_map() -> dict[int, str]:
    try:
        out = subprocess.check_output(
            [TMUX_BIN, "-S", SOCKET, "list-panes", "-a",
             "-F", "#{pane_pid}|#{session_name}:#{window_index}.#{pane_index}"],
            text=True, stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {}
    res = {}
    for line in out.splitlines():
        if "|" not in line:
            continue
        p, t = line.split("|", 1)
        try:
            res[int(p)] = t
        except ValueError:
            pass
    return res


def pane_for(pid: int, ppid: dict[int, int], panes: dict[int, str]) -> str | None:
    seen = set()
    while pid and pid not in seen:
        seen.add(pid)
        if pid in panes:
            return panes[pid]
        pid = ppid.get(pid, 0)
    return None


def encoded_cwd(cwd: str) -> str:
    return re.sub(r"[/.]", "-", cwd)


def session_name(cwd: str | None, sid: str | None) -> str | None:
    if not cwd or not sid:
        return None
    path = os.path.join(PROJECTS_DIR, encoded_cwd(cwd), f"{sid}.jsonl")
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    matches = CT_RE.findall(data)
    return matches[-1].decode("utf-8", "replace") if matches else None


def build_payload() -> dict:
    raw = load_sessions()
    ppid = pid_ppid_map()
    panes = tmux_pane_map()

    details = []
    for s in raw:
        cwd = s.get("cwd")
        sid = s.get("sessionId")
        pid = s.get("pid") or 0
        status = normalize_status(s.get("status"))
        details.append({
            "project_name": os.path.basename(cwd) if cwd else None,
            "session_name": session_name(cwd, sid),
            "status": status,
            "pane_target": pane_for(int(pid), ppid, panes) if pid else None,
            "session_id": sid,
            "cwd": cwd,
            "pid": pid,
            "model_display": s.get("version") or "",
            "context_display": s.get("kind") or "",
        })

    details.sort(key=lambda s: (
        STATUS_ORDER.get(s["status"], 99),
        s.get("project_name") or "",
    ))
    blocked = sum(1 for s in details if s["status"] == "Input")
    running = sum(1 for s in details if s["status"] == "Working")
    idle = sum(1 for s in details if s["status"] == "Idle")
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
