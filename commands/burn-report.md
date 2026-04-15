Generate a visual postmortem of the current (or a specific) session.

Run the burn report script. Try these locations in order:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-/dev/null}/scripts/burn-report.sh" $ARGUMENTS 2>/dev/null || \
bash ~/.claude/scripts/burn-report.sh $ARGUMENTS 2>/dev/null || \
echo "burn-report.sh not found"
```

`$ARGUMENTS` is optional — pass a session ID or a path to a `.jsonl` file to report on a specific past session. Without args, it uses the current session.

Show the full output to the user verbatim — the visual boxes are the whole point. Do not summarize or paraphrase.

After the report, if there are notable findings (🚨 files re-read 5+ times, >8 subagents, >10K char pastes, >90% cache reads) briefly reinforce the top 1–2 recommendations from the "WHAT TO DO NEXT" box in plain language. Do not repeat the entire report.

If the user is in a lean session (✅), congratulate them briefly and stop — no further commentary.
