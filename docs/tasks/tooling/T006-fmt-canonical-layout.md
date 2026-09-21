# T006 — fmt canonical layout

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.98 of 1 |
| queue position | 36 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> `neper fmt` implements the complete canonical-layout contract: LF/UTF-8 output, four-space indentation, deterministic 100-scalar wrapping, preserved comments and literal spelling, sorted eligible `use` declarations, exact failure behavior, idempotence and golden output

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `fmt-file PATH --json` (D234): one `formatted` record whose text is the canonical layout -- four-space indent by brace depth, one space around binary and assignment operators and after comma and colon, no space inside delimiters or around `.`/`..` or before a call or index list, slice and array element types and prefix operators glued, comments preserved with a trailing comment one space out, blank runs collapsed to one with none at a block edge, a single final newline; tests/conformance/tools/fmt.e is already canonical, so the golden pins idempotence too; `--check` reports E-FORMAT-0001 at the first non-canonical byte and exits 1 (D244). One space inside a brace pair on a line -- `{ ret ok }`, `struct { a: i32 }`, `Pair { a: 1i32 }` -- and none in `{}` (D255), pinned by tests/conformance/format/layout.e, a deliberately mangled source whose canonical side is the golden; `fmt-file PATH` without `--json` prints the canonical text itself. What `fmt` refuses is diagnostics in every form (D257): each invalid token under its lexical code and a comment between an attribute and its declaration as E-FORMAT-9999, the stream ending in a result that exits 1 with no `formatted` record, the plain form printing the human lines to stderr. Three more of section 6's rules (D273): exactly one blank line separates top-level declarations -- an attribute, a `///` or `//` line, or a `use` before another `use` leads into the next one rather than separating it -- an empty block is `{}`, and `else` follows `}` on the same line; the format fixture pins all three. The contiguous comment-free `use` block at the start of a file sorts by module path then alias (D274), pinned by the fixture. A bracketed list -- a call's or signature's `(...)`, a type body's `{...}` -- that would exceed 100 columns from where it opens breaks after the opener, one element per line four columns in with a trailing comma, the closer back on the opener's indent; one that fits is joined onto one line with no trailing comma; a grouping `(` or any `[` only ever joins, since a trailing comma inside is not syntax, and a list with a comment inside is left as written (D277). A member literal after a keyword keeps its space (`case .Red`, not `case.Red`) and a `case` or `default` label sits at its `switch`'s indent, the statements under it one level in (D284). Every source of the compiler and the library formats idempotently, and a compiler built from its own formatted source agrees with the goldens. An aggregate literal's body is a list too (D285): a `{` after a PascalCase name outside an `if`/`while`/`for`/`switch`/`when`/`else` header or a signature's `-> Type` is the parser's own literal rule, so `Pair { a: 1, b: 2 }` joins and a wide one breaks one field per line. A run of attribute lines sorts by attribute name (D286). `fmt -` reads stdin and writes only the canonical source to stdout, `--json` the `formatted` record under the `--path` identity (D289). `fmt FILE` formats the file in place, writing nothing when it is canonical, and `fmt` with no operand formats every `.e` under the project's src/ and lib/ in byte order, `--check` naming each non-canonical file as an E-FORMAT-0001 line and exiting 1 (D295); both suites format a one-file project and a copied file to the corpus's canonical text

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] one statement per line
- [ ] raw-string delimiter minimization
- [ ] a `--json` stream over a project

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D234` — `fmt --json` emits the canonical layout (`docs/decisions.md:4228`)
- `D244` — `fmt --check` reports E-FORMAT-0001 (`docs/decisions.md:4492`)
- `D255` — The format corpus, and a space inside a brace pair (`docs/decisions.md:4841`)
- `D257` — What `fmt` refuses is diagnostics, in every form (`docs/decisions.md:4879`)
- `D273` — One blank line between declarations, `{}`, and `else` beside `}` (`docs/decisions.md:5359`)
- `D274` — The leading `use` block sorts by module path, then alias (`docs/decisions.md:5378`)
- `D277` — Lists break at 100 columns, one element per line, and join when they fit (`docs/decisions.md:5435`)
- `D284` — A second fixture per corpus root, and what writing them found (`docs/decisions.md:5600`)
- `D285` — An aggregate literal's body is a list (`docs/decisions.md:5615`)
- `D286` — Attribute lines sort by name (`docs/decisions.md:5627`)
- `D289` — `-` reads stdin on `tokens`, `parse` and `fmt` (`docs/decisions.md:5695`)
- `D295` — `fmt FILE` formats in place; `fmt` alone formats the project (`docs/decisions.md:5792`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `formatted`: `src/tool.e`×15‡, `benchmarks/metamorphic/metamorphic.py`×8, `src/main.e`×8‡, `lib/e/ui/control.e`×7‡, `scripts/build-docs-pdf.py`×3, `benchmarks/metamorphic/format_tree.py`×2, `scripts/render_module_apis.py`×2, `benchmarks/llm_edit/neper_advantage_matrix.md`×1

## Existing fixtures

- `tests/conformance/tools/fmt.e`
- `tests/conformance/format/layout.e`

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
