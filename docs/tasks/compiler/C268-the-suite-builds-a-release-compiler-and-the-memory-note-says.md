# C268 — the suite builds a release compiler, and the memory note says which build it measured

| field | value |
|---|---|
| category | compiler / Tooling |
| score | 0.00 of 1 |
| queue position | 223 of 223 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The self-hosted compiler the suite runs was a debug build, and a debug build fills every allocation with 0xCD (D306, section 11). An arena pool charges what it touches, so every pool the loader sizes from the program is committed whether it holds anything or not. Measured on this tree compiling src/main.e: debug-built 6'608-8'883 MB, release-built 365 MB, and the two emit byte-identical code (basic and x_duckdb fixtures hash the same, module surfaces pass 498 exact, graph-file behaves the same). The cost was not subtle: building the compiler left 234 MB free on a 16 GB machine and the suite died on `fatal: out of memory: the system refused to commit` whenever another session held a few gigabytes. After passing --release on the seeded build path the same run leaves ~7.8 GB free and the compiler is 10.74 MB instead of 12.42 MB. The C bootstrap's `build` has no --release, so the NEPER_SEED-less path still builds a debug compiler. This mattered because the numbers contradicted each other and nothing said why: a comment claimed a 388m peak while measurement said 7-9 GB, and hours went into hunting an allocation that did not exist -- the phases really do split 340 MB front end against 6.2 GB after lowering, but the cause was the fill, not any one table. Acceptance: both runners build the compiler with --release on the seeded path and say so where the build happens; the bootstrap path states that it cannot and why; every memory figure left in a label names the build it measured, so a debug and a release number cannot be read as a contradiction again; and one check fails if a runner's compiler build loses --release, so the cost cannot come back silently.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D306` — Two million lines: pools sized from the program, and the constants underneath (`docs/decisions.md:6153`)

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
