---
feature: Hooks
globs:
  - scripts/burn-rate-paste-saver.sh
  - scripts/burn-rate-subagent-gate.sh
  - scripts/burn-rate-log.sh
  - hooks/hooks.json
updated: 2026-06-15
---

# Hooks (non-router)

The lifecycle hooks other than the SessionStart router (see context-router.md for that).

## Wiring

`hooks/hooks.json` registers four events via `${CLAUDE_PLUGIN_ROOT}`:
- **SessionStart** → `burn-rate-resume.sh` (context router)
- **UserPromptSubmit** → `burn-rate-paste-saver.sh`, then `burn-rate.sh`
- **PreToolUse:Task** → `burn-rate-subagent-gate.sh`
- **SessionEnd** → `burn-rate-log.sh`

`install.sh` wires the same set into `~/.claude/settings.json` for the non-plugin install.

## paste-saver (`burn-rate-paste-saver.sh`)

UserPromptSubmit hook. Saves prompts ≥ `BURN_RATE_PASTE_WARN` chars (default 3000) to
`./.burn-rate/pastes/paste-TIMESTAMP.txt`, auto-adds `.burn-rate/` to `.gitignore`.
**Soft-warn, never blocks** — current turn works as the user expects; next turn coaches
file reference. Disable with `BURN_RATE_NO_DIET=1`.

## subagent gate (`burn-rate-subagent-gate.sh`)

PreToolUse:Task hook. Emits `permissionDecision: ask` once the session has spawned
≥ `BURN_RATE_SUBAGENT_BUDGET` subagents (default 5). **`ask`, not `deny`** — educational,
not punitive; user keeps control. Disable with `BURN_RATE_SUBAGENT_BUDGET=0`.

## history logger (`burn-rate-log.sh`)

SessionEnd hook. Appends a row to `~/.claude/.burn-rate/history.jsonl` (capped 500 rows,
~6 months of daily use). Feeds `/burn-trend`.

## Key fix (stdin hook context)

All session-aware hooks read the hook **context JSON from stdin** (not just
`CLAUDE_SESSION_ID` env) to find the transcript — env-only lookup caused cross-session
bleed and false warnings in fresh sessions. `burn-rate.sh`, `burn-rate-log.sh`, and
`burn-rate-subagent-gate.sh` were patched April 2026 and **committed in v4.2.0** (they'd
sat uncommitted until then). Follow-up: the step-3 fallback is now worktree-safe — the
project-dir key maps both `/` and `.` to `-` (so `/.claude` → `--claude`), which it
previously got wrong, silently failing to find the transcript in worktree sessions.
