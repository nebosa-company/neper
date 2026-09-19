# Neper

## Capabilities

For every landed capability:

1. Update its compiler/tooling row in `scripts/render_progress.py`: `1` delivered,
   `0` absent, or a truthful fraction, with evidence or the remaining gap.
2. Run `python scripts/render_progress.py`.
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
