# C140 — NeperOS Secure (C116's remainder): an encrypted store, the clipboard, autofill, biometrics

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 22 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued (2026-10-08). The Secure app (D2235) is the vault's face with real one-time passwords (RFC 6238, checked at start) on sample logins held in memory. Acceptance: (1) the store encrypted at rest: a key from the master password with PBKDF2 or Argon2 (e.crypto.kdf) and an AEAD (e.crypto.aead) per entry, kept in Files' protected directory (C125) with a version and an integrity tag, a wrong password taking constant time, auto-lock on timeout and when the app leaves; (2) add and edit entries for logins and codes, import and export (an encrypted file, and the common authenticator formats), the otpauth:// URI from a QR scan (L137, C122), the SHA-256 and SHA-512 and eight-digit variants of TOTP, and HOTP; (3) a clipboard service with a timed clear, and autofill of a login into the Browser (C129) and other apps through a capability; (4) fingerprint and face unlock (C126 settings) with the master password as the fallback; (5) a password generator with options and a breach check by hash prefix over C117; (6) Wallet's cards and Dynamic's API keys can be kept here; (7) a fixture on QEMU that creates a vault, restarts and checks the entries decrypt, and the RFC 4226 and RFC 6238 vectors. Not queued here: sharing a vault, passkeys.

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
