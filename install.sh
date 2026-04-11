#!/usr/bin/env bash
# ============================================================================
# Burn Rate Installer
# Installs the burn-rate hook, save-context command, and global rules
# for Claude Code. Works on macOS and Linux.
# https://github.com/rajkaria/burn-rate
# ============================================================================

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
REPO_URL="https://raw.githubusercontent.com/rajkaria/burn-rate/main"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; }

# --- Pre-checks ---
if [ ! -d "$CLAUDE_DIR" ]; then
  error "~/.claude directory not found. Is Claude Code installed?"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  error "python3 is required for safe settings.json merging."
  exit 1
fi

echo ""
echo -e "  ${BOLD}Burn Rate Installer${NC}"
echo "  ==================="
echo ""

# --- Create directories ---
mkdir -p "$SCRIPTS_DIR" "$COMMANDS_DIR"

# --- Determine source (local repo or curl pipe) ---
# When piped via `curl | bash`, BASH_SOURCE[0] is empty or "bash"
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "bash" ]; then
  CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  if [ -f "$CANDIDATE/scripts/burn-rate.sh" ]; then
    SCRIPT_DIR="$CANDIDATE"
  fi
fi

if [ -n "$SCRIPT_DIR" ]; then
  SOURCE="local"
  info "Installing from local repository..."
else
  SOURCE="remote"
  info "Downloading from GitHub..."
fi

fetch_file() {
  local src_path="$1"
  local dest="$2"
  if [ "$SOURCE" = "local" ]; then
    # Symlink so repo updates propagate without reinstall
    ln -sf "$SCRIPT_DIR/$src_path" "$dest"
  else
    curl -fsSL "$REPO_URL/$src_path" -o "$dest"
  fi
}

# --- Clean up old session-guard installation if present ---
if [ -f "$SCRIPTS_DIR/session-guard.sh" ]; then
  rm "$SCRIPTS_DIR/session-guard.sh"
  warn "Removed old session-guard.sh (replaced by burn-rate.sh)"
fi

# --- Install burn-rate.sh ---
fetch_file "scripts/burn-rate.sh" "$SCRIPTS_DIR/burn-rate.sh"
chmod +x "$SCRIPTS_DIR/burn-rate.sh"
info "Installed burn-rate.sh"

# --- Install save-context command ---
fetch_file "commands/save-context.md" "$COMMANDS_DIR/save-context.md"
info "Installed /save-context command"

# --- Install burn-rate stats command ---
fetch_file "commands/burn-rate.md" "$COMMANDS_DIR/burn-rate.md"
info "Installed /burn-rate command"

# --- Install pricing.json ---
fetch_file "pricing.json" "$SCRIPTS_DIR/pricing.json"
info "Installed pricing.json (edit to update when Anthropic changes rates)"

# --- Update settings.json with hook ---
if [ -f "$SETTINGS_FILE" ]; then
  if grep -q "burn-rate" "$SETTINGS_FILE" 2>/dev/null; then
    info "Hook already configured in settings.json (skipping)"
  else
    python3 << 'PYEOF'
import json, sys, os

settings_file = os.path.expanduser("~/.claude/settings.json")

try:
    with open(settings_file) as f:
        settings = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    print("Warning: Could not parse settings.json, creating backup", file=sys.stderr)
    settings = {}

hook_entry = {
    "matcher": "",
    "hooks": [{"type": "command", "command": "bash ~/.claude/scripts/burn-rate.sh"}]
}

if "hooks" not in settings:
    settings["hooks"] = {}

if "UserPromptSubmit" not in settings["hooks"]:
    settings["hooks"]["UserPromptSubmit"] = []

# Remove old session-guard hooks if present
settings["hooks"]["UserPromptSubmit"] = [
    h for h in settings["hooks"]["UserPromptSubmit"]
    if not any("session-guard" in hook.get("command", "") for hook in h.get("hooks", []))
]

# Check if burn-rate already present
existing = [h for h in settings["hooks"]["UserPromptSubmit"]
            if any("burn-rate" in hook.get("command", "") for hook in h.get("hooks", []))]

if not existing:
    settings["hooks"]["UserPromptSubmit"].append(hook_entry)

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
    info "Added UserPromptSubmit hook to settings.json"
  fi
else
  cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/burn-rate.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
  info "Created settings.json with hook"
fi

# --- Update global CLAUDE.md ---
if [ -f "$CLAUDE_MD" ]; then
  if grep -q "Burn Rate" "$CLAUDE_MD" 2>/dev/null; then
    info "Global CLAUDE.md already has Burn Rate rules (skipping)"
  else
    if grep -q "Session Guard" "$CLAUDE_MD" 2>/dev/null; then
      warn "Replacing old Session Guard rules with Burn Rate rules..."
      python3 << 'PYEOF'
import os
claude_md = os.path.expanduser("~/.claude/CLAUDE.md")
with open(claude_md) as f:
    content = f.read()
content = content.replace("Session Guard", "Burn Rate")
with open(claude_md, "w") as f:
    f.write(content)
PYEOF
      info "Updated CLAUDE.md (Session Guard -> Burn Rate)"
    else
      warn "Existing CLAUDE.md found. Appending Burn Rate rules..."
      echo "" >> "$CLAUDE_MD"
      fetch_file "claude-md-template.md" "/tmp/burn-rate-template.md"
      cat "/tmp/burn-rate-template.md" >> "$CLAUDE_MD"
      rm -f "/tmp/burn-rate-template.md"
      info "Appended Burn Rate rules to CLAUDE.md"
    fi
  fi
else
  fetch_file "claude-md-template.md" "$CLAUDE_MD"
  info "Created global CLAUDE.md with Burn Rate rules"
fi

# --- Done ---
echo ""
info "Installation complete!"
echo ""
echo "  What's installed:"
if [ "$SOURCE" = "local" ]; then
  echo "    - Hook:     ~/.claude/scripts/burn-rate.sh  -> repo (symlinked, auto-updates)"
else
  echo "    - Hook:     ~/.claude/scripts/burn-rate.sh  (copied, re-run to update)"
fi
echo "    - Command:  /save-context                   (save session state)"
echo "    - Command:  /burn-rate                      (check stats on demand)"
echo "    - Rules:    ~/.claude/CLAUDE.md              (global session rules)"
echo ""
echo "  Configuration (env vars in your shell profile):"
echo "    BURN_RATE_COMPACT=8         — compact nudge (prompt count)"
echo "    BURN_RATE_WARN=15           — wrap-up nudge (prompt count)"
echo "    BURN_RATE_STRONG=25         — strong warning (prompt count)"
echo "    BURN_RATE_URGENT=40         — urgent stop (prompt count)"
echo "    BURN_RATE_TOKEN_COMPACT=10000000  — compact nudge (token volume)"
echo "    BURN_RATE_TOKEN_WARN=30000000     — wrap-up nudge (token volume)"
echo "    BURN_RATE_TOKEN_STRONG=60000000   — strong warning (token volume)"
echo "    BURN_RATE_TOKEN_URGENT=100000000  — urgent stop (token volume)"
echo ""
echo "  Start a new Claude Code session to activate."
echo ""
