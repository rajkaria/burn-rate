Show the current session's burn rate stats on demand.

Run the burn rate analysis. Try these script locations in order (first match wins):

```bash
# Plugin install location
bash "${CLAUDE_PLUGIN_ROOT:-/dev/null}/scripts/burn-rate.sh" 2>/dev/null || \
# Script install location
bash ~/.claude/scripts/burn-rate.sh 2>/dev/null || \
echo "burn-rate.sh not found"
```

Report the results to the user:
- **Prompt count** — how many user messages in this session
- **Token count** — total tokens consumed (input + cache + output)
- **Estimated cost** — based on the detected model and current pricing
- **Subagent count** — how many subagents were spawned

If no output (session is below all thresholds), tell the user their current session is still in the safe zone (<15 prompts) and show the token count so far.

Additionally, provide these tips based on the current session:
- If subagent count is high: suggest more targeted tool calls
- If the user has been pasting large blocks of text: remind them to use file references
- Recommend running `/save-context` before starting a new session when they're ready to wrap up
