# C150 — NeperOS storage remainder: per-app directories, Share, thumbnails, zip, external storage, large files

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.85 of 1 |
| queue position | 23 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C125 (D2382): the Files app is on the real filesystem with list, create, rename, move, copy, trash, search, recent and select, and hands a file to Document. Acceptance: (1) the capability model: the filesystem server tells its clients apart (badged endpoints from the kernel or a per-app request endpoint) so an app sees only its own directory and what Files shares to it; (2) Share to another app and the Camera, Wallet and Mail apps saving into Files once they exist (C121, C122, C128); (3) a grid view with image thumbnails (PNG/JPEG decode into e.gfx scenes); (4) browse and extract a zip with e.fmt.zip (the disk image seeded by scripts/make_fs_image.py so a fixture has one); (5) external storage: a second block device as a second root through a second filesystem server instance; (6) entries beyond sixteen a directory (files larger than 4 KB: done, D2387). Delivered by C125 and not to redo: everything in D2375-D2382. PART (D2446): zip archives are browsed (entries and sizes) in Document via Files' handover, e.fmt.zip, fixture document_zip. Remaining: extract an entry, per-app directories, Share, thumbnails, external storage. PART (D3806, D3803): Files grid with PNG/JPEG thumbnails and zip extraction of the whole archive into /<name> with zip-slip refusal; QEMU rows files_grid and document_zip_extract pass. Missing: per-app directories (no kernel badging), Share and saving from Camera/Wallet/Mail into Files, external storage, single-entry extract. PART (D4810-D4814): per-app directories (fs endpoint stamped, installed app 100-199 confined under /d<N>, row install_confined), Share sheet from Files (files_share), zip-entry extract (document_zip_entry), external storage as a second filesystem server (files_external). Remaining: per-app quota, sharing from installed apps, browsing into and writing to folders on the external card, Camera/Wallet saving beyond /DCIM, Downloads and /Wallet.

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
