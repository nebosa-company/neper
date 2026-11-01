# Windows completion, round 78 lane o

Before (status.json + status.d, weights of scripts/render_looks.py, 30 controls): Windows Light 85.3, Windows Dark 77.3. After: Light 86.7, Dark 81.3
(overlay `status.d/zzz...z-r78o.json`, one z more than every other file; the file name is short only because the path must stay under 260 characters).

## Raised (all to `review`, none to matched)

| Row | Look | Change | Measured |
|---|---|---|---|
| token_edit | dark | Frame is the native dark edit frame (1 px #9B9B9B, focused #FFFFFF, 1 px #383838 ring, #202020 face, square) instead of the light underline; `looks_o78.dark_edit_frame`, one hook in `control.windows_token_field` | outer, ring and face runs equal `edit-rest` and `edit-focus` of ref/windows-native/dark; chips stay derived |
| radio_group | dark | Group frame #333333 (1.29 : 1) to #707070 (3.3 : 1), `looks_o78.dark_group_line`, one hook in `control.windows_group` | contrast computed; no capture of a dark group frame |
| date_edit | dark | none (status only): head compared | 0 px off over 4 left columns, 24 right columns, 4 top and 4 bottom rows against `combo-edit-rest` and `-hover`; Focus 32 px, all in face row 3 (glyph tops) |
| date_edit | light | none (status only): head compared | Focus cell against `ref/windows/combo_box_edit.png`: left 5, right 22 columns 81 (drop button, other width), top 0, bottom 0 |

The light date edit is capped at review: no v3 capture of a date edit exists and the native datepicker and monthcal captures are a different control (160 x 26 square #8D8D8D frame).

## Rows still below their ceiling, and why they stay

Light: text_edit, memo (no TcxTextEdit or TcxMemo in any v3 capture; the native light edit frame is 8 to 15 levels off v3's), progress_bar (v3's own bar was never captured; native is 16 px, ours 21), combo_box, page_control, tree_list, vertical_grid, data_grid, dialog (measured against 1:1 captures, glyph and ClearType residue remains, see their notes). Capped by missing v3 references or by unmatched text, not by drawing gaps found now.

Dark: button_edit, check_list_box, progress_bar, page_control, status_bar, toolbar_button, menu_bar, tree_list, vertical_grid, data_grid, dialog. The native control stays light under dark mode (or has no native twin) and v3 has no dark mode, so each is a derivation from the matched light drawing through the dark colour map: review is the ceiling. Nothing here may be raised without a real dark capture.

## Light and Dark difference

Dark is lower because 11 dark rows have only a derived reference where Light has a v3 capture, and 3 dark rows were `started` (token_edit, radio_group, date_edit). The two Light review rows with no v3 capture (text_edit, memo) are matched in Dark against the native dark captures, which is why Dark text_edit and memo are ahead.

## Recorded oddities (not changed)

- Dark radio captions are black on #202020 (about 1.1 : 1): the native dark radio capture has no light ink, and the matched dark radio row copies it; radio_group inherits it. The group caption beside it is white.
- Dark toolbar_button's top bar draws the gallery's line icons, Light the v3 atlas (known, derived).
- Native dark `groupbox` stays a #DCDCDC frame with a black caption (group_box dark is matched against that).

## Sheets

Every Windows sheet has a Windows Dark twin (only `edits_dialog-diff`, a difference picture, has none). 30 dark control sheets viewed beside their light twins at 1x; no missing or empty sheet. Re-rendered with the new hooks: token_edit, radio_group, radio_group_dialog, token_edit_dialog (only token_edit and radio_group dark changed).
