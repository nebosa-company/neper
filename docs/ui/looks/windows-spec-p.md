# Windows and Windows Dark rows below matched, round 79 lane p

Policy (maintainer, round 79): no real screenshots will exist. A Windows or Windows Dark row with no capture may be raised from review to matched when every checked number agrees with cited public Windows 11 values within tolerance and every state was measured and viewed. A row that has a v3 capture keeps needing that capture.

## 1. Windows Dark radio_group (started to review)

Cause: `windows_dark_choice` copies the native dark radio capture, whose enabled caption is black on #202020 (about 1.1 : 1). The group row has no capture, so nothing forced that.

Fix: a radio of a group in the Windows look is built with `Phase.context` 1000 and up (`radio_in_group`, `windows_choice_high` strips the marker, `windows_dark_choice(..., lit)`), which draws the caption #FFFFFF (#CCCCCC disabled). Windows Light is unchanged by construction (the marker is removed before any other use); every other look calls `radio` as before. The derived dark sheets without a capture, choices_filter (Match group) and radio_dialog, pass the marker too. The standalone radio, radio_states, radio_hover and native_dark2 keep the capture's black on purpose: that capture is their evidence. Measured in the rendered cell: caption ink max 255 on a 32, 32, 32 page, 16 : 1; viewed all four cells of radio_group, plus choices_filter and radio_dialog. Raised to `review` (ceiling: no dark group capture exists, the #707070 frame is a derived choice).

## 2. Rows below matched

Own comparer (`numpy`, exact edge pixels against `ref/windows-native/light` captures of real Windows 11 controls) for text_edit. Why nothing was raised: the Windows look draws v3 (Win32, DevExpress) controls, 21 to 22 px high with square frames; WinUI 3 Fluent values (TextBox 32 px, 4 px radius, ProgressBar 1 px track) describe a different control family, so measuring this drawing against them would fail on purpose, not on a defect.

Windows Light
- text_edit: measured against edit-rest/-hover/-focus/-disabled/-readonly/-selected/-password @1x. Rest, focus, read-only and password: top, bottom, left and right edge pixels equal within 2 levels (frame 236/254/255 ring, #838383 foot, right 230/247). Hover: ring 250 against 254 (4 levels) and disabled face white against the capture's #F0F0F0 (15 levels). The disabled white follows v3's states/edit-button-ellipsis-pressed-options-cardart capture, so the native twin disagrees with the only v3 capture. Height 21 (DFM) against the 24 of the native sample. Missing: a rule saying which of the two disabled faces is right; stays review.
- memo: the Focused, selected cell overdraws the second line (the selection band hides "hexproof an", only "d indestructible" shows). A defect, not a missing number. Needs that fix and the native edit-multiline captures measured.
- date_edit: no v3 capture and no native twin (DTP is 160 x 26 square, ours is the editable combo drawing); Fluent CalendarDatePicker (32 px, 4 px radius) is another shape. Missing: a reference for the drawn control.
- progress_bar: v3 bar 21 px (DFM), native Win32 16 px, WinUI ProgressBar a 1 px track. Missing: any reference for the 21 px bar.
- combo_box, page_control, tree_list, vertical_grid, data_grid, dialog: have v3 captures with ClearType, artwork or bitmap residue left; the policy keeps them capture-bound.

Windows Dark (v3 has no dark mode; the native control stays light or has no twin, so each is the matched light drawing through the colour map)
- date_edit, button_edit, token_edit, check_list_box, progress_bar, page_control, status_bar, toolbar_button, menu_bar, tree_list, vertical_grid, data_grid, dialog: the light row is not matched or is v3-captured, and the dark twin follows it. Fluent dark tokens (accent #4CC2FF, card #2B2B2B, text #FFFFFF) are the palette already used and measure nothing about size or structure. Missing: a dark capture or a WinUI control of the same shape; none will exist.
- radio_group: section 1.

Result: no row raised to matched. Windows Dark radio_group raised to review.
