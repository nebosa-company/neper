# C052 — Structured edits (v1 precursor for T2 H29)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.91 of 1 |
| queue position | 9 of 45 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `plan-rename-file --json --symbol m.f --to g` emits a plan -- `precondition` (file hashes), `edit` (`rename-symbol`, site, span, replacement), `postcondition` -- and applies nothing; `scripts/apply_plan.py` applies all or none against the hashes; both suites round-trip it (D376); `add-parameter-and-migrate` is `plan-add-parameter-file`, applied and re-checked by both suites, refused where a value or a protocol holds the signature (D406); `replace-expression` is `plan-replace-expression-file`, the span checked to be one expression node, applied and re-checked by both suites (D414); `change-signature` is `plan-change-signature-file`, the parameters reordered or removed by index and every call re-rendered from its own text, applied and re-checked by both suites (D415) -- the four shapes `m25-h29-structured-edits.md` fixed all exist. every plan's result names the program's `snapshot` (D436). `--arguments FILE` gives the added parameter an argument per call by the call's line and column with a `*` default, refused for a call it leaves out (D455). `neper apply-plan` (D481) applies a plan in the compiler -- every precondition's hash or nothing, highest offset first, `.tmp` and one replace, E-TOOL-0003 for a plan that cannot be applied as it stands -- and both suites apply every corpus plan with it; the Python applier is retired. A type's rename is a plan too (D515), from the index's references, where a subject naming a type was refused; the plans over the compiler itself -- a function at five hundred and forty sites, a type at four hundred -- apply and build the stable stage in both suites (D537), and so do the signature plans over the same function, its parameters reordered at every call and a parameter added with an argument at every call (D538). A stale plan's refusal names the file whose precondition no longer holds, in the message and as `symbol` (D547)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] a plan over more than one program

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D376` — The first structured edit: a rename is a plan with preconditions, and nothing applies itself (`docs/decisions.md:8352`)
- `D406` — `plan-add-parameter-file`: the signature-change plan (`docs/decisions.md:9039`)
- `D414` — `plan-replace-expression-file`: the fourth plan shape (`docs/decisions.md:9206`)
- `D415` — `plan-change-signature-file`: the four plan shapes all exist (`docs/decisions.md:9226`)
- `D436` — A plan's result names the program's snapshot (`docs/decisions.md:9636`)
- `D455` — An argument per call for the added parameter (`docs/decisions.md:9935`)
- `D481` — `apply-plan`: the compiler applies its own plans (`docs/decisions.md:10409`)
- `D515` — A type's rename is a plan (`docs/decisions.md:10909`)
- `D537` — The plans over the compiler (`docs/decisions.md:11203`)
- `D538` — The signature plans over the compiler (`docs/decisions.md:11217`)
- `D547` — The stale plan's file (`docs/decisions.md:11356`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `rename-symbol`: `tests/conformance/tools/plan_rename_type.x64-linux.expected.jsonl`×11, `tests/conformance/tools/plan_rename_type.x64-windows.expected.jsonl`×11, `tests/conformance/tools/plan_rename_field.x64-linux.expected.jsonl`×6, `tests/conformance/tools/plan_rename_field.x64-windows.expected.jsonl`×6, `tests/conformance/tools/plan_rename_error.x64-linux.expected.jsonl`×4, `tests/conformance/tools/plan_rename_error.x64-windows.expected.jsonl`×4, `src/tool.e`×3‡, `tests/conformance/tools/plan_generated.x64-linux.expected.jsonl`×3
- `scripts/apply_plan.py`: `src/main.e`×1‡
- `add-parameter-and-migrate`: `tests/conformance/tools/plan_parameter.x64-linux.expected.jsonl`×2, `tests/conformance/tools/plan_parameter.x64-windows.expected.jsonl`×2, `tests/conformance/tools/plan_parameter_sites.x64-linux.expected.jsonl`×2, `tests/conformance/tools/plan_parameter_sites.x64-windows.expected.jsonl`×2, `src/tool.e`×1‡
- `plan-add-parameter-file`: `src/main.e`×4‡, `scripts/render_card.py`×1, `src/tool.e`×1‡
- `replace-expression`: `src/main.e`×5‡, `src/tool.e`×4‡, `tests/conformance/tools/plan_replace.x64-linux.expected.jsonl`×2, `tests/conformance/tools/plan_replace.x64-windows.expected.jsonl`×2, `scripts/render_card.py`×1, `tests/conformance/tools/plan_replace_refused.expected.jsonl`×1
- `plan-replace-expression-file`: `src/main.e`×4‡, `scripts/render_card.py`×1, `src/tool.e`×1‡
- `change-signature`: `src/main.e`×5‡, `tests/conformance/tools/plan_signature.x64-linux.expected.jsonl`×4, `tests/conformance/tools/plan_signature.x64-windows.expected.jsonl`×4, `tests/conformance/tools/plan_signature_remove.x64-linux.expected.jsonl`×4, `tests/conformance/tools/plan_signature_remove.x64-windows.expected.jsonl`×4, `src/tool.e`×3‡, `benchmarks/metamorphic/reorder_parameters.py`×1, `scripts/render_card.py`×1
- `plan-change-signature-file`: `src/main.e`×4‡, `scripts/render_card.py`×1, `src/tool.e`×1‡
- `.tmp`: `lib/e/fmt/opus.e`×27‡, `src/main.e`×6‡

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
