# Neper

- The working tree is shared. Commit only touched paths; never use `git add -A` or
  `git add .`. Check status before staging and committing; do not overwrite another
  session's changes.
- For every landed capability, work only on the first item in
  `docs/work-queue.json` and update its truthful score and evidence. Keep it first
  while partial; at score 1, remove it and append the completed record as one JSON
  line to `docs/work-done.jsonl`. Run `python scripts/render_progress.py` and
  `python scripts/render_tasks.py`, and commit the generated `docs/progress.html`
  with the implementation.
- `docs/progress.html` is the only readiness document and is never hand-edited.
  Module readiness is derived automatically from committed module metadata and
  source.
- Append design decisions to `docs/decisions.md` as `## D<n> — <title>`; preserve
  earlier entries.
- Change source and docs with the Edit tool, or `build/windows/patch.exe` for a
  multi-site edit (D1455), never a Python patch script or `python - <<EOF` heredoc that
  carries `old`/`new` strings. Across Neper, Dart and Rust alike, code delivered that
  way took twice the output tokens per byte and cost 4-5x as much per KB of new code
  (`python scripts/lang-stats.py`). A script is for content it computes: constants,
  tables, generated fixtures.
- Read the digests before the logs: `docs/digest/queue.tsv` (one row per open item)
  and `docs/digest/decisions.tsv` (one row per decision, with its size); then
  `grep -n "^## D<n> " docs/decisions.md` for the one entry. Regenerate with
  `python scripts/render_digest.py`; never read `decisions.md` whole.

## Prompt routing (measured: `python scripts/lang-stats.py`)

- OpenCode reads this file and the skill at `.opencode/skills/neper/SKILL.md`; both
  route to the same path: card first (`docs/llm-neper-card.md`), `context-file` before
  file reads, `patch.exe` or `plan-*` before scripts, `scripts/check-fixture.sh` to
  verify one fixture. `python scripts/check_agent_routes.py` fails when a route breaks.
- Name the queue item (`L0xx`/`C0xx`/`T0xx`) plus its acceptance list in
  every build prompt. Bare delegates ("continue", "do it", "implement
  those", "/goal continue") correlate with repeat 59–72% and turns/ed
  6–7 — restate the item ID instead.
- Read `docs/llm-neper-card.md` (traps section: `target`, `Vec`/`i8`,
  D66 no-shadow, string escapes, bootstrap-only rules) and resolve
  symbols via context-file/`neper index` before opening files.
  Full-turn context at 400–500 Ktk vs 1–5 K via context-file is the
  largest cost lever (T026).
- Repair prompts carry the diagnostic identity: code (`E-XXXX-nnnn`),
  span, expected vs found. Median fix is 1–2 turns with it, 3+ without;
  repeated codes across consecutive failures mean the message was
  misread — re-attach the subject (T028).
- Separate verify-only turns (run suite, report tail, no edits) from
  build turns. Never combine "implement + verify everything" in one
  prompt.
- Multi-file edits are one transaction with preconditions per file
  (expected SHA-256); a stale precondition aborts, never partially
  applies. No Python patch script or `python - <<EOF` heredoc carrying
  `old`/`new` strings — Edit or `build/windows/patch.exe` spec only.
  Scripts are for content they compute.
