# Burn Rate — project notes for Claude Code

This project dogfoods its own **Context Router**. Per-feature context lives in
`docs/context/` and is auto-loaded by the `burn-rate-resume.sh` SessionStart hook based
on which files you're touching — so this file stays thin on purpose. Don't paste session
summaries back into here; run `/save-context` and it updates the right feature doc plus
the index below. See [docs/context/context-router.md](docs/context/context-router.md).

## Context index

| Feature | Doc | Covers |
|---|---|---|
| Overview | [docs/context/_overview.md](docs/context/_overview.md) | Project-wide state, surface area, release status |
| Context Router | [docs/context/context-router.md](docs/context/context-router.md) | Router hook, `/save-context`, `/burn-context-init`, `docs/context/` format |
| Hooks | [docs/context/hooks.md](docs/context/hooks.md) | paste-saver, subagent gate, history logger, hook wiring |
| Reporting & Analysis | [docs/context/reporting.md](docs/context/reporting.md) | `burn-rate.sh`, `/burn-report`, `/burn-trend`, `/burn-lint` |
| Install & Packaging | [docs/context/install.md](docs/context/install.md) | `install.sh`, `uninstall.sh`, plugin manifest, versioning |

_To add context for a new area: create `docs/context/<feature>.md` with `globs:`
frontmatter (the source paths it's about), then add a row here. `/save-context`
maintains both automatically._
