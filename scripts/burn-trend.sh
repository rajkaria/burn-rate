#!/usr/bin/env bash
# ============================================================================
# burn-trend — cross-session trend report from ~/.claude/.burn-rate/history.jsonl
# ============================================================================

set -uo pipefail

HIST_FILE="$HOME/.claude/.burn-rate/history.jsonl"
if [ ! -f "$HIST_FILE" ]; then
  echo "No history yet. Run a few sessions, then try again."
  echo "(History is written on SessionEnd or when you run /save-context.)"
  exit 0
fi

python3 - "$HIST_FILE" << 'PYEOF'
import json, sys, os
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

hist = sys.argv[1]
rows = []
with open(hist, encoding="utf-8", errors="ignore") as f:
    for line in f:
        try: rows.append(json.loads(line))
        except: continue

if not rows:
    print("History file empty.")
    sys.exit(0)

def parse_ts(s):
    try: return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except: return None

now = datetime.now(timezone.utc)
def bucket(dt, days_ago):
    if not dt: return False
    return (now - dt) <= timedelta(days=days_ago)

last7 = [r for r in rows if bucket(parse_ts(r.get("ended") or ""), 7)]
prev7 = [r for r in rows if parse_ts(r.get("ended") or "")
         and timedelta(days=7) < (now - parse_ts(r.get("ended"))) <= timedelta(days=14)]

def fmt(n):
    if n >= 1_000_000_000: return f"{n/1e9:.2f}B"
    if n >= 1_000_000:     return f"{n/1e6:.1f}M"
    if n >= 1_000:         return f"{n/1e3:.1f}K"
    return str(int(n))

def stats(rs):
    if not rs: return None
    tok = sum(r.get("total_tokens", 0) for r in rs)
    p   = sum(r.get("prompts", 0) for r in rs)
    s   = sum(r.get("subagents", 0) for r in rs)
    return {"sessions": len(rs), "tokens": tok, "prompts": p,
            "avg_tok": tok // len(rs), "tpp": tok // p if p else 0,
            "subagents": s}

W = 78
def row(s, W=W):
    s = s[:W-4]
    return "│ " + s + " " * (W - 3 - len(s)) + "│"
def title(s, W=W):
    s = f" {s} "
    pad = W - 2 - len(s); l = pad // 2
    return "┌" + "─"*l + s + "─"*(pad-l) + "┐"
def footer(W=W): return "└" + "─"*(W-2) + "┘"

print()
print(title("BURN-TREND"))
print(row(f"History: {hist}"))
print(row(f"Sessions logged: {len(rows)}"))
print(footer())

cur = stats(last7)
prev = stats(prev7)

print()
print(title("LAST 7 DAYS"))
if cur:
    print(row(f"Sessions:         {cur['sessions']}"))
    print(row(f"Total tokens:     {fmt(cur['tokens'])}"))
    print(row(f"Avg per session:  {fmt(cur['avg_tok'])}"))
    print(row(f"Tokens/prompt:    {fmt(cur['tpp'])}"))
    print(row(f"Subagents:        {cur['subagents']}"))
else:
    print(row("(no sessions in last 7 days)"))
print(footer())

# Week-over-week delta
if cur and prev:
    def pct(a, b):
        if not b: return "—"
        d = (a - b) * 100.0 / b
        sign = "+" if d >= 0 else ""
        return f"{sign}{d:.0f}%"
    print()
    print(title("WEEK-OVER-WEEK"))
    print(row(f"Tokens:           {fmt(prev['tokens'])} → {fmt(cur['tokens'])}   ({pct(cur['tokens'], prev['tokens'])})"))
    print(row(f"Avg per session:  {fmt(prev['avg_tok'])} → {fmt(cur['avg_tok'])}   ({pct(cur['avg_tok'], prev['avg_tok'])})"))
    print(row(f"Tokens/prompt:    {fmt(prev['tpp'])} → {fmt(cur['tpp'])}   ({pct(cur['tpp'], prev['tpp'])})"))
    d = cur['avg_tok'] - prev['avg_tok']
    if d < -cur['avg_tok'] * 0.2:
        print(row("🎉 Trending leaner — keep going."))
    elif d > prev['avg_tok'] * 0.2:
        print(row("⚠️  Sessions getting heavier — revisit habits."))
    print(footer())

# Top projects in last 7 days
if last7:
    by_proj = defaultdict(lambda: {"sessions": 0, "tokens": 0})
    for r in last7:
        k = r.get("project", "?") or "?"
        by_proj[k]["sessions"] += 1
        by_proj[k]["tokens"] += r.get("total_tokens", 0)
    top = sorted(by_proj.items(), key=lambda x: -x[1]["tokens"])[:5]
    print()
    print(title("TOP PROJECTS (last 7 days)"))
    for p, s in top:
        print(row(f"{fmt(s['tokens']):>7}  {s['sessions']:>2} sessions  {p}"))
    print(footer())

# Recent sessions table
print()
print(title("LAST 10 SESSIONS"))
for r in rows[-10:][::-1]:
    ended = (r.get("ended") or "")[:16].replace("T", " ")
    tok = fmt(r.get("total_tokens", 0))
    pr = r.get("prompts", 0)
    pj = (r.get("project", "?") or "?")[:20]
    print(row(f"{ended}  {pr:>3}p  {tok:>7}  {pj}"))
print(footer())
print()
PYEOF
