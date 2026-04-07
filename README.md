# Burn Rate

Watch your Claude Code tokens burn in real-time.

Every message you send re-sends the **entire conversation**. Message 50 costs 50x more than message 1. But Claude Code gives you zero cost feedback — you find out after.

Burn Rate fixes that: real-time warnings, cost estimates, anti-pattern detection, and context saving so you can split sessions without losing state.

```
BURN RATE [25 prompts | ~$18.50]: Session getting costly.
Run /save-context and start fresh.
```

## Why You Need This

A real user's data before installing Burn Rate:

| What happened | Cost |
|--------------|------|
| 1 session: "go through the spec, build everything" | **$221** |
| 1 session: "strategize, find optimum solution, start entire build" | **$111** |
| 1 session: 184 prompts chatting with Claude all day | **$133** |
| **Top 5 sessions total** | **$621** |

The same work split into focused 15-prompt sessions would have cost ~$120. That's **5x savings** just by knowing when to stop.

### The cost curve is exponential

```
Prompt 1:   $0.30  (small context)
Prompt 10:  $0.80  (growing)
Prompt 25:  $1.50  (large — you're here when warned)
Prompt 50:  $2.50  (massive — compaction kicking in)
Prompt 100: $2.50+ (re-reading everything every turn)
```

*Costs for Opus. Sonnet is ~5x cheaper, Haiku ~20x cheaper. Burn Rate auto-detects your model.*

## Install

### As a Claude Code Plugin (Recommended)

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

Then enable: `claude plugins enable burn-rate`

### One-Line Script Install

```bash
curl -fsSL https://raw.githubusercontent.com/rajkaria/burn-rate/main/install.sh | bash
```

### From Source

```bash
git clone https://github.com/rajkaria/burn-rate.git
cd burn-rate
bash install.sh
```

## What You Get

| Feature | How It Helps |
|---------|-------------|
| **Real-time warnings** at 15 / 25 / 40 prompts | You know when to stop before it gets expensive |
| **Cost estimate** on every warning | See dollars, not abstract token counts |
| **`/burn-rate`** command | Check stats on demand, anytime |
| **`/save-context`** command | Save session state so new sessions aren't cold starts |
| **Subagent storm detection** | Warns when 8+ agents are spawned (each loads full context) |
| **Behavioral rules** | Claude pushes back on wasteful patterns automatically |
| **Model-aware pricing** | Auto-detects Opus / Sonnet / Haiku for accurate estimates |

## How to Reduce Your Burn Rate

### 1. Split sessions at 15-20 prompts

**Expensive way:**
```
You: "Build the entire app from this spec"
... 80 prompts later ...
Cost: ~$150
```

**Cheap way:**
```
Session 1 (12 prompts): "Set up the database schema for users and sessions"
  → /save-context

Session 2 (15 prompts): "Build the auth API routes. Context is in CLAUDE.md"
  → /save-context

Session 3 (10 prompts): "Build the frontend login page"
  → /save-context

Total cost: ~$30 (5x cheaper, same result)
```

### 2. Reference files instead of pasting specs

**Expensive way:**
```
You: [pastes 20,000 character spec into chat]
You: "Now implement the auth module"
You: "Now add the API routes"
You: "Now write tests"
→ That 20K spec is re-sent with EVERY message for the rest of the session
```

**Cheap way:**
```
You: "Read docs/SPEC.md and implement the auth module from section 3"
→ Claude reads it once, doesn't carry it in every message
```

### 3. Give specific prompts, not sweeping ones

**Triggers subagent storm (~$50+ in agents alone):**
```
You: "Go through the entire codebase, understand everything, optimize it,
      improve it, and then create a full plan"
→ Claude spawns 20-60 parallel agents, each loading full project context
```

**Targeted and cheap:**
```
You: "Check the auth middleware for security issues"
→ Claude greps for the file, reads it, gives feedback. One tool call.
```

### 4. Don't paste full build logs

**Expensive (60K chars in context forever):**
```
You: [pastes entire npm build output]
"Fix the build"
```

**Cheap:**
```
You: "Build failed with: TypeError: Cannot read property 'map' of undefined
      at UserList.tsx:42"
```

### 5. Use `/save-context` before ending sessions

```
You: /save-context
Claude: Saved to CLAUDE.md:
  - Current state: Auth working, API routes done, frontend pending
  - Next steps: Build the dashboard page
  - Key decisions: Using JWT over sessions for auth

[Start new session]
You: "Continue with the dashboard. Context is in CLAUDE.md"
Claude: [reads CLAUDE.md, picks up exactly where you left off]
```

## The Five Anti-Patterns

| Anti-Pattern | Real Example | Cost Impact | How Burn Rate Helps |
|-------------|-------------|-------------|-------------------|
| **Monster sessions** | 184 prompts in one session | $133 | Warns at 15/25/40 with cost |
| **Spec pasting** | 20K char doc pasted in chat | Re-sent every message | Rules suggest file references |
| **Subagent storms** | "build everything" → 60 agents | $50+ in agents alone | Warns at 8/15 subagents |
| **File re-reads** | Same file read 42 times | Wasted tokens | Short sessions prevent this |
| **Build output dumping** | 60K chars of npm errors | Context bloat | Rules ask for relevant lines |

## Configuration

Adjust warning thresholds (add to your shell profile):

```bash
export BURN_RATE_WARN=15     # Gentle nudge (default: 15)
export BURN_RATE_STRONG=25   # Strong warning (default: 25)
export BURN_RATE_URGENT=40   # Urgent stop (default: 40)
```

## How It Works

1. A `UserPromptSubmit` hook fires on every prompt you send
2. Uses `CLAUDE_SESSION_ID` to find the exact current session's JSONL file
3. Counts user messages and subagent sessions
4. Detects which model you're using (Opus/Sonnet/Haiku) for accurate cost estimates
5. Outputs warnings that appear as system feedback in your session

The hook adds <50ms to each prompt — you won't notice it.

## What Gets Installed

**Plugin install** — managed by Claude Code:

| Component | Purpose |
|-----------|---------|
| Hook (`UserPromptSubmit`) | Real-time prompt counter + cost estimator |
| `/save-context` command | Save session state to project CLAUDE.md |
| `/burn-rate` command | Check current stats on demand |
| Rules | Session management injected into Claude's behavior |
| Skill | Anti-pattern guidance |

**Script install** — files copied to `~/.claude/`:

| File | Purpose |
|------|---------|
| `scripts/burn-rate.sh` | Hook script |
| `commands/burn-rate.md` | `/burn-rate` command |
| `commands/save-context.md` | `/save-context` command |
| `CLAUDE.md` | Global rules (appended) |
| `settings.json` | Hook registration (merged) |

## Compatibility

- Claude Code CLI, Desktop App, Web App
- All Claude models (Opus, Sonnet, Haiku)
- macOS and Linux
- Works alongside `everything-claude-code`, `superpowers`, and other plugins

## Uninstall

**Plugin:** `claude plugins disable burn-rate`

**Script:** `curl -fsSL https://raw.githubusercontent.com/rajkaria/burn-rate/main/uninstall.sh | bash`

## Contributing

PRs welcome:

- **Cost model calibration** — share your real token data from Sonnet/Haiku sessions
- **New anti-patterns** — what wasteful patterns have you seen?
- **Platform testing** — Linux, different shells
- **IDE integration** — VS Code / JetBrains hook support

## License

MIT
