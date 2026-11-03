# T065 — H43: performance-regression obligations with pre-registered statistics bound into receipts

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.00 of 1 |
| queue position | 151 of 192 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened 2026-11-03 from docs/post-m2-llm-hardening.md:1549 by the single-list audit; not previously a queue row. Acceptance: A change contract can name a benchmark obligation (baseline artifact, workload/data hashes, metric, threshold, repetitions, warmup) and the runner returns pass/regression/inconclusive/invalid from a distribution, never a best run. Fixtures for a known regression, noisy data, changed baseline, background disturbance and cherry-picked samples never produce a pass; result artifacts and environment identity enter the receipt. Size L. Checked open: grep H43 in work-done = 0; not named in T039-T042 queue text; benchmarks/baseline/gate.py judges fixed budgets only, not contract-bound obligations.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
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
