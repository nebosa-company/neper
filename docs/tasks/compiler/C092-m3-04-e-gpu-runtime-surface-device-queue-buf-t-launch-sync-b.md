# C092 — M3-04: e.gpu runtime surface: Device, Queue, Buf[T], launch, sync, barrier

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.80 of 1 |
| queue position | 24 of 48 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `e.gpu` at `surface: partial`: `open`/`close`/`has`/`info`, `queue` and `queue_with`, `Buf[T]` as a generation-checked handle into a per-device table, `alloc`/`upload`/`write`/`download`/`release`/`len`, tokens with `done`/`wait`/`wait_for`, `sync`, `grid1/2/3`, and `gpu.launch[K]` as the third argument-pack intrinsic: the pack is checked against the kernel's parameters (`Buf[T]` for a device slice, a value of the parameter's type otherwise) and expands into a generated launcher per calling module, kernel and argument shape (D778). `gpu.barrier()` is the third device intrinsic recognised, legal only in a kernel's own body, lowered as the cut of the CPU build (D780). The fault buffer (D785): a failed tag, alignment, null, enum or bounds check in a kernel's CPU build writes the queue's one `FaultRecord` and ends the invocation, `sync`/`download` answer `Fault` once, `last_fault` answers the record. Presentation (D791): `Image`, `open_target`, `acquire`, `present`, `presented`, `resize` and `close_target`, offscreen on the CPU device

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] `[]Atomic[T]` parameters, `gpu.memory_barrier`, staging pools that do anything
- [ ] a lock on the device block

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D778` — M3 opens with `e.gpu` on the CPU backend and `gpu.launch` as the third pack intrinsic (`docs/decisions.md:14678`)
- `D780` — The CPU build of a kernel is a resumable step; `gpu.barrier()` is its cut (`docs/decisions.md:14766`)
- `D785` — The fault buffer and `gpu.Fault` on the CPU backend (`docs/decisions.md:14898`)
- `D791` — Presentation is images, targets and frames over kernels; `gpu-presentation-api` delivered (`docs/decisions.md:15039`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `e.gpu`: `src/check.e`×6‡, `src/lower.e`×5‡, `lib/e/gfx/scene.e`×2‡, `lib/e/gpu.e`×2†, `scripts/algos/batch45.json`×2, `scripts/algos/decisions-pending.md`×2†, `src/resolve.e`×2†, `lib/e/gpu/tensor.e`×1
- `queue_with`: `lib/e/gpu.e`×2†
- `upload`: `lib/e/ui/asset.e`×8, `lib/e/gpu/tensor.e`×7, `lib/e/gpu.e`×2†, `lib/e/fmt/brotli.e`×1‡, `lib/e/gfx/image.e`×1, `lib/e/gfx/scene.e`×1‡
- `download`: `lib/e/gpu.e`×5†, `lib/e/gpu/tensor.e`×3, `lib/e/fmt/brotli.e`×1‡
- `wait_for`: `lib/e/dist/deadlock.e`×5, `lib/e/task.e`×4, `lib/e/os.windows.e`×3‡, `lib/e/sync.e`×3, `lib/e/concurrent/queue.e`×2, `lib/e/db/storage.e`×1†, `lib/e/gpu.e`×1†, `scripts/algos/batch28.json`×1
- `gpu.barrier`: `src/check.e`×5‡, `lib/e/gpu.e`×1†, `src/lower.e`×1‡
- `FaultRecord`: `lib/e/gpu.e`×4†
- `Fault`: `lib/e/test/support.e`×18, `lib/e/gpu.e`×12†, `lib/e/os.windows.e`×7‡, `lib/e/os.linux.e`×5‡, `src/main.e`×3‡, `lib/e/resilience.e`×1, `src/lower.e`×1‡
- `last_fault`: `lib/e/gpu.e`×3†
- `Image`: `lib/e/gfx/scene.e`×20‡, `lib/e/gfx/image.e`×19, `lib/e/ui/widget.e`×11‡, `lib/e/gpu.e`×9†, `scripts/build-docs-pdf.py`×7, `lib/e/fmt/png.e`×6, `lib/e/ui/control.e`×6‡, `lib/e/fmt/webp.e`×5†
- `open_target`: `lib/e/ui/window.e`×2, `lib/e/gpu.e`×1†, `lib/e/ui/testing.e`×1
- `presented`: `lib/e/fmt/brotli.e`×4‡, `lib/e/gpu.e`×4†, `lib/e/ui/testing.e`×2, `lib/e/ui/window.e`×2, `lib/e/gfx/scene.e`×1‡, `lib/e/os.linux.e`×1‡, `lib/e/os.windows.e`×1‡, `lib/e/ui/app.e`×1†
- `resize`: `lib/e/ui/collection.e`×18†, `lib/e/ui/window.e`×2, `lib/e/fmt/brotli.e`×1‡, `lib/e/gfx/scene.e`×1‡, `lib/e/gpu.e`×1†, `lib/e/os.linux.e`×1‡, `lib/e/ui/app.e`×1†, `lib/e/ui/navigation.e`×1†

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
