# C091 — M3-03: CPU backend, workgroup-by-workgroup launch with barrier loop-fission

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.30 of 1 |
| queue position | 30 of 55 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> A launch on `.Cpu` runs the whole grid on the calling thread, workgroups in workgroup-id order and invocations in local-id order, the grid rounded up to whole workgroups, with `gpu.gid`, `gpu.lid` and `gpu.wgid` set before each invocation (D778; `link/gpu_cpu`, `examples/saxpy.e`)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the barrier state machine and its divergence trap, per-invocation slots for locals that cross a barrier, `shared var`, subgroups
- [ ] the debug `0xCD` fill, `--subgroup-width`

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D778` — M3 opens with `e.gpu` on the CPU backend and `gpu.launch` as the third pack intrinsic (`docs/decisions.md:14678`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `.Cpu`: `lib/e/gpu.e`×6
- `gpu.gid`: `lib/e/gpu.e`×1, `src/check.e`×1‡, `src/lower.e`×1‡
- `gpu.lid`: `src/lower.e`×1‡
- `gpu.wgid`: `src/lower.e`×1‡

## Existing fixtures

- `tests/selfhost/fixtures/link/gpu_cpu`

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
