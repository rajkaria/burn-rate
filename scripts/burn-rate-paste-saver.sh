#!/usr/bin/env bash
# ============================================================================
# burn-rate-paste-saver — soft paste-bomb mitigation
# When the user sends a prompt with a large blob inside, save it to a file so
# on the NEXT turn they can reference @file instead of re-pasting. This turn
# is never disrupted — we only reduce waste on future turns.
# ============================================================================

set -uo pipefail

# Threshold in chars. 3000 ≈ 750 tokens — catches real paste bombs without
# firing on normal messages. Set BURN_RATE_NO_DIET=1 to disable.
THRESHOLD="${BURN_RATE_PASTE_WARN:-3000}"

if [ "${BURN_RATE_NO_DIET:-0}" = "1" ]; then
  exit 0
fi

# Read the UserPromptSubmit JSON from stdin
INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    o = json.load(sys.stdin)
    print(o.get('prompt', ''), end='')
except Exception:
    pass
" 2>/dev/null)

LEN=${#PROMPT}
if [ "$LEN" -lt "$THRESHOLD" ]; then
  exit 0
fi

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
PASTES_DIR="$CWD/.burn-rate/pastes"
mkdir -p "$PASTES_DIR" 2>/dev/null || exit 0

TS=$(date +%Y%m%d-%H%M%S)
PASTE_FILE="$PASTES_DIR/paste-${TS}.txt"
printf '%s' "$PROMPT" > "$PASTE_FILE" 2>/dev/null || exit 0

# Rough token estimate (4 chars/token)
EST_TOKENS=$((LEN / 4))

# Relative path for the user-facing message
REL_PATH="${PASTE_FILE#$CWD/}"

# Ensure .gitignore ignores .burn-rate/ (friendly default)
GI="$CWD/.gitignore"
if [ -f "$GI" ] && ! grep -q '^\.burn-rate/' "$GI" 2>/dev/null; then
  echo '.burn-rate/' >> "$GI" 2>/dev/null
fi

# Output context line (injected into Claude's view this turn)
printf 'BURN RATE PASTE SAVED: user message had %s chars (~%s tokens). Saved to %s. Tell the user: next turn, reference @%s instead of re-pasting — saves ~%s tokens per subsequent turn. Do NOT narrate this unless they paste again; just act on it silently this turn.\n' \
  "$LEN" "$EST_TOKENS" "$REL_PATH" "$REL_PATH" "$EST_TOKENS"
