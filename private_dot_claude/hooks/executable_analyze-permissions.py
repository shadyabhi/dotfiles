#!/usr/bin/env python3
"""Analyze the permission audit log and suggest new auto-approve rules.

Usage:
    python3 ~/.claude/hooks/analyze-permissions.py [--days N] [--top N] [--json]
"""

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

LOG_FILE = Path.home() / ".claude" / "logs" / "permission-audit.jsonl"


def load_entries(since=None):
    """Load audit log entries, optionally filtering by date."""
    entries = []
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not LOG_FILE.exists():
        return entries
    for line in LOG_FILE.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if since:
            ts = datetime.fromisoformat(entry["ts"])
            if ts < since:
                continue
        entries.append(entry)
    return entries


def generalize_bash_command(cmd):
    """Generalize a bash command into a permission pattern.

    "git diff HEAD~1" -> "git diff*"
    "npm run build"   -> "npm run*"
    "python3 foo.py"  -> "python3*"
    """
    parts = cmd.strip().split()
    if not parts:
        return cmd

    # For common tools, keep first two tokens
    two_token_prefixes = {
        "git", "npm", "npx", "go", "docker", "cargo", "pip", "pip3",
        "gh", "make", "gradle", "./gradlew", "newt", "kubectl",
        "python3", "python", "node", "java", "curl", "metatron",
        "uv", "tox", "chezmoi",
    }
    if parts[0] in two_token_prefixes and len(parts) > 1:
        return f"{parts[0]} {parts[1]}*"

    return f"{parts[0]}*"


def suggest_pattern(tool, input_summary):
    """Suggest a permission pattern for a tool call."""
    if tool == "Bash":
        prefix = generalize_bash_command(input_summary)
        return f"Bash({prefix})"
    if tool in ("Edit", "Write", "Read", "NotebookEdit"):
        # Suggest based on directory
        path = input_summary
        if "/" in path:
            directory = "/".join(path.split("/")[:-1])
            return f"{tool}({directory}/*)"
        return tool
    if tool == "WebFetch":
        # Extract domain
        match = re.search(r"https?://([^/]+)", input_summary)
        if match:
            return f"WebFetch(domain:{match.group(1)})"
        return "WebFetch"
    if tool.startswith("mcp__"):
        return tool
    return tool


def analyze(entries):
    """Analyze entries and produce a report."""
    total = len(entries)
    approved = sum(1 for e in entries if e.get("auto_approved"))
    denied = total - approved

    # Group non-approved by suggested pattern
    pattern_counts = Counter()
    pattern_examples = defaultdict(list)

    for entry in entries:
        if entry.get("auto_approved"):
            continue
        tool = entry["tool"]
        summary = entry.get("input_summary", "")
        pattern = suggest_pattern(tool, summary)
        pattern_counts[pattern] += 1
        if len(pattern_examples[pattern]) < 3:
            pattern_examples[pattern].append(summary[:100])

    # Group by tool for overview
    tool_counts = Counter()
    tool_denied = Counter()
    for entry in entries:
        tool_counts[entry["tool"]] += 1
        if not entry.get("auto_approved"):
            tool_denied[entry["tool"]] += 1

    return {
        "total": total,
        "auto_approved": approved,
        "needed_approval": denied,
        "approval_rate": f"{approved / total * 100:.1f}%" if total else "N/A",
        "by_tool": {
            tool: {"total": tool_counts[tool], "needed_approval": tool_denied.get(tool, 0)}
            for tool in sorted(tool_counts, key=tool_counts.get, reverse=True)
        },
        "suggested_patterns": [
            {
                "pattern": pattern,
                "count": count,
                "examples": pattern_examples[pattern],
            }
            for pattern, count in pattern_counts.most_common()
        ],
    }


def print_report(report):
    """Print a human-readable report."""
    print("=" * 60)
    print("  PERMISSION AUDIT REPORT")
    print("=" * 60)
    print()
    print(f"  Total tool calls:     {report['total']}")
    print(f"  Auto-approved:        {report['auto_approved']}")
    print(f"  Needed approval:      {report['needed_approval']}")
    print(f"  Auto-approval rate:   {report['approval_rate']}")
    print()

    if report["by_tool"]:
        print("-" * 60)
        print("  BY TOOL")
        print("-" * 60)
        for tool, counts in report["by_tool"].items():
            na = counts["needed_approval"]
            marker = " ***" if na > 0 else ""
            print(f"  {tool:<30} {counts['total']:>5} total, {na:>5} unapproved{marker}")
        print()

    if report["suggested_patterns"]:
        print("-" * 60)
        print("  SUGGESTED PERMISSION PATTERNS (by frequency)")
        print("-" * 60)
        print()
        for item in report["suggested_patterns"]:
            print(f"  \"{item['pattern']}\"  ({item['count']}x)")
            for ex in item["examples"]:
                print(f"    e.g. {ex}")
            print()

        # Print copy-pasteable JSON array
        print("-" * 60)
        print("  COPY-PASTE FOR settings.json permissions.allow:")
        print("-" * 60)
        patterns = [item["pattern"] for item in report["suggested_patterns"] if item["count"] >= 2]
        if patterns:
            for p in patterns:
                print(f'      "{p}",')
        else:
            print("  (No patterns with 2+ occurrences yet — keep collecting data)")
    print()


def main():
    parser = argparse.ArgumentParser(description="Analyze Claude Code permission audit log")
    parser.add_argument("--days", type=int, default=7, help="Only analyze last N days (0=all, default: 7)")
    parser.add_argument("--top", type=int, default=50, help="Show top N suggestions (default: 50)")
    parser.add_argument("--all", action="store_true", help="Analyze all time (overrides --days)")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args()

    since = None
    if not args.all and args.days > 0:
        since = datetime.now(timezone.utc) - timedelta(days=args.days)

    entries = load_entries(since)
    if not entries:
        print("No audit log entries found.", file=sys.stderr)
        print(f"Log file: {LOG_FILE}", file=sys.stderr)
        sys.exit(1)

    report = analyze(entries)

    if args.top:
        report["suggested_patterns"] = report["suggested_patterns"][: args.top]

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_report(report)


if __name__ == "__main__":
    main()
