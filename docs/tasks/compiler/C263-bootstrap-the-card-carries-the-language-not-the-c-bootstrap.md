# C263 — bootstrap: the card carries the language, not the C bootstrap's defects

| field | value |
|---|---|
| category | compiler / Language design |
| score | 0.00 of 1 |
| queue position | 219 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened from the 2026-11-04 language design review. Problem: docs/llm-neper-card.md tells an author that code under `src/` must also build with the C bootstrap, which refuses `-=` and `x > CONST {` and truncates a function past 256 locals silently. Those are bootstrap defects printed as language rules. A generator avoids legal syntax and still cannot know when the truncation bites, and a clean bootstrap build is not proof of anything. Proposal: the card carries the language and nothing else. The bootstrap either accepts the surface the grammar defines or it is gone, which is C088, the first queue row. Until then the card carries one sentence pointing at C088 instead of a list of shapes to avoid. Token and cost: the card is loaded on nearly every edit turn, so a `src/`-only exception list is tokens spent on a defect the self-host build would catch anyway, and a silently truncated function costs a debugging session. Not done: the card source edit and re-render, and either the three bootstrap fixes with a fixture per shape or C088's closure.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `src/`: `scripts/drivers_reference.rs`×12†, `scripts/query_reference.mjs`×9, `benchmarks/baseline/results/baseline-linux.json`×8, `benchmarks/baseline/results/h25-linux-d936.json`×8, `benchmarks/llm_edit/hard_context.py`×8, `scripts/page_reference.mjs`×7, `scripts/syncjob_reference.mjs`×7, `scripts/offline_reference.mjs`×6

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- `python scripts/render_progress.py` must run clean after the queue edit.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
