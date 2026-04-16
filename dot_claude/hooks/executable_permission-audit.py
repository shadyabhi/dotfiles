#!/usr/bin/env python3
"""Claude Code PreToolUse hook — logs every tool call with auto-approval status.

Writes JSONL to ~/.claude/logs/permission-audit.jsonl.
Always exits 0 so it never blocks tool execution.
"""

import json
import os
import sys
from datetime import datetime, timezone
from fnmatch import fnmatch
from pathlib import Path

CLAUDE_DIR = Path.home() / ".claude"
LOG_FILE = CLAUDE_DIR / "logs" / "permission-audit.jsonl"
SETTINGS_FILES = [
    CLAUDE_DIR / "settings.json",
    CLAUDE_DIR / "settings.local.json",
]


def load_allow_patterns():
    """Load permission allow patterns from all settings files."""
    patterns = []
    for path in SETTINGS_FILES:
        try:
            data = json.loads(path.read_text())
            patterns.extend(data.get("permissions", {}).get("allow", []))
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            continue
    return patterns


def parse_pattern(pattern):
    """Parse a permission pattern into (tool_glob, arg_glob).

    Examples:
        "WebSearch"              -> ("WebSearch", None)
        "Bash(git status*)"     -> ("Bash", "git status*")
        "mcp__sourcegraph__*"   -> ("mcp__sourcegraph__*", None)
    """
    paren = pattern.find("(")
    if paren == -1:
        return (pattern, None)
    tool = pattern[:paren]
    arg = pattern[paren + 1 :].rstrip(")")
    return (tool, arg)


def get_permission_key(tool_name, tool_input):
    """Extract the permission-matching key from tool input.

    Mirrors Claude Code's permission key construction:
      Bash  -> "command" or "command:description"
      Read/Edit/Write/Glob -> "file_path"
      Grep  -> "pattern"
      Others -> tool_name (for MCP tools, etc.)
    """
    if not isinstance(tool_input, dict):
        return ""

    if tool_name == "Bash":
        cmd = tool_input.get("command", "")
        desc = tool_input.get("description", "")
        return cmd, desc
    if tool_name in ("Read", "Edit", "Write", "NotebookEdit"):
        return tool_input.get("file_path", ""), ""
    if tool_name == "Glob":
        return tool_input.get("pattern", ""), ""
    if tool_name == "Grep":
        return tool_input.get("pattern", ""), ""
    if tool_name == "WebFetch":
        url = tool_input.get("url", "")
        # WebFetch patterns use domain: prefix
        return url, ""
    return "", ""


def is_auto_approved(tool_name, tool_input, allow_patterns):
    """Check if a tool call matches any allow pattern."""
    key, desc = get_permission_key(tool_name, tool_input)

    for pattern in allow_patterns:
        tool_glob, arg_glob = parse_pattern(pattern)

        # Check tool name match
        if not fnmatch(tool_name, tool_glob):
            continue

        # No argument pattern -> tool name match is sufficient
        if arg_glob is None:
            return True

        # Check argument pattern against key and key:description
        if fnmatch(key, arg_glob):
            return True
        if desc and fnmatch(f"{key}:{desc}", arg_glob):
            return True

    return False


def summarize_input(tool_name, tool_input):
    """Create a short summary of the tool input for logging."""
    if not isinstance(tool_input, dict):
        return str(tool_input)[:200]

    if tool_name == "Bash":
        return tool_input.get("command", "")[:200]
    if tool_name in ("Read", "Edit", "Write", "NotebookEdit"):
        return tool_input.get("file_path", "")[:200]
    if tool_name == "Glob":
        return tool_input.get("pattern", "")[:200]
    if tool_name == "Grep":
        return tool_input.get("pattern", "")[:200]
    if tool_name == "WebFetch":
        return tool_input.get("url", "")[:200]
    if tool_name == "WebSearch":
        return tool_input.get("query", "")[:200]
    if tool_name == "Agent":
        return tool_input.get("description", "")[:200]

    # For MCP and other tools, grab the first meaningful field
    for k in ("query", "question", "operation", "skill", "url", "command"):
        if k in tool_input:
            return f"{k}={tool_input[k]}"[:200]

    return json.dumps(tool_input)[:200]


def main():
    try:
        hook_data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        return

    tool_name = hook_data.get("tool_name", "")
    tool_input = hook_data.get("tool_input", {})
    session_id = hook_data.get("session_id", "")
    cwd = hook_data.get("cwd", "")
    permission_mode = hook_data.get("permission_mode", "")

    allow_patterns = load_allow_patterns()
    approved = is_auto_approved(tool_name, tool_input, allow_patterns)

    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "tool": tool_name,
        "input_summary": summarize_input(tool_name, tool_input),
        "auto_approved": approved,
        "session_id": session_id,
        "cwd": cwd,
        "permission_mode": permission_mode,
    }

    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG_FILE, "a") as f:
        f.write(json.dumps(entry) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # Never fail — never block tool execution
    sys.exit(0)
