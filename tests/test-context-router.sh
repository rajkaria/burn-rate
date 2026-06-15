#!/usr/bin/env bash
# ============================================================================
# Smoke tests for the burn-rate context router (scripts/burn-rate-resume.sh).
# Self-contained: builds throwaway git repos in $TMPDIR, asserts on the hook's
# injected output. Run:  bash tests/test-context-router.sh
# ============================================================================

set -uo pipefail

ROUTER="$(cd "$(dirname "$0")/.." && pwd)/scripts/burn-rate-resume.sh"
PASS=0
FAIL=0

red()   { printf '\033[0;31m%s\033[0m\n' "$1"; }
green() { printf '\033[0;32m%s\033[0m\n' "$1"; }

ok()   { green "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { red   "  ✗ $1"; FAIL=$((FAIL+1)); }

# assert_contains <haystack> <needle> <msg>
assert_contains() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 (missing: $2)";; esac; }
assert_absent()   { case "$1" in *"$2"*) bad "$3 (unexpected: $2)";; *) ok "$3";; esac; }

newrepo() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email test@test.dev
  git -C "$d" config user.name  test
  git -C "$d" config commit.gpgsign false
  echo "$d"
}
mkdoc() { # <repo> <name> <globs-inline> <updated> <body>
  mkdir -p "$1/docs/context"
  cat > "$1/docs/context/$2.md" <<EOF
---
feature: $2
globs: $3
updated: $4
---
$5
EOF
}
run() { CLAUDE_PROJECT_DIR="$1" bash "$ROUTER" 2>&1; }

echo "context router smoke tests"
echo "=========================="

# --- 1. routes by working-tree change -------------------------------------
echo "[1] routes by working-tree change"
D=$(newrepo)
mkdoc "$D" alpha "[src/alpha.*]" 2026-06-15 "ALPHA-BODY-MARKER"
mkdoc "$D" beta  "[src/beta.*]"  2026-06-15 "BETA-BODY-MARKER"
git -C "$D" add -A && git -C "$D" commit -qm init
mkdir -p "$D/src"; echo "x" > "$D/src/alpha.py"   # touch alpha only (untracked)
OUT="$(run "$D")"
assert_contains "$OUT" "alpha :: "        "alpha selected"
assert_absent   "$OUT" "beta :: "         "beta NOT selected"
assert_contains "$OUT" "ALPHA-BODY-MARKER" "alpha body injected"
assert_contains "$OUT" "• beta"           "beta still in index"
rm -rf "$D"

# --- 2. respects the doc cap ----------------------------------------------
echo "[2] respects BURN_RATE_ROUTER_MAX_DOCS"
D=$(newrepo)
for n in one two three four; do mkdoc "$D" "$n" "[src/shared.*]" 2026-06-15 "BODY-$n"; done
git -C "$D" add -A && git -C "$D" commit -qm init
mkdir -p "$D/src"; echo "x" > "$D/src/shared.py"
OUT="$(CLAUDE_PROJECT_DIR="$D" BURN_RATE_ROUTER_MAX_DOCS=2 bash "$ROUTER" 2>&1)"
CNT=$(printf '%s\n' "$OUT" | grep -c ' :: ')
[ "$CNT" -eq 2 ] && ok "exactly 2 docs selected (got $CNT)" || bad "cap not respected (got $CNT)"
rm -rf "$D"

# --- 3. flags stale docs ---------------------------------------------------
echo "[3] flags stale docs"
D=$(newrepo)
mkdoc "$D" gamma "[src/gamma.*]" 2000-01-01 "GAMMA-BODY"
git -C "$D" add -A && git -C "$D" commit -qm init
mkdir -p "$D/src"; echo "x" > "$D/src/gamma.py"
OUT="$(run "$D")"
assert_contains "$OUT" "may be out of date" "stale flag on the selected doc"
rm -rf "$D"

# --- 4. legacy mode: no docs/context, CLAUDE.md has a session block --------
echo "[4] legacy fallback (## Session Context)"
D=$(newrepo)
cat > "$D/CLAUDE.md" <<EOF
# Proj
## Session Context (Last updated: $(date +%Y-%m-%d) 09:00)
### Current State
LEGACY-BLOCK-MARKER
EOF
git -C "$D" add -A && git -C "$D" commit -qm init
OUT="$(run "$D")"
assert_contains "$OUT" "BURN RATE RESUME"     "legacy resume banner"
assert_contains "$OUT" "LEGACY-BLOCK-MARKER"  "legacy block body injected"
rm -rf "$D"

# --- 5. disabled via env ---------------------------------------------------
echo "[5] disabled via BURN_RATE_NO_ROUTER"
D=$(newrepo)
mkdoc "$D" delta "[src/delta.*]" 2026-06-15 "DELTA-BODY"
git -C "$D" add -A && git -C "$D" commit -qm init
mkdir -p "$D/src"; echo x > "$D/src/delta.py"
OUT="$(CLAUDE_PROJECT_DIR="$D" BURN_RATE_NO_ROUTER=1 bash "$ROUTER" 2>&1)"
[ -z "$OUT" ] && ok "no output when disabled" || bad "expected empty output"
rm -rf "$D"

# --- 6. clean tree falls back to recent commits ----------------------------
echo "[6] clean tree routes by recent commits"
D=$(newrepo)
mkdoc "$D" epsilon "[src/epsilon.*]" 2026-06-15 "EPSILON-BODY"
git -C "$D" add -A && git -C "$D" commit -qm init
mkdir -p "$D/src"; echo x > "$D/src/epsilon.py"
git -C "$D" add -A && git -C "$D" commit -qm "work on epsilon"   # now tree is clean
OUT="$(run "$D")"
assert_contains "$OUT" "epsilon :: " "epsilon selected from commit history"
rm -rf "$D"

# --- 7. no docs + no legacy block = silent --------------------------------
echo "[7] silent when nothing to route"
D=$(newrepo)
echo "# empty" > "$D/CLAUDE.md"
git -C "$D" add -A && git -C "$D" commit -qm init
OUT="$(run "$D")"
[ -z "$OUT" ] && ok "no output" || bad "expected empty output"
rm -rf "$D"

echo "=========================="
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
