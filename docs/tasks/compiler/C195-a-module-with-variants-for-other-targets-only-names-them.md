# C195 — A module with variants for other targets only names them

| field | value |
|---|---|
| category | compiler / WebAssembly |
| score | 0.00 of 1 |
| queue position | 102 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5682 (D5662's open point). Needs nothing. Build: `project.select_source` (project.e:376) answers a new `NoVariant` with the suffixes it saw when the directory has variants of the stem for other arches or oses and none for this target and no plain file; graph.e's fallback from one root to the other (graph.e:798, :805) treats it as ModuleNotFound and keeps the first root's suffixes; E-MODULE-0001 then reads `use plat` has variants for linux, macos and windows and none for wasi (sorted, `and` before the last; an arch variant said the same way). Acceptance: (1) the 17 refusals D5662 lists under `use plat`, `x.*.capi` and `x.oracle.mysqlclient` show the new text in the refused column of `scripts/wasm-sweep.sh`; (2) a conformance case beside `reject module_missing` in tests/conformance/reject, run by run.sh and run.ps1 (check_suite_parity.py passes), pins the text, and module_missing keeps its own; (3) v2 == v3, and no other expected diagnostic changes

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `project.select_source`: `src/graph.e`×3†, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.neperos.e`×1, `lib/e/os.wasi.e`×1†, `lib/e/os.windows.e`×1‡, `lib/e/os/shell.windows.e`×1‡, `src/main.e`×1‡
- `x.oracle.mysqlclient`: `lib/x/oracle/mysql.e`×1
- `scripts/wasm-sweep.sh`: `scripts/wasm-sweep.sh`×3, `scripts/run-wasm.mjs`×1

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
