# C083 — Determinism harness

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.90 of 1 |
| queue position | 24 of 53 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/roadmap.md`, section **M2 — Self-hosting and `.em` modules**:

> Determinism harness: byte-identical output across `-j 1` and `-j N`, **and byte-identical output from an incremental rebuild and a clean build** of the same sources, over an edit script that touches bodies of inlined, generic and comptime-executed functions (spec §12, D36); the device-reached case is added to the same harness at M3, when `@gpu` exists

**Done when:** `neper` compiles itself; GP-01 passes its applicable correctness,
failure-injection and deterministic-build cases; a one-function edit rebuilds in
milliseconds on Linux and Windows; clean, incremental, relocated, `-j 1`, every
supported worker count and perturbed-schedule builds produce byte-identical
deterministic artifacts; every M2 API matches source; and the language- and
tool-complete release gates below pass.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> compiler fixed point on both platforms, artifact-linked equals source-linked for every artifact fixture, and incremental equals clean for link/incremental (D205); the compiler's own 31 artifacts, listed in graph order, link byte-equal to the source build, and so does the set with one module rebuilt incrementally (D213, D214) -- `link-em` lays functions out in the order the artifacts are given, so the order is an input. `-j N` caps every phase's workers and `--perturb` turns the crew's schedule around (D331): both suites require the compiler built under `-j 1` and under `-j 3 --perturb` to be the stable stage byte for byte, and the inlined release fixture under `-j 1 --perturb` the default build; the hot build under either is the cold image. A relocated build is the same image (D337): the sources spelled from the project root in the line table, so the operand's spelling and the project's place change nothing, pinned by both suites. The fixed point caught the crew's one shared scratch table (D505): the workers' checkers forked every table they append to but the constant expressions, so D500's fold on eight workers wrote over each other's copies and once folded `if 4991usize < limit` away in a loaded stage 3; each worker now has its own

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the device-reached edit case that waits on M3

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D205` — `emit-em-all --incremental` applies the edge rule (`docs/decisions.md:3736`)
- `D213` — The artifact path at the compiler's own size (`docs/decisions.md:3898`)
- `D214` — The edge rule is settled before lowering, and a kept module is not compiled (`docs/decisions.md:3917`)
- `D331` — `-j N`, a perturbed schedule, and the harness asking whether the image depends on either (`docs/decisions.md:6952`)
- `D337` — A relocated build is the same build: the image spells its sources from the root (`docs/decisions.md:7168`)
- `D500` — An `if` over constants folds (`docs/decisions.md:10694`)
- `D505` — The crew's one shared scratch table (`docs/decisions.md:10763`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `link-em`: `src/main.e`×4‡, `benchmarks/fuzz/fuzz.py`×1
- `perturb`: `src/main.e`×11‡, `src/graph.e`×2†

## Existing fixtures

- `tests/selfhost/fixtures/link/incremental`

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
