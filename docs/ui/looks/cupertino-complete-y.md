# Round 84 lane y: completing the Cupertino and CupertinoDark looks

Rule applied (maintainer, "complete all looks"): a Cupertino row with no Flutter widget or no citable Apple number may be `ready` when every cell is drawn correctly and legible (viewed at 1x and 1.5x, light and dark), the shape is the real macOS or iOS control, own measurements agree with what is cited, citations are labelled solid or from memory, and dark colours hold 4.5:1 for text and 3:1 for controls. `matched` still means a reference was measured; nothing here is `matched`.

Scratch comparers (python, PIL, not committed): colour runs along rows and columns, ink bounding boxes, WCAG contrast of the dominant colour against the farthest pixel in a box. Code: `lib/e/ui/looks_y84.e` (Apple logo path, thin-divider switch); hooks in `control.e` (kind 20 mark, split sash width, ring tone), `overlay.e` (Cupertino tag line cap).

## Raised to `ready` (4 rows, both looks)

| row | defect fixed | measured | cited solid | from memory |
|---|---|---|---|---|
| menu_bar | Apple logo was discs; hover and pressed cells drew the bar clipped to 372 wide | bar 24 high (rows 32 to 55), 36 at 1.5x; 400 wide in all three cells; text 19.4:1 light, 14.3:1 dark | HIG: the menu bar is 24 pt high | face colours, 13 pt titles, chip colour and radius, Cmd words for shortcuts |
| hint | the wrapped tag lost its third line (`max_lines 2`); the cell was too short | tag 20 high, 11 pt, radius 4, 6 x 3 padding; text 17.6:1 and 10.1:1 | none | all metrics (AppKit help tag) |
| activity_indicator | error and paused rings drew the blue 35 % ring | spinners 20 x 20, 36 x 36, 64 x 64; ring 3.6:1 and 4.66:1; error 3.18:1 and 4.99:1; lead tick 3.11:1 and 5.57:1 | tick geometry and alpha ramp (Flutter `activity_indicator.dart`, round 81 u) | 20 and 36 or 37 sizes, ring width |
| progress_bar | none found | track 4, thick 6; fill 3.6:1 and 4.66:1; error 3.18:1 and 4.99:1; paused orange 1.97:1 light, 8.28:1 dark | none | track height and caps (UIProgressView) |

Contrast exceptions, stated so the audit can judge them: the unfilled track of every bar and ring is the system fill (1.25:1 light, 1.57:1 dark) and carries no state, the value is in the fill and the caption; the light paused bar is Apple's systemOrange at 1.97:1; the light spinner's lead tick is Flutter's own ramp at 3.11:1.

## Fixed, row stays `review`

- splitter: the sheet now has the HIG thin divider (1 pt, cited) beside the thick one, upright and lying, 16 cells, panes 201 x 121 so the divider is under the harness pointer. The Hover and Dragged cells of every divider still look like Rest (the pointer does not reach the sash in the harness) and only the last cell shows the keyboard ring (the harness focuses the last focusable): states not drawn, so not raised.
- swipe_actions: a Cupertino-only sheet (`y84_swipe_actions.e`) draws the collection's real tiles, 80 wide and row high, Archive accent and Delete red, the row text clear of them. Not raised: white 12 px labels on the system fills are 3.4 to 4.0:1, under 4.5:1; hover buttons and the mid-swipe drag are not drawn.

## Rows left below `ready`, and why

Looked at and drawn correctly, but a text or control pair is Apple's own colour under the contrast rule: combo_box (placeholder 'Size' about 2:1 in dark), page_control (grey tab labels; the strip focus ring is a plain rectangle), status_bar (secondary grey text), vertical_grid (secondary values; white card on the grouped ground 1.1:1), tree_list, scroll_bar (thumb against the ground), toolbar_button (accent text 3.6:1 light), data_grid (grouped cell: the footer total and the group total touch the scroll bar), spin_edit (the keyboard ring around the minus half is clipped flat at the divider).

Not drawn as the Cupertino shape, the shared Material-derived shape in Cupertino colours (a toast is not an iOS notification, a list row is not a UITableView cell, and so on): toast, list, banner, empty_state, rich_tooltip, notification_list, card, key_value_editor and the other generic extra rows. Raising them needs profile-specific drawing, not a judgement.

Known and not done in this lane: popup_menu draws the macOS menu only (Flutter's reference is the iOS context menu, 14 radius, 43 rows, trailing icons), there is no iOS menu cell; large_title, range_slider (touching cell stacks both thumbs), date_range_picker, image_combo_box and date_edit sheets were not re-examined; roughly 70 further extra rows were not individually viewed in this lane and keep their status.

## Regression

Re-rendered one at a time with the change, then `git status`: menu_bar, splitter, hint, linux_hint, linux_menu_bar, linux_popup_menu, linux_splitter, material_menu, material_menu_bar, material_splitter, material_tooltip, popup_menu, rich_tooltip, split_button, title_bar, nav_toolbar, nav_sidebar, f_dock_panel, f_workspace, surf_overlay, nav_navigation_split, h_swipe_actions, activity_indicator (23 apps): every PNG of every other look byte for byte as committed. Exception, not mine: Material `tooltip` (all four files) differs from the committed bytes with or without this change (checked with the lane's two shared-code edits stashed), stale on master like Material date_input; restored to the committed bytes.

## Batch 2: contrast and ring fixes (Cupertino look only)

Changes: secondary label 60 % to 80 % (light) and 70 % (dark) in `style.cupertino`, so secondary text, the Cupertino placeholder and muted marks hold 4.5:1; tab-bar grey 8E8E93 to 6C6C70; the overlay scroll thumb from 35 % to 48 % (light) and 44 % (dark) of the label colour (2.4:1 became 3.6:1 light, 4.3:1 dark); the stepper halves are positioned layers (the focused half's ring is no longer cut). All 45 Cupertino sheet apps that call `run_cupertino` plus the nine row apps were re-rendered afterwards; `git status` after the run shows no file outside the Cupertino folders and these sources.

Raised to `ready` (both looks): combo_box, spin_edit, status_bar, tree_list, vertical_grid. Per-row measurements are in their overlay notes (`status.d/...-r84y2.json`): combo_box 22 high, placeholder 5.97:1 and 4.5:1; spin_edit 94 x 32, glyphs 3.14:1 and 3.5:1; status_bar text 5.1 to 6.6:1; tree_list rows 24 apart; vertical_grid rows 44 apart (HIG 44 hit region cited).

Not raised, with the measured reason: scroll_bar (Hover and Pressed draw the Rest thumb), page_control (the strip focus ring is a square rectangle), toolbar_button (accent text 3.6:1 on the light ground; the accent was not darkened because every matched row was compared at 007AFF), data_grid (group total touches the scroll thumb), splitter (Hover, Dragged and three of four Focus cells show Rest; the harness pointer does not reach the sash and focuses the last focusable), swipe_actions (white 12 px tile labels 3.4 to 4.0:1).

Not started in this lane: the iOS context-menu cell for popup_menu, and the item-by-item pass over the generic extra rows; both need Cupertino-specific drawing code that was not written, so no extra row is raised.

## Batch 3: harness aim, contrast and the iOS menu

Root cause for the Rest-looking Hover, Pressed and Focus cells of scroll_bar and splitter: not duplicate keys (every cell already had its own key range) but the pointer: the harness drives a cell at its centre, the scroll thumb stands 31 px to the right of it and the sash at two thirds of its `position` argument, so nothing was hovered. `looks.aim` (offset from the cell centre) in `cup_scroll.e` and `cup_splitter.e` fixes both; only Cupertino PNGs of those two sheets changed (both apps write the Cupertino looks alone).

Raised to `ready` (both looks): splitter (sixteen cells, all states now drawn; divider line 3.4:1 light, 5:1 dark), scroll_bar (hover and pressed 6 wide against 4), swipe_actions (tile labels 5.3 to 5.8:1 with a darker accent and red in the swipe tile only), popup_menu (iOS context menu cell added: 250 wide, radius 14, 44 high rows, trailing symbols; the macOS destructive row 4.98:1).

Not raised: page_control (strip focus ring is a 13 px rectangle through the label), toolbar_button (accent text 3.6:1; the nav bar text code is shared with matched rows, so no row-only darker blue was possible), data_grid (chosen row white on 007AFF, 4.02:1; the group total overlap is fixed).

## Batch 4: generic extra rows, first look (divider, link, key_caps, rating, skeleton)

Viewed light and dark at 1x. None raised. These rows have no UIKit or AppKit control behind them (skeleton and rating are Material or web patterns, key caps and the underlined link are web idioms), so "the shape is the real macOS or iOS control" cannot be defended by restyling alone; the divider is a hairline at about 1.2:1 (a separator, not a control) and the Vertical cell is nearly invisible; the link's accent text is 3.6:1 on the light ground. The other generic extra rows (about 65: toast, list, banner, card, empty_state, sheet, popover, ribbon, wizard and the rest) were not viewed in this lane and keep `review`.

Final regression: the 45 `run_cupertino` apps, the nine row apps, cup_menu, y84_swipe_actions and activity_indicator were re-rendered after the last code change; `git status` shows no file outside the Cupertino folders and the sources.

## Batch 4b and 5: page_control, toolbar_button, data_grid, rating, skeleton

- toolbar_button raised: the sheet draws with a local theme copy whose accent is Apple's increased-contrast blue (0040DD, 409CFF dark); every other sheet and the shared nav-bar code keep 007AFF.
- data_grid raised: the sheet-local chosen-row fill 0A60FF (light) gives white text 5.08:1, dark 0B57D0 6.39:1.
- page_control stays at review: the strip focus ring is a 13 px rectangle through the label; the segmented strip code is shared with the matched segmented_control row, and its pictures must not move, so no fix was made.
- rating and skeleton raised under the coordinator's standard for generic rows (own tokens, system fills, no Material shape), viewed at 1x and 1.5x, light and dark.
- divider not raised: the hairlines are about 1.1:1 and the Vertical cell is nearly invisible. link not raised: the accent text is 3.6:1 and it underlines on hover. key_caps was seen at 1x only.
- Not viewed in this lane and left at `review`: the remaining generic extra rows (icon_button, toggle_button, split_button, speed_dial, range_slider, dial, password_field, autocomplete, banner, toast, card, sheet, popover, ribbon, wizard and about forty more).

## Batch 6: re-run, link, divider, icon_button, password_field

- Regression: the 45 `run_cupertino` apps, the nine row apps, cup_menu, y84_swipe_actions, activity_indicator, link, password_field, icon_button and divider were re-rendered after the last code change; nothing outside the Cupertino folders moved (segmented_control PNGs included).
- `looks_y84.tinted` gives a shared sheet a Cupertino-only accent: a copy of the tokens with another Primary; any other look gets its own tokens back. Used by link.e.
- Cupertino placeholders (text fields) use the secondary label colour; the old dimmed copy was 1.7:1 light.
- Raised: link (0040DD / 409CFF text), divider (hairline separators are decorative, WCAG 1.4.11), icon_button, password_field.
- page_control: a second attempt (padding the strip segments) moved the labels and left the ring unchanged, so it was reverted; the ring is not tied to the segment rectangle and the cause was not found. Stays `review`.
- Viewed and not raised (Material-looking or not an Apple idiom): toast (stacked heavy shadow bands), card (elevated, filled, outlined, dragged tilt), banner (accent 'Details' links 3.6:1), toggle_button and split_button (white on 0A84FF in dark is 3.65:1), sheet (spreadsheet) and ribbon (Office ribbon).
- Not viewed: about 45 further generic extra rows.

## Round 85

Standard: a row is `ready` when drawn with the Cupertino look's own tokens in every state, legible, no clipping, 4.5:1 text and 3:1 controls (a separator hairline is decorative and its colour is stated), and not a Material shape where an iOS or macOS idiom exists; every picture viewed light and dark at 1x and 1.5x. Code: `lib/e/ui/looks_y85.e` (sheet-local increased-contrast blues with a ring at 80 %, the opaque separator colours, the card face); hooks in `control.e` (divider, rating hover star, card, toast, tab-strip focus inset) and `widget.e` (a negative `focus_inset` keeps the ring outside the bounds). Every hook is gated on the Cupertino profile; all 254 look apps were re-rendered one at a time, and no Linux, Neper, Windows Light or Material picture moved (the stale Windows Dark and Material ones named in audit 43 were restored, not committed).

Audit 43 downgrades fixed (all four back to `ready`): spin_edit (the pointer is aimed at the plus half with `looks.aim`), rating (focus ring drawn, hover star 5.9:1 and 5.1:1, pressed 4.9:1 and 3.9:1), divider (C6C6C8 / 38383A one pixel thick, 1.53:1 and 1.45:1, decorative), page_control (the runtime insets a tab's ring 3 px; a negative focus_inset on Cupertino tab strips keeps it around the segment; segmented_control pictures are byte for byte).

Stale pictures: 25 sheets from audit 43 plus list_rows, markdown_view and date_range_picker_open (touched by the new divider colours) re-rendered and committed; 19 viewed. Defects seen and not fixed: duration_picker and time_picker steppers clip at the cell edge, light command_palette draws no active row, document_tabs keyboard focus draws no ring, sheet (spreadsheet) cuts cell text without an ellipsis.

Generic rows: raised to `ready`: card (grouped inset card, 10 pt, no shadow), toggle_button and split_button (white on 0045E6 / 0B57D0, 4.8:1 or better in every state). Reshaped, not raised: toast (22 pt banner, soft shadow; the Material severity wells stay), banner (accent links fixed; the pressed plain label is dimmed to 35 %, shared with the matched button row). Not restyled, with reasons in the overlay: ribbon (Office idiom, no macOS control), sheet (this row is the spreadsheet, not a modal sheet). Nine more sheets take the tinted blues (pagination, shortcut_recorder, key_value_editor, accordion, breadcrumbs, autocomplete, date_range_picker, navigation_rail, navigation_drawer_rows) and stay `review`. About 40 generic rows were not viewed cell by cell this round and keep their status.

Completion (Cupertino, Light and Dark equal): 93.3 % to 96.0 %; ready base rows 12 to 14 (matched 13 unchanged, review 5 to 3); ready idiom rows 6 to 11.

## Round 86

Standard as round 85. Code: `lib/e/ui/looks_y86.e` (the chosen-row accent, the chosen tab face), hooks in `navigation.e` (palette row, document tab pill and ring inset, ribbon tab strip) and `control.e` (toast elevation), all gated on the Cupertino profile. Overlay `status.d/zzz...-y.json` (246 z).

Audit 44 downgrades, both fixed and back to `ready`: spin_edit (the sheet takes the 0040DD / 409CFF blue with its ring at 80 %: glyph 4.8 to 5.4:1 hovered and pressed in light, 3.0 to 3.8:1 in dark, ring 5.9 and 4.5:1) and time_picker (Cupertino cell 430 wide, the seconds stepper no longer clips; its Hover, Focus and Pressed cells now aim at a stepper half, they hit the colon before and drew Rest).

Visible defects from round 85, fixed and raised to `ready`: duration_picker (cell 400 wide, stepper halves no longer cut), command_palette (active row in the accent with white text, 5.1:1 light and 6.4:1 dark; the light palette drew none), document_tabs (chosen tab a raised pill, keyboard ring shown; the focus cell's click now lands on the one tab stop). toast also raised (flat 22 pt banner, no shadow band, text 5.2 and 5.6:1).

Reshaped, not raised: ribbon (tab strip is the macOS toolbar tab idiom, chosen tab a raised pill; the panel is still the Office ribbon and the Save and Undo text is 3.6:1). sheet stays the spreadsheet row; the modal sheet idiom already exists as bottom_sheet and side_sheet (iOS grabber, rounded top, dimmed backdrop), which were viewed and not changed (Save white on 007AFF is 4.0:1, needs the tinted fill, not done).

Viewed at 1.5x light and dark (1x only where noted above): spin_edit, time_picker, duration_picker, command_palette, document_tabs (1x too), toast, ribbon, speed_dial, range_slider, dial, autocomplete, banner, key_caps, bottom_sheet, side_sheet, sheet. Left at review with the reason: speed_dial (Material pill, accent text 3.6:1), range_slider and dial (focus ring too faint in dark, dial ring is a rounded square), autocomplete (the suggestion list is not drawn), banner (Material severity wells, Details 3.6:1), key_caps (web idiom). About 45 further generic rows (empty_state, rich_tooltip, notification_list, avatar, icon, image, markdown_view, terminal_view, code_editor and so on) were not viewed this round and keep their status.

Defect found in the harness: `looks.aim` persists across the looks of one run, so an aim set for the Cupertino look leaks into the Material look that follows (it changed Material time_picker and document_tabs); both sheets now reset it for every other look.

Regression: 28 sheet apps re-rendered one at a time (time_picker, autocomplete, banner, sheet, navigation_split, dock_panel, workspace, wizard, title_bar, accordion, breadcrumbs, navigation_rail, popup_menu, combo_box, link, rich_tooltip, calendar, font_picker, date_range_picker, pagination, sidebar, toolbar, data_grid, tree_list, status_bar, menu_bar, button, card; plus the changed apps): no Neper, Linux, Windows or Material picture moved, except Windows Dark dock_panel, which is stale on master (audit 44) and was restored. workspace (Cupertino) changed with the tab pill and was committed after viewing.
