# Flutter comparison, lane i (round 74: Neper controls lane f left unmeasured, controls with no Flutter widget, cut rings)

Own comparer (python, numpy, scipy, not committed): flat exact-colour components with bounding boxes, ring and edge profiles per cell. Neper sheet against `ref/flutter/neper` at 1x and 1.5x, light measured, dark by role colours. The black hover outline of the refs is the harness artifact and was ignored. Palette (G1), density (G2) and ring (G3) deviations are those of `flutter-compare.md`.

## Measured against Flutter

- icon_button: 32 against 40 (G2); 1.5x 48 against 60 (exact scale). Hover 8, focus and pressed 10 per cent state layers equal. Tint is the accent where Flutter standard and tonal use on-surface-variant (new, recorded). Disabled tonal dddee4 against dedee4. Row ready.
- search_field: fixed four defects in `control.search_field` for Neper only: the Clear label was clipped at the pill edge, hover showed nothing, disabled looked like filled, no focus or invalid outline. Now hover d6d8de (ref d8d7de), disabled f1f3f9 (f2f2f8), fill e6e8ef (e8e7ee), 200 x 52 pill against 378 x 56. Row ready.
- range_slider: handles 4 x 44 bars against 20 px circles (intended); track 4 against 4/6; ring round slider plus label. 1.5x exact. Row ready, deviation recorded.
- autocomplete: no Flutter Autocomplete capture. Compared with textfield-outlined (252 x 56, 1 px, 2 px focus) and the DropdownMenu list (rows 48): 200 x 48, list rows 36. Row ready.
- calendar and date-edit popup: day circle 32 against 40, pitch 32 against 48, popup 256 x 292 r12 against a 360 modal r28. Row ready; the date_edit popup was cut by its cells and is now whole.
- Input controls at 150 per cent: button 77 x 32 to 117 x 48, checkbox halo 40 to 60 and ring 138 x 50 to 207 x 74, radio halo and icon button 32 to 48, search 200 x 52 to 300 x 78, autocomplete list 168 x 124 to 252 x 186. All 1.5 times within 1 px, as the refs (button 88 x 40 to 134 x 60). Radio halo is 35 x 32 against the checkbox's 40 x 40 and Flutter's 40: recorded (G2).
- image_combo_box: row stays review, see the ring section.

## No Flutter widget: best-judgement review

Numbers used: Material 3 divider 1 dp, drag handle 4 dp thick, Flutter scrollbar thickness 8 dp, list item 48 dp (dense desktop 32), assist chip 32 dp r8, outlined card r12 with a 1 dp outline-variant, label-large 14/20, dense status bar 24 dp; Neper rules: 4 px grid, radii 4/8/12/16/28, state layers 8/10/10, ring 3 px solid 2 px outside, 32 px pointer targets.

- splitter: 1 px line, grip on hover, accent line dragged, focus draws a 3 px accent bar. Matches the divider and handle numbers; 3 px focus bar is the ring rule. No change.
- scroll_bar: overlay thumb 4 px at rest, 8 to 10 px on hover and press, full radius; Flutter 8 dp. Hover and press match, the 4 px rest thumb is the overlay style. No change.
- tree_list: rows are 17 px in the v3 dialog list sheet (text of "Expansions" clipped at the row top) against 32 px target and 4 px grid. Violation of a sheet that copies the v3 dialog; not fixed (the control takes its row height from the sheet), left recorded.
- vertical_grid: rows 30 px against the 32 target and the 4 px grid; group heading and values aligned. Recorded, not fixed (sheet geometry).
- status_bar: fixed. The sheet placed 19 px bars and clipped the text; Neper bars are 24 tall as the v2 spec and M3 dense bar say.
- status button (pressable status panel): hover layer 8 per cent on a 24 px panel; below the 32 px pointer target by design of the dense bar. Recorded.
- label: text roles from the Neper scale, 14/20; the Word wrap cell clips its second line because the sheet gives the label a fixed 34 px box. Recorded, sheet geometry.
- group_box: captioned row list with a soft edge against the outlined card (r12, 1 dp outline-variant); unchanged.

Other sheets built for 22 px Windows controls show a 48 px Neper field with its value hanging below the outline (combo_box_focus, combo_box_edit, combo_box_pick, combo_hover, edits_states, spin_edit). The cell is no longer the cause; the sheet fixes the field height. Recorded, not fixed.

## Cut rings and open lists in the Neper sheets

Detector: a scratch script lists every cell of every Neper and Neper dark sheet whose border row or column holds focus-ring pixels (accent 145db2, dark b3c5ff), plus a second pass for any ink touching the border; the hits were looked at. Found and fixed with a Neper-only padding hook (`looks.pad_neper`, used by `run_all` and the Neper runner; Windows, Linux, Cupertino, Material PNGs are untouched):

- Ring cut at the cell (button, button_kinds, button_states, checkbox, checkbox_states, radio_states, scale_marks and scale_button excepted below, page_control custom, duration_picker, edits_states button edit, toolbar_button, pull_to_refresh): fixed by cell padding; duration_picker also gets a 300 px wrapper in Neper so its trailing ring fits.
- Content cut at the cell (date_edit popup, image_combo_box lists, label, hint, token_edit, status_bar, combo_hover, spin_edit, combo_box sheets): fixed by padding; status_bar bars are now 24.
- Not fixed: scale_button, scale_marks and scale_edits (test tiles with fractional cells; a plain rerun changes the committed Windows PNGs, so they are left as they were); image_combo_box focus ring is still interrupted by the label notch (the notch box overdraws the ring top), row stays review; label Word wrap and tree_list rows are control or sheet geometry.
- Legit, not defects: filled accent buttons, splitter bars and tree row rings that touch the cell by design.
