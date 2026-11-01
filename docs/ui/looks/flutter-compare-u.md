# Round 81 lane u: Android menu bar, Cupertino label, spinner and scrollbar citations

Own scratch comparers (python, numpy, PIL, not committed): colour runs along columns and rows, ink extents, ink mass (summed coverage) against PIL Segoe UI at the cited size. Sources read: `D:/flutter/packages/flutter/lib/src/material/menu_anchor.dart`, `scrollbar.dart`, `cupertino/activity_indicator.dart` (solid, source on disk); `ref/flutter/material/{light,dark}/menu-anchor-open@1x.png`.

## Android menu_bar (light and dark) raised to `matched`

Audit 40 found the panel 280 wide and the dividers 17 rows. Flutter's vertical menu is an `IntrinsicWidth`, a row is `_MenuItemLabel`: 12 padding, the label, 12, the shortcut (12 and a 24 icon for a submenu), 12 padding; the M3 menu holds it to 112 to 280.

Changed (Android only; code in `looks_u81.e`, hooks in `navigation.e`, sheet cell width in `material_menu_bar.e`):
- Panel width is the widest row (label and shortcut measured with the face), rounded up to a whole pixel, held to 112 to 280. Open-Cards panel: 188 wide (was 280). Label to shortcut gap 12 (was 105).
- Divider 16 rows (8, the line, 7), as `Divider(height: 16)`. Panel 336 high (8 + 6 x 48 + 2 x 16 + 8), rows still 48, hovered row 200 to 247.
- The shortcut text is on-surface like Flutter's `Text` inside the button (was the muted tone); the submenu arrow stays on-surface-variant (Flutter `iconColor`).
- The open sheet's cell is 400 wide (was 520): the driven pointer sits at the cell centre and the narrower panel would have left it outside.

Measured on the committed 1x PNGs, light and dark: panel x 80 to 267 (188), first label ink 12 px in, shortcut ink ends 12 px before the panel edge (the same 12 px as the Flutter MenuAnchor ref: last ink to flat panel end 12), separators one row (192 and 304, cac4d0), rows 48. Against the ref: row pitch 48, first row centre 8 + 24 under the panel top, label ink 49 px in after a 24 px icon (12 + 24 + 12 plus a pixel of bearing), in both modes. Light and dark viewed.

Recorded, unchanged: menu shade level 2 (M3 token) against Flutter's 3; the bar fills its container where Flutter's hugs its content; no Flutter MenuBar frame exists (the ref is a MenuAnchor with icons, so the icon column is not drawn); the open title tint has no source line in `menu_anchor.dart`. The black outline on the ref's panel is the harness artifact and is ignored.

## Cupertino label (light and dark) raised to `matched`, shapes only

Cause: the headline cell asked for no weight (Regular). Asking for 600 drew Bold (672 mass, width 125), because the rig has Regular and Bold only. `looks.read_semibold` registers Segoe UI Semibold (font id 16) for a sheet that calls it (`cup_label` does), so weight 600 now picks it; other sheets keep their font chain and do not move.

Ink mass of "Deck Properties" (coverage summed, PIL Segoe UI at the same size as reference): 17 px 504 against 514 semibold (regular 391, bold 672), width 121 against 121; 1.5x 1137 against 1163 (878, 1489), width 180 against 181. Within 2.2 % of the semibold reference. Other cells unchanged. Recorded: Segoe UI stands for SF Pro. Every other Cupertino control that asks for weight 600 (buttons, segmented titles) still draws Segoe UI Bold: not changed here.

Hazard found: `looks.open` gets its `Rig` from an arena that is not always zeroed, so a rig field read in `set_look` must be set in `open` (otherwise Cupertino sheets failed with `TooLarge`).

## Cupertino activity_indicator: spinner fixed, row stays `review`

Source (solid, `activity_indicator.dart`): eight ticks, `RRect` from x = +-r/10, y = -r/3 to -r, corner r/10, tick colour 3C3C44 (dark EBEBF5), alpha ramp 47, 47, 47, 47, 72, 97, 122, 147 of 255 behind the active tick. Ours drew 12 ticks from 0.52 r. Now a separate mark (kind 21 in `control.e`, used only by `cupertino_ring`; the button's loading ring keeps kind 10). Measured on the 64 px cell: 64 high, ramp 48, 71, 97, 122, 147. The determinate ring has no Flutter or Apple number, so the row stays `review`. Re-rendered with the new spinner: activity_indicator, progress_bar, pull_to_refresh (Cupertino only).

## Android scroll_bar: measured, not changed, `review`

`scrollbar.dart` (solid): Android thickness 8 / 2 = 4, margin 2, minimum length 48, drag on-surface 60 %, hover 50 %, idle the theme highlight; 8 and 12 only on desktop or with a visible track. Ours: rest thumb 4 wide, 2 from the edge (matches); hovered and dragged 8 wide (Flutter Android keeps 4); one grey in all states; the 32 px thumb is below Flutter's 48 minimum. M3 has no scrollbar spec, so there is no cited number to pick a side. Left at `review` with the gaps in the row note.

## Left at `review`, no citable number

Cupertino spin_edit, combo_box, image_combo_box, date_edit, progress_bar, group_box, page_control, splitter, status_bar, toolbar_button, menu_bar, popup_menu, hint, tree_list, vertical_grid, data_grid, stepper, list: no published Apple number (round 80 s read the HIG pages; UIKit and AppKit pages give no point values); their metrics are from memory and are not a basis for `matched`. Cupertino list and popup_menu have Flutter refs but a different shape (iOS grouped list and context menu against our macOS rows and menu), already recorded in round 70 and 77. Android hint, list, splitter, status_bar and the other rows with no M3 component keep their round 77 and audit 3 notes: the Flutter Tooltip is 32 high against the M3 24 kept, the Flutter ListTile deviations are recorded, and the rest have no Flutter or M3 number.

## Regression

Re-rendered with the new code: material_menu_bar (open sheet), cup_label, activity_indicator, cup_progress, button, button_states, button_hover, button_arrows, cup_button, f_dock_panel, h_pull_to_refresh, skeleton, banner, notification_list, toast, card, avatar, gauge, icon, hint, toolbar_button, progress_bar, linux_progress_bar, material_progress, checkbox, native_dark: every PNG of Windows, Linux and Neper byte for byte, and of Material and Cupertino apart from the files named above.
