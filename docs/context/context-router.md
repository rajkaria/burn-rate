---
feature: Context Router
globs:
  - scripts/burn-rate-resume.sh
  - commands/save-context.md
  - commands/burn-context-init.md
  - docs/context/*
  - tests/test-context-router.sh
updated: 2026-06-15
---

# Context Router

Keeps `CLAUDE.md` thin and loads per-feature context on demand, so a session only
pays for the context it actually needs.

## How it works

- **Per-feature docs** live in `docs/context/<feature>.md`. Each declares `globs:` in
  YAML frontmatter — the source paths that doc is "about".
- **`CLAUDE.md`** holds only a thin index table (feature → doc → covers). No `@import`
  (that would eager-load everything and defeat the point), no session blocks.
- **The router** (`scripts/burn-rate-resume.sh`, the SessionStart hook) computes the
  files you've recently touched (last N commits via `git diff` + uncommitted via
  `git status`), matches them against every doc's globs, and injects the top-scoring
  docs plus the thin index. Capped at `BURN_RATE_ROUTER_MAX_DOCS` (default 3) and
  `BURN_RATE_ROUTER_MAX_CHARS` (default 1500/doc) so it can never re-bloat.

## Key decisions

- **On-demand, not `@import`.** Imports load eagerly every session → zero savings.
  Only lazy loading helps. The index lets Claude read any doc on demand even when the
  router didn't auto-pick it.
- **File-based routing**, not branch name — the user's worktree branches are
  auto-named (`claude/<slug>`), so branch routing would miss. Changed files always
  reflect real work and are immune to branch naming.
- **Hook kept the `burn-rate-resume.sh` filename** so the existing `~/.claude` symlink
  and all hook wiring stay valid — the router goes live the instant the repo updates,
  no re-wiring. The script's role grew; the filename stayed.
- **Legacy fallback**: if a repo has no `docs/context/` but still has a
  `## Session Context` block in CLAUDE.md, the hook behaves exactly like the old
  resume hook. Nothing breaks before migration.
- **Budget guard is load-bearing**: a "load relevant docs" feature that loads 8 docs
  is just bloat again. The cap + relevance ranking is the whole point.

## Files

- `scripts/burn-rate-resume.sh` — the router (router mode + legacy fallback)
- `commands/save-context.md` — writes back into the matching feature doc, not one
  growing block; refreshes the index
- `commands/burn-context-init.md` — one-time migration from a legacy block
- `docs/context/*.md` — the feature docs (this directory)
- `tests/test-context-router.sh` — smoke tests (routing, cap, staleness, legacy)

## Config

`BURN_RATE_CONTEXT_DIR` (default `docs/context`), `BURN_RATE_ROUTER_MAX_DOCS` (3),
`BURN_RATE_ROUTER_MAX_CHARS` (1500), `BURN_RATE_ROUTER_LOOKBACK` (5 commits),
`BURN_RATE_RESUME_MAX_AGE_DAYS` (7), `BURN_RATE_NO_ROUTER=1` to disable.

## Next steps

- Optional: `/burn-lint` already flags unroutable/stale/bloated context docs — keep an
  eye on those findings as docs accumulate.
- Optional: a UserPromptSubmit refinement that adds an intent-matched doc when the
  first prompt clearly names a feature the file-based router missed.
