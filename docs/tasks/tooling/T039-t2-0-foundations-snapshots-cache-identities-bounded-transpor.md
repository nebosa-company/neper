# T039 — T2.0 foundations: snapshots, cache identities, bounded transport

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.80 of 1 |
| queue position | 137 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning text of D1954; AUDIT (D2319, from decision titles, acceptance runs not re-executed): most of the slice has landed under earlier C-items -- H15: D369 policy identity, D398 compiler identity, D407/D436 snapshot named by results, D431, D502 overlays, D507 candidate keys, D1518, D1519 apply-plan transaction, D1526 batch snapshots/pins/eviction/stale keys; H16: D372, D399/D496 deadlines, D409/D410 batch, D558/D559 retained memory and 10,000 queries, D947, D1527; H18: D370 bounded run capture, D1525 chunked capture, D400 byte-bounded context pages, D432 fixes carry preconditions, D454/D561 progress ordering; H24: D341 fuzzing and nesting, D343 atomic publication, D368 corrupt artifacts named, D435 cache fault injection, D472, D474 whole-build budget. post-m2-llm-hardening T2.0 slice missing from the queue: immutable snapshots, complete cache identities, bounded request/result storage, cancellation, compact transport and hardened artifact publication (H15/H16/H18/H24). Pickup immediately after the chart cluster (L061, L068-L075). Versioned schema from the start; later slices extend it only by capability. FIRST SLICE (D2319): `info --json --capabilities` lists every command with its group, the stream versions, bounding flags and the snapshot field; golden in tests/conformance/tools/capabilities.expected.jsonl, both suites. NOT DONE: per-command schema versions and bounds, the versioned edit/fix schema with expected-source hashes, bounded run --json capture, H15/H16/H24 acceptance runs. ACCEPTANCE ROWS FOUND (D2319 follow-up): the suite carries fault injection for apply (--fault-apply), cancellation (--fault-cancel), hash collision (--fault-collision), a worker running dry (--fault-dry, six rows), an interrupted edit (--fault-edit) and cache writes (--fault-write), the ten-thousand edit/query/revert soak under a fixed budget (run.ps1 batch soak), -j 1 versus -j 3 --perturb byte equality, and the seeded Windows run reached them green (run 16, D2317). REMAINING GAPS, named: no test of a source file changing between the lazy read of two modules of one check (a mixed-version snapshot), no queued-request saturation test (there is no request queue to saturate: `query-batch` is one process, one request at a time), and package-resolution/generator-input identity waits on M6. SUITE (run 18): the capabilities golden and the schema validation pass on Windows.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D341` — Bounded malformed input: the fuzzer, the nesting bound, and the link's hash scratch (`docs/decisions.md:7301`)
- `D343` — An artifact is published by one atomic replace, and a damaged cache is rebuilt (`docs/decisions.md:7368`)
- `D368` — A corrupt artifact is named: E-LINK-0001 on the command line, `invalid-artifact` in the manifest (`docs/decisions.md:8102`)
- `D369` — A check policy is a build identity: `--unchecked` artifacts carry their own mode (`docs/decisions.md:8128`)
- `D370` — `run --json` holds a bounded prefix of the child's output, and says what it left (`docs/decisions.md:8162`)
- `D372` — No persistent server before the measurement says so: H10 and H16 dispositions (`docs/decisions.md:8217`)
- `D398` — The compiler that wrote an artifact is part of its identity (`docs/decisions.md:8852`)
- `D399` — `--deadline MS`: a build is cancelled at the next checkpoint between phases (`docs/decisions.md:8878`)
- `D400` — `--bytes N`: a context page is bounded in serialized bytes, and says what it held (`docs/decisions.md:8905`)
- `D407` — A context answer names the program it was computed against (`docs/decisions.md:9071`)
- `D409` — `query-batch`: many queries, one check (`docs/decisions.md:9114`)
- `D410` — A batch line is a request of its own, and the arena says so (`docs/decisions.md:9138`)
- `D431` — The inline cap is part of the artifact identity (`docs/decisions.md:9550`)
- `D432` — A fix carries the plans' preconditions (`docs/decisions.md:9566`)
- `D435` — A fault injected into the cache writes (`docs/decisions.md:9619`)
- `D436` — A plan's result names the program's snapshot (`docs/decisions.md:9636`)
- `D454` — Progress records (`docs/decisions.md:9922`)
- `D472` — A cyclic artifact reference is a damaged artifact (`docs/decisions.md:10240`)
- `D474` — A whole-build budget over the interpreter's steps (`docs/decisions.md:10288`)
- `D496` — The deadline inside an evaluation (`docs/decisions.md:10636`)
- `D502` — Overlays: a module's text from another file (`docs/decisions.md:10722`)
- `D507` — The key is a candidate (`docs/decisions.md:10796`)
- `D558` — Retained memory after warmup (`docs/decisions.md:11532`)
- `D559` — Ten thousand reclaimed queries (`docs/decisions.md:11549`)
- `D561` — Live progress has an explicit order (`docs/decisions.md:11585`)
- `D947` — H25's persistent-session workflow: a query in tens of milliseconds, nothing retained (`docs/decisions.md:18975`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `query-batch`: `src/main.e`×7‡, `benchmarks/baseline/session.py`×3, `scripts/check_batch_snapshots.py`×2, `benchmarks/metamorphic/reorder_parameters.py`×1, `scripts/render_card.py`×1, `src/tool.e`×1‡, `tests/conformance/tools/batch_broken.expected.jsonl`×1, `tests/conformance/tools/capabilities.expected.jsonl`×1

## Existing fixtures

- `tests/conformance/tools/capabilities.expected.jsonl`

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
