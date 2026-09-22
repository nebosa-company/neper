# T015 — Generated source maps

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.72 of 1 |
| queue position | 44 of 48 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

The contract is `docs/tooling.md`, section `## 8. Generated source maps` (the closed v1 authority; `docs/tooling-v2-draft.md` is the non-normative successor draft).

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Section 8, both halves (D264). The generator: `test` writes `nptest-runner.e.map.json` beside the runner it generates -- `neper-source-map`, the runner's SHA-256, one mapping from the operand's text at its place in the runner to the operand -- validated against the schema by both suites. The consumer: `emit-executable`, `run`, `dis` and `check-file` read `<operand>.map.json` when one lies beside the operand; a diagnostic inside a mapped range is reported at the original span as primary with the generated span related, so a test that does not compile is reported at the test's own line (tests/conformance/tools/test_compile_error.e); a map whose hash is not the operand's, or that is not a source map, is E-TOOL-0001 and the command fails with no artifact written (tests/conformance/tools/stale_map.e). The runner's map has two mappings when the operand's `main` was renamed (D281), the second beginning mid-line. A stale or malformed map is E-TOOL-0001 up front and the analysis still runs unmapped, so the operand's own diagnostics follow it; `check` and `build` then fail with no artifact, as section 8 says (D300, tests/conformance/tools/stale_map_error)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] a `project-src` identity
- [ ] columns across a mapping that does not start at a line (the rename's own line)
- [ ] more than eight mappings
- [ ] a reader beyond the key scan this one document shape needs

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D264` — Source maps: the test runner writes one, and the compiler reads it back (`docs/decisions.md:5033`)
- `D281` — The runner renames the operand's `main`, and the map carries the seam (`docs/decisions.md:5531`)
- `D300` — Analysis still runs under a stale source map (`docs/decisions.md:5922`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `neper-source-map`: `src/main.e`×3‡, `tests/conformance/tools/combined_inputs.e.map.json`×1, `tests/conformance/tools/combined_stale.e.map.json`×1, `tests/conformance/tools/generated_map.e.map.json`×1, `tests/conformance/tools/hand_edited.e.map.json`×1, `tests/conformance/tools/nested_deep.e.map.json`×1, `tests/conformance/tools/nested_deep.mid1.map.json`×1, `tests/conformance/tools/nested_deep.mid2.map.json`×1
- `emit-executable`: `benchmarks/baseline/results/baseline-linux.json`×8, `benchmarks/baseline/results/baseline-windows.json`×8, `src/main.e`×8‡, `benchmarks/baseline/h01-windows-d351.json`×6, `benchmarks/baseline/h29-windows-d382.json`×6, `benchmarks/baseline/h29-windows-d384.json`×4, `benchmarks/baseline/h29-windows-d386.json`×4, `benchmarks/baseline/h29-windows-d387.json`×4
- `check-file`: `src/main.e`×10‡, `src/tool.e`×6‡, `benchmarks/fuzz/fuzz.py`×3, `benchmarks/scale/profile_check.sh`×3, `scripts/algos/agent_brief.md`×2, `scripts/card_examples.py`×2, `scripts/algos/decisions-pending.md`×1†, `scripts/render_card.py`×1
- `project-src`: `tests/conformance/tools/plan_rename_type.x64-linux.expected.jsonl`×13, `tests/conformance/tools/plan_rename_type.x64-windows.expected.jsonl`×13, `tests/conformance/tools/nested_instance.x64-linux.expected.jsonl`×9, `tests/conformance/tools/nested_instance.x64-windows.expected.jsonl`×9, `tests/conformance/tools/uses_type.expected.jsonl`×9, `src/main.e`×8‡, `tests/conformance/tools/plan_rename_error.x64-linux.expected.jsonl`×6, `tests/conformance/tools/plan_rename_error.x64-windows.expected.jsonl`×6

## Existing fixtures

- `tests/conformance/tools/test_compile_error.e`
- `tests/conformance/tools/stale_map.e`
- `tests/conformance/tools/stale_map_error.e`

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
