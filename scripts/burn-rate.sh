#!/usr/bin/env bash
# ============================================================================
# Burn Rate — Claude Code UserPromptSubmit Hook
# Real-time session cost monitoring, anti-pattern detection.
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
  # v2: Use session ID to find the exact current session file
  SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 2 -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
fi

if [ -z "$SESSION_FILE" ]; then
  # Fallback: most recently modified JSONL (for older Claude Code versions)
  SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 2 -name "*.jsonl" -type f -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -1)
fi

if [ -z "$SESSION_FILE" ]; then
  exit 0
fi

# --- Count ACTUAL human prompts (not tool results) ---
# "type":"user" includes tool results which inflates the count 10x.
# We count only real human messages by excluding tool_result content.
USER_MSG_COUNT=$(python3 -c "
import json
count = 0
try:
    with open('$SESSION_FILE') as f:
        for line in f:
            try:
                obj = json.loads(line)
            except:
                continue
            if obj.get('type') != 'user':
                continue
            if obj.get('isSidechain', False):
                continue
            if obj.get('userType', '') == 'tool':
                continue
            content = obj.get('message', {}).get('content', '')
            if isinstance(content, list):
                types = [i.get('type') for i in content if isinstance(i, dict)]
                if types and all(t == 'tool_result' for t in types):
                    continue
            count += 1
except:
    pass
print(count)
" 2>/dev/null || echo "0")

# --- Read actual token usage + compute cost from session JSONL ---
# Uses pricing.json (from plugin dir or ~/.claude/scripts/) for accurate rates.
# Falls back to hardcoded defaults if pricing file not found.
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

TOKEN_DATA=$(python3 << PYEOF
import json, sys, os

# --- Read pricing ---
pricing = {
    # Defaults: Opus 4.6 / Sonnet 4.6 / Haiku 4.5 (April 2026)
    # Source: https://platform.claude.com/docs/en/about-claude/pricing
    "opus":   {"input": 5.0, "cache_write": 6.25, "cache_read": 0.50, "output": 25.0},
    "sonnet": {"input": 3.0, "cache_write": 3.75, "cache_read": 0.30, "output": 15.0},
    "haiku":  {"input": 1.0, "cache_write": 1.25, "cache_read": 0.10, "output": 5.0},
}
pricing_file = "$PRICING_FILE"
if pricing_file and os.path.isfile(pricing_file):
    try:
        with open(pricing_file) as f:
            loaded = json.load(f)
        for model_key in ["opus", "sonnet", "haiku"]:
            if model_key in loaded:
                pricing[model_key].update(loaded[model_key])
    except:
        pass

# --- Read session tokens ---
total_input = 0
total_cache_create = 0
total_cache_read = 0
total_output = 0
model = "opus"
try:
    with open("$SESSION_FILE") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except:
                continue
            if obj.get("type") == "assistant":
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
except:
    pass

total = total_input + total_cache_create + total_cache_read + total_output

# --- Compute cost in cents ---
p = pricing.get(model, pricing["opus"])
cost_dollars = (
    total_input * p["input"]
    + total_cache_create * p["cache_write"]
    + total_cache_read * p["cache_read"]
    + total_output * p["output"]
) / 1_000_000
cost_cents = int(cost_dollars * 100)

print(f"{total} {cost_cents} {model}")
PYEOF
)

TOTAL_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $1}')
COST_CENTS=$(echo "$TOKEN_DATA" | awk '{print $2}')
MODEL=$(echo "$TOKEN_DATA" | awk '{print $3}')

# --- Format token count for display ---
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

# --- Format cost (only used if SHOW_COST=1) ---
COST_SUFFIX=""
if [ "$SHOW_COST" = "1" ]; then
  COST_DOLLARS=$((COST_CENTS / 100))
  COST_REMAINDER=$((COST_CENTS % 100))
  COST_SUFFIX=" | ~\$${COST_DOLLARS}.$(printf '%02d' $COST_REMAINDER)"
fi

# --- Build output ---
PARTS=()

# Prompt count warnings — token-focused, cost only if opted in
if [ "$USER_MSG_COUNT" -ge "$URGENT_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT} tokens${COST_SUFFIX}]: Session is VERY large — each message re-sends the full ${TOKEN_FMT} context. Run /save-context and start a new session NOW.")
elif [ "$USER_MSG_COUNT" -ge "$STRONG_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT} tokens${COST_SUFFIX}]: Session getting heavy. Run /save-context and start fresh.")
elif [ "$USER_MSG_COUNT" -ge "$WARN_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT} tokens${COST_SUFFIX}]: Consider wrapping up soon. Run /save-context before starting a new session.")
fi

# Subagent storm warnings
if [ "$SUBAGENT_COUNT" -ge 15 ]; then
  PARTS+=("SUBAGENT STORM: ${SUBAGENT_COUNT} subagents spawned — each loads full project context independently. Use targeted Grep/Glob instead.")
elif [ "$SUBAGENT_COUNT" -ge 8 ]; then
  PARTS+=("SUBAGENT WARNING: ${SUBAGENT_COUNT} subagents so far. Consider more targeted tool calls to reduce cost.")
fi

# Print output
if [ ${#PARTS[@]} -gt 0 ]; then
  printf '%s\n' "${PARTS[@]}"
fi
