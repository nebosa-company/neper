# T002 — build

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.85 of 1 |
| queue position | 31 of 48 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

The contract is `docs/tooling.md`, section `## 7. Test, build and command results` (the closed v1 authority; `docs/tooling-v2-draft.md` is the non-normative successor draft).

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `emit-executable PATH ROOT ARCH OS OUTPUT [--release] [--arena SIZE] --json` (D230): the section 1 header with command `build`, every front-end, lowering, code-selection and error-table diagnostic as a record, and the result naming the executable as it was given; tests/conformance/tools pins a program that builds and one that is rejected. Every successful build writes `.neper/<mode>/build-manifest.json` under the project root, making the directory when it is missing (D254, D287: `os.mkdir` joined the fixed surface as a bootstrap intrinsic, the self-hosted side already having it from the per-host `e.os` source), its one artifact the executable as named with the SHA-256 of the bytes written; both suites remove the directory, validate the manifest the build makes against the schema and compare the hash to the file on disk. `--project DIR` names the project root outright instead of discovering it from the operand (D263), so a file outside the tree -- a generated test runner -- is built as part of it. Spec section 2's spelling works (D276): `neper build FILE [-o OUT] [--target ARCH-OS] [--release] [--json]`, with the toolchain root the binary's own directory, the target the host unless said, and the output the operand's stem (`.exe` on Windows); `run`, `check`, `fmt`, `index`, `dis` and `build-manifest` have the same front door; both suites compare the short `build` stream to the positional form's golden. `neper test FILE [--project DIR]` is the short `test` (D292): always the stream, its WORKDIR `.neper/debug/test/` under the project the operand is in, made when missing; both suites compare it to the positional form's golden. `neper check` and `neper test` with no operand are the project the current directory is in (D294)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] a project root as `build`'s operand
- [ ] warnings

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D230` — `emit-executable --json` is the build stream (`docs/decisions.md:4173`)
- `D254` — A build writes its manifest, into a directory the project makes once (`docs/decisions.md:4802`)
- `D263` — `test-project` runs every module under a project, and a runner is built as part of it (`docs/decisions.md:5003`)
- `D276` — Spec section 2's spellings, as a front door onto the positional forms (`docs/decisions.md:5412`)
- `D287` — `os.mkdir` joins the fixed surface, as a bootstrap intrinsic only (`docs/decisions.md:5635`)
- `D292` — `neper test FILE` works under `.neper/debug/test/` (`docs/decisions.md:5749`)
- `D294` — `neper check` and `neper test` with no operand are the project (`docs/decisions.md:5774`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `os.mkdir`: `lib/e/fs.e`×4, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×4, `src/tool.e`×2‡, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×2, `src/main.e`×1‡
- `e.os`: `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×164, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×145, `src/resolve.e`×36†, `lib/e/ui/app.e`×12†, `lib/e/os.linux.e`×9‡, `src/check.e`×8‡, `lib/e/fs.e`×7, `lib/e/os.windows.e`×7‡
- `.exe`: `benchmarks/baseline/results/baseline-windows.json`×9, `benchmarks/baseline/h01-windows-d351.json`×7, `benchmarks/baseline/h29-windows-d382.json`×7, `benchmarks/baseline/h29-windows-d384.json`×5, `benchmarks/baseline/h29-windows-d386.json`×5, `benchmarks/baseline/h29-windows-d387.json`×5, `benchmarks/baseline/h29-windows-d390.json`×5, `benchmarks/fuzz/fuzz.py`×4
- `build-manifest`: `src/main.e`×8‡, `src/tool.e`×7‡, `tests/conformance/tools/manifest.e`×1, `tests/conformance/tools/manifest.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest.x64-windows.expected.jsonl`×1, `tests/conformance/tools/manifest_map.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest_map.x64-windows.expected.jsonl`×1, `tests/conformance/tools/manifest_project.x64-linux.expected.jsonl`×1
- `.neper/debug/test/`: `src/main.e`×1‡

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
