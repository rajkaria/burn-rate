# Burn Rate

Watch your Claude Code tokens burn in real-time. Get warned before sessions get expensive, detect wasteful patterns, and preserve context so fresh sessions aren't cold starts.

## The Problem

Every message in a Claude Code session re-sends the **entire conversation history**. A 100-prompt session costs ~100x more per message than the first. But there's zero cost feedback during a session — you only find out after.

| Session Length | Estimated Cost | What Happens |
|---------------|---------------|--------------|
| 10 prompts | $1-5 | Normal |
| 25 prompts | $15-30 | Getting expensive |
| 50 prompts | $50-100 | Wasteful |
| 100+ prompts | $100-250+ | Burning money |

*Costs shown for Opus. Sonnet is ~5x cheaper, Haiku ~20x cheaper. Burn Rate auto-detects your model.*

## What It Does

### 1. Real-time burn rate monitor
A `UserPromptSubmit` hook fires on every message with your prompt count and estimated cost:
```
BURN RATE [25 prompts | ~$18.50]: Session getting costly.
Run /save-context and start fresh.
```

Uses `CLAUDE_SESSION_ID` to track the exact current session (v2) — no cross-session confusion.

### 2. On-demand stats
Type `/burn-rate` anytime to check your current session's prompt count, cost estimate, and subagent count.

### 3. Anti-pattern detection
Warns about subagent storms (8+ subagents spawned from vague prompts).

### 4. Cross-session context persistence
`/save-context` saves your session state (decisions, files changed, next steps) to the project's `CLAUDE.md`. Fresh sessions read it and pick up where you left off.

### 5. Global behavioral rules
Injects rules into Claude's global instructions to push back on wasteful patterns: vague "build everything" prompts, spec pasting, build output dumping.

## Install

### As a Claude Code Plugin (Recommended)

```bash
claude plugins add burn-rate --marketplace https://github.com/rajkaria/burn-rate
```

Or add it manually to your `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "burn-rate": {
      "source": {
        "source": "github",
        "repo": "rajkaria/burn-rate"
      }
    }
  }
}
```

Then enable it:

```bash
claude plugins enable burn-rate
```

### Quick Install (Script)

If you prefer a standalone install without the plugin system:

```bash
curl -fsSL https://raw.githubusercontent.com/rajkaria/burn-rate/main/install.sh | bash
```

### From Source

```bash
git clone https://github.com/rajkaria/burn-rate.git
cd burn-rate
bash install.sh
```

## Configuration

Override thresholds with environment variables:

```bash
export BURN_RATE_WARN=15     # Gentle nudge (default: 15)
export BURN_RATE_STRONG=25   # Strong warning (default: 25)
export BURN_RATE_URGENT=40   # Urgent stop (default: 40)
```

## Usage

### During a session
Burn Rate runs automatically. You'll see nudges at 15, 25, and 40 prompts with cost estimates.

### Saving context
```
/save-context
```
Writes a structured summary to your project's `CLAUDE.md` — current state, files changed, next steps, key decisions.

### Starting fresh
Start Claude Code in the same project. It reads the `CLAUDE.md` and has full context from the last session.

## The Five Anti-Patterns

| Anti-Pattern | Impact | How Burn Rate Helps |
|-------------|--------|-------------------|
| **Monster sessions** (50+ prompts) | $50-250+ per session | Warns at 15/25/40 prompts with cost estimate |
| **Spec pasting** (large docs in chat) | Stays in context forever | Rules tell Claude to suggest file references |
| **Subagent storms** (20+ agents) | Each loads full context | Warns at 8/15 subagents |
| **File re-reads** (same file 20+ times) | Wasted tokens | Short sessions prevent compaction-driven re-reads |
| **Build output dumping** | 5K-60K chars per paste | Rules tell Claude to ask for relevant lines only |

## What Gets Installed

**Plugin install** — everything is managed by Claude Code's plugin system:

| Component | What It Does |
|-----------|-------------|
| Hook (`UserPromptSubmit`) | Fires on every prompt — counts messages, estimates cost, detects subagent storms |
| `/save-context` command | Saves session state to project CLAUDE.md |
| `/burn-rate` command | Check stats on demand |
| Rules | Session management rules injected into Claude's behavior |
| Skill | Anti-pattern detection guidance |

**Script install** — files are copied directly:

| File | Purpose |
|------|---------|
| `~/.claude/scripts/burn-rate.sh` | Hook script |
| `~/.claude/commands/burn-rate.md` | `/burn-rate` command |
| `~/.claude/commands/save-context.md` | `/save-context` command |
| `~/.claude/CLAUDE.md` | Global rules (appended if file exists) |
| `~/.claude/settings.json` | Hook registration (merged safely) |

## How It Works

The hook script:
1. Uses `CLAUDE_SESSION_ID` env var to find the exact current session's JSONL file
2. Falls back to most-recently-modified JSONL for older Claude Code versions
3. Counts `"type":"user"` lines for prompt count
4. Counts subagent JSONL files in the session directory
5. Estimates cost using an empirical model based on real session data
6. Outputs warnings to stdout which Claude Code displays as hook feedback

## Compatibility

- Claude Code CLI, Desktop App, Web App
- All Claude models (Opus, Sonnet, Haiku)
- macOS and Linux
- Works alongside `everything-claude-code`, `superpowers`, and other plugins

## Uninstall

**Plugin install:**
```bash
claude plugins disable burn-rate
```

**Script install:**
```bash
curl -fsSL https://raw.githubusercontent.com/rajkaria/burn-rate/main/uninstall.sh | bash
```

## Contributing

PRs welcome. Areas that would help:

- **Better cost models** — if you have real token data from Sonnet/Haiku sessions, help calibrate the estimates
- **More anti-patterns** — what other wasteful patterns have you seen?
- **Platform testing** — test on Linux, different shell environments
- **IDE integration** — VS Code / JetBrains extension hook support

## License

MIT
