# C079 — Cross-module inlining, 40 NIR cap

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.95 of 1 |
| queue position | 22 of 54 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/roadmap.md`, section **M2 — Self-hosting and `.em` modules**:

> Cross-module inlining via NIR, capped at 40 NIR instructions per callee, each inlined body recorded as a body-hash edge

**Done when:** `neper` compiles itself; GP-01 passes its applicable correctness,
failure-injection and deterministic-build cases; a one-function edit rebuilds in
milliseconds on Linux and Windows; clean, incremental, relocated, `-j 1`, every
supported worker count and perturbed-schedule builds produce byte-identical
deterministic artifacts; every M2 API matches source; and the language- and
tool-complete release gates below pass.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The inlining oracle (D207): every short non-generic function of every module is lowered ahead of the program into a builder of its own, and a call to one that came out at forty NIR instructions or under, with at most one register result, is replaced by a copy of its body -- parameters become the arguments, returns become branches to the continuation, references are re-interned -- in module order on both link paths, so an executable linked from artifacts is still byte-identical. Only a release build inlines (D211): a debug build keeps every call a frame, as section 13's debug-info rule says, and `emit-em-all --release` is where the artifacts' body edges come from. The artifact records a body edge to every inlined callee of another module, and `--incremental` acts on it: link/incremental pins, in release, a body edit behind a signature edge keeping the dependent and one behind a body edge rebuilding it. The oracle is built twice, the second against the first, so a copy is two levels deep and carries the body edges of the body it copies (D212, link/inline_nested: a leaf's body edit rebuilds the module two copies up). `--inline-cap N` and `--explain` (D348): the cap re-evaluated at 0/20/40/80/160 on the compiler compiling 500k lines (forty retained: seven per cent faster than none, twenty as fast at five per cent less image, more buys nothing) and every oracle decision explained on request

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the cap is applied within a module too, where the section has none
- [ ] a third level

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D207` — Cross-module inlining through an oracle lowered ahead of the program (`docs/decisions.md:3775`)
- `D211` — Debug builds do not inline; `emit-em-all` takes `--release` (`docs/decisions.md:3858`)
- `D212` — Nested inlining through a second oracle, and every function has a frame (`docs/decisions.md:3875`)
- `D348` — Declared resources, containment, and a resource's fields as its module's (`docs/decisions.md:7533`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `inline-cap`: `src/main.e`×6‡, `src/lower.e`×2‡, `src/nir.e`×1†

## Existing fixtures

- `tests/selfhost/fixtures/link/incremental`
- `tests/selfhost/fixtures/link/inline_nested`

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
