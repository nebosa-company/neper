# C147 — Full suites complete on this machine: Windows run.ps1 and Linux run.sh

| field | value |
|---|---|
| category | compiler / Validation |
| score | 0.50 of 1 |
| queue position | 28 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C115 (2026-10-08). Neither full suite finishes here: tests/selfhost/run.ps1 trips on PowerShell's Stop preference when a native command writes to stderr, and the Linux run.sh builds with neper build, which crashes the WSL2 VM on this host. Per-feature fixtures have been run by hand on both hosts. Acceptance: (1) run.ps1 runs to its end on this Windows host without manual patching; (2) run.sh runs to its end in WSL, with the memory it needs set down in the script's header and the VM left alive; (3) each reports its last line and the count of checks, and the totals feed docs/test-results.json, the tile on the readiness page. PART (D2313): NEPER_SEED in run.ps1 (the bootstrap cannot build src/main.e under this host's commit), stale assertions fixed, fix_module_surfaces.py, -j 2 for the two huge fixtures; run.ps1 passes stage 1 and about 3,700 lines. PART 2 (D2317): NEPER_JOBS caps default workers from the environment; stale NeperOS and determinism assertions fixed; the seeded Windows run passes to line 9914 of 9937 (stops at the Flashlight timing fixture; sc500k static gate needs >3 GB free commit; network check hits a live API). NOT DONE: a complete run on either host (run.sh under WSL not run) and the test-results.json totals. RUN 17 (2026-10-10, seeded, with the sc500k static gate and the live-API network assertion excluded through an untracked copy): every row passes through the NeperOS app fixtures, including x_migrate, the capabilities golden and the --compact rows; the only stop is the Flashlight fixture's `morse done` marker, which waits on wall-clock ticks the emulated frames delay on a loaded host.

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
