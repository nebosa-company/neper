# T013 — Stable diagnostic codes from diagnostics.md

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.85 of 1 |
| queue position | 42 of 48 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> Complete deterministic `index` output for every specified symbol and reference, including unresolved references and compiler-origin protocol, iterator and formatting calls. Stable diagnostic codes come only from `diagnostics.md`; fixes carry non-overlapping original-byte edits and expected-source hashes

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> 39 of 46 registered codes are emitted (D215; the E-SAFETY codes under D345, D348, D349, D351, D354, D357 and D365; E-TEST-9999 under D256, E-FORMAT-9999 under D257, E-TOOL-0001 under D264, E-SYNTAX-0012 under D275), and every one reaches the JSON stream as a `diagnostic` record with its span (D228): E-CLI-9999 for the usage line, E-LEX-0001/0002/0003/9999 for the token the scanner refused by the byte it starts at, E-MODULE-0001 for a `use` naming no module or one defined by both roots and E-MODULE-0002 for one closing a cycle, each at the module that wrote it, E-COMPTIME-9999 for a reflection shape and E-MEM-9999 for an atomic's element or ordering, beside the E-NAME, E-TYPE, E-ERROR and E-LINK codes already there; check/module_missing, module_cycle, lex_literal, lex_tab, lex_utf8 pin them. E-FORMAT-0001 for a source that is not in canonical layout, via `fmt --check` (D244). `test` reports E-TEST-9999 at a `@test` that is not a test -- not a function, or one with a signature other than `fn name(a: *mem.Arena) -> err` -- and exits 2 with nothing compiled (D256, tests/conformance/tools/test_reject.e). `fmt` refuses a comment between an attribute and its declaration as E-FORMAT-9999 at the comment, and an invalid token under its lexical code, as records in the stream rather than a bare `error:` line (D257, tests/conformance/tools/fmt_reject.e). A stale or malformed source map beside the operand is E-TOOL-0001 (D264, tests/conformance/tools/stale_map.e). A soft delimiter still open at a column-0 declaration is E-SYNTAX-0012 at the opener (D275, tests/conformance/reject/barrier.e). Every code the compiler raises is pinned by a conformance fixture (D297)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] E-GPU, E-SAFETY and E-TOOL-9999, whose subjects do not yet diagnose
- [ ] E-LINK-9999 pinned

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D215` — Registered diagnostic codes for the graph, the scanner and the command line (`docs/decisions.md:3943`)
- `D228` — `check-file --json`, through one diagnostic emitter (`docs/decisions.md:4141`)
- `D244` — `fmt --check` reports E-FORMAT-0001 (`docs/decisions.md:4492`)
- `D256` — A `@test` that is not a test is E-TEST-9999, before anything is compiled (`docs/decisions.md:4860`)
- `D257` — What `fmt` refuses is diagnostics, in every form (`docs/decisions.md:4879`)
- `D264` — Source maps: the test runner writes one, and the compiler reads it back (`docs/decisions.md:5033`)
- `D275` — Every recovered failure is a diagnostic, and a barrier crossing is E-SYNTAX-0012 (`docs/decisions.md:5389`)
- `D297` — A reject fixture for every code the compiler raises (`docs/decisions.md:5852`)
- `D345` — Resources are affine and owed: the H01 rules checked over the seeded handles (`docs/decisions.md:7412`)
- `D348` — Declared resources, containment, and a resource's fields as its module's (`docs/decisions.md:7533`)
- `D349` — A borrow is given to no one, a copy is not a duplicate, and `os.dup` is (`docs/decisions.md:7580`)
- `D351` — Nothing moves out from under a pointer, and an arena is affine (`docs/decisions.md:7648`)
- `D354` — H02's lexical subset: a region ends at its reset, a view at its container's change (`docs/decisions.md:7739`)
- `D357` — A thread over this frame's storage is joined in this frame (`docs/decisions.md:7826`)
- `D365` — What a thread was given is the thread's until the join, and H04's design (`docs/decisions.md:8025`)

## Existing fixtures

- `tests/selfhost/fixtures/check/module_missing`
- `tests/conformance/tools/test_reject.e`
- `tests/conformance/tools/fmt_reject.e`
- `tests/conformance/tools/stale_map.e`
- `tests/conformance/reject/barrier.e`

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
