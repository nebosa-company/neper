# Windows Dark group box, round 81 lane t

Windows Dark 80.0 to 81.3 (group_box review to matched; Windows Light 86.7 unchanged). Overlay `status.d/zz...-r81t.json` (225 z; the path is over 259 characters, read and write it through a `subst` of `status.d`).

## What was wrong (audit 40 (1))

The look's own group box drew a #707070 frame that no capture has (the dark captures `groupbox-rest` and `groupbox-disabled` are #DCDCDC), a Tahoma 11 caption, and at 1x two half-pixel rows of #484848 on the horizontal edges. The disabled caption #9D9D9D had no capture behind it: the disabled capture is the rest capture, pixel for pixel.

## Fix

- `control.windows_group_box`, Dark only (hooks to `lib/e/ui/looks_t81.e`, Light and every other look unchanged): frame #DCDCDC, caption Segoe UI 12 (the capture's face and size), the gap in the top edge starting 7 in, the caption 9 in, the gap a whole number of pixels wide (a fractional gap left one part-covered pixel at its end), one caption ink in every state (white; disabled equals rest as in the capture).
- `group_box.e`: Dark cells are pinned at whole logical pixels. The cause of the half-pixel rows was the harness centring an odd-height (61 px) box in the cell; a real placement on whole pixels draws one row.
- `native_dark6.e`: the disabled caption is white like the rest one (it was #9D9D9D).

## Measured (own comparer, scratch, not committed)

- A scratch cell of the look's own `group_box_of` at the capture's size (176 wide, "Group", one child row) against `groupbox-rest` and `groupbox-disabled` @1x, top band 200 x 30: frame pixels xor 0, gap 7 to 43 as the capture, caption ink mask 180 px both, xor 0 (both captures identical).
- `native_dark6.png`, both cells, against the whole captures: frame 0, caption window 0, body 0 px off.
- `group_box.png` @1x, Rest, Disabled, Empty: frame 140 wide, 1 px #DCDCDC, no grey residue on either side of any edge, stub 7 (capture 7), caption ink x 9 to 58 and y -4 to +7 from the frame corner (capture x 9, y -4 to +7). Viewed at 4x beside the capture.
- 1.5x does not match: capture 1 device px lines and a 7 px stub; ours 2 px lines on top, bottom and right (left 1) and a 10 px stub. The row's status follows the 1x captures, as every Windows Dark row's rule does.

## Rows left below matched, and why

- Section header cell of group_box.png: dark TGradient #4A4A4A to #2B2B2B, white title: in no dark capture, derived.
- Long caption cell: a caption longer than the frame overruns it and removes the top edge; no capture of that case.
- `group_box_dialog.png` (Windows Dark) still draws its frame #333333 through `windows_group_exact` (1.29 : 1): untouched, no capture backs it.
- radio_group Dark frame #707070 contradicts the only dark group capture (#DCDCDC) and sits on half pixels at 1x: untouched.

## Re-audit: Windows Dark rows whose Dark colours are not backed by a dark capture

Notes added to each row (status unchanged, nothing raised on a colour choice).

- Not backed at all: splitter (matched on the maintainer's 2026-10-17 acceptance alone; recommend an auditor decides whether it stays matched), radio_group, check_list_box, progress_bar, page_control, status_bar, toolbar_button, menu_bar, tree_list, vertical_grid.
- Part backed: date_edit (calendar popup), button_edit (ellipsis button), token_edit (chips), data_grid (body and rows), dialog (body), button (toggle, loading, plain kinds), radio (white enabled caption), popup_menu (parent hover, picture column), list_box (column without a bar).

Regression: 17 sheets of other looks and Windows re-rendered (card, avatar, banner, divider, linux_button, linux_checkbox, linux_dialog, cup_scroll, cup_alert, cup_menu_bar, status_bar, progress_bar, tree_list, material_menu_bar, text_edit, radio, group_box_dialog), `git status` shows no other PNG changed.
