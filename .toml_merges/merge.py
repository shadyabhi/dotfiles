#!/usr/bin/env python3
"""Merge a TOML overlay into stdin, preserving unmanaged configuration."""

import argparse
from collections.abc import Mapping
from copy import deepcopy
from pathlib import Path
import sys

import tomlkit
from tomlkit.exceptions import TOMLKitError


def same_value(left, right):
    left = left.unwrap() if hasattr(left, "unwrap") else left
    right = right.unwrap() if hasattr(right, "unwrap") else right
    return equal_values(left, right)


def equal_values(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(
            equal_values(value, right[key]) for key, value in left.items()
        )
    if isinstance(left, list):
        return len(left) == len(right) and all(
            equal_values(a, b) for a, b in zip(left, right)
        )
    return left == right


def merge(document, overlay, path=()):
    changed = False
    for key, value in overlay.items():
        if key not in document:
            document[key] = deepcopy(value)
            changed = True
            continue

        current = document[key]
        if isinstance(current, Mapping) != isinstance(value, Mapping):
            raise ValueError(f"table/value conflict at {'.'.join((*path, key))}")
        if isinstance(value, Mapping):
            changed = merge(current, value, (*path, key)) or changed
        elif not same_value(current, value):
            document[key] = deepcopy(value)
            changed = True
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--merge", required=True, type=Path)
    args = parser.parse_args()

    original = sys.stdin.buffer.read()
    try:
        live = original.decode("utf-8")
        document = tomlkit.parse(live)
        overlay = tomlkit.parse(args.merge.read_text(encoding="utf-8"))
        changed = merge(document, overlay)
        output = tomlkit.dumps(document) if changed else live
        if changed and "\r\n" in live and "\n" not in live.replace("\r\n", ""):
            output = output.replace("\r\n", "\n").replace("\n", "\r\n")
        if changed and original and not live.endswith("\n"):
            output = output.rstrip("\r\n")
    except (OSError, UnicodeError, TOMLKitError, ValueError) as error:
        print(f"merge.py: {error}", file=sys.stderr)
        return 1

    sys.stdout.buffer.write(output.encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
