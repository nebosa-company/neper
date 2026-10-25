# C188 — wasm32-wasi sockets, resolution and the poller through neper_host

| field | value |
|---|---|
| category | library / WebAssembly |
| score | 0.00 of 1 |
| queue position | 95 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5675, D5676. Needs nothing: works in the plain build (C186/C187 not required). Build: src/wasm.e `register_import` accepts the library `neper_host`; os.wasi.e `socket_open`, `socket_set_nonblocking`, `socket_bind`, `socket_local_address`, `socket_listen`, `socket_accept`, `socket_connect`, `socket_send`, `socket_receive`, `socket_send_to`, `socket_receive_from`, `socket_shutdown`, `socket_close`, `socket_resolve`, `send_file` and the seven `poller_*` over D5676's imports (the 32-byte address record written byte by byte, host handles from 0x40000000, errno 26 and 7 as WouldBlock, `native_code` the WASI errno, ENOSYS as Unsupported); e.net `map_error_with_code` and `already_connected` gain `when target.os == .Wasi` arms (14 Refused, 15 Reset, 23 and 40 Unreachable, 73 Timeout, 3 AddressInUse; 30 already connected). scripts/run-wasm.mjs: `neper_host` import shims in the module's Worker that copy through a 64 KiB data SAB beside the mailbox and block in Atomics.wait (D5675), and the host on Node's main thread over node:net, node:dgram and node:dns with D5676's semantics (pauseOnConnect listener queue, nonblocking connect EINPROGRESS then EALREADY then EISCONN or the error once, 1 MiB send and receive marks, level-triggered poller, latched wake answering count 0). Acceptance: (1) os_socket, os_resolve, async_io, macos_poller_loss and net pass in the plain `scripts/wasm-sweep.sh` on Windows Node 24 and on WSL Node 22. (2) A module that reaches no socket function imports nothing from neper_host (wasm_basics byte-identical), and the plain sweep gains no failure. (3) Recorded here: the round trip of a 64-byte loopback echo from a module (D5670 measured 53-66 us from JS). The net_* fixtures that start threads are C189

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `register_import`: `src/wasm.e`×2
- `socket_open`: `lib/e/net.e`×4, `lib/e/os.windows.e`×4‡, `lib/e/os.linux.e`×2‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†, `lib/e/os/shell.macos.e`×1†, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×1
- `socket_set_nonblocking`: `lib/e/net.e`×10, `lib/e/async/io.e`×2, `lib/e/os.windows.e`×2‡, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×2, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†
- `socket_bind`: `lib/e/os.windows.e`×4‡, `lib/e/net.e`×2, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×2, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×2, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†
- `socket_local_address`: `scripts/gen_tftp_test.py`×7, `lib/e/os.windows.e`×2‡, `scripts/socks_fixture_head.e`×2, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†, `scripts/gen_sp_test.py`×1
- `socket_listen`: `lib/e/os.windows.e`×3‡, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×2, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×2, `lib/e/net.e`×1, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†
- `socket_accept`: `lib/e/os.windows.e`×3‡, `lib/e/async/io.e`×1, `lib/e/net.e`×1, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×1
- `socket_connect`: `lib/e/net.e`×3, `lib/e/os.windows.e`×3‡, `lib/e/os.linux.e`×2‡, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×2, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×2, `lib/e/async/io.e`×1, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1
- `socket_send`: `lib/e/os.windows.e`×7‡, `lib/e/os.linux.e`×4‡, `lib/e/net.e`×3, `lib/e/os.macos.e`×2‡, `lib/e/os.neperos.e`×2, `lib/e/os.wasi.e`×2†, `lib/e/os/shell.macos.e`×1†, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×1
- `socket_receive`: `lib/e/os.windows.e`×7‡, `lib/e/net.e`×3, `lib/e/os.linux.e`×3‡, `lib/e/os.macos.e`×2‡, `lib/e/os.neperos.e`×2, `lib/e/os.wasi.e`×2†, `lib/e/os/shell.macos.e`×1†, `scripts/grpccall_socket_client.e`×1
- `socket_send_to`: `lib/e/os.windows.e`×4‡, `lib/e/net.e`×1, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†, `lib/e/os/shell.macos.e`×1†
- `socket_receive_from`: `lib/e/os.windows.e`×4‡, `lib/e/net.e`×1, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†, `lib/e/os/shell.macos.e`×1†
- `socket_shutdown`: `lib/e/os.windows.e`×3‡, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×2, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×2, `lib/e/net.e`×1, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†
- `socket_close`: `lib/e/os.windows.e`×10‡, `lib/e/net.e`×9, `lib/e/os.linux.e`×6‡, `lib/e/os/shell.macos.e`×3†, `lib/e/os.macos.e`×2‡, `lib/e/os.neperos.e`×2, `lib/e/os.wasi.e`×2†, `scripts/grpccall_socket_client.e`×2
- `socket_resolve`: `lib/e/net.e`×2, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†, `lib/e/os.windows.e`×1‡
- `send_file`: `scripts/algos/decisions-pending.md`×2†, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†, `lib/e/os.windows.e`×1‡, `scripts/algos/batch46.json`×1
- `native_code`: `lib/e/io.e`×12, `lib/e/os.neperos.e`×10, `lib/e/os.linux.e`×4‡, `lib/e/os.macos.e`×4‡, `lib/e/os.windows.e`×4‡, `lib/e/net.e`×3, `lib/e/os.wasi.e`×2†, `lib/e/fs.e`×1
- `map_error_with_code`: `lib/e/net.e`×3
- `already_connected`: `lib/e/net.e`×2
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
