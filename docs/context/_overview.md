---
feature: Overview
globs: [README.md]
updated: 2026-06-15
---

# Burn Rate — overview

A Claude Code plugin that makes token burn visible and cuts it: a real-time fuel
gauge, anti-pattern detection (paste bombs, subagent storms, file re-reads), and
cross-session context persistence.

This doc is the default context the router loads when nothing more specific matches.
For a specific area, the router will load the matching doc instead — see the index in
the project `CLAUDE.md`.

## Surface area

- **Commands:** `/burn-rate`, `/burn-report`, `/burn-lint`, `/burn-trend`,
  `/save-context`, `/burn-context-init`
- **Hooks:** SessionStart (context router), UserPromptSubmit (paste-saver + main
  analyzer), PreToolUse:Task (subagent gate), SessionEnd (history logger)
- **Distribution:** `install.sh` (symlink + settings.json) and the plugin manifest
  under `.claude-plugin/`

## Current state

**v4.2.0 — shipped to `main`, live via symlinks.** Three things landed this session:
(1) the **Context Router** — per-feature `docs/context/` docs loaded on demand with a
thin `CLAUDE.md` index ([context-router.md](context-router.md)); (2) three **burn
levers** — eager-MCP audit in `/burn-lint`, a strategic-compact tip, and re-read-cost in
`/burn-report` ([reporting.md](reporting.md)); (3) the long-uncommitted **April
stdin-JSON hook-context fix** plus a worktree project-key bug fix ([hooks.md](hooks.md)).
Tests: context-router 11/11, burn-levers 10/10. No outstanding bugs.

## Where things live

| Area | Doc |
|---|---|
| Context router, save-context, migration | context-router.md |
| paste-saver, subagent-gate, history logger, wiring | hooks.md |
| burn-rate analyzer, report, trend, lint | reporting.md |
| install.sh, uninstall, plugin manifest, versioning | install.md |
