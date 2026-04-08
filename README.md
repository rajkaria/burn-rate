# Your Claude Code sessions burn 5x more tokens than they should.

You just don't know it yet.

I analyzed my usage and found this:

```
Session 1:  "build everything from the spec"      →  567M tokens
Session 2:   all-day session, no breaks               →  294M tokens
Session 3:  "strategize and start the build"       →  297M tokens
──────────────────────────────────────────────────────────────────
Top 5 sessions                                      →  1.3 BILLION tokens
```

The same work, split into short focused sessions: **~200M tokens.**

That's **1.1 billion tokens wasted** because nobody told me to stop.

## The thing Anthropic doesn't show you

Every message re-sends your **entire conversation**. The context size grows with every turn:

```
Message 1  ░                          ~50K tokens
Message 10 ░░░░                       ~2M tokens
Message 25 ░░░░░░░░░░                 ~10M tokens
Message 50 ░░░░░░░░░░░░░░░░░         ~40M tokens
Message 100░░░░░░░░░░░░░░░░░░░░░░░░  ~100M+ tokens
```

By message 50, you've spent more on re-reading old context than on actual work.

There's no token counter. No warning. Nothing. You're flying blind.

**Burn Rate is the missing fuel gauge.**

```
BURN RATE [15 prompts | 8.2M tokens]: Consider wrapping up soon.
Run /compact to continue, or /save-context to start fresh.
```

```
BURN RATE [25 prompts | 22.5M tokens]: Session getting heavy.
Run /save-context and start fresh.
  [1.1M/prompt | context: 20.8M reads, 1.2M writes | output: 48.2K]
```

```
BURN RATE [40 prompts | 58.3M tokens]: Session is VERY large.
Each message re-sends the full 58.3M context. Run /save-context and start a new session NOW.
  [1.4M/prompt | context: 55.1M reads, 2.8M writes | output: 112.0K]
```

> **Note on pricing:** Burn Rate focuses on tokens because that's the universal metric — whether you're on Max ($100/mo), Pro ($20/mo), or pay-per-token API. On flat-rate plans, long sessions eat your rate limit quota faster. On API plans, you can optionally show dollar estimates with `BURN_RATE_SHOW_COST=1`.

## Install (30 seconds)

### Claude Code

```
/plugin marketplace add rajkaria/burn-rate
/plugin install burn-rate@burn-rate
```

### Cursor

```
/add-plugin burn-rate
```

Or search for "burn-rate" in the plugin marketplace.

### Script Install (works everywhere)

```bash
curl -fsSL https://raw.githubusercontent.com/rajkaria/burn-rate/main/install.sh | bash
```

That's it. Start a new session and you'll see your burn rate.

## How to use it

### It warns you automatically — you don't do anything

Just code like normal. Burn Rate watches in the background and speaks up when it matters:

```
You: "Add user authentication to the app"
You: "Use JWT, add refresh tokens"
You: "Add the login page"
  ... working away ...

┌──────────────────────────────────────────────────────────────────────────────┐
│ BURN RATE [15 prompts | 8.2M tokens]: Consider wrapping up soon.            │
│ Run /compact to continue, or /save-context to start fresh.                  │
└──────────────────────────────────────────────────────────────────────────────┘

You: (keeps going anyway)
You: "Add the signup page too"
  ... 10 more messages ...

┌──────────────────────────────────────────────────────────────────────────────┐
│ BURN RATE [25 prompts | 22.5M tokens]: Session getting heavy.               │
│ Run /save-context and start fresh.                                          │
│   [1.1M/prompt | context: 20.8M reads, 1.2M writes | output: 48.2K]        │
└──────────────────────────────────────────────────────────────────────────────┘
```

That's your cue.

### `/save-context` — save your progress in 5 seconds

When you see the warning (or when you're done with a task), type:

```
You: /save-context
```

Claude writes a structured summary to your project's `CLAUDE.md`:

```markdown
## Session Context (Last updated: 2026-04-07 14:30)

### Current State
- Auth system working: JWT + refresh tokens implemented
- Login page done, signup page in progress
- Database: users table with email/password/refresh_token columns

### Recent Changes
- Created src/auth/jwt.ts — token generation and validation
- Created src/pages/login.tsx — login form with error handling
- Modified src/db/schema.ts — added users table

### Next Steps
- Finish signup page (form validation pending)
- Add password reset flow
- Write auth middleware for protected routes

### Key Decisions
- JWT over sessions: stateless, works with mobile app later
- Refresh tokens stored in DB, not cookies
```

### Start a fresh session — zero context loss

```
You: [start new Claude Code session in the same project]
You: "Continue where I left off. Check CLAUDE.md for context."

Claude: [reads CLAUDE.md]
"I see auth is done and you need to finish the signup page.
 Let me pick up from the form validation..."
```

**Two sessions. ~2M tokens total. Instead of one monster session burning 40M+.**

### `/burn-rate` — check your stats anytime

Don't want to wait for a warning? Just ask:

```
You: /burn-rate
Claude: "Current session: 8 prompts, 3.1M tokens (390K/prompt)
         Breakdown: 2.8M cache reads, 210K cache writes, 42K output
         2 subagents spawned. You're in the safe zone."
```

## The habits that are burning your tokens

### "Build everything from the spec"

You paste a 20K character spec and say "implement this."

Claude spawns 60 parallel agents. Each one loads your entire project context. Your one prompt just burned 50M+ tokens in subagent overhead alone.

**Instead:** "Implement the auth module from section 3 of `docs/SPEC.md`"

### Pasting walls of text

That error log you just pasted? 60,000 characters. It's now part of every message for the rest of this session — re-sent with every turn.

**Instead:** "Build failed with `TypeError: Cannot read 'map' of undefined at UserList.tsx:42`"

### The all-day session

An all-day session without breaks. You and Claude going back and forth for hours. The context window fills up, compaction kicks in, and Claude re-reads 200M+ tokens of context every time you say "ok" or "yes do that."

**Instead:** `/save-context` every 15-20 messages. Start fresh. It's free and takes 5 seconds.

### The file that got read 42 times

Real stat: one file was read 42 times in a single session. Why? Because after context compaction, Claude forgets what it already read and reads it again. And again. And again.

**Instead:** Short sessions mean less compaction. Less compaction means fewer re-reads.

## What's in the box

| You get | What it does |
|---------|-------------|
| Automatic warnings | Shows prompts + tokens + breakdown at 15 / 25 / 40 messages |
| Token breakdown | See exactly what's eating tokens: cache reads vs writes vs output |
| Tokens per prompt | Know your burn velocity — is context growing fast or slow? |
| `/burn-rate` | Check your full session stats anytime |
| `/save-context` | Save state to CLAUDE.md + post-session burn report |
| `/compact` suggestion | At 15-25 prompts, suggests compact as alternative to new session |
| Smart rules | Claude pushes back on vague prompts and spec pasting |
| Subagent alerts | Warns when too many agents are spawned |
| Optional cost display | Set `BURN_RATE_SHOW_COST=1` for API/pay-per-token users |

Zero config. Works immediately. Adds <50ms per prompt.

## Configuration

```bash
export BURN_RATE_WARN=15       # Gentle nudge threshold (default: 15)
export BURN_RATE_STRONG=25     # Strong warning threshold (default: 25)
export BURN_RATE_URGENT=40     # Urgent stop threshold (default: 40)
export BURN_RATE_SHOW_COST=1   # Show $ estimates (for API/pay-per-token users only)
```

### Who should enable cost display?

| Plan | Show cost? | Why |
|------|-----------|-----|
| **Claude Max** ($100/mo) | No (default) | You pay flat rate. Tokens = rate limit capacity. |
| **Claude Pro** ($20/mo) | No (default) | Same — focus on tokens as your capacity signal. |
| **API / pay-per-token** | Yes (`BURN_RATE_SHOW_COST=1`) | You pay per token. $ matters directly. |

## Works everywhere

Claude Code CLI, Desktop, Web, VS Code, JetBrains. All models. macOS and Linux. Plays nice with `everything-claude-code`, `superpowers`, and other plugins.

## Uninstall

Plugin: `/plugin uninstall burn-rate@burn-rate`

Script: `curl -fsSL https://raw.githubusercontent.com/rajkaria/burn-rate/main/uninstall.sh | bash`

## Contributing

The token analysis is based on real session data. PRs welcome for:
- More anti-patterns you've observed
- Platform testing (Linux, different shells)
- Better context persistence strategies

## License

MIT
