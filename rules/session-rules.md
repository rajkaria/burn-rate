## Session Length Management (Burn Rate)
- Track conversation depth. After ~15 user messages, remind the user to consider wrapping up and starting a fresh session.
- After ~25 user messages, strongly recommend saving context and starting a new session. Explain that each message re-sends the full conversation, making long sessions exponentially expensive.
- Before ending any session or when the user says they're done, proactively offer to run `/save-context` to preserve state for the next session.

## Prompt Discipline
- When the user gives a broad prompt like "build everything" or "go through the spec and implement it all," push back. Ask them to break it into specific, scoped tasks (e.g., "Let's start with the database schema" or "Let's focus on the auth module first").
- When the user pastes a large spec or document (>3000 chars) into the chat, suggest putting it in a file (e.g., `docs/SPEC.md`) and referencing it instead. Large pasted content stays in context for every subsequent message.
- When the user pastes raw build output or stack traces, ask them to share only the relevant error lines.

## Context Persistence
- When starting a session in a project, check for a project-level CLAUDE.md in the project root. If it has a `## Session Context` section, read it to understand prior context.
- When saving context (via `/save-context` or before session end), update the project-root CLAUDE.md with: key decisions made, files modified, current state, and next steps.

## Output Efficiency
- Do NOT narrate between tool calls. No "Now I'll do X", "Let me check Y", or "Task N done, moving to Z".
- Only output text when: asking a question, reporting an error/blocker, or delivering final results.
- Skip transition phrases. Go straight from one tool call to the next silently.
- TodoWrite: update at most once per logical phase, not per micro-step.
- Combine adjacent independent tool calls into parallel batches without pausing to narrate.
- Final summary only — no per-step progress reports.

## Subagent Awareness
- Avoid spawning many subagents for broad exploration tasks. Each subagent loads full project context independently.
- When a single focused search (Grep/Glob) would suffice, use that instead of an Explore agent.
- Never spawn more than 3 agents for a single task unless the user explicitly requests parallel work.
