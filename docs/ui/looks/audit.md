# Looks audit 4, 2026-10-16 (Windows light and Windows dark only)

Independent recompute of the two Windows looks after rounds 4 to 11 (30 controls x 2). Nothing here trusts a self-report. Scale 1.0, PIL and numpy, `python -I`, scratch tools in a temp folder (not the workers' `scripts/looks_*.py`). Audit 3 and its evidence check of the other looks follow below, unchanged.

Result. Windows (light): matched 13, review 16, started 1, ready 0 (workers claimed matched 15, review 14, started 1; audit 3 had matched 7, review 19, started 4). Windows dark: matched 0, review 17, started 13 (workers claimed matched 3, review 16, started 11). Page completion after this audit: Windows Light 76 %, Dark 43 %, the Windows flavor 59 %, all five flavors 47 %.

Windows (light) changes against the workers' claims. Downgraded from matched: combo box (one flat pixel 3 levels off in the flat card combo, one 4 levels off in the open Condition list head, the in-place grid editor combo captured with no cell), image combo box (the same head pixel; the open Art 2 reference head shows another item than ours), group box (the open frame reference has its interior blanked, the three Options title bars fail the ink rule, the page header hover grab has no cell). Upgraded from the workers' review: list box. Windows dark: the three matched claims (text edit, spin edit, mask edit) fall to review: the native dark edit is 150 x 24 and ours 141 x 22, and the workers' zero followed cutting two plain rows (against the uncut capture 693 of 3137 flat px are off at rest). Toolbar button and vertical grid dark fall from review to started (no native dark reference exists for either).

## Method

Fresh renders. All 131 `examples/looks` apps were compiled with the committed `build/windows/neper-self.exe` (arena 4g) and run in 361 (app, argument) combinations in a scratch folder (every no-argument app run, the argument lists of `scripts/looks_scale_sheets.json`, the 892 candidate lists of `looks_scale_check.py` for the 12 multi-sheet apps, `page_control t12 t13 t14`). Every Windows and Windows dark PNG a run wrote was hashed against the committed one; no sheet had two writers with different bytes. Light: of 616 committed PNGs, 412 are byte for byte what HEAD renders; at scale 1.0 that is 303 of 308 (not reproduced: dialog_more, dialog_more2 and dialog_more3, last committed at 85c946922 before later lib changes, and the two scale tile sheets), and 199 of 308 `@1.5x` PNGs differ from a fresh render. Dark: 331 of 618 identical; 87 of 309 at 1.0 differ (every popup_menu_sel_*, popup_menu_sub_* and menu_bar_open_* sheet, data_grid_bottom2 and bottom3, data_grid_states, dialog_more*, list_box_blur, list_box_dialog, list_box_focus) and 200 at 1.5. All comparisons below use the fresh renders. One app does not run at HEAD: `toolbar_button toolbar_button_hot` traps (`build_hot` returns 10 cells for 9 allocated, `slice end 10 out of bounds for len 9`); a scratch copy with `ret (9usize, ok)` reproduces the committed toolbar_button_hot.png byte for byte, so only the app source is wrong. `linux_button` also exits 1 (not a Windows sheet).

Reference integrity. The 278 `ref/windows` sheets split into 644 crops (XY cut on the sheet background). Hashed and pixel-checked against the 606 raw grabs: 618 are exact sub-images of one grab, 11 are exact except their last row (the three toolbar sheets: row 25 from x 288 on is the bar's own #D2D2D2 edge, edited in the reference, not captured), 15 are composites or edited (6 combo and 6 image combo open lists = a head crop over a popup crop, the group box frame with its interior blanked, the radio dialog group, the older 150 % data_grid@1.5x capture). Six reference sheets have no sheet of ours: combo_box_flat-left, data_grid_missing, data_grid_sort, scroll_bar_live-across, splitter_live-across and the raw main-window grab. The token edit references are real exact crops (audit 3's stand-in finding does not hold).

Comparison. Structural pixel of the reference: a pixel in a straight run of 11 or more equal pixels whose colour occurs 30 or more times in the sheet and that is not within 1 px of a non-flat pixel; off = more than 2 levels in any channel. The mask comes from the reference only. The workers' `looks_cells.py` ANDs it with the structural mask of ours, so a reference-flat pixel where ours is not flat (an anti-aliased corner) is never counted; two such pixels exist (combo_box_flat_card 1 px at 3 levels, image_combo_box_open_condition_head 1 px at 4 levels) and are counted here. Same-size sheets are compared in place (ours at the reference position); where the sheet sizes differ the crop is placed at the offset of fewest flat-px off within the sheet (the offset is a free parameter, only sizes and inner geometry are tested). Excluded and counted apart: pixels within 2 px of non-flat text ink (glyph anti-aliasing against ClearType, reported as `text`), v3's coloured and gray icon bitmaps (toolbar strips: every group of pixels up to 20 x 20 that differs from the strip background; the combo flat card crops: the neighbouring toolbar icons from x 156; the group box title bars: the icon area from x 436), and the edited toolbar row is compared as given. Ink boxes: lines of pixels more than 60, 100 or 150 levels from the cell background, rows within 2 blank rows count as one line (a mnemonic underline), boxes within 1 px at 60 and at 100 or 150. A crop passes with 0 chrome px off and its ink boxes in agreement; a text line whose glyphs differ in content (a second check on luminance after the best 1 px shift) also fails it.

States. The 558 manifest rows of `ref/windows/states` (a row is a captured state; the 49 dialog and main-window rows are bases). A row is credited to a crop when the crop is an exact sub-image of that grab and the grab differs from its nearest same-size rest grab inside the crop; `identical` = the grab equals its rest grab (no distinct look) or the pressed grab is unchanged inside the held crop built from it. `matched` needs every captured state of the control credited and passing, so a state with no crop keeps a control at review; uncaptured states are listed as unverified; nothing is `ready`.

Windows dark. Reference = `ref/windows-native/dark` at @1x (191 captures). `matched` needs the native dark geometry, text and every native-dark-captured state; the native-light-in-dark controls (tab control, status bar, date picker and calendar, menu bar, message box and task dialog, group box frame, progress bar, list box and combo drop list, the light toolbar) have no dark reference and stay `started` where nothing was compared. Numbers come from placing the native control rect in our dark sheet at the offset of fewest flat-px off, without cutting rows.

## Windows (light) look

Crops = reference crops of the control's sheets that pass / all (chrome = flat px off outside text; text = flat px off within 2 px of text ink). States = captured manifest rows: pass / fail / no cell / identical to rest.

| Control | Workers | Audit 3 | Now | Crops | States | Key numbers | Unverified (no capture) |
|---|---|---|---|---|---|---|---|
| Label | matched | matched | **matched** | 12/12 | 0 / 0 / 0 / 2 | 0 flat px off, max 1 level, ink boxes within 1 px; link hover and pressed identical to rest | disabled (native only), rotated, other backgrounds |
| Button | review | review | **review** | 74/80 | 57 / 1 / 2 / 3 | 0 chrome px; 6 crops fail ink boxes; the disabled Edit Rule button and the pressed card art arrow button have no cell | toggle, split, loading, plain kinds |
| Check box | matched | matched | **matched** | 29/29 | 16 / 0 / 0 / 0 | 0 flat px off, max 0 levels (7 hover, 5 pressed, 4 focus) | disabled, indeterminate (native only) |
| Radio button | review | review | **review** | 20/20 | 14 / 0 / 1 / 9 | 0 px off; the hover over Search Cards has no cell | disabled |
| Radio group | matched | matched | **matched** | 17/17 | n/a | 0 px off, max 2 levels, ink within 1 px | disabled |
| Text edit | review | review | **review** | 37/37 | 2 / 0 / 0 / 0 | 0 chrome px (8 text-edge px max 4 levels); hot key and password edits stand in, no TcxTextEdit is captured | every state of the control, selection, read-only, disabled, invalid |
| Spin edit | matched | matched | **matched** | 37/37 | 16 / 0 / 0 / 0 | 0 chrome px (8 text-edge px max 4 levels); tiles fitted to these captures | disabled, read-only |
| Combo box | matched | review | **review** | 41/44 | 59 / 2 / 1 / 4 | 1 flat px 3 levels (flat card drop button edge), 1 px 4 levels (Condition head); flat Mode combo ink fails on a foreign pixel; grid editor combo no cell | disabled, read-only |
| Image combo box | matched | review | **review** | 28/29 | 27 / 1 / 0 / 1 | 1 flat px 4 levels in the open Condition head; the Art 2 composite head shows Stretch where ours shows Top-Left Corner | disabled, row hover |
| Date edit | started | started | **started** | none | - | no TcxDateEdit with an editor or button in any capture | every state |
| Mask edit | matched | matched | **matched** | 37/37 | 3 / 0 / 0 / 0 | 0 chrome px (rest, hover, focus) | typed text, invalid, disabled, read-only |
| Memo | review | started | **review** | none | - | no TcxMemo captured; the native multi-line edit was sampled only (foot 131 against 187 and 190) | every state |
| Button edit | matched | review | **matched** | 37/37 | 7 / 0 / 0 / 0 | 0 chrome px; audit 3's ellipsis pixel is gone | read-only, invalid |
| Token edit | matched | started | **matched** | 3/3 | rest only | 3 exact crops of the Filter Cards tab, 0 px off | focus, hover, disabled, tokens present |
| Check list box | review | review | **review** | 12/15 | 5 / 1 / 0 / 5 | 13 flat px up to 95 levels in the 3 selected focused row crops (audit 3: 893 to 956 px) | disabled, multi-select, indeterminate rows |
| Progress bar | review | started | **review** | none | 0 / 0 / 3 / 0 | not in any v3 frame; runs set from the native light captures | every state |
| Group box | matched | matched | **review** | 1/4 | 0 / 0 / 1 / 0 | frame reference has its interior blanked; the 3 title bars fail ink; page header hover has no cell | disabled, focus |
| Page control | review | review | **review** | 8/21 | 4 / 10 / 0 / 18 | strips 0 chrome px; 156 px near tab text (max 212 levels) and the tab icon groups fail | disabled tab, scroll buttons |
| Splitter | matched | review | **matched** | 8/8 | 0 / 0 / 0 / 6 | 0 px off, max 2 levels; 3 hover and 3 pressed grabs show no distinct look inside the strips | drag, disabled |
| Status bar | matched | matched | **matched** | 8/8 | 0 / 0 / 0 / 4 | 0 px off, max 0 levels | disabled panels, pressed panel |
| Toolbar button | matched | review | **matched** | 11/11 | 14 / 0 / 0 / 10 | 0 flat px off outside the v3 icon bitmaps; reference row 25 (x 288 on) is edited | checked, focus, dropdown, disabled |
| Menu bar | matched | review | **matched** | 21/21 | 24 / 0 / 0 / 0 | 0 px off, max 1 level (rest, hot, open titles) | disabled item, Alt-key focus |
| Popup menu | review | review | **review** | 14/77 | 14 / 63 / 8 / 8 | 370 chrome px over 32 crops, ink boxes fail on 17 (underlines, arrow rows, icon column) | disabled items beyond the captured menus |
| Hint (tooltip) | matched | review | **matched** | 6/6 | 6 / 0 / 0 / 0 | 0 px off, max 1 level, ink within 1 px | multi-line, other placements |
| Scroll bar | review | review | **review** | 0/1 | 0 / 16 / 1 / 1 | live bar 611 px off (586 chrome, max 240 levels) | disabled, horizontal |
| List box | review | review | **matched** | 3/3 | 2 / 0 / 0 / 2 | 0 px off, max 1 level, ink within 1 px (audit 3: ink 2 to 3 px off) | disabled, multi-select |
| Tree list | review | review | **review** | 0/11 | 0 / 7 / 1 / 4 | 871 chrome px, 6047 px in all, max 255 levels | disabled |
| Vertical grid | review | review | **review** | 0/11 | 0 / 4 / 2 / 5 | 6206 chrome px, 15,825 px in all | other editors, disabled |
| Data grid | review | review | **review** | 0/68 | 0 / 49 / 2 / 13 | 41,354 chrome px, 65,590 px in all | edit mode, disabled, sort and filter popups, 150 % |
| Dialog (form chrome) | review | review | **review** | 68/99 | 7 / 0 / 0 / 0 | title bars and captions 0 px off; 31 body crops fail (app content, not composed) | caption pressed, resize, disabled |

Counts: matched 13, ready 0, review 16, started 1.

Ten largest remaining mismatches (flat px off in one crop, text included; dialog bodies are app content and left out): data_grid_group2 6219 and 4701; data_grid_group 5973; data_grid_group3 5538; data_grid_hover8 3377; data_grid_main 2291; vertical_grid_states 1796; vertical_grid_hover and states 1399 (each of 4 crops); tree_list_expanded 1297; data_grid_shortcuts_hover 1134.

Unchanged since audit 3. The reference-bearing sheets of the seven controls audit 3 confirmed (label, check box, radio group, spin edit, mask edit, group box, status bar) are byte for byte the audit 3 commit's, except label.png (a new Disabled cell) and edits_states.png (the disabled button edit cell re-laid, now passing); the rest sheets checkbox.png, mask_edit.png, radio_group.png and spin_edit.png gained disabled or read-only cells. The recomputed crops still match.

## Windows dark look

| Control | Workers | Now | Native dark reference | Evidence |
|---|---|---|---|---|
| Label | review | **review** | label-rest | white Segoe UI on #202020 matched in colour; Tahoma text has other ink boxes |
| Button | review | **review** | button-* | rings, faces and focus dots follow the native ones; native 110 x 32 captures leave 890 to 1518 of 2315 to 3045 flat px off |
| Check box | review | **review** | checkbox-* | 13 x 13 marks equal (8 of 2184 flat px off at rest, 123 pressed, 75 to 152 disabled); caption fonts differ |
| Radio button | review | **review** | radio-* | native tiles used; caption and focus rectangle are v3's |
| Radio group | started | **started** | none (frame stays light) | frame not compared |
| Text edit | matched | **review** | edit-* | 150 x 24 against 141 x 22: 693 of 3137 flat px off at rest, 650 of 3102 focused |
| Spin edit | matched | **review** | spin-* | up-down 26 of 98 off (1 chrome), edit part 264 of 1234 off |
| Combo box | review | **review** | combo-* | 887 of 3082 (edit rest), 638 of 3089 (list rest) off |
| Image combo box | review | **review** | combo-list-* | list frame only; no native pictures |
| Date edit | started | **started** | none (stays light) | not compared |
| Mask edit | matched | **review** | edit-* | same 22 against 24 frame as the text edit |
| Memo | review | **review** | edit-multiline-vscroll | 2215 of 12,743 flat px off; native scroll bar is light |
| Button edit | started | **started** | none for the ellipsis button | edit frame only |
| Token edit | started | **started** | none | edit frame only |
| Check list box | review | **review** | checklist-* | face and row colours; native check boxes are the light theme's |
| Progress bar | started | **started** | none (native is light) | not compared |
| Group box | started | **started** | none (frame stays light) | not compared |
| Page control | started | **started** | none (native is light) | not compared |
| Splitter | started | **started** | none (no native splitter) | not compared |
| Status bar | started | **started** | none (native is light) | not compared |
| Toolbar button | review | **started** | none (native is the light toolbar) | washes are guesses |
| Menu bar | started | **started** | none (native is white) | not compared |
| Popup menu | review | **review** | menu-popup-* | frame, body and separator colours equal; hot row has no native fill |
| Hint (tooltip) | review | **review** | tooltip-rest | frame ring exact on the 126 x 20 cell; balloon variant has no cell |
| Scroll bar | review | **review** | vscroll-*, hscroll-* | native values for track and thumb; 2592 of 2866 flat px off against the 17 px native bar; hover and pressed equal rest |
| List box | started | **started** | none (unthemed light list) | not compared |
| Tree list | review | **review** | tree-* | colours from the capture; markers are mapped light tiles |
| Vertical grid | review | **started** | none (no native property grid) | list view colours borrowed only |
| Data grid | review | **review** | listview-* | colours from the capture; no per-cell diff |
| Dialog (form chrome) | review | **review** | window-*, dialog-* | caption cells 0 of about 7300 flat px off (worker); close button 33 against 46 wide |

Counts: matched 0, ready 0, review 17, started 13. Controls with a native dark capture but no match at native geometry: all 17 review rows; controls where the native control stays light in dark mode or does not exist (no reference): radio group frame, date edit, button edit, token edit, progress bar, group box, page control, splitter, status bar, toolbar button, menu bar, list box, vertical grid.

## Scale robustness (sample of 12 sheets)

The workers' `scripts/looks_scale_check.py` on button, checkbox_states, radio_group_states, edits_dialog, spin_edit, combo_box, image_combo_box, popup_menu_file, tree_list, data_grid_top, status_bar and menu_bar reports every sheet passing at 1.5 and at 2.0 (exact / within a device pixel, thresholds 93 and 95: button 94.2 / 100 and 98.3 / 100, spin edit 96.6 / 99.4 and 99.2 / 99.4, status bar 96.4 / 100 and 95.6 / 100, image combo box 98.7 / 100 and 99.9 / 100, the rest 100). Its checker leaves text out, lets a run end softly where the 1.0 edge is a blend and rounds like `winpx.edge` (the rule under test). An own check (text left out like theirs, every 1.0 run of 8 or more equal pixels outside the sheet background must be a run of scale times the length at the rounded place, colour within 8 levels, the pixel just past each end not of the run colour; exact / within 1 px) gives, at 1.5 and 2.0: button 90.5 / 94.3 and 98.5 / 99.7; check box 100 and 100; radio group 100 and 100; edits_dialog 100 and 100; spin edit 89.4 / 92.5 and 85.5 / 92.8; combo box 100 and 100; image combo box 86.1 / 95.8 and 83.7 / 92.8; popup menu file 100 and 100; tree list 92.5 / 100 and 100; data grid top 99.7 / 99.9 and 99.7 / 99.9; status bar 91.6 / 99.2 and 90.4 / 98.4; menu bar 100 and 100. The runs that fail on the image combo box are the vector stand-in icons (a 2.0 render viewed shows them crisp); spin edit and image combo box at 2.0 are just under the 93 % threshold on the stricter check. Scale stays informational for the statuses.

## Findings for the maintainers

- `scripts/looks_cells.py` ANDs the reference's structural mask with that of ours (`smask & omask`), which hides a reference-flat pixel where ours is not flat; the two pixels above were hidden that way. Its ink rule groups rows without merging a mnemonic underline, which makes the 'Row Color:' label crop fail at the 60 level (it passes at 100 and 150).
- 204 light and 287 dark committed PNGs are not what HEAD renders (87 dark and 5 light sheets at 1.0, 199 and 200 at 1.5); the page thumbnails of the dark popup, menu bar and grid sheets are stale. `toolbar_button_hot` traps at HEAD (`build_hot` returns 10 for 9 cells).
- Reference edits that are not live pixels: the toolbar crops' row 25 from x 288, the blanked Deck Legality interior, the head over popup composites of the 12 open list sheets.
- The scale checker's tolerances (soft ends, text left out, colour 8, runs within 1) are looser than an exact run test; see the sample above.

---

# Looks audit 3, 2026-10-16

Independent recompute after rounds 4 to 7 (226 interaction-state captures, 298 + 34 hover captures, winpx scale robustness, dark variants of all four flavors). Nothing here trusts a self-report. A fresh render check first: 16 apps (button, checkbox, radio, mask_edit, spin_edit, button_edit, text_edit, popup_menu, data_grid, edits_*, button_*, checkbox_states, radio_states) were rebuilt into a scratch folder and their 240 Neper, Windows, Windows dark and Neper dark PNGs at 1.0 and 1.5 are byte for byte the committed ones, so the committed sheets are current.

## Method (Windows light)

Every ref sheet in `ref/windows/` (230 PNGs, 711 crops: the connected non-background regions) was matched against our sheet with PIL and numpy, `python -I`, scale 1.0. Where the ref sheet has the size of ours the crop is compared in place (cells are on the same grid); where the ref is a single crop and ours a full sheet the crop is placed at the offset of least structural error within 4 px (the offset is then a free parameter, only sizes and inner geometry are tested). 693 of 711 crops were found as exact sub-images of one of the 606 raw captures (558 state grabs plus dialog, menu and main-window grabs; hash then pixel check); of the other 18, 15 are composites (6 combo and 6 image combo open lists, the Select Format frame with its interior blanked, the radio dialog group, the main-window data grid) and 3 are tiny exact crops (two 9x5 menu glyphs and a 1 px splitter strip). Each captured state (558 manifest rows) was credited to a cell only when the state differs from its nearest rest grab inside the crop.

Strict rule as in audit 2: structural = a ref pixel in a flat fill or a straight run of 11 or more equal pixels (colour seen 30 times or more, not within 1 px of ink); tolerance 2 levels per channel; text anti-aliasing and ClearType excluded. Added: text ink boxes (pixels more than 60, 100 and 150 levels from the crop background, lines grouped by rows) must agree within 1 px at the 60 level and at one of the other two; v3 coloured icon and card artwork is excluded. A cell passes when it has 0 structural pixels off and its ink boxes agree. `matched` needs every captured state of the control to have a cell and every own cell to pass; states with no capture are listed as unverified; `ready` also needs every state the control can have to be captured and matching.

Result: matched 7, ready 0, review 19, started 4. No control can be `ready`: no control has a capture of its disabled state (the single disabled capture, the Edit Rule button, has no cell), and spin edit, check box, radio group, mask edit, group box, label and status bar, the best cases, all lack disabled and one or more of indeterminate, read-only, invalid.

Hover: 148 cells sit in the hover sheets (button_hover, checkbox_hover, radio_hover, check_list_box_hover, combo_hover, edits_hover, tree_list_hover*, vertical_grid_hover, data_grid_*hover*, toolbar_button_hot, menu_bar_hot, status_bar_hover, title_bar_hover, splitter hover); all 148 are exact crops that also occur in a `hover-*` grab, so the claimed hover cells do use the real hover captures. 55 of the 148 pass. 7 of those cells come from grabs pixel-identical to their rest grab (check list rows, the Internet Authentication combo edit and the grouped grid rest): the control shows no distinct hover there. The four `*_held` sheets are pressed states from non-hover grabs.

Scale (informational for `matched`, none downgraded for it): `scripts/looks_scale_check.py` at 2.0 passes every baked-tile control except mask_edit (92.0 % of runs hold, threshold 93, clean on view): button 99.7, checkbox 96.9, radio 100, spin 94.7, button edit 96.7, text edit 93.2, popup menu file 100, data grid 99.6. At 1.5 (informational) button 76.4, checkbox 89.0, radio 87.2, mask edit 92.8, popup menu file 79.2 (uneven rings, dotted focus rectangles) while spin, button edit, text edit and data grid stay at 93 to 98. 58 Windows sheet apps were rendered at 2.0 and all ran except edits_hover, which dies with `e.mem.Exhausted` at 2.0 (the 4g arena). Viewed at 2.0: button, mask edit, page control (tab bevels double up) and check list box (blocky check glyphs).

Neper (light) is left at `ready` (the baseline: the look is its own reference); the contrast pass nevertheless flags two Neper sheets: label (3.8:1 text) and image combo box (3.2:1 text). Neper dark: `button`, `hint` fall to started and `toolbar_button` stays started because the PNG shows light text on the light accent face (1.1:1) although the earlier note measured the label at 7.7:1.

## Windows (light) look

Cells = own cells matching / own cells. States = captured manifest rows: match / fail / no cell / identical to rest (a hover or pressed grab with no distinct look).

| Control | Was | Now | Cells | States (match / fail / no cell / identical) | Key numbers and unverified states |
|---|---|---|---|---|---|
| Label | matched | **matched** | 11/11 | 0 / 0 / 0 / 2 | all 11 label cells match the live crops, 10 with 0 structural px off and 1 with a single px (a descender row of text, 191 levels); ink boxes within 1 px on all 11; the link hover and pressed grabs are pixel-identical to rest.  Unverified: disabled (#6D6D6D guess), rotated labels, other backgrounds, non-ASCII text |
| Button | review | **review** | 46/80 | 29 / 29 / 2 / 3 | 46 of 80 cells match (rest, default, mnemonic and shift cells 15 of 15) but only 29 of 63 captured states do: the DPI-scaled dialog buttons fail in pressed (11 of 24), hover (14 of 31) and focus (4 of 6), up to 372 px with border rows up to 40 levels off.  Unverified: toggle, split, loading and plain kinds (no capture); disabled has one capture and no cell |
| Check box | matched | **matched** | 29/29 | 16 / 0 / 0 / 0 | all 29 cells in 3 sheets match the live crops (0 structural px off, ink boxes within 1 px) and all 16 captured states (7 hover, 5 pressed, 4 focus) match.  Unverified: disabled, indeterminate |
| Radio button | matched | **review** | 14/20 | 10 / 3 / 1 / 10 | 14 of 20 cells match; the selected radio ring and dot are up to 9 levels off (tolerance 2) over 100 to 304 px in radio_states and radio_hover, so 3 captured states fail and the hover over Search Cards has no cell.  Unverified: disabled |
| Radio group | matched | **matched** | 17/17 | n/a | all 17 cells (radio_group_dialog 3, radio_group_states 14, hover crops included) match the live crops with 0 structural px off (max 2 levels) and ink boxes within 1 px.  Unverified: disabled |
| Text edit | matched | **review** | 2/3 | 4 / 1 / 0 / 0 | the shared password-edit chrome is exact (0 px over 2 levels on 496x22) but the hot key edit focused cell has ink boxes 3 px off, so 2 of 3 own cells and 4 of 5 captured states match.  Unverified: selection, read-only, disabled, invalid |
| Spin edit | matched | **matched** | 19/19 | 16 / 0 / 0 / 0 | all 19 cells match the live crops (0 structural px off, max 1 level, ink boxes within 1 px) and all 16 captured states (8 hover, 6 pressed, 2 focus) match.  Unverified: disabled, read-only |
| Combo box | matched | **review** | 13/38 | 10 / 21 / 30 / 3 | 13 of 38 cells and 10 of 64 captured states match; the open-list sheets are composite references with no exact source (6 cells, 17 to 21 px up to 139 levels off), the editable focus is 15 px off (255 levels) and 30 hover and open rows have no cell.  Unverified: disabled, read-only |
| Image combo box | matched | **review** | 14/26 | 2 / 1 / 0 / 0 | 14 of 26 cells match (closed, cell editor, hover); the open-list composites fail (197 px up to 245 levels in the art list, ink boxes up to 4 px in the condition list) and 2 of the 3 captured states match.  Unverified: disabled, row hover |
| Date edit | started | **started** | none | - | no date edit exists in any v3 capture (none is reachable without printing), so nothing is compared.  Unverified: every state |
| Mask edit | matched | **matched** | 6/6 | 3 / 0 / 0 / 0 | all 6 cells exact against the live password mask edit (0 px over 2 levels on 496x22 at rest, hover, focused with caret) and all 3 captured states match.  Unverified: text (non-password) content, invalid mask, disabled, read-only |
| Memo | started | **started** | none | - | no memo exists in any v3 capture, so nothing is compared.  Unverified: every state |
| Button edit | review | **review** | 0/9 | 0 / 7 / 0 / 0 | 8 of 9 cells are exact apart from one frame pixel 4 levels off (tolerance 2) in the ellipsis button, and the disabled cell is 27 px off by up to 84 levels and 2 px shifted, so all 7 captured states fail on that pixel.  Unverified: read-only, disabled (no capture) |
| Token edit | review | **started** | 0/3 | n/a | no token edit exists in the v3 captures; the 3 token_edit_dialog cells are tab-control crops used as a stand-in (1748 px off), so nothing is verified.  Unverified: every state (the reference sheet is a proxy built from the Filter tab crop) |
| Check list box | matched | **review** | 1/15 | 0 / 6 / 0 / 5 | 1 of 15 cells match; rows and check boxes are 893 to 956 px off (up to 95 levels) in every state sheet, 6 of 11 captured states fail and the 5 hover grabs are identical to rest.  Unverified: disabled, multi-select, indeterminate rows |
| Progress bar | started | **started** | none | 0 / 0 / 3 / 0 | the v3 progress bar was never on screen in any capture (3 progress frames show the report window only), so nothing is compared.  Unverified: every state |
| Group box | matched | **matched** | 4/4 | n/a | all 4 cells match (the frame is exact against the Deck Legality crop with its interior blanked; the 3 Options page headers are 0 px off with ink boxes exact at the 60-level threshold outside v3's icon art).  Unverified: disabled, focus (no capture) |
| Page control (tabs) | review | **review** | 0/21 | 0 / 14 / 0 / 18 | 0 of 21 cells match; tab strip edges and the selected tab are 13 to 70 px off (up to 248 levels) with ink boxes 4 to 7 px off, 14 selected or pressed states fail and the 18 hover grabs are identical to rest.  Unverified: disabled tab, scroll buttons |
| Splitter | matched | **review** | 6/9 | 0 / 0 / 3 / 3 | 6 of 9 cells match; the across splitter hover and held cells are 7 px off by 3 levels (tolerance 2), the live strip ink is 2 px off and the 3 pressed grabs have no cell.  Unverified: drag, disabled |
| Status bar | matched | **matched** | 8/8 | 0 / 0 / 0 / 4 | all 8 cells exact (main bar, 3 report-window bars and 4 hover crops: 0 structural px off, max 1 level); the 4 hover grabs are pixel-identical to rest.  Unverified: disabled panels, pressed panel |
| Toolbar button | matched | **review** | 0/11 | 0 / 14 / 0 / 10 | 0 of 11 cells match; the toolbar strips are 195 to 469 px off (up to 176 levels, ink boxes up to 25 px), 14 captured states fail (7 hover, 2 pressed, 5 hint contexts) and 10 hover grabs are identical to rest.  Unverified: checked, focus, dropdown, disabled (identical grabs) |
| Menu bar | matched | **review** | 10/21 | 14 / 10 / 0 / 0 | 10 of 21 cells match (rest and 8 of 9 open titles exact); the 10 hot-title cells are 8 px off by up to 52 levels at the bar right end and 1 px vertical, and the open Online title is 2 px off on ink, so 10 of 24 captured states fail.  Unverified: disabled item, Alt-key focus |
| Popup menu | matched | **review** | 131/172 | 72 / 9 / 12 / 0 | 131 of 172 cells and 72 of 93 captured states match (frames, separators, text); 12-px runs (a mnemonic underline or check glyph) are up to 255 levels off in the View, Search and Print menus (289 px), and 12 hover rows have no cell.  Unverified: disabled items beyond the captured menus |
| Hint (tooltip) | review | **review** | 3/6 | 3 / 3 / 0 / 0 | 3 of 6 hint cells match; the grid header, Cards expand and Filter tooltips are 11 to 26 px off (up to 209 levels, border or shadow).  Unverified: multi-line hints, other placements |
| Scroll bar | review | **review** | 0/1 | 0 / 0 / 17 / 1 | the one live scroll bar cell is 938 px off (up to 240 levels, thumb and arrows) and 17 of 18 captured states (11 hover, 6 pressed) have no cell.  Unverified: disabled, horizontal |
| List box | matched | **review** | 1/3 | 1 / 1 / 0 / 2 | 1 of 3 cells match; the frame is exact (0 structural px, max 1 level) but the blur and dialog cells have text ink boxes 2 to 3 px off, so 1 of 4 captured states fails.  Unverified: disabled, multi-select |
| Tree list | review | **review** | 0/11 | 0 / 3 / 2 / 4 | 0 of 11 cells match; rows, expanders and check boxes are 342 to 1462 px off (up to 255 levels, ink boxes up to 19 px), 3 states fail and 2 have no cell.  Unverified: disabled |
| Vertical grid (property grid) | review | **review** | 0/11 | 0 / 5 / 2 / 6 | 0 of 11 cells match; 1663 to 2280 px off (up to 255 levels) in the Deck Properties grid, 5 captured states fail and the 2 category-list hovers have no cell.  Unverified: other editors, disabled |
| Data grid | review | **review** | 0/66 | 0 / 36 / 2 / 14 | 0 of 66 cells match; grid lines and header bands are 5.8k to 9.5k px off per sheet (up to 254 levels), 36 captured states fail and 2 hovers have no cell.  Unverified: edit mode, disabled, sort and filter popups, 150 % |
| Dialog (form chrome) | review | **review** | 31/79 | 49 / 7 / 1 / 2 | 31 of 79 cells match (title bars within 1 to 2 px); dialog bodies are app content that the sheet does not compose, so the 352k px difference there is not a control mismatch, and 7 captured states fail.  Unverified: caption pressed (not capturable), resize, disabled; inactive caption only for the main window |

Counts: matched 7, ready 0, review 19, started 4 (self-reported before the audit: matched 17, review 10, started 3).

Downgraded from self-reported matched to review: radio, text edit, combo box, image combo box, check list box, splitter, toolbar button, menu bar, popup menu, list box. Token edit fell from review to started (its reference sheet is a tab-control crop used as a stand-in, 1748 px off). Confirmed matched: label, check box, radio group, spin edit, mask edit, group box, status bar.

Ten largest remaining Windows mismatches (structural px off in one cell, tolerance 2 levels; dialog bodies are app content and left out): data_grid_bottom 9509; data_grid_states 9010; data_grid_main 8487; vertical_grid_states 2280; token_edit_dialog 1748 (stand-in reference); tree_list_rules 1462; check_list_box_hover 956; scroll_bar_live 938; toolbar_button_hot 469; button_hover 372.

## The other looks (evidence check)

Every one of the 30 controls has a PNG for each of the seven looks and every PNG referenced by `status.json` and the overlays resolves to an existing file; none is a single colour. For `review` the sheet must satisfy the measured floor on every component (text and its states 4.5:1 or better, other UI parts 3:1; a component below 4.5:1 is allowed only when it is equally low in the twin theme and 2:1 or better, which is how disabled and secondary text show up). The dark looks must also differ from the light twin (mean difference of at least 30 levels; all measure 149 to 229), show no light-only chrome (a white face on a dark page) and no word that passes in the light twin but falls under 4.5:1 in the dark one. `matched` is never used: none of these looks has a live reference.

### Neper dark

Was started 5, review 25; now started 7, review 23.

| Control | Was | Now | Evidence |
|---|---|---|---|
| Label | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Button | review | **started** | not verified: the PNG shows light text on the light accent face (9 cells at 1.1:1) although the earlier note measured the label at 7.7:1. |
| Check box | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Radio button | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Radio group | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Text edit | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Spin edit | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Combo box | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Image combo box | started | **started** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Date edit | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Mask edit | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Memo | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Button edit | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Token edit | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Check list box | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Progress bar | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Group box | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Page control (tabs) | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Splitter | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Status bar | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Toolbar button | started | **started** | not verified: the captioned buttons show light text on the light accent face (2 cells at 1.1:1). |
| Menu bar | started | **started** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Popup menu | started | **started** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Hint (tooltip) | review | **started** | not verified: the PNG shows light text on the light accent face (1 cell at 1.1:1) although the earlier note measured the label at 7.7:1. |
| Scroll bar | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| List box | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Tree list | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Vertical grid (property grid) | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Data grid | started | **started** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |
| Dialog (form chrome) | review | **review** | (unchanged) Neper dark = style.reference(.Dark) tokens, no platform branch. Measured on the 1.0 PNG with PIL (WCAG 2): text #E1E2E9 on page #121318 14.4... |

### Windows dark

Was started 30, review 0; now started 2, review 28.

| Control | Was | Now | Evidence |
|---|---|---|---|
| Label | started | **review** | 26 cells measured on label.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 204 levels mean difference from the light twin, no light-only chrome. |
| Button | started | **review** | 24 cells measured on button.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.0:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.014, 199 levels mean difference from the light twin, no light-only chrome. |
| Check box | started | **review** | 30 cells measured on checkbox.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 199 levels mean difference from the light twin, no light-only chrome. |
| Radio button | started | **review** | 20 cells measured on radio.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 199 levels mean difference from the light twin, no light-only chrome. |
| Radio group | started | **review** | 8 cells measured on radio_group.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 203 levels mean difference from the light twin, no light-only chrome. |
| Text edit | started | **review** | 20 cells measured on text_edit.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.4:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.014, 202 levels mean difference from the light twin, no light-only chrome. |
| Spin edit | started | **review** | 20 cells measured on spin_edit.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 204 levels mean difference from the light twin, no light-only chrome. |
| Combo box | started | **review** | 16 cells measured on combo_box.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 4.4:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.014, 203 levels mean difference from the light twin, no light-only chrome. |
| Image combo box | started | **started** | not verified: 2 words fall under 4.5:1 that pass in the light twin (lowest 3.0:1). |
| Date edit | started | **review** | 16 cells measured on date_edit.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.8:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.014, 206 levels mean difference from the light twin, no light-only chrome. |
| Mask edit | started | **review** | 20 cells measured on mask_edit.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.7:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.014, 202 levels mean difference from the light twin, no light-only chrome. |
| Memo | started | **review** | 16 cells measured on memo.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.7:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.014, 202 levels mean difference from the light twin, no light-only chrome. |
| Button edit | started | **review** | 20 cells measured on button_edit.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.4:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.014, 204 levels mean difference from the light twin, no light-only chrome. |
| Token edit | started | **review** | 16 cells measured on token_edit.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 4.4:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.014, 203 levels mean difference from the light twin, no light-only chrome. |
| Check list box | started | **review** | 8 cells measured on check_list_box.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 198 levels mean difference from the light twin, no light-only chrome. |
| Progress bar | started | **review** | 20 cells measured on progress_bar.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 188 levels mean difference from the light twin, no light-only chrome. |
| Group box | started | **review** | 14 cells measured on group_box.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 202 levels mean difference from the light twin, no light-only chrome. |
| Page control (tabs) | started | **review** | 12 cells measured on page_control.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 203 levels mean difference from the light twin, no light-only chrome. |
| Splitter | started | **review** | 1 cells measured on splitter.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.024, 204 levels mean difference from the light twin, no light-only chrome. |
| Status bar | started | **review** | 6 cells measured on status_bar.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 200 levels mean difference from the light twin, no light-only chrome. |
| Toolbar button | started | **review** | 17 cells measured on toolbar_button.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.1:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.014, 205 levels mean difference from the light twin, no light-only chrome. |
| Menu bar | started | **review** | 6 cells measured on menu_bar.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 204 levels mean difference from the light twin, no light-only chrome. |
| Popup menu | started | **review** | 3 cells measured on popup_menu.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 198 levels mean difference from the light twin, no light-only chrome. |
| Hint (tooltip) | started | **review** | 10 cells measured on hint.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.014, 204 levels mean difference from the light twin, no light-only chrome. |
| Scroll bar | started | **review** | 16 cells measured on scroll_bar.png: text at least 4.5:1 (captions 12:1; the four 4.1:1 parts are non-text scroll thumbs) and other parts at least 3:1; page luminance 0.014, 206 levels mean difference from the light twin, no light-only chrome. |
| List box | started | **review** | 1 cells measured on list_box.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.024, 203 levels mean difference from the light twin, no light-only chrome. |
| Tree list | started | **started** | not verified: 9 words fall under 4.5:1 that pass in the light twin (lowest 2.2:1). |
| Vertical grid (property grid) | started | **review** | 1 cells measured on vertical_grid.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.024, 192 levels mean difference from the light twin, no light-only chrome. |
| Data grid | started | **review** | 1 cells measured on data_grid.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.024, 192 levels mean difference from the light twin, no light-only chrome. |
| Dialog (form chrome) | started | **review** | 23 cells measured on dialog.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.2:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.014, 199 levels mean difference from the light twin, no light-only chrome. |

### macOS / iOS (Cupertino) light

Was started 30, review 0; now started 16, review 14.

| Control | Was | Now | Evidence |
|---|---|---|---|
| Label | started | **started** | not verified: 6 cells under the floor (text 4.5:1, other UI 3:1; lowest 1.6:1). |
| Button | started | **started** | not verified: 6 cells under the floor (text 4.5:1, other UI 3:1; lowest 1.6:1). |
| Check box | started | **review** | 24 cells measured on checkbox.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 2.1:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Radio button | started | **review** | 24 cells measured on radio.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 2.1:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Radio group | started | **review** | 8 cells measured on radio_group.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 2.1:1 or better that is equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Text edit | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.7:1). |
| Spin edit | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 3.9:1). |
| Combo box | started | **review** | 12 cells measured on combo_box.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.4:1 or better that is equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Image combo box | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.8:1). |
| Date edit | started | **review** | 14 cells measured on date_edit.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 4.0:1 or better that is equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Mask edit | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.7:1). |
| Memo | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.7:1). |
| Button edit | started | **review** | 21 cells measured on button_edit.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 2.1:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Token edit | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.7:1). |
| Check list box | started | **review** | 7 cells measured on check_list_box.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Progress bar | started | **started** | not verified: 4 cells under the floor (text 4.5:1, other UI 3:1; lowest 1.2:1). |
| Group box | started | **started** | not verified: 2 cells under the floor (text 4.5:1, other UI 3:1; lowest 3.1:1). |
| Page control (tabs) | started | **started** | not verified: 5 cells under the floor (text 4.5:1, other UI 3:1; lowest 3.8:1). |
| Splitter | started | **review** | 1 cells measured on splitter.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Status bar | started | **review** | 7 cells measured on status_bar.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.1:1 or better that is equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Toolbar button | started | **started** | not verified: 2 cells under the floor (text 4.5:1, other UI 3:1; lowest 3.6:1). |
| Menu bar | started | **review** | 5 cells measured on menu_bar.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Popup menu | started | **started** | not verified: 10 cells under the floor (text 4.5:1, other UI 3:1; lowest 1.8:1). |
| Hint (tooltip) | started | **review** | 7 cells measured on hint.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Scroll bar | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 2.4:1). |
| List box | started | **review** | 8 cells measured on list_box.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Tree list | started | **review** | 49 cells measured on tree_list.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Vertical grid (property grid) | started | **started** | not verified: 13 cells under the floor (text 4.5:1, other UI 3:1; lowest 2.9:1). |
| Data grid | started | **started** | not verified: 16 cells under the floor (text 4.5:1, other UI 3:1; lowest 1.4:1). |
| Dialog (form chrome) | started | **review** | 8 cells measured on dialog.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |

### macOS / iOS dark

Was started 30, review 0; now started 5, review 25.

| Control | Was | Now | Evidence |
|---|---|---|---|
| Label | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.6:1). |
| Button | started | **started** | not verified: 2 cells under the floor (text 4.5:1, other UI 3:1; lowest 1.6:1); 1 words fall under 4.5:1 that pass in the light twin (lowest 4.4:1). |
| Check box | started | **review** | 24 cells measured on checkbox.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 2.7:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 203 levels mean difference from the light twin, no light-only chrome. |
| Radio button | started | **review** | 24 cells measured on radio.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 2.7:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 210 levels mean difference from the light twin, no light-only chrome. |
| Radio group | started | **review** | 8 cells measured on radio_group.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.8:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.012, 211 levels mean difference from the light twin, no light-only chrome. |
| Text edit | started | **review** | 24 cells measured on text_edit.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 2.4:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 207 levels mean difference from the light twin, no light-only chrome. |
| Spin edit | started | **review** | 19 cells measured on spin_edit.png: text at least 4.5:1 and other parts at least 3:1, except 6 cells at 3.5:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 205 levels mean difference from the light twin, no light-only chrome. |
| Combo box | started | **review** | 12 cells measured on combo_box.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.2:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.012, 201 levels mean difference from the light twin, no light-only chrome. |
| Image combo box | started | **review** | 16 cells measured on image_combo_box.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 2.2:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 208 levels mean difference from the light twin, no light-only chrome. |
| Date edit | started | **review** | 14 cells measured on date_edit.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.8:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.012, 212 levels mean difference from the light twin, no light-only chrome. |
| Mask edit | started | **review** | 20 cells measured on mask_edit.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 2.4:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 205 levels mean difference from the light twin, no light-only chrome. |
| Memo | started | **review** | 15 cells measured on memo.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 2.4:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 204 levels mean difference from the light twin, no light-only chrome. |
| Button edit | started | **review** | 21 cells measured on button_edit.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 2.6:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 210 levels mean difference from the light twin, no light-only chrome. |
| Token edit | started | **review** | 16 cells measured on token_edit.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 2.4:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.012, 211 levels mean difference from the light twin, no light-only chrome. |
| Check list box | started | **review** | 7 cells measured on check_list_box.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.025, 204 levels mean difference from the light twin, no light-only chrome. |
| Progress bar | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.6:1). |
| Group box | started | **review** | 18 cells measured on group_box.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 2.6:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 209 levels mean difference from the light twin, no light-only chrome. |
| Page control (tabs) | started | **review** | 19 cells measured on page_control.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.012, 206 levels mean difference from the light twin, no light-only chrome. |
| Splitter | started | **review** | 1 cells measured on splitter.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.025, 210 levels mean difference from the light twin, no light-only chrome. |
| Status bar | started | **review** | 6 cells measured on status_bar.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 4.2:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.012, 206 levels mean difference from the light twin, no light-only chrome. |
| Toolbar button | started | **review** | 15 cells measured on toolbar_button.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 2.9:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.012, 214 levels mean difference from the light twin, no light-only chrome. |
| Menu bar | started | **review** | 5 cells measured on menu_bar.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.012, 208 levels mean difference from the light twin, no light-only chrome. |
| Popup menu | started | **review** | 20 cells measured on popup_menu.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 2.3:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.025, 202 levels mean difference from the light twin, no light-only chrome. |
| Hint (tooltip) | started | **review** | 7 cells measured on hint.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.012, 209 levels mean difference from the light twin, no light-only chrome. |
| Scroll bar | started | **started** | not verified: light chrome on the dark page (7 white faces). |
| List box | started | **review** | 8 cells measured on list_box.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.012, 206 levels mean difference from the light twin, no light-only chrome. |
| Tree list | started | **review** | 49 cells measured on tree_list.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.012, 208 levels mean difference from the light twin, no light-only chrome. |
| Vertical grid (property grid) | started | **review** | 21 cells measured on vertical_grid.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.012, 210 levels mean difference from the light twin, no light-only chrome. |
| Data grid | started | **started** | not verified: 2 illegible words. |
| Dialog (form chrome) | started | **review** | 8 cells measured on dialog.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.012, 202 levels mean difference from the light twin, no light-only chrome. |

### Android (Material) light

Was started 30, review 0; now started 5, review 25.

| Control | Was | Now | Evidence |
|---|---|---|---|
| Label | started | **review** | 32 cells measured on label.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 2.3:1 or better that is equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Button | started | **review** | 52 cells measured on button.png: text at least 4.5:1 and other parts at least 3:1, except 6 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Check box | started | **review** | 45 cells measured on checkbox.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Radio button | started | **review** | 30 cells measured on radio.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Radio group | started | **review** | 39 cells measured on radio_group.png: text at least 4.5:1 and other parts at least 3:1, except 6 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Text edit | started | **review** | 26 cells measured on text_field.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Spin edit | started | **review** | 36 cells measured on spin_edit.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Combo box | started | **review** | 26 cells measured on combo_box.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 2.3:1 or better that is equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Image combo box | started | **started** | not verified: 2 cells under the floor (text 4.5:1, other UI 3:1; lowest 2.0:1). |
| Date edit | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.2:1). |
| Mask edit | started | **review** | 29 cells measured on mask_edit.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 2.3:1 or better that is equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Memo | started | **review** | 28 cells measured on memo.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Button edit | started | **review** | 33 cells measured on button_edit.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Token edit | started | **review** | 18 cells measured on token_edit.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Check list box | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.6:1). |
| Progress bar | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.2:1). |
| Group box | started | **review** | 40 cells measured on group_box.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Page control (tabs) | started | **review** | 36 cells measured on tabs.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 2.3:1 or better that is equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Splitter | started | **review** | 16 cells measured on splitter.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Status bar | started | **review** | 6 cells measured on status_bar.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Toolbar button | started | **review** | 60 cells measured on fab.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Menu bar | started | **review** | 10 cells measured on navigation_bar.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Popup menu | started | **review** | 11 cells measured on menu.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Hint (tooltip) | started | **review** | 6 cells measured on tooltip.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Scroll bar | started | **review** | 16 cells measured on scroll_bar.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 2.4:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| List box | started | **review** | 27 cells measured on list.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 2.3:1 or better that are equally low in the dark twin (disabled or secondary); no reference screen, so only rendering and contrast are verified. |
| Tree list | started | **started** | not verified: 6 cells under the floor (text 4.5:1, other UI 3:1; lowest 1.5:1). |
| Vertical grid (property grid) | started | **review** | 63 cells measured on vertical_grid.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Data grid | started | **review** | 100 cells measured on data_grid.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |
| Dialog (form chrome) | started | **review** | 6 cells measured on dialog.png: text at least 4.5:1 and other parts at least 3:1; no reference screen, so only rendering and contrast are verified. |

### Android dark

Was started 30, review 0; now started 3, review 27.

| Control | Was | Now | Evidence |
|---|---|---|---|
| Label | started | **review** | 32 cells measured on label.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.0:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.006, 227 levels mean difference from the light twin, no light-only chrome. |
| Button | started | **review** | 52 cells measured on button.png: text at least 4.5:1 and other parts at least 3:1, except 6 cells at 2.9:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 211 levels mean difference from the light twin, no light-only chrome. |
| Check box | started | **review** | 45 cells measured on checkbox.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 222 levels mean difference from the light twin, no light-only chrome. |
| Radio button | started | **review** | 30 cells measured on radio.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 223 levels mean difference from the light twin, no light-only chrome. |
| Radio group | started | **review** | 39 cells measured on radio_group.png: text at least 4.5:1 and other parts at least 3:1, except 3 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 226 levels mean difference from the light twin, no light-only chrome. |
| Text edit | started | **review** | 26 cells measured on text_field.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 214 levels mean difference from the light twin, no light-only chrome. |
| Spin edit | started | **review** | 36 cells measured on spin_edit.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 224 levels mean difference from the light twin, no light-only chrome. |
| Combo box | started | **review** | 26 cells measured on combo_box.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.0:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.006, 224 levels mean difference from the light twin, no light-only chrome. |
| Image combo box | started | **review** | 28 cells measured on image_combo_box.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 2.6:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 228 levels mean difference from the light twin, no light-only chrome. |
| Date edit | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 1.2:1). |
| Mask edit | started | **review** | 29 cells measured on mask_edit.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.0:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.006, 221 levels mean difference from the light twin, no light-only chrome. |
| Memo | started | **review** | 28 cells measured on memo.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 214 levels mean difference from the light twin, no light-only chrome. |
| Button edit | started | **review** | 33 cells measured on button_edit.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 226 levels mean difference from the light twin, no light-only chrome. |
| Token edit | started | **review** | 18 cells measured on token_edit.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.006, 228 levels mean difference from the light twin, no light-only chrome. |
| Check list box | started | **started** | not verified: 1 cell under the floor (text 4.5:1, other UI 3:1; lowest 2.0:1). |
| Progress bar | started | **review** | 20 cells measured on progress.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 2.0:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.006, 226 levels mean difference from the light twin, no light-only chrome. |
| Group box | started | **review** | 40 cells measured on group_box.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 226 levels mean difference from the light twin, no light-only chrome. |
| Page control (tabs) | started | **review** | 36 cells measured on tabs.png: text at least 4.5:1 and other parts at least 3:1, except 1 cell at 3.0:1 or better that is equally low in the light twin (disabled or secondary); page luminance 0.006, 225 levels mean difference from the light twin, no light-only chrome. |
| Splitter | started | **review** | 16 cells measured on splitter.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.006, 220 levels mean difference from the light twin, no light-only chrome. |
| Status bar | started | **review** | 6 cells measured on status_bar.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.006, 225 levels mean difference from the light twin, no light-only chrome. |
| Toolbar button | started | **review** | 60 cells measured on fab.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 220 levels mean difference from the light twin, no light-only chrome. |
| Menu bar | started | **review** | 10 cells measured on navigation_bar.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.006, 216 levels mean difference from the light twin, no light-only chrome. |
| Popup menu | started | **review** | 11 cells measured on menu.png: text at least 4.5:1 and other parts at least 3:1, except 2 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.014, 214 levels mean difference from the light twin, no light-only chrome. |
| Hint (tooltip) | started | **review** | 6 cells measured on tooltip.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.006, 221 levels mean difference from the light twin, no light-only chrome. |
| Scroll bar | started | **review** | 16 cells measured on scroll_bar.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.006, 221 levels mean difference from the light twin, no light-only chrome. |
| List box | started | **review** | 27 cells measured on list.png: text at least 4.5:1 and other parts at least 3:1, except 4 cells at 3.0:1 or better that are equally low in the light twin (disabled or secondary); page luminance 0.006, 216 levels mean difference from the light twin, no light-only chrome. |
| Tree list | started | **started** | not verified: 6 cells under the floor (text 4.5:1, other UI 3:1; lowest 1.7:1). |
| Vertical grid (property grid) | started | **review** | 63 cells measured on vertical_grid.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.006, 225 levels mean difference from the light twin, no light-only chrome. |
| Data grid | started | **review** | 100 cells measured on data_grid.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.006, 220 levels mean difference from the light twin, no light-only chrome. |
| Dialog (form chrome) | started | **review** | 6 cells measured on dialog.png: text at least 4.5:1 and other parts at least 3:1; page luminance 0.023, 174 levels mean difference from the light twin, no light-only chrome. |

