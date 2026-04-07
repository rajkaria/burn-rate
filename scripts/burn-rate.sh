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

# --- Count user messages ---
USER_MSG_COUNT=$(grep -c '"type":"user"' "$SESSION_FILE" 2>/dev/null || echo "0")

# --- Detect model (for cost estimation accuracy) ---
# Check first assistant message for model info; default to opus
MODEL="opus"
MODEL_LINE=$(grep -m1 '"model"' "$SESSION_FILE" 2>/dev/null || true)
if echo "$MODEL_LINE" | grep -qi "haiku" 2>/dev/null; then
  MODEL="haiku"
elif echo "$MODEL_LINE" | grep -qi "sonnet" 2>/dev/null; then
  MODEL="sonnet"
fi

# --- Count subagents ---
SESSION_STEM=$(basename "$SESSION_FILE" .jsonl)
SESSION_DIR=$(dirname "$SESSION_FILE")/"$SESSION_STEM"
SUBAGENT_COUNT=0
if [ -d "$SESSION_DIR/subagents" ]; then
  SUBAGENT_COUNT=$(find "$SESSION_DIR/subagents" -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

# --- Estimate cost ---
# Empirical model from analyzing 27 real sessions.
# Context grows per-turn; cache reads dominate (~96% of input).
# Cost multipliers by model (relative to Opus):
#   Opus:   1.0x  ($15/1M input, $75/1M output)
#   Sonnet: 0.2x  ($3/1M input, $15/1M output)
#   Haiku:  0.05x ($0.80/1M input, $4/1M output)
estimate_cost() {
  local prompts=$1
  local subs=$2
  local base_cost=0

  # Base cost in cents (calibrated for Opus 4.6)
  if [ "$prompts" -le 10 ]; then
    base_cost=$((prompts * 30))
  elif [ "$prompts" -le 20 ]; then
    base_cost=$(( 300 + (prompts - 10) * 80 ))
  elif [ "$prompts" -le 35 ]; then
    base_cost=$(( 1100 + (prompts - 20) * 150 ))
  else
    base_cost=$(( 3350 + (prompts - 35) * 250 ))
  fi

  # Add subagent cost (~$1.00 avg per subagent for Opus)
  local sub_cost=$((subs * 100))
  local total=$(( base_cost + sub_cost ))

  # Apply model multiplier
  case "$MODEL" in
    haiku)  total=$(( total * 5 / 100 )) ;;  # 5% of Opus cost
    sonnet) total=$(( total * 20 / 100 )) ;;  # 20% of Opus cost
  esac

  echo "$total"
}

COST_CENTS=$(estimate_cost "$USER_MSG_COUNT" "$SUBAGENT_COUNT")
COST_DOLLARS=$((COST_CENTS / 100))
COST_REMAINDER=$((COST_CENTS % 100))
COST_FMT="\$${COST_DOLLARS}.$(printf '%02d' $COST_REMAINDER)"

# Model label for display
MODEL_LABEL=""
if [ "$MODEL" != "opus" ]; then
  MODEL_LABEL=" (${MODEL})"
fi

# --- Build output ---
PARTS=()

# Prompt count warnings
if [ "$USER_MSG_COUNT" -ge "$URGENT_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ~${COST_FMT}${MODEL_LABEL}]: Session is VERY expensive — each message re-sends ~${USER_MSG_COUNT}x context. Run /save-context and start a new session NOW.")
elif [ "$USER_MSG_COUNT" -ge "$STRONG_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ~${COST_FMT}${MODEL_LABEL}]: Session getting costly. Run /save-context and start fresh.")
elif [ "$USER_MSG_COUNT" -ge "$WARN_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ~${COST_FMT}${MODEL_LABEL}]: Consider wrapping up soon. Run /save-context before starting a new session.")
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
