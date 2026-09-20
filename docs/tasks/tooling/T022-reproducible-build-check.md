# T022 — Reproducible-build check

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.85 of 1 |
| queue position | 48 of 49 (only position 1 is eligible for the next session; see README) |
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

> Both suites check the compiler's fixed point -- stage 2 and stage 3 byte for byte -- and, since D261, that a program built twice is the same executable and that the second build's manifest carries the first's artifact SHA-256, so two builds can be compared by their manifests without the executables (D254 wrote the hash); `neper compare-manifests A B [--json]` (D482) is that comparison as a command -- identity, inputs, dependencies and artifacts by hash, not path -- and both suites hold two builds' manifests to agree and a debug one to differ from a release one by mode and artifact

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] cross-host comparison (a Windows and a Linux build differ by design)
- [ ] the dependency and library hashes the manifest does not yet carry

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D254` — A build writes its manifest, into a directory the project makes once (`docs/decisions.md:4802`)
- `D261` — A program built twice is the same bytes, and its manifest says so (`docs/decisions.md:4954`)
- `D482` — `compare-manifests`: two builds held against each other (`docs/decisions.md:10427`)

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
