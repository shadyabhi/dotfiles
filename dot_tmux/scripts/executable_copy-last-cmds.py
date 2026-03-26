#!/usr/bin/env python3
"""Show last N commands in fzf, preview combined output, copy selection to clipboard."""

import subprocess
import sys
import os
import re
import tempfile
import shutil

PROMPT_PATTERNS = [r'^➤ ', r'^❯ ', r'^\$ ', r'^% ', r'^> ']

def run(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout

def detect_prompt(lines):
    for pat in PROMPT_PATTERNS:
        if sum(1 for l in lines if re.search(pat, l)) >= 2:
            return pat
    return PROMPT_PATTERNS[0]

def main():
    pane_id = sys.argv[1]
    output = run(f"tmux capture-pane -p -t {pane_id} -S -5000")
    lines = output.splitlines()

    prompt_pat = detect_prompt(lines)

    # Detect multi-line prompt prefix (e.g. "→ ~/.tmux" before "➤ cmd")
    # Look for lines like "→ " or "➜ " that consistently appear before the prompt
    prefix_pat = r'^[→➜] '

    # Split into blocks at prompt lines
    blocks = []
    current = []
    for line in lines:
        if re.search(prompt_pat, line):
            if current:
                blocks.append("\n".join(current))
            current = [line]
        # If we see the prompt prefix and we already have a block, end it
        elif re.search(prefix_pat, line) and current:
            blocks.append("\n".join(current))
            current = []
        elif current:
            current.append(line)
    if current:
        blocks.append("\n".join(current))

    # Filter out blocks that are just a prompt with no real output
    def has_content(block):
        blines = block.splitlines()
        return any(l.strip() for l in blines[1:])
    blocks = [b for b in blocks if has_content(b)]

    # Strip trailing blank lines from each block
    def strip_trailing(block):
        blines = block.splitlines()
        while blines and not blines[-1].strip():
            blines.pop()
        return "\n".join(blines)
    blocks = [strip_trailing(b) for b in blocks]

    if not blocks:
        print("No commands found in this pane.")
        input()
        sys.exit(1)

    total = len(blocks)
    tmpdir = tempfile.mkdtemp()

    try:
        # Write preview files
        for i in range(1, total + 1):
            with open(os.path.join(tmpdir, f"preview_{i}"), "w") as f:
                f.write("\n".join(blocks[-i:]) + "\n")

        # Build fzf input
        entries = "\n".join(
            f"Last {i} cmd{'s' if i > 1 else ''}" for i in range(1, total + 1)
        )

        result = subprocess.run(
            ["fzf", "--reverse", "--prompt=Copy> ",
             f"--preview=echo {{}} | grep -oE '[0-9]+' | head -1 | xargs -I% cat {tmpdir}/preview_%",
             "--preview-window=down:70%:wrap"],
            input=entries, capture_output=True, text=True,
        )

        if result.returncode == 0 and result.stdout.strip():
            n = int(re.search(r'\d+', result.stdout).group())
            preview = os.path.join(tmpdir, f"preview_{n}")
            subprocess.run(["pbcopy"], input=open(preview).read(), text=True)
            print(f"Copied last {n} command{'s' if n > 1 else ''} to clipboard!")
            import time; time.sleep(0.5)
    finally:
        shutil.rmtree(tmpdir)

if __name__ == "__main__":
    main()
