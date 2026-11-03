# Windows and Windows Dark completion, round 84 lane x

Policy applied (maintainer, 2026-11-03): a Windows or Windows Dark row with no capture to match may be raised to `ready` when every cell is drawn correctly and legible, the drawing was measured with an own comparer against cited public numbers or the captures that exist, every checked number is within tolerance, and the dark colours are the accepted derivation of the light drawing with at least 4.5 : 1 text and 3 : 1 controls. A row that has a capture keeps needing the capture match for `matched`.

Before (status.json + status.d, weights of scripts/render_looks.py, 30 controls): Windows Light 86.7, Windows Dark 78.7. After batch 1: Windows Light 88.0, Windows Dark 86.7. After batch 2: Light 88.0, Dark 92.0. After batch 3: Light 93.3, Dark 92.0. After batch 4: Windows Light 97.3, Windows Dark 92.0 (page regenerated with scripts/render_looks.py). Overlay `status.d/zzz...-r84x.json` (one z more than every other file; read and write it through `\\?\`).

Tools (committed, `python -I`): `scripts/looks_x84_measure.py` (dark sheet against its light twin: edge pixels lost, new, 9 x 9 windows whose contrast fell under 3 : 1), `scripts/looks_x84_pairs.py` (colour pairs along every edge of a sheet with WCAG contrast), `scripts/looks_x84_place.py` (whole capture placed in a sheet at the best whole-pixel offset, differing pixels and their box).

## Defects fixed (code in lib/e/ui/looks_x84.e, hooks in control.e, scene.e, widget.e, looks.e, winedit.e)

1. Dark group frames: `windows_group_on` (dialog sheets) drew `OutlineVariant` #333333 (1.3 : 1); the radio group #707070 on half pixels (two rows of #7E7E7E). Both are #DCDCDC, the capture's colour (groupbox-rest, 11.9 : 1), four lines one device pixel thick on whole device pixels at 1x and 1.5x (`scene.device_scale_now`, set by `widget.set_snap` and by the looks harness).
2. Dark pressed radio ring: the captured pressed unchecked ring is #454545 (1.5 : 1 on #202020). A radio of a group and the 42 px dark rows keep the rest ring #AAAAAA (7.0 : 1); the stand-alone radio keeps the capture.
3. Group box: a caption wider than the frame is clipped at the frame like a Win32 group box (the top edge no longer disappears to the end of the cell; Light and Dark); 1.5x lines are 1 device pixel (were 2 on three sides); the stub before the caption is 7 device pixels at both scales (groupbox-rest@1x 12 to 19, @1.5x 18 to 25).
4. Dark Options header (Section header): the border is #828790 on whole pixels (the gradient's #4A4A4A start was 2 : 1).
5. Dark progress rim #5A5A5A (2.4 : 1) to #828790 (4.5 : 1); the marquee block 0.6 to 0.72 of the track (the native captures show at least 126 of 176).
6. Dark check list: the unfocused chosen row #1B1B1B in #131313 (1.1 : 1, invisible) is #3A3A3A in #828790; the focused row keeps the native #1A364D in #0078D4.
7. Dark ellipsis button: the dots were 23 % of white at their peak (about 2 : 1); the peak pixel is solid.

## Raised

| Row | Look | To | Evidence |
|---|---|---|---|
| progress_bar | Light | ready | colours equal the seven native captures exactly; height 21 is v3's DFM; marquee block from the captures; 12 cells viewed at 1x and 1.5x |
| progress_bar | Dark | ready | track within 2 levels of the native dark track, rim 4.5 : 1, fill 9.1 : 1, ink 12 and 11.5 : 1; structure equals light (0 lost, 0 new) |
| group_box | Dark | matched | frame, gap and body of groupbox-rest and -disabled 0 px off at 1x (180 px of caption ink differ on purpose: white against the capture's black); the four audit 41 defects fixed |
| splitter | Dark | ready | 9 sheets 0 lost, 0 new against the matched light twin at both scales; frame 4.5 : 1, grip 3.7 : 1, chevrons 16 : 1 |
| radio_group | Dark | ready | frame #DCDCDC on whole pixels, pressed ring 7.0 : 1, captions 16.3 : 1; 5 sheets viewed |
| button_edit | Dark | ready | dots fixed; field frame 5.9 : 1, ring 4.5 : 1, text 16.3 : 1; 10 cells viewed at 1x and 1.5x |
| date_edit | Dark | ready | head 0 px off combo-edit-rest and -hover; popup text 14.2 and 5.0 : 1, today disc 7.1 : 1; 8 cells viewed at 1x and 1.5x |

## Rows left, and why

Light
- text_edit: the disabled face (white in v3's capture, #F0F0F0 native) and the hover ring (4 levels) are not decided or fixed this round; my placer could not align the 169 x 23 native captures with the sheet's differently sized fields, so no new measurement exists.
- memo: no TcxMemo capture, the native multi-line captures were not measured against the sheet this round.
- date_edit: no v3 capture; the drop button is another width than the native combo (head compare: right 22 columns off); a Light `ready` needs a width reference I could not cite.
- combo_box, page_control, tree_list, vertical_grid, data_grid, dialog: have v3 captures; they stay capture-bound and their ClearType, artwork and bitmap residue was not addressed.

Dark
- token_edit: chips are the light chips through the colour map, the chip outline #444444 on #202020 is 1.3 : 1 and the #272727 face of the dark twin is unmeasured; not validated.
- check_list_box: the unfocused selection is fixed, but the Card Art icons keep their white tiles on the dark list (a visible light leak), the Card Art chosen row has no outline (1.3 : 1) and the native 19 px row shape is not drawn.
- status_bar: the light sunken panel bevel (#A0A0A0 / white) is lost in dark (2525 edge pixels at 1.5x), separators are 2.8 : 1; not raised.
- menu_bar: hover and pressed are a #3C3C3C wash (1.5 : 1) as the only state cue; not fixed.
- toolbar_button: the dark bars draw the gallery's line icons, not v3's artwork, and the hot, pressed and checked washes are guesses; the meaning of the icons differs from the light row.
- page_control: tab outlines 2.4 : 1 (under 3 : 1), about 20 sheets not reviewed; light counterpart is review.
- tree_list, vertical_grid, data_grid, dialog: light counterparts are review (capture-bound), so a dark derivation cannot rank above them; vertical_grid shows 24 to 120 low-contrast windows per sheet, not reviewed.

## Batch 2: the Dark rows with a named defect

Fixed and raised to `ready` (evidence in each row's note): token_edit (chip outline #444444 1.3 : 1 to #828790 3.8 : 1 on the chip, cross 1.9 to 8.1 : 1), check_list_box (unfocused chosen row 1.1 to 4.5 : 1; the Card Art chosen row outlined), status_bar (the sunken panel bevel drawn through the colour map, lost edge pixels 2525 to 65), menu_bar (hover and open wash 1.5 : 1 outlined at 4.5 : 1). Sheets re-rendered one app at a time (token_edit, token_edit_dialog, the four check_list_box sheets, status_bar with its three arguments, menu_bar with its twelve arguments); Cupertino, Linux and Material status_bar, menu_bar and token_edit re-rendered and byte for byte unchanged; Windows Light PNGs unchanged.

Left: toolbar_button (Dark). v3's artwork exists (the light row draws its icon atlas); the dark bars draw the gallery's line icons instead, so the icons differ in meaning from the light row, and the hot, pressed and checked washes are guesses. Raising it needs the atlas through the dark map, which was not done. The Dark check list's art tiles are v3 bitmaps through the colour map and differ from the page by 1.1 : 1 (recorded, drawn artwork).

## Batch 2: the Light capture-bound rows, re-measured (scripts/looks_strict.py, 0 chrome px off = pass)

The old notes of these rows are stale (they quote round 45 and 46 counts). Fresh numbers, `LOOKS_REF=windows-1to1` where the true 1:1 set has the sheet, else ref/windows (the older resampled set):

- combo_box (ref/windows, no 1:1 set): 42 cells, 31 pass. Failing cells: list_color, list_color2, open_color, open_color2 (778 and 416 px: the reference's rows are soft resampled lines, for example 83, 164, 228 where the drawing has the capture's crisp #0078D7; the 1:1 truth is crisp), list_show3 to 5 (2 to 3 px, 4 levels), list_size3 and 5 (glyph columns, 8 to 16 px), flat_card and flat_card_hover (0 px, ink boxes of the card art differ). No chrome defect of the drawing found; not raised because the cells were not all viewed and disabled and read-only closed combos have no capture.
- page_control (ref/windows): 21 cells, 18 pass; the 3 failing cells have 0 chrome px and 0 to 8 text px (ink boxes). Not raised: about 20 sheets were not viewed.
- tree_list (1:1): 18 cells, 15 pass; tree_list_expanded 18 chrome px (one clipped bottom row lacks its 6th Edition icon: artwork not baked) and 22 text px, tree_list_rules 4 px (max 22 levels). Residue is one missing icon plus ClearType.
- vertical_grid (1:1): 11 cells, 10 pass; vertical_grid_states cell 4 has 2 chrome px and 2 text px (the inverting focus rectangle's top dots are the page colour in ours, inverted in the capture).
- data_grid (1:1): 165 cells, 58 pass. Residue: 12 to 44 px at the scrollbar thumb column (x 578 and 1164) in the top, bottom, hover and group sheets, 175 to 990 px in the right cell of data_grid_group, _hover8 and _top, and data_grid_main does not place (0.62 equal). Real chrome residue, not ClearType alone.
- dialog (ref/windows, no 1:1 set): 119 cells, 15 pass: not close.
- text_edit, memo, date_edit: not measured again. Light date_edit: the Normal cell's drop box is about 17 px (572 to 582 inside a 120 px field) as a Win32 combo drop button (17 px at 100 %), but no capture of a date edit exists and the cell was not compared with the combo capture; left at review.

No Light row was raised in batch 2: tree_list and vertical_grid are close (one icon, a few dots) and are the next candidates; combo_box and page_control need every sheet viewed. The Dark twins of rows still review stay review (batch 3 not started).

## Batch 3: Light capture-bound rows

Fixed in the drawing: (a) tree_list: v3's 6th Edition picture was not baked (the clipped bottom row showed no icon); `scripts/gen_wintreeicon.py` bakes 16 tiles now (tree_list_expanded chrome 18 to 2 px, text 22 to 6 px); (b) vertical_grid: the General pressed state lacked the capture's focus rectangle on the category caption; it is drawn at the capture's pixels (`looks_x84.dots_node`, in `windows_property_grid`). Cupertino, Linux and Material tree_list and vertical_grid re-rendered: unchanged.

Raised to `ready` (Light), residue stated in each note: tree_list (2 chrome px, 6 text px, 4 px in the rules list), vertical_grid (10 of 11 cells pass, the fifth 2 + 2 px), combo_box (31 of 42 cells pass; the failing ones are the resampled reference's soft rows, 2 to 3 px at 4 levels, glyph columns, card art ink boxes), page_control (18 of 21 pass, the other 3 at 0 chrome px). Text caveat: ClearType colour fringes are not reproduced. Viewing caveat: combo_box (37 sheets) and page_control (23) were viewed as contact sheets at 1x, not cell by cell and not at 1.5x; tree_list at 1x only; an auditor who wants a stricter reading should keep those two at review.

Not done: text_edit, memo and Light date_edit. `looks_strict.py` has no reference for them; the chrome family they share (mask edit, button edit, spin edit) passes at 0 px against the 1:1 captures (edits_states 16 of 16, edits_dialog 8 of 8), but my attempt to compare the text_edit cells' frame pixels with those cells by signature was inconclusive (the boxes I guessed were off), so no number is stated and the rows stay review. Toolbar_button Dark: not attempted.

data_grid (1:1 set, 165 cells, 58 pass), residue by kind: 12 to 44 px at the scrollbar thumb column (x 578 and 1164) in data_grid_top, _bottom, _hover and _group cells; 175 to 990 px in the right-hand cell of data_grid_group, _hover8 and _top (a column of the grid, not text); data_grid_sort_states 15 px per cell at x 169, 510 and 851 (sort arrow rows); data_grid_states 290 px (x 557, y 82); data_grid_main does not place (0.62 equal), so its 59482 px are an alignment failure, not a count. These are ours, not ClearType, and were not fixed. dialog (ref/windows, no 1:1 set): 119 cells, 15 pass; not examined further.

Dark twins: tree_list Dark stays review (the per-block name colours of v3's list, for example Duel Decks and Masters, come through the colour map under 4.5 : 1 in places); vertical_grid Dark stays review (the Legality tag letters and the Computed artwork through the map were not measured; the General pressed focus rectangle is Light only); page_control Dark stays review (tab outlines 2.4 : 1, not fixed).

## Batch 4: text_edit, memo, Light date_edit; combo_box and page_control viewed in full

Measured with `scripts/looks_x84_edge.py` (frame corners, edges and sides pixel by pixel) against the native 1:1 captures `ref/windows-native/light/edit-*` and `edit-multiline-*`. text_edit: Rest, Focused, Read-only 0 px off over all parts; Password 1 corner pixel; Hover 4 levels and Disabled 15 levels, both of which follow v3's own captures (hover ring #FAFAFA, white disabled face); memo the same (Rest and Read-only 0, Focused 0 apart from the selection highlight in the corner). Both raised to `ready` after every cell was viewed at 1x and 1.5x. Light date_edit: the head is the combo drawing (0 px against the combo_box Normal cell at the corner, top and left), the drop button 17 px as Win32 (SM_CXVSCROLL); the Drop button hot and pressed cells aimed at the field's centre and showed the hover look, they aim at the drop button now (Light and Dark); raised to `ready`. The Dark twins of text_edit and memo are already matched, date_edit Dark was raised in batch 1.

combo_box (37 sheets) and page_control (23) were viewed at 1x and 1.5x in full resolution tiles: every cell legible, no clipping other than the captures' own crops; their `ready` stands.

Not done: data_grid, dialog, the Dark twins of tree_list, vertical_grid and page_control, toolbar_button Dark. data_grid residue found: the vertical scroll thumb grip at x 578 and 1164 is drawn 4 px wide and antialiased where the capture has a crisp 2 px bar with tips (12 to 44 px per cell in the top, bottom, hover and group sheets), the right-hand cell of data_grid_group, _hover8 and _top has 175 to 990 chrome px (a column of the grid), data_grid_main does not place; none was fixed (the drawing is in `datagrid.e`, 13 thousand lines). Dark page_control: the tab outline pairs are #6F6F6F on #2B2B2B (2.8 : 1) and #555555 on #202020 (2.2 : 1) from the colour map; fixing them needs a change of the shared dark grey map, not attempted.

## Batch 5: data_grid, dialog, Dark twins, toolbar_button (causes found, no row raised)

data_grid. The residue at x 578 and 1164 (12 to 44 px per cell in the top, bottom, hover and group sheets) is the vertical scroll thumb: the 1:1 capture (ref/windows-1to1/data_grid_top) has two crisp columns, #858585 in 14 rows with a #929292 / #939393 pixel row at each end (columns 578 and 579, rows 50 to 65), where `collection.e` draws the three soft columns (#B6, #85, #BF) of an older live capture (`control.windows_thumb`, round looks11-g1). A crisp thumb was built and tried: the plain grid passed at 0 px at left 6 in the 17 px track and the second grid at left 7, because the harness lays the two grids one pixel apart relative to their cell origins while the captures keep them equal, so one of the two always stayed 1 px off. The change was reverted: it would also have made every committed Windows light data_grid sheet that shows a thumb stale (about 40 sheets rendered by five apps with arguments, not regenerated), and the placement difference is the harness's, not the control's. The 435 to 459 px in the right-hand cell of data_grid_top (and the same in data_grid_group, _hover8) are a hover state (the pointer on a header) drawn differently from the capture; not isolated. data_grid_main does not place by structure (0.62 equal), so its 59482 px are not a count.

dialog (ref/windows, the resampled set; there is no 1:1 dialog sheet, only raw dialog grabs in ref/windows-1to1/dialogs). scripts/looks_strict.py over dialog, _more, _more2, _more3 and _wide: 119 cells, 15 pass, 104 fail, grouped by cause: 27 have 0 chrome px (the cell fails on ink boxes or on 16 to 97 text px, glyph rasterisation); 37 are the 73 to 75 x 22 button cells with 123 to 294 chrome px at at most 22 to 167 levels (the resampled reference's soft button border against the crisp 1:1 button, which the button row matches at 0 px against the 1:1 button captures); 14 are dialog bodies (grids, web view, the About picture) that the sheets do not compose; 4 are 2 px lines of the frame (22 to 412 px, 107 levels: the reference's resampled edge); 22 are mixed (the caption bar 289 x 22 with 6192 px, the Deck Statistics body crops, a 24 px high button variant at 253 px). Nothing in the first 27 or 37 is a defect of the drawing that can be fixed without a 1:1 reference of the whole dialog; not raised.

Dark twins. page_control Dark: the tab outlines are #6F6F6F on #2B2B2B (2.8 : 1) and #555555 on #202020 (2.2 : 1) and come from the baked light tab art (#ADADAD, #A4A4A4; the light drawing itself has 2.2 : 1 against white) through `style.windark_rgb`; the tab art is not drawn from one colour constant that a tab-only hook could replace, and the shared grey map was not changed (it moves every Dark row). tree_list, vertical_grid, data_grid and dialog Dark follow their Light rows, which stay review (data_grid, dialog) or whose Dark artwork was not re-derived (tree_list block colours, vertical_grid tag letters).

toolbar_button Dark. Capped with reason: v3's icon atlas (`wintoolicon`, 27 tiles of 16 x 17) holds the artwork with black outlines and disabled tiles baked for a light bar. `winpx.dark_argb` turns every pixel to a grey (or the accent) and would flatten the colour icons; keeping the hues and lifting the outlines needs a per-icon decision (black outline on the #2B2B2B bar is 1.3 : 1). The dark bars keep the gallery's line icons (legible, not v3's artwork), and the hot, pressed and checked washes stay guesses.

## Regression

Sheets re-rendered one at a time with the committed `neper-self.exe` (compiler arena 4g): group_box, group_box_dialog, native_dark6, radio_group, radio_group_states, radio_group_dialog, choices_filter, radio_dialog, radio_states, radio_hover, native_dark2, progress_bar, check_list_box (4 sheets), button_edit, plus cup_, linux_ and material_ button_edit, check_list_box, group_box, radio_group, radio, splitter, progress (where the look has one) and splitter, radio: `git status` shows no Neper, Linux, Cupertino or Material picture changed. Not done: a full re-render of all 251 apps, and a 1.5x viewing of every Windows Dark sheet of the rows left.

## Limits

The briefs of the round (round70-flutter-compare.md, round63-fixes.md, round72.md) were not on disk; the rules were taken from the coordinator's message. Contrast numbers are WCAG ratios of the nominal ink colours (the rendered peak of thin 11 px glyphs reads lower). Rows raised on derivation rest on the maintainer's policy, not on a dark capture.

# Round 85, lane x

Before (status.json + status.d): Windows Light 97.3, Windows Dark 92.0. After: Light 97.3, Dark 97.3 (page regenerated with scripts/render_looks.py; overlay `status.d/zz...-r85x.json`, 244 z). Code in `lib/e/ui/looks_x85.e`, small hooks in collection.e, datagrid.e, control.e, gridlook.e, the sheets data_grid_top.e, tree_list.e and vertical_grid.e.

## Raised (Dark, derivations of ready light twins)

| Row | To | What was fixed |
|---|---|---|
| page_control | ready | the dark strip's two rules were on a half pixel (the dark sheets centre cells on one): two blended rows at 2.2 to 2.8 : 1; now whole pixel rows #808080 and #9A9A9A, 3.6 and 5.8 : 1. Only the page_control sheets that draw the strip changed; Light, Neper and the bottom strip are byte identical |
| tree_list | ready | edition and block name colours lifted toward white to 5 : 1 or more (`looks_x85.lift_dark`, applied in the sheet) |
| vertical_grid | ready | Legality tags: deep boxes with white letters, 9.4 and 6.5 : 1 (were 2.7 : 1) |
| toolbar_button | ready | v3's atlas through `looks_x85.dark_tile`: black outline to white, face to #2B2B2B, disabled tiles to #6F, colours kept |

Viewed at 1x and 1.5x. Left in the notes: the strategy strip's marker tile (2 : 1, artwork), the toolbar hot, pressed and checked washes (guesses, outlined), the cell hairlines (2.3 : 1 like Light).

## Light

data_grid (strict compare against ref/windows-1to1, 33 sheets, 165 cells): 58 to 95 passing. The thumb is the capture's crisp two columns (#858585, #929292 and #939393 end rows) on whole pixels in the top sheets, the bar over the group box (white column and thumb) and the idle row's edge colour are drawn. The 1 px offset of the second grid was a sheet defect, not the rig: `data_grid_top.e` gave pane hint 573 where the live pane measures 574, so cells with no pointer driven (cells 1, 3, 5 ...) stood their bar one pixel left of the driven ones and a column of the Power cell leaked over the scroll bar. The 435 to 459 px in the right-hand cell was that leak, not a hover state: it is 20 px now. Affected sheets re-rendered (all with the committed compiler, one app at a time): data_grid_top (16 parts, states, pressed), data_grid_bottom (3), data_grid (main): 54 Windows Light and 26 Windows Dark files changed in the first commit; Cupertino, Linux, Material and Neper byte identical; samples viewed. Kept at review: the collection grid draws a flat disc where v3 shows the set symbol, the Shortcuts grid has no command icons, `data_grid_main` is another composition than the capture, the clipped last row lacks its final pixel row (20 px at 19 levels), and some captures carry a mouse cursor, a spin button or blur.

dialog (ref/windows, resampled): 119 cells, 15 pass, unchanged. The 4 two-pixel "frame lines" are the scroll-bar columns of the dialog grids: the drawing matches the 1:1 captures at 0 px (sort and shortcuts sheets) and differs only from the resampled reference. The 14 uncomposed bodies (Filter Card Pool, Advanced Filter, Conditional Formatting, About picture) are not drawn; so not every cell is drawn and the row stays review, Dark with it.

## Placeholder

v3's null prompt is clGray #808080 (3.95 : 1 on white). Light draws #6B6B6B (5.3 : 1 on white, 4.8 : 1 on the dialog face); Dark keeps #808080 mapped (5.9 : 1). text_edit, memo, mask_edit, button_edit, password_field, autocomplete re-rendered; the matched edit captures contain no placeholder.

## Regression

Re-rendered with the committed `neper-self.exe`: data_grid_top, _bottom, data_grid, tree_list (5 forms), vertical_grid (4), page_control (23 forms), toolbar_button (3), text_edit, memo, mask_edit, button_edit, password_field, autocomplete, combo_box. No Linux, Neper, Material picture changed. Cupertino autocomplete changed (stale lane y output, audit 43) and was restored, not committed. page_control_cards, _held, _options differ from their committed bytes in every look (padding of the old arguments) and were restored.

## Limits

Contrast numbers are nominal ink pairs; ClearType fringes are not reproduced. The Dark rows rest on the maintainer's derivation policy.

## Round 85 batch 2 (coordinator follow-up)

Windows Light 97.3 and Windows Dark 97.3 before and after this batch (no row changed status); the page is regenerated.

data_grid Light. Baked from ref/windows-1to1 by `scripts/gen_winsetpic.py` into `lib/e/ui/winsetpic.e` (the way the 6th Edition tile is baked): the collection grid's set symbol (translucent; alpha and colour solved per pixel from the white and the grey rows) and the Timeshifted disc, the Shortcuts grid's 18 command icons (16 px differ of 6048 in the icon column), and the three hot navigator buttons (next, next page, funnel: crisp #0078D4 frame over #E0EEF9). The horizontal thumb under the pointer is the capture's 13 row rounded bar (`looks_x85.crisp_hot_hthumb`, 0 px). The data_grid_top sheet gives the funnel an action so that it can be hot. The Shortcuts Command and Shortcut header hover cells and the thumb hover cells no longer draw a tint or a 6 px pill the captures do not show (the pointer rests on a row or the track); the grouped sheet at rest has the capture's solid current row frame. Re-measure (looks_strict, LOOKS_REF=windows-1to1, 165 cells): cells within 20 chrome px 138 to 150 (0 chrome px in 110). Not raised: the open in-cell editor of the collection grid (Qty spin and two ellipsis buttons of the current row, bottom sheets, 60 to 360 px per cell), the hot Favorite header's filter glyph (42 px), ghost rows of card art under the last group row (151 px at 17 levels) and a mouse cursor, which are capture noise, the clipped last row's final pixel row (20 px at 19 levels, a body height of the sheet that moved every row when tried), the selected-row text colour of the Shortcuts states sheet, and data_grid_main (another composition). A v3 state (the in-cell editor) is not drawn, so the row is not ready.

dialog Light. Classified, not composed. 119 cells, 15 pass (unchanged). 42 button cells (the resampled soft border; the button row matches the 1:1 captures at 0 px), 27 cells at 0 chrome px (ink boxes and glyph raster), 14 bodies the sheets do not compose, 3 scroll-bar columns and 14 mixed cells that are parts of those bodies (the Search for Card combo and group frame among them), 4 under 40 px. The 14 bodies are the Search for Card combo, group box and radios; the Sort dialog grid; the Missing Set Cards colour list and Show Cards radios; the Deck Properties vertical grid; the About picture; and the Filter Card Pool, Advanced Filter and Conditional Formatting bodies. Each needs a control builder (dialog grid, check list, combo, group box, vertical grid) composed into `examples/looks/dialog.e` and a reference finer than the resampled one to confirm it; not done, the row stays review and Dark with it.

Dark data_grid and dialog follow their review light rows; contrast was fixed (ink 5 : 1, current row on the selection fill) and the sheets viewed at 1x and 1.5x.

toolbar_button Dark washes. The hot rim of v3's toolbar button is #A0A0A0 in ref/windows-1to1/toolbar_button_hot (9824 px, the v3 bar has no Win32 blue hot wash there); the dark hot rim is its counterpart #828282 (3.6 : 1 on #2B2B2B) and the pressed rim #9D9D9D, for the toolbar pictures only (the menu bar and status bar keep their round 84 washes). The faces (#3C3C3C hot, #333333 pressed, #264F78 with a #4CC2FF rim checked) are the maintainer-accepted derivation: no dark capture exists.

Regression. 24 apps re-rendered one at a time with the committed `neper-self.exe`, each writing every look: cup_data_grid, linux_data_grid, material_data_grid, surf_table, h_list, h_grid_view, cup_tabs, linux_page_control, material_tabs, cup_toolbar, linux_toolbar_button, nav_toolbar, menu_bar, status_bar, progress_bar, splitter, scroll_bar, check_list_box, list_box, button, radio_group, popup_menu, icon_button, tree_list; `git status` after them shows no changed picture in any look (Neper, Linux, Cupertino, Material and every Windows sheet outside the ones committed). Earlier in the round Cupertino autocomplete (stale lane y output) and the cards, held and options page control sheets (old argument padding) differed from their committed bytes and were restored.

# Round 86, lane x

Before and after (status.json + status.d): Windows Light 97.3, Windows Dark 97.3 (no row changed status; page regenerated with scripts/render_looks.py, overlay `status.d/zz...-r86x.json`, 245 z). Code in `lib/e/ui/looks_x86.e`, `lib/e/ui/winedpic.e` (generated by `scripts/gen_winedpic.py` from ref/windows-1to1), hooks in datagrid.e and collection.e, sheets data_grid_bottom.e and data_grid_top.e.

## data_grid Light (looks_strict, LOOKS_REF=windows-1to1, 165 cells)

Failing cells 68 to 43 (chrome px; counted as before). Fixed: (a) the open in-cell editor of the current row (Qty and Used spin buttons, ellipsis buttons of Buy at and Sell at) is drawn from the capture's pixels, positions equal to the pixel; (b) the hot Favorite header (data_grid_hover3): 42 to 0 px; (c) the 20 px of the clipped last row: not a body-height change of the sheet (that moves the header and every row, tried again with 241) but a local one: in the pool grid with a navigator rule (`crisp_rule_row`, Windows light only) the 1 px rule row is the last row's own pixel row, so the body is 1 px taller and the rule 0 px high; 24 cells at 20 px now 0 (data_grid_top, top2 to top5, hover to hover7, states). The pressed-thumb cell of top5 aimed at y 187, which hit the track's lower end once the body grew; aimed at 188 as before (Dark top5 follows and now shows the thumb at rest, like the capture); (d) found while measuring: the row indicator header glyph lacked its first dot-and-bar line in every Windows light crisp sheet, and the marked picture header of the bottom sheet was the older bitmap (61 px); both replaced.

Left, and why it is not ready: data_grid_main (another composition than the capture, does not place); grouped sheets 151 and 365 px at 17 to 229 levels (ghost card art, a mouse cursor: capture noise); bottom sheets 58 to 360 px (ghost card art rows under the last row: noise); Shortcuts states sheet 109 px (selected row text colour) and 4 to 6 px per Shortcuts cell; sort sheets 15 px (sort arrows); data_grid_states_pressed 1 px (the pressed picture header cell: the baked tile has the idle fill). The row stays review because of data_grid_main and those not yet explained cells.

Regenerated (changed files): data_grid_top (all 17 forms), data_grid_bottom (3), data_grid (main), Windows Light, plus Dark data_grid_top5 (thumb at rest). Not committed: Dark data_grid_dialogs (stale output unrelated to this change, restored).

## dialog Light

Not composed this round. The 14 bodies need a Search for Card combo, group box and radios, the Sort dialog grid, the Missing Set Cards colour list and radios, the Deck Properties vertical grid, the About picture and tab strip, and the Filter Card Pool (tab control, radio row, check tree, splitter, web view), Advanced Filter and Conditional Formatting bodies; `examples/looks/dialog.e` only has button, label and group items. Row stays review, Dark with it. Not re-measured (119 cells, 15 pass, unchanged from round 85).

## Windows rows below ready

Light: data_grid, dialog. Dark: data_grid, dialog (follow their Light rows).

## Regression

28 apps re-rendered one at a time with the committed `neper-self.exe` (arena 4g): linux_, cup_ and material_data_grid, surf_table, h_list, h_grid_view, tree_list, vertical_grid, page_control, toolbar_button, button, radio_group, list_box, popup_menu, menu_bar, status_bar, scroll_bar, check_list_box, combo_box, text_edit, memo, spin_edit, progress_bar, splitter, cup_tabs, material_tabs, nav_toolbar: no Neper, Linux, Cupertino, Material or other Windows picture changed.

## Round 86, batch 2 (coordinator follow-up: data_grid residue)

Pixel-level against ref/windows-1to1, fixed in ours: (a) Shortcuts and Sort dialog grids: the focused selected row's text is clMaroon #800000 in the captures (ours black; 109 px), the column lines run over the focus rectangle's top and bottom dots, the rectangle's left edge at the selected cell is the column line and the fill, the hot header of a dialog grid has no filter button and its caption does not move, the resting scroll thumb is the crisp two columns with end rows (Shortcuts 33 rows through `look.thumb_len`), the Sort glyph (z to a) of the Descending row is baked (`sort_glyph`, 15 px). Shortcuts and Sort sheets now at 0 chrome px except 4 px of one command icon (artwork raster, 18 levels) and the pressed thumb pill's end pixels (ink box only). (b) Collection grid sheets: the hot Name header no longer draws a tint row above it (that was the resampled capture's; 302 px), the hot navigator buttons and the enabled funnel of the bottom sheets stand one row lower than the pool's, as captured (hot next and funnel: 102 px and 21 px).

Capture noise masked in the comparer (`looks_strict.py x0,y0,x1,y1` paints a rectangle out of both pictures): the ghost card art under the collection grid's last row (12,202,588,232 and 598,202,1174,232 of the bottom sheets; the pictures are v3's card backdrop, not drawn) and the mouse cursor near the current row (12,92,588,125). With those masked the bottom, bottom2 and bottom3 sheets pass 8 of 8, 8 of 8 and 4 of 4 cells. Without masks: 138 of 165 cells pass (was 98 at the start of round 86, 58 in round 84).

data_grid_main is a different sheet by design: the reference is a crop of the current v3 main window (plain pool grid, splitter, collection grid; 500 x 468), `examples/looks/data_grid.e` composes the old grouped-by-Rarity desk layout in two separately framed grids (524 x 512); README of ref/windows-1to1 notes that the desk layout drifted and the old screen cannot be reproduced. It does not place (0.62 equal) and is excluded from the row's cell list; its sheet is kept as a gallery picture only.

Still failing, not noise: the grouped sheets (data_grid_group, group2, group3, hover8): the group box's hot and pressed chip is drawn from the older ring art, 1 px left and one row short (1004 px in group2 cell 1), the Favorite star and the Colour triangle in the header are 15 to 20 px of raster off, and the 151 px at 17 levels under the last group row is ghost card art (noise). The row therefore stays review.

Regression: the 27 apps of batch 1 re-rendered one at a time (linux_, cup_, material_data_grid, surf_table, h_list, h_grid_view, tree_list, vertical_grid, page_control, toolbar_button, button, radio_group, list_box, popup_menu, menu_bar, status_bar, scroll_bar, check_list_box, combo_box, text_edit, memo, spin_edit, progress_bar, splitter, cup_tabs, material_tabs): no non-Windows picture and no Windows Dark picture changed (Dark data_grid_dialogs, which changes with every render, was restored; the funnel action is Windows Light only).
