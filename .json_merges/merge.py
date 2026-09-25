#!/usr/bin/env python3
"""Generic chezmoi modify-script backend.

Reads the live file's current content on stdin, layers plain-JSON files on
top of it, writes the merged result to stdout. See the "Readable JSON
overlays" plan for the contract.

  --defaults FILE  fill-missing-only layer (optional, applied first): fills
                    a path only if the live file doesn't already have it.
  --merge FILE      deep-merge layer, overlay wins on conflicts (repeatable,
                    applied in the order given; missing files are skipped).
                    Objects merge recursively; scalars are overwritten
                    (including false/0); arrays are unioned by deep
                    equality, live items first in live order, then overlay
                    items not already present, in overlay order.
  --no-trailing-newline  omit the trailing newline chezmoi would otherwise get
"""
import argparse
import json
import sys
from pathlib import Path


def load_json(desc, text):
    if not text.strip():
        return {}
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"merge.py: {desc} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)


def deepfill(a, d):
    """Fill paths missing from `a` with `d`'s value, recursing into objects.
    Never overwrites a value `a` already has."""
    if isinstance(a, dict) and isinstance(d, dict):
        for k, v in d.items():
            if k not in a:
                a[k] = v
            elif isinstance(a[k], dict) and isinstance(v, dict):
                deepfill(a[k], v)
    return a


def deepmerge(a, b):
    """Recursively merge `b` onto `a`; `b` wins on scalars/objects (including
    false/0), keeps `a`'s key order and appends `b`'s new keys at the end,
    and unions arrays instead of replacing them."""
    if isinstance(a, dict) and isinstance(b, dict):
        for k, v in b.items():
            a[k] = deepmerge(a[k], v) if k in a else v
        return a
    if isinstance(a, list) and isinstance(b, list):
        return a + [item for item in b if item not in a]
    return b


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--defaults")
    parser.add_argument("--merge", action="append", default=[])
    parser.add_argument("--no-trailing-newline", action="store_true")
    args = parser.parse_args()

    result = load_json("stdin", sys.stdin.read())

    if args.defaults and Path(args.defaults).is_file():
        result = deepfill(result, load_json(args.defaults, Path(args.defaults).read_text()))

    for path in args.merge:
        if Path(path).is_file():
            result = deepmerge(result, load_json(path, Path(path).read_text()))

    out = json.dumps(result, indent=2)
    # Match Go's encoding/json HTMLEscape, which chezmoi's toPrettyJson used
    # to apply, so re-running apply doesn't reintroduce a diff against what
    # the Netflix claude/codex wrapper (also Go's encoding/json) writes back.
    # Safe as a plain replace: these characters only occur inside JSON
    # string values, never as structural characters.
    out = out.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")

    sys.stdout.write(out if args.no_trailing_newline else out + "\n")


if __name__ == "__main__":
    main()
