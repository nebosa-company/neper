# C266 — the bootstrap builds the tree again: refresh it, or make the seed path the contract

| field | value |
|---|---|
| category | compiler / Hardening |
| score | 0.00 of 1 |
| queue position | 221 of 222 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Found while getting tests/selfhost to reach its DuckDB fixture. build/windows/neper.exe and build/linux/neper are both 0.0.96-neper0 and neither can parse the current tree: lib/e/str.e:13 stops at a function type as a struct member, src/check.e:924 at a type-member limit. The bootstrap is a fixed point -- it must parse what it builds -- so once the language gains syntax it cannot build src/main.e, and the suite fails at selfhost.ps1:39 'self-hosted compiler slice did not build'. Windows only appeared healthy because a self-hosted compiler from 6 Nov sat in build/; Linux had nothing until run.sh gained the NEPER_SEED path run.ps1 already had (83bc973bb), and a compiler cross-emitted from the Windows self-host works as that seed. Acceptance: a bootstrap that builds the current src/main.e on both hosts with no NEPER_SEED set, and a suite run on a clean checkout that reaches its fixtures; or, if the seed becomes the contract, both runners require NEPER_SEED and fail with one message naming how to produce it; plus a check that asserts the bootstrap parses the tree so this cannot rot silently again.

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
