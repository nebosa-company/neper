# Round 79 lane q: Android menu bar, rows without a Flutter widget, Android date input

Own comparer (python, numpy, scipy, not committed): exact-colour flat components with bounding boxes, row and column colour runs, corner profiles. Palette difference of Android primary (6750a4 against Flutter 65558f), the black harness outline and the mid-fade hover and pressed frames are accepted and not repeated. Policy of this round: no device screenshot will exist; a row without a Flutter widget may reach `matched` only on a measurement against cited public numbers that covers every state.

## Android menu bar (raised to `matched`, light and dark)

The previous picture was the M3 navigation bar. The Android look now draws a real menu bar (`examples/looks/material_menu_bar.e`, `menu_bar.png` and `menu_bar-open.png`; hooks in `navigation.menu_bar_of` and `bar_menu_clamped`, code in `lib/e/ui/looks_q79.e`; other looks untouched). Flutter has no MenuBar reference image, so the numbers are Flutter's published MenuBar source (`menu_anchor.dart`, `_MenuBarDefaultsM3`, `_MenuButtonDefaultsM3`, `_MenuDefaultsM3`) and the M3 menu tokens:

- Bar: surface-container, 4 px corners, level 3 shade, 4 px side padding. Measured 48 high (buttons at least 64 x 48), f3edf7 (dark 211f26), corner inset 2 px at the top row (radius 4).
- Title: square, at least 64 x 48, 8 px side padding, label-large; state layers on-surface 8 % hover, 10 % pressed, focused or open. Measured: Cards title 64 x 48; hover e2dce6 over f3edf7 (8 % gives e2), pressed and open ded8e2 (10 % gives de), keyboard focus ded8e2; dark hover 312e36, pressed 35323a (8 % gives 31, 10 % gives 35), all exact.
- Menu: surface-container, 4 px corners, level 2 shade (M3 md.comp.menu; Flutter uses 3), 8 px top and bottom padding, rows 48 high, width 112 to 280. Measured: panel 280 wide (the max), rows 48 (hovered row 202.5 to 250.5, one row), separator 1 px with 8 px each side, hovered row e3dee7 (8 % gives e3), disabled items at 38 %, panel f4edf7 (dark 201e25, one level off the bar fill).
- States viewed in both palettes: rest, hover, pressed, keyboard focus, open with a hovered row, disabled rows, a separator, shortcuts.

Recorded deviations: the menu shade is level 2 (M3 token) where Flutter paints 3; the bar needs no Flutter match in width (it fills its container). Windows, Linux, Neper and Cupertino menu bars are drawn by the same function and are unchanged (re-rendered, byte-identical).

## Android date input (measured, row stays `review`)

`date_input.png` was stale; the sample typed "2026-10-16" under a "mm/dd/yyyy" hint and a Feb 21 headline. It is now "02/21/2026", plus `date_input_focus.png` (field focused) and `date_input_error.png` ("13/45/2026"). Fixed: the outlined field's label notch was painted in the page colour (white on the light card, a dark box on the dark card); inside the modal it is now the card colour (`FieldOptions.on_raised`, set by `date_entry` for the Android look only). The field starts 21 px under the divider as in Flutter's `datepicker-input-open@1x` (206 against 185 + 21), was 16.

Against `datepicker-input-open@1x` (light and dark): field 56 high (ref 56, rows 206 to 261), outline 1 px 79747e (ref 7a757f; dark 938f99 against 948f99), card fill ece6f0 (ece6ee), divider cac4d0 (cac4cf), header 120 (ref 119). Focus: outline 3 px primary and the label primary (M3 token focus width 3; Flutter 2, recorded, spec wins), error: 1 px b3261e (Flutter ba1a1a, palette). Recorded: card 360 wide (M3 container token; Flutter's input dialog is 328), card 279 high against 270 (the M3 supporting text "mm/dd/yyyy", absent in Flutter).

Why not matched: the calendar's hover, focus and pressed day states are unmeasured on Android, and the docked picker (the field form without a dialog) is not drawn.

## Rows below `matched`, and the specific missing evidence

M3 defines no such component (nothing to cite): Android label, spin_edit, splitter, status_bar, scroll_bar, tree_list, vertical_grid, data_grid (its picture also shows no hover tone on the hovered row and has no filter row or footer), image_combo_box.
Android hint: plain tooltip 24 high on inverse-surface (M3) against Flutter's 32; the rich tooltip's left edge column is half a pixel off Material Web (218 ring px), and the Plain, long cell clips its text.
Android date_edit: see above.
Cupertino (shapes only, nothing from Flutter): label, spin_edit, combo_box, image_combo_box, date_edit, progress_bar, group_box, page_control, splitter, status_bar, toolbar_button, menu_bar, popup_menu, hint, scroll_bar, tree_list, vertical_grid, data_grid. The Apple numbers in the existing notes (UIProgressView height, UIPageControl dots, AppKit menu rows, scroller widths) are from memory; no public page could be read here to cite, and Flutter's refs are iOS idioms (context menu, date picker wheel) where these rows draw macOS idioms (menu, stepper field). Without a cited number the rows stay `review`.
