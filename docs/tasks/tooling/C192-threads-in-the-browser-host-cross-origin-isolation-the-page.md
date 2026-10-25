# C192 — Threads in the browser host: cross-origin isolation, the page as host

| field | value |
|---|---|
| category | tooling / WebAssembly |
| score | 0.00 of 1 |
| queue position | 99 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5679 (on D5674's protocol). Needs C187 and C191. Build: neper-host.js for a module importing env.memory: rejects with one sentence when crossOriginIsolated is false; the calling thread (the page's main thread; under Node the importing thread) is the host, owning the in-memory file system and WASI over the shared memory; every thread a Worker whose WASI imports are mailbox proxies (D5674's 128-byte layout), answered through Atomics.waitAsync or, where it is missing, postMessage; thread-spawn a host call that reuses or makes Workers (measured: a Worker made by a blocked Worker never starts in Chrome, D5670); the end as D5674. A plain module keeps its file system inside its one Worker. Acceptance: (1) wasm_threads and the fifteen thread fixtures of C187's acceptance pass through neper-host.js under Node 24 (`wasm-sweep.sh --host neper-host --threads`). (2) Browser pane, page served with --isolated: wasm_threads gives exit 0 and the native stdout; served without --isolated the page reports the isolation sentence; both recorded here. (3) C191's acceptance still holds for plain modules

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
