# G008 — custom painters + row style + conditional formatting rules

| field | value |
|---|---|
| category | library / UI |
| score | 0.70 of 1 |
| queue position | 80 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> D3917: e.ui.gridrules (cell-is, text, blank, above/below, top/bottom with ties and percent, duplicate/unique, 2/3-colour scale, data bar, icon set; per-field priority, whole-row, refresh by column version) and datagrid set_rules rendering (fill, bar, icon, ink, bold); ui_gridrules fixture incl. 150,000 rows vs own count, ui_datagrid section 14 pixel probes, mutations caught (exit 83, 351); v5 cardgrid uses a data bar and a top-price rule; custom painters and row_role were G006. Open: rules manager UI, expression rules, MTG legality/foil painters, Linux run.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

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
