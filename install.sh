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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
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
echo -e "  ${BOLD}Burn Rate Installer${NC}"
echo "  ==================="
echo ""

# --- Create directories ---
mkdir -p "$SCRIPTS_DIR" "$COMMANDS_DIR"

# --- Determine source (local repo or remote) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/scripts/burn-rate.sh" ]; then
  SOURCE="local"
  info "Installing from local repository..."
else
  SOURCE="remote"
  REPO_URL="https://raw.githubusercontent.com/rajkaria/burn-rate/main"
  info "Downloading from GitHub..."
fi

# --- Clean up old session-guard installation if present ---
if [ -f "$SCRIPTS_DIR/session-guard.sh" ]; then
  rm "$SCRIPTS_DIR/session-guard.sh"
  warn "Removed old session-guard.sh (replaced by burn-rate.sh)"
fi

# --- Install burn-rate.sh ---
if [ "$SOURCE" = "local" ]; then
  cp "$SCRIPT_DIR/scripts/burn-rate.sh" "$SCRIPTS_DIR/burn-rate.sh"
else
  curl -fsSL "$REPO_URL/scripts/burn-rate.sh" -o "$SCRIPTS_DIR/burn-rate.sh"
fi
chmod +x "$SCRIPTS_DIR/burn-rate.sh"
info "Installed burn-rate.sh"

# --- Install save-context command ---
if [ "$SOURCE" = "local" ]; then
  cp "$SCRIPT_DIR/commands/save-context.md" "$COMMANDS_DIR/save-context.md"
else
  curl -fsSL "$REPO_URL/commands/save-context.md" -o "$COMMANDS_DIR/save-context.md"
fi
info "Installed /save-context command"

# --- Update settings.json with hook ---
if [ -f "$SETTINGS_FILE" ]; then
  if grep -q "burn-rate" "$SETTINGS_FILE" 2>/dev/null; then
    info "Hook already configured in settings.json (skipping)"
  else
    python3 -c "
import json

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

hook_entry = {
    'matcher': '',
    'hooks': [{'type': 'command', 'command': 'bash ~/.claude/scripts/burn-rate.sh'}]
}

if 'hooks' not in settings:
    settings['hooks'] = {}

if 'UserPromptSubmit' not in settings['hooks']:
    settings['hooks']['UserPromptSubmit'] = []

# Remove old session-guard hooks if present
settings['hooks']['UserPromptSubmit'] = [
    h for h in settings['hooks']['UserPromptSubmit']
    if not any('session-guard' in hook.get('command', '') for hook in h.get('hooks', []))
]

# Check if burn-rate already present
existing = [h for h in settings['hooks']['UserPromptSubmit']
            if any('burn-rate' in hook.get('command', '') for hook in h.get('hooks', []))]

if not existing:
    settings['hooks']['UserPromptSubmit'].append(hook_entry)

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" 2>/dev/null
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
    # Remove old Session Guard rules if present
    if grep -q "Session Guard" "$CLAUDE_MD" 2>/dev/null; then
      warn "Replacing old Session Guard rules with Burn Rate rules..."
      python3 -c "
with open('$CLAUDE_MD') as f:
    content = f.read()
content = content.replace('Session Guard', 'Burn Rate')
with open('$CLAUDE_MD', 'w') as f:
    f.write(content)
" 2>/dev/null
      info "Updated CLAUDE.md (Session Guard -> Burn Rate)"
    else
      warn "Existing CLAUDE.md found. Appending Burn Rate rules..."
      echo "" >> "$CLAUDE_MD"
      if [ "$SOURCE" = "local" ]; then
        cat "$SCRIPT_DIR/claude-md-template.md" >> "$CLAUDE_MD"
      else
        curl -fsSL "$REPO_URL/claude-md-template.md" >> "$CLAUDE_MD"
      fi
      info "Appended Burn Rate rules to CLAUDE.md"
    fi
  fi
else
  if [ "$SOURCE" = "local" ]; then
    cp "$SCRIPT_DIR/claude-md-template.md" "$CLAUDE_MD"
  else
    curl -fsSL "$REPO_URL/claude-md-template.md" -o "$CLAUDE_MD"
  fi
  info "Created global CLAUDE.md with Burn Rate rules"
fi

# --- Done ---
echo ""
info "Installation complete!"
echo ""
echo "  What's installed:"
echo "    - Hook:    ~/.claude/scripts/burn-rate.sh (fires on every prompt)"
echo "    - Command: /save-context (saves session state to project CLAUDE.md)"
echo "    - Rules:   ~/.claude/CLAUDE.md (global session management rules)"
echo ""
echo "  Configuration (env vars):"
echo "    BURN_RATE_WARN=15    — gentle nudge threshold"
echo "    BURN_RATE_STRONG=25  — strong warning threshold"
echo "    BURN_RATE_URGENT=40  — urgent stop threshold"
echo ""
echo "  Start a new Claude Code session to activate."
echo ""
