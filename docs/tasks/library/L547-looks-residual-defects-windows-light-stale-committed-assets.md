# L547 — Looks residual defects: Windows Light, stale committed assets, harness bugs and open rows

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 477 of 477 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened 2026-11-19 from the handover fold; L165 holds the headline score. Acceptance: each lead is fixed with a re-render that matches the reference, or struck. Windows Light: group rows 1 px high; round 38/40 footer constants may be wrong against the crisp 1:1 refs; check tiles, expander bitmaps and v3 artwork not re-derived; a one-pixel column at x 498 in data_grid_main; stale data_grid_dialogs_sort PNG. Stale assets: neper-dark/menu_bar-open.png (+1.5x) need regenerating; gen_winmenuicon.py needs a guard before rerun; radio_dialog Options crop and native_dark4 compare to old captures; combo_box_flat greyscale vs committed ClearType; Neper disabled selected rows draw no fill. Open rows: Windows dialog 12 of 14 bodies composed (windows-complete-x.md round 88), 32 of 119 cells pass strict compare, no captured states for caption pressed, resize or disabled, message-box bitmaps and task dialog not drawn; deviations Deck Legality memo Tahoma 13 vs Verdana 11, About skull posterised, older bodies not re-fitted; Shortcuts icon residue 4 px. Cupertino idiom rows (22 at review: autocomplete, banner, breadcrumbs, carousel, color_picker, dial, dock_panel, font_picker, grid_view, image, key_caps, list, navigation_rail, navigation_split, pagination, range_slider, scroll_area, shortcut_recorder, terminal_view, wizard, reorderable_list, pull_to_refresh), never-viewed rows (notification_list, page_view, schedule, flow_editor, stepper, sheet; schedule, flow_editor, sheet and hint are also open Material rows), Cupertino date_edit limit. Material: markdown_view two-word link hover gap; table deviations (16 dp margin vs 24, Type column left aligned). Harness bugs: cells sharing keys make the runtime resolve the pointer to the first element with that key; a pointer aimed at a cell centre lands 30 px off small controls; for stale committed PNGs restore the committed bytes unless explained.

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
