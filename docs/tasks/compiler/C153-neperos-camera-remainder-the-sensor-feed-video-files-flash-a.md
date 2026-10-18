# C153 — NeperOS Camera remainder: the sensor feed, video files, flash and exposure hardware, the QR reader

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 48 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C122 (D2397): the Camera writes photos and straightened scans as PNG files in /DCIM that Photos lists, with focus ring, exposure steps and a timer. Acceptance: (1) a camera driver server (virtio-video or USB video under QEMU, the Pixel camera later) delivering frames to the viewfinder at a steady rate, front and rear chosen from the devices found; (2) video recording with a codec from the library and audio from e.audio, written as a file Photos plays; (3) focus, exposure, flash and HDR stacking as far as the hardware has them; (4) Scan mode's QR reading (L137) opening the code's content, and a scan offered to Wallet documents (C121); (5) a fixture on QEMU against a test video source. Not queued here: portrait blur, night mode, RAW capture.

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
