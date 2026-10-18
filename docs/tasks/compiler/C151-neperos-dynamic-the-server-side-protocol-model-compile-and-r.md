# C151 — NeperOS Dynamic, the server side: protocol, model, compile-and-repair, signing, many installed apps

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.50 of 1 |
| queue position | 24 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C124 (D2388): the device can verify, install, keep, ask about and launch a signed package and refuses what it did not declare. Acceptance: (1) the protocol over C117's TLS: a request carries the prompt, the app's identity and the device's API level; the answer carries the package (manifest, image, source, signature), streamed into the filesystem (a GET larger than httpc.e's 96 KB, with a request body); (2) a local test server with a canned model answer (no live model in the suite) that goes prompt to installed icon to launch to extension, as an installfixture; (3) the Dynamic app (D2238) calling it in place of its three templates and showing the stages from the server's progress; (4) the compile step on the server (the Neper compiler against the app kit, diagnostics fed back to the model until it builds or gives up readably), the scan before signing, a reproducible build, signing and revocation, an audit log; (5) many installed apps (the shell's single slot becomes a list from /apps), removal, update and rollback, and the manifest icon on the grid; (6) the NIR walk of the scanner (raw syscalls, undeclared capabilities, unbounded loops over input), with its report on the Details screen. Delivered by C124 and not to redo: D2383-D2388. PART (D4108): the build server streams stages, the 430 KB package is fetched without the httpc limit, checked and kept in /apps (dynamic_server); a restart adopts it and launches it (dynamic_server_again). Missing: many installed apps, update/rollback, removal, a live model. PART (D5103): many apps, update/rollback and removal pass. Remaining: live model, a fourth icon, the NIR scanner.

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
