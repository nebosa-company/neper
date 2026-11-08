# C253 — a64 Linux CI job running the aarch64 differential check on an arm runner or under QEMU

| field | value |
|---|---|
| category | tooling / Optimization |
| score | 0.00 of 1 |
| queue position | 206 of 225 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened from docs/compiler-optimizations.md: CI has macos-14 for native macOS a64 but no Linux a64 job, so a64 codegen changes (C242, C243, C249) are checked only in WSL. scripts/a64-differential.sh runs prebuilt x64/aarch64 pairs named in build/a64/out/names.txt, which scripts/a64-differential.ps1 builds on Windows, so the job needs a Linux step that builds the pairs itself. Acceptance: a workflow runs the differential on ubuntu-24.04-arm (native) or ubuntu-latest with qemu-user, libc6:arm64 and aarch64-linux-gnu-gcc, builds both architectures of every fixture in the list, and fails when any pair differs outside the five expected ones (when_target, os_fs, fs_basics, os_gaps, debug_dump); a deliberately broken a64 select_binary makes the job fail; the job is triggered by workflow_dispatch and by pushes touching src/codegen_a64.e, src/regalloc.e or src/nir.e.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
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
