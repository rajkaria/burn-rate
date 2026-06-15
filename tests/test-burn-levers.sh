#!/usr/bin/env bash
# ============================================================================
# Tests for the burn levers: MCP/tool-schema audit, the project-key convention
# used by the session-lookup fallback, and the strategic-compact wiring.
# Run:  bash tests/test-burn-levers.sh
# ============================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/scripts/burn-rate-lint.sh"
PASS=0; FAIL=0
ok()  { printf '\033[0;32m  ✓ %s\033[0m\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '\033[0;31m  ✗ %s\033[0m\n' "$1"; FAIL=$((FAIL+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 (missing: $2)";; esac; }
no()  { case "$1" in *"$2"*) bad "$3 (unexpected: $2)";; *) ok "$3";; esac; }

echo "burn levers tests"
echo "================="

# --- 1. project-key convention: / and . both become - (worktree .claude path) ---
echo "[1] project-key handles /.claude worktree paths"
KEY="-$(printf '%s' "/Users/x/Projects/app/.claude/worktrees/wt-1" | sed 's|[/.]|-|g' | sed 's|^-||')"
[ "$KEY" = "-Users-x-Projects-app--claude-worktrees-wt-1" ] \
  && ok "key = $KEY" || bad "wrong key: $KEY"

# --- 2. MCP audit flags an eagerly-loaded server (HOME isolated) ---
echo "[2] MCP audit flags eager mcpServers"
H=$(mktemp -d); P=$(mktemp -d)
mkdir -p "$H/.claude"
cat > "$P/.mcp.json" <<'JSON'
{ "mcpServers": { "weather-api": { "command": "node", "args": ["x.js"] } } }
JSON
OUT="$(cd "$P" && HOME="$H" bash "$LINT" 2>&1)"
has "$OUT" "MCP / TOOL SCHEMAS" "MCP section present"
has "$OUT" "weather-api"        "eager server listed"
has "$OUT" "eagerly-loaded"     "flagged as eager"
rm -rf "$H" "$P"

# --- 3. MCP audit reports clean when there are no eager servers ---
echo "[3] MCP audit reports clean with no mcpServers"
H=$(mktemp -d); P=$(mktemp -d)
mkdir -p "$H/.claude"
printf '{ "enabledPlugins": { "a@x": true, "b@y": true } }' > "$H/.claude/settings.json"
OUT="$(cd "$P" && HOME="$H" bash "$LINT" 2>&1)"
has "$OUT" "no eagerly-loaded mcpServers" "reports clean"
has "$OUT" "2 plugin(s) enabled"          "counts deferred plugins"
no  "$OUT" "in EVERY prompt"              "no false eager warning"
rm -rf "$H" "$P"

# --- 4. strategic-compact + lull wiring present in burn-rate.sh ---
echo "[4] strategic-compact wiring present"
SRC="$(cat "$ROOT/scripts/burn-rate.sh")"
has "$SRC" "STRATEGIC COMPACT"            "strategic compact message"
has "$SRC" "BURN_RATE_NO_COMPACT_TIP"     "opt-out env var"
has "$SRC" "int(lull)"                    "lull emitted from analyzer"

echo "================="
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
