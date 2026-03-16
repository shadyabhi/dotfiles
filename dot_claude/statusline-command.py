#!/usr/bin/env python3

import json
import sys

# ---------------------------------------------------------------------------
# Data extraction
# ---------------------------------------------------------------------------
input_data = json.load(sys.stdin)

model = input_data.get("model", {}).get("display_name", "")
cwd = input_data.get("workspace", {}).get("current_dir", "")
transcript_path = input_data.get("transcript_path", "")

# ---------------------------------------------------------------------------
# Session cost — from cumulative token counters in the live JSON input
# Opus pricing (per million tokens): Input $15 | Cache Write $18.75 | Cache Read $1.50 | Output $75
# ---------------------------------------------------------------------------
ctx = input_data.get("context_window", {})
total_input = ctx.get("total_input_tokens", 0) or 0
total_output = ctx.get("total_output_tokens", 0) or 0
session_cost = (total_input * 15.00 + total_output * 75.00) / 1_000_000


# ---------------------------------------------------------------------------
# Context window usage
# ---------------------------------------------------------------------------
used_pct = ctx.get("used_percentage")
used_int = round(used_pct) if used_pct is not None else 0

# ---------------------------------------------------------------------------
# ANSI helpers
# ---------------------------------------------------------------------------
RESET = "\033[0m"
BOLD = "\033[1m"
FG_WHITE = "\033[97m"
FG_BLACK = "\033[30m"

BG_SESSION = "\033[48;5;24m"    # steel blue

CODE_SESSION = 24

# Context bar — per-block fg colors (transparent bg, no powerline)
FG_CTX_GREEN  = "\033[38;5;34m"   # green  (blocks 0–4)
FG_CTX_ORANGE = "\033[38;5;214m"  # orange (blocks 5–7)
FG_CTX_RED    = "\033[38;5;196m"  # red    (blocks 8–9)
FG_CTX_EMPTY  = "\033[38;5;238m"  # dark grey for unfilled blocks

# ---------------------------------------------------------------------------
# Model name — Anthropic/Claude brand coral background (#D97757 → 256-color 173), white text
# ---------------------------------------------------------------------------

BG_BARHOST = "\033[48;5;173m"     # Anthropic coral — Claude brand color
CODE_BARHOST = 173

fill_fraction = (used_int / 100.0) if used_pct is not None else 0.0
model_bar = f"{FG_WHITE}{BOLD}{model}{RESET}"

# ---------------------------------------------------------------------------
# Powerline rendering
# ---------------------------------------------------------------------------
ARROW = "\ue0b0"

def render_seg(bg, fg, label, value):
    return f"{bg}{fg}{BOLD} {label} {RESET}{bg}{fg} {value} {RESET}"

segments = []  # list of (rendered_str, bg_code)

# 1. Model name — white text on Anthropic coral background
bar_segment = (
    f"{BG_BARHOST}{BOLD} {model_bar}{BG_BARHOST} {RESET}"
)
segments.append((bar_segment, CODE_BARHOST))

# 2. Context usage bar — plain rectangular bar, no powerline arrows, transparent bg
#    Each of 10 blocks is individually colored: green → orange → red by position.
#    Unfilled blocks are dim grey. Format:  ▓▓▓▓░░░░░░ 42%
ctx_bar_inline = ""
if used_pct is not None:
    BAR_WIDTH = 10
    filled = round(fill_fraction * BAR_WIDTH)
    filled = max(0, min(BAR_WIDTH, filled))

    def block_color(i):
        if i < 5:
            return FG_CTX_GREEN
        elif i < 8:
            return FG_CTX_ORANGE
        else:
            return FG_CTX_RED

    blocks = ""
    for i in range(BAR_WIDTH):
        if i < filled:
            blocks += block_color(i) + "\u2588"   # █ filled, colored by position
        else:
            blocks += FG_CTX_EMPTY + "\u2591"     # ░ unfilled, dim grey
    blocks += RESET

    # Percentage color matches the color of the last filled block (or green if empty)
    pct_color = block_color(filled - 1) if filled > 0 else FG_CTX_GREEN
    ctx_bar_inline = f" {blocks} {pct_color}{BOLD}{used_int}%{RESET}"

# 3 (or 2 if no ctx data). Session cost segment (steel blue)
cost_segment = (
    f"{BG_SESSION}{FG_WHITE} ${session_cost:.2f} 💰 {RESET}"
)
segments.append((cost_segment, CODE_SESSION))

# ---------------------------------------------------------------------------
# Join with powerline arrows + space between segments
# The ctx bar is inline (no bg, no arrows) — injected after the first segment.
# ---------------------------------------------------------------------------
result = ""
for i, (seg_str, bg_code) in enumerate(segments):
    if i == 0:
        result = seg_str
        # Inject the plain rectangular ctx bar right after the model segment
        result += ctx_bar_inline
    else:
        # No arrow before the cost segment — start it cleanly with just a space
        result = f"{result} {seg_str}"

# Final arrow to transparent background
last_code = segments[-1][1]
result += f"\033[38;5;{last_code}m{ARROW}{RESET}"

sys.stdout.write(result)
