#!/usr/bin/env bash
# ============================================================================
# burn-rate-resume — SessionStart hook
# If ./CLAUDE.md has a fresh "## Session Context" block, inject it as
# additional context so Claude naturally picks up where the user left off.
# Never auto-executes anything — priming only.
# ============================================================================

set -uo pipefail

if [ "${BURN_RATE_NO_RESUME:-0}" = "1" ]; then
  exit 0
fi

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
CM="$CWD/CLAUDE.md"
[ -f "$CM" ] || exit 0

# Freshness window (days). Default 7. Set to 0 to always show.
MAX_AGE_DAYS="${BURN_RATE_RESUME_MAX_AGE_DAYS:-7}"

python3 - "$CM" "$MAX_AGE_DAYS" "$CWD" << 'PYEOF'
import sys, os, re, subprocess
from datetime import datetime, timedelta

path, max_age_days, cwd = sys.argv[1], int(sys.argv[2]), sys.argv[3]

try:
    text = open(path, encoding="utf-8", errors="ignore").read()
except Exception:
    sys.exit(0)

# Find the session context block
m = re.search(
    r"^##\s+Session Context\s*(?:\(Last updated:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})(?:\s+([0-9]{2}:[0-9]{2}))?\))?\s*\n(.*?)(?=^##\s|\Z)",
    text, re.MULTILINE | re.DOTALL,
)
if not m:
    sys.exit(0)

date_str, time_str, body = m.group(1), m.group(2), m.group(3).strip()
if not body:
    sys.exit(0)

# Freshness
age_note = ""
stale = False
if date_str:
    try:
        ts = datetime.strptime(
            f"{date_str} {time_str or '00:00'}", "%Y-%m-%d %H:%M"
        )
        age = (datetime.now() - ts).days
        if max_age_days > 0 and age > max_age_days:
            stale = True
            age_note = f" (stale — {age}d old, threshold {max_age_days}d)"
        elif age == 0:
            age_note = " (today)"
        elif age == 1:
            age_note = " (yesterday)"
        else:
            age_note = f" ({age}d ago)"
    except Exception:
        pass

# Git divergence check — compare HEAD to any sha stored in the block
head = ""
try:
    head = subprocess.check_output(
        ["git", "-C", cwd, "rev-parse", "--short", "HEAD"],
        stderr=subprocess.DEVNULL, text=True
    ).strip()
except Exception:
    pass

divergence = ""
sha_in_block = re.search(r"\b([0-9a-f]{7,12})\b", body)
if head and sha_in_block:
    stored = sha_in_block.group(1)
    if not head.startswith(stored[:7]) and not stored.startswith(head[:7]):
        divergence = f" Note: git HEAD is now {head}, block references {stored}."

# Trim body to ~1500 chars for prompt efficiency
trimmed = body if len(body) <= 1500 else body[:1500] + "\n… (truncated — see CLAUDE.md for full context)"

# Emit additional context
if stale:
    print(f"BURN RATE RESUME: found session context in CLAUDE.md but it's stale{age_note}. "
          f"Ask user whether to use it or start fresh — do not auto-resume.\n\n"
          f"--- Stale session context ---\n{trimmed}\n--- end ---")
else:
    print(f"BURN RATE RESUME: found session context in CLAUDE.md{age_note}. "
          f"User likely wants to continue where they left off — acknowledge briefly "
          f"and wait for their direction.{divergence}\n\n"
          f"--- Session context ---\n{trimmed}\n--- end ---")
PYEOF
