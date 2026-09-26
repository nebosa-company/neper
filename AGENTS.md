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
- Change source and docs with the Edit tool, or `build/windows/patch.exe` for a
  multi-site edit (D1455), never a Python patch script or `python - <<EOF` heredoc that
  carries `old`/`new` strings. Across Neper, Dart and Rust alike, code delivered that
  way took twice the output tokens per byte and cost 4-5x as much per KB of new code
  (`python scripts/lang-stats.py`). A script is for content it computes: constants,
  tables, generated fixtures.
