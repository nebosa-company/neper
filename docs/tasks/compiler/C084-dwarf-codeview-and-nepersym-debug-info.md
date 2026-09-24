# C084 — DWARF, CodeView and .nepersym debug info

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.35 of 1 |
| queue position | 17 of 45 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> Debug info on the default path (spec §13, D9, D64): the fixed DWARF (ELF/Mach-O) and CodeView (PE) locals-and-types subset with `DW_OP_fbreg` locations, so `lldb`, `gdb`, WinDbg, `lldb-dap` and `codelldb` show locals from here — VS Code and Zed debugging with zero adapters of our own. Debug builds do not inline; `--g` adds the subset and `inlined_subroutine` records to a release build

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The symbol and line table (D206, D209): after the code, per function its start, length and `module.function` name, and its line rows -- a code offset, a line and a file wherever the line changes, inlined bodies naming their own file -- which the trap protocol reads for its backtrace; artifacts carry the rows in a Lines section and the artifact path reproduces the table byte for byte

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] DWARF or CodeView for a foreign debugger
- [ ] a named `.nepersym` section rather than the bytes after the code
- [ ] variables

Notes:

- Score 0.35 with three large deliverables. Take them in the roadmap's order: the DWARF locals-and-types subset on ELF first (`lldb`/`gdb` must show locals), CodeView on PE second, a named `.nepersym` section third. Each is its own session series.

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D206` — A trap ends with its backtrace, from a symbol table after the code (`docs/decisions.md:3755`)
- `D209` — The line table: every frame of a backtrace has its file and line (`docs/decisions.md:3821`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `module.function`: `src/tool.e`×6‡, `src/em_link.e`×2†, `src/lower.e`×2‡, `src/nir.e`×2†, `lib/e/debug.e`×1, `src/check.e`×1‡, `src/codegen_x64.e`×1‡

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
