# Session Guard for Claude Code

Stop burning tokens on monster sessions. Session Guard monitors your Claude Code usage in real-time, warns before sessions get expensive, and preserves context so fresh sessions aren't cold starts.

## The Problem

Every message in a Claude Code session re-sends the **entire conversation history**. A 100-prompt session costs ~100x more per message than the first message. Real-world data from power users:

| Session Length | Estimated Cost | What Happens |
|---------------|---------------|--------------|
| 10 prompts | $1-5 | Normal |
| 25 prompts | $15-30 | Getting expensive |
| 50 prompts | $50-100 | Wasteful |
| 100+ prompts | $100-250+ | Burning money |

Most users don't realize this because there's no feedback loop. Session Guard fixes that.

## What It Does

**1. Real-time prompt counter with cost estimates**
A `UserPromptSubmit` hook fires on every message, showing your prompt count and estimated cost:
```
SESSION GUARD [25 prompts | ~$18.50 est.]: Session getting costly.
Run /save-context and start a fresh session to save money.
```

**2. Anti-pattern detection**
Warns about subagent storms (10+ subagents spawned from vague prompts).

**3. Cross-session context persistence**
The `/save-context` command saves your session state (decisions, files changed, next steps) to the project's `CLAUDE.md`. When you start a fresh session, Claude reads it and picks up where you left off.

**4. Global behavioral rules**
Injects rules into Claude's global instructions to:
- Push back on vague "build everything" prompts
- Suggest file references over pasting large specs
- Limit subagent spawning
- Proactively offer context saving

## Install

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/rajkaria/claude-session-guard/main/install.sh | bash
```

### Manual

```bash
git clone https://github.com/rajkaria/claude-session-guard.git
cd claude-session-guard
bash install.sh
```

## Configuration

Override thresholds with environment variables:

```bash
export SG_WARN_AT=15     # Gentle nudge (default: 15)
export SG_STRONG_AT=25   # Strong warning (default: 25)
export SG_URGENT_AT=40   # Urgent stop (default: 40)
```

## Usage

### During a session

Session Guard runs automatically. You'll see nudges at 15, 25, and 40 prompts.

### Saving context before ending

```
/save-context
```

This writes a structured summary to your project's `CLAUDE.md`:
- Current state (what works, what's broken)
- Files changed and why
- Next steps for the next session
- Key decisions made

### Starting a new session

Just start Claude Code in the same project. It reads the `CLAUDE.md` and has full context from the last session.

## The Five Anti-Patterns It Prevents

| Anti-Pattern | Impact | How Session Guard Helps |
|-------------|--------|----------------------|
| Monster sessions (50+ prompts) | $50-250+ per session | Warns at 15/25/40 prompts |
| Spec pasting (large docs in chat) | Stays in context forever | Rules tell Claude to suggest file references |
| Subagent storms (20+ agents) | Each loads full context | Warns at 8/15 subagents, rules limit spawning |
| File re-reads (same file 20+ times) | Wasted tokens | Short sessions prevent compaction-driven re-reads |
| Build output dumping | 5K-60K chars per paste | Rules tell Claude to ask for relevant lines only |

## What Gets Installed

| File | Purpose |
|------|---------|
| `~/.claude/scripts/session-guard.sh` | Hook script (prompt counter + cost estimator) |
| `~/.claude/commands/save-context.md` | `/save-context` slash command |
| `~/.claude/CLAUDE.md` | Global rules (appended if file exists) |
| `~/.claude/settings.json` | Hook registration (merged safely) |

## Compatibility

- Claude Code CLI, Desktop App, Web App
- All Claude models (Opus, Sonnet, Haiku)
- macOS and Linux
- Works alongside `everything-claude-code`, `superpowers`, and other plugins

## Uninstall

```bash
# Remove the hook script
rm ~/.claude/scripts/session-guard.sh

# Remove the command
rm ~/.claude/commands/save-context.md

# Remove the hook from settings.json (manual edit)
# Remove Session Guard rules from ~/.claude/CLAUDE.md (manual edit)
```

## License

MIT
