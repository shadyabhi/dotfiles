#!/usr/bin/env python3
"""Emit JSON describing local AI agent sessions.

Output:
    { "summary": "🔔0 🤔1 💤2",
      "details": [ { agent, project_name, session_name, status, pane_target, ... }, ... ] }

Usage:
    menubar.py            # full JSON
    menubar.py summary    # just the summary string
"""

from __future__ import annotations

import glob
import json
import os
import re
import sqlite3
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from typing import Any

HOME = os.path.expanduser("~")
CLAUDE_SESSIONS_DIR = os.environ.get(
    "CLAUDE_SESSIONS_DIR", os.path.join(HOME, ".claude", "sessions")
)
CLAUDE_PROJECTS_DIR = os.environ.get(
    "CLAUDE_PROJECTS_DIR", os.path.join(HOME, ".claude", "projects")
)
CODEX_HOME = os.environ.get("CODEX_HOME", os.path.join(HOME, ".codex"))
CODEX_STATE_DB = os.environ.get("CODEX_STATE_DB", os.path.join(CODEX_HOME, "state_5.sqlite"))
SOCKET = f"/private/tmp/tmux-{os.getuid()}/default"
TMUX_BIN = os.environ.get("TMUX_BIN", "/opt/homebrew/bin/tmux")
CT_RE = re.compile(rb'"customTitle":"([^"]*)"')
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
BOX_CHARS = "│╭╮╰╯─━┃┌┐└┘┏┓┗┛║╔╗╚╝═╠╣╦╩╬▌▐█"

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


@dataclass(frozen=True)
class TmuxPane:
    pid: int
    target: str
    command: str
    cwd: str
    title: str


def normalize_status(raw: str | None) -> str:
    if not raw:
        return "Idle"
    return STATUS_MAP.get(raw.lower(), "Idle")


def run_text(args: list[str]) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, FileNotFoundError, PermissionError, OSError):
        return ""


def load_json_file(path: str) -> Any:
    try:
        with open(path, "rb") as f:
            return json.loads(f.read())
    except (OSError, json.JSONDecodeError):
        return None


def load_jsonl(path: str) -> list[dict]:
    try:
        with open(path, "rb") as f:
            lines = f.readlines()
    except OSError:
        return []

    events = []
    for line in lines:
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            events.append(value)
    return events


def epoch_ms_from_iso(value: str | None) -> int | None:
    if not value:
        return None
    try:
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return None


def epoch_ms(value: int | None) -> int | None:
    return value * 1000 if value else None


def pid_ppid_map() -> dict[int, int]:
    out = run_text(["ps", "-Aco", "pid=,ppid="])
    m = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            try:
                m[int(parts[0])] = int(parts[1])
            except ValueError:
                pass
    return m


def process_maps() -> tuple[dict[int, int], dict[int, str], dict[int, list[int]]]:
    out = run_text(["ps", "-Aco", "pid=,ppid=,command="])
    ppid, command, children = {}, {}, defaultdict(list)
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 2:
            continue
        try:
            pid = int(parts[0])
            parent = int(parts[1])
        except ValueError:
            continue
        ppid[pid] = parent
        command[pid] = parts[2] if len(parts) > 2 else ""
        children[parent].append(pid)
    return ppid, command, dict(children)


def tmux_panes() -> list[TmuxPane]:
    out = run_text([
        TMUX_BIN,
        "-S",
        SOCKET,
        "list-panes",
        "-a",
        "-F",
        "#{pane_pid}|#{session_name}:#{window_index}.#{pane_index}|"
        "#{pane_current_command}|#{pane_current_path}|#{pane_title}",
    ])
    panes = []
    for line in out.splitlines():
        parts = line.split("|", 4)
        if len(parts) != 5:
            continue
        try:
            pid = int(parts[0])
        except ValueError:
            continue
        panes.append(TmuxPane(pid, parts[1], parts[2], parts[3], parts[4]))
    return panes


def tmux_pane_map(panes: list[TmuxPane]) -> dict[int, str]:
    return {pane.pid: pane.target for pane in panes}


def pane_for(pid: int, ppid: dict[int, int], panes: dict[int, str]) -> str | None:
    seen = set()
    while pid and pid not in seen:
        seen.add(pid)
        if pid in panes:
            return panes[pid]
        pid = ppid.get(pid, 0)
    return None


def process_tree_has(pid: int, commands: dict[int, str], children: dict[int, list[int]], needle: str) -> bool:
    stack, seen = [pid], set()
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        if needle in (commands.get(cur) or "").lower():
            return True
        stack.extend(children.get(cur, []))
    return False


def encoded_cwd(cwd: str) -> str:
    return re.sub(r"[/.]", "-", cwd)


def claude_session_name(cwd: str | None, sid: str | None) -> str | None:
    if not cwd or not sid:
        return None
    path = os.path.join(CLAUDE_PROJECTS_DIR, encoded_cwd(cwd), f"{sid}.jsonl")
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    matches = CT_RE.findall(data)
    return matches[-1].decode("utf-8", "replace") if matches else None


def collect_claude(ppid: dict[int, int], pane_by_pid: dict[int, str]) -> list[dict]:
    details = []
    for path in glob.glob(os.path.join(CLAUDE_SESSIONS_DIR, "*.json")):
        s = load_json_file(path)
        if not isinstance(s, dict):
            continue
        cwd = s.get("cwd")
        sid = s.get("sessionId")
        pid = s.get("pid") or 0
        status = normalize_status(s.get("status"))
        details.append({
            "agent": "Claude",
            "project_name": os.path.basename(cwd) if cwd else None,
            "session_name": claude_session_name(cwd, sid),
            "status": status,
            "pane_target": pane_for(int(pid), ppid, pane_by_pid) if pid else None,
            "session_id": sid,
            "cwd": cwd,
            "pid": pid,
            "model_display": s.get("version") or "",
            "context_display": s.get("kind") or "",
            "started_at": s.get("startedAt"),
            "updated_at": s.get("updatedAt"),
        })
    return details


def codex_rows() -> list[dict]:
    if not os.path.exists(CODEX_STATE_DB):
        return []
    try:
        conn = sqlite3.connect(f"file:{CODEX_STATE_DB}?mode=ro", uri=True, timeout=0.1)
        conn.row_factory = sqlite3.Row
        try:
            rows = conn.execute(
                """
                select id, rollout_path, created_at, updated_at, cwd, title, model,
                       reasoning_effort, cli_version, agent_nickname, agent_role, archived
                from threads
                where archived = 0
                order by updated_at desc
                """
            ).fetchall()
        finally:
            conn.close()
    except sqlite3.Error:
        return []
    return [dict(row) for row in rows]


def preview_text(value: str | None, limit: int = 220) -> str | None:
    if not value:
        return None
    value = re.sub(r"\s+", " ", value).strip()
    if not value:
        return None
    if len(value) > limit:
        value = value[:limit - 3] + "..."
    return value


def codex_turn_state(rollout_path: str | None) -> tuple[bool, int | None, str | None]:
    latest_started: str | None = None
    latest_started_at: int | None = None
    completed: set[str] = set()
    last_user_message: str | None = None

    for event in load_jsonl(rollout_path or ""):
        ts = epoch_ms_from_iso(event.get("timestamp"))
        if event.get("type") != "event_msg":
            continue
        payload = event.get("payload") or {}
        typ = payload.get("type")
        turn_id = payload.get("turn_id")
        if typ == "task_started":
            latest_started = turn_id
            latest_started_at = ts
        elif typ == "task_complete" and turn_id:
            completed.add(turn_id)
        elif typ == "user_message":
            last_user_message = payload.get("message")

    return (
        bool(latest_started and latest_started not in completed),
        latest_started_at,
        preview_text(last_user_message),
    )


def codex_live_panes(rows: list[dict], panes: list[TmuxPane], commands: dict[int, str], children: dict[int, list[int]]) -> dict[str, str]:
    by_cwd: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        cwd = row.get("cwd")
        if cwd:
            by_cwd[cwd].append(row)
    for matches in by_cwd.values():
        matches.sort(key=lambda r: r.get("updated_at") or 0, reverse=True)

    matched: dict[str, str] = {}
    used_threads: set[str] = set()
    for pane in panes:
        if "codex" not in pane.command.lower() and not process_tree_has(pane.pid, commands, children, "codex"):
            continue
        candidates = by_cwd.get(pane.cwd, [])
        for row in candidates:
            thread_id = row.get("id")
            if thread_id and thread_id not in used_threads:
                matched[thread_id] = pane.target
                used_threads.add(thread_id)
                break
    return matched


def collect_codex(panes: list[TmuxPane], commands: dict[int, str], children: dict[int, list[int]]) -> list[dict]:
    rows = codex_rows()
    live_panes = codex_live_panes(rows, panes, commands, children)
    details = []
    for row in rows:
        thread_id = row.get("id")
        pane_target = live_panes.get(thread_id)
        running, started_at, prompt_preview = codex_turn_state(row.get("rollout_path"))
        if not pane_target:
            status = "Idle"
        elif running:
            status = "Working"
        else:
            status = "Idle"

        cwd = row.get("cwd")
        title = row.get("title") or row.get("agent_nickname") or thread_id
        context = row.get("reasoning_effort") or row.get("cli_version") or ""
        if row.get("agent_role"):
            context = f"{row.get('agent_role')} · {context}" if context else row.get("agent_role")
        details.append({
            "agent": "Codex",
            "project_name": os.path.basename(cwd) if cwd else None,
            "session_name": title,
            "status": status,
            "pane_target": pane_target,
            "session_id": thread_id,
            "cwd": cwd,
            "pid": None,
            "model_display": row.get("model") or "",
            "context_display": context,
            "started_at": started_at or epoch_ms(row.get("created_at")),
            "updated_at": epoch_ms(row.get("updated_at")),
            "prompt_preview": prompt_preview,
        })
    return details


def tmux_capture(target: str, lines: int = 50) -> str:
    return run_text([
        TMUX_BIN, "-S", SOCKET, "capture-pane", "-p",
        "-t", target, "-S", f"-{lines}", "-E", "-1",
    ])


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
    joined = "  ·  ".join(tail)
    return preview_text(joined)


def build_payload() -> dict:
    panes = tmux_panes()
    ppid = pid_ppid_map()
    proc_ppid, commands, children = process_maps()
    if proc_ppid:
        ppid = proc_ppid
    pane_by_pid = tmux_pane_map(panes)

    details = []
    details.extend(collect_claude(ppid, pane_by_pid))
    details.extend(collect_codex(panes, commands, children))

    details.sort(key=lambda s: (
        STATUS_ORDER.get(s["status"], 99),
        s.get("agent") or "",
        s.get("project_name") or "",
        -(s.get("updated_at") or 0),
    ))
    for d in details:
        if d.get("status") == "Input" and not d.get("prompt_preview"):
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
