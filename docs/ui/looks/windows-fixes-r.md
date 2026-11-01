# Windows Dark legibility and Windows memo, round 80 lane r

Windows Light 86.7 (unchanged), Windows Dark 78.7 to 81.3 (overlay `status.d/zz...-r80r.json`, two z more than audit 39's file).

## 1. Dark captions that were black on #202020

Cause: three drawings copied a native capture whose caption is black (the gallery's WM_CTLCOLORSTATIC colouring does not reach a radio's text, and the unthemed group box and the ItemsView header use black).

- Radio: `windows_dark_choice` draws every caption #FFFFFF (#CCCCCC disabled); the lit-only mark of round 79 stays as plumbing. Affects radio, radio_states, radio_hover, native_dark, native_dark2 and every derived radio.
- group_box: `native_dark6` draws "Group" white (#9D9D9D disabled), and `windows_group_box` takes the 3.3 : 1 frame line of the radio group (`looks_o78.dark_group_line`; it was #333333, 1.29 : 1).
- Header (native_dark7): Name and Kind white on the #191919 band; the pressed Size cell is #838383, where black stays.
- The three native sheets keep black outside the Windows Dark look, so Windows, Neper and the other looks render byte for byte as before.

Scan (scratch script, not committed): every Windows Dark PNG at 1x (427), pixels at most 22 levels bright whose 9 x 9 median is 26 to 90, clustered, then every cluster cropped at 2x and viewed (62 crops). Before: black text in the radio cells of native_dark, radio, radio_states, radio_hover, in native_dark6 and native_dark7. After: 39 files still hold clusters, all dotted focus rectangles, shadows, the radio dot, the cursor glyph and the Ok frame, none text; the syslink "a link" is blue (about 2.8 : 1, not near-black, left). Limit: the scan finds near-black ink only; mid-grey ink on a mid-grey fill is not measured.

Measured for the two raised rows: see the notes in the overlay (mark 24 x 22 of all ten native radio captures 0 px off; groupbox-rest and -disabled 0 px off below the caption row; caption ink boxes within one pixel; caption ink 255 on 32, 16 : 1).

## 2. memo

Defect: the light GDI edit sets the unselected glyphs in two passes clipped left and right of the selection band over the full height, so lower rows lost the glyphs between the band's edges. The Dark edit uses another path and was whole. Fix in `widget.e` (two more clipped passes above and below the selected row). Viewed all eight cells of windows/memo.png and windows-dark/memo.png.

## 3. Rows still below matched, and the evidence missing

Light
- text_edit: disabled face (white in v3's capture, #F0F0F0 native) and hover ring differ; needs a rule saying which capture is right.
- memo: no v3 capture of a TcxMemo; the native edit-multiline captures hold other text and a native frame (8 to 15 levels off v3's); no pixel comparison exists.
- combo_box, page_control, tree_list, vertical_grid, data_grid, dialog: measured against 1:1 captures with ClearType, artwork or bitmap residue left; capture-bound.
- date_edit: no v3 capture, no native twin of the editable combo drawing.
- progress_bar: v3's 21 px bar was never captured (native 16 px).

Dark (v3 has no dark mode; each is the matched light drawing through the colour map, a dark capture of the same shape would be required)
- radio_group: no dark group capture; the #707070 frame is a choice.
- date_edit, button_edit, token_edit, check_list_box, progress_bar, page_control, status_bar, toolbar_button, menu_bar, tree_list, vertical_grid, data_grid, dialog.

Regression: 19 sheets of other looks (card, avatar, banner, divider, linux_button, linux_checkbox, linux_dialog, cup_scroll, cup_alert, cup_menu_bar, status_bar, progress_bar, tree_list, toolbar_button, material_menu_bar, spin_edit, text_edit, label, scroll_bar) re-rendered: identical.
