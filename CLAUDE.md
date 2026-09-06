# neper — working instructions

## Readiness reporting

`docs/progress.html` is the single readiness document for this project. It reports
compiler, module and tooling readiness as percentages, each backed by a scored
capability list.

**Every session that lands a capability updates it, in the same commit as the change
that earned it.** The page is generated, never hand-edited:

1. Move the affected rows in the `compiler` / `tooling` tables near the top of
   `scripts/render_progress.py` — score `1` when delivered, `0` when not started, or a
   fraction when partial, with the evidence or the gap in the third column.
2. Run `python scripts/render_progress.py` from the repository root.
3. Commit the regenerated `docs/progress.html` alongside the change.

Module readiness needs no editing: it is read from `docs/module-apis.md`,
`docs/modules.json`, the committed `lib/e` sources and the intrinsics seeded in
`src/resolve.e`.

Do not create a second progress page, dashboard or artifact. If a readiness summary is
needed somewhere else, point at this file.

## Staging

Follow `docs/implementation-handoff.md` section 8: commit only the paths the change
touches. Never `git add -A` or `git add .` — the working tree is shared with other
active sessions and usually carries unrelated uncommitted work. Check `git status`
before staging and again before committing; if a file you need is modified by someone
else, say so rather than clobbering it.

## Decisions

Record a design decision as a `## D<n> — <title>` section in `docs/decisions.md`,
continuing the existing numbering. Earlier rows are history and are not rewritten.
