# C192 — macOS verification on real hardware: what the CI runners cannot do

| field | value |
|---|---|
| category | library / macOS |
| score | 0.20 of 1 |
| queue position | 10 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The checklist is a program, written 2026-10-25 (D5228) and compiled for both architectures but never run: tests/macos/manual/main.e. Build it on the Mac (neper-self emit-executable tests/macos/manual/main.e . aarch64 macos manual; x64 on an Intel Mac) and run ./manual from a Terminal: it goes through one check at a time, says what to do, waits where a person is needed, and writes PASS, FAIL or skipped lines to ~/neper-manual-results.txt. It covers: the window's Retina scale, a menu-bar icon's left and right click, a pop-up menu choice, a global shortcut press (Control-Option-Shift-F12), the Open panel with two files and the Save panel's name and .txt, a drop from Finder, the clipboard in TextEdit, a notice banner, a Dock menu task and the 50% badge, Finder starting a program for an associated file, the print panel's range and copies, the camera permission, Touch ID where enrolled, the screen capture size, and VoiceOver reading a published tree and pressing its button. Not covered by it (a program cannot drive them): a real pointer drag out of a window into Finder, a notarized bundle opened on a clean Mac (C191), live resize while dragging an edge and IME composition (C190), a Metal or MoltenVK device run (C193). Done when it has been run on an Apple-silicon Mac and an Intel Mac and its results are recorded here.

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
