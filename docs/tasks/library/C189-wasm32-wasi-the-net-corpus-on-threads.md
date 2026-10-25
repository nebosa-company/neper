# C189 — wasm32-wasi: the net_* corpus on --threads

| field | value |
|---|---|
| category | library / WebAssembly |
| score | 0.00 of 1 |
| queue position | 96 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5676 (its in-scope list). Needs C187 and C188. Build: whatever these fixtures show missing in the host's socket emulation or in os.wasi.e, inside D5676's table; a call the table lacks (a socket option, multicast) gets a decision row of its own before it is added. Acceptance: (1) in `scripts/wasm-sweep.sh --threads`, net_http, net_http_pool, net_tls, net_ftp, net_grpctls, net_imap, net_ldap, net_mdns, net_pop3, net_smtp, net_socks, net_sp, net_tftp and net_zmtp pass on Windows Node 24 and WSL Node 22; one that cannot is recorded here with its reason and the row that would add what it needs. (2) The full --threads sweep passes everything the plain sweep passes. (3) Five consecutive runs of the passing net set without a failure (timing races in the host's emulation)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

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
