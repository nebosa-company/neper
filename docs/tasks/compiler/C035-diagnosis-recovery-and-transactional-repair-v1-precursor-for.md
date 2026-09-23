# C035 — Diagnosis, recovery and transactional repair (v1 precursor for T2 H09)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.86 of 1 |
| queue position | 1 of 47 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H09 — diagnosis, recovery and transactional repair** (track: T2.2 (Edit and test evidence, open)):

- Emit causal diagnostics with stable codes, an error origin, related locations,
  expected/actual types or resource states, and a bounded instantiation/call chain.
  Group cascades under the primary cause without hiding independent failures.
- Keep lexer/parser recovery deterministic and lossless. Consume input or stop at
  each recovery step, preserve invalid bytes and expose error nodes. Never silently
  insert/delete/transpose characters and compile the repaired interpretation.
- Distinguish syntactically recovered, semantically incomplete, rejected and fully
  checked output. Unsupported analysis and budget exhaustion fail closed. Valid
  declarations elsewhere may still be indexed with explicit completeness metadata.
- Structured fixes identify the source snapshot, expected bytes/hash, exact
  nonoverlapping edits and postconditions. Multi-file refactors validate every
  precondition before writing; failure leaves all sources untouched. Define a
  recoverable transaction/journal and coordination with concurrent editor changes.
- Preview semantic impact: callers, borrowed results, affected generics, protocols,
  tests and public APIs. Format only within a well-defined transaction; preserve
  comments and unrelated source. Recheck after applying, since a suggested fix is
  not a proof of program correctness.
- Never mark a fix automatically safe merely because it compiles. Narrowing casts,
  added error discards, changed ownership, disabling checks and introducing unsafe
  code need explicit semantic justification and must not be hidden repair defaults.

Acceptance: truncated code, malformed UTF-8, missing delimiters, several independent
errors, stale source during a rename, cross-file partial failure and diagnostic
floods. Test the real command schema and ordering, not regexes over human messages.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Every two-site E-SAFETY diagnostic carries its other site -- acquisition, move, deferred call, borrow, pointer, reset, mutation, thread start -- as a `related` span with a message saying which (D364), pinned by the reject corpus; stable codes throughout; the parser's nesting bound and error nodes are D341's; a forgotten cleanup carries its `defer <closer>(x)` and an untested acquisition its `if e != ok { ret e }` as `fixes` entries (D381, D382), and a rename is a plan with preconditions (D376); a type mismatch names both types in its message and carries them as `expected` and `actual` fields, pinned by `reject/type_mismatch` (D401). A diagnostic raised in a module that is not the operand names it under its own root (`toolchain-lib`, `project-src`, `project-lib`) by the manifest's rule (D427). a scalar mismatch at a name or a literal carries the conversion as a `maybe` fix over the expression's span (D444). an unknown value name within two edits of a name in scope names it and carries it as a `maybe` fix (D445), a member a module does not export names the module, the member and the nearest export at the member's token (D447), and a field an aggregate does not declare names the type, the field and the nearest field (D448); an unknown type name sits on its token and names the nearest type in scope -- a declared type or a builtin scalar -- as a `maybe` fix (D485; it was a location-free `name resolution failed`); the conversion fix reaches a whole value -- a call, a field read, an index, a group -- wrapped as one (D491; `reject/type_mismatch_call`), an arithmetic expression still offering none. An instance asked for by an instance relates the chain of requests, innermost first, up to three links (D543), where one site was named. `check-file --json` goes on past a failing function to the next and reports every function's first error in one run, the instances after them (D553), the plain output keeping to the first for neper-0 parity, where the first had ended the check; a cascade inside a body is still cut at its first failure

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] cascades across functions grouped under a primary cause, lossless recovery beyond D341

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D341` — Bounded malformed input: the fuzzer, the nesting bound, and the link's hash scratch (`docs/decisions.md:7301`)
- `D364` — A safety diagnostic carries its other site as a related span (`docs/decisions.md:8008`)
- `D376` — The first structured edit: a rename is a plan with preconditions, and nothing applies itself (`docs/decisions.md:8352`)
- `D381` — The first fix: a forgotten cleanup offers its `defer` (`docs/decisions.md:8466`)
- `D382` — The second fix: an untested acquisition offers its test (`docs/decisions.md:8490`)
- `D401` — A type mismatch names both types, in the message and as fields (`docs/decisions.md:8923`)
- `D427` — A diagnostic names the module it lands in by the manifest's rule (`docs/decisions.md:9457`)
- `D444` — A scalar mismatch carries its conversion as a fix (`docs/decisions.md:9760`)
- `D445` — An unknown name names its nearest neighbour (`docs/decisions.md:9778`)
- `D447` — A module without the member named says which (`docs/decisions.md:9809`)
- `D448` — A field the aggregate does not declare says which (`docs/decisions.md:9822`)
- `D485` — An unknown type name, at its token, with the nearest type (`docs/decisions.md:10476`)
- `D491` — The conversion fix over a whole value (`docs/decisions.md:10551`)
- `D543` — The instantiation chain (`docs/decisions.md:11294`)
- `D553` — Every function's first error (`docs/decisions.md:11440`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `toolchain-lib`: `src/main.e`×2‡, `src/tool.e`×2‡, `tests/conformance/tools/explain.expected.jsonl`×2, `tests/conformance/reject/safety_copy_toolchain.e`×1, `tests/conformance/tools/manifest_unsafe.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest_unsafe.x64-windows.expected.jsonl`×1
- `project-src`: `tests/conformance/tools/plan_rename_type.x64-linux.expected.jsonl`×13, `tests/conformance/tools/plan_rename_type.x64-windows.expected.jsonl`×13, `tests/conformance/tools/nested_instance.x64-linux.expected.jsonl`×9, `tests/conformance/tools/nested_instance.x64-windows.expected.jsonl`×9, `tests/conformance/tools/uses_type.expected.jsonl`×9, `benchmarks/baseline/results/context-linux-d948.json`×8†, `benchmarks/baseline/results/context-windows-d948.json`×8†, `src/main.e`×8‡
- `project-lib`: `src/main.e`×2‡, `src/tool.e`×2‡, `tests/conformance/reject/safety_pushed_twice.expected.jsonl`×2, `tests/conformance/reject/safety_codec_decode_resource.expected.jsonl`×1, `tests/conformance/reject/safety_codec_encode_resource.expected.jsonl`×1, `tests/conformance/reject/safety_copy_toolchain.e`×1, `tests/conformance/reject/safety_copy_toolchain.expected.jsonl`×1, `tests/conformance/tools/arena_layout.expected.jsonl`×1

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
