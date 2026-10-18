# C169 — NeperOS Blocks remainder: fast fall, held keys and drags, score board, sound

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.95 of 1 |
| queue position | 64 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C139 (D2428): Blocks has hold, ghost, kicks and a saved best score. Acceptance: (1) a finer timer (C163) so the fall reaches 20 rows a second at high levels, and auto-repeat on held buttons plus drags and swipes (the touch layer needs press, move and release events); (2) a score board of the best games and the last game kept in storage; (3) sound effects and music through e.audio (C166); (4) a fixture that plays a scripted sequence with the fixed seed and checks the score and the lines; the name stays Blocks (never Tetris). PART (D2445): the score board (five best games and the last game in /blocks, game-over card, fixtures blocks_board and blocks_board_again). Remaining: the finer timer, held keys and drags, sound, the scripted-sequence fixture. PART (D4016): blocks, blocks_kept(_again), blocks_board(_again), blocks_script (score 286), blocks_drag, blocks_swipe, blocks_hold pass; Fall: manual restarts with the fixed seed, held keys repeat from the end of a frame. Missing: sound.

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
