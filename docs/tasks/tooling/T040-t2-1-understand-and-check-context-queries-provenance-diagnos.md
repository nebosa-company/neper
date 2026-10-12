# T040 — T2.1 understand and check: context, queries, provenance, diagnostics

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.05 of 1 |
| queue position | 138 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only (D1954). T2.1 slice missing: compiler-derived context, reusable semantic queries, generated provenance, compiled guidance, unsafe enumeration, tiered checks, optimization explanations and causal/recoverable diagnostics. Pickup immediately after the chart cluster. Freeze latency/startup/resource budgets before implementation. FIRST STEP (D2316): latency budgets frozen in docs/tooling-budgets.md from scripts/measure_tooling_latency.py (small program 55-90 ms; src/main.e check 450 ms, index 1.3 s / 11.8 MB, module context 1.6 s). NOT DONE: every other T2.1 obligation (compiler-derived context beyond context-file, reusable queries, provenance, compiled guidance, unsafe enumeration, tiered checks, optimization explanations, causal diagnostics) and memory budgets.

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
