# T009 — index, symbols and references

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.92 of 1 |
| queue position | 41 of 51 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

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

> `index-file PATH ROOT ARCH OS --json` (D232): a `symbol` record for the operand module and each of its module-scope declarations -- fn, extern, type, const, module_var, error -- with the closed `kind`, qualified name, full and selection spans and container id, ending in the result with the symbol count; tests/conformance/tools/index.e pins all seven kinds. Each symbol carries its `signature` (the header up to the body brace, so a const or extern is its own), its `attributes` (the `@name` run section 12 requires adjacent) and its `documentation` -- spec section 3's `///` run, one optional space stripped, joined with LF, ended by a blank line or an ordinary `//`, and attaching through the attributes (D251); the fixture pins a two-line doc, a documented `@test`, and a run broken by a blank line. Under a function or type the parse tree supplies its parameters, fields and enum/union members as `parameter`, `field` and `member` symbols with the declaration as `container_id`, qualified `module.Decl.name`, their own signature and `///` documentation, in token order (D258); the fixture pins a documented field, two enum members and three parameters. Every use of one of the module's own names, and every name reached through a `use` qualifier, is a `reference` record (D271): `import` for each `use`, `type` in a type position or a type's name in a path, `call` before `(`, `instantiate` before `[`, `write` before an assignment, `address` after `&`, `read` otherwise; a bare name resolves to the operand's symbol by id -- spec section 5 lets no local shadow a module-scope name, so the match is the resolution -- and a qualified one names `path.name` with a null id; records sorted by span start after the symbols, the result counting both; the fixture pins eleven across every role but `protocol`. Symbols and references go out in section 5's one span order (D280): the references are collected first, every symbol's id is known before any record is written, and each reference is emitted before the first symbol -- nested ones included -- whose span starts after it; the fixture's thirty records are monotone in span start. `index-project DIR ROOT ARCH OS WORKDIR --json` indexes every module under a project's src and lib in byte order, each in its own `index-file --json --path REL` process so its identity is its path from the root, the symbol, reference and diagnostic records under one header and a result with the totals; `neper index` with no operand is that over the project the current directory is in (D298, tests/conformance/tools/index_project). Locals are symbols (D483): every `let`/`var` binding, each name of a tuple binding, and every `for` variable is a `local` under its function, and a bare name in the body that is a local or parameter declared before it is a reference to that symbol with its role, read off the tree as the module-scope references are; the two index goldens carry them. The sixteen compiler-origin functions exposed through the source-delivered `e.atomic`, `e.io` and `e.str` modules are null-span `intrinsic` symbols with exact canonical signatures (D577)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] `--all` for the toolchain's lib
- [ ] comptime parameters
- [ ] compiler-origin `protocol` and iterator references

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D232` — `index --json` names the module and its declarations (`docs/decisions.md:4203`)
- `D251` — A symbol carries its signature, its attributes and its `///` documentation (`docs/decisions.md:4729`)
- `D258` — A declaration's parameters, fields and members are symbols under it (`docs/decisions.md:4905`)
- `D271` — References in the index, resolved by the rule that forbids shadowing (`docs/decisions.md:5292`)
- `D280` — The index is one span order over symbols and references (`docs/decisions.md:5517`)
- `D298` — `neper index` with no operand indexes the project (`docs/decisions.md:5868`)
- `D483` — Locals in the index (`docs/decisions.md:10444`)
- `D577` — Compiler-origin source APIs have exact indexed signatures (`docs/decisions.md:11832`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `@name`: `src/tool.e`×2‡, `src/check.e`×1‡
- `documentation`: `tests/conformance/tools/index.expected.jsonl`×24, `tests/conformance/tools/index_unsafe.expected.jsonl`×18, `src/tool.e`×9‡, `tests/conformance/tools/index_project.expected.jsonl`×8, `scripts/build-docs-pdf.py`×4, `tests/conformance/tools/index.e`×2, `scripts/build-docs-pdf.ps1`×1, `scripts/build-docs-pdf.sh`×1
- `container_id`: `tests/conformance/tools/index.expected.jsonl`×24, `tests/conformance/tools/index_unsafe.expected.jsonl`×18, `tests/conformance/tools/index_project.expected.jsonl`×8, `src/tool.e`×7‡, `src/main.e`×2‡, `scripts/check_module_surfaces.py`×1
- `instantiate`: `src/check.e`×19‡, `src/lower.e`×4‡, `src/em.e`×2‡, `tests/conformance/tools/index_unsafe.expected.jsonl`×2, `src/tool.e`×1‡, `tests/conformance/reject/safety_copy_toolchain.e`×1, `tests/conformance/tools/explain.e`×1
- `e.atomic`: `src/resolve.e`×14†, `src/check.e`×8‡, `src/main.e`×2‡, `benchmarks/metamorphic/rename_symbols.py`×1, `lib/e/cancel.e`×1, `lib/e/metrics.e`×1, `lib/e/sync.e`×1, `lib/e/task.e`×1
- `e.io`: `src/check.e`×4‡, `src/lower.e`×3‡, `src/main.e`×3‡, `lib/e/fmt/bson.e`×2, `lib/e/fmt/msgpack.e`×2, `lib/e/fmt/quoted_printable.e`×2, `benchmarks/llm_gen/README.md`×1, `benchmarks/llm_gen/tasks/factorial/neper.e`×1
- `e.str`: `src/lower.e`×17‡, `src/check.e`×7‡, `lib/e/str.e`×6†, `lib/e/fmt/json.e`×4†, `lib/e/fmt/csv.e`×3, `lib/e/fmt/ini.e`×3, `lib/e/fmt/png.e`×3, `lib/e/fmt/jpeg.e`×2†

## Existing fixtures

- `tests/conformance/tools/index.e`
- `tests/conformance/tools/index_project`

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
