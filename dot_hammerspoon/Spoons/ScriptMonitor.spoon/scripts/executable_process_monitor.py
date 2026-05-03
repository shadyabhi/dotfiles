#!/usr/bin/env python3
"""Process monitor. App names passed as argv."""

import subprocess
import sys


def is_running(app_name):
    result = subprocess.run(
        ["pgrep", "-xq", app_name],
        capture_output=True,
    )
    return result.returncode == 0


def main():
    apps = sys.argv[1:]
    not_running = [app for app in apps if not is_running(app)]
    if not_running:
        print(f"Not running: {', '.join(not_running)}")


if __name__ == "__main__":
    main()
