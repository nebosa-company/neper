# C195 — macOS shell polish: drag files and images out, session restore, Dock overlay image

| field | value |
|---|---|
| category | library / macOS |
| score | 0.70 of 1 |
| queue position | 13 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Built 2026-10-25 (D5226): drag_start now drags files (each path as an NSURL file URL, one dragging item per file, up to 16) and images (TIFF data under public.tiff) as well as text and bytes; taskbar_overlay draws the overlay into the lower right quarter of the program's own Dock icon (the first icon is kept so a second overlay replaces the first, and a picture with no area puts the system's back). tests/macos/probe/polish.e on the runners: the overlay is seen in the Dock screenshot over the folder icon, replaced and cleared without error, and a drag of two files and an image out of a window ends Cancelled when a mouse up is posted, on aarch64 and x64; ui_drag_drop and ui_taskbar pass and the corpus is 1108. Not done: session restore (restart_register) stays Unsupported, because a launchd job with KeepAlive starts at once and a Mac restores a program's windows through the system's own saved state, which is not a command line to register; promised files (a file made at the drop's destination) and a real pointer drag with the files landing in Finder (C192).

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
