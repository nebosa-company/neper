# Round 77, lane k: the Neper items audit 36 found

Branch looks77-k from master 03f30359c. Own scratch comparer (not committed) against `ref/flutter/neper`.

- date_edit: field 256 x 48 (was 40), Flutter textfield-outlined 252 x 56. Same deviation as text_edit, mask_edit, button_edit and autocomplete (48 against 56: 4 px grid, desktop density). Touch hosts keep 56. The day hover cell draws a 32 x 32 hover circle on a day.
- combo_box: field 150 x 48 against DropdownMenu 56; list rows 36 against 48 (desktop density). Past seven rows the list scrolls in a 252 px viewport (Flutter menu height is capped as well). The value stops 4 px before the 32 px state circle.
- hint: plain tooltip 24 high (M3 24 dp) against Flutter 32, fill inverse-surface 2f3035 against Flutter's test default 707070. No line cap for Neper; the wrapped text keeps all three lines.
- Windows-capture sheets: the Neper pictures of the 33 combo_box capture sheets, edits_states, edits_hover, edits_dialog, combo_hover and native_dark_open0 to 5 are no longer written and were removed (152 PNGs): they place 22 px Windows fields at fixed window positions, so Neper showed crushed empty fields. `looks.windows_capture()` marks such a sheet. native_dark, native_dark_icb and native_dark_mask show Neper fields correctly and stay.
- Not measured against Flutter: native_dark2 to 7 (Windows native controls, no Neper control).
