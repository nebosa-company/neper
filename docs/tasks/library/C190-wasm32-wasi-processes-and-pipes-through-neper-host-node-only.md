# C190 — wasm32-wasi processes and pipes through neper_host (Node only)

| field | value |
|---|---|
| category | library / WebAssembly |
| score | 0.00 of 1 |
| queue position | 97 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5677. Needs C188 (the neper_host shims and host loop). Build: in scripts/run-wasm.mjs (lib/wasm/run-wasm.mjs once C194 has moved it) the imports proc_spawn, proc_wait, proc_kill, proc_group_kill, pipe, handle_read, handle_write, handle_close over node:child_process, with guest paths mapped through the runner's preopens and an argv[0] that is a guest path ending in .wasm run as process.execPath, the runner and that module's host path; neper-host.js answers ENOSYS if C191 has landed. os.wasi.e: `neper_os_spawn`, `neper_os_wait`, `spawn_with_options`, `wait_usage` (peak_memory 0), `kill`, `proc_group_spawn/terminate/close`, `pipe`, `pipe_read`; `neper_os_read`, `neper_os_write` and `neper_os_close` route a File whose raw is at least 0x40000000 to handle_read, handle_write and handle_close; `dup` of a host handle answers Unsupported. Acceptance: (1) os_process and os_group pass in `scripts/wasm-sweep.sh` (with --threads if they start threads) on Windows Node 24 and WSL Node 22. (2) os_shell, os_exchange, proc_sys, ui_activation, ui_file_access, ui_lifecycle, ui_notification, ui_permissions, ui_print and ui_shell_ops rerun: each passes or its remaining reason is recorded here (e.os.shell's wasi variant is D5623's and not this item). (3) Neither sweep gains a failure

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `neper_os_spawn`: `src/runtime_elf_a64.e`×2, `src/runtime_elf_a64.s`×2†, `src/runtime_elf_x64.e`×2†, `src/runtime_elf_x64.s`×2†, `src/runtime_macos_a64.e`×2, `src/runtime_macos_a64.s`×2, `src/runtime_macos_x64.e`×2†, `src/runtime_macos_x64.s`×2†
- `neper_os_wait`: `src/em.e`×4‡, `src/lower.e`×4‡, `src/runtime_elf_a64.e`×4, `src/runtime_elf_a64.s`×4†, `src/runtime_elf_x64.e`×4†, `src/runtime_elf_x64.s`×4†, `src/runtime_macos_a64.e`×4, `src/runtime_macos_a64.s`×4
- `spawn_with_options`: `lib/e/os/shell.macos.e`×5†, `lib/e/os/shell.linux.e`×4, `lib/e/proc.e`×2, `src/main.e`×2‡, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†
- `wait_usage`: `lib/e/os/shell.macos.e`×5†, `lib/e/os/shell.linux.e`×4, `lib/e/os.linux.e`×2‡, `lib/e/os.windows.e`×2‡, `src/check.e`×2‡, `src/main.e`×2‡, `benchmarks/metamorphic/rename_symbols.py`×1, `lib/e/os.macos.e`×1‡
- `pipe_read`: `lib/e/os.windows.e`×4‡, `lib/e/proc.e`×2, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†
- `neper_os_read`: `src/runtime_elf_x64.s`×5†, `src/runtime_elf_a64.e`×4, `src/runtime_elf_a64.s`×4†, `src/runtime_elf_x64.e`×4†, `src/runtime_pe_x64.asm`×4†, `src/runtime_pe_x64.e`×4†, `lib/e/os.wasi.e`×2†, `src/em.e`×2‡
- `neper_os_write`: `src/lower.e`×3‡, `lib/e/os.wasi.e`×2†, `src/runtime_elf_a64.e`×2, `src/runtime_elf_a64.s`×2†, `src/runtime_elf_x64.e`×2†, `src/runtime_elf_x64.s`×2†, `src/runtime_macos_a64.e`×2, `src/runtime_macos_a64.s`×2
- `neper_os_close`: `src/runtime_elf_a64.e`×2, `src/runtime_elf_a64.s`×2†, `src/runtime_elf_x64.e`×2†, `src/runtime_elf_x64.s`×2†, `src/runtime_macos_a64.e`×2, `src/runtime_macos_a64.s`×2, `src/runtime_macos_x64.e`×2†, `src/runtime_macos_x64.s`×2†
- `scripts/wasm-sweep.sh`: `scripts/wasm-sweep.sh`×3, `scripts/run-wasm.mjs`×1

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
