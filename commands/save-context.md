Save the current session context so the next session can pick up where this one left off.

This project (and any project using the **Context Router**) keeps context in
per-feature docs under `docs/context/`, NOT in one growing `## Session Context` block.
Write the session's state into the doc(s) for the area you actually worked on, so the
router can load just that next time.

Do the following:

1. **Summarize this session** — identify:
   - Key decisions made
   - Files created or modified (list them with brief descriptions)
   - Current state of the work (what's working, what's not)
   - Blockers or open questions
   - Clear, actionable next steps

2. **Find the target feature doc(s).** Look at what this session changed
   (`git status` + recent `git diff --stat`). For each changed area, find the
   `docs/context/<feature>.md` whose `globs:` frontmatter matches those paths.
   - **Migration case:** if there is no `docs/context/` directory but `CLAUDE.md` has a
     legacy `## Session Context` block, run `/burn-context-init` first to split it, then
     continue.
   - **No matching doc:** create a new `docs/context/<feature>.md`. Add YAML frontmatter
     with `feature:`, `globs:` (the source paths it covers — be specific so routing is
     accurate), and `updated:` (today). Then add a row to the index table in `CLAUDE.md`.

3. **Update the matching doc(s) in place** — refresh these sections (create if missing).
   **Overwrite** the current state; do not append session-after-session (that's the bloat
   the router exists to kill). Keep prior decisions that still hold.
   ```
   ## Current state — what's working, deployed, broken
   ## Recent changes — files touched and why
   ## Key decisions — choices and trade-offs, why X over Y
   ## Next steps — specific, actionable
   ```
   Bump the doc's `updated:` frontmatter to today.

4. **Refresh the index** — make sure the table in `CLAUDE.md` lists every
   `docs/context/*.md` with a one-line "covers" description and points at the right path.
   Keep `CLAUDE.md` thin: index only, no session prose.

5. **Safety check** — NEVER write API keys, tokens, passwords, or secrets into any doc.
   Reference credentials generically (e.g., "configured Supabase connection", not the key).

6. **Post-session burn report** — run the burn rate script and show a summary:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT:-/dev/null}/scripts/burn-rate.sh" 2>/dev/null || bash ~/.claude/scripts/burn-rate.sh 2>/dev/null
   # Also flush to history so /burn-trend picks it up
   bash "${CLAUDE_PLUGIN_ROOT:-/dev/null}/scripts/burn-rate-log.sh" 2>/dev/null || bash ~/.claude/scripts/burn-rate-log.sh 2>/dev/null
   ```
   Then summarize: total prompts, total tokens, tokens per prompt, cache reads vs writes
   vs output, and how it compares to an ideal session (15 prompts, <10M tokens).

7. **Confirm** — tell the user which doc(s) you updated (with paths) and that they can
   safely start a new session — the router will reload exactly those when they next touch
   the same files.
