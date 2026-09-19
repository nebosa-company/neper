# Neper

- The working tree is shared. Commit only touched paths; never use `git add -A` or
  `git add .`. Check status before staging and committing; do not overwrite another
  session's changes.
- For every landed capability, update its truthful score and evidence in
  `scripts/render_progress.py`, run `python scripts/render_progress.py`, and
  commit the generated `docs/progress.html` with the implementation.
- `docs/progress.html` is the only readiness document and is never hand-edited.
- Append design decisions to `docs/decisions.md` as `## D<n> — <title>`; preserve
  earlier entries.
