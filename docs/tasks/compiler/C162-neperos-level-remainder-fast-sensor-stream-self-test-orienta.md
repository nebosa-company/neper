# C162 — NeperOS Level remainder: fast sensor stream, self-test, orientation modes, feedback

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.90 of 1 |
| queue position | 57 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C132 (D2421): Level filters the accelerometer and gyroscope of the sensor service with a complementary filter and keeps its calibration. Acceptance: (1) the sensors read at 50 Hz or better from the sensor server of C161 (the half-second tick of the scripted source is too slow for a real filter); (2) a Kalman filter in the library next to the complementary one, and a self-test on a flat surface that reports the sensor's noise and bias; (3) Level, Angle and an edge mode switched from the real orientation; (4) the readings in degrees, per cent slope and a ratio, and a beep or vibration when level; (5) a fixture feeding a recorded trace and checking the reading to a tenth of a degree. PART (D2444): e.control Kalman filter (kalman_new/start/step) and noise_bias self-test, checked against an independent 2x2-matrix implementation (control_kalman). Remaining: the 50 Hz stream from the sensor server, Level's modes, readings and feedback, a recorded-trace fixture. PART: level, level_stream, level_selftest, level_kept, level_kept_again boot rows pass.

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
