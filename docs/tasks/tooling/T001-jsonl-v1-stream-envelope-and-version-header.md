# T001 — JSONL v1 stream envelope and version header

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.97 of 1 |
| queue position | 29 of 47 (only position 1 is eligible for the next session; see README) |
| difficulty | low — rated for a small model; a whole checklist line per session is realistic |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> The finite-command JSONL contract for `build`, `check`, `run`, `test`, `fmt`, `tokens`, `parse`, `index`, `dis` and `info`: one version header, advertised `language_profiles`, closed record discriminators, diagnostics in-stream, one final result and no human text on stdout. Validate every record with the v1 schema and every non-schema ordering rule with the S0 tooling corpus (D65)

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The header, diagnostic, token, syntax and result records of section 1 (D227, D228), each a line, the result last with the exit status; emitted by `tokens`, `parse`, `check-file`, `info` (D229), `emit-executable` (D230), `run` (D231), `index` (D232), `dis` (D233), `fmt` (D234) and `test` (D240) -- every section 1 command now streams. An operand that cannot be read answers with the envelope on every one of them (D260): the header, one location-free E-CLI-9999, the result exiting 2 with the command's own zero counts, pinned in both suites for tokens, parse, fmt, fmt --check, dis and test; `check`, `build`, `run` and `index` had it since D228-D232. `-` reads the operand from stdin under the `--path` identity section 4 requires with it, on `tokens`, `parse` and `fmt` (D289: `os.stdin` joined the bootstrap's fixed surface the way `os.mkdir` did); both suites pipe a fixture in and compare against its own golden. `--absolute-paths` on `tokens`, `parse`, `check` and `index` adds `absolute_path` beside the operand's identity and changes nothing else (D290: an absolute operand as given, a relative one under the current directory, which `os.current_dir` joined the bootstrap's fixed surface for); both suites take the field out of a check and a tokens stream and require the golden. `-` on `index-file` under `--path` (D488) reads the module from stdin, the loader taking the text as the root's; both suites pipe the index fixture in and require its golden. `.` and `..` segments are collapsed in `absolute_path` (D489), never past a drive or the leading separator, so two spellings of one file compare equal; both suites spell the fixture roundabout and require the plain path

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] a result record on a JSON output that cannot be initialised

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D227` — `tokens --json` and `parse --json`, and the first of the conformance corpus (`docs/decisions.md:4120`)
- `D228` — `check-file --json`, through one diagnostic emitter (`docs/decisions.md:4141`)
- `D229` — `info --json` is the capability query, pinned per host (`docs/decisions.md:4158`)
- `D230` — `emit-executable --json` is the build stream (`docs/decisions.md:4173`)
- `D231` — `run --json` builds then launches, capturing the whole output (`docs/decisions.md:4189`)
- `D232` — `index --json` names the module and its declarations (`docs/decisions.md:4203`)
- `D233` — `dis --json` lists each function's bytes (`docs/decisions.md:4216`)
- `D234` — `fmt --json` emits the canonical layout (`docs/decisions.md:4228`)
- `D240` — `test --json` runs each @test in its own process (`docs/decisions.md:4372`)
- `D260` — An unreadable operand is the envelope, on every `--json` command (`docs/decisions.md:4935`)
- `D289` — `-` reads stdin on `tokens`, `parse` and `fmt` (`docs/decisions.md:5695`)
- `D290` — `--absolute-paths` adds `absolute_path` beside the operand's identity (`docs/decisions.md:5714`)
- `D488` — `-` on `index` (`docs/decisions.md:10519`)
- `D489` — `.` and `..` collapsed in `absolute_path` (`docs/decisions.md:10531`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `check-file`: `src/main.e`×10‡, `src/tool.e`×6‡, `benchmarks/fuzz/fuzz.py`×3, `benchmarks/scale/profile_check.sh`×3, `scripts/card_examples.py`×2, `scripts/render_card.py`×1, `tests/conformance/tools/plan_generated.x64-linux.expected.jsonl`×1, `tests/conformance/tools/plan_generated.x64-windows.expected.jsonl`×1
- `emit-executable`: `benchmarks/baseline/results/baseline-linux.json`×8, `benchmarks/baseline/results/baseline-windows.json`×8, `src/main.e`×8‡, `benchmarks/baseline/h01-windows-d351.json`×6, `benchmarks/baseline/h29-windows-d382.json`×6, `benchmarks/baseline/h29-windows-d384.json`×4, `benchmarks/baseline/h29-windows-d386.json`×4, `benchmarks/baseline/h29-windows-d387.json`×4
- `os.stdin`: `benchmarks/metamorphic/rename_symbols.py`×1, `src/source.e`×1, `tests/conformance/accept/safety_seeded_handle.e`×1, `tests/conformance/reject/safety_seeded_opaque.e`×1, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×1, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×1
- `os.mkdir`: `lib/e/fs.e`×4, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×4, `src/tool.e`×2‡, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×2, `src/main.e`×1‡
- `absolute-paths`: `src/main.e`×6‡, `src/tool.e`×2‡
- `absolute_path`: `src/main.e`×14‡, `src/tool.e`×2‡, `scripts/validate_stream.py`×1
- `os.current_dir`: `src/main.e`×3‡, `lib/e/fs.e`×1, `src/graph.e`×1†, `src/stats.e`×1, `src/tool.e`×1‡

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
