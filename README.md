# Your Claude Code sessions cost 5x more than they should.

You just don't know it yet.

I analyzed my usage and found this:

```
Session 1:  "build everything from the spec"      →  $221
Session 2:  "strategize and start the build"       →  $111
Session 3:   184 messages in one sitting            →  $133
─────────────────────────────────────────────────────────────
Top 5 sessions                                      →  $621
```

The same work, split into short focused sessions: **~$120.**

That's **$500 wasted** because nobody told me to stop.

## The thing Anthropic doesn't show you

Every message re-sends your **entire conversation**. The cost per message grows with every turn:

```
Message 1  ░                          $0.30
Message 10 ░░░░                       $0.80
Message 25 ░░░░░░░░░░                 $1.50
Message 50 ░░░░░░░░░░░░░░░░░         $2.50
Message 100░░░░░░░░░░░░░░░░░░░░░░░░  $2.50+
```

By message 50, you've spent more on re-reading old context than on actual work.

There's no cost counter. No warning. Nothing. You're flying blind.

**Burn Rate is the missing fuel gauge.**

```
BURN RATE [15 prompts | 8.2M tokens | ~$7.50]: Consider wrapping up soon.
Run /save-context before starting a new session.
```

```
BURN RATE [25 prompts | 42.1M tokens | ~$18.50]: Session getting costly.
Run /save-context and start fresh.
```

```
BURN RATE [40 prompts | 127.5M tokens | ~$53.50]: Session is VERY expensive.
Each message re-sends the full 127.5M context. Run /save-context and start a new session NOW.
```

## Install (30 seconds)

Pick one:

### Option A: Script Install (fastest)

```bash
curl -fsSL https://raw.githubusercontent.com/rajkaria/burn-rate/main/install.sh | bash
```

### Option B: Claude Code Plugin

Add to your `~/.claude/settings.json`:

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

Then: `claude plugins enable burn-rate`

### Option C: From Source

```bash
git clone https://github.com/rajkaria/burn-rate.git && cd burn-rate && bash install.sh
```

That's it. Start a new Claude Code session and you'll see your burn rate.

## How to use it

### It warns you automatically — you don't do anything

Just code like normal. Burn Rate watches in the background and speaks up when it matters:

```
You: "Add user authentication to the app"
You: "Use JWT, add refresh tokens"
You: "Add the login page"
  ... working away ...

┌─────────────────────────────────────────────────────────────────────┐
│ BURN RATE [15 prompts | ~$7.50]: Consider wrapping up soon.        │
│ Run /save-context before starting a new session.                   │
└─────────────────────────────────────────────────────────────────────┘

You: (keeps going anyway)
You: "Add the signup page too"
  ... 10 more messages ...

┌─────────────────────────────────────────────────────────────────────┐
│ BURN RATE [25 prompts | ~$18.50]: Session getting costly.          │
│ Run /save-context and start fresh.                                 │
└─────────────────────────────────────────────────────────────────────┘
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

**Two sessions. $15 total. Instead of one monster session for $80.**

### `/burn-rate` — check your stats anytime

Don't want to wait for a warning? Just ask:

```
You: /burn-rate
Claude: "Current session: 8 prompts, ~$3.20 estimated cost,
         2 subagents spawned. You're in the safe zone."
```

## The habits that are costing you money

### "Build everything from the spec"

You paste a 20K character spec and say "implement this."

Claude spawns 60 parallel agents. Each one loads your entire project context. Your one message just cost $50 in subagent overhead alone.

**Instead:** "Implement the auth module from section 3 of `docs/SPEC.md`"

### Pasting walls of text

That error log you just pasted? 60,000 characters. It's now part of every message for the rest of this session.

**Instead:** "Build failed with `TypeError: Cannot read 'map' of undefined at UserList.tsx:42`"

### The all-day session

184 messages. You and Claude going back and forth for 8 hours. By message 100, Claude is re-reading 300MB of context every time you say "ok" or "yes do that."

**Instead:** `/save-context` every 15-20 messages. Start fresh. It's free and takes 5 seconds.

### The file that got read 42 times

Real stat: `roundEngine.ts` was read 42 times in one session. Why? Because after context compaction, Claude forgets what it already read and reads it again. And again. And again.

**Instead:** Short sessions mean less compaction. Less compaction means fewer re-reads.

## What's in the box

| You get | What it does |
|---------|-------------|
| Automatic warnings | Shows prompt count + estimated cost at 15 / 25 / 40 messages |
| `/burn-rate` | Check your current burn rate anytime |
| `/save-context` | Save decisions + state + next steps to CLAUDE.md |
| Smart rules | Claude automatically pushes back on vague prompts and spec pasting |
| Model detection | Auto-adjusts estimates for Opus / Sonnet / Haiku |
| Subagent alerts | Warns when too many agents are spawned |

Zero config. Works immediately. Adds <50ms per prompt.

## Configuration

Want different thresholds? Set env vars:

```bash
export BURN_RATE_WARN=15     # default: 15
export BURN_RATE_STRONG=25   # default: 25
export BURN_RATE_URGENT=40   # default: 40
```

## Works everywhere

Claude Code CLI, Desktop, Web, VS Code, JetBrains. All models. macOS and Linux. Plays nice with `everything-claude-code`, `superpowers`, and other plugins.

## Uninstall

Plugin: `claude plugins disable burn-rate`

Script: `curl -fsSL https://raw.githubusercontent.com/rajkaria/burn-rate/main/uninstall.sh | bash`

## Contributing

The cost model is calibrated from real Opus session data. If you have Sonnet or Haiku usage data, PRs to improve the estimates are very welcome.

## License

MIT
