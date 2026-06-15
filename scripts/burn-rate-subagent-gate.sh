#!/usr/bin/env bash
# ============================================================================
# burn-rate-subagent-gate — PreToolUse gate for Task/Agent invocations
# When N subagents have already been spawned in this session, force the user
# to confirm before spawning more. Returns JSON with permissionDecision=ask.
# https://code.claude.com/docs/en/hooks
# ============================================================================

set -uo pipefail

# Threshold: after this many subagents in the session, every further Task
# spawn requires explicit user OK. Default 5 — aggressive enough to catch
# spec-paste disasters (60 agents) without annoying normal usage.
THRESHOLD="${BURN_RATE_SUBAGENT_BUDGET:-5}"

# Gate disabled?
if [ "${BURN_RATE_SUBAGENT_BUDGET:-}" = "0" ]; then
  exit 0
fi

PROJECTS_DIR="$HOME/.claude/projects"

# Hook context via stdin JSON (session_id, transcript_path, cwd).
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

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  SESSION_FILE="$TRANSCRIPT_PATH"
fi
if [ -z "$SESSION_FILE" ] && [ -n "$SESSION_ID" ]; then
  SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 2 -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
fi
if [ -z "$SESSION_FILE" ]; then
  # No session file → allow (we can't count, don't block)
  exit 0
fi

# Count Task/Agent tool_use blocks so far in this session
COUNT=$(python3 - "$SESSION_FILE" << 'PYEOF'
import json, sys
n = 0
try:
    with open(sys.argv[1], errors="ignore") as f:
        for line in f:
            try: o = json.loads(line)
            except: continue
            if o.get("type") != "assistant": continue
            for b in o.get("message", {}).get("content", []) or []:
                if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("Task", "Agent"):
                    n += 1
except Exception:
    pass
print(n)
PYEOF
)

COUNT=${COUNT:-0}

if [ "$COUNT" -lt "$THRESHOLD" ]; then
  # Under budget → allow silently
  exit 0
fi

# At or over budget → ask user
REASON="Burn Rate: ${COUNT} subagents already spawned (budget: ${THRESHOLD}). Each subagent loads full context independently. Confirm to continue, or use Grep/Glob for narrow searches. Set BURN_RATE_SUBAGENT_BUDGET=0 to disable this gate."

# Emit JSON decision on stdout per Claude Code hooks spec
cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "${REASON}"
  }
}
JSON
