# Windows and Windows Dark completion, round 84 lane x

Policy applied (maintainer, 2026-11-03): a Windows or Windows Dark row with no capture to match may be raised to `ready` when every cell is drawn correctly and legible, the drawing was measured with an own comparer against cited public numbers or the captures that exist, every checked number is within tolerance, and the dark colours are the accepted derivation of the light drawing with at least 4.5 : 1 text and 3 : 1 controls. A row that has a capture keeps needing the capture match for `matched`.

Before (status.json + status.d, weights of scripts/render_looks.py, 30 controls): Windows Light 86.7, Windows Dark 78.7. After: Windows Light 88.0, Windows Dark 86.7 (page regenerated with scripts/render_looks.py). Overlay `status.d/zzz...-r84x.json` (one z more than every other file; read and write it through `\\?\`).

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

## Regression

Sheets re-rendered one at a time with the committed `neper-self.exe` (compiler arena 4g): group_box, group_box_dialog, native_dark6, radio_group, radio_group_states, radio_group_dialog, choices_filter, radio_dialog, radio_states, radio_hover, native_dark2, progress_bar, check_list_box (4 sheets), button_edit, plus cup_, linux_ and material_ button_edit, check_list_box, group_box, radio_group, radio, splitter, progress (where the look has one) and splitter, radio: `git status` shows no Neper, Linux, Cupertino or Material picture changed. Not done: a full re-render of all 251 apps, and a 1.5x viewing of every Windows Dark sheet of the rows left.

## Limits

The briefs of the round (round70-flutter-compare.md, round63-fixes.md, round72.md) were not on disk; the rules were taken from the coordinator's message. Contrast numbers are WCAG ratios of the nominal ink colours (the rendered peak of thin 11 px glyphs reads lower). Rows raised on derivation rest on the maintainer's policy, not on a dark capture.
