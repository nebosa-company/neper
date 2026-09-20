# C062 — Merged error table

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.75 of 1 |
| queue position | 18 of 51 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

One merged error table per image: every module's `error` names get one identity across the whole program, built in `main.e` before lowering, so a trap and `neper test` can name an error from any module (spec §7, §11 Trap protocol).

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> src/error_table.e builds it and push_err expands against it; `main`'s failure line reads it in the binary (D199): a root `main` returning anything but `ok` reaches a synthesized `neper_report_failure`, one compare per declared error of the program, which writes `error: <qualified name>` to stderr through the runtime's own write before the exit with code 1 -- link/failure_line pins the module's own error and one of `e.os`'s on both platforms

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the trap protocol's use of it and `neper test`

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D199` — `main`'s failure line is written from a synthesized error table (`docs/decisions.md:3630`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `e.os`: `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×118, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×117, `src/resolve.e`×36†, `lib/e/os.linux.e`×8†, `src/check.e`×8‡, `lib/e/fs.e`×7, `lib/e/proc.e`×6, `tests/conformance/tools/context_moves.x64-linux.expected.jsonl`×6

## Existing fixtures

- `tests/selfhost/fixtures/link/failure_line`

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
