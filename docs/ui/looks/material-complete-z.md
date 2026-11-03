# Round 84 lane z: Android (Material, MaterialDark) rows below ready

Goal (maintainer, "complete all looks"): raise every Material and MaterialDark row below `ready` to `ready` where the row can honestly satisfy the decision: every cell drawn and legible, the drawing follows cited M3 tokens or is built from measured M3 parts, and my own comparer measured it. Own scratch comparers (python, numpy, PIL, not committed) read the committed 1x PNGs. The briefs named in the task (`round70-flutter-compare.md`, `round63-fixes.md`, `round72.md`) do not exist on disk, so the rules come from the task text, `audit.md` (Audit 42), `flutter-compare-m/n/q/s/u/w.md` and `scripts/render_looks.py`.

Result. The 30 Delphi-equivalent controls: Android Light and Dark 85.3 % before (19 matched, 11 review), 90.7 % after (4 rows to ready, 7 left at review). The 66 platform-idiom rows (extras) were not touched: none of them is raised here.

## Root cause found: shared keys hid every hover in three grid sheets

The runtime resolves `widget.interaction(key)` to the first element carrying that key. data_grid (four grids, row keys 1 to 6 in each), tree_list (three trees, node keys 1 to 6) and vertical_grid (three grids, `101 + index`) put the same keys in every cell, so the pointer driven into the "hovered" cell lit the first cell's row or nothing. `Cell` apps must build unique keys (`looks.e` says so for control keys; row keys of a table are keys too). Fixed in the three sheet apps by giving each grid its own row keys (a `base` in the high bits). Only `examples/looks/material_*.e` changed, so only Material and MaterialDark pictures move.

## Raised to `ready` (Light and Dark)

### data_grid (`material/data_grid.png`, `data_grid_select.png`)
Measured, light then dark: header 56 high (rows 40 to 95), row pitch 52, 52, 52, 52, 52, divider 1 px outline-variant cac4d0 / 49454f exact, hovered row on-surface 8 % over surface ece5ed / 252229 exact, selected row secondary-container e8def8 / 4a4458 exact, body text 16.2:1 / 14.3:1 on surface, on-secondary-container 13.2:1 / 7.2:1 on the selected row. M3 has no data table; the 52 dp row and 56 dp header are the Material data table sizes (not an md.comp token), colours and layers are M3 baseline tokens. All four cells viewed at 1x and 1.5x, light and dark. The select-mode sheet got a taller cell (424, was 380) so its last row is no longer cut; its Focused cell shows the hover layer, not a ring (recorded).

### tree_list (`material/tree_list.png`)
Measured: row pitch 48 x 5, dividers outline-variant, selected e8def8 / 4a4458, hovered 8 % (ece5ed / 252229), focused 10 % (e8e1e9 / 29272d), header surface-container f3edf7 / 211f26, all exact. 48 dp is the md.comp.menu list-item height and the touch target. Viewed light 1x and dark 1.5x (light 1.5x and dark 1x are the same code at another scale, not viewed).

### label (`material/label.png`)
Cap height measured per role against Roboto's 0.711 em at the M3 type-scale size: Headline medium 28 sp 20 px (19.9), Headline small 24 sp 17 (17.1), Title medium and Body large 16 sp 12 (11.4), the 14 sp roles 11 (10.0), the 12 sp roles 9 (8.5), Display small 36 sp line 28 and Title large 22 sp line 17 whole-word boxes (include the i dot). One to two pixels over throughout is the anti-aliasing row and hinting; identical in the dark twin. Contrast: 15 of 16 cells 4.5:1 or better; the Disabled cell is on-surface at the 38 % M3 content level (exempt). Viewed light 1x and dark 1.5x.

### spin_edit (`material/spin_edit.png`)
M3 has no number field. Built from measured parts: outlined field 96 x 56 (bbox of the 79747e outline: 96 x 56), outline 1 px, 3 px focused, error b3261e, disabled at the 12 % / 38 % split, and the 40 dp icon buttons that are already `matched` (hover 8 %, pressed 10 %). All 12 cells viewed at 1x and 1.5x, light and dark. The offset of the hovered-plus and pressed-plus cells is intentional (the pointer must land on the button).

## Left at `review`, with the reason

| Row | Why |
|---|---|
| vertical_grid | Hover fixed (shared keys; and a property row has no pointer target, so the cell now hovers the General heading). Not uniform: the last group's rows are 34 dp apart, the first group's 26 (56 in the General-shut cell) because the library stretches them with the cell height. Changing `options.height` or the cell height moved the pitch, not the cause. |
| date_edit | Added `date_picker_day_hover`, `_day_pressed`, `_day_focus` (selected day at the 10 % layer, via the new `Drive.Tabs`) and `date_picker_docked`. The docked calendar is 312 wide with a 40 dp day pitch where the M3 docked container is 360 wide: a measured deviation, not fixed. `date_input.png` re-rendered: byte for byte as committed, it is not stale in this checkout. |
| image_combo_box | The disabled cell is the whole field at 38 % (`control.image_select`), so its outline is 38 % where the M3 token is 12 %. Library change not made. |
| status_bar | Pressable panel hover works (`f3edf7` to `e1dbe5` at the pointer). The Narrow cell hard-clips its message ("All: 120") where `status_bar_of` promises an ellipsis; wrapping the clip box in a flex and in a padded node left the picture unchanged. |
| hint | `material_tooltip.e` on this master draws the rich plate at the top of its cell and does not reproduce the committed `tooltip.png` (91 000 px differ): a later library change moved it. The half pixel edge could not be re-measured; committed picture left. |
| scroll_bar | The differences from Flutter's Android scrollbar (hover and drag 8 wide against 4, one thumb colour, 32 px against the 48 px minimum) live in the runtime's shared scroll thumb used by every look. No M3 token to decide, no hook added. |
| splitter | M3 has no splitter; the handle and sash were not measured against any token. Viewed light only. |

## Not done

The other review rows of the platform-idiom set (list, key_value_editor, time_picker digits and scrim, range_slider notes, menu_bar and the rest) were not examined in this lane: the same duplicate-key hover defect is likely in other multi-cell sheets that drive a hover on a keyed row, and has not been searched for. The key_value_editor Focus cell draws no focus ring on this master (it is byte for byte the committed picture; a Material-only `FocusHover` variant removed the hover instead of adding a ring and was reverted).

## Code

- `lib/e/ui/looks_z84.e`: `stops(n)` and `walk(harness)` (n Tab presses, then the pointer leaves). Hook: `Drive.Tabs` and one line in `looks.drive_cell`. No other look draws a cell with it.
- `examples/looks/material_data_grid.e`, `material_tree_list.e`, `material_vertical_grid.e`: unique row keys; vertical_grid hovers the heading.
- `examples/looks/material_date_picker.e`: `x` renders the day hover, pressed and focus sheets; `x y` the docked sheet.

## Regression

Re-rendered after the hook: button, checkbox, combo_box, label, memo, data_grid, tree_list, vertical_grid, status_bar, splitter, scroll_bar, spin_edit, cup_data_grid, cup_label, cup_tree_list, linux_data_grid, linux_tree_list, material_label, material_scroll_bar, material_spin_edit, material_status_bar, material_splitter, material_list, material_image_combo_box. `git status` after: only Material and MaterialDark pictures of data_grid, tree_list and vertical_grid and the new date_picker sheets differ; every Windows, Linux, Neper and Cupertino picture is byte for byte as committed.

## Batch 2 (the coordinator's list)

Android Light and Dark: 90.7 % before this batch, 98.7 % after (10 ready, 19 matched, hint at review).

Raised to `ready`: status_bar, image_combo_box, vertical_grid, date_edit, scroll_bar, splitter. Evidence per row is in its overlay note (`status.d/*-r84z.json`).

Library changes, all Material only (the Windows, Linux, Cupertino and Neper pictures of every one of the 251 sheet apps were re-rendered with them and are byte for byte as committed, except Cupertino `hint`, which competes with `cup_tooltip.e` as audit 42 recorded; restored):
- `navigation.e`: a squeezed status message is a Word-wrapped single line so its ellipsis draws.
- `control.e` and `looks_z84_edge.e`: the Android disabled image combo box's outline is on-surface 12 %.
- `widget.e`: the scroll thumb on the Material look is 4 wide in every state, 48 shortest, 60 % on drag.
- `overlay.e`: the Android docked calendar is 360 wide with 48 dp day cells.

Matched or ready rows whose pictures moved because of those changes (viewed): `date_range_picker_open` (docked calendar now 360 wide; the row stays matched, an audit may want to re-measure it), `memo`, `scroll_area`, `terminal_view` (scroll thumb 4 wide, 48 shortest).

Findings worth keeping:
- A property grid's rows are 56 dp minimum and shrink with a fixed cell: the uneven 26 / 34 pitch was the sheet, not the control. Other sheets with a fixed cell height around a min-height control may show shrunk rows.
- Hint: a 310 px cell no longer fits the rich tooltip below its anchor; cell is now 400 and the long sample two lines. Stays review: the plate's left edge column is still a partial pixel.

Duplicate-key scan (all 251 apps, a temporary detector in `looks.render_sheet`, not committed). Sheets reporting repeated keys after the fixes: Material-relevant: calendar (4), font_picker (5), h_pull_to_refresh (1), surf_table (15, 30), terminal_view (27), material_progress (10), b70_dialogs time_picker_dial (3), material_tree_list (3, hover works). Shared apps also draw other looks: calendar, font_picker, h_pull_to_refresh, surf_table, terminal_view, b70_dialogs, progress_bar, data_grid, tree_list, data_grid_dialogs, choices_filter, dialog_message, check_list_box_dialog, native_dark2 and the Cupertino and Linux apps cup_vertical_grid, linux_tree_list, linux_page_control, linux_toolbar_button. Repeated keys inside one control (calendar, progress) are not cell-sharing; in calendar the hover shows. pull_to_refresh's hover cell shows no hover and font_picker's hover lands at the bottom of its list: not fixed, no other look's picture was changed.

## Not done

The 66 platform-idiom rows were not raised in this batch. Viewed and found defective: search_field (the invalid cell is drawn like the filled one), large_title (the disabled-action cell shows no action), split_button (the menu-open cell shows no open menu), speed_dial (no open dial), pull_to_refresh (no hover), font_picker (hover off the list). key_value_editor and time_picker were viewed earlier and not changed. None of them is raised.
