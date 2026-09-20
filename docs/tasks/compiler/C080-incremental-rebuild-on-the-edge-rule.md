# C080 — Incremental rebuild on the edge rule

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.95 of 1 |
| queue position | 24 of 47 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/roadmap.md`, section **M2 — Self-hosting and `.em` modules**:

> Incremental and parallel module compilation on the edge rule of spec §12

**Done when:** `neper` compiles itself; GP-01 passes its applicable correctness,
failure-injection and deterministic-build cases; a one-function edit rebuilds in
milliseconds on Linux and Windows; clean, incremental, relocated, `-j 1`, every
supported worker count and perturbed-schedule builds produce byte-identical
deterministic artifacts; every M2 API matches source; and the language- and
tool-complete release gates below pass.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `emit-em-all --incremental` (D205) lets section 12's edge rule decide per module: the artifact on disk stays when its source hash and build mode are unchanged (`--release` builds release artifacts, D211) and every recorded edge still matches the declaration it names in the target's fresh Interface, and is replaced otherwise; `kept`/`rebuilt` is printed per module. The decision is taken after checking and before lowering (D214): every hash an Interface carries comes from the checker -- a body hash is over the declaration's tokens -- so the fresh Interfaces are written from it alone, and a kept module is not lowered, selected or written at all. That is the saving: over the compiler's 31 modules a build with nothing changed takes 10 s against 34 s, and one with a body edit in `decimal` rebuilds `decimal` alone in 13 s, linking byte-equal to a clean build. An artifact holds the whole module now, not the functions this program reaches; the linker prunes. link/incremental pins unchanged sources kept, a body edit behind a signature edge rebuilding only its module with the linked result byte-equal to a clean build, and a signature edit rebuilding the dependent, on both platforms. The artifact path became usable at this size in D213: a CRC per read and a bit-loop `xor` under it had cost minutes. The checker settles the declarations first and the edge rule decides on them, so a kept module's bodies are not checked either, and the load-time checksum is table-driven (D224): a build with nothing changed is 4 s. `emit-executable --incremental` and `run --incremental` are the hot build (D319): the keep set settled after the declarations, the kept modules' bodies and code skipped, each fresh module's artifact written as it is selected, and the image linked from every module's artifact, byte for byte the cold build's; the compiler with nothing changed settles in 0.6 s and links in 1.0 s. At scale the artifact path walks a module's own rows and resolves through indexes, bytes are bytes and the NIR section is not written (D320): warm, nothing changed, the compiler builds in 1.1 s, a 500k-line program in 3.1 s and a 2M-line one in 12.6 s, each the cold build's image byte for byte. An unchanged module is not parsed unless something that changed imports it (D322, artifacts carry their imports, format 6): warm builds 0.86 s / 1.5 s / 6.1 s, and a leaf edit costs the warm build plus the module; with the manifest's digests carried on the artifact (D323, format 7) a release-built compiler builds itself warm in 0.24 s, 500k lines in 0.97 s, 2M in 4.0 s; with the artifacts read and validated on worker threads and the link reading through the bounds it holds (D324): 0.19 s / 0.36 s / 1.6 s

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the load itself -- every artifact read and widened to decide --
- [ ] the declarations of every module

Notes:

- The gap clause in the queue predates D319–D324, which delivered the hot build it names. At 0.95 what is still owed is the roadmap's 'a one-function edit rebuilds in milliseconds' on both hosts against a measured baseline, and a warm build that does not load every module's declarations. Measure with `--stats` on a warm no-change build before choosing; if nothing is left, the honest increment is a `Not yet:` rewrite and the score.

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D205` — `emit-em-all --incremental` applies the edge rule (`docs/decisions.md:3736`)
- `D211` — Debug builds do not inline; `emit-em-all` takes `--release` (`docs/decisions.md:3858`)
- `D213` — The artifact path at the compiler's own size (`docs/decisions.md:3898`)
- `D214` — The edge rule is settled before lowering, and a kept module is not compiled (`docs/decisions.md:3917`)
- `D224` — The kept modules' bodies are not checked, and the checksum is table-driven (`docs/decisions.md:4079`)
- `D319` — A hot build: `emit-executable --incremental`, the image from artifacts (`docs/decisions.md:6496`)
- `D320` — The artifact path at scale: bytes are bytes, a module's own rows, indexes over every walk (`docs/decisions.md:6526`)
- `D322` — A hot build parses what changed, and what it must (`docs/decisions.md:6617`)
- `D323` — The manifest's digests ride the artifact, and the root arena is a gibibyte (`docs/decisions.md:6668`)
- `D324` — A wave's artifacts on worker threads, and the link reads what it holds (`docs/decisions.md:6705`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `rebuilt`: `src/main.e`×14‡, `src/tool.e`×3‡, `lib/e/data/slot_map.e`×1, `lib/e/fmt/json.e`×1†, `lib/e/fmt/uri.e`×1, `scripts/render_tasks.py`×1†, `src/artifact_hash.e`×1, `src/em_link.e`×1†

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
