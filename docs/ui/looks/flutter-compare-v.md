# Round 82 lane v: Segoe UI Semibold for every Cupertino sheet

Cause: only the `label` sheet registered Segoe UI Semibold (font id 16), so weight 600 drew Segoe UI Bold in every other Cupertino control (filled and tinted buttons, segmented titles, dialog titles, wizard, page control and others). Fix: `looks.read_fonts` now also reads `seguisb.ttf`, so every rig carries the face and `set_look` puts it in the Cupertino chain. One line in `lib/e/ui/looks.e`; no other look's font chain changes.

## Measured

Scratch comparers (python, numpy, scipy, PIL, not committed). All 127 sheet apps that call `run_all` or `run_cupertino`, plus the 51 that call `run_ten`, `run_every` or `looks_g.run`, were re-rendered one at a time with the change. Non-Cupertino PNGs: byte for byte unchanged, except Material `key_value_editor`, which is stale on master (same bytes with the font change removed; not committed, like date_input).

Cupertino ink changed in 14 sheets, light and dark, 1x and 1.5x: alert_dialog, breadcrumbs, button, dialog, empty_state, font_picker, large_title, markdown_view, page_control, segmented_control, speed_dial (and speed_dial_open), swipe_actions, toolbar_button, wizard. Each was compared with the same code minus the font (baseline renders, flat-fill components of 5 x 5 uniform colour, matched by overlap): heights, radii, fills and y positions identical. Only label-sized widths moved, because semibold is narrower than bold: button 2 px, empty_state 1, font_picker 2 (5 at 1.5x), page_control 2, segmented 3, wizard 2, speed_dial 1 to 3, swipe_actions 2, hint 5 to 7. Dialog cards, alert_dialog, breadcrumbs, large_title, toolbar_button and markdown_view (1x): shape ink identical, only glyphs differ. Light and dark viewed (button, dialog, alert_dialog dark, segmented, wizard).

Against `ref/flutter/cupertino` (shapes only): the compared quantities (heights, radii, fills, rings, shadows) did not move, so no matched row regresses. Widths of label-sized controls were never comparable (Flutter's label is Roboto) and stay recorded as such. No row is raised or downgraded.

## Not committed: stale PNGs on master

`cupertino/hint` (written by both `hint.e` and `cup_tooltip.e`, order-dependent), `navigation_stack` and `navigation_split` (the committed PNGs show a nav bar face that the current code no longer draws) already differ from what the unchanged code renders. Left at their committed bytes so this commit holds only the font effect; their text still shows the old weight until they are regenerated.

## Rows touched

Overlay `status.d/...-r82v.json`: the 14 sheets above get a note; the 'semibold mapped to Segoe UI Bold' gap on button_edit, check_list_box, data_grid, date_edit, group_box, image_combo_box, mask_edit, memo, menu_bar, navigation_bar, radio_group, search_field, slider, splitter, status_bar, stepper, switch, tab_bar, token_edit, tree_list and vertical_grid now reads Semibold; button loses the audit 41 gap; label's 'this sheet only' line is corrected. Statuses unchanged.

Still Bold on purpose: controls that ask weight 700.
