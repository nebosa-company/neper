# L065 — Complete native code editor in e.ui.code_editor (CodeMirror 6 / JustCode parity)

| field | value |
|---|---|
| category | library / UI |
| score | 0.00 of 1 |
| queue position | 66 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only: docs/code-editor-plan.md defines 18 ordered work packages and 247 undelivered capabilities in docs/widget-plan.json phase P7, including all 35 JustCode language modes and the September 2026 TIOBE top 30: 51 required modes/adapters in total. C# and Java remain required; 16 additions include PHP, Visual Basic .NET/classic, Fortran, Scratch project support, Ada, Objective-C, COBOL, Julia, Ruby, Perl, SAS, MATLAB, Caml, Prolog and GML. Reuse existing UI/text/scene services and shell owners. P7 remains next-release work; its prerequisites and acceptance checks are in the plan. Score is the fraction of P7's 247 components delivered with evidence; full completion also requires every package acceptance check. D1807 records this backlog entry; D1809 adds TIOBE coverage.

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] document storage and atomic transactions
- [ ] native input/IME/accessibility
- [ ] Unicode/multicursor editing and history
- [ ] virtualized layout
- [ ] syntax and semantic highlighting
- [ ] gutters/decorations/bookmarks/folding
- [ ] complete language packs
- [ ] search/replace
- [ ] completion/snippets/inline suggestions
- [ ] diagnostics/spelling
- [ ] LSP and navigation/refactoring
- [ ] themes/extensions/keymaps
- [ ] diff/merge/minimap/collaboration
- [ ] tab/split/file/host integration
- [ ] parity, platform and performance evidence

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
