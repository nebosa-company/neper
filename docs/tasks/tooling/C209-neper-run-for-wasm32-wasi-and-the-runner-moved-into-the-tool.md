# C209 — neper run for wasm32-wasi, and the runner moved into the toolchain

| field | value |
|---|---|
| category | tooling / WebAssembly |
| score | 0.85 of 1 |
| queue position | 93 of 94 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5681. Needs nothing. Build: `dispatch` (main.e:14104) also sends `run ... wasm32 wasi ...` to `wasm_command`, which after writing the module runs it with `run_program` as node --no-warnings RUNNER OUT ARGS (node found by walking PATH, node.exe on Windows, as shell.linux.e:118 walks it; NEPER_NODE overrides; neither: E-CLI-9999 `running a wasm32-wasi module needs Node.js: node on PATH, or NEPER_NODE`); `--threads` and `--release` reach the build. scripts/run-wasm.mjs moves to lib/wasm/run-wasm.mjs and `run` finds it under the toolchain root (`own_directory(args[0])`/lib/wasm); every caller (wasm-sweep.sh, check-fixture.sh, wasm-compiler.sh, wasm-bench.sh, the D5651 blocks of run.sh and run.ps1) moves to the new path in the same commit and nothing stays at the old one. Acceptance: (1) from build/windows, and build/linux in WSL, `neper run tests/selfhost/fixtures/link/wasm_basics/src/main.e --target wasm32-wasi` prints the program's output and reports its status; (2) with node off PATH and no NEPER_NODE it prints the diagnostic; (3) wasm_release run with --release and the argument `bounds` reports 134; (4) the D5651 blocks pass with the moved runner, check_suite_parity.py passes, v2 == v3. D5650 saw `neper build --target wasm32-wasi` from a worktree stop at `the program has no main` (toolchain root build/windows): run from the toolchain as the suites do, and fix it here if it is the short form's own bug. Built as D5780: wasm_command runs the module for `run` (find_node, wasm_run), runner and host moved to lib/wasm, callers updated, tests registered in run.sh/run.ps1. Verified on Windows (wasm_basics, wasm_release bounds 134, no-node diagnostic, native run unchanged, v2==v3, sweep 1041/73/22/0, wasm-compiler 8/8)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the same on build/linux in WSL
- [ ] the D5651 blocks run only piecewise (no full suite completes here)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `wasm_command`: `src/main.e`×2‡
- `run_program`: `lib/e/js/interp.e`×3‡, `src/main.e`×3‡
- `own_directory`: `src/main.e`×2‡

## Existing fixtures

- `tests/selfhost/fixtures/link/wasm_basics/src/main.e`

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
