# Round 76, lane j: the nine Neper rows audit 35 downgraded, and the stale-sheet sweep

Branch looks76-j from master 51c3eb3e0. Compared with `ref/flutter/neper` (textfield-outlined, dropdownmenu, searchbar) by an own scratch comparer (not committed).

## Root cause (text_edit, mask_edit, button_edit, combo_box)

`control.field` (the Neper and Android builder) put the value in a flex stack that did not clip; the Windows, Cupertino and Linux builders set `overflow = .Clip` on that stack. So a value wider than the content box ran over the outline and over the end button. The sheets pass long strings on purpose. Fix once, in the shared builder, for the Neper profile only (`grow.overflow = .Clip`); Windows, Linux, Cupertino and Material PNGs are byte-identical (the sweep below re-rendered every Neper-drawing app, which also redraws those looks for the apps that run all ten: no non-Neper PNG changed except three sets that are stale on master, see below).

Measured: long text field 140 x 48, ink stops 17 px (text_edit), 16 (mask_edit) and 15 (button_edit, the '...' glyph) from the right outline; Flutter's content padding is 16. Outline 1 px 737784 against the ref 747780, corner arc equal sample by sample, left padding 16 equal. Disabled outlined field: Flutter has no fill and a 12 percent outline; Neper drew a 4 percent fill (its label notch showed as a light patch) and a 38 percent outline; now no fill and 221,222,228 against ref 222,222,228.

## Other defects found and fixed (all sheet geometry or list or bar code)

- date_edit: the 210 px sheet column squeezed the 256 px field to 200 and left the calendar glyph outside, drawn 2 px wide. Column is 280 for Neper; hot and pressed cells aim the pointer at the icon button.
- search_field: the bar was 40 empty and 52 filled (line padding on top of the 32 px Clear button); now 40 in every cell. Flutter SearchBar is 56 with icons (recorded deviation, docs/ux 40 px bar).
- autocomplete and combo_box open lists: rows now fill the list width, and the list is field wide and starts 4 px under the field's bottom edge (the anchor is the editor, 12 px inside it, so the list covered the lower outline). Flutter's DropdownMenu list is field wide and flush under the field (the ref's black outline is the harness artifact and is ignored).
- combo_box: drop button cells were Windows' 24 px field; the Focus tap missed the editor; open-list sheet had no room under the field (combo_box_lists gets 290 px, row hover aimed at the second row).
- token_edit: Wrapped cell now 320 wide with five tokens; hover, hover close and focused cells aim at the chip, its cross and the input line.
- hint: the rich tooltip hangs from the anchor's right edge and was clamped to the sheet edge; the anchor is now 180 in and 60 lower.

## Still review

- hint: Wrapped cell shows two lines of a three line text (plain tooltip max_lines 2, no ellipsis). Not part of the audit finding, needs a decision.

## Stale sweep (part 2)

All 146 Neper-drawing sheet apps (every app of examples/looks that is not cup_, linux_ or material_ prefixed and calls run_all, run_every, run_ten or the g runner), each with every argument of scripts/looks_scale_sheets.json, rendered one at a time: no app failed to compile or run. 128 Neper and Neper dark PNGs changed against the first commit of this branch (the only one-row notch change is key_value_editor). Reasons, by group:
- the nine rows' sheets (above);
- the field clip and the disabled fill and outline: memo, password_field, spin_edit, edits_states, edits_hover, edits_dialog, combo_hover, combo_box_{dialog,edit,flat_card,flat_card_hover,flat_hover,focus,held,pick,search_held}, native_dark, native_dark_icb, native_dark_mask. Known cost: edits_dialog, edits_states, edits_hover, combo_hover and the combo_box_* sheets above stand Neper fields in Windows sized boxes (30 px stacks, 21 to 23 px field heights) that squeeze the frame below its content, so the clip now hides the value that used to hang below the outline. Both renders are wrong; the sheets need Neper geometry (not done, not rows);
- list rows filling the list: combo_box_open_*, native_dark_open0 to 3 (field wide list now covers the Windows sized field in these Windows capture sheets; same remark);
- toolbar_button_hot (size 1338 x 518 to 1358 x 788, 1.5x too): stale since round 5, the sheet grew in lane 62689b75f and was never re-rendered with the hot argument.
Non-Neper PNGs that changed in the sweep and were reverted because they also change without this branch's library change (stale on master): material and material dark key_value_editor, cupertino and cupertino dark navigation_stack and navigation_split.
