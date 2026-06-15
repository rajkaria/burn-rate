#!/usr/bin/env bash
# ============================================================================
# Burn Rate v6 — Claude Code UserPromptSubmit Hook
# Real-time session token monitoring, anti-pattern detection.
# Uses CLAUDE_SESSION_ID for accurate current-session tracking.
# https://github.com/rajkaria/burn-rate
# ============================================================================

# Don't use set -e: grep -c returns exit 1 on zero matches
set -uo pipefail

# --- Configurable thresholds (override via env vars) ---
# Prompt-count thresholds
COMPACT_AT="${BURN_RATE_COMPACT:-8}"
WARN_AT="${BURN_RATE_WARN:-15}"
STRONG_AT="${BURN_RATE_STRONG:-25}"
URGENT_AT="${BURN_RATE_URGENT:-40}"

# Token-volume thresholds (whichever fires first — prompts or tokens)
TOKEN_COMPACT_AT="${BURN_RATE_TOKEN_COMPACT:-10000000}"    # 10M
TOKEN_WARN_AT="${BURN_RATE_TOKEN_WARN:-30000000}"          # 30M
TOKEN_STRONG_AT="${BURN_RATE_TOKEN_STRONG:-60000000}"       # 60M
TOKEN_URGENT_AT="${BURN_RATE_TOKEN_URGENT:-100000000}"      # 100M

# Show dollar cost estimates? Only relevant for API/pay-per-token users.
SHOW_COST="${BURN_RATE_SHOW_COST:-0}"

# --- Locate current session ---
# Claude Code passes hook context (session_id, transcript_path, cwd) via stdin JSON,
# NOT env vars. Read it. Fall back to env var, then to project-scoped most-recent.
PROJECTS_DIR="$HOME/.claude/projects"

if [ ! -d "$PROJECTS_DIR" ]; then
  exit 0
fi

HOOK_INPUT=""
if [ ! -t 0 ]; then
  HOOK_INPUT=$(cat 2>/dev/null || true)
fi

SESSION_ID=""
TRANSCRIPT_PATH=""
HOOK_CWD=""
if [ -n "$HOOK_INPUT" ] && command -v python3 >/dev/null 2>&1; then
  eval "$(printf '%s' "$HOOK_INPUT" | python3 -c '
import json, sys, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for k, v in (("SESSION_ID", d.get("session_id", "")),
             ("TRANSCRIPT_PATH", d.get("transcript_path", "")),
             ("HOOK_CWD", d.get("cwd", ""))):
    print(f"{k}={shlex.quote(str(v or \"\"))}")
' 2>/dev/null)"
fi

SESSION_ID="${SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
SESSION_FILE=""

# 1. Preferred: transcript_path directly from hook input
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  SESSION_FILE="$TRANSCRIPT_PATH"
fi

# 2. Look up by session_id
if [ -z "$SESSION_FILE" ] && [ -n "$SESSION_ID" ]; then
  SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 2 -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
fi

# 3. Fall back to most-recent jsonl scoped to the *current project* only
if [ -z "$SESSION_FILE" ]; then
  CWD_FOR_SCOPE="${HOOK_CWD:-$PWD}"
  # Claude stores per-project dirs as the cwd with / replaced by -
  # Claude Code's per-project dir replaces BOTH / and . with - (so /.claude -> --claude)
  PROJECT_KEY="-$(printf '%s' "$CWD_FOR_SCOPE" | sed 's|[/.]|-|g' | sed 's|^-||')"
  PROJECT_DIR="$PROJECTS_DIR/$PROJECT_KEY"
  if [ -d "$PROJECT_DIR" ]; then
    SESSION_FILE=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.jsonl" -type f -print0 2>/dev/null \
      | xargs -0 ls -t 2>/dev/null \
      | head -1)
  fi
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

# --- Single Python call: prompts + tokens + breakdown + cost ---
ANALYSIS=$(python3 - "$SESSION_FILE" "$PRICING_FILE" "$SHOW_COST" << 'PYEOF'
import json, sys, os
from collections import Counter, deque

session_file = sys.argv[1]
pricing_file = sys.argv[2]
show_cost = sys.argv[3]

# Track last N assistant turns' tool mix for model-switch suggestion
recent_turns = deque(maxlen=5)  # each: set of tool names used

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
file_reads = Counter()

try:
    with open(session_file) as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue

            msg_type = obj.get("type")

            if msg_type == "user":
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
                # Per-file Read counter for re-read warnings
                content = obj.get("message", {}).get("content", [])
                tools_this_turn = set()
                if isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_use":
                            name = b.get("name", "")
                            tools_this_turn.add(name)
                            if name == "Read":
                                p = (b.get("input") or {}).get("file_path", "")
                                if p:
                                    file_reads[p] += 1
                if tools_this_turn:
                    recent_turns.append(tools_this_turn)
except Exception:
    pass

total_tokens = total_input + total_cache_create + total_cache_read + total_output

# --- Tokens per prompt ---
tokens_per_prompt = int(total_tokens / human_prompts) if human_prompts > 0 else 0

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

# Trivial-streak detection for model-switch tip.
# Trivial = last 5 turns used ONLY safe narrow tools (Bash/Read/Edit/Write/Glob/Grep)
# and no Task/WebSearch/WebFetch anywhere in the window.
TRIVIAL_OK = {"Bash", "Read", "Edit", "Write", "Glob", "Grep", "TodoWrite", "NotebookEdit"}
HEAVY = {"Task", "Agent", "WebSearch", "WebFetch"}
# "lull" = last 5 turns were all light/narrow work (no heavy tools) — a natural
# break where compaction is safe. trivial_streak adds the Opus check (model tip).
lull = (
    len(recent_turns) >= 5 and
    all(not (t & HEAVY) and t.issubset(TRIVIAL_OK | HEAVY) for t in recent_turns)
)
trivial_streak = lull and model == "opus"

# Worst re-read (basename + count), for live warning
worst_path, worst_count = ("", 0)
if file_reads:
    worst_path, worst_count = file_reads.most_common(1)[0]
worst_base = os.path.basename(worst_path) if worst_path else ""

# Output: prompts total_tokens tokens_per_prompt cache_read cache_create output cost_cents model worst_count worst_basename trivial_streak
print(f"{human_prompts} {total_tokens} {tokens_per_prompt} {total_cache_read} {total_cache_create} {total_output} {cost_cents} {model} {worst_count} {worst_base or '-'} {int(trivial_streak)} {int(lull)}")
PYEOF
)

# --- Parse results ---
USER_MSG_COUNT=$(echo "$ANALYSIS" | awk '{print $1}')
TOTAL_TOKENS=$(echo "$ANALYSIS" | awk '{print $2}')
TOKENS_PER_PROMPT=$(echo "$ANALYSIS" | awk '{print $3}')
CACHE_READ=$(echo "$ANALYSIS" | awk '{print $4}')
CACHE_CREATE=$(echo "$ANALYSIS" | awk '{print $5}')
OUTPUT_TOKENS=$(echo "$ANALYSIS" | awk '{print $6}')
COST_CENTS=$(echo "$ANALYSIS" | awk '{print $7}')
MODEL=$(echo "$ANALYSIS" | awk '{print $8}')
WORST_READ_COUNT=$(echo "$ANALYSIS" | awk '{print $9}')
WORST_READ_FILE=$(echo "$ANALYSIS" | awk '{print $10}')
TRIVIAL_STREAK=$(echo "$ANALYSIS" | awk '{print $11}')
LULL=$(echo "$ANALYSIS" | awk '{print $12}')
REREAD_WARN_AT="${BURN_RATE_REREAD_WARN:-5}"

# One-shot per session: remember we've shown the model-switch tip
TIP_FLAG_DIR="$HOME/.claude/.burn-rate/tips-shown"
mkdir -p "$TIP_FLAG_DIR" 2>/dev/null
TIP_FLAG="$TIP_FLAG_DIR/${CLAUDE_SESSION_ID:-unknown}.model-switch"

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
TPP_FMT=$(format_tokens "$TOKENS_PER_PROMPT")
CACHE_READ_FMT=$(format_tokens "$CACHE_READ")
CACHE_CREATE_FMT=$(format_tokens "$CACHE_CREATE")
OUTPUT_FMT=$(format_tokens "$OUTPUT_TOKENS")

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

# --- Plan budget % (for Max/Pro flat-rate users) ---
# Translates tokens into "% of a heavy session" — a capacity signal
# BURN_RATE_PLAN: pro | max | max20 | api (default: empty = hidden)
# Or set BURN_RATE_SESSION_BUDGET directly in tokens.
PLAN="${BURN_RATE_PLAN:-}"
SESSION_BUDGET="${BURN_RATE_SESSION_BUDGET:-0}"
if [ "$SESSION_BUDGET" = "0" ]; then
  case "$PLAN" in
    pro)   SESSION_BUDGET=50000000 ;;      # 50M
    max)   SESSION_BUDGET=150000000 ;;     # 150M
    max20) SESSION_BUDGET=500000000 ;;     # 500M
    *)     SESSION_BUDGET=0 ;;
  esac
fi
BUDGET_SUFFIX=""
if [ "$SESSION_BUDGET" -gt 0 ] && [ "$TOTAL_TOKENS" -gt 0 ]; then
  # Integer percentage (bash)
  PCT=$((TOTAL_TOKENS * 100 / SESSION_BUDGET))
  PLAN_LABEL="${PLAN:-budget}"
  BUDGET_SUFFIX=" | ${PCT}% of ${PLAN_LABEL}"
fi

# --- Build output ---
PARTS=()

# v4: Token breakdown line (always shown when threshold hit)
BREAKDOWN="[${TPP_FMT}/prompt | context: ${CACHE_READ_FMT} reads, ${CACHE_CREATE_FMT} writes | output: ${OUTPUT_FMT}]"

# v6: Nudge on whichever fires first — prompt count OR token volume
# Messages kept minimal — they're injected into context every prompt
# Output directive tells Claude to minimize its own response tokens
OUTPUT_DIRECTIVE="Keep responses minimal: no narration between tool calls, no summaries unless asked."

if [ "$USER_MSG_COUNT" -ge "$URGENT_AT" ] || [ "$TOTAL_TOKENS" -ge "$TOKEN_URGENT_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT}${COST_SUFFIX}${BUDGET_SUFFIX}]: /save-context and new session NOW. ${OUTPUT_DIRECTIVE}")
elif [ "$USER_MSG_COUNT" -ge "$STRONG_AT" ] || [ "$TOTAL_TOKENS" -ge "$TOKEN_STRONG_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT}${COST_SUFFIX}${BUDGET_SUFFIX}]: Heavy session. /save-context and start fresh. ${OUTPUT_DIRECTIVE}")
elif [ "$USER_MSG_COUNT" -ge "$WARN_AT" ] || [ "$TOTAL_TOKENS" -ge "$TOKEN_WARN_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT}${COST_SUFFIX}${BUDGET_SUFFIX}]: /compact or /save-context. ${OUTPUT_DIRECTIVE}")
elif [ "$USER_MSG_COUNT" -ge "$COMPACT_AT" ] || [ "$TOTAL_TOKENS" -ge "$TOKEN_COMPACT_AT" ]; then
  PARTS+=("BURN RATE [${USER_MSG_COUNT} prompts | ${TOKEN_FMT}${BUDGET_SUFFIX}]: Run /compact. ${OUTPUT_DIRECTIVE}")
fi

# Model-switch tip (one-shot per session)
if [ "${TRIVIAL_STREAK:-0}" = "1" ] && [ ! -f "$TIP_FLAG" ] && [ "${BURN_RATE_NO_MODEL_TIP:-0}" != "1" ]; then
  PARTS+=("MODEL TIP: last 5 turns were narrow edits — switch to Haiku with /model haiku for ~5× cheaper. (shown once)")
  touch "$TIP_FLAG" 2>/dev/null
fi

# Strategic compaction tip (one-shot): a large, mostly-re-read context during a
# light-work lull is the ideal moment to /compact — you shed accumulated context
# right at a task boundary, while it's cheap to re-establish what matters.
STRATEGIC_FLAG="$TIP_FLAG_DIR/${CLAUDE_SESSION_ID:-unknown}.strategic-compact"
STRATEGIC_AT="${BURN_RATE_STRATEGIC_COMPACT:-5000000}"   # 5M floor
if [ "${LULL:-0}" = "1" ] && [ "$TOTAL_TOKENS" -ge "$STRATEGIC_AT" ] \
   && [ ! -f "$STRATEGIC_FLAG" ] && [ "${BURN_RATE_NO_COMPACT_TIP:-0}" != "1" ] \
   && [ "$TOTAL_TOKENS" -gt 0 ] && [ "$((CACHE_READ * 100 / TOTAL_TOKENS))" -ge 70 ]; then
  PARTS+=("STRATEGIC COMPACT: ${TOKEN_FMT} context, mostly re-read — and you're at a light-work lull. Ideal moment to /compact before the next task. (shown once)")
  touch "$STRATEGIC_FLAG" 2>/dev/null
fi

# Per-file re-read warning (feature #2)
if [ -n "$WORST_READ_COUNT" ] && [ "$WORST_READ_COUNT" -ge "$REREAD_WARN_AT" ] && [ "$WORST_READ_FILE" != "-" ]; then
  PARTS+=("RE-READ WARNING: '${WORST_READ_FILE}' read ${WORST_READ_COUNT}× — pin it or /save-context.")
fi

# Subagent warnings
if [ "$SUBAGENT_COUNT" -ge 15 ]; then
  PARTS+=("SUBAGENT STORM: ${SUBAGENT_COUNT} spawned. Use Grep/Glob instead.")
elif [ "$SUBAGENT_COUNT" -ge 8 ]; then
  PARTS+=("SUBAGENT WARNING: ${SUBAGENT_COUNT} so far. Prefer targeted tool calls.")
fi

if [ ${#PARTS[@]} -gt 0 ]; then
  printf '%s\n' "${PARTS[@]}"
fi
