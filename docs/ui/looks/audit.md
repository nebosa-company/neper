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

