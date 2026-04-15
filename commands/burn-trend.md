Show week-over-week burn rate trends across all your sessions.

Run the trend script:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-/dev/null}/scripts/burn-trend.sh" 2>/dev/null || \
bash ~/.claude/scripts/burn-trend.sh 2>/dev/null || \
echo "burn-trend.sh not found"
```

Show the output verbatim. The comparison table is the whole point.

If history is empty, tell the user:
- History is written automatically on SessionEnd (the plugin hook).
- `/save-context` also flushes the current session to history as a safety net.
- They'll need at least a couple of sessions before trends become meaningful.

If the week-over-week row shows a large regression (🎉 or ⚠️), surface that insight in one plain-language line. Do not repeat the entire report.
