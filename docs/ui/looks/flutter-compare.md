

# Flutter comparison (round 70, lane a: inputs)

References: `ref/flutter/neper` (M3, seed #1b3a6b) for the Neper looks, `ref/flutter/material` (M3, seed #6750A4) for Android, `ref/flutter/cupertino` for macOS/iOS (shapes only, its text is Roboto). Comparer: own python (numpy, scipy) scripts, not committed: components found by bounding box, size, corner radius, mode fill, edge colour, shadow ring and glyph ink box read per cell, light only for the numbers, dark checked by role. Coverage is partial: the Material rows below were measured cell by cell; the Neper and Cupertino rows of this lane were only measured for button, icon button, checkbox, radio, range slider and the text fields, and are left at their status.

## Global deviations (all controls)

- G1 Neper palette: `docs/ux/tokens.json` primary is #145db2, Flutter's fromSeed(#1b3a6b) gives #425e91. Same roles and the same state layers (hover 8, focus 10, pressed 10); Neper's own tokens win.
- G2 Neper density: pointer-host controls are 32 tall (button, icon button 32, fields 30), Flutter is 40/48/56. README: density is a setting.
- G3 Neper focus: 3 px solid ring 2 px outside; Flutter shows a state layer only. Stated design.
- G4 Android palette: the published M3 baseline (#6750A4, matched earlier against Material Web) against Flutter's fromSeed result #65558F for primary, on-primary-container and tertiary roles; surfaces, outline and containers agree within 2 levels. Not changed here: the palette is shared by every Android row, so it needs one decision for all lanes.
- G5 Flutter harness artifacts, ignored: black outline on hovered buttons, on elevated buttons at rest, on every FAB state and on snackbar/menu surfaces (refs `button-*-hover`, `button-elevated-*`, `fab-*`, switch hover/focus); pressed refs are a mid-ripple frame.

## Deviations by control

- button, Neper: 32 tall pill against 40 (G2); Cupertino: medium 34, large 50 against Flutter large 52 x r8, label font differs.
- radio, Android: ring 20 x 20 (M3 spec, Material Web) against Flutter 18 x 18.
- checkbox, Android: focused unchecked halo tinted primary, Flutter on-surface. Unfixed gap.
- checkbox, Neper: focus ring is clipped to the row height in the sheet (only the two side bars show); halo is a rounded square not a circle. Unfixed gap.
- checkbox, Cupertino: focus ring surrounds box and label (134 x 26), Flutter rings the 14 px box only (20 x 20). Unfixed gap.
- range slider, Neper: vertical-bar handles (M3 expressive), Flutter draws round thumbs. Intended per the Neper component spec.

## Fixed

- Android outlined icon button: the focused outline turned primary; Flutter and the M3 outlined icon button keep the outline colour. Only the outlined button turns primary. Fix in `material_icon_button` (control.e); changes `material/icon_button`, `material/fab` and the dark pair.

# Flutter comparison: display and selection controls (round 70, lane b)

References: `ref/flutter/neper` (Material 3, seed #1b3a6b) for the Neper pair, `ref/flutter/material` (seed #6750A4) for the Android pair, `ref/flutter/cupertino` for the macOS and iOS pair (shapes only: its text is Roboto). Windows and GNOME have no Flutter reference and were left alone. Method: a private comparer (numpy and Pillow) lines each ref up with the same state of the sheet cell, finds the widget by its bounding box and compares size, corner radius, flat fills (tolerance 2 levels), outline, shadow, ink box. Glyph pixels are excluded. Sheet cells are 1.0 scale.

Black outlines in the refs are the harness artifact and were ignored: card-elevated (rest, hover, focus, pressed, disabled), snackbar-open and snackbar-floating, stepper-horizontal-rest, and the hovered buttons of the Stepper and banner refs, in the neper and material families, light and dark.

Controls with no Flutter widget captured, so no comparison and no status change: tooltip, rich_tooltip, avatar, skeleton, empty_state, toast (Neper toast is the desktop sibling of the snackbar, a different control), stepper (the number spin box), and every Cupertino row except list, date_picker and time_picker.

## Fixed in this round

- Android linear progress track: Flutter paints the track `secondary-container` (#E8DEF8 light, #4A4458 dark); the Android look used `surface-container-highest` (Material Web). Now `secondary-container`, track pixels equal the ref exactly in both modes.
- Cupertino wheels (`overlay.time_wheels`, `date_wheels`): one 36 px selection band with radius 8 across all wheels, wheels touching, as in Flutter and UIKit (was one pill per wheel, 8 px apart).
- New sheets so the pickers can be compared: `time_picker_dial` (Neper pair, Android pair), `date_picker_modal` (Neper pair), `picker_wheels` (Neper pair, Cupertino pair), and Neper `snackbar` and `badge` (they had Android sheets only). Apps `examples/looks/b70_dialogs.e`, `b70_neper.e`; runner `lib/e/ui/looks_b70.e`.

## Deviations, intended (control, state, what differs, why)

Palette, every Neper and Android row: Neper roles come from its own six tonal ramps (docs/ux README), not `ColorScheme.fromSeed`: light primary (20,93,178) vs Flutter (66,94,145), dark primary (179,197,255) vs (172,199,255), track (214,227,255) vs (218,226,249), outline-variant (195,198,213) vs (196,198,208); neutrals are within 1 to 2 levels. Android light uses the M3 baseline tokens, not fromSeed: primary (103,80,164) vs Flutter (101,85,143), error (179,38,30) vs (186,26,26); Android dark primary (208,188,255) vs (207,189,254) is within tolerance. Decision for the orchestrator: matching Flutter's fromSeed would change every Android light sheet.

- progress_bar, Neper, all: rounded 4 px bar with a 4 px gap and a stop dot (docs/ux ProgressBar anatomy); Flutter 3.44 draws a flat 240x4 bar with no gap and no dot. Android look matches Flutter: flat 240x4.
- activity_indicator, Neper and Android: ring sizes 48 (default), 36, 24, 20, 64 with stroke 4, 3, 2, 2.25, 4.5 (docs/ux ProgressRing); Flutter is one 40 px ring with stroke 4. The sheet has no 48 cell, so the Android row is not compared at equal size (see open gaps).
- card, Neper and Android: sheet card is 220 wide and content high (76) against Flutter's 192x72 test box; radius 12, filled and outlined fills and the outline are within 1 to 5 levels (palette); the elevated card has a shadow below, Flutter's ref shows none outside the artifact outline.
- divider, all: 1 px `outline-variant` line; Flutter's 1 px line straddles two rows (blended 2 px) in the ref, same colour.
- banner, Neper and Android: tonal rounded container with a status well (docs/ux Banner); Flutter MaterialBanner is a full-width bar with a bottom rule and the actions under the text.
- snackbar, Neper and Android: matches (48 high, radius 4, fill within 1 level, action in inverse-primary); ours has an elevation-3 shadow, Flutter's ref has none outside the artifact outline.
- badge, Neper and Android: dot 6, count badge 16 high, "99+" 26 to 27 wide against Flutter's 28; fill is the palette error colour.
- date_picker, Android: dialog 360 wide, radius 28, 48 px day pitch, 40 px selected circle (within 1 px of Flutter), fills within 2 levels. Differs: scrim 32 % (M3 spec) vs Flutter's black 54 %; no year dropdown on the month label; weekday letters are smaller; header date is smaller.
- date_picker and time_picker, Neper: same dialog shapes as the Android look; sizes follow docs/ux TimePicker (dial 224, period segments 48 by 64, hour and minute boxes 80x64) against Flutter's 256, 52 by 80 and 96x80.
- table, Neper and Android: dense 28 px rows and a tinted header with a sort glyph and column rules; Flutter DataTable has 48 px rows, a 56 px header, a checkbox column and right-aligned numbers (docs/ux Table: selection is a row highlight). Row rules match the ref colour (Android (202,196,208) vs (202,196,207)).
- accordion, Neper and Android: grouped tonal sections with a 12 px radius (docs/ux Accordion); Flutter ExpansionTile is a flat list tile with a leading icon, supporting text and rules.
- wizard, Neper and Android: header row of numbered steps over a content slot and Back/Next (docs/ux Wizard); Flutter Stepper is a vertical or horizontal track with filled grey inactive circles. Step circle 24 px in both.
- calendar, Android: the bare calendar uses a 40 px pitch (the dialog uses 48).
- Cupertino time and date wheels: rows are 36 px (docs/ux TimePicker) against Flutter's 32, no perspective squeeze, band fill is a palette role (Flutter's is a translucent grey over white: (239,239,240) light).

## Open gaps (rows left at review)

- list: Neper has no list tile (leading icon, two lines, trailing chevron). Flutter ListTile and CupertinoListSection rest, hover, focus, pressed and selected have no Neper counterpart; the Neper list is a list box (21 px text rows).
- time_picker, Android: dial 224 vs 256, boxes 80x64 vs 96x80, period 48x64 vs 52x80, dialog 308 vs 358 wide; needs Material-profile branches in `overlay.time_picker_modal_with` and `time_dial`.
- time_picker, Neper: the dial face and the knob draw as squircles, not circles. The Neper look draws every rounded corner as a quadratic curve, so a radius of half the side bulges 0.06 r past a circle (6.8 px on the 224 dial, 2 px on a 72 px avatar). `widget.set_arc_corners` fixes it for a look but changes every Neper picture; needs a decision.
- activity_indicator, Android: sizes on the sheet are 20, 36, 64; Flutter is 40 with stroke 4, ours is 3 at 36.

# Flutter comparison, navigation and overlay controls (round 70, lane c)

References: `ref/flutter/<neper|material|cupertino>/<light|dark>`. Neper look = Flutter M3 seed #1b3a6b, Material = seed #6750A4, Cupertino = Flutter Cupertino (Roboto stands in for SF, so text is excluded; shapes, sizes, fills only). Method: a scratch python comparer (not committed) lists every flat fill (exact colour, 4-connected, at least 60 px) of the Neper sheet and the Flutter ref with bounding box and corner radius, matches fills within 2 levels, then ink extents on single rows for widths. Light and dark gave the same results unless a line says otherwise.

Controls with no Flutter reference (not compared, rows untouched): sidebar, bottom_app_bar, breadcrumbs, menu_bar, popover, flyout, side_sheet, title_bar, document_tabs, toolbar (command bar), Windows and GNOME looks.

## Harness artifacts ignored

The black outline of the headless run (not M3) is in these refs, in both families: menu-popup-open, menu-anchor-open, dropdownmenu-open (surface), searchbar-focus and searchbar-disabled (a black 390 by 68 box around the bar), navigationrail-focus and navigationrail-pressed (around the FAB), the hovered bar tooltip in navigationbar-hover. Flutter hover, focus and pressed frames are also caught while the state layer is still fading in (rail hover on an unselected pill is 3 % of onSurface, spec is 8 %), so state layer colours are compared against Neper's spec values 8/10/10 only by direction.

## Deviations kept (control, state, what differs, why)

- all Neper rows, rest: secondary container is d6e3ff, Flutter fromSeed gives dae2f9 (6 levels on B). Neper tokens are its own palette, not generated from the seed; a token change would move every Neper sheet.
- all Material rows, rest: surfaceContainer f3edf7 (published M3 baseline), Flutter fromSeed f2ecf4 (3 levels on B). Same reason, token level.
- navigation_rail, Neper and Material, all: no icon slot, the label sits in the 56 by 32 pill; Flutter stacks icon over label and has a FAB. The library rail takes labels only.
- navigation_rail, focus: Neper draws the 3 px solid ring 2 px outside (design system); Flutter shows only the state layer.
- navigation_drawer, rest: drawer 256 wide (sheet choice), ref 300; no header text or icons. Indicator height 56, inset 12, end corners 16 match.
- alert_dialog, Neper and Material: sheet card 380 wide against 298, and the three-action example uses filled action pills; radius 28 and fills match.
- popup_menu, Neper: the v3 command menu, r8 with a stepped 4 px shadow, 48 px rows with shortcut column; M3 menu is r4 with a soft shadow (not measurable, the ref draws the black artifact there).
- popup_menu, Cupertino: macOS menu (r8, small rows); Flutter shows the iOS context menu (r14, 250 wide, trailing icons). Kept, not matched; row stays review.
- search_field, Neper: 200 by 52 with a text Clear button; M3 SearchBar is 56 high with icons. Not the same control, kept.
- toolbar and large_title, Neper: desktop command toolbar and header, not an M3 AppBar.
- Cupertino alert_dialog and action_sheet: Flutter fills are translucent over the barrier (f1f1f1 and f2f2f2 over its grey); ours are opaque tokens (f4f4f6, e9e9eb). Sheet ground is f2f2f7 (dark 1c1c1e) against Flutter white (black), which also explains the search field fill e3e3e9 against efeff0 (same 12 % tertiary rule).

## Fixed

- action_sheet, Cupertino and Cupertino dark: was the generic bottom sheet with handle and left-aligned rows; now the library's grouped iOS cards (`overlay.action_sheet_ios`: inset 8, r14, 56 px rows, centred blue actions, separate Cancel card). The Cancel card is now the lighter one as in Flutter (white, 2c2c2c). `surf_overlay.e` picks the iOS form for the Cupertino profile; all other looks re-render byte-identical.
