# Neper

- The working tree is shared. Commit only touched paths; never use `git add -A` or
  `git add .`. Check status before staging and committing; do not overwrite another
  session's changes.
- For every landed capability, update the first item in `docs/work-queue.json`
  with its truthful score and evidence. Keep it first while partial; at score 1,
  remove it and append the completed record as one JSON line to
  `docs/work-done.jsonl`. Run
  `python scripts/render_progress.py` and commit the generated
  `docs/progress.html` with the implementation.
- `docs/progress.html` is the only readiness document and is never hand-edited.
- Append design decisions to `docs/decisions.md` as `## D<n> — <title>`; preserve
  earlier entries.
