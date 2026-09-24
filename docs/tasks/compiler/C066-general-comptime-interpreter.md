# C066 — General comptime interpreter

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.85 of 1 |
| queue position | 15 of 46 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> Compile-time interpreter for `const` and `[...]` arguments — to spec §9's promise that any function is callable: structs, slices, strings and the arena as interpreter memory (D218–D222 stop at integers, bools and arrays). Then `neper eval EXPR`: the expression parsed as a `const` initialiser, folded by that interpreter and printed — no codegen, no link, and the comptime ceiling (no I/O, externs or threads) by design. Not a runtime interpreter (D470)

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> A `const` initialiser may call a function (D218): the interpreter walks the callee's syntax tree with integer and bool values -- locals, assignment and the compound forms, `if`, `while`, `break`, `ret`, every operator, checked casts, constants, and calls to other such functions in any module -- under the section's ten-million-step budget, and a call that reaches anything else, or runtime state, is refused under E-COMPTIME-9999 naming the constant and what it reached (link/comptime_call, check/comptime_call_runtime, check/comptime_call_budget). A call stands in an array length and a `[...]` argument the same way (D219), and a `when` condition that is not a question about the target is a bool it evaluates (D220); an array local of integers or bools -- `zero`, indexed reads and writes, `.len` -- and `for` over a range run in the frame (D221, a sieve in link/comptime_call). A `const` may be a bool -- `true`, a comparison, `&&`, `||`, `!`, or a call -- and a constant that reaches a call through another is put off until the signatures exist rather than refused (D222); one a type asks for before them is refused with the reason (check/comptime_call_in_type). An `if` whose condition is constants alone -- a comparison, `&&`, `||` over constants, literals and their operators, no local and no call -- is settled by the same interpreter (D500), the arm not taken no code in the checker and the lowering alike, and a `phase` record each; `fold_const` pins two folds and a branch over a local. Before it: integer const folding, and a branch settled by one `meta` question. link/comptime_branch walks `meta.fields` with arms that do not type check for each other's field types, and recurses on `meta.element_type` with the guard arm as its base case -- neither could be written before, and both are what a codec over a struct is (D138). `mem.size_of[T]()` on a scalar folds the same way (D144), which is what lets one generic `load` in e.bytes hold a bitcast for each float width with the wrong one gone. The condition still has to be a `meta` or size question compared against a constant: an `if` over an arbitrary comptime expression wants the interpreter this does not have

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] structs, slices
- [ ] the arena as interpreter memory
- [ ] an array across a call
- [ ] meta-only calls in a body

Notes:

- Order matters: the evidence says 'Before it: integer const folding, and a branch over a local' are done; next is structs, then slices, then strings, then the arena as interpreter memory, then an array across a call, then meta-only calls in a body. Roadmap backlog 'neper eval EXPR' (D470) waits on this item.

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D138` — a branch a `meta` question settles has one arm, and the other is not code (`docs/decisions.md:2142`)
- `D144` — `e.bytes` needs the foundation layer, and one generic `load` needs `size_of` to fold (`docs/decisions.md:2375`)
- `D218` — A `const` initialiser may call a function (`docs/decisions.md:3992`)
- `D219` — A call in an array length or a `[...]` argument (`docs/decisions.md:4015`)
- `D220` — A `when` condition through the interpreter (`docs/decisions.md:4026`)
- `D221` — Array locals and `for` over a range in the interpreter (`docs/decisions.md:4036`)
- `D222` — Bool constants, and a calling constant put off rather than refused (`docs/decisions.md:4050`)
- `D500` — An `if` over constants folds (`docs/decisions.md:10694`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `.len`: `src/main.e`×542‡, `src/check.e`×333‡, `src/tool.e`×309‡, `lib/e/ui/control.e`×173‡, `src/em.e`×168‡, `lib/e/fmt/json.e`×154†, `lib/e/os.linux.e`×145‡, `lib/e/algo/sketch.e`×139†
- `fold_const`: `tests/conformance/tools/fold_const.expected.jsonl`×5
- `meta.fields`: `src/check.e`×6‡, `lib/e/fmt/asn1.e`×4, `lib/e/fmt/bson.e`×4, `lib/e/fmt/csv.e`×4, `lib/e/fmt/msgpack.e`×4, `lib/e/fmt/ini.e`×3, `lib/e/fmt/json.e`×3†, `lib/e/text/template.e`×3
- `meta.element_type`: `lib/e/simd.e`×34, `src/check.e`×5‡, `scripts/check_module_surfaces.py`×1, `src/parse.e`×1†

## Existing fixtures

- `tests/selfhost/fixtures/link/comptime_call`
- `tests/selfhost/fixtures/check/comptime_call_runtime`
- `tests/selfhost/fixtures/check/comptime_call_budget`
- `tests/selfhost/fixtures/link/comptime_call/src/main.e`
- `tests/selfhost/fixtures/check/comptime_call_in_type`
- `tests/selfhost/fixtures/link/comptime_branch`

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
