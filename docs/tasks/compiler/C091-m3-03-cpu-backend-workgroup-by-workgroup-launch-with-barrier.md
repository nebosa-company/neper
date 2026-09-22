# C091 — M3-03: CPU backend, workgroup-by-workgroup launch with barrier loop-fission

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.65 of 1 |
| queue position | 24 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> A launch on `.Cpu` runs the whole grid on the calling thread, workgroups in workgroup-id order and invocations in local-id order, the grid rounded up to whole workgroups, with `gpu.gid`, `gpu.lid` and `gpu.wgid` set before each step (D778). The kernel's CPU build is a resumable step (D780): every local lives in a frame of the invocation's own (`FieldAddress` words made in the entry block, `Stack` answering the next one), the body is cut at every `gpu.barrier()` into a store of the barrier's number, a return and a resume block the entry's dispatch branches to by `pc`; `launch_run` in `e.gpu` schedules a workgroup round by round until every invocation returned, and an invocation that returned before a barrier its peers reached, or reached another one, traps as `barrier` naming both (`link/gpu_barrier`, `link/gpu_divergence`). A kernel's `shared var`s are one block per launch handed to every step, 0xCD-filled per workgroup (D781)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the occurrence count of a barrier in a loop (only the static barrier is compared)
- [ ] a barrier inside a helper a kernel calls or inside a `for` (its counters are not frame slots), per-invocation frames over 1 KB, subgroups, `--subgroup-width`, frame reuse across launches

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D778` — M3 opens with `e.gpu` on the CPU backend and `gpu.launch` as the third pack intrinsic (`docs/decisions.md:14678`)
- `D780` — The CPU build of a kernel is a resumable step; `gpu.barrier()` is its cut (`docs/decisions.md:14766`)
- `D781` — `shared var` on the CPU backend: the workgroup's block, addressed in the entry (`docs/decisions.md:14822`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `.Cpu`: `lib/e/gpu.e`×6
- `gpu.gid`: `lib/e/gpu/tensor.e`×18, `lib/e/gpu.e`×1, `src/check.e`×1‡
- `FieldAddress`: `src/lower.e`×35‡, `src/codegen_x64.e`×4‡, `src/nir.e`×3†, `scripts/algos/decisions-pending.md`×1†, `src/em.e`×1‡
- `Stack`: `src/lower.e`×35‡, `lib/e/ui/undo.e`×21, `lib/e/data/stack.e`×11, `lib/e/concurrent/stack.e`×10, `src/codegen_x64.e`×9‡, `lib/e/data/window.e`×7, `lib/e/ui/widget.e`×7‡, `src/regalloc.e`×7
- `gpu.barrier`: `src/check.e`×5‡, `lib/e/gpu.e`×1, `src/lower.e`×1‡
- `launch_run`: `lib/e/gpu.e`×3, `src/lower.e`×3‡
- `e.gpu`: `src/check.e`×6‡, `src/lower.e`×5‡, `lib/e/gfx/scene.e`×2†, `src/resolve.e`×2†, `lib/e/gpu.e`×1, `lib/e/gpu/tensor.e`×1, `lib/e/ui/app.e`×1†, `lib/e/ui/testing.e`×1

## Existing fixtures

- `tests/selfhost/fixtures/link/gpu_barrier`
- `tests/selfhost/fixtures/link/gpu_divergence`

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
