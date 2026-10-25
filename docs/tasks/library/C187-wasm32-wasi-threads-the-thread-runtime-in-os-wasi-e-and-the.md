# C187 — wasm32-wasi threads: the thread runtime in os.wasi.e and the Node thread host

| field | value |
|---|---|
| category | library / WebAssembly |
| score | 0.00 of 1 |
| queue position | 94 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5673, D5674. Needs C186. Build, os.wasi.e: the D5672 pseudo-imports declared; `neper_os_thread_create/join/detach` over D5673's 64-byte thread block (state, tid, entry slot, context, stack top, floor, size, link), its free list and `rt_lock` (Drepper's mutex over wasm_cas32/wait32/store32/notify); reserve and release under the lock; `wait_u32`/`wake_one_u32`/`wake_all_u32` over wait32/notify when `wasm_threads()` is 1 (0 and 1 ok, 2 Timeout); `current_thread_id` = thread.id + 1; `last_error_detail` as os.linux.e's 64 thread-keyed slots; mounts loaded in `neper_start_args`; `rt_grow` loops. Plain modules answer as before (thread_create Unsupported, futex returns at once). Build, scripts/run-wasm.mjs for a module importing `env.memory`: Node's main thread is the host and owns the shared memory and one node:wasi bound by `wasi.start({exports: {memory, _start() {}}})` with D5620's readdir shim; every thread, the first too, a Worker whose wasi_snapshot_preview1 imports are mailbox proxies (128-byte SAB per thread, D5674's layout; the host answers with Atomics.waitAsync); `thread-spawn` a host call that reuses an idle Worker or makes one, tids from 1, -6 past 0x1FFFFFFF; idle Workers unref'd; `proc_exit`, an engine error or a RangeError in any thread ends the run, terminates the rest and sets process.exitCode (never process.exit); stackSizeMb 256 for the first thread, 64 for others. New fixture `link/wasm_threads` with D5674's list; the D5651 blocks of run.sh and run.ps1 gain it built with --threads. Acceptance: (1) wasm_threads passes on x64 and on wasm32-wasi --threads under Windows Node 24 and WSL Node 22, ten runs in a row on each. (2) In `scripts/wasm-sweep.sh --threads`: thread_spawn, thread_pool, thread_group, thread_perturb, sync_guard, sync_rwguard, sync_dataguard, sync_flight, os_futex, os_exit_threads, concurrent_deque_stack, concurrent_queue_map, cancel, mediator and task_pool pass; test_poll, thread_fiber, gpu_device_lock, js_generator_shutdown, runtime_gaps, cli_config and error_detail each pass or have their remaining non-thread reason recorded here. (3) The full --threads sweep passes everything the plain sweep passes, and the plain sweep gains no failure. (4) wasm_threads' 200 spawn-and-join cycles take under a second (pooled Workers; a new Worker per thread measured 33-46 ms, D5670). Opus: bringing threads up under some twenty fixtures means hunting hangs and races in a runtime and a host at once, the class where C184 needed Opus (D5670)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `wait_u32`: `lib/e/sync.e`×19, `src/runtime_pe_x64.asm`×14†, `src/runtime_macos_x64.s`×13†, `src/runtime_macos_a64.s`×12, `src/runtime_elf_a64.s`×3†, `src/runtime_elf_x64.s`×3†, `src/runtime_neperos_a64.s`×3, `src/em.e`×2‡
- `wake_one_u32`: `lib/e/sync.e`×3, `src/runtime_elf_a64.e`×2, `src/runtime_elf_a64.s`×2†, `src/runtime_elf_x64.e`×2†, `src/runtime_elf_x64.s`×2†, `src/runtime_macos_a64.e`×2, `src/runtime_macos_a64.s`×2, `src/runtime_macos_x64.e`×2†
- `wake_all_u32`: `lib/e/sync.e`×9, `src/runtime_elf_a64.e`×2, `src/runtime_elf_a64.s`×2†, `src/runtime_elf_x64.e`×2†, `src/runtime_elf_x64.s`×2†, `src/runtime_macos_a64.e`×2, `src/runtime_macos_a64.s`×2, `src/runtime_macos_x64.e`×2†
- `current_thread_id`: `lib/e/os.linux.e`×6‡, `lib/e/os.windows.e`×5‡, `lib/e/os.macos.e`×4‡, `lib/e/gpu.e`×2†, `lib/e/os.neperos.e`×2, `lib/e/os.wasi.e`×2†, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×2, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×2
- `last_error_detail`: `lib/e/os.linux.e`×15‡, `lib/e/os.wasi.e`×15†, `lib/e/os.windows.e`×14‡, `lib/e/os.macos.e`×12‡, `lib/e/fs.e`×7, `lib/e/proc.e`×5, `lib/e/net.e`×2, `lib/e/os.neperos.e`×1
- `neper_start_args`: `lib/e/os.wasi.e`×3†, `src/runtime_macos_a64.s`×3, `src/runtime_macos_a64.e`×2, `src/runtime_macos_x64.e`×2†, `src/runtime_macos_x64.s`×2†, `src/wasm.e`×2, `src/link_macho.e`×1
- `rt_grow`: `lib/e/os.wasi.e`×3†
- `proc_exit`: `lib/e/os.wasi.e`×4†

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
