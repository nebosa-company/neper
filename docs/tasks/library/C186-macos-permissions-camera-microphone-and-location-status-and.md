# C186 — macOS permissions: camera, microphone and location status and request

| field | value |
|---|---|
| category | library / macOS |
| score | 0.60 of 1 |
| queue position | 4 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Built 2026-10-25 (D5218): permission_status reads AVCaptureDevice authorizationStatusForMediaType (camera, microphone) and CLLocationManager authorizationStatus (location); a status that is not decided or is restricted is Unavailable because shell.Permission has no not-determined state. permission_request asks for the camera and microphone through AVCaptureDevice requestAccessForMediaType with a global Objective-C block (isa from dlsym _NSConcreteGlobalBlock, BLOCK_IS_GLOBAL, an @cc invoke), only when a capture device exists, and waits for the answer (up to five minutes). tests/macos/probe/permissions.e on the runners: camera unavailable, microphone granted, location unavailable, requests return at once, no crash; ui_permissions passes and the corpus is 1105. Open: a location request (CLLocationManager requestWhenInUseAuthorization with a delegate callback on the shell target), a not-determined state in shell.Permission (shared by every host), and a real prompt on a Mac with a camera, which only a person can answer (C192). Done when those three are checked.

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
