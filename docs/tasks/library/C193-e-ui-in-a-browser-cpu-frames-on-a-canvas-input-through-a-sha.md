# C193 — e.ui in a browser: CPU frames on a canvas, input through a shared ring

| field | value |
|---|---|
| category | library / WebAssembly |
| score | 0.00 of 1 |
| queue position | 100 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5680. Needs C191; the page must be cross-origin isolated (D5680). Build: neper_host window_open, window_metrics, window_title, window_present, window_poll and window_cursor in neper-host.js (the page's canvas transferred to the module Worker with transferControlToOffscreen, frames by putImageData with the channel order of os.windows.e's present, input as 32-byte os.WindowEvent records in a 256-record SAB ring read by window_poll with Atomics.wait and its timeout); run-wasm.mjs answers ENOSYS to them; os.wasi.e's window functions call them and keep today's answers on ENOSYS. Acceptance: (1) an e.ui program built for wasm32-wasi (a gallery example, or a new tests/wasm/browser/ui_counter with a button and a label) renders in the Browser pane on a page served with --isolated: a screenshot of the first frame, then after a click on the button a screenshot showing the label changed, and typed text reaching a text field; the screenshots kept in the evidence (UI work is shown in screenshots). (2) The Node sweeps and the ui_* fixtures' wasm results are unchanged (the ENOSYS path). (3) On a page that is not isolated, run() with a canvas rejects with one sentence

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

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
