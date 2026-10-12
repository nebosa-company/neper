# C125 — NeperOS Files: real storage through the filesystem server, file hand-over between apps

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 2 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by the user (2026-10-08). The Files app (D2219) browses a sample tree kept in the process. Acceptance: (1) the tree is the real one behind fs_server.e (a virtio-blk disk or the Pixel's storage later): list, create, rename, move, copy, delete (with a trash that empties after thirty days), file sizes and times from the filesystem, and the storage summary from the real free space and the real mix of types; (2) the capability model: an app sees only its own directory and what the user shares to it through Files; the Files app is the one that holds the whole tree; (3) hand-over: Open sends the file to the app for its type (Document C123, Photos, a media player) and Share sends it to another app; the Camera (C122), Wallet (C121) and Mail save into it; (4) search by name and by type, recent files, multi-select with copy, move and delete, a grid view with thumbnails for images (reusing e.gfx scene clipping); (5) archives: browse and extract a zip; (6) external storage: a USB disk or SD card appears as a second root; (7) a fixture on QEMU that creates, renames and deletes on a real disk image and checks the bytes after a reboot. Not queued here: cloud drives, sync, encryption of folders (Secure's job).

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
