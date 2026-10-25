# C186 — wasm32-wasi --threads: the threaded module shape and real atomics

| field | value |
|---|---|
| category | compiler / WebAssembly |
| score | 0.00 of 1 |
| queue position | 93 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5671, D5672 (measurements D5670). Needs nothing; first of C186-C196. Build: `--threads` on `emit-executable FILE ROOT wasm32 wasi OUT` (read where `--release` is, D5650; `short_form` forwards it for `neper build|run --target wasm32-wasi`), passed to `wasm.emit` in its options; without it every module is byte-for-byte today's. Threaded shape: memory imported as `env.memory` (limits flag 0x03, minimum today's page count, maximum 65536) and still exported; every data segment passive, a data count section (id 12) before the code section, and `memory.init`/`data.drop` of each segment at the start of `_start`; `$floor` mutable; a `$tid` i32 global; import `wasi.thread-spawn` (i32)->i32; export `wasi_thread_start` (i32,i32)->() with exactly D5673's body. NIR atomics as the 0xFE i64 forms of D5672's table (natural alignment, B+1/B+4/B+5/B+6), min/max as a cmpxchg loop, `atomic.fence`; plain modules keep D5605. The seven `wasm` pseudo-imports of D5672 (`threads`, `thread.id`, `thread.spawn`, `memory.atomic.wait32`, `memory.atomic.notify`, `i32.atomic.rmw.cmpxchg`, `i32.atomic.load`/`store`) in `inline_operation`, with their plain-module forms. Runner, until C187: scripts/run-wasm.mjs gives a module that imports `env.memory` a shared memory (initial from its import section's limits), runs it on one thread with node:wasi direct, and answers `thread-spawn` with -1. `scripts/wasm-sweep.sh --threads` and `scripts/check-fixture.sh NAME --target wasm32-wasi --threads` pass the flag to the wasm build only. Acceptance: (1) the plain module of every link fixture is byte-identical to the one the compiler before C186 writes (a cmp over both compilers' sweep output directories), `scripts/wasm-compiler.sh` at its default set is all identical, and v2 == v3. (2) New fixture `link/wasm_atomics`: load, store, add, sub, and, or, xor, xchg, min and max (signed and unsigned) and cas (success and failure) at 8, 16, 32 and 64 bits, and a fence; the same stdout on x64, wasm32-wasi plain and wasm32-wasi --threads. (3) `wasm-tools validate` passes on the --threads modules of wasm_basics and wasm_atomics, and `wasm-tools print` shows `(import "env" "memory" (memory N 65536 shared))`, passive data and the `wasi_thread_start` export. (4) `scripts/wasm-sweep.sh --threads -j 4` passes exactly the set the plain sweep passes (both counts recorded here). (5) The D5651 suite block passes unchanged

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `short_form`: `src/main.e`×4‡
- `wasm.emit`: `src/main.e`×1‡
- `_start`: `tests/conformance/parse/every_kind.expected.jsonl`×379‡, `tests/conformance/tokens/every_kind.expected.jsonl`×378‡, `src/check.e`×347‡, `src/tool.e`×218‡, `src/lower.e`×212‡, `src/parse.e`×164†, `src/main.e`×136‡, `src/em.e`×97‡
- `atomic.fence`: `lib/e/concurrent/deque.e`×2, `lib/e/thread/pool.e`×2
- `thread.spawn`: `scripts/gen_tftp_test.py`×7, `lib/e/thread/pool.e`×2, `scripts/gen_sp_test.py`×2, `scripts/gen_zmtp_test.py`×2, `lib/e/js/interp.e`×1‡, `lib/e/js/realm.e`×1†, `lib/e/task.e`×1, `scripts/gen_poll_test.py`×1
- `inline_operation`: `src/wasm.e`×2
- `scripts/wasm-compiler.sh`: `scripts/wasm-compiler.sh`×3

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
