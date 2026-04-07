Show the current session's burn rate stats on demand.

Run the burn rate hook script and display the output:

```bash
bash ~/.claude/scripts/burn-rate.sh
```

If no output (session is below all thresholds), tell the user their current session is still in the safe zone (<15 prompts).

Additionally, provide these tips based on the current session:
- If subagent count is high: suggest more targeted tool calls
- If the user has been pasting large blocks of text: remind them to use file references
- Recommend running `/save-context` before starting a new session when they're ready to wrap up
