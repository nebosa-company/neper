# C122 — NeperOS Camera: a real sensor feed, files in Photos, video, focus and exposure

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 5 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by the user (2026-10-08). The Camera app (D2217) shows drawn sample scenes and keeps captures in the process. Acceptance: (1) a camera driver server (a virtio-video or USB video device under QEMU, the Pixel camera path later) delivering frames to the viewfinder at a steady rate; (2) a photo written as a file (PNG or JPEG through the image library) that the Photos app lists; (3) video recording with a codec from the library and audio from e.audio; (4) tap to focus and exposure, the timer, HDR-style stacking and the flash as far as the hardware has them; (5) Scan mode finds the page edges (e.gfx.vision), straightens it and offers it to Wallet documents (C121) and to a QR reader (L137) that opens the code's content; (6) front and rear cameras chosen from the devices found; (7) a fixture on QEMU against a test video source. Not queued here: portrait blur, night mode, RAW capture.

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
