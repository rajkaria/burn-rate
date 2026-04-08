Show the current session's burn rate stats on demand.

Run the burn rate analysis. Try these script locations in order (first match wins):

```bash
# Plugin install location
bash "${CLAUDE_PLUGIN_ROOT:-/dev/null}/scripts/burn-rate.sh" 2>/dev/null || \
# Script install location
bash ~/.claude/scripts/burn-rate.sh 2>/dev/null || \
echo "burn-rate.sh not found"
```

Report the results to the user in a clear table:
- **Prompt count** — how many actual human messages in this session (tool results are excluded)
- **Token count** — total tokens consumed
- **Tokens per prompt** — average tokens consumed per human prompt (shows burn velocity)
- **Token breakdown** — cache reads (re-sent context), cache writes (new context), output (Claude's responses)
- **Subagent count** — how many subagents were spawned
- **Estimated cost** — only shown if user has set `BURN_RATE_SHOW_COST=1`

If no output (session is below all thresholds), still show the stats in a friendly format — tell the user their current session is in the safe zone (<15 prompts) and show their token count, tokens per prompt, and breakdown.

Interpret the breakdown for the user:
- If cache reads dominate (>90% of total): "Most tokens are context being re-sent — normal for long sessions but grows fast"
- If cache writes are high relative to reads: "Lots of new context being added — heavy exploration or file reads"
- If output is unusually high (>5% of total): "Claude is generating a lot of output — large code generation or explanations"

Additionally, provide tips based on the current session:
- If subagent count is high: suggest more targeted tool calls
- If tokens per prompt is >3M: "Context is getting heavy — consider /compact or /save-context"
- Recommend running `/save-context` before starting a new session when they're ready to wrap up
