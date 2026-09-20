# C050 — Learnability and executable API documentation (v1 precursor for T2 H11)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.76 of 1 |
| queue position | 11 of 54 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H11 — learnability and executable API documentation** (track: T2.1 (Understand and check, open)):

The adopted [standard-library review](stdlib-hardening.md) (D84, SL01–SL11) is part
of this closure: fix catalogue shadowing/import collisions without new syntax,
validate extracted declarations with the real resolver, migrate delivered CPU I/O,
JSON, filesystem/process and iteration surfaces, and deliver `e.cancel` and basic
`e.text.utf8` through this cross-cutting gate. H01/H02/H07 control ownership and native
error-detail migration; H17 controls naming/refactor impact and H18 the installed
capability inventory. Later crypto/network/image/test-support libraries require
frozen contracts and named future fixtures, not premature implementation claims.

Generate compact language cards and per-symbol API records from the selected
language/profile and checked library sources. Distinguish planned, present,
supported-on-target and verified APIs. The current card's examples and tool names
are guidance, not evidence that an executable implements every promised command.

Each API record should expose ownership, borrowing, invalidation, mutation,
allocation, error/partial-success behavior, thread restrictions, phase/target,
examples and executable tests. Provide positive and near-miss negative examples
for novel rules. Publicly shipped examples must compile and run, or be explicitly
labeled rejection tests/proposals with their expected diagnostic.

Avoid requiring every model invocation to read the full specification. Serve a
small versioned entry card plus task-relevant contracts with hashes and provenance.
Measure whether added metadata reduces total repair cost. Keep source/JSON schemas
canonical and allow compact query projections instead of inventing a second terse
programming notation. Lexical tokens and different model tokenizers remain distinct.

Audit API defaults and naming for accidental semantic differences: copying versus
borrowing, mutable versus frozen, consume versus close-on-success, element versus
byte count, and CPU versus device. Correct undocumented exceptions and generate
examples for them. Do not rename stable syntax or APIs on character-count grounds.

Acceptance: cards for old and revised language versions cannot be confused; no
planned-only API is suggested as implemented; examples compile with the advertised
toolchain; retrieval finds exact ownership/failure contracts without unrelated APIs.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The index carries every symbol's signature, spans, attributes and documentation (D232), `context-file` its resource and unsafe facts (D361) and, from the signature, the caller's contract -- allocation from an arena parameter, borrow or mutation per pointer parameter as the view rule reads it, fallible or partial results, a thread started in the body (D396) -- per function with `--symbol`, per module as a catalogue with `--module` (D397); the language card is generated and stamped (D374) and its examples are programs both suites check with the compiler -- a ```neper fence checks clean, a ```neper reject E-CODE fence is refused with that code, the near miss beside the edit shapes (D404). the card's diagnostic codes are marked verified, present or planned from the goldens, the suites and the source (D440), and its displayed grammar productions are explicitly `present` (D567). Concrete functions in a module catalogue are `supported-on-target`, derived from the checked source and requested concrete target rather than a second registry (D568); the first executable test reaching one promotes it to `verified` and is named as evidence (D570). Planned-only modules and APIs answer `unavailable` instead of appearing callable (D571-D572). Generic signatures retain their comptime parameters and dependent types (D573), and catalogues include generic templates: an uninstantiated template is `present`, while a tested concrete instance promotes its template to `verified` (D574). Both suites resolve all twenty-eight source-delivered surfaces and compare their exact declarations with the catalogue (D576); the sixteen compiler-origin functions in `e.atomic`, `e.io` and `e.str` expose exact indexed template signatures to the same gate (D577). `e.proc.run` now delivers independent capture limits and explicit exit, cancellation, deadline and output-limit outcomes over the host process-group/job boundary (D578), with inherited-writer drain closure still pending. The same semantic gate requires every catalogue declaration from all thirteen partial M1/M2 source modules and compares exact signatures for twelve; `e.simd` retains SL01's explicit dependent-metavariable spelling exception (D579)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the remaining SL05 drain edge
- [ ] variant-composed spec surfaces
- [ ] the deferred-library fixture manifest

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D232` — `index --json` names the module and its declarations (`docs/decisions.md:4203`)
- `D361` — `context-file`: one function's facts, with provenance, under a budget (`docs/decisions.md:7924`)
- `D374` — The language card is rendered from the grammar, stamped and hashed (`docs/decisions.md:8282`)
- `D396` — `context-file` states the caller's contract from the signature (`docs/decisions.md:8803`)
- `D397` — `context-file --module`: the contract facts as a catalogue (`docs/decisions.md:8832`)
- `D404` — The card's examples are programs the suites check (`docs/decisions.md:9000`)
- `D440` — The card marks each diagnostic code verified, present or planned (`docs/decisions.md:9700`)
- `D567` — The language card marks grammar-rule standing (`docs/decisions.md:11685`)
- `D568` — API catalogue standing comes from the checked target (`docs/decisions.md:11698`)
- `D570` — Verified APIs name an executable test witness (`docs/decisions.md:11731`)
- `D571` — An absent catalogue subject is explicitly unavailable (`docs/decisions.md:11747`)
- `D572` — An absent API subject is explicitly unavailable (`docs/decisions.md:11760`)
- `D573` — Generic API signatures keep their compile-time parameters (`docs/decisions.md:11774`)
- `D574` — Module catalogues include generic API templates (`docs/decisions.md:11787`)
- `D576` — Source API surfaces are checked by the real resolver (`docs/decisions.md:11817`)
- `D577` — Compiler-origin source APIs have exact indexed signatures (`docs/decisions.md:11832`)
- `D578` — Controlled process runs report bounded partial outcomes (`docs/decisions.md:11846`)
- `D579` — Delivered M1/M2 partial catalogues join the semantic gate (`docs/decisions.md:11863`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `context-file`: `src/tool.e`×6‡, `src/main.e`×5‡, `src/check.e`×3‡, `benchmarks/llm_edit/README.md`×1, `benchmarks/llm_edit/semantic.py`×1, `scripts/render_card.py`×1, `tests/conformance/tools/context_moves.e`×1, `tests/conformance/tools/contract.e`×1
- `supported-on-target`: `tests/conformance/tools/catalog.x64-linux.expected.jsonl`×3, `tests/conformance/tools/catalog.x64-windows.expected.jsonl`×3, `tests/conformance/tools/batch.x64-linux.expected.jsonl`×2, `tests/conformance/tools/batch.x64-windows.expected.jsonl`×2, `tests/conformance/tools/catalog_verified.x64-linux.expected.jsonl`×2, `tests/conformance/tools/catalog_verified.x64-windows.expected.jsonl`×2, `src/tool.e`×1‡
- `verified`: `src/tool.e`×13‡, `src/main.e`×9‡, `scripts/render_card.py`×8, `src/nir.e`×5†, `src/em.e`×4‡, `tests/conformance/tools/catalog_verified.x64-linux.expected.jsonl`×2, `tests/conformance/tools/catalog_verified.x64-windows.expected.jsonl`×2, `lib/e/crypto/mac.e`×1
- `unavailable`: `src/tool.e`×2‡, `tests/conformance/reject/safety_thread_dynamic_array_element_context.e`×1, `tests/conformance/tools/batch.x64-linux.expected.jsonl`×1, `tests/conformance/tools/batch.x64-windows.expected.jsonl`×1, `tests/conformance/tools/catalog_unavailable.expected.jsonl`×1
- `e.atomic`: `src/resolve.e`×14†, `src/check.e`×8‡, `src/main.e`×2‡, `benchmarks/metamorphic/rename_symbols.py`×1, `lib/e/cancel.e`×1, `lib/e/metrics.e`×1, `lib/e/sync.e`×1, `lib/e/task.e`×1
- `e.io`: `src/check.e`×4‡, `src/lower.e`×3‡, `src/main.e`×3‡, `lib/e/fmt/bson.e`×2, `lib/e/fmt/msgpack.e`×2, `lib/e/fmt/quoted_printable.e`×2, `benchmarks/llm_gen/README.md`×1, `benchmarks/llm_gen/tasks/factorial/neper.e`×1
- `e.str`: `src/lower.e`×17‡, `src/check.e`×7‡, `lib/e/str.e`×6†, `lib/e/fmt/json.e`×4†, `lib/e/fmt/csv.e`×3, `lib/e/fmt/ini.e`×3, `lib/e/fmt/png.e`×3, `lib/e/fmt/jpeg.e`×2†
- `e.simd`: `src/check.e`×6‡, `scripts/check_module_surfaces.py`×2, `benchmarks/metamorphic/rename_symbols.py`×1, `src/lower.e`×1‡

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
