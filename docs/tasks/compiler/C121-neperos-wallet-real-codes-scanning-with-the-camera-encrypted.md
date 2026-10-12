# C121 — NeperOS Wallet: real codes, scanning with the Camera, encrypted storage, more validators

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 6 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by the user (2026-10-08). The Wallet app (D2216) holds payment cards, tickets, certificates, loyalty and transit cards, bank accounts and documents (a passport, a visa, a driving license, birth, marriage, address and tax certificates, a social security card, notary acts, employment contracts, non-disclosure agreements, vehicle registrations) on sample data. Acceptance: (1) real QR and barcode encoding and decoding in the library (L137 has QR; add Code 128 and EAN/UPC from e.valid's families) so a ticket or pass shows a code that scans and the Camera can read one; (2) document scanning: the Camera app (not yet written) takes a page, e.gfx.vision straightens and crops it, and the page is kept with the document and shown full screen; (3) the cards kept encrypted at rest in Secure (C116) behind the master password, with no card number kept beyond the last four digits unless the user asks; (4) validators stay in the library, not the app: e.valid gained card_brand (D2216); the rest of the identifier checksum suite (L030: LEI, ISIN, VIN, Verhoeff, BIC) and an expiry check join it; (5) a machine-readable zone reader for passports and driving-license barcodes; (6) add and edit a document or a bank account with full validation messages; (7) a fixture on QEMU for add, edit, remove and the encrypted round trip. Not queued here: tap-to-pay, issuer provisioning, government verification of a certificate.

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
