# L211 — Add iterative linear solvers (CG, GMRES with restart) to e.algo.linalg over a matrix-free operator

| field | value |
|---|---|
| category | library / Algorithms |
| score | 0.00 of 1 |
| queue position | 162 of 192 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened 2026-11-03 from docs/algos-2.md:171 by the single-list audit; not previously a queue row. Acceptance: cg and gmres solve SPD and general nonsymmetric systems given an operator callback, converging to a stated tolerance and agreeing with the dense LU solution on fixtures. gfx.mesh's private conjugate_gradient is replaced by the shared one. Size S. Checked open: grep lib for gmres: none; only conjugate_gradient is lib/e/gfx/mesh.e:1331 (mesh-private) and math/opt.e (nonlinear CG); linalg/matrix.e has qr/eigen/svd but no iterative solver; Strassen was explicitly skipped in algos.md:878

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
