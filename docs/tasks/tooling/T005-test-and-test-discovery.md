# T005 — test and @test discovery

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.97 of 1 |
| queue position | 33 of 47 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> `@test` discovery uses one child process and fresh arena per test, parallel scheduling with deterministic report order, capture, the 60-second timeout and structured outcomes. `run --json` captures arbitrary child bytes without corrupting JSONL; every duration is the sole normalized volatile field in golden comparisons

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `test-file PATH ROOT ARCH OS WORKDIR --json` (D240): the @test functions of the operand -- an `@test` attribute on a top-level `fn` -- are discovered in source order, a runner carrying them is compiled by spawning the compiler again, and each test runs in its own process so a trap is a crash rather than aborting the harness; the section 7 stream buffers one `test` record per function in source order, a `test_summary`, and the result, exiting 1 if any test is not `passed`. A returned err is `failed`, a trap `crashed`, classified from exit status and stderr; each test and the run carry a real `duration_ms` from the monotonic clock (D242), normalised out of the golden. a test that outruns the deadline is ended by a watchdog thread inside the runner -- the fixed os surface gives the driver no kill and no timed wait, so the child self-terminates on the futex wait's deadline and exits 124 -- and is reported `timeout` with the deadline in `timeout_s` (D246, `WORKDIR [TIMEOUT_MS]`). A crashed test carries the same structured `trap` payload as `run` (D253), mapped from the generated runner back onto the operand -- the runner is the operand's text two `use` lines down, so its span, frame functions and lines come out as the operand's, and a frame in the runner's own scaffolding keeps its printed name with no source; a crash with no record is the `exit` kind carrying the status. `error` is `ok` for a passed test and the qualified name after `error: ` for a failed one, with the runner's module name replaced by the operand's; the fixture's third test indexes past a five-element array. A `@test` that is not a test is refused before anything is compiled, as E-TEST-9999 at the declaration (D256). `test-project DIR ROOT ARCH OS WORKDIR [TIMEOUT_MS] --json` runs every module under DIR/src (D263): the tree in byte order, each module through `test-file --json --path REL` in its own process so its `file` is its path under src and its `module` the dotted name (`nested.deep`), the runner built as part of the project via `emit-executable --project DIR` so a test's `use` of a sibling module resolves, a module with no tests counted and skipped without a compile, and the children's records merged under one header, one summed `test_summary` and one result with the test and module counts; tests/conformance/tools/test_project pins three modules, one test-less, one failing test and one nested test that uses a sibling. A test that does not compile is reported at its own span through the runner's source map, the compiler's records forwarded before the E-CLI-9999 (D264). An operand that both defines `main` and carries tests works (D281): the runner renames the operand's `main` to `nptest_operand_main` and its source map carries the seam as a second mapping, so a diagnostic past it still lands on the operand (tests/conformance/tools/test_main, test_main_error)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] `message` from `test.assert`
- [ ] a call to the operand's own `main` from its tests

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D240` — `test --json` runs each @test in its own process (`docs/decisions.md:4372`)
- `D242` — A test carries its real wall time (`docs/decisions.md:4463`)
- `D246` — A test that outruns its deadline is ended from inside (`docs/decisions.md:4525`)
- `D253` — A trap's record is read back as the `trap` payload, under `run` and `test` (`docs/decisions.md:4761`)
- `D256` — A `@test` that is not a test is E-TEST-9999, before anything is compiled (`docs/decisions.md:4860`)
- `D263` — `test-project` runs every module under a project, and a runner is built as part of it (`docs/decisions.md:5003`)
- `D264` — Source maps: the test runner writes one, and the compiler reads it back (`docs/decisions.md:5033`)
- `D281` — The runner renames the operand's `main`, and the map carries the seam (`docs/decisions.md:5531`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `test_summary`: `src/main.e`×4‡, `src/tool.e`×2‡, `tests/conformance/tools/test.expected.jsonl`×1, `tests/conformance/tools/test_main.expected.jsonl`×1, `tests/conformance/tools/test_only.expected.jsonl`×1, `tests/conformance/tools/test_project.expected.jsonl`×1, `tests/conformance/tools/test_timeout.expected.jsonl`×1
- `crashed`: `src/tool.e`×7‡, `src/main.e`×5‡, `tests/conformance/tools/test.expected.jsonl`×2, `tests/conformance/tools/test_main.expected.jsonl`×1, `tests/conformance/tools/test_only.expected.jsonl`×1, `tests/conformance/tools/test_project.expected.jsonl`×1, `tests/conformance/tools/test_timeout.e`×1, `tests/conformance/tools/test_timeout.expected.jsonl`×1
- `duration_ms`: `src/tool.e`×4‡, `tests/conformance/tools/test.expected.jsonl`×4, `tests/conformance/tools/test_project.expected.jsonl`×4, `src/main.e`×3‡, `tests/conformance/tools/test_main.expected.jsonl`×3, `tests/conformance/tools/test_only.expected.jsonl`×3, `tests/conformance/tools/test_timeout.expected.jsonl`×3
- `timeout_s`: `src/tool.e`×5‡, `scripts/bonsai_driver.py`×4, `src/main.e`×3‡, `tests/conformance/tools/test.expected.jsonl`×3, `tests/conformance/tools/test_project.expected.jsonl`×3, `tests/conformance/tools/test_main.expected.jsonl`×2, `tests/conformance/tools/test_only.expected.jsonl`×2, `tests/conformance/tools/test_timeout.expected.jsonl`×2
- `nested.deep`: `tests/conformance/tools/catalog_verified.x64-linux.expected.jsonl`×2, `tests/conformance/tools/catalog_verified.x64-windows.expected.jsonl`×2, `src/main.e`×1‡, `tests/conformance/tools/impact.expected.jsonl`×1, `tests/conformance/tools/impact_local.expected.jsonl`×1, `tests/conformance/tools/test_project.expected.jsonl`×1, `tests/conformance/tools/test_project/src/nested/deep.e`×1
- `nptest_operand_main`: `src/main.e`×1‡

## Existing fixtures

- `tests/conformance/tools/test_project`
- `tests/conformance/tools/test_main.e`

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
