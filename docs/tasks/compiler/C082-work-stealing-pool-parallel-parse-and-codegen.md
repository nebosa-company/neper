# C082 — Work-stealing pool, parallel parse and codegen

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.75 of 1 |
| queue position | 25 of 55 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/roadmap.md`, section **M2 — Self-hosting and `.em` modules**:

> Work-stealing thread pool, per-thread arenas, sharded intern table

**Done when:** `neper` compiles itself; GP-01 passes its applicable correctness,
failure-injection and deterministic-build cases; a one-function edit rebuilds in
milliseconds on Linux and Windows; clean, incremental, relocated, `-j 1`, every
supported worker count and perturbed-schedule builds produce byte-identical
deterministic artifacts; every M2 API matches source; and the language- and
tool-complete release gates below pass.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> the front end runs in waves of eight workers (D321); the modules are lowered, selected and written as artifacts on eight workers with checkers that share the declarations (D325); and the same workers check the bodies and build both inlining oracles first, each with a checker forked from the program's and importing the types of a body copied from another worker's oracle (D326). A two-million-line program builds cold in 7.6 s debug and 7.4 s release where it took 29 and 26, its body sweep 0.6 s where it took 1.9 (1.3 s where it took 5.7 in release), the settle nothing on a cold build and the lowering not re-checking what the sweep checked (D327), and the bootstrap runs a thread inline. The names are validated on the workers too (D328), the artifact writer copies bytes with one runtime call (D329), and the allocator, the digest and the lexer lost their last quadratic and per-byte costs (D330): a million-line program builds cold in 3.0 s on Windows and 3.4 s on Linux, warm in half a second; the link's per-artifact passes run on the workers too, with SHA-256 and CRC-32C in hardware where the CPU has them (D336): a million-line program builds warm in a quarter of a second, the compiler in 65 ms

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] collecting the declarations, reachability and layout
- [ ] the work is assigned statically, not stolen

Notes:

- The remaining gap is spelled in the evidence's last clause: collecting the declarations, reachability and layout are still sequential, and work is assigned statically rather than stolen. Measure before and after with `--stats`; a change that does not move a number is not the feature.

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D321` — The front end in waves of workers (`docs/decisions.md:6579`)
- `D325` — The modules lowered on worker threads, and every executable linked from artifacts (`docs/decisions.md:6731`)
- `D326` — The bodies checked and both oracles built on the workers that lower (`docs/decisions.md:6769`)
- `D327` — The settle writes an interface only when an edge asks, and the sweep's answers reach the lowering (`docs/decisions.md:6818`)
- `D328` — Names validated on the workers; the declaration tables stay copied (`docs/decisions.md:6855`)
- `D329` — `os.copy_bytes`: one runtime copy where a byte loop stood, and the failure report in value order (`docs/decisions.md:6877`)
- `D330` — The last three leaves, a Linux arena past two gibibytes, and a promotion bug found by measuring (`docs/decisions.md:6905`)
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
