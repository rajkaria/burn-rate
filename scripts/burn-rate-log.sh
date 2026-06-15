#!/usr/bin/env bash
# ============================================================================
# burn-rate-log — append a session snapshot to ~/.claude/.burn-rate/history.jsonl
# Called on SessionEnd (and by /save-context as a safety net).
# Cheap, idempotent per session (dedupes by session_id + last_timestamp).
# ============================================================================

set -uo pipefail

PROJECTS_DIR="$HOME/.claude/projects"
HIST_DIR="$HOME/.claude/.burn-rate"
HIST_FILE="$HIST_DIR/history.jsonl"
mkdir -p "$HIST_DIR"

# Hook context is passed via stdin JSON (session_id, transcript_path, cwd), not env.
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
  CWD_FOR_SCOPE="${HOOK_CWD:-$PWD}"
  # Claude Code's per-project dir replaces BOTH / and . with - (so /.claude -> --claude)
  PROJECT_KEY="-$(printf '%s' "$CWD_FOR_SCOPE" | sed 's|[/.]|-|g' | sed 's|^-||')"
  PROJECT_DIR="$PROJECTS_DIR/$PROJECT_KEY"
  if [ -d "$PROJECT_DIR" ]; then
    SESSION_FILE=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.jsonl" -type f -print0 2>/dev/null \
      | xargs -0 ls -t 2>/dev/null | head -1)
  fi
fi
[ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ] || exit 0

python3 - "$SESSION_FILE" "$HIST_FILE" << 'PYEOF'
import json, sys, os
from collections import Counter

session_file, hist_file = sys.argv[1], sys.argv[2]

prompts = 0
ti = tcw = tcr = to = 0
model = "opus"
started = ended = None
tool_counts = Counter()
subagents = 0
sid = ""
project = ""

try:
    with open(session_file, errors="ignore") as f:
        for line in f:
            try: o = json.loads(line)
            except: continue
            sid = o.get("sessionId", sid)
            ts = o.get("timestamp")
            if ts:
                started = started or ts
                ended = ts
            t = o.get("type")
            if t == "user":
                if o.get("isSidechain") or o.get("userType") == "tool": continue
                c = o.get("message", {}).get("content", "")
                if isinstance(c, list):
                    types = [i.get("type") for i in c if isinstance(i, dict)]
                    if types and all(x == "tool_result" for x in types): continue
                prompts += 1
            elif t == "assistant":
                u = o.get("message", {}).get("usage", {})
                ti += u.get("input_tokens", 0)
                tcw += u.get("cache_creation_input_tokens", 0)
                tcr += u.get("cache_read_input_tokens", 0)
                to += u.get("output_tokens", 0)
                m = o.get("message", {}).get("model", "")
                if "haiku" in m.lower(): model = "haiku"
                elif "sonnet" in m.lower(): model = "sonnet"
                for b in o.get("message", {}).get("content", []) or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        tool_counts[b.get("name", "?")] += 1
                        if b.get("name") in ("Task", "Agent"):
                            subagents += 1
except Exception:
    sys.exit(0)

total = ti + tcw + tcr + to
if total == 0:
    sys.exit(0)

# Derive project name from session path: ~/.claude/projects/-Users-...-<name>/*.jsonl
proj_dir = os.path.basename(os.path.dirname(session_file))
# Strip leading "-Users-..." prefix heuristically: take last segment after last "-"
project = proj_dir.split("-")[-1] if proj_dir.startswith("-") else proj_dir

entry = {
    "session_id": sid or os.path.basename(session_file).replace(".jsonl", ""),
    "project": project,
    "started": started,
    "ended": ended,
    "model": model,
    "prompts": prompts,
    "total_tokens": total,
    "cache_read": tcr,
    "cache_write": tcw,
    "input": ti,
    "output": to,
    "subagents": subagents,
    "tools": dict(tool_counts),
}

# Dedupe: remove any prior row for this session_id, then append
rows = []
if os.path.exists(hist_file):
    try:
        with open(hist_file, encoding="utf-8", errors="ignore") as f:
            for line in f:
                try:
                    r = json.loads(line)
                    if r.get("session_id") != entry["session_id"]:
                        rows.append(r)
                except:
                    continue
    except Exception:
        pass

rows.append(entry)

# Cap at 500 rows (~6 months of daily usage) to bound file size
rows = rows[-500:]

with open(hist_file, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PYEOF
