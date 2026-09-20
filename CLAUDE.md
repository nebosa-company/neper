# Neper

## Capabilities

For every landed capability:

1. Work only on the first item in `docs/work-queue.json` and update its truthful
   score and evidence. Keep it first while partial. At score `1`, remove it and
   append the completed record as one JSON line to `docs/work-done.jsonl`.
2. Run `python scripts/render_progress.py` and `python scripts/render_tasks.py`.
3. Commit `docs/progress.html` with the implementation.

`docs/progress.html` is the only readiness document and is never hand-edited.
Module readiness is derived automatically from committed module metadata and source.

## Git

The working tree is shared. Commit only touched paths; never use `git add -A` or
`git add .`. Check status before staging and committing. Do not overwrite a file
modified by another session.

## Decisions

Append design decisions to `docs/decisions.md` as `## D<n> — <title>`; preserve
earlier entries.
