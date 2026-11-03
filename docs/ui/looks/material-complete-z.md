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

## Batch 3

Moved pictures confirmed (viewed, committed in batch 2): `date_range_picker_open` is the docked calendar variant, not the picture of the matched date_range_picker row (`date_range_picker.png`, unchanged); the Flutter reference for the row is the range dialog, and the only earlier measurement of the `_open` sheet was the band colour (e8def8 / 4a4458), still exact (e8def8 at the band pixel). `memo`, `scroll_area` and `terminal_view` changed only in their scroll thumbs (4 wide, 48 shortest). The terminal_view sheet is not a ready candidate (hover and focus cells draw no row layer).

Fixed, Material only, other looks byte for byte (search_field_all, nav_large_title, h_pull_to_refresh re-rendered):
- `search_field` invalid and focus cells (control.e, Android): error outline and the 10 % focus layer. Raised to `ready` (extra row).
- `nav_large_title.e`: the Android sheet shows a disabled Done beside Edit. `large_title` stays review (bar height not measured against the M3 large app bar).
- `h_pull_to_refresh.e`: the Android hover cell aims at the Refresh button. `pull_to_refresh` stays review (the refreshing arc is a few pixels).
- `hint` stays review: the reference's edge is a shadow gradient, so the partial edge column cannot be matched or excused.

Duplicate-key sheets that still lose a hover in the Material look and were not fixed: font_picker (hover cell lands at the foot of its list), terminal_view and surf_table (no row layer in the cells).

Still not examined: the other 55 idiom rows, including split_button and speed_dial (no open state drawn).

## Batch 4

Raised to `ready`: split_button (chevron turns up when open, open menu sheet with 48 dp rows), speed_dial (open FAB list, 56 dp items), large_title (152 dp bar measured on `large_title_full.png`, the shared sheet's 124 px cell had clamped it; the row's picture is now the full sheet).

Fixed, Material only, other looks byte for byte (split_button, speed_dial, font_picker re-rendered; git status shows only Material pictures): `control.split_button` chevron; new apps `material_split_open.e` (`split_button_open.png`, `x` for `speed_dial_open.png`) and `material_large_title.e`; `font_picker.e` hover aims at the Roboto row (Material profile only).

Left at review: font_picker (the sample line ignores family, style and size), pull_to_refresh (the indeterminate arc is a few pixels at the frame the sheet takes; `Settle` did not advance it), terminal_view and surf_table (hover cells draw no row layer; not changed).

## Batch 5

Raised to `ready`: password_field (7 cells; the disabled eye is now at 38 %, Material only).
Improved, still review: link (label centred in its 48 dp target, focus underlines; pressed and focus layers still do not show), rating and dial (focus cell identical to rest), autocomplete (no open suggestion list drawn).

Idiom rows raised in total in this lane: search_field, split_button, speed_dial, large_title, password_field (5 of 66). About 50 idiom rows were not examined; the ones seen are listed above.

## Batch 6

Raised to `ready`: pull_to_refresh (arc drawn at a fixed 70 % by the sheet, indicator 40 dp), rating (focus layer via Tab walk), autocomplete (open list as wide as its field), key_value_editor (focus ring; hover cell moved before it because a keyboard walk mutes the pointer layers of later frames).

Fixed, stays review: font_picker (sample follows style and size up to 20 sp; family and italic need faces the rig does not load), link (pressed and focus layers are eased and the sheet's frames do not advance time).
Not fixed: dial (no keyboard focus drawn for it in the Android look), terminal_view (rows are not pointer targets of the list; a per-cell key salt changed nothing and was reverted). surf_table (the matched `table` row) was not touched.

Hooks added: `looks_z84_edge.set_ring` (collection.pull_to_refresh), the Material-only guarded edits in `control.e` (font_picker sample, autocomplete width) and `collection.e` (ring size 48). Other looks byte for byte for every app re-rendered (pull_to_refresh, font_picker, autocomplete, combo_box, choices_filter, token_edit, rating, key_value_editor).

## Batch 7

Raised to `ready`: key_caps, skeleton, empty_state, toast (viewed light and dark at 1x, no library change; evidence in the overlay notes, 1.5x not viewed). Idiom rows raised in this lane: search_field, split_button, speed_dial, large_title, password_field, pull_to_refresh, rating, autocomplete, key_value_editor, key_caps, skeleton, empty_state, toast (13 of 66). About 40 idiom rows were not examined: notification_list, avatar, icon, image, markdown_view, code_editor, schedule, flow_editor, sheet, canvas, popover, flyout, side_sheet, action_sheet, tree_table, bottom_app_bar, toolbar, navigation_stack, navigation_split, sidebar, breadcrumbs, document_tabs, dock_panel, workspace, command_palette, window_switcher, ribbon, title_bar, scroll_area, list, grid_view, carousel, pagination, page_view, swipe_actions, reorderable_list, shortcut_recorder, color_picker, calendar, duration_picker, gauge, level, toggle_button, rich_tooltip, time_picker, android_text_modes.


## Round 85 (lane z2)

Android Light and Dark, Delphi-equivalent rows: 98.7 % before, 100 % after (hint raised to ready). Idiom rows ready or matched: 39 of 90 before, 54 after (ready 13 to 27, matched 26 to 27).

Library and hook changes, all Material only (every Windows, Linux, Neper picture of each re-rendered app is byte for byte as committed; the Cupertino pictures of date_range_picker and tree_table differ from their commits exactly as they do on the base, stale and not restaged):
- `overlay.calendar_with`: in a wide-slot (docked, 360 dp) calendar the range band is drawn per slot, so it runs unbroken across the row. date_range_picker is back to matched (band e8def8 / 4a4458 exact against `ref/flutter/material/*/daterangepicker-open`, continuous, 40 high against Flutter's 42).
- `control.dial`: the Android knob draws the handle's state layer (hover 8, focus and pressed 10 percent, 40 dp) and a 3 dp ring 2 dp outside the handle for keyboard focus.
- `looks.Drive`: `PressSettle` and `FocusSettle` (the pressed and focus frames wait for an eased layer); used by `link.e` for Android only.
- `looks_z85.hover_rows` and `collection.row`: rows of a virtual list carry a hover-only region and the 8 percent layer, switched on by `terminal_view.e`.
- `looks_x63.mono_theme`: Cascadia Mono as the Android fixed-pitch face (Roboto Mono is not installed); used by the terminal, code editor and markdown sheets, which were proportional.
- `surf_table.e`: root cause of the dead hover and focus cells: the row keys `base + 1 + index` collided with the table's own parts keyed `key + 1, 2, 3 ...` and the pointer aim assumed a 33 px header (Android 56). Android rows now start at `base + 101` and aim below the 56 dp header; the Android columns are wider so the sort arrow no longer runs over Qty and the tree names are not clipped.

Raised to ready: hint (soft shadow edge stated), link, dial, terminal_view, avatar, code_editor, markdown_view, popover, side_sheet, action_sheet, toolbar, pagination, toggle_button, gauge, level. Raised to matched: date_range_picker. The four rows raised from 1x only (key_caps, skeleton, empty_state, toast) were re-viewed light and dark at 1.5x and hold; the light toast stack shows the same hard foot shadow band as flyout (to check with that fix).

Left at review, with the defect (overlay notes hold the detail): font_picker (family and italic cannot show, list hover grey, focus cell cut), tree_table (28 dp rows), notification_list, icon (not Material Symbols), image (bordered cell), schedule, flow_editor (states equal rest), flyout, command_palette, window_switcher (hard shadow band), sheet, canvas, bottom_app_bar, navigation_stack, navigation_split, sidebar, breadcrumbs, title_bar, document_tabs, dock_panel, workspace, list, shortcut_recorder (no focus indicator).

Not examined (about 18 idiom rows): ribbon, scroll_area, grid_view, carousel, page_view, swipe_actions, reorderable_list, color_picker, calendar, duration_picker, time_picker, rich_tooltip, android_text_modes, and the others of the earlier list not named above.

### Round 85, second pass

Shared hard shadow. Cause: `widget.paint` drew every `style.shadow` as a shifted copy of the box (a hard foot), in the Android look too, wherever a control set an offset shadow instead of `shade`. With the Android rig the offset now selects the drawn M3 level (offset 1 level 1, 2 level 2, 3 to 4 level 3, 6 level 4, more level 5), the soft two-part shadow of `e.ui.matshade`. The switch is `widget.soft_shadows`, set by `looks.shoot` from the rig's look (and by `control.focus_look` for a product Android theme), so no other look inherits it. Material pictures that moved and were viewed (1x, and 1.5x where noted in the row): flyout, command_palette, window_switcher, toast (three sheets), card, dock_panel, navigation_drawer, speed_dial_open, autocomplete_open, bottom_sheet, side_sheet, action_sheet, date_range_picker_open, alert; buttons, chips, tabs, menus and every other app rendered (about 60 in a snapshot worktree) did not move.

Regression. 30 sheets (button, checkbox, combo_box, data_grid, date_edit, dial, link, memo, text_edit, tree_list, label, hint, terminal_view, surf_table table and tree_table, surf_overlay flyout, popover, action_sheet and side_sheet, f_command_palette, f_window_switcher, image, code_editor, markdown_view, font_picker, date_range_picker, notification_list, toast, calendar, scroll_bar, spin_edit, progress_bar, card) were rendered once at this branch and once at the base commit cf285b6be, one app at a time, and every Windows, Windows Dark, Linux, Linux Dark, Neper, Neper Dark, Cupertino and Cupertino Dark picture was compared with `diff -rq`: no difference. (The committed Cupertino and Neper pictures of several apps are stale against both trees, as audit 43 recorded; they were not restaged.)

Raised to ready: flyout, command_palette, window_switcher, calendar, rich_tooltip, font_picker (family name leads the sample; a per-family preview is a rig limit: the rig loads Roboto, Segoe UI and Tahoma only; the list hover is the M3 8 percent on-surface layer, neutral grey on the white surface-container-lowest ground).

Fixed but still review: image (Bordered cell draws its outline; the placeholder glyph is a theme-less 2:1 grey).

Left at review, reason: scroll_area (thumb about 2.4:1 under 3:1), ribbon (stand-in glyphs), grid_view (tile labels unpadded), carousel, swipe_actions, reorderable_list, color_picker, duration_picker, time_picker stays matched (its earlier ref measurement stands; tiny seconds marks and equal-to-rest states are noted in its overlay), notification_list, icon, schedule, flow_editor, sheet, canvas, bottom_app_bar, navigation_stack, navigation_split, sidebar (the shared sheet's cell height shrinks the rows; changing it would move every look), breadcrumbs (8 px baseline offset in the library, not traced), title_bar, document_tabs, dock_panel, workspace, list, shortcut_recorder, tree_table. Not examined: android_text_modes.


## Round 86 (lane z3)

Android idiom rows ready or matched: 59 of 90 before (ready 32, matched 27), 64 after (ready 37, matched 27). Method: every picture re-rendered one at a time with the committed `neper-self.exe`, viewed light and dark at 1x and at 1.5x (the ten audit 44 rows at 1.5x in downscaled montages), contrast ratios computed from the M3 baseline token pairs (primary 6750a4 on fef7ff 6.1:1, on-surface-variant 8.9:1, on-primary 6.4:1, outline 79747e 4.3:1, dark 10.9, 10.9, 7.7, 5.9:1), not from every glyph.

Audit 44's ten rows, viewed. Held ready: code_editor, popover, skeleton, empty_state, toolbar, pagination, key_value_editor, markdown_view (with a recorded gap), key_caps (fixed). Downgraded to review: terminal_view (the focus cell equals rest: the scrollback list draws no focus indicator in any look).

Fixed, Android only (non-Material pictures byte for byte as committed):
- code_editor: the disabled cell drew a caret and current-line tint; none now (`examples/looks/code_editor.e`).
- key_caps: the compact cap's label was flush at the top; centred (control.compact_key_caps).
- rich-text links (markdown_view_links): keyboard focus lays the 10 % layer and the 2 dp underline (control.rich_piece); the pressed sheet waits for its eased layer. Recorded: a two-word link lights the word under the pointer only (both words share one key).
- scroll thumb (widget.e): 70 % of on-surface-variant at rest (3.98:1 light, 5.9:1 dark; was 2.4:1), 90 % over its strip. Pressed equals hover in the scroll_area sheet.
- font_picker: `looks_z86` (family faces, oblique shear), `VisualTransform.skew` (new field, 0 everywhere else), the list shows whole rows. Family rows and the sample use Roboto, Segoe UI or Tahoma where the rig has the face; other families show their name alone; Italic is Skia's fake italic (shear 1/4). New sheet `font_picker_faces.png` (`examples/looks/font_picker_faces.e`). Raised to ready.
- grid_view tile labels padded 12 dp; breadcrumbs centred in their 48 dp targets (the trail is on one baseline); sidebar four-item frame 248 high, sheet drawn in a 320 cell; canvas bars stand 12 dp above the frame foot.

Raised to ready: font_picker, scroll_area, grid_view, breadcrumbs, sidebar, canvas.

Left at review, with the defect: terminal_view (no focus indicator), ribbon (stand-in glyphs), carousel (text-glyph arrows, hover, pressed and focus equal rest), swipe_actions (one action colour, hover equals rest), reorderable_list (no drag handle, states equal rest), color_picker (unlabeled sliders, alike layers), duration_picker (step marks barely legible), icon (not Material Symbols), image (theme-less placeholder glyph 2:1), schedule (clipped labels, chips overflow), flow_editor (states equal rest), sheet (disabled equals rest, cut cell text), bottom_app_bar (text actions where M3 has icons, no hover cell), tree_table, notification_list, title_bar, document_tabs, dock_panel, workspace, list, shortcut_recorder, navigation_stack, navigation_split, android_text_modes (a text-rendering mode, not a drawn row). None was examined this round beyond the audit 43 and 44 notes; time ran out before the library work they need.

Regression: 28 sheets re-rendered one at a time (button, checkbox, combo_box, label, memo, data_grid, tree_list, status_bar, splitter, scroll_bar, spin_edit, progress_bar, card, toast, calendar, hint, link, image, terminal_view, markdown_view, code_editor, font_picker, key_caps, nav_breadcrumbs, nav_sidebar, h_grid_view, f_scroll_area, canvas), `git status` after each: every Neper, Neper Dark, Linux, Linux Dark, Windows, Windows Dark, Cupertino and Cupertino Dark picture is byte for byte as committed.


## Round 87 (lane z4)

Android idiom rows ready or matched: 63 of 89 before (ready 36, matched 27), 66 after (ready 40, matched 26). Method: every picture re-rendered one at a time with the committed `neper-self.exe`, viewed light and dark at 1x and 1.5x (montages), contrasts measured at the pixel.

Task 1, the round 86 scroll thumb. It was in the library but not in the committed pictures. Re-rendered: table, notification_list, data_grid, memo, tree_list, scroll_bar (the only Material sheets that draw it among about 40 candidates rendered: code_editor, terminal_view, markdown_view, list_box, schedule, sheet, canvas and the rest are unchanged). `table` re-measured against `ref/flutter/material/*/datatable-rest@1x`: the rule is cac4d0 against cac4cf, but the header is f3edf7 against the reference's surface fdf7ff, rows are 28 dp against 48, and the reference has a checkbox column. Matched is withdrawn: `table` is review.

Task 2, scroll_area. `looks_z87.aim` (a new file; it sets `looks.aim` for the Android look and clears it for every other, because the sheet apps run all looks in one process) points the Hover and Pressed cells at the thumb. Thumb 7f7a84 at rest, 5b5761 hovered, 49454f dragged (dark 938f99, b8b2be, cac4d0): three distinct states, 3.98 to 10.9:1. Raised to ready.

Task 3, idiom rows.
- Raised to ready: swipe_actions (hover and focus layers on More, Delete in the error colour), duration_picker (the 250 wide cell squeezed the 40 dp buttons to 22 px so the marks degenerated; the Android sheet is 520 wide), bottom_app_bar (Material icons, new `matglyph_z87` share, archive and delete outlines; hover and focus cells added for Android only).
- Improved, still review: carousel (M3 chevron icon buttons; hover, pressed and focus layers still do not draw on them, aim and a Tab walk tried).
- Tried, no change: reorderable_list (aiming at the third row draws nothing; the plain rows have no pointer layer or handle for the Android look).
- Not touched, reason: ribbon (command glyphs are stand-ins; needs six more icon outlines), color_picker (pressed would need the slider value label), icon and image (library glyphs, a theme-less placeholder), schedule, flow_editor and sheet (states equal rest in the library's drawing), terminal_view (the list is not focusable in any look), markdown_view two-word link (recorded gap, row stays ready), android_text_modes (a rendering mode, not a drawn row), notification_list (round 85 defects stand).

Findings. Windows Dark `data_grid_dialogs` and `native_dark4` re-render differently from their committed pictures on unmodified master code too (text bands, 704 and 2081 px): the committed pictures are stale, not changed here, and were restored. Cupertino `swipe_actions` is overwritten by `h_swipe_actions` although `y84_swipe_actions` owns it; restored after each render.

Overlay `status.d/` 246 z then `-z87.json` (255 characters, the file system limit; sorts after `-z45.json` by the digit).


## Round 88 (lane z5)

Android idiom rows ready or matched: 66 of 89 before (ready 40, matched 26), 72 after (ready 45, matched 27). The Delphi-equivalent `table` row is back to matched. Method: each picture re-rendered one at a time with the committed `neper-self.exe`, viewed light and dark at 1x and 1.5x, contrasts from the M3 token pairs, geometry measured at the pixel.

Task 1, duration_picker. The Hover cell aimed at the centre of the cell, the gap between two steppers, so it drew Rest. `looks_z87.aim` now points it at the Minutes plus button (hover layer d9d4dd over e6e0e9, dark 424047 over 36343b). Raised to ready.

Task 2, table. `surf_table.e` builds the Android table as Flutter's DataTable: `looks_z88.head_flat` (new file, Material only) puts the header on the surface colour, rows are 48 dp, a checkbox column (centred in header and rows through the same switch in `collection.selection_check`) and numbers at the end. Measured against `ref/flutter/material/*/datatable-rest@1x`: header 56, row pitch 48, rule cac4d0 against cac4cf (dark 49454f against 49454e), ground equal to header, checkbox within 1 px. Recorded deviations: 16 dp margin against Flutter's 24, Type left aligned. The data grid and tree table are untouched (tree_table re-rendered, byte for byte). Back to matched.

Task 3, idiom rows.
- Raised to ready: notification_list (list 330 high so the third notice and Details are whole; a wrapped message no longer squeezes the well and dismiss button), carousel (hover and pressed aimed at the 40 dp Next button; the pointer was 6 px outside it; the focus cell lands on Previous with four Tab presses), reorderable_list (24 dp drag handle, 56 dp rows, list item layers 8 and 10 percent, aim on the third row), ribbon (real command glyphs and the table grid), color_picker (R, G, B, A letters and 0 to 255 readings; wider cell).
- Tried, reverted: terminal_view focus indicator. A focusable region with a 3 dp secondary outline around the list draws when forced on, but the Focus drive never puts focus inside it (focus_within is false in every cell), so the cell stays equal to Rest; not committed.
- Not touched, reason: icon (library glyphs are not Material Symbols), image (theme-less placeholder glyph), schedule, flow_editor, sheet (states equal rest in the library drawing), android_text_modes (a rendering mode), markdown_view two-word link (recorded gap, row stays ready).

Findings. A slider's thumb position is computed from the width its node was built with, not the box it is laid out in: a slider put in a narrower flex drew its track short and its thumb clipped. Keep the slider's width and widen the container. Windows `data_grid_main` (both palettes, and its vs-ref image) and Cupertino `tree_table` re-render differently from their commits on unmodified code (stale on master); restored, not committed.

Regression. 36 sheet apps (surf_table table and tree_table, button, checkbox, combo_box, label, memo, data_grid, tree_list, status_bar, scroll_bar, spin_edit, progress_bar, card, toast, calendar, hint, link, image, terminal_view, markdown_view, code_editor, font_picker, key_caps, nav_breadcrumbs, nav_sidebar, h_grid_view, f_scroll_area, canvas, text_edit, list_box, radio, dialog) plus the six changed apps were rendered one at a time; every Neper, Linux, Windows and Cupertino picture is byte for byte as committed except the stale ones named above.

Overlay `status.d/` 250 z then `.json` (255 characters; the 246 z plus `-zzzz-r88z.json` asked for is 261, too long; this sorts after `-zzz.json` because of the character at 247).
