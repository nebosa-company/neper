# C170 — NeperOS Secure remainder: HOTP, QR and export, clipboard and autofill, biometrics, breach check

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.70 of 1 |
| queue position | 65 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C140 (D2429): Secure has the encrypted vault, SHA-1/256/512 codes of 6 to 8 digits with their own period, and otpauth import from /otpauth.txt. Acceptance: (1) HOTP entries with a counter that advances on use; (2) the otpauth URI from a QR scan (L137, C122) and an export (an encrypted file and the common authenticator formats); (3) a clipboard service with a timed clear and autofill of a login into the Browser (C129) and other apps through a capability; (4) fingerprint and face unlock (C126 settings) with the master password as the fallback, and auto-lock on timeout; (5) a password generator with options and a breach check by hash prefix over C117; (6) Wallet's cards and Dynamic's API keys kept here; not queued: sharing a vault, passkeys. PART (D2442): HOTP entries (counter kept and sealed, Next moves it), several otpauth URIs imported from /otpauth.txt, fixture secure_import (TOTP SHA-256/8 digits/45 s and HOTP counter 3). Remaining: QR scan and export, breach check, fingerprint/auto-lock, Paste beyond AI (C175). PART (D4100-D4101): QR symbol shown, export and breach check by hash prefix over TLS; secure_export and secure_breach pass; auto-lock in code (no marker in a passing row). Missing: QR scan from the camera, fingerprint/face unlock, clipboard/autofill service, Wallet and API keys kept in Secure. PART (D5100): Secure Scan reads an otpauth QR from a Camera frame (row secure_scan passes). Remaining: fingerprint/face unlock, clipboard/autofill service, Wallet and API keys kept in Secure.

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
