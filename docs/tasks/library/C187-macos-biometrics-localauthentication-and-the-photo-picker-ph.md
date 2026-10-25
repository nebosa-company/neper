# C187 — macOS biometrics (LocalAuthentication) and the photo picker (PHPicker)

| field | value |
|---|---|
| category | library / macOS |
| score | 0.50 of 1 |
| queue position | 5 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Built 2026-10-25 (D5220): biometrics through LocalAuthentication, capabilities().biometrics is LAContext canEvaluatePolicy for Touch ID asked at every call (true only where enrolled), permission_status(Biometric) is Granted there, and biometric_verify shows the system sheet through evaluatePolicy:localizedReason:reply: with a hand-built global block and waits up to a minute; without biometrics it answers Unsupported. The photo picker is the open panel narrowed to image extensions (png, jpg, jpeg, gif, heic, tiff, bmp, webp), several files on request; PHPicker (the Photos library) is a SwiftUI view this library cannot present. ui_permissions now follows what the host offers (the fixture used to require biometrics to be off everywhere). tests/macos/probe/biometrics_photos.e on the runners: no biometrics, verify is Unsupported, the picker is shown and dismissed (Cancelled); the corpus is 1105. Open: a real Touch ID sheet and a confirmed photo selection need a person and a Mac with Touch ID (C192); Photos-library access (PHPicker) is not done. Done when those are checked.

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
