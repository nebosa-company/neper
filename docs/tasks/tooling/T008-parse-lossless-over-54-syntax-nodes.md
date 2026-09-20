# T008 — parse, lossless over 54 syntax nodes

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.97 of 1 |
| queue position | 42 of 53 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> Lossless `tokens`/`parse` output over grammar revision 1's closed 94-token and 54-syntax-node registries in `grammar.ebnf`: trivia, BOM, physical newline spelling, invalid-byte capture, `ErrorNode` recovery and reconstruction of every original byte. Spans retain original byte offsets plus normalized one-based scalar and UTF-16 columns

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `parse [--json] [--path VIRTUAL.e] FILE` (D227): the token records, one `syntax` record whose root lists the top-level nodes with kind, span, token range and ordered `{node}`/`{token}` children, a `diagnostic` where the parser stopped, and the `result`; schema-valid, and tests/conformance/parse pins every_kind and recovery byte for byte. Recovery past the first error was already in the tree -- an `ErrorNode` per failed statement or declaration, the parse going on -- and now every failure is a diagnostic at its own token, not only the first (D275, parse/two_errors pins three); a soft delimiter still open at a column-0 declaration keyword is E-SYNTAX-0012 at the opener, naming the keyword that ended it, in the parse stream, the check stream and the human line (parse/barrier, reject/barrier); `-` reads stdin under `--path` (D289)

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D227` — `tokens --json` and `parse --json`, and the first of the conformance corpus (`docs/decisions.md:4120`)
- `D275` — Every recovered failure is a diagnostic, and a barrier crossing is E-SYNTAX-0012 (`docs/decisions.md:5389`)
- `D289` — `-` reads stdin on `tokens`, `parse` and `fmt` (`docs/decisions.md:5695`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `ErrorNode`: `src/main.e`×18‡, `src/parse.e`×6†, `tests/conformance/parse/two_errors.expected.jsonl`×2, `src/check.e`×1‡, `src/resolve.e`×1†, `src/syntax.e`×1, `src/tool.e`×1‡, `tests/conformance/parse/barrier.expected.jsonl`×1

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
