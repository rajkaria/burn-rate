---
feature: Reporting & Analysis
globs:
  - scripts/burn-rate.sh
  - scripts/burn-report.sh
  - scripts/burn-trend.sh
  - scripts/burn-rate-lint.sh
  - pricing.json
updated: 2026-06-15
---

# Reporting & analysis

The read-side tools that turn transcript data into signal.

## `burn-rate.sh` (main analyzer)

UserPromptSubmit hook + `/burn-rate` command. Parses the session transcript and emits
the live gauge: prompt count, token volume, per-prompt rate, cache reads vs writes vs
output. Thresholds are both prompt-count (`BURN_RATE_WARN/STRONG/URGENT`) and
token-volume (`BURN_RATE_TOKEN_*`) based. Also: per-file re-read counter
(`BURN_RATE_REREAD_WARN`), plan-budget % (`BURN_RATE_PLAN`), and a one-shot
model-switch tip when a trivial-streak is detected (flag file under
`~/.claude/.burn-rate/tips-shown/` so it shows at most once per session). It also fires
a one-shot **strategic-compact tip** at a natural lull when context is large and mostly
re-read (`lull` signal + cache-read share ≥70%), and resolves the session transcript
from the hook's stdin JSON — with a worktree-safe project-dir fallback (`/` and `.` both
map to `-`, so `/.claude` → `--claude`).

## `/burn-report` (`burn-report.sh`)

Visual postmortem: top re-read files **plus the wasted-token cost of those re-reads**
(redundant reads × file size), paste bombs, biggest turns, recommendations.

## `/burn-trend` (`burn-trend.sh`)

Week-over-week trend from `~/.claude/.burn-rate/history.jsonl`.

## `/burn-lint` (`burn-rate-lint.sh`)

Audits CLAUDE.md files for bloat (section sizes, duplicate paragraphs, token estimate)
and — since the Context Router landed — audits `docs/context/`: flags docs with no
`globs:` (unroutable), stale docs, and oversized feature docs. It also audits
**eagerly-loaded MCP servers** (`mcpServers` in `.mcp.json` / `~/.claude.json` /
settings) — each adds its tool schema to every turn; plugin tools deferred via
ToolSearch are reported as fine. The audit runs even when no `CLAUDE.md` is present.

## Pricing

`pricing.json` holds per-token rates for optional `$` display
(`BURN_RATE_SHOW_COST=1`). Tokens are the primary metric; cost is opt-in.
