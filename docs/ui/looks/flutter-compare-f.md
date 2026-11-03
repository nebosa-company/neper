# Flutter comparison, lane f (round 72: the rows audit 33 found unmeasured, and lane a's partial inputs)

References: `ref/flutter/neper` (M3, seed #1b3a6b), `ref/flutter/material` (M3 baseline #6750A4), `ref/flutter/cupertino` (shapes only; text is Roboto). Own comparer: python (numpy, scipy), not committed. It lists every flat exact-colour component (4-connected, at least 60 px) of the sheet PNG and of the ref at 1x with bounding box, area and corner run, and reads edge-colour profiles across the field borders. Light was measured cell by cell; dark by its role colours (listed where they differ). Glyph and text pixels are not compared. The black hover outline of the refs is a harness artifact and was ignored.

## Fixed

- Cupertino slider (and the colour picker's sliders): track 2 px with the lit part 2 px (was 4 px), as Flutter's CupertinoSlider draws it (ref track 96 x 2 at 1x). Thumb 26 against Flutter 26 to 27, accent 007aff and dark 0a84ff equal to the ref.
- Android checkbox focus halo: already on-surface in the source (the lane a note was stale): unchecked focus halo e8e1e9 against ref e6e1e8, hover ece5ed against ebe6ee, pressed efe6f6 against eee6f4; dark focus 29272d equal, hover 252229 against 242228. Halo 40 x 40, box 18 x 18, as the ref.

## Cupertino field family (against CupertinoTextField, ref 250 x 36: a 2 px e6e6e6 border, dark 191919, radius 5, fill ffffff, dark 000000, no ring)

Each was read separately from its own sheet.

- memo: 197 x 97 box, 2 px soft edge (ededf1, ededee), fill ffffff, dark 2c2c2e on ground 1c1c1e; ref dark fill is black on black. Focus 3 px ring 6db0fb (dark 12559a), none in the ref.
- mask_edit: field 168 x 32 inside a 1 px dcdcdd edge (34 high), fill ffffff, radius 7 inside, dark edge 464649 and fill 2c2c2e. Ring and the clear glyph have no ref.
- token_edit: field 298 x 32 in a 1 px dcdcdd edge; chips 24 high, d6eaff r12 (b3d7ff selected, dark 22466d and 1d538a). A chip has no Flutter Cupertino equivalent.
- button_edit: field 168 x 32 in a 1 px dcdcdd edge, trailing 28 x 27 button f0f0f1 (hover e5e5e7, dark 3c3c40 and 48484d), radius 2. No ref for the button.
- text_edit: 188 x 32 inside a 1 px dcdcdd edge, radius 7.

Deviations (same reason for all five, the AppKit field): 34 high against 36, 1 px edge against 2, outer radius about 8 against 5, ring 3 px against none, dark fill 2c2c2e against black.

## Cupertino input controls

- checkbox: unchecked inner 11 x 12 (ref 12 x 12), checked 13 x 14 r3 007aff (ref 14 x 14 r4, 007aff); dark checked 0a84ff against Flutter 3264d7. Flutter's dark checkbox colour is not the iOS system blue; kept at the system blue. Focus ring surrounds the label as well as the box (lane a; kept, macOS ring).
- radio: 11 x 10 inner (ref 12 x 12), selected disc 007aff.
- switch: knob 26 (ref 26), track off dedee4 (ref eaeaeb), dark off 39393d (ref 262629), on 34c759 / 30d158 equal.
- slider: see Fixed; track dedee4 against e4e4e6, dark 39393d against 2b2b2e. Focus ring macOS, none in the ref.
- segmented_control: container 181 x 32 e3e3e9 against ref sliding 165 x 32 efeff0 (width is the labels); thumb 69 x 28 r7 against 57 x 28 r6.
- search_field: 220 x 36, r10, e3e3e9 against 300 x 36, r9, efeff0 (ref is a translucent tertiary fill over white; ours is flattened on the f2f2f7 ground).
- button: filled 94 x 34 r9 against Flutter large 86 x 52 r11. Not the same size class (macOS medium against Flutter's large; the Cupertino large is 50, not measured here again), so it stays review.
- no Flutter Cupertino widget exists for: icon button, range slider, combo box, autocomplete, stepper, image combo box, date edit, calendar. Not compared, rows unchanged.

## Android rows (against the material refs)

- divider: 1 px cac4d0 against ref cac4cf; the ref's e3dde7 on two rows is the same 1 px line centred between pixels. Dark 2f2c33 pair likewise.
- banner: 400 x 64 r11 card f7f2fa against Flutter's full-width bar 420 x 103 with a cac4cf rule and no radius (f8f2fa). M3 has no banner; recorded. Dark container 1d1b20 equal.
- table: header 300 x 55 f3edf7 and 1 px cac4d0 rules against 48 px rows, a 66 px header and a checkbox column, rule cac4cf. Recorded (dense v3 grid parity). Dark header 211f26.
- accordion: sections 280 wide, radius 12, f7f2fa, headers 52 against Flutter's flat 320 x 72 expanded tile ded9e0. Recorded.
- wizard: step circles 22 x 22 6750a4 against Flutter's 24 px 65558f; buttons 37 tall r18. Recorded (palette G4, shape).
- date_picker: dialog 360 wide r28 ece6f0 against ece6ee, header 120 against 119, selected circle 38 against 38; scrim 32 % against 54 % (M3 spec 32 %; deviation kept). Dark dialog 2b2930 against 2b292f.

## Neper

- date_edit: field 48 against 56 (recorded earlier); the calendar popup is a 200 wide r12 e6e8ef surface with 30 px day circles (r8 squares, accent 145db2), against the 360 wide r28 M3 dialog with 38 px circles. Desktop dropdown calendar against modal; recorded, row stays ready. Dark popup 292a2f.
- image_combo_box: field 140 x 48 r4, list 136 wide r4 edeff5 with 46 px rows against the DropdownMenu ref 136 wide, 48 px rows, ededf4. The 2 px row difference is the desktop list density; recorded, row stays ready.
- button 32 against 40, icon button 32 against 40 (G2); checkbox box 18 (ref 18), halo clipped to the cell height; radio ring 20 against 18 (M3 spec); text field 48 against 56, combo box and autocomplete 46 inner plus a 1 px edge against 54; search field 200 x 52 r20 against SearchBar 378 x 56 r28; range slider vertical bar handles against round thumbs; toggle button 56 x 30 r15 (no Flutter equivalent). All recorded, no status change.
- No Neper sheet exists for switch, slider, chips, segmented button or fab; nothing to compare.
