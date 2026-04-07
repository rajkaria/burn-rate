#!/usr/bin/env bash
# ============================================================================
# Session Guard Installer
# Installs the session-guard hook, save-context command, and global rules
# for Claude Code. Works on macOS and Linux.
# https://github.com/rajkaria/claude-session-guard
# ============================================================================

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; }

# --- Pre-checks ---
if [ ! -d "$CLAUDE_DIR" ]; then
  error "~/.claude directory not found. Is Claude Code installed?"
  exit 1
fi

echo ""
echo "  Session Guard Installer"
echo "  ======================="
echo ""

# --- Create directories ---
mkdir -p "$SCRIPTS_DIR" "$COMMANDS_DIR"

# --- Determine source (local repo or remote) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/scripts/session-guard.sh" ]; then
  # Installing from cloned repo
  SOURCE="local"
  info "Installing from local repository..."
else
  # Installing from curl pipe
  SOURCE="remote"
  REPO_URL="https://raw.githubusercontent.com/rajkaria/claude-session-guard/main"
  info "Downloading from GitHub..."
fi

# --- Install session-guard.sh ---
if [ "$SOURCE" = "local" ]; then
  cp "$SCRIPT_DIR/scripts/session-guard.sh" "$SCRIPTS_DIR/session-guard.sh"
else
  curl -fsSL "$REPO_URL/scripts/session-guard.sh" -o "$SCRIPTS_DIR/session-guard.sh"
fi
chmod +x "$SCRIPTS_DIR/session-guard.sh"
info "Installed session-guard.sh"

# --- Install save-context command ---
if [ "$SOURCE" = "local" ]; then
  cp "$SCRIPT_DIR/commands/save-context.md" "$COMMANDS_DIR/save-context.md"
else
  curl -fsSL "$REPO_URL/commands/save-context.md" -o "$COMMANDS_DIR/save-context.md"
fi
info "Installed /save-context command"

# --- Update settings.json with hook ---
if [ -f "$SETTINGS_FILE" ]; then
  # Check if hook already exists
  if grep -q "session-guard" "$SETTINGS_FILE" 2>/dev/null; then
    info "Hook already configured in settings.json (skipping)"
  else
    # Use python to safely merge the hook into existing settings
    python3 -c "
import json, sys

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

hook_entry = {
    'matcher': '',
    'hooks': [{'type': 'command', 'command': 'bash ~/.claude/scripts/session-guard.sh'}]
}

if 'hooks' not in settings:
    settings['hooks'] = {}

if 'UserPromptSubmit' not in settings['hooks']:
    settings['hooks']['UserPromptSubmit'] = []

# Check if already present
existing = [h for h in settings['hooks']['UserPromptSubmit']
            if any('session-guard' in hook.get('command', '') for hook in h.get('hooks', []))]

if not existing:
    settings['hooks']['UserPromptSubmit'].append(hook_entry)

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" 2>/dev/null
    info "Added UserPromptSubmit hook to settings.json"
  fi
else
  # Create minimal settings.json
  cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/session-guard.sh"
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
  if grep -q "Session Guard" "$CLAUDE_MD" 2>/dev/null; then
    info "Global CLAUDE.md already has Session Guard rules (skipping)"
  else
    warn "Existing CLAUDE.md found. Appending Session Guard rules..."
    echo "" >> "$CLAUDE_MD"
    if [ "$SOURCE" = "local" ]; then
      cat "$SCRIPT_DIR/claude-md-template.md" >> "$CLAUDE_MD"
    else
      curl -fsSL "$REPO_URL/claude-md-template.md" >> "$CLAUDE_MD"
    fi
    info "Appended Session Guard rules to CLAUDE.md"
  fi
else
  if [ "$SOURCE" = "local" ]; then
    cp "$SCRIPT_DIR/claude-md-template.md" "$CLAUDE_MD"
  else
    curl -fsSL "$REPO_URL/claude-md-template.md" -o "$CLAUDE_MD"
  fi
  info "Created global CLAUDE.md with Session Guard rules"
fi

# --- Done ---
echo ""
info "Installation complete!"
echo ""
echo "  What's installed:"
echo "    - Hook:    ~/.claude/scripts/session-guard.sh (fires on every prompt)"
echo "    - Command: /save-context (saves session state to project CLAUDE.md)"
echo "    - Rules:   ~/.claude/CLAUDE.md (global session management rules)"
echo ""
echo "  Configuration (env vars):"
echo "    SG_WARN_AT=15    — gentle nudge threshold"
echo "    SG_STRONG_AT=25  — strong warning threshold"
echo "    SG_URGENT_AT=40  — urgent stop threshold"
echo ""
echo "  Start a new Claude Code session to activate."
echo ""
