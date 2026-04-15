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

# --- Install scripts ---
for s in burn-rate.sh burn-report.sh burn-rate-lint.sh burn-rate-log.sh \
         burn-trend.sh burn-rate-subagent-gate.sh burn-rate-paste-saver.sh \
         burn-rate-resume.sh; do
  fetch_file "scripts/$s" "$SCRIPTS_DIR/$s"
  chmod +x "$SCRIPTS_DIR/$s" 2>/dev/null || true
  info "Installed $s"
done

# --- Install slash commands ---
for c in save-context.md burn-rate.md burn-report.md burn-lint.md burn-trend.md; do
  fetch_file "commands/$c" "$COMMANDS_DIR/$c"
  info "Installed /${c%.md} command"
done

# --- Install pricing.json ---
fetch_file "pricing.json" "$SCRIPTS_DIR/pricing.json"
info "Installed pricing.json (edit to update when Anthropic changes rates)"

# --- Update settings.json with all hooks ---
python3 << 'PYEOF'
import json, os

settings_file = os.path.expanduser("~/.claude/settings.json")
scripts = "~/.claude/scripts"

try:
    with open(settings_file) as f:
        settings = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    settings = {}

settings.setdefault("hooks", {})

def cmd(script):
    return {"type": "command", "command": f"bash {scripts}/{script}"}

def has(event, matcher, script_substr):
    for h in settings["hooks"].get(event, []):
        if h.get("matcher", "") != matcher:
            continue
        for hk in h.get("hooks", []):
            if script_substr in hk.get("command", ""):
                return True
    return False

def ensure(event, matcher, script):
    settings["hooks"].setdefault(event, [])
    # purge legacy session-guard entries
    if event == "UserPromptSubmit":
        settings["hooks"][event] = [
            h for h in settings["hooks"][event]
            if not any("session-guard" in hk.get("command", "") for hk in h.get("hooks", []))
        ]
    if has(event, matcher, script):
        return
    # append to existing matcher group if one exists
    for h in settings["hooks"][event]:
        if h.get("matcher", "") == matcher:
            h.setdefault("hooks", []).append(cmd(script))
            return
    settings["hooks"][event].append({"matcher": matcher, "hooks": [cmd(script)]})

# SessionStart: resume prior context
ensure("SessionStart",     "",     "burn-rate-resume.sh")
# UserPromptSubmit: paste saver first, then main analyzer
ensure("UserPromptSubmit", "",     "burn-rate-paste-saver.sh")
ensure("UserPromptSubmit", "",     "burn-rate.sh")
# PreToolUse:Task: subagent budget gate
ensure("PreToolUse",       "Task", "burn-rate-subagent-gate.sh")
# SessionEnd: history logger
ensure("SessionEnd",       "",     "burn-rate-log.sh")

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
info "Wired all burn-rate hooks into settings.json (SessionStart, UserPromptSubmit, PreToolUse:Task, SessionEnd)"

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
echo "    - Command:  /burn-report                    (visual postmortem)"
echo "    - Command:  /burn-lint                      (CLAUDE.md bloat audit)"
echo "    - Command:  /burn-trend                     (week-over-week trends)"
echo "    - Hooks:    SessionStart resume, paste saver, subagent gate, history logger"
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
