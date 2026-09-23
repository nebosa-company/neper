# C053 — Bounded semantic context for harnesses (v1 precursor for T2 H08)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.68 of 1 |
| queue position | 11 of 46 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H08 — bounded semantic context for harnesses** (track: T2.1 (Understand and check, open)):

Deliver a compiler query, provisionally `neper context`, rather than requiring a
harness to infer semantics from prose. Reuse the resolver, checker and dependency
graph; do not build a second approximate language implementation.

The versioned query contract must support symbol/span selection and return:

- Exact signatures, resolved types/imports/call targets, generic arguments,
  compiler-generated calls and applicable API contracts.
- Ownership transfer, borrow origins, invalidations, cleanup/exit paths, possible
  effects/errors, unsafe boundaries, shared-state and lock obligations.
- Selected language/profile/target/check policy, source/build hashes, dependency
  summary hashes, and identities for the snapshot and requested subject.
- For each fact: compiler-proved, declared-and-checked, trusted external contract,
  runtime-observed or unknown, with provenance. Comments and model-written claims
  are documentation, never promoted to proved facts.

Use caller-selected projections and deterministic byte/record budgets. Return
omission counts, completeness flags and snapshot-bound continuation cursors; never
silently truncate a contract or pretend an incomplete graph is complete. A compact
summary links to exact source instead of dumping whole bodies and the whole API catalogue.
The compiler budgets bytes/records; the harness measures tokenizer-specific tokens.

Represent indirect calls conservatively. Unknown targets/effects are unknown, not
pure or empty. Recursive effect summaries need a convergent rule, public boundary
contracts and budget handling. Avoid creating a second general effect language
unless the requirements justify it.

Existing index numeric IDs are stable only within identical source. Cross-query
edits require snapshot identity plus source hashes; numeric IDs are not persistent
global symbol identities. Source changes invalidate cursors and edits. Target,
generic, protocol, contract and safety changes invalidate cached summaries even
when the function body is unchanged.

Acceptance: deterministic pagination, partial/broken sources, missing imports,
unresolved calls, two generic instances, stale snapshots, removed symbols and
target/check-policy changes. No compiler-proved label may be assigned to an
unverified external assertion. Include misleading instructions in source comments
as inert data in harness tests.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `context-file --json --symbol module.name [--budget N] [--cursor N]` (D361): a subject record bound to the source SHA-256, target and check policy, then facts with provenance -- signature, `own` parameters, the rules that held or the unsafe boundary, every resolved call, dispatch, instantiation and discard with its span -- under a record budget with omission counts, a completeness flag and a deterministic cursor; pinned per host; the caller's contract from the signature -- allocation, borrow, mutation, errors, threads (D396) -- and the same per module as a catalogue (D397); `--bytes N` bounds a page in serialized bytes and the result reports `bytes` (D400); a type subject answers with its fields or members, its layout on the target and what the rules make of a value -- resource, borrow or copy (D419). a constant or a global is a subject too: its declaration, its settled value or its initialisation, and for a global that every thread shares it (D437). a function's page names every module its module imports with the interface hash the manifest records (D498), so an answer can be held against the interfaces it rests on. A broken source answers as a stream (D520): every query over a program that does not check emits its header, the diagnostic and a result of exit 1 on stdout, where `context-file`, `uses-file` and the plans had written text to stderr and nothing a harness could read; pinned over `query_broken` for three commands on both hosts

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] borrow origins inside a body as facts (the views are, D487)
- [ ] partial answers over the functions that do check

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D361` — `context-file`: one function's facts, with provenance, under a budget (`docs/decisions.md:7924`)
- `D396` — `context-file` states the caller's contract from the signature (`docs/decisions.md:8803`)
- `D397` — `context-file --module`: the contract facts as a catalogue (`docs/decisions.md:8832`)
- `D400` — `--bytes N`: a context page is bounded in serialized bytes, and says what it held (`docs/decisions.md:8905`)
- `D419` — A type is a context subject (`docs/decisions.md:9306`)
- `D437` — A constant or a global is a context subject (`docs/decisions.md:9649`)
- `D487` — Views as facts (`docs/decisions.md:10508`)
- `D498` — Dependency hashes on the context page (`docs/decisions.md:10667`)
- `D520` — A broken source answers as a stream (`docs/decisions.md:10977`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `context-file`: `src/tool.e`×6‡, `src/main.e`×5‡, `benchmarks/baseline/context.py`×4, `src/check.e`×3‡, `benchmarks/baseline/session.py`×2, `benchmarks/llm_edit/README.md`×1, `benchmarks/llm_edit/semantic.py`×1, `scripts/render_card.py`×1
- `uses-file`: `src/tool.e`×7‡, `src/check.e`×3‡, `src/main.e`×3‡, `benchmarks/baseline/rename.py`×2, `benchmarks/baseline/session.py`×2, `scripts/render_card.py`×1, `tests/conformance/tools/plan_generated.x64-linux.expected.jsonl`×1, `tests/conformance/tools/plan_generated.x64-windows.expected.jsonl`×1
- `query_broken`: `tests/conformance/tools/batch_broken.txt`×2, `tests/conformance/tools/batch_broken.expected.jsonl`×1, `tests/conformance/tools/context_broken.expected.jsonl`×1, `tests/conformance/tools/plan_rename_broken.expected.jsonl`×1, `tests/conformance/tools/uses_broken.expected.jsonl`×1

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
