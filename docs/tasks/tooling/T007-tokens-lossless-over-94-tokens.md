# T007 — tokens, lossless over 94 tokens

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.95 of 1 |
| queue position | 41 of 53 (only position 1 is eligible for the next session; see README) |
| difficulty | low — rated for a small model; a whole checklist line per session is realistic |

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

> `tokens [--json] [--path VIRTUAL.e] FILE` (D227): the section 1 header, a `token` record per token with its registry kind, lexeme, span and leading trivia, a `diagnostic` before each `INVALID` token whose lexeme is the base64 object, and the `result`; every record validates against docs/schemas/neper-v1.schema.json, the trivia and lexemes concatenate back to every byte of the compiler's own sources, and tests/conformance/tokens pins every_kind (93 of the 94 kinds) and hostile (BOM, CRLF, a tab, unterminated literals, invalid UTF-8 inside a comment) byte for byte; `-` reads stdin under `--path` (D289)

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

Notes:

- The evidence names no gap: the 94th token kind is not pinned by `every_kind` (93 of 94). Find which kind is missing by diffing the registry in `docs/grammar.ebnf` against the golden in `tests/conformance/tokens/`, add it, and re-pin.

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D227` — `tokens --json` and `parse --json`, and the first of the conformance corpus (`docs/decisions.md:4120`)
- `D289` — `-` reads stdin on `tokens`, `parse` and `fmt` (`docs/decisions.md:5695`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `INVALID`: `lib/e/os.windows.e`×15‡, `tests/conformance/tokens/hostile.expected.jsonl`×7, `src/tool.e`×2‡

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
