# C154 — NeperOS Wallet remainder: encrypted storage, MRZ from an image, editing, camera scanning

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.85 of 1 |
| queue position | 49 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C121 (D2402): Wallet draws real QR and Code 128 symbols, validates its form with e.valid, and shows the newest Camera scan on a document. Acceptance: (1) the cards kept encrypted at rest under the Secure vault's master password (the vault module's derive/seal over the filesystem server), with no card number beyond the last four digits unless the user asks, loaded at start and fixture-tested through an encrypted round trip on a disk; (2) editing an existing card or document with the same validation; (3) Camera Scan mode feeding frames to e.barcode.qr_scan and offering the decoded text (a pass, a URL) to Wallet or the browser; (4) a machine-readable zone read from a scanned page (the OCR-B glyphs) and checked by e.valid.mrz_td3; (5) a scan stored with its own document instead of the newest one; (6) expiry checked against the clock. PART (D2447): a card's expiry is checked against the clock (Expired status; fixture wallet). Remaining: encrypted storage under the Secure master password, editing, Camera Scan mode, MRZ from an image, a scan per document. PART (D3807, D3808): cards sealed under the Secure vault key with an unlock screen, edit card for payment/bank/document, scan stored per document; disk chain secure_vault -> secure_vault_more -> secure_vault_again passes (12 records, expiry edited) and camera_scan -> camera_scan_more passes. Missing: Camera scan mode feeding qr_scan, MRZ from an image (no OCR-B recogniser), password prompt when no vault exists. PART (D4810-D4814): Camera Scan reads a QR into /scancode and Wallet adds it as a card (camera_scan, camera_scan_later); master-password create flow when no vault exists (wallet_vault_create, wallet_vault_create_again); save a card code as PNG to Files (wallet_image); MRZ read from a scan (wallet_mrz; mrz_read matches the reference reader exactly; gfx_vision +3 page reads). Remaining: a real OCR-B passport page untested (font unavailable), Camera 186x300 scan sheet too small for MRZ, TD1/TD2 zones, vault password change, opening a QR URL in the Browser.

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
