# L222 — TLS 1.3 server and client with P-256/RSA credentials, client-certificate auth and PSK session resumption

| field | value |
|---|---|
| category | library / Formats |
| score | 0.00 of 1 |
| queue position | 180 of 192 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened 2026-11-03 from docs/tls-p256-openrouter.md:40 by the single-list audit; not previously a queue row. Acceptance: e.net.tls serves with P-256 and RSA server keys (not only Ed25519), requests and verifies client certificates, and resumes sessions through PSK tickets; 0-RTT stays refused unless replay-safe. Loopback fixtures and an external interop probe cover each mode. Size L. Checked open: docs list client auth, resumption and 0-RTT as unsupported; lib/e/net/tls.e line 1297 'resumes nothing'; validate_server_credentials returns an Ed25519 key only; grep for CertificateRequest/psk finds nothing.

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
