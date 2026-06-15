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
`~/.claude/.burn-rate/tips-shown/` so it shows at most once per session).

## `/burn-report` (`burn-report.sh`)

Visual postmortem: top re-read files, paste bombs, biggest turns, recommendations.

## `/burn-trend` (`burn-trend.sh`)

Week-over-week trend from `~/.claude/.burn-rate/history.jsonl`.

## `/burn-lint` (`burn-rate-lint.sh`)

Audits CLAUDE.md files for bloat (section sizes, duplicate paragraphs, token estimate)
and — since the Context Router landed — audits `docs/context/`: flags docs with no
`globs:` (unroutable), stale docs, and oversized feature docs.

## Pricing

`pricing.json` holds per-token rates for optional `$` display
(`BURN_RATE_SHOW_COST=1`). Tokens are the primary metric; cost is opt-in.
