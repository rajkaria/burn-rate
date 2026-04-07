#!/usr/bin/env bash
# ============================================================================
# Burn Rate — Claude Code UserPromptSubmit Hook
# Real-time session token monitoring, anti-pattern detection.
# Uses CLAUDE_SESSION_ID for accurate current-session tracking.
# https://github.com/rajkaria/burn-rate
# ============================================================================

# Don't use set -e: grep -c returns exit 1 on zero matches
set -uo pipefail

# --- Configurable thresholds (override via env vars) ---
WARN_AT="${BURN_RATE_WARN:-15}"
STRONG_AT="${BURN_RATE_STRONG:-25}"
URGENT_AT="${BURN_RATE_URGENT:-40}"

# Show dollar cost estimates? Only relevant for API/pay-per-token users.
# Set BURN_RATE_SHOW_COST=1 to enable. Off by default (most users are on Max/Pro).
SHOW_COST="${BURN_RATE_SHOW_COST:-0}"

# --- Locate current session using CLAUDE_SESSION_ID ---
PROJECTS_DIR="$HOME/.claude/projects"

if [ ! -d "$PROJECTS_DIR" ]; then
  exit 0
fi

SESSION_ID="${CLAUDE_SESSION_ID:-}"
SESSION_FILE=""

if [ -n "$SESSION_ID" ]; then
  SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 2 -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
fi

if [ -z "$SESSION_FILE" ]; then
  SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 2 -name "*.jsonl" -type f -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -1)
fi

if [ -z "$SESSION_FILE" ]; then
  exit 0
fi

# --- Find pricing.json ---
PRICING_FILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
for candidate in \
  "${CLAUDE_PLUGIN_ROOT:-}/pricing.json" \
  "$SCRIPT_DIR/../pricing.json" \
  "$HOME/.claude/scripts/pricing.json"; do
  if [ -f "$candidate" ]; then
    PRICING_FILE="$candidate"
    break
  fi
done

# --- Single Python call: count prompts + read tokens + compute cost ---
# Passes file paths as arguments (not string interpolation) for safety.
ANALYSIS=$(python3 - "$SESSION_FILE" "$PRICING_FILE" "$SHOW_COST" << 'PYEOF'
import json, sys, os

session_file = sys.argv[1]
pricing_file = sys.argv[2]
show_cost = sys.argv[3]

# --- Default pricing (Opus 4.6 / Sonnet 4.6 / Haiku 4.5, April 2026) ---
pricing = {
    "opus":   {"input": 5.0, "cache_write": 6.25, "cache_read": 0.50, "output": 25.0},
    "sonnet": {"input": 3.0, "cache_write": 3.75, "cache_read": 0.30, "output": 15.0},
    "haiku":  {"input": 1.0, "cache_write": 1.25, "cache_read": 0.10, "output": 5.0},
}
if pricing_file and os.path.isfile(pricing_file):
    try:
        with open(pricing_file) as f:
            loaded = json.load(f)
        for k in ["opus", "sonnet", "haiku"]:
            if k in loaded:
                pricing[k].update(loaded[k])
    except Exception:
        pass

# --- Parse session ---
human_prompts = 0
total_input = 0
total_cache_create = 0
total_cache_read = 0
total_output = 0
model = "opus"

try:
    with open(session_file) as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue

            msg_type = obj.get("type")

            if msg_type == "user":
                # Count only actual human prompts
                if obj.get("isSidechain", False):
                    continue
                if obj.get("userType", "") == "tool":
                    continue
                content = obj.get("message", {}).get("content", "")
                if isinstance(content, list):
                    types = [i.get("type") for i in content if isinstance(i, dict)]
                    if types and all(t == "tool_result" for t in types):
                        continue
                human_prompts += 1

            elif msg_type == "assistant":
                u = obj.get("message", {}).get("usage", {})
                total_input += u.get("input_tokens", 0)
                total_cache_create += u.get("cache_creation_input_tokens", 0)
                total_cache_read += u.get("cache_read_input_tokens", 0)
                total_output += u.get("output_tokens", 0)
                m = obj.get("message", {}).get("model", "")
                if "haiku" in m.lower():
                    model = "haiku"
                elif "sonnet" in m.lower():
                    model = "sonnet"
except Exception:
    pass

total_tokens = total_input + total_cache_create + total_cache_read + total_output

# --- Compute cost ---
cost_cents = 0
if show_cost == "1":
    p = pricing.get(model, pricing["opus"])
    cost_dollars = (
        total_input * p["input"]
        + total_cache_create * p["cache_write"]
        + total_cache_read * p["cache_read"]
        + total_output * p["output"]
    ) / 1_000_000
    cost_cents = int(cost_dollars * 100)

print(f"{human_prompts} {total_tokens} {cost_cents} {model}")
PYEOF
)

# --- Parse results ---
USER_MSG_COUNT=$(echo "$ANALYSIS" | awk '{print $1}')
TOTAL_TOKENS=$(echo "$ANALYSIS" | awk '{print $2}')
COST_CENTS=$(echo "$ANALYSIS" | awk '{print $3}')
MODEL=$(echo "$ANALYSIS" | awk '{print $4}')

# Handle Python failure
if [ -z "$USER_MSG_COUNT" ] || [ -z "$TOTAL_TOKENS" ]; then
  exit 0
fi

# --- Format token count ---
format_tokens() {
  local n=$1
  if [ "$n" -ge 1000000000 ]; then
    echo "$((n / 1000000000)).$(( (n % 1000000000) / 100000000 ))B"
  elif [ "$n" -ge 1000000 ]; then
    echo "$((n / 1000000)).$(( (n % 1000000) / 100000 ))M"
  elif [ "$n" -ge 1000 ]; then
    echo "$((n / 1000)).$(( (n % 1000) / 100 ))K"
  else
    echo "$n"
  fi
}

TOKEN_FMT=$(format_tokens "$TOTAL_TOKENS")

# --- Count subagents ---
SESSION_STEM=$(basename "$SESSION_FILE" .jsonl)
SESSION_DIR=$(dirname "$SESSION_FILE")/"$SESSION_STEM"
SUBAGENT_COUNT=0
if [ -d "$SESSION_DIR/subagents" ]; then
  SUBAGENT_COUNT=$(find "$SESSION_DIR/subagents" -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

# --- Format cost suffix (only if opted in) ---
COST_SUFFIX=""
if [ "$SHOW_COST" = "1" ] && [ "$COST_CENTS" -gt 0 ]; then
  COST_DOLLARS=$((COST_CENTS / 100))
  COST_REMAINDER=$((COST_CENTS % 100))
  COST_SUFFIX=" | ~\$${COST_DOLLARS}.$(printf '%02d' $COST_REMAINDER)"
fi

# --- Build output ---
PARTS=()

if [ "$USER_MSG_COUNT" -ge "$URGENT_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT} tokens${COST_SUFFIX}]: Session is VERY large — each message re-sends the full ${TOKEN_FMT} context. Run /save-context and start a new session NOW.")
elif [ "$USER_MSG_COUNT" -ge "$STRONG_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT} tokens${COST_SUFFIX}]: Session getting heavy. Run /save-context and start fresh.")
elif [ "$USER_MSG_COUNT" -ge "$WARN_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT} tokens${COST_SUFFIX}]: Consider wrapping up soon. Run /save-context before starting a new session.")
fi

if [ "$SUBAGENT_COUNT" -ge 15 ]; then
  PARTS+=("SUBAGENT STORM: ${SUBAGENT_COUNT} subagents spawned — each loads full project context independently. Use targeted Grep/Glob instead.")
elif [ "$SUBAGENT_COUNT" -ge 8 ]; then
  PARTS+=("SUBAGENT WARNING: ${SUBAGENT_COUNT} subagents so far. Consider more targeted tool calls to reduce token burn.")
fi

if [ ${#PARTS[@]} -gt 0 ]; then
  printf '%s\n' "${PARTS[@]}"
fi
