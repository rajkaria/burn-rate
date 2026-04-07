#!/usr/bin/env bash
# ============================================================================
# Session Guard — Claude Code UserPromptSubmit Hook
# Monitors session length, estimates cost, and detects anti-patterns.
# https://github.com/rajkaria/claude-session-guard
# ============================================================================

set -euo pipefail

# --- Configurable thresholds (override via env vars) ---
WARN_AT="${SG_WARN_AT:-15}"
STRONG_AT="${SG_STRONG_AT:-25}"
URGENT_AT="${SG_URGENT_AT:-40}"

# --- Locate current session ---
PROJECTS_DIR="$HOME/.claude/projects"

if [ ! -d "$PROJECTS_DIR" ]; then
  exit 0
fi

# Find the most recently modified .jsonl session file
LATEST_SESSION=$(find "$PROJECTS_DIR" -maxdepth 2 -name "*.jsonl" -type f -print0 2>/dev/null \
  | xargs -0 ls -t 2>/dev/null \
  | head -1)

if [ -z "$LATEST_SESSION" ]; then
  exit 0
fi

# --- Count user messages ---
USER_MSG_COUNT=$(grep -c '"type":"user"' "$LATEST_SESSION" 2>/dev/null || echo "0")

# --- Count subagents (if session dir exists) ---
SESSION_STEM=$(basename "$LATEST_SESSION" .jsonl)
SESSION_DIR=$(dirname "$LATEST_SESSION")/"$SESSION_STEM"
SUBAGENT_COUNT=0
if [ -d "$SESSION_DIR/subagents" ]; then
  SUBAGENT_COUNT=$(find "$SESSION_DIR/subagents" -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

# --- Estimate cost (rough, based on Opus 4.6 cache-read-heavy sessions) ---
# Average cost per prompt increases non-linearly as context grows
# Based on real-world data: ~$0.30/prompt at start, ~$1.50/prompt at 30+
estimate_cost() {
  local prompts=$1
  if [ "$prompts" -le 10 ]; then
    echo "$((prompts * 30))"  # ~$0.30 each = 30 cents
  elif [ "$prompts" -le 20 ]; then
    echo "$(( 300 + (prompts - 10) * 80 ))"  # ~$0.80 each
  elif [ "$prompts" -le 35 ]; then
    echo "$(( 1100 + (prompts - 20) * 150 ))"  # ~$1.50 each
  else
    echo "$(( 3350 + (prompts - 35) * 250 ))"  # ~$2.50 each
  fi
}

COST_CENTS=$(estimate_cost "$USER_MSG_COUNT")
COST_DOLLARS=$((COST_CENTS / 100))
COST_REMAINDER=$((COST_CENTS % 100))
COST_FMT="\$${COST_DOLLARS}.$(printf '%02d' $COST_REMAINDER)"

# --- Build output ---
OUTPUT=""

# Prompt count warnings
if [ "$USER_MSG_COUNT" -ge "$URGENT_AT" ]; then
  OUTPUT="SESSION GUARD [$USER_MSG_COUNT prompts | ~${COST_FMT} est.]: This session is VERY expensive. Each message re-sends ~${USER_MSG_COUNT}x context. Run /save-context and start a new session NOW."
elif [ "$USER_MSG_COUNT" -ge "$STRONG_AT" ]; then
  OUTPUT="SESSION GUARD [$USER_MSG_COUNT prompts | ~${COST_FMT} est.]: Session getting costly. Run /save-context and start a fresh session to save money."
elif [ "$USER_MSG_COUNT" -ge "$WARN_AT" ]; then
  OUTPUT="SESSION GUARD [$USER_MSG_COUNT prompts | ~${COST_FMT} est.]: Consider wrapping up soon. Run /save-context before starting a new session."
fi

# Subagent storm warning (independent of prompt count)
if [ "$SUBAGENT_COUNT" -ge 15 ]; then
  SUBAGENT_WARN="SUBAGENT STORM: ${SUBAGENT_COUNT} subagents spawned. Each loads full context independently. Use targeted searches instead of broad exploration."
  if [ -n "$OUTPUT" ]; then
    OUTPUT="${OUTPUT}\n${SUBAGENT_WARN}"
  else
    OUTPUT="$SUBAGENT_WARN"
  fi
elif [ "$SUBAGENT_COUNT" -ge 8 ]; then
  SUBAGENT_WARN="SUBAGENT WARNING: ${SUBAGENT_COUNT} subagents in this session. Consider more targeted tool calls."
  if [ -n "$OUTPUT" ]; then
    OUTPUT="${OUTPUT}\n${SUBAGENT_WARN}"
  else
    OUTPUT="$SUBAGENT_WARN"
  fi
fi

# Print output (if any)
if [ -n "$OUTPUT" ]; then
  echo -e "$OUTPUT"
fi
