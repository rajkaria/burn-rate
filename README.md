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

### `/burn-report` — see where your tokens actually went

The warnings tell you *when* you're burning. `/burn-report` shows *why*. It's a visual postmortem of your session — the file that got read 42 times, the paste bomb that keeps getting re-sent, the turn that cost 40% of the whole session.

```
You: /burn-report
```

```
┌──────────────────────────────── BURN REPORT ─────────────────────────────────┐
│ Window:  2026-04-07T09:12 → 2026-04-07T16:48                                │
│ Model:   opus                                                               │
│ 🔥 RUNAWAY — this session cost ~5x what it should have                      │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────── TOTALS ───────────────────────────────────┐
│ Human prompts:        62                                                    │
│ Total tokens:         187.4M                                                │
│ Tokens per prompt:    3.0M   ← burn velocity                                │
│ Tools invoked:        418                                                   │
│ Subagents spawned:    23                                                    │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────── WHERE YOUR TOKENS WENT ───────────────────────────┐
│ cache reads  (re-sent)   ██████████████████████░░ 170.1M 90.8%              │
│ cache writes (new)       █░░░░░░░░░░░░░░░░░░░░░░░  12.4M  6.6%              │
│ input        (uncached)  ░░░░░░░░░░░░░░░░░░░░░░░░   1.2M  0.6%              │
│ output       (reply)     ░░░░░░░░░░░░░░░░░░░░░░░░   3.7M  2.0%              │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────────── FILES RE-READ (the silent killer) ──────────────────────┐
│  42×  src/auth/middleware.ts                                        🚨      │
│  31×  src/db/schema.ts                                              🚨      │
│  18×  package.json                                                  🚨      │
│   9×  src/pages/login.tsx                                           🚨      │
│   4×  src/pages/signup.tsx                                          ⚠️      │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────── BIGGEST CONTEXT TURNS (largest single-message cost) ─────────────┐
│ turn #47     74.2M  ██████████████████████░░░░░░░░ 39.6% of session         │
│ turn #52     21.1M  ██████░░░░░░░░░░░░░░░░░░░░░░░░ 11.3% of session         │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────── PASTE BOMBS (user messages ≥ 2K chars — re-sent every turn) ─────┐
│  62.1K chars  "Here's the spec, implement all of it: ## Feature 1…"         │
│  14.8K chars  "Build failed, here's the full stack trace…"                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────── WHAT TO DO NEXT ───────────────────────────────┐
│ • middleware.ts read 42× — pin it or start fresh session                    │
│ • 23 subagents spawned — prefer Grep/Glob for narrow searches               │
│ • Pasted 62.1K chars — move large blobs to a file and reference it          │
│ • 3.0M/prompt is heavy — /save-context and start fresh                      │
│ • 91% is re-sent context — session length is the problem                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

Share the screenshot. That's usually all it takes.

**Report a specific past session:**

```
/burn-report 179f391c-4ae4-4127-8b7e-4c7b0aaaecc7
/burn-report ~/.claude/projects/my-project/abc123.jsonl
```

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
| `/burn-report` | Visual postmortem: top re-read files, paste bombs, context jumps |
| `/burn-lint` | Audits CLAUDE.md for bloat (every line re-sent each prompt) |
| Re-read warnings | Inline warning when one file is read 5+ times |
| Plan budget % | Optional "% of session budget" display for Max/Pro users |
| `/burn-trend` | Cross-session trends — week-over-week tokens, top projects |
| Subagent budget gate | Forces confirm after N subagents spawn (catches spec-paste disasters) |
| Paste saver | Large pastes auto-saved to a file — swap to `@file` on next turn |
| Session resume | New session? Burn Rate reads CLAUDE.md and primes Claude to continue |
| Model-switch tip | Suggests Haiku when you're on a trivial-edit streak (shown once) |
| `/save-context` | Save state to CLAUDE.md + post-session burn report |
| `/compact` suggestion | At 15-25 prompts, suggests compact as alternative to new session |
| Smart rules | Claude pushes back on vague prompts and spec pasting |
| Subagent alerts | Warns when too many agents are spawned |
| Optional cost display | Set `BURN_RATE_SHOW_COST=1` for API/pay-per-token users |

Zero config. Works immediately. Adds <50ms per prompt.

## Configuration

```bash
export BURN_RATE_WARN=15              # Gentle nudge threshold (default: 15)
export BURN_RATE_STRONG=25            # Strong warning threshold (default: 25)
export BURN_RATE_URGENT=40            # Urgent stop threshold (default: 40)
export BURN_RATE_REREAD_WARN=5        # Warn when one file is read N times (default: 5)
export BURN_RATE_SHOW_COST=1          # Show $ estimates (API/pay-per-token users only)
export BURN_RATE_PLAN=max             # pro | max | max20 → shows "% of session budget"
export BURN_RATE_SESSION_BUDGET=0     # Override budget in tokens (0 = use plan default)
export BURN_RATE_SUBAGENT_BUDGET=5    # Confirm before spawning >N subagents (0 = disable)
export BURN_RATE_PASTE_WARN=3000      # Chars threshold for paste saver (default: 3000)
export BURN_RATE_NO_DIET=1            # Disable paste saver entirely
export BURN_RATE_NO_RESUME=1          # Disable session auto-resume
export BURN_RATE_RESUME_MAX_AGE_DAYS=7 # Stale-after days for resume (default: 7)
export BURN_RATE_NO_MODEL_TIP=1       # Silence the Haiku suggestion
```

### Re-read warnings (feature)

When the same file gets read 5+ times in a session — the classic post-compaction waste — you'll see:

```
RE-READ WARNING: 'middleware.ts' read 6× — pin it or /save-context.
```

Pin frequently-used files with `@src/auth/middleware.ts` at the start of your message so Claude sees them without re-reading.

### Plan budget % (for Max/Pro users)

Flat-rate plans don't care about dollars — they care about rate-limit capacity. Set `BURN_RATE_PLAN` and tokens are shown as percent of a reasonable "heavy session" budget:

```
BURN RATE [22 prompts | 45.2M | 30% of max]: Heavy session. /save-context.
```

| Plan | Default session budget |
|------|------------------------|
| `pro` | 50M tokens |
| `max` | 150M tokens |
| `max20` | 500M tokens |

Override with `BURN_RATE_SESSION_BUDGET=<tokens>` for your own calibration.

### `/burn-trend` — week-over-week trends

The plugin logs every session (anonymously, locally) to `~/.claude/.burn-rate/history.jsonl` on SessionEnd. `/burn-trend` turns that into a report:

```
You: /burn-trend
```

```
┌──────────────────────────────── BURN-TREND ────────────────────────────────┐
│ History: ~/.claude/.burn-rate/history.jsonl                                │
│ Sessions logged: 47                                                        │
└────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────── LAST 7 DAYS ────────────────────────────────┐
│ Sessions:         12                                                       │
│ Total tokens:     94.3M                                                    │
│ Avg per session:  7.9M                                                     │
│ Tokens/prompt:    812K                                                     │
│ Subagents:        11                                                       │
└────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────── WEEK-OVER-WEEK ──────────────────────────────┐
│ Tokens:           218.4M → 94.3M   (-57%)                                  │
│ Avg per session:  15.6M → 7.9M     (-49%)                                  │
│ Tokens/prompt:    1.8M → 812K      (-55%)                                  │
│ 🎉 Trending leaner — keep going.                                           │
└────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────── TOP PROJECTS (last 7 days) ────────────────────────┐
│   52.1M   7 sessions  my-saas                                              │
│   31.4M   3 sessions  burn-rate                                            │
│   10.8M   2 sessions  blog                                                 │
└────────────────────────────────────────────────────────────────────────────┘
```

History is purely local — no uploads, ever. Capped at 500 rows (~6 months) to stay small.

### Paste saver (zero-friction paste mitigation)

Pasted a big log or spec? Burn Rate silently saves it to `./.burn-rate/pastes/paste-TIMESTAMP.txt` and tells Claude to reference it on the next turn. **Your current turn works as usual** — the paste still goes through. On the next turn, Claude suggests `@.burn-rate/pastes/paste-xxx.txt` instead, saving the re-send cost forever after.

```
You: [pastes a 15K-char build log]
      Please find the root cause of the failure.

Claude: [works on it normally this turn]
        💡 Burn Rate saved your paste to .burn-rate/pastes/paste-20260407-143022.txt
        — reference @that file next turn instead of re-pasting to save ~3.7K tokens/turn.
```

`.burn-rate/` is auto-added to `.gitignore`. Disable with `BURN_RATE_NO_DIET=1`, or raise the threshold with `BURN_RATE_PASTE_WARN=10000` if 3K is too tight for your workflow.

### Session auto-resume

Start a new session in a project that has a recent `## Session Context` block in `CLAUDE.md` — Burn Rate reads it and quietly primes Claude with the context:

```
[You open a fresh Claude Code session in ./my-saas]

Claude: I see we left off yesterday with the signup page form validation pending.
        Auth is done, login is working. Want to continue there, or something else?
```

- **Fresh (<7d):** primed silently, Claude acknowledges briefly and waits for your direction.
- **Stale (>7d):** Claude flags it and asks before using — old context shouldn't ambush you.
- **Git diverged:** Claude notes that HEAD moved since the block was written.

Never auto-executes anything. Disable with `BURN_RATE_NO_RESUME=1`.

### Model-switch tip (one-shot Haiku suggestion)

When your last 5 turns have been narrow edits (Bash/Read/Edit only, no Task/WebSearch), Burn Rate suggests switching to Haiku:

```
MODEL TIP: last 5 turns were narrow edits — switch to Haiku with /model haiku for
~5× cheaper. (shown once)
```

Shown **at most once per session** — never nags. Silence entirely with `BURN_RATE_NO_MODEL_TIP=1`.

### Subagent budget gate (catches the 60-agent disaster)

The #1 token-burn event: you paste a spec, Claude spawns 60 parallel agents, each loads the full project context. **50M+ tokens gone in one prompt.**

After `BURN_RATE_SUBAGENT_BUDGET` subagents (default 5) have already been spawned in the session, every further `Task` call pauses and asks you to confirm:

```
🛑 Confirm tool use: Task

   Burn Rate: 6 subagents already spawned (budget: 5).
   Each subagent loads full context independently.
   Confirm to continue, or use Grep/Glob for narrow searches.

   [Allow] [Deny]
```

Disable with `BURN_RATE_SUBAGENT_BUDGET=0`. Raise the budget if you routinely need more.

### `/burn-lint` — audit your CLAUDE.md

Every line in `CLAUDE.md` (project-root or `~/.claude/`) is re-sent with every prompt. A bloated CLAUDE.md silently taxes every session forever.

```
You: /burn-lint
```

```
┌────────────────────────────── BURN-RATE LINT ──────────────────────────────┐
│ File: ./CLAUDE.md                                                          │
│ 🔥 BLOATED — this file adds massive overhead to every session              │
└────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────── SIZE ───────────────────────────────────┐
│ Lines:            1,247                                                    │
│ Characters:       52.3K                                                    │
│ Estimated tokens: ~13.1K   (re-sent every prompt)                          │
└────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────── SECTIONS (## headings) ──────────────────────────┐
│  412 lines  Architecture Overview                                  🚨      │
│  287 lines  Coding Standards                                       🚨      │
│  156 lines  Past Session Notes                                     ⚠️      │
│   89 lines  API Conventions                                                │
└────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────── RECOMMENDATIONS ──────────────────────────────┐
│ • ~13.1K tokens × every prompt — prune aggressively                        │
│ • Biggest section 'Architecture Overview' is 412 lines — move details out  │
│ • Split by topic: CONTRIBUTING.md, ARCHITECTURE.md, etc.                   │
└────────────────────────────────────────────────────────────────────────────┘
```

Pass a path to lint a specific file:

```
/burn-lint path/to/OTHER.md
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
