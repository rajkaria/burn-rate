Audit CLAUDE.md files for bloat. Every line in CLAUDE.md is silently re-sent with every prompt — large or duplicated instructions cost real tokens.

Run the lint script. Try these locations in order:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-/dev/null}/scripts/burn-rate-lint.sh" $ARGUMENTS 2>/dev/null || \
bash ~/.claude/scripts/burn-rate-lint.sh $ARGUMENTS 2>/dev/null || \
echo "burn-rate-lint.sh not found"
```

`$ARGUMENTS` is optional — pass a path to a specific CLAUDE.md. With no args it checks both the project-root `CLAUDE.md` and `~/.claude/CLAUDE.md`.

Show the output verbatim. The boxed report is the whole point.

After the report, if the file is 🔥 BLOATED or ⚠️ HEAVY, offer to help prune it: ask which section the user wants to trim first, or propose moving the biggest section to a separate doc file referenced from CLAUDE.md. Do NOT modify the file without explicit user approval — CLAUDE.md is sacred.

If the file is ✅ LEAN, stop — no further action needed.
