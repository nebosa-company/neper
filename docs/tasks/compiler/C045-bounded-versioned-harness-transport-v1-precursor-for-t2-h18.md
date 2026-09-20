# C045 — Bounded, versioned harness transport (v1 precursor for T2 H18)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.68 of 1 |
| queue position | 8 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H18 — bounded, versioned harness transport** (track: T2.0 (Tooling foundations, open)):

**T2 tooling-v2 delivery: real protocol/schema migration and bounded output.** Extend H08
compact context to diagnostics, indexing, parse export, tests and program capture.

- Define selectable projections and document/symbol tables with snapshot-local IDs.
  Keep a lossless export for consumers that need it; do not require a full token or
  AST dump to answer a narrow semantic question. Include version/capability discovery.
- Every bounded result reports completeness and why it stopped. Exact omitted
  counts may be unknown when traversal stops early; report unknown rather than
  inventing a count. Cursors bind snapshot, query and projection and expire explicitly.
- Fix the roadmap/schema discrepancy: current v1 `edit`/`fix` cannot carry the
  promised expected-source hash. Introduce a versioned schema with document/snapshot
  preconditions, byte spans, edits, applicability and validation obligations. Do not
  add fields to a closed v1 record while continuing to label it v1.
- Add machine-readable diagnostic reasons and typed facts such as expected/actual
  type, resource state, failed phase, unsupported capability or exhausted budget.
  Keep stable causal relations; message wording is not the machine discriminator.
- Replace unbounded complete-output capture as the sole `run --json` contract.
  Bound memory, disk capture and transport; define stdout/stderr chunks or artifact
  references, byte counts, truncation, binary encoding and overflow policy. Draining
  or terminating a flooding child must avoid pipe deadlock and report lost output.
- Separate timely progress from canonical final results. Specify ordering, sequence
  IDs, backpressure, disconnect/cancellation and final status for each transport.
  Output completion must not be confused with child-process success.
- Validate every published JSON example against its selected schema, including
  mandatory diagnostic-parent fields. Reconcile package source coordinates and
  future manifest fields through a versioned extension, not an incompatible v1 reuse.

Acceptance: schema validation of real commands and examples; old-client rejection
or negotiated support; narrow query on a large index; early pagination; binary and
flooding child output; slow/disconnected consumer; cancelled test suite; invalid
cursor; stale fix. Measure serialized bytes and actual tokenizer costs under H25.
No output limit may silently turn an incomplete check/test into a passing result.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> One versioned JSONL stream with a header, a closed record set and `result.data` as the extension map, validated against `docs/schemas/neper-v1.schema.json` by the suites (D227-D300); two-site diagnostics carry `related` (D364); `run --json` is bounded -- `--capture N` bytes per stream in the record, whole counts and `captured_complete` in the result, the files beside the executable holding the rest (D370); a build past `--deadline` ends with one diagnostic and exit 3 (D399); a context page reports its serialized `bytes` and takes a byte budget (D400), and its cursor is bound to the program's `snapshot` on the subject record (D407). a `fix` carries the plans' preconditions, the identity and SHA-256 of the source its edits are offsets into (D432). under `--json --time` every phase of a build is a `progress` record of the stream with its milliseconds, the arena and the elapsed time (D454). Typed name facts (D514): an unknown value name, an unknown type and a module without the member named carry `symbol`, `owner` and `near` as fields beside the message, as a mismatch carries `expected` and `actual` (D401), pinned by the near fixtures and the project goldens. Every E-SAFETY diagnostic carries `symbol`, the resource, view or type its rule is about (D545), pinned by the forty-nine safety and region fixtures. A program that does not load answers as a stream from every query (D521): the header is held until the first record, so the loader's parse or import diagnostic comes under it and a result of exit 1 follows, where the diagnostic had been text on stderr, and `index-file` over a file that does not parse had a stream with no header; pinned over `query_syntax` for three queries and the index on both hosts; `dis-file` and `build-manifest-file` answer the same way (D522), the manifest command under a `manifest` header in place of its object, and a batch over a program that does not check or load is one stream under a `query-batch` header (D523)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] streamed capture chunks
- [ ] sequence IDs

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D227` — `tokens --json` and `parse --json`, and the first of the conformance corpus (`docs/decisions.md:4120`)
- `D300` — Analysis still runs under a stale source map (`docs/decisions.md:5922`)
- `D364` — A safety diagnostic carries its other site as a related span (`docs/decisions.md:8008`)
- `D370` — `run --json` holds a bounded prefix of the child's output, and says what it left (`docs/decisions.md:8162`)
- `D399` — `--deadline MS`: a build is cancelled at the next checkpoint between phases (`docs/decisions.md:8878`)
- `D400` — `--bytes N`: a context page is bounded in serialized bytes, and says what it held (`docs/decisions.md:8905`)
- `D401` — A type mismatch names both types, in the message and as fields (`docs/decisions.md:8923`)
- `D407` — A context answer names the program it was computed against (`docs/decisions.md:9071`)
- `D432` — A fix carries the plans' preconditions (`docs/decisions.md:9566`)
- `D454` — Progress records (`docs/decisions.md:9922`)
- `D514` — Typed name facts (`docs/decisions.md:10897`)
- `D521` — The header held until the first record (`docs/decisions.md:10990`)
- `D522` — The two commands left on stderr (`docs/decisions.md:11006`)
- `D523` — A batch that cannot be answered is one stream (`docs/decisions.md:11017`)
- `D545` — The safety family's symbol (`docs/decisions.md:11327`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `docs/schemas/neper-v1.schema.json`: `scripts/validate_stream.py`×2
- `captured_complete`: `src/main.e`×2‡, `tests/conformance/tools/run.expected.jsonl`×1, `tests/conformance/tools/run_args.expected.jsonl`×1, `tests/conformance/tools/run_flood.expected.jsonl`×1, `tests/conformance/tools/run_trap.expected.jsonl`×1
- `index-file`: `src/main.e`×9‡, `benchmarks/metamorphic/metamorphic.py`×2, `benchmarks/metamorphic/rename_locals.py`×1, `benchmarks/metamorphic/rename_symbols.py`×1, `benchmarks/metamorphic/reorder_parameters.py`×1, `scripts/check_module_surfaces.py`×1, `src/check.e`×1‡, `src/tool.e`×1‡
- `dis-file`: `src/main.e`×7‡, `tests/conformance/tools/dis_inlined.e`×1
- `build-manifest-file`: `src/main.e`×2‡, `src/tool.e`×1‡
- `query-batch`: `src/main.e`×6‡, `benchmarks/metamorphic/reorder_parameters.py`×1, `scripts/render_card.py`×1, `tests/conformance/tools/batch_broken.expected.jsonl`×1

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
