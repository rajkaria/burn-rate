#!/usr/bin/env bash
# ============================================================================
# burn-rate lint — audit CLAUDE.md files for bloat
# Every line in a project-root or global CLAUDE.md is silently injected into
# every session's context. Large or duplicated instructions cost real tokens.
# ============================================================================

set -uo pipefail

# Arg handling
TARGET="${1:-}"

W=78
hr() { printf '%*s\n' "$W" '' | tr ' ' '─'; }

# Collect candidate files
FILES=()
if [ -n "$TARGET" ]; then
  if [ -f "$TARGET" ]; then
    FILES+=("$TARGET")
  else
    echo "Not a file: $TARGET"; exit 1
  fi
else
  [ -f "CLAUDE.md" ] && FILES+=("$(pwd)/CLAUDE.md")
  [ -f "$HOME/.claude/CLAUDE.md" ] && FILES+=("$HOME/.claude/CLAUDE.md")
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No CLAUDE.md found in $(pwd) or ~/.claude/ — auditing context docs + MCP only."
else
for F in "${FILES[@]}"; do
  python3 - "$F" << 'PYEOF'
import sys, os, re, hashlib
from collections import Counter, defaultdict

path = sys.argv[1]
try:
    text = open(path, encoding="utf-8", errors="ignore").read()
except Exception as e:
    print(f"Cannot read {path}: {e}")
    sys.exit(0)

lines = text.splitlines()
chars = len(text)
# Rough token estimate: ~4 chars/token for English prose
est_tokens = chars // 4

# Section breakdown (by ## heading)
sections = []
cur_name, cur_lines = "(preamble)", []
for ln in lines:
    if ln.startswith("## "):
        sections.append((cur_name, cur_lines))
        cur_name, cur_lines = ln[3:].strip(), []
    else:
        cur_lines.append(ln)
sections.append((cur_name, cur_lines))

# Duplicate-paragraph detection (normalized, ≥ 40 chars)
paras = [p.strip() for p in re.split(r"\n{2,}", text) if p.strip()]
norm = [re.sub(r"\s+", " ", p.lower()) for p in paras]
hashes = Counter()
para_by_hash = {}
for p, n in zip(paras, norm):
    if len(n) < 40: continue
    h = hashlib.md5(n.encode()).hexdigest()
    hashes[h] += 1
    para_by_hash.setdefault(h, p)
dupes = [(para_by_hash[h], c) for h, c in hashes.items() if c >= 2]

# Verdict
if est_tokens >= 8000 or len(lines) >= 1000:
    verdict = "🔥 BLOATED — this file adds massive overhead to every session"
elif est_tokens >= 3000 or len(lines) >= 400:
    verdict = "⚠️  HEAVY — consider splitting or pruning"
elif est_tokens >= 1000 or len(lines) >= 150:
    verdict = "🟡 MODERATE — watch the growth"
else:
    verdict = "✅ LEAN — good"

def fmt(n):
    if n >= 1_000_000: return f"{n/1e6:.1f}M"
    if n >= 1_000:     return f"{n/1e3:.1f}K"
    return str(n)

# --- Print report ---
W = 78
print()
def row(s, W=78):
    s = s[:W-4]
    return "│ " + s + " " * (W - 3 - len(s)) + "│"
def title(s, W=78):
    s = f" {s} "
    pad = W - 2 - len(s)
    l = pad // 2
    return "┌" + "─"*l + s + "─"*(pad-l) + "┐"
def footer(W=78): return "└" + "─"*(W-2) + "┘"

print(title("BURN-RATE LINT"))
print(row(f"File: {path}"))
print(row(verdict))
print(footer())

print()
print(title("SIZE"))
print(row(f"Lines:            {len(lines)}"))
print(row(f"Characters:       {fmt(chars)}"))
print(row(f"Estimated tokens: ~{fmt(est_tokens)}   (re-sent every prompt)"))
print(footer())

# Sections table
if len(sections) > 1:
    print()
    print(title("SECTIONS (## headings)"))
    for name, body in sorted(sections, key=lambda x: -len(x[1])):
        n = len(body)
        flag = "  🚨" if n >= 200 else ("  ⚠️" if n >= 100 else "")
        nm = (name[:W-20]) if len(name) > W-20 else name
        print(row(f"{n:>4} lines  {nm}{flag}"))
    print(footer())

# Duplicates
if dupes:
    print()
    print(title("DUPLICATED PARAGRAPHS"))
    for p, c in sorted(dupes, key=lambda x: -x[1])[:5]:
        preview = re.sub(r"\s+", " ", p)[:W-12]
        print(row(f"{c}× — “{preview}”"))
    print(footer())

# Recommendations
print()
print(title("RECOMMENDATIONS"))
tips = []
if est_tokens >= 3000:
    tips.append(f"• ~{fmt(est_tokens)} tokens × every prompt — prune aggressively")
biggest = max(sections, key=lambda x: len(x[1]))
if len(biggest[1]) >= 100:
    tips.append(f"• Biggest section '{biggest[0]}' is {len(biggest[1])} lines — move details to a linked file")
if dupes:
    tips.append(f"• {len(dupes)} duplicated paragraphs — consolidate")
if len(lines) >= 400:
    tips.append("• Split by topic: CONTRIBUTING.md, ARCHITECTURE.md, etc. — reference from CLAUDE.md")
tips.append("• Move rarely-used context into project docs, not CLAUDE.md")
if not tips:
    tips = ["• Nothing to fix. Keep it this tight."]
for t in tips[:6]:
    print(row(t))
print(footer())
print()
PYEOF
done
fi

# --- Context Router docs audit (docs/context/) ---
CTX_DIR="${BURN_RATE_CONTEXT_DIR:-docs/context}"
if [ -d "$CTX_DIR" ]; then
  python3 - "$CTX_DIR" << 'PYEOF'
import sys, os, re
from datetime import datetime

ctx = sys.argv[1]
W = 78
def row(s, W=78):
    s = s[:W-4]; return "│ " + s + " " * (W - 3 - len(s)) + "│"
def title(s, W=78):
    s = f" {s} "; pad = W - 2 - len(s); l = pad // 2
    return "┌" + "─"*l + s + "─"*(pad-l) + "┐"
def footer(W=78): return "└" + "─"*(W-2) + "┘"

def frontmatter(text):
    globs, updated = [], None
    if not text.startswith("---"):
        return globs, updated
    end = text.find("\n---", 3)
    if end == -1:
        return globs, updated
    key = None
    for raw in text[3:end].splitlines():
        line = raw.rstrip()
        m = re.match(r"^(\w[\w-]*):\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if key == "globs" and val.startswith("[") and val.endswith("]"):
                globs = [g.strip().strip("'\"") for g in val[1:-1].split(",") if g.strip()]
            elif key == "updated":
                updated = val.strip("'\"") or None
        elif key == "globs" and line.strip().startswith("-"):
            g = line.strip()[1:].strip().strip("'\"")
            if g:
                globs.append(g)
    return globs, updated

AGING_DAYS = int(os.environ.get("BURN_RATE_CONTEXT_AGING_DAYS", "30"))
docs = sorted(f for f in os.listdir(ctx) if f.endswith(".md"))
if docs:
    print(title("CONTEXT DOCS (docs/context/)"))
    print(row(f"{len(docs)} feature docs — the router loads these on demand"))
    print(footer())
    print()
    print(title("PER-DOC"))
    findings = []
    for fn in docs:
        fp = os.path.join(ctx, fn)
        try:
            text = open(fp, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        globs, updated = frontmatter(text)
        est = len(text) // 4
        flags = []
        if not globs and fn not in ("_overview.md", "overview.md"):
            flags.append("no globs -> UNROUTABLE")
        if est >= 1200 or text.count("\n") >= 200:
            flags.append(f"bloated ~{est}t")
        if updated:
            try:
                age = (datetime.now() - datetime.strptime(updated.strip()[:10], "%Y-%m-%d")).days
                if age > AGING_DAYS:
                    flags.append(f"aging {age}d")
            except ValueError:
                flags.append("bad updated: date")
        else:
            flags.append("no updated: date")
        tag = ("  ! " + "; ".join(flags)) if flags else "  ok"
        print(row(f"{fn:<26} ~{est:>4}t{tag}"))
        for fl in flags:
            findings.append((fn, fl))
    print(footer())
    if findings:
        print()
        print(title("CONTEXT RECOMMENDATIONS"))
        if any("UNROUTABLE" in f for _, f in findings):
            print(row("- Add globs: frontmatter so the router can load these docs"))
        if any("bloated" in f for _, f in findings):
            print(row("- Split bloated feature docs - they undercut the router's savings"))
        if any(("aging" in f or "no updated" in f) for _, f in findings):
            print(row("- Refresh stale docs via /save-context, or prune dead ones"))
        print(footer())
    print()
PYEOF
fi

# --- MCP / tool-schema audit (what's re-sent every turn besides CLAUDE.md) ---
python3 - << 'PYEOF'
import json, os

W = 78
def row(s, W=78):
    s = s[:W-4]; return "│ " + s + " " * (W - 3 - len(s)) + "│"
def title(s, W=78):
    s = f" {s} "; pad = W - 2 - len(s); l = pad // 2
    return "┌" + "─"*l + s + "─"*(pad-l) + "┐"
def footer(W=78): return "└" + "─"*(W-2) + "┘"

home = os.path.expanduser("~")
eager = {}          # name -> source (eagerly-loaded = schema in every turn)
plugins = 0

def add(servers, src):
    if isinstance(servers, dict):
        for name in servers:
            eager.setdefault(name, src)

# Project-scoped .mcp.json (loads eagerly once the project is trusted)
if os.path.isfile(".mcp.json"):
    try:
        add(json.load(open(".mcp.json")).get("mcpServers", {}), ".mcp.json")
    except Exception:
        pass

# ~/.claude.json — global + per-project mcpServers
cj = os.path.join(home, ".claude.json")
if os.path.isfile(cj):
    try:
        d = json.load(open(cj))
        add(d.get("mcpServers", {}), "~/.claude.json")
        proj = d.get("projects", {}).get(os.getcwd())
        if isinstance(proj, dict):
            add(proj.get("mcpServers", {}), "~/.claude.json (this project)")
    except Exception:
        pass

# settings.json / settings.local.json — mcpServers + enabledPlugins
for s in ("settings.json", "settings.local.json"):
    p = os.path.join(home, ".claude", s)
    if os.path.isfile(p):
        try:
            d = json.load(open(p))
            add(d.get("mcpServers", {}), f"~/.claude/{s}")
            plugins = max(plugins, sum(1 for v in d.get("enabledPlugins", {}).values() if v))
        except Exception:
            pass

print()
print(title("MCP / TOOL SCHEMAS (re-sent every turn)"))
if eager:
    print(row(f"{len(eager)} eagerly-loaded MCP server(s) — schema in EVERY prompt:"))
    for name, src in sorted(eager.items()):
        print(row(f"  - {name}   ({src})"))
    print(row(""))
    print(row("Each adds its full tool schema to context on every turn. Disable any"))
    print(row("you don't use; prefer servers/plugins that defer tool loading."))
else:
    print(row("OK - no eagerly-loaded mcpServers found."))
    if plugins:
        print(row(f"  {plugins} plugin(s) enabled; their tools are deferred (ToolSearch),"))
        print(row("  so they don't tax every turn."))
print(footer())
print()
PYEOF
