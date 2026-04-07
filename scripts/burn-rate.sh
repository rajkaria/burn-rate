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

# --- Read actual token usage from session JSONL ---
# Extract token counts from assistant message usage fields
# This gives us real numbers, not estimates
TOKEN_DATA=$(python3 -c "
import json, sys
total_input = 0
total_cache_create = 0
total_cache_read = 0
total_output = 0
model = 'opus'
try:
    with open('$SESSION_FILE') as f:
        for line in f:
            try:
                obj = json.loads(line)
            except:
                continue
            if obj.get('type') == 'assistant':
                u = obj.get('message', {}).get('usage', {})
                total_input += u.get('input_tokens', 0)
                total_cache_create += u.get('cache_creation_input_tokens', 0)
                total_cache_read += u.get('cache_read_input_tokens', 0)
                total_output += u.get('output_tokens', 0)
                m = obj.get('message', {}).get('model', '')
                if 'haiku' in m.lower():
                    model = 'haiku'
                elif 'sonnet' in m.lower():
                    model = 'sonnet'
except:
    pass
total = total_input + total_cache_create + total_cache_read + total_output
print(f'{total} {total_input} {total_cache_create} {total_cache_read} {total_output} {model}')
" 2>/dev/null || echo "0 0 0 0 0 opus")

TOTAL_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $1}')
INPUT_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $2}')
CACHE_CREATE=$(echo "$TOKEN_DATA" | awk '{print $3}')
CACHE_READ=$(echo "$TOKEN_DATA" | awk '{print $4}')
OUTPUT_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $5}')
MODEL=$(echo "$TOKEN_DATA" | awk '{print $6}')

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

# --- Estimate cost from actual tokens ---
# Pricing per 1M tokens (in hundredths of a cent for integer math):
#   Opus:   input=$15, cache_create=$18.75, cache_read=$1.88, output=$75
#   Sonnet: input=$3,  cache_create=$3.75,  cache_read=$0.30, output=$15
#   Haiku:  input=$0.80, cache_create=$1.00, cache_read=$0.08, output=$4
# We compute in microdollars (1M microdollars = $1) then convert to cents
estimate_cost_from_tokens() {
  local cost_micros=0
  case "$MODEL" in
    opus)
      cost_micros=$(( INPUT_TOKENS * 15 + CACHE_CREATE * 19 + CACHE_READ * 2 + OUTPUT_TOKENS * 75 ))
      ;;
    sonnet)
      cost_micros=$(( INPUT_TOKENS * 3 + CACHE_CREATE * 4 + CACHE_READ * 1 + OUTPUT_TOKENS * 15 ))
      ;;
    haiku)
      cost_micros=$(( INPUT_TOKENS * 1 + CACHE_CREATE * 1 + CACHE_READ * 1 + OUTPUT_TOKENS * 4 ))
      ;;
  esac
  # Convert from microdollars-per-million to cents: divide by 1M, multiply by 100
  # Simplified: divide by 10000
  echo $(( cost_micros / 10000 ))
}

COST_CENTS=$(estimate_cost_from_tokens)
COST_DOLLARS=$((COST_CENTS / 100))
COST_REMAINDER=$((COST_CENTS % 100))
COST_FMT="\$${COST_DOLLARS}.$(printf '%02d' $COST_REMAINDER)"

# Model label for display
MODEL_LABEL=""
if [ "$MODEL" != "opus" ]; then
  MODEL_LABEL=" ${MODEL}"
fi

# --- Build output ---
PARTS=()

# Prompt count warnings
if [ "$USER_MSG_COUNT" -ge "$URGENT_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT} tokens | ~${COST_FMT}${MODEL_LABEL}]: Session is VERY expensive — each message re-sends the full ${TOKEN_FMT} context. Run /save-context and start a new session NOW.")
elif [ "$USER_MSG_COUNT" -ge "$STRONG_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT} tokens | ~${COST_FMT}${MODEL_LABEL}]: Session getting costly. Run /save-context and start fresh.")
elif [ "$USER_MSG_COUNT" -ge "$WARN_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT} tokens | ~${COST_FMT}${MODEL_LABEL}]: Consider wrapping up soon. Run /save-context before starting a new session.")
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
