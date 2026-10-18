# G006 — e.ui.datagrid v1: bands, footer, group rows, filter row, navigator, indicator, preview, no-data

| field | value |
|---|---|
| category | library / UI |
| score | 0.95 of 1 |
| queue position | 78 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Proposed by docs/grid.md section 9 (MTG Studio v3 migration grid, 150k records, DevExpress TcxGrid parity; measured Delphi baselines in section 6.1). Design: grid.md section 5, mapping and acceptance rows: section 7. Acceptance: pixel-level offline screenshot fixtures (per neper offline UI screenshot recipe); keyboard/pointer fixtures. DONE in lib/e/ui/datagrid.e + tests/selfhost/fixtures/link/ui_datagrid (D3910-D3915; origin D2367-D2372): header with sort indicator and resize/reorder, virtual body over the grouping visible list, group rows with summaries, footer, no-data text, typed cells, custom cells (application builds the node; v5 paints mana badges), row roles, filter row (above the header), bands, row indicator, navigator, in-place editing (typed commit, invalid keeps editor, null, dictionary growth, Tab/Shift+Tab/Escape), preview row (table detail), column hide and move, layout save/load (widths, order, hidden, sort, flags, filter texts; unknown or repeated entries tolerated), pixel probes (band fill, selected-row fill, identical frames). Fixture: about 190 checks through the UI harness, 25 mutations caught, and the v5 sample (D:epos\mtg.studio.src5\cardgrid) running 150,000 rows. NOT DONE: whole-frame golden images (the harness has no fonts; glyph goldens need a font decision), a column chooser window, the filter row below the header, a Linux run.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Existing fixtures

- `tests/selfhost/fixtures/link/ui_datagrid`

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
