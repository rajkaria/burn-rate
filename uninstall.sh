#!/usr/bin/env bash
# ============================================================================
# Burn Rate Uninstaller
# Removes the burn-rate hook, commands, and optionally the CLAUDE.md rules.
# https://github.com/rajkaria/burn-rate
# ============================================================================

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; NC=''
fi

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

echo ""
echo "  Burn Rate Uninstaller"
echo "  ====================="
echo ""

# --- Remove scripts and config ---
for file in burn-rate.sh pricing.json; do
  if [ -f "$SCRIPTS_DIR/$file" ]; then
    rm "$SCRIPTS_DIR/$file"
    info "Removed $file"
  fi
done

# --- Remove commands ---
for cmd in save-context.md burn-rate.md; do
  if [ -f "$COMMANDS_DIR/$cmd" ]; then
    rm "$COMMANDS_DIR/$cmd"
    info "Removed /$(basename "$cmd" .md) command"
  fi
done

# --- Remove hook from settings.json ---
if [ -f "$SETTINGS_FILE" ] && grep -q "burn-rate" "$SETTINGS_FILE" 2>/dev/null; then
  python3 << 'PYEOF'
import json, os

settings_file = os.path.expanduser("~/.claude/settings.json")

with open(settings_file) as f:
    settings = json.load(f)

if "hooks" in settings and "UserPromptSubmit" in settings["hooks"]:
    settings["hooks"]["UserPromptSubmit"] = [
        h for h in settings["hooks"]["UserPromptSubmit"]
        if not any("burn-rate" in hook.get("command", "") for hook in h.get("hooks", []))
    ]
    # Clean up empty arrays/objects
    if not settings["hooks"]["UserPromptSubmit"]:
        del settings["hooks"]["UserPromptSubmit"]
    if not settings["hooks"]:
        del settings["hooks"]

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
  info "Removed hook from settings.json"
fi

# --- Prompt about CLAUDE.md ---
if [ -f "$CLAUDE_MD" ] && grep -q "Burn Rate" "$CLAUDE_MD" 2>/dev/null; then
  warn "Burn Rate rules found in ~/.claude/CLAUDE.md"
  echo "  You may want to manually edit this file to remove the"
  echo "  '# Global Rules (Burn Rate)' section if you no longer need it."
  echo ""
fi

info "Uninstall complete."
echo ""
