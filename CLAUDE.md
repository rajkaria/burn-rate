# Burn Rate — project notes for Claude Code

## Session Context (Last updated: 2026-04-15 10:59)

### Current State
Burn Rate plugin expanded from 2 commands to 5 + 4 hooks. All features shipped, syntax-validated, integration-tested end-to-end. No outstanding bugs. Ready to bump version and cut a release.

- **Commands:** `/burn-rate`, `/burn-report`, `/burn-lint`, `/burn-trend`, `/save-context`
- **Scripts:** `burn-rate.sh`, `burn-report.sh`, `burn-rate-lint.sh`, `burn-rate-log.sh`, `burn-trend.sh`, `burn-rate-subagent-gate.sh`, `burn-rate-paste-saver.sh`, `burn-rate-resume.sh`
- **Hooks wired:** SessionStart (resume), UserPromptSubmit (paste-saver + main analyzer), PreToolUse:Task (subagent gate), SessionEnd (history logger)
- **README:** fully updated with rendered example boxes for every new feature + env-var docs

### Recent Changes
- `scripts/burn-report.sh` — visual postmortem (top re-read files, paste bombs, biggest turns, recommendations)
- `scripts/burn-rate.sh` — extended with per-file re-read counter, plan-budget %, model-switch trivial-streak detection
- `scripts/burn-rate-lint.sh` — CLAUDE.md bloat auditor (section sizes, dupes, token estimate)
- `scripts/burn-rate-log.sh` — SessionEnd logger writing to `~/.claude/.burn-rate/history.jsonl` (capped 500 rows)
- `scripts/burn-trend.sh` — week-over-week trend report from history file
- `scripts/burn-rate-subagent-gate.sh` — PreToolUse:Task gate, emits `permissionDecision: ask` JSON when subagent count ≥ `BURN_RATE_SUBAGENT_BUDGET` (default 5)
- `scripts/burn-rate-paste-saver.sh` — UserPromptSubmit hook, saves ≥3K-char prompts to `./.burn-rate/pastes/paste-TIMESTAMP.txt`, auto-adds `.burn-rate/` to `.gitignore`, never blocks
- `scripts/burn-rate-resume.sh` — SessionStart hook, reads `## Session Context` block from project CLAUDE.md, flags stale (>7d) and git-diverged cases
- `commands/burn-report.md`, `commands/burn-lint.md`, `commands/burn-trend.md` — new slash commands
- `commands/save-context.md` — also flushes history.jsonl as safety net
- `hooks/hooks.json` — wired all four hook events
- `README.md` — new sections for `/burn-report`, `/burn-lint`, `/burn-trend`, paste saver, auto-resume, model tip, subagent gate; expanded env-var table

### Next Steps
1. **Version bump + release** — update plugin manifest to new version, tag release, push. The feature surface expanded significantly; warrants a minor version.
2. **Real-world shakedown** — paste saver, resume, and subagent gate haven't been exercised in anger. Run a day of normal work with the new hooks and look for: false-positive paste saves on reasonable prompts, noisy resume prompts, subagent gate firing when it shouldn't.
3. **Consider tests** — there's currently no test suite. At minimum, smoke tests for the three new hook scripts (paste-saver, resume, subagent-gate) would prevent regressions. Python+bash stub patterns are already established in the hooks themselves.
4. **Optional polish:**
   - Paste saver could strip the saved file's path from the prompt on current turn (currently only helps future turns)
   - Resume hook could show a `git diff --stat` when HEAD diverged from stored SHA
   - Add a `/burn-trend --project <name>` filter
5. **Docs:** an `ARCHITECTURE.md` describing the hook graph (which hook runs when, data flow into history.jsonl) would help future contributors.

### Key Decisions
- **Paste saver: soft-warn, never block.** Current turn works as user expects; next turn coaches file reference. Hostile UX (blocking) rejected in favor of zero-friction.
- **Auto-resume: prime, don't execute.** Inject context as additional info; never auto-run tasks; flag stale (>7d) and git-diverged cases. Default-on but with `BURN_RATE_NO_RESUME=1` escape hatch.
- **Model-switch tip: one-shot, self-suppressing.** Flag file at `~/.claude/.burn-rate/tips-shown/<session>.model-switch` ensures at most one tip per session — avoids nagging.
- **Subagent gate: `permissionDecision: ask`, not `deny`.** User retains control; gate is educational, not punitive. Default budget 5 (aggressive enough to catch 60-agent disasters, permissive enough for normal parallel work).
- **History capped at 500 rows** (~6 months daily use) — keeps `history.jsonl` tiny.
- **Leaderboard (#8) explicitly out of scope.** Requires backend, auth, privacy review — it's a separate product, not a plugin feature. **Will not be built.**

### Deferred but doable in-plugin later
- Paste saver could auto-edit the message to strip the blob (needs hook support for prompt mutation — not currently confirmed available)
- Cross-project week-over-week diff in `/burn-trend`
- Per-user rate-limit calibration (requires Anthropic API for actual plan usage — currently static budgets)

### Previous Session Notes
None — this was the first CLAUDE.md written for the project.
