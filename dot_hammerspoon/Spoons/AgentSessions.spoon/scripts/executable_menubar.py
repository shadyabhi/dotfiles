#!/usr/bin/env python3
"""Emit JSON describing local AI agent sessions, sourced from `workmux status --json`.

Output:
    { "summary": "🔔0 🤔1 💤2",
      "details": [ { agent, project_name, session_name, status, pane_target, ... }, ... ] }

Usage:
    menubar.py            # full JSON
    menubar.py summary    # just the summary string
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

SOCKET = f"/private/tmp/tmux-{os.getuid()}/default"
TMUX_BIN = os.environ.get("TMUX_BIN", "/opt/homebrew/bin/tmux")
WORKMUX_BIN = os.environ.get("WORKMUX_BIN", "/opt/homebrew/bin/workmux")
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
BOX_CHARS = "│╭╮╰╯─━┃┌┐└┘┏┓┗┛║╔╗╚╝═╠╣╦╩╬▌▐█"

# Map workmux's `status` field to the display bucket the panel groups by.
STATUS_MAP = {"working": "Working", "waiting": "Input", "done": "Idle"}
STATUS_ORDER = {"Input": 0, "Working": 1, "Idle": 2}


def run_text(args: list[str]) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, FileNotFoundError, PermissionError, OSError):
        return ""


def tmux_capture(target: str, lines: int = 60) -> str:
    return run_text([
        TMUX_BIN, "-S", SOCKET, "capture-pane", "-p",
        "-t", target, "-S", f"-{lines}", "-E", "-1",
    ])


def preview_text(value: str | None, limit: int = 220) -> str | None:
    if not value:
        return None
    value = re.sub(r"\s+", " ", value).strip()
    if not value:
        return None
    if len(value) > limit:
        value = value[:limit - 3] + "..."
    return value


def waiting_preview(target: str | None) -> str | None:
    if not target:
        return None
    text = tmux_capture(target, 60)
    if not text:
        return None
    text = ANSI_RE.sub("", text)
    stripper = str.maketrans("", "", BOX_CHARS)
    cleaned = []
    for raw in text.splitlines():
        line = raw.translate(stripper).strip()
        if line:
            cleaned.append(line)
    if not cleaned:
        return None
    tail = cleaned[-5:]
    return preview_text("  ·  ".join(tail))


def workmux_agents() -> list[dict]:
    out = run_text([WORKMUX_BIN, "status", "--all", "--json"])
    if not out:
        return []
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return []
    return data.get("agents") or []


def to_detail(agent: dict) -> dict:
    workdir = agent.get("workdir")
    project = agent.get("project") or (os.path.basename(workdir) if workdir else None)
    worktree = agent.get("worktree")
    branch = agent.get("branch")
    title = agent.get("title") or branch or worktree
    pane_id = agent.get("pane_id")
    elapsed = agent.get("elapsed_secs")
    updated_ts = agent.get("updated_ts")

    return {
        "agent": (agent.get("agent_kind") or "Agent").capitalize(),
        "project_name": project or worktree,
        "session_name": title,
        "worktree": worktree,
        "branch": branch,
        "window_name": agent.get("window_name"),
        "status": STATUS_MAP.get((agent.get("status") or "").lower(), "Idle"),
        "pane_target": pane_id,
        "session_id": pane_id,
        "cwd": workdir,
        "pid": None,
        "elapsed_secs": elapsed,
        "started_at": (updated_ts - (elapsed or 0)) * 1000 if updated_ts else None,
        "updated_at": updated_ts * 1000 if updated_ts else None,
    }


def build_payload() -> dict:
    details = [to_detail(a) for a in workmux_agents()]
    details.sort(key=lambda s: (
        STATUS_ORDER.get(s["status"], 99),
        s.get("agent") or "",
        s.get("project_name") or "",
        -(s.get("updated_at") or 0),
    ))
    for d in details:
        if d["status"] == "Input":
            d["prompt_preview"] = waiting_preview(d.get("pane_target"))

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
