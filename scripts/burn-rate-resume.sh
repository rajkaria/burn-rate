#!/usr/bin/env bash
# ============================================================================
# burn-rate context router — SessionStart hook
# ----------------------------------------------------------------------------
# Loads ONLY the project context relevant to what you're about to work on,
# instead of dragging a monolithic CLAUDE.md into every session.
#
#   • ROUTER MODE  — if ./docs/context/*.md exists, each doc declares `globs:`
#                    in its frontmatter. The hook looks at which files you've
#                    been touching (recent commits + uncommitted changes) and
#                    injects only the docs whose globs match, plus a thin index
#                    of everything available. Capped, so it can never re-bloat.
#
#   • LEGACY MODE  — if there's no docs/context/ but CLAUDE.md still has a
#                    "## Session Context" block, behave exactly like the old
#                    resume hook (inject that block). Nothing breaks pre-migration.
#
# Never auto-executes anything — priming only. Always exits 0.
# Disable with BURN_RATE_NO_RESUME=1 (or BURN_RATE_NO_ROUTER=1).
# ============================================================================

set -uo pipefail

if [ "${BURN_RATE_NO_RESUME:-0}" = "1" ] || [ "${BURN_RATE_NO_ROUTER:-0}" = "1" ]; then
  exit 0
fi

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
CTX_DIR="${BURN_RATE_CONTEXT_DIR:-docs/context}"
MAX_DOCS="${BURN_RATE_ROUTER_MAX_DOCS:-3}"
MAX_CHARS="${BURN_RATE_ROUTER_MAX_CHARS:-1500}"
MAX_AGE_DAYS="${BURN_RATE_RESUME_MAX_AGE_DAYS:-7}"
LOOKBACK="${BURN_RATE_ROUTER_LOOKBACK:-5}"

python3 - "$CWD" "$CTX_DIR" "$MAX_DOCS" "$MAX_CHARS" "$MAX_AGE_DAYS" "$LOOKBACK" << 'PYEOF'
import sys, os, re, subprocess, fnmatch
from datetime import datetime

cwd       = sys.argv[1]
ctx_dir   = os.path.join(cwd, sys.argv[2])
max_docs  = int(sys.argv[3])
max_chars = int(sys.argv[4])
max_age   = int(sys.argv[5])
lookback  = int(sys.argv[6])


def git(*args):
    try:
        return subprocess.check_output(
            ["git", "-C", cwd, *args],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
    except Exception:
        return ""


def changed_sets():
    """Returns (working_tree, recent_commits).

    working_tree = what you're editing NOW (strongest signal for "what is this
    session about"); recent_commits = what was worked on lately (carries the
    routing when the tree is clean, e.g. resuming after a break)."""
    wt, commits = set(), set()
    # recent commits (clamp lookback to how many commits actually exist)
    count = git("rev-list", "--count", "HEAD")
    try:
        n = min(lookback, max(int(count) - 1, 0)) if count else 0
    except ValueError:
        n = 0
    if n > 0:
        for f in git("diff", "--name-only", f"HEAD~{n}..HEAD").splitlines():
            if f.strip():
                commits.add(f.strip())
    # uncommitted (staged + unstaged + untracked). --untracked-files=all so a
    # brand-new directory is listed file-by-file, not collapsed to "newdir/".
    for line in git("status", "--porcelain", "--untracked-files=all").splitlines():
        p = line[3:].strip() if len(line) > 3 else ""
        # handle "old -> new" renames
        if " -> " in p:
            p = p.split(" -> ", 1)[1]
        if p:
            wt.add(p)
    return wt, commits


def parse_frontmatter(text):
    """Minimal YAML-ish frontmatter parser. Returns (meta, body)."""
    meta = {"feature": None, "globs": [], "updated": None}
    if not text.startswith("---"):
        return meta, text
    end = text.find("\n---", 3)
    if end == -1:
        return meta, text
    fm = text[3:end].strip("\n")
    body = text[end + 4:].lstrip("\n")
    key = None
    for raw in fm.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        m = re.match(r"^(\w[\w-]*):\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if key == "globs":
                if val.startswith("[") and val.endswith("]"):
                    meta["globs"] = [g.strip().strip("'\"") for g in val[1:-1].split(",") if g.strip()]
                elif val:
                    meta["globs"] = [val.strip("'\"")]
                # else: list items follow on subsequent lines
            elif key in meta:
                meta[key] = val.strip("'\"") or None
        elif key == "globs":
            item = line.strip()
            if item.startswith("-"):
                g = item[1:].strip().strip("'\"")
                if g:
                    meta["globs"].append(g)
    return meta, body


def matches(path, globs):
    base = os.path.basename(path)
    hits = 0
    for g in globs:
        if fnmatch.fnmatch(path, g) or fnmatch.fnmatch(base, g):
            hits += 1
    return hits


def age_note(date_str, mtime):
    """Return (note, is_stale) from an `updated:` date or file mtime."""
    ts = None
    if date_str:
        for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d"):
            try:
                ts = datetime.strptime(date_str.strip(), fmt)
                break
            except ValueError:
                continue
    if ts is None and mtime:
        ts = datetime.fromtimestamp(mtime)
    if ts is None:
        return "", False
    age = (datetime.now() - ts).days
    if max_age > 0 and age > max_age:
        return f"stale {age}d", True
    if age <= 0:
        return "today", False
    if age == 1:
        return "1d ago", False
    return f"{age}d ago", False


def trim(body):
    return body if len(body) <= max_chars else body[:max_chars] + "\n… (truncated — open the doc for the rest)"


# ---------------------------------------------------------------------------
# ROUTER MODE
# ---------------------------------------------------------------------------
docs = []
if os.path.isdir(ctx_dir):
    for fn in sorted(os.listdir(ctx_dir)):
        if not fn.endswith(".md"):
            continue
        fp = os.path.join(ctx_dir, fn)
        try:
            text = open(fp, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        meta, body = parse_frontmatter(text)
        rel = os.path.relpath(fp, cwd)
        try:
            mtime = os.path.getmtime(fp)
        except OSError:
            mtime = 0
        docs.append({
            "name": fn, "rel": rel, "meta": meta, "body": body.strip(),
            "feature": meta["feature"] or fn[:-3], "mtime": mtime,
        })

if docs:
    wt, commits = changed_sets()
    # what you're editing now counts far more than what was recently committed
    WT_WEIGHT = 3
    try:
        ratio = float(os.environ.get("BURN_RATE_ROUTER_MIN_RATIO", "0.4"))
    except ValueError:
        ratio = 0.4
    for d in docs:
        g = d["meta"]["globs"]
        d["score"] = WT_WEIGHT * sum(matches(f, g) for f in wt) + sum(matches(f, g) for f in commits)

    ranked = sorted(docs, key=lambda d: (-d["score"], d["name"]))
    # keep only docs clearly relevant to the top signal — drops weakly-related
    # docs so a focused session loads one doc, not three
    top = ranked[0]["score"] if ranked else 0
    threshold = max(1, top * ratio)
    selected = [d for d in ranked if d["score"] > 0 and d["score"] >= threshold][:max_docs]

    # Default when nothing matched: fall back to _overview.md if present.
    if not selected:
        ov = next((d for d in docs if d["name"] in ("_overview.md", "overview.md")), None)
        if ov:
            selected = [ov]

    # --- Build the thin index (always) ---
    index_lines = []
    for d in sorted(docs, key=lambda d: d["name"]):
        note, _ = age_note(d["meta"]["updated"], d["mtime"])
        suffix = f"  [{note}]" if note else ""
        index_lines.append(f"  • {d['feature']} — {d['rel']}{suffix}")
    index = "\n".join(index_lines)

    out = []
    sel_names = {d["name"] for d in selected}
    if selected:
        out.append(
            "BURN RATE CONTEXT ROUTER: based on the files you've been touching, the "
            "project context below is most relevant. Acknowledge briefly and wait for "
            "direction — do not auto-resume work. Other context docs exist (see index); "
            "read them on demand if you need them."
        )
    else:
        out.append(
            "BURN RATE CONTEXT ROUTER: no feature docs matched recent changes. "
            "Available project context is indexed below — read the relevant doc on demand."
        )
    out.append(f"\n--- Context index ({len(docs)} docs) ---\n{index}")

    head = git("rev-parse", "--short", "HEAD")
    for d in selected:
        note, stale = age_note(d["meta"]["updated"], d["mtime"])
        flags = []
        if stale:
            flags.append(f"⚠ {note} — may be out of date, confirm before relying on it")
        sha = re.search(r"\b([0-9a-f]{7,12})\b", d["body"])
        if head and sha and not head.startswith(sha.group(1)[:7]) and not sha.group(1).startswith(head[:7]):
            flags.append(f"git HEAD is now {head}, doc references {sha.group(1)}")
        flag_str = ("  (" + "; ".join(flags) + ")") if flags else ""
        out.append(f"\n--- {d['feature']} :: {d['rel']}{flag_str} ---\n{trim(d['body'])}")

    print("\n".join(out))
    sys.exit(0)

# ---------------------------------------------------------------------------
# LEGACY MODE — no docs/context/, fall back to the old "## Session Context" block
# ---------------------------------------------------------------------------
cm = os.path.join(cwd, "CLAUDE.md")
if not os.path.isfile(cm):
    sys.exit(0)
try:
    text = open(cm, encoding="utf-8", errors="ignore").read()
except Exception:
    sys.exit(0)

m = re.search(
    r"^##\s+Session Context\s*(?:\(Last updated:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})(?:\s+([0-9]{2}:[0-9]{2}))?\))?\s*\n(.*?)(?=^##\s|\Z)",
    text, re.MULTILINE | re.DOTALL,
)
if not m:
    sys.exit(0)

date_str, time_str, body = m.group(1), m.group(2), m.group(3).strip()
if not body:
    sys.exit(0)

note, stale = age_note(f"{date_str} {time_str}".strip() if date_str else None, os.path.getmtime(cm))
note_txt = f" ({note})" if note else ""

head = git("rev-parse", "--short", "HEAD")
divergence = ""
sha = re.search(r"\b([0-9a-f]{7,12})\b", body)
if head and sha and not head.startswith(sha.group(1)[:7]) and not sha.group(1).startswith(head[:7]):
    divergence = f" Note: git HEAD is now {head}, block references {sha.group(1)}."

trimmed = body if len(body) <= 1500 else body[:1500] + "\n… (truncated — see CLAUDE.md for full context)"

if stale:
    print(f"BURN RATE RESUME: found session context in CLAUDE.md but it's stale{note_txt}. "
          f"Ask user whether to use it or start fresh — do not auto-resume.\n\n"
          f"--- Stale session context ---\n{trimmed}\n--- end ---")
else:
    print(f"BURN RATE RESUME: found session context in CLAUDE.md{note_txt}. "
          f"User likely wants to continue where they left off — acknowledge briefly "
          f"and wait for their direction.{divergence}\n\n"
          f"--- Session context ---\n{trimmed}\n--- end ---")
PYEOF

exit 0
