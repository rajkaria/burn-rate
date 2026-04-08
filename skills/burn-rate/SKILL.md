---
name: burn-rate
description: |
  Real-time session cost monitoring, anti-pattern detection, and cross-session context persistence for Claude Code.
  TRIGGER when: any session starts, user sends 10+ messages, user says "save context", "wrap up", "new session", or session approaches token limits.
origin: community
metadata:
  author: rajkaria
  version: "4.0.0"
  license: MIT
---

# Burn Rate

Watch your tokens burn in real-time. Warns before sessions get expensive, detects wasteful patterns, and preserves context across sessions so fresh starts aren't cold starts.

## When to Activate

- Every session (via UserPromptSubmit hook — always-on monitoring)
- When the user says "save context", "wrap up", or "new session"
- When session crosses prompt thresholds (15 / 25 / 40)
- When anti-patterns are detected (subagent storms, long sessions)

## Why This Matters

Claude Code sessions are **exponentially expensive** as they grow. Each message re-sends the entire conversation. Real-world data from power users:

| Session Length | Typical Cost (Opus 4.6) | Tokens |
|---------------|-------------------------|--------|
| 10 prompts | ~$0.50-2 | 1-5M |
| 25 prompts | ~$5-10 | 10-30M |
| 50 prompts | ~$15-40 | 30-100M |
| 100+ prompts | ~$40-100 | 100-300M |

## The Five Anti-Patterns

### 1. Monster Sessions
Sessions with 50+ prompts where each message pays for the full conversation history.

**Detection:** Prompt count thresholds (15 / 25 / 40).
**Fix:** Break work into focused 15-20 prompt sessions. Use `/save-context` before ending.

### 2. Spec Pasting
Pasting entire project specs or design docs directly into chat. These stay in context for every subsequent message.

**Detection:** User messages exceeding 3,000 characters.
**Fix:** Put specs in files (`docs/SPEC.md`, project CLAUDE.md) and reference them.

### 3. Subagent Storms
Vague prompts like "build everything from the spec" trigger 20-60 parallel subagent sessions, each loading full project context independently.

**Detection:** Sessions spawning 8+ subagents.
**Fix:** Give specific, scoped instructions instead of broad "build everything" prompts.

### 4. File Re-Read Waste
The same file read 10-40+ times in a single session because context compaction loses file contents.

**Fix:** Keep sessions short so compaction doesn't discard recently-read files.

### 5. Build Output Dumping
Pasting raw terminal output (npm errors, build logs, stack traces) of 5,000-60,000 characters.

**Fix:** Paste only the relevant error lines, not the full log.

## Session Rules (Global CLAUDE.md)

1. **Track conversation depth.** After ~15 user messages, remind to wrap up.
2. **After ~25 messages**, strongly recommend saving context and starting fresh.
3. **Push back on vague prompts.** Ask users to scope down "build everything" requests.
4. **Suggest file references over pasting.** When a user pastes >3,000 chars, suggest a file.
5. **Before session end**, offer to run `/save-context`.
6. **Minimize subagent spawning.** Prefer targeted Grep/Glob over broad Explore agents.

## Hook: burn-rate.sh

A `UserPromptSubmit` hook that fires on every prompt:

- Uses `CLAUDE_SESSION_ID` to find the exact current session (falls back to most-recent JSONL)
- Counts actual human prompts (excludes tool results which inflate counts 10x)
- Reads real token usage from session JSONL (input, cache write, cache read, output)
- Shows tokens by default; dollar estimates opt-in via `BURN_RATE_SHOW_COST=1`
- Returns warnings at configurable thresholds

### Thresholds (configurable via env vars)

| Env Var | Default | Description |
|---------|---------|-------------|
| `BURN_RATE_WARN` | 15 | Gentle nudge threshold |
| `BURN_RATE_STRONG` | 25 | Strong warning threshold |
| `BURN_RATE_URGENT` | 40 | Urgent "stop now" threshold |

## Command: /save-context

1. Summarizes the current session (decisions, files changed, state, next steps)
2. Writes/updates the project-root `CLAUDE.md` with a `## Session Context` section
3. Preserves previous session notes as history
4. Confirms the user can safely start a new session

## Installation

### Claude Code

```
/plugin marketplace add rajkaria/burn-rate
/plugin install burn-rate@burn-rate
```

### Script Install

```bash
curl -fsSL https://raw.githubusercontent.com/rajkaria/burn-rate/main/install.sh | bash
```

## Token Growth Reference

Typical token accumulation per session (varies by project size and tool usage):

| Prompts | Typical Tokens | Action |
|---------|---------------|--------|
| 1-10 | 0.5 - 5M | Normal |
| 10-15 | 5 - 10M | Plan to wrap up |
| 15-25 | 10 - 30M | Save context, start fresh |
| 25-40 | 30 - 80M | Urgently end session |
| 40+ | 80M+ | Burning tokens fast |

Dollar cost estimates available for API/pay-per-token users via `BURN_RATE_SHOW_COST=1`. Uses `pricing.json` for rates (user-updatable when Anthropic changes pricing).

## Compatibility

- Claude Code CLI, Desktop App, Web App
- All Claude models (Opus, Sonnet, Haiku)
- macOS and Linux
- Works alongside `everything-claude-code`, `superpowers`, and other plugins
- Complements `strategic-compact` (compaction within sessions) — Burn Rate manages across sessions
