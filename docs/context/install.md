---
feature: Install & Packaging
globs:
  - install.sh
  - uninstall.sh
  - .claude-plugin/*
updated: 2026-06-15
---

# Install & packaging

## Two install paths

1. **`install.sh`** — symlinks scripts to `~/.claude/scripts/`, commands to
   `~/.claude/commands/`, and wires hooks into `~/.claude/settings.json` (idempotent
   python merge). When run from a local clone it **symlinks** (repo edits propagate
   with no reinstall); piped via curl it downloads.
2. **Plugin manifest** — `.claude-plugin/marketplace.json` + `plugin.json`, hooks via
   `hooks/hooks.json` using `${CLAUDE_PLUGIN_ROOT}`.

## Why the router needed no rewiring

`burn-rate-resume.sh` kept its filename when it became the context router, so the
existing `~/.claude/scripts/burn-rate-resume.sh` symlink already serves the new logic.
Only genuinely new files (e.g. `commands/burn-context-init.md`) need a fresh symlink,
which is why `install.sh` is re-run after adding the router.

## Versioning

Bump `version` in **both** `.claude-plugin/plugin.json` and `marketplace.json` together.
Context Router shipped as **4.1.0**; the three burn levers (MCP audit, strategic-compact,
re-read cost) + the worktree project-key fix shipped as **4.2.0**. Both minor — additive
and backward compatible.

## Gotchas

- `install.sh` purges legacy `session-guard` hook entries from settings.json — follow
  that same pattern if a hook is ever renamed/removed.
- The command/script lists in `install.sh` must include every new command/script or it
  won't be symlinked on install.
