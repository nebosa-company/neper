# C280 — a window whose present fails still reports itself presenting

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 1 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Open. ui_window reaches its failing-presenter section and exits 34. Splitting that assertion shows the failing part is window.presenting: after the presenter under test refuses a frame, the window still answers that it is presenting (exit 341), so the release and the cleared slot the fixture then checks were never reached. The path to look at is request_frame in lib/e/ui/window.e: it returns early when gpu.native(s.frames) holds and again when gpu.presented(s.frames) errors, and in both of those it sets frame_requested without touching has_presenter; present_whole does clear has_presenter and release the presenter, but only if it gets that far, and it returns before the presenter is called when gpu.read_image fails. Whether the cpu target used here takes the native early return is the first thing to establish. Reached only now: this fixture could not compile before the queue migration below, so no run had exercised it since window.open grew its queue parameter. Acceptance: after a failed present the window answers that it is not presenting, the presenter has been released exactly once, and its slot is clear; ui_window exits 0.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

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
