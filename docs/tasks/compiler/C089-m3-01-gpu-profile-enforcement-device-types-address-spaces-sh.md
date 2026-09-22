# C089 — M3-01: @gpu profile enforcement, device types, address spaces, shared var

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.45 of 1 |
| queue position | 22 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The `@gpu(X, Y, Z)` attribute is read at signature collection: one to three positive integer literals with a product of at most 1024, on a non-extern function, refused otherwise under one diagnostic; a kernel called anywhere but `gpu.launch` is refused at the call (D778). `shared var name: T` is a statement directly in a kernel's body with a device storage type and no initialiser, refused elsewhere, with an initialiser, or with a pointer, slice, string, bool or function type; on the CPU build its storage is the workgroup's block, one per launch, addressed in the kernel's entry block and filled with 0xCD before every workgroup (D781; `link/gpu_shared`). `[]shared T` and `*shared T` parse and are erased on the CPU build, as section 10 says they are

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the call-chain profile check inside a kernel (a helper reached from a kernel is not yet device-only)
- [ ] the device storage type rule in full (`usize` and `union` in buffers), private-memory pointer refusal
- [ ] the shared total in the Interface entry, `caps(...)` and `ftz`

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D778` — M3 opens with `e.gpu` on the CPU backend and `gpu.launch` as the third pack intrinsic (`docs/decisions.md:14678`)
- `D781` — `shared var` on the CPU backend: the workgroup's block, addressed in the entry (`docs/decisions.md:14822`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `gpu.launch`: `lib/e/gpu/tensor.e`×12, `src/check.e`×10‡, `lib/e/gpu.e`×3†, `scripts/algos/decisions-pending.md`×1†, `src/lower.e`×1‡, `src/main.e`×1‡

## Existing fixtures

- `tests/selfhost/fixtures/link/gpu_shared`

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
