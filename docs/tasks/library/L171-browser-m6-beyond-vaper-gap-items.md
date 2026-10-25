# L171 — Browser M6: beyond Vaper (gap items)

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 102 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Plan docs/browser-progress.html. Needs L170; individual gap rows may start earlier when nothing blocks them. Acceptance: every tracker row with track gap or core is done or explicitly deferred with a decision: Shadow DOM and custom elements (6.16), Workers and Service Workers (6.18, 6.19), contenteditable and Selection (6.11, 6.12), process isolation and OS sandbox (8.1 to 8.3, N.6), DevTools (7.13), WebAssembly (5.17), vertical writing modes (2.16, N.5), audio (3.19), backdrop-filter and blend modes (N.3), colour emoji and CFF (N.4), HSTS and clickjacking protections (4.15, 4.16), fuzzing (8.4)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

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
