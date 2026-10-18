# C163 — NeperOS Flashlight remainder: a finer timer, quick toggles, patterns, torch policy

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.80 of 1 |
| queue position | 58 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C133 (D2422): the Flashlight drives a simulated torch through the settings server. Acceptance: (1) a finer timer (a 10 ms tick or a timer capability in the kernel) so a Morse unit can be 100 ms and a strobe can reach 10 flashes a second, with a speed control; (2) a quick toggle from the status bar and the lock screen; (3) patterns kept as a list the user can add to; (4) the torch turned off when the camera opens (the camera server of C153) and on a timeout, and the flash-mode permission check; (5) a fixture that sends a message and checks the beat times against the unit. PART (D4014): flashlight, flashlight_beats, flashlight_strobe, flashlight_timer, flashlight_kept(_again), lock_torch, camera_torch and the new status_torch (status-bar Torch pill) pass; flashlight_timer flaked once under load.

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
