#!/usr/bin/env python3
"""Simple process monitor. Ensures required apps are running."""

import subprocess


REQUIRED_APPS = [
    "Lumesent",
    "Shottr",
    "BetterDisplay",
    "MacWhisper"
]


def is_running(app_name):
    result = subprocess.run(
        ["pgrep", "-xq", app_name],
        capture_output=True,
    )
    return result.returncode == 0


def main():
    not_running = [app for app in REQUIRED_APPS if not is_running(app)]
    if not_running:
        print(f"Not running: {', '.join(not_running)}")


if __name__ == "__main__":
    main()
