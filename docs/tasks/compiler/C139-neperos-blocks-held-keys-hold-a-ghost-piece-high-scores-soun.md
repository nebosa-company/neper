# C139 — NeperOS Blocks: held keys, hold, a ghost piece, high scores, sound

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 21 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued (2026-10-08). The Blocks app (D2234, called Lunatris until D2241) plays a falling-blocks game on tap buttons with the piece falling on the 500 ms tick. Acceptance: (1) a finer timer (C133) so the fall can reach 20 rows a second at high levels, and auto-repeat on held buttons (the touch layer needs press and release events, not only taps); (2) a hold piece, a ghost piece showing where the piece will land, the standard wall kicks (a 7-bag is already used); (3) high scores and the last game kept in storage (C125), with a score board; (4) sound effects and music through e.audio; (5) swipe and tap gestures (drag the piece, swipe down to drop) once the touch layer carries drags; (6) the name: the game is called Blocks (renamed from Lunatris by the user, D2241); it must not be called Tetris, a registered trademark; (7) a fixture that plays a scripted sequence with a fixed seed and checks the score and the lines. Not queued here: multiplayer, other modes.

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
