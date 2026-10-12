# C098 — AES-GCM at OpenSSL's speed: AES and carry-less multiply instructions for e.crypto.aead

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.00 of 1 |
| queue position | 53 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> e.crypto.aead's AES-GCM is portable Neper, a bitsliced AES (BearSSL's aes_ct64) and a GHASH from masked integer products (ghash_ctmul64), D1645. Measured 2026-09-28 on the Core i5-12500H, sealing one TLS record: 11.6 us for 100 bytes and 702 us for 16 KB (23 MB/s), against OpenSSL's 0.73 us and 3.19 us (5.1 GB/s, through Python's cryptography 48, whose call overhead is included): 16 times slower on small records and 220 times on large ones. It bounds every TLS user: x.microsoft.tds scans SQL Server at 28-35% of the fastest language (D1643), where OpenSSL, Go and rustls run AES-NI and PCLMULQDQ. Closing the gap needs the back end to emit AESENC/AESENCLAST and PCLMULQDQ (x64) behind a CPU check with the portable path as the fallback, as SHA-256 and CRC-32C already are in the link (D336), then a GCM that keeps its expanded key and H powers across records (e.net.tls expands the key for every record today) and runs four to eight blocks in flight. Until then, the portable path's own lever is codegen: the same bitsliced rounds run at about 130 cycles a byte, several times BearSSL's in C.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D336` — Two hashes in hardware, the warm build's readers, and the link on the workers (`docs/decisions.md:7108`)

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
