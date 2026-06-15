One-time migration: split a monolithic `CLAUDE.md` into the Context Router layout
(`docs/context/` per-feature docs + a thin index). Safe and idempotent — if
`docs/context/` already exists, report and stop.

Why: every line of `CLAUDE.md` is re-sent into every session. A growing
`## Session Context` block (and `### Previous Session Notes`) taxes every prompt. The
router loads only the relevant per-feature doc instead. See
`docs/context/context-router.md` (created by this command) for how it works.

Do the following:

1. **Guard.** If `docs/context/` already exists, tell the user the project is already
   migrated and stop. Don't clobber existing docs.

2. **Read the current `CLAUDE.md`.** Capture any `## Session Context` block and
   `### Previous Session Notes`. Also skim the repo (top-level dirs, scripts, commands,
   `git log --oneline -20`) to learn the natural feature areas.

3. **Decide the feature split.** Group the project into a handful of coherent areas
   (aim for 3–7). Examples: one per subsystem, per top-level source dir, or per command
   group. Don't over-split — a doc per file defeats the purpose.

4. **Create `docs/context/<feature>.md` for each area.** Every doc starts with YAML
   frontmatter, then the state sections:
   ```markdown
   ---
   feature: <Human Name>
   globs:
     - <source path or glob this doc is about>
     - <another>
   updated: <today YYYY-MM-DD>
   ---

   ## Current state
   ## Recent changes
   ## Key decisions
   ## Next steps
   ```
   - `globs:` is what makes routing work — list the real paths each area owns. Be
     specific; avoid broad globs that match everything.
   - Seed each doc by distributing the old block's content into the area it belongs to.
   - Create `docs/context/_overview.md` for project-wide state (it's the router's default
     when nothing else matches) and a `docs/context/context-router.md` describing this
     setup.

5. **Replace the block in `CLAUDE.md` with a thin index.** Keep any genuine global rules,
   then add:
   ```markdown
   ## Context index

   | Feature | Doc | Covers |
   |---|---|---|
   | <Name> | docs/context/<feature>.md | <one line> |
   ```
   Remove the old `## Session Context` and `### Previous Session Notes` blocks — their
   content now lives in the docs. `CLAUDE.md` should be index + rules only.

6. **Safety check** — never copy secrets into the new docs.

7. **Confirm** — list the docs created and show the new `CLAUDE.md` index. Mention that
   `/save-context` will maintain these from now on, and the SessionStart router will load
   the relevant one based on which files are being touched.
