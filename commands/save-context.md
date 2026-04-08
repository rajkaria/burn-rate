Save the current session context so the next session can pick up where this one left off.

Do the following:

1. **Summarize this session** — identify:
   - Key decisions made
   - Files created or modified (list them with brief descriptions)
   - Current state of the work (what's working, what's not)
   - Blockers or open questions
   - Clear, actionable next steps

2. **Update the project-root CLAUDE.md** — find or create a `CLAUDE.md` file in the project root directory (NOT ~/.claude/CLAUDE.md — that's global). Add or update a `## Session Context` section with the summary. If previous session context exists, move it under `### Previous Session Notes`. Structure:

```
## Session Context (Last updated: YYYY-MM-DD HH:MM)

### Current State
- What's working, deployed, broken

### Recent Changes
- Files modified and why

### Next Steps
- What to pick up in the next session (be specific and actionable)

### Key Decisions
- Architecture choices, trade-offs, why we chose X over Y

### Previous Session Notes
- (older context, kept for reference but can be trimmed)
```

3. **Safety check** — NEVER write API keys, tokens, passwords, or secrets into the CLAUDE.md. If the session involved credentials, reference them generically (e.g., "configured Supabase connection" not the actual key).

4. **Post-session burn report** — run the burn rate script and show a summary:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-/dev/null}/scripts/burn-rate.sh" 2>/dev/null || bash ~/.claude/scripts/burn-rate.sh 2>/dev/null
```

Then summarize for the user:
- Total prompts, total tokens, tokens per prompt
- Token breakdown (cache reads vs writes vs output)
- How this compares to an ideal session (15 prompts, <10M tokens)

5. **Confirm** — tell the user the context has been saved and they can safely start a new session. Mention the file path where context was saved.
