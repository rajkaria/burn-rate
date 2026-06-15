#!/usr/bin/env bash
# ============================================================================
# Burn Report — visual session postmortem
# Shows where your tokens actually went: top re-read files, context jumps,
# subagent storms, paste bombs.
# ============================================================================

set -uo pipefail

PROJECTS_DIR="$HOME/.claude/projects"
[ -d "$PROJECTS_DIR" ] || { echo "No ~/.claude/projects directory."; exit 0; }

SESSION_ID="${CLAUDE_SESSION_ID:-}"
SESSION_FILE=""

if [ -n "$SESSION_ID" ]; then
  SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 2 -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
fi

# Allow override: burn-report.sh <path-or-session-id>
if [ -n "${1:-}" ]; then
  if [ -f "$1" ]; then
    SESSION_FILE="$1"
  else
    SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 2 -name "${1}.jsonl" -type f 2>/dev/null | head -1)
  fi
fi

if [ -z "$SESSION_FILE" ]; then
  SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 2 -name "*.jsonl" -type f -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null | head -1)
fi

[ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ] || { echo "No session file found."; exit 0; }

python3 - "$SESSION_FILE" << 'PYEOF'
import json, sys, os, re
from collections import Counter, defaultdict

session_file = sys.argv[1]

# ---------- Parse ----------
human_prompts = 0
total_in = total_cw = total_cr = total_out = 0
model = "opus"
started = ended = None

file_reads = Counter()             # path -> count
file_edits = Counter()
bash_cmds = Counter()
tool_counts = Counter()
subagent_spawns = 0
turn_tokens = []                   # per-assistant-turn total tokens
paste_sizes = []                   # (chars, preview)
last_cache_read = 0
cache_read_jumps = []              # (prompt_num, delta)

def truncate(s, n=60):
    s = s.replace("\n", " ").replace("\r", " ")
    return s if len(s) <= n else s[:n-1] + "…"

with open(session_file, errors="ignore") as f:
    for line in f:
        try:
            o = json.loads(line)
        except Exception:
            continue

        ts = o.get("timestamp")
        if ts:
            started = started or ts
            ended = ts

        t = o.get("type")

        if t == "user":
            if o.get("isSidechain"): continue
            if o.get("userType") == "tool": continue
            msg = o.get("message", {})
            content = msg.get("content", "")
            if isinstance(content, list):
                types = [i.get("type") for i in content if isinstance(i, dict)]
                if types and all(x == "tool_result" for x in types):
                    continue
                # count text size for paste detection
                text = " ".join(i.get("text","") for i in content if isinstance(i,dict) and i.get("type")=="text")
            else:
                text = content if isinstance(content,str) else ""
            human_prompts += 1
            if len(text) >= 2000:
                paste_sizes.append((len(text), truncate(text, 80)))

        elif t == "assistant":
            msg = o.get("message", {})
            u = msg.get("usage", {})
            ti = u.get("input_tokens", 0)
            tcw = u.get("cache_creation_input_tokens", 0)
            tcr = u.get("cache_read_input_tokens", 0)
            to = u.get("output_tokens", 0)
            total_in += ti; total_cw += tcw; total_cr += tcr; total_out += to
            turn_total = ti + tcw + tcr + to
            if turn_total > 0:
                turn_tokens.append(turn_total)
            # context jump detection
            if tcr > last_cache_read and last_cache_read > 0:
                delta = tcr - last_cache_read
                if delta > 100_000:
                    cache_read_jumps.append((human_prompts, delta))
            last_cache_read = max(last_cache_read, tcr)

            m = msg.get("model","")
            if "haiku" in m.lower(): model = "haiku"
            elif "sonnet" in m.lower(): model = "sonnet"

            content = msg.get("content", [])
            if isinstance(content, list):
                for b in content:
                    if not isinstance(b, dict): continue
                    if b.get("type") != "tool_use": continue
                    name = b.get("name","?")
                    tool_counts[name] += 1
                    inp = b.get("input", {}) or {}
                    if name == "Read":
                        p = inp.get("file_path","")
                        if p: file_reads[p] += 1
                    elif name in ("Edit","Write","NotebookEdit"):
                        p = inp.get("file_path","") or inp.get("notebook_path","")
                        if p: file_edits[p] += 1
                    elif name == "Bash":
                        cmd = (inp.get("command","") or "").strip().split("\n")[0][:80]
                        if cmd: bash_cmds[cmd] += 1
                    elif name in ("Task","Agent"):
                        subagent_spawns += 1

total_tokens = total_in + total_cw + total_cr + total_out

def fmt(n):
    if n >= 1_000_000_000: return f"{n/1e9:.2f}B"
    if n >= 1_000_000:     return f"{n/1e6:.1f}M"
    if n >= 1_000:         return f"{n/1e3:.1f}K"
    return str(n)

def bar(frac, width=30):
    frac = max(0.0, min(1.0, frac))
    filled = int(frac * width)
    return "█" * filled + "░" * (width - filled)

# ---------- Verdict ----------
tpp = total_tokens // human_prompts if human_prompts else 0
if total_tokens >= 100_000_000 or human_prompts >= 40:
    verdict = "🔥 RUNAWAY — this session cost ~5x what it should have"
elif total_tokens >= 60_000_000 or human_prompts >= 25:
    verdict = "⚠️  HEAVY — save-context before it gets worse"
elif total_tokens >= 30_000_000 or human_prompts >= 15:
    verdict = "🟡 WARM — consider /compact"
else:
    verdict = "✅ LEAN — good discipline"

W = 78
def hr(ch="─"): return ch * W
def title(s):
    s = f" {s} "
    pad = W - len(s)
    left = pad // 2
    return "┌" + "─"*left + s + "─"*(pad-left) + "┐"
def row(s):
    s = s[:W-2]
    return "│ " + s + " " * (W - 2 - len(s) - 1) + "│"
def footer(): return "└" + "─"*(W-2) + "┘"

print()
print(title("BURN REPORT"))
print(row(f"Session: {os.path.basename(session_file)}"))
if started and ended:
    print(row(f"Window:  {started[:19]} → {ended[:19]}"))
print(row(f"Model:   {model}"))
print(row(verdict))
print(footer())

# ---------- Totals ----------
print()
print(title("TOTALS"))
print(row(f"Human prompts:        {human_prompts}"))
print(row(f"Total tokens:         {fmt(total_tokens)}"))
print(row(f"Tokens per prompt:    {fmt(tpp)}   ← burn velocity"))
print(row(f"Tools invoked:        {sum(tool_counts.values())}"))
print(row(f"Subagents spawned:    {subagent_spawns}"))
print(footer())

# ---------- Breakdown bars ----------
print()
print(title("WHERE YOUR TOKENS WENT"))
if total_tokens > 0:
    parts = [
        ("cache reads  (re-sent)", total_cr),
        ("cache writes (new)    ", total_cw),
        ("input        (uncached)", total_in),
        ("output       (reply)  ", total_out),
    ]
    for label, n in parts:
        pct = n / total_tokens
        print(row(f"{label} {bar(pct, 24)} {fmt(n):>7} {pct*100:4.1f}%"))
else:
    print(row("(no token usage recorded)"))
print(footer())

# ---------- Top re-read files (the "42 times" moment) ----------
print()
print(title("FILES RE-READ (the silent killer)"))
if file_reads:
    shown = 0
    for path, cnt in file_reads.most_common(10):
        flag = "  🚨" if cnt >= 5 else ("  ⚠️" if cnt >= 3 else "")
        short = path if len(path) <= W-16 else "…" + path[-(W-17):]
        print(row(f"{cnt:>3}×  {short}{flag}"))
        shown += 1
    if shown == 0:
        print(row("(none)"))
else:
    print(row("(no Read calls)"))
print(footer())

# ---------- Re-read cost (avoidable tokens) ----------
import os as _os
_redundant = sum(c - 1 for c in file_reads.values() if c > 1)
if _redundant:
    _waste = 0
    for _p, _c in file_reads.items():
        if _c > 1:
            try:
                _waste += (_c - 1) * (_os.path.getsize(_p) // 4)
            except OSError:
                pass
    print()
    print(title("RE-READ COST (avoidable)"))
    _msg = f"{_redundant} redundant re-read(s)"
    if _waste:
        _msg += f"  ≈ {fmt(_waste)} tokens re-injected"
    print(row(_msg))
    print(row("Each re-read re-sends the whole file into context. Fix: keep the"))
    print(row("file pinned, or let claude-mem semantic-prime instead of re-Reading."))
    print(footer())

# ---------- Top edits ----------
if file_edits:
    print()
    print(title("FILES EDITED"))
    for path, cnt in file_edits.most_common(8):
        short = path if len(path) <= W-10 else "…" + path[-(W-11):]
        print(row(f"{cnt:>3}×  {short}"))
    print(footer())

# ---------- Tool usage ----------
print()
print(title("TOOL USAGE"))
top_tools = tool_counts.most_common(8)
max_n = max((n for _,n in top_tools), default=1)
for name, n in top_tools:
    print(row(f"{name:<24} {bar(n/max_n, 24)} {n}"))
if not top_tools:
    print(row("(no tools used)"))
print(footer())

# ---------- Biggest turns ----------
if turn_tokens:
    print()
    print(title("BIGGEST CONTEXT TURNS (largest single-message cost)"))
    sorted_turns = sorted(enumerate(turn_tokens, 1), key=lambda x: -x[1])[:5]
    for idx, n in sorted_turns:
        pct = n / total_tokens if total_tokens else 0
        print(row(f"turn #{idx:<4}  {fmt(n):>7}  {bar(pct, 30)} {pct*100:4.1f}% of session"))
    print(footer())

# ---------- Context jumps ----------
if cache_read_jumps:
    print()
    print(title("CONTEXT JUMPS (>100K tokens added in one turn)"))
    for p, d in sorted(cache_read_jumps, key=lambda x: -x[1])[:5]:
        print(row(f"after prompt #{p:<3}  +{fmt(d):>7} re-read context"))
    print(footer())

# ---------- Paste bombs ----------
if paste_sizes:
    print()
    print(title("PASTE BOMBS (user messages ≥ 2K chars — re-sent every turn)"))
    for size, preview in sorted(paste_sizes, key=lambda x: -x[0])[:5]:
        print(row(f"{fmt(size):>6} chars  “{preview}”"))
    print(footer())

# ---------- Top bash commands ----------
if bash_cmds:
    print()
    print(title("TOP BASH COMMANDS"))
    for cmd, n in bash_cmds.most_common(5):
        print(row(f"{n:>2}×  {cmd[:W-8]}"))
    print(footer())

# ---------- Recommendations ----------
print()
print(title("WHAT TO DO NEXT"))
tips = []
worst_read = file_reads.most_common(1)
if worst_read and worst_read[0][1] >= 5:
    p, c = worst_read[0]
    tips.append(f"• {os.path.basename(p)} read {c}× — pin it or start fresh session")
if subagent_spawns >= 8:
    tips.append(f"• {subagent_spawns} subagents spawned — prefer Grep/Glob for narrow searches")
if paste_sizes and paste_sizes[0][0] >= 10_000:
    tips.append(f"• Pasted {fmt(paste_sizes[0][0])} chars — move large blobs to a file and reference it")
if tpp >= 3_000_000:
    tips.append(f"• {fmt(tpp)}/prompt is heavy — /save-context and start fresh")
if total_cr and total_tokens and total_cr / total_tokens > 0.9:
    tips.append(f"• {total_cr/total_tokens*100:.0f}% is re-sent context — session length is the problem")
if not tips:
    tips.append("• Session is lean. Keep doing what you're doing.")
for t in tips[:6]:
    print(row(t))
print(footer())
print()
PYEOF
