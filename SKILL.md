---
name: session-guard
description: |
  Real-time session cost monitoring, anti-pattern detection, and cross-session context persistence for Claude Code.
  TRIGGER when: any session starts, user sends 10+ messages, user says "save context", "wrap up", "new session", or session approaches token limits.
origin: community
metadata:
  author: rajkaria
  version: "1.0.0"
  license: MIT
---

# Session Guard

Monitors your Claude Code sessions in real-time, warns before they get expensive, detects wasteful patterns, and preserves context across sessions so fresh starts aren't cold starts.

## When to Activate

- Every session (via UserPromptSubmit hook — always-on monitoring)
- When the user says "save context", "wrap up", or "new session"
- When session crosses prompt thresholds (15 / 25 / 40)
- When anti-patterns are detected (spec pasting, subagent storms, file re-reads)

## Why This Matters

Claude Code sessions are **exponentially expensive** as they grow. Each message re-sends the entire conversation. Real-world data from power users shows:

| Session Length | Typical Cost | Tokens |
|---------------|-------------|--------|
| 10 prompts | ~$2-5 | 1-5M |
| 25 prompts | ~$15-30 | 30-80M |
| 50 prompts | ~$50-100 | 100-300M |
| 100+ prompts | ~$100-250 | 300M-550M |

The top 5 costliest sessions in one user's history consumed **~$621** — mostly from sessions that should have been split into 3-4 focused sessions.

## The Five Anti-Patterns

### 1. Monster Sessions (The #1 Problem)
Sessions with 50+ prompts where each message pays for the full conversation history.

**Detection:** Prompt count thresholds (15 / 25 / 40).
**Fix:** Break work into focused 15-20 prompt sessions. Use `/save-context` before ending.

### 2. Spec Pasting
Pasting entire project specs, READMEs, or design docs directly into chat. These stay in context for every subsequent message.

**Detection:** User messages exceeding 3,000 characters.
**Fix:** Put specs in files (`docs/SPEC.md`, project CLAUDE.md) and reference them: "Follow the spec in docs/SPEC.md for the auth module."

### 3. Subagent Storms
Vague prompts like "build everything from the spec" trigger 20-60 parallel subagent sessions, each loading full project context independently.

**Detection:** Sessions spawning 10+ subagents.
**Fix:** Give specific, scoped instructions. Instead of "implement the whole app," say "Create the database schema for users and sessions."

### 4. File Re-Read Waste
The same file read 10-40+ times in a single session because context compaction loses file contents.

**Detection:** Identical Read tool calls with the same file_path.
**Fix:** Keep sessions short so compaction doesn't discard recently-read files. For critical files, mention them in CLAUDE.md so they're always loaded.

### 5. Build Output Dumping
Pasting raw terminal output (npm errors, build logs, stack traces) of 5,000-60,000 characters into chat.

**Detection:** User messages with terminal output patterns.
**Fix:** Paste only the relevant error lines. Use "The build failed with: [specific error message]" instead of the full log.

## Session Rules (Injected via Global CLAUDE.md)

When this skill is active, Claude follows these rules in every session:

1. **Track conversation depth.** After ~15 user messages, remind the user to consider wrapping up.
2. **After ~25 messages**, strongly recommend saving context and starting a new session.
3. **Push back on vague prompts.** When receiving "build everything" or "go through the spec and implement," ask the user to scope it down.
4. **Suggest file references over pasting.** When a user pastes >3,000 chars, suggest putting it in a file.
5. **Before session end**, proactively offer to run `/save-context`.
6. **Minimize subagent spawning.** Prefer targeted Grep/Glob over broad Explore agents. Never spawn 5+ agents for a single task.

## Hook: session-guard.sh

A `UserPromptSubmit` hook that fires on every prompt:

- Finds the current session's JSONL file
- Counts user messages
- Estimates cost based on token accumulation
- Returns warnings at configurable thresholds

### Thresholds (configurable via env vars)

| Env Var | Default | Description |
|---------|---------|-------------|
| `SG_WARN_AT` | 15 | Gentle nudge threshold |
| `SG_STRONG_AT` | 25 | Strong warning threshold |
| `SG_URGENT_AT` | 40 | Urgent "stop now" threshold |

## Command: /save-context

A slash command that:

1. Summarizes the current session (decisions, files changed, state, next steps)
2. Writes/updates the project-root `CLAUDE.md` with a `## Session Context` section
3. Preserves previous session notes as history
4. Confirms the user can safely start a new session

### Context Format

```markdown
## Session Context (Last updated: YYYY-MM-DD HH:MM)

### Current State
- What's working, deployed, broken

### Recent Changes
- Files modified and why

### Next Steps
- What to pick up in the next session

### Key Decisions
- Architecture choices, trade-offs made

### Previous Session Notes
- (rotated history from prior sessions)
```

## Installation

### Quick Install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/rajkaria/claude-session-guard/main/install.sh | bash
```

### Manual Install

1. Copy `scripts/session-guard.sh` to `~/.claude/scripts/`
2. Copy `commands/save-context.md` to `~/.claude/commands/`
3. Copy `claude-md-template.md` content to `~/.claude/CLAUDE.md`
4. Add the hook to `~/.claude/settings.json`:

```json
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
```

## Cost Estimation Reference

Based on Opus 4.6 pricing ($15/1M input, $75/1M output, cache reads at $1.88/1M):

| Prompts | Estimated Session Cost | What You Should Do |
|---------|----------------------|-------------------|
| 1-10 | $0.50 - $3 | Normal usage |
| 10-15 | $3 - $10 | Start planning to wrap up |
| 15-25 | $10 - $30 | Save context, start new session |
| 25-40 | $30 - $80 | Urgently end this session |
| 40-100 | $80 - $250+ | You're burning money |

## Compatibility

- Claude Code CLI, Desktop App, Web App
- Works with all Claude models (Opus, Sonnet, Haiku)
- Compatible with `everything-claude-code` and `superpowers` plugins
- Complements `strategic-compact` skill (compaction within sessions) — this skill manages across sessions

## Related Skills

- **strategic-compact** — When to `/compact` within a session
- **cost-aware-llm-pipeline** — Cost patterns for apps you build with Claude API
- **prompt-optimizer** — Optimize individual prompt structure
