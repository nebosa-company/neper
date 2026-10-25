# C191 — A browser host for wasm32-wasi modules: lib/wasm/neper-host.js

| field | value |
|---|---|
| category | tooling / WebAssembly |
| score | 0.00 of 1 |
| queue position | 98 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5678. Needs nothing (plain modules). Build: lib/wasm/neper-host.js, one ES module with no build step and no dependency: `run(source, {args, env, files, stdout, stderr})` resolving to `{exitCode, files}`; the module always in a dedicated module Worker made from import.meta.url (node:worker_threads under Node); WASI preview 1 in JS for exactly the 24 functions os.wasi.e imports, answering as uvwasi does, over an in-memory tree preopened as fd 3 `.`, 4 `/exe` (the module as /exe/NAME.wasm, args[0]), 5 `/tmp`, 6 `/home`; realtime and monotonic clocks in ns; random_get in pieces of 65,536 bytes; proc_exit by a sentinel thrown out of _start; every neper_host import ENOSYS. The CLI form `node lib/wasm/neper-host.js FILE.wasm ARGS`; `scripts/wasm-sweep.sh --host neper-host`; `scripts/serve-wasm.mjs [--isolated] [--port N]` (127.0.0.1, read-only, COOP same-origin and COEP require-corp under --isolated); `tests/wasm/browser/index.html?module=URL&args=A,B` setting window.neperResult = {exitCode, stdout, stderr}. Acceptance: (1) wasm_basics, wasm_ops, wasm_flow, wasm_reserve, fs_basics, os_clock_random and os_environment pass through neper-host.js under Node 24 and Node 22 (`wasm-sweep.sh --host neper-host`: the native stdout and status). (2) The full sweep through neper-host.js: counts recorded next to run-wasm.mjs's, and each fixture that passes under run-wasm.mjs but not here listed with its reason. (3) Browser pane (preview_start on serve-wasm.mjs, javascript_exec reading window.neperResult): the modules of wasm_basics and fs_basics give exit 0 and the native stdout, on a plain page and on an --isolated one; recorded here (D5670's probe ran v2.exe's module in a Worker under a 60-line shim, so the route is known to work). (4) No browser runs in the suites

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
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
