# C297 — net_ftp: the explicit-TLS session fails its AUTH TLS handshake

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 1 of 225 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Open, and pre-existing: it is the fixture after fmt_encode in the suite, so no run had reached it. net_ftp exits 44 and prints nothing. That code is not the fixture's own -- it reports a spawned server's exit through `if job.failure != 0i32 { os.exit(job.failure) }` -- and the server side returns 44 at `if ftp.auth_tls(&c, config) != ok || !c.secured || !c.protected || c.broken { ret 44i32 }`, so the explicit-TLS session is the one failing: either the AUTH TLS handshake itself errors, or the connection afterwards does not report itself secured and protected as the fixture expects. The plain, PASV-fallback and parser halves of the fixture are not implicated, since it reaches this one. The next step is to know which of those four conditions holds, by reporting them separately. Acceptance: net_ftp exits 0 and prints net ftp ok, with the FTPS session secured and protected.

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
