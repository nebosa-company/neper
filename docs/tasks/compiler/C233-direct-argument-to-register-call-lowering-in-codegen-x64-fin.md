# C233 — Direct argument-to-register call lowering in codegen_x64 (finish db-perf item 1 acceptance)

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.00 of 1 |
| queue position | 147 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened 2026-11-03 from docs/db-perf-plan.md:60 by the single-list audit; not previously a queue row. Acceptance: A call moves an argument already in a register straight to its parameter register and the result straight to its destination register, with the outgoing-slot path kept only for stack args. benchmarks/db/run.py shows the SQLite scan at >=70% of C (now 56-59%) on both hosts, no cell slower, stage 2 = stage 3 fixed point re-baselined. Size L. Checked open: regalloc.e already has crosses_call preference (D1607) but doc records acceptance missed; load_call_arguments path still the rule in src/codegen_x64.e; no queue row mentions call lowering or db scan ratio.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

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
