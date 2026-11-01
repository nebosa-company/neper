# Flutter comparison, round 77 lane m (Android and macOS / iOS rows below `matched`)

Row census (status.json plus every status.d overlay at master `03f30359c`): 106 controls have at least one Cupertino or Android look row that is not `matched` or `ready`, 365 look rows in all. Only 11 of those controls have a Flutter ref in `ref/flutter/manifest.csv`; the other 95 (Cupertino activity_indicator, range_slider and date_range_picker aside, mostly platform idiom controls) have no Flutter widget, so no row of them was raised. Ranked by rows below `matched` among the 11: tab_bar 4 (Android and Cupertino, light and dark), list 4, then activity_indicator, date_range_picker, hint, range_slider, segmented_control, slider (dark only), time_picker, list_box, popup_menu 2 each (slider 1). Also looked at against the nearest Flutter widget: toast (SnackBar), large_title (large AppBar), search_field.

Comparer: own python (numpy, scipy), not committed: colour runs along rows and columns, exact-colour components with bounding boxes, corner-area radius, ink boxes. The palette difference of Android primary (6750a4 against Flutter 65558f, G4 of flutter-compare.md, accepted) and the black harness outline are not repeated below. Where Flutter differs from the M3 spec on purpose the spec value stays; for Cupertino the HIG number stays and only shapes are compared (its text is Roboto).

## Fixed in code (Android look only; Windows, Linux, Neper and Cupertino pictures byte-identical)

- Segmented button (`control.segmented_control`): was 38 high (the frame edge was drawn over the segments), now 40 outside the edge, pill radius 20, as Flutter's SegmentedButton and M3. New sheet `examples/looks/material_segmented.e` (`material/segmented_control.png`, cells 250 wide so the check and label fit). Also changes `material/font_picker`, which uses the button.
- Modal time picker, dial form (`overlay.time_dial`, `time_box`, `period_segment`, `time_picker_modal_with`): dial 256 with numbers on a 100 ring and a 48 handle (was 224, 88, 44), hour and minute selectors 96 x 80 (was 80 x 64), 24 wide colon, AM over PM one 52 x 80 frame of two 40 segments (was two 48 x 32 boxes with a gap). Dialog 328 x 512; Flutter 358 x 512. Changes `material/time_picker_dial` only.
- Range band of the calendar (`overlay.calendar`, ranged): `secondary-container` with `on-secondary-container` digits in the Android look (was `primary-container`). Flutter and M3 draw secondary-container: e8def8 (dark 4a4458), measured equal. Changes `material/calendar` and `material/date_range_picker_open`.

## Measured, rows raised to `matched`

- slider, Android dark: thumb 20, inactive track 4, disabled colours 646067 and 2d2b31 against 646068 and 2e2b31, hover halo 221f29 equal, focus and pressed halo 26222e against 26232e. Against Material Web the row had 20 states with 1 over the line (labeled pressed, 55 px of anti-aliasing along the drop and ring edges, no shape difference).
- range_slider, Android and dark: thumb 20 (Flutter 20), inactive track 4 (4), disabled thumb a9a3aa against a8a3aa.
- activity_indicator, Android and dark: the 48 cell of `progress.png` (the M3 size): arc 40 across, 4 stroke, round caps, no track; Flutter CircularProgressIndicator 40 across, 4 stroke. The sheet's 20, 36 and 64 cells are Neper sizes with stroke size / 12 (3 at 36).
- tab_bar (the Android rows reuse `tabs.png`, the sheet of page_control): primary indicator 3 high, secondary 2, divider 1 px, divider cac4d0 against cac4cf (dark 49454f against 49454e).
- segmented_control, Android and dark: height 40, pill edge, 1 px outline 79747e (Flutter 7a757f; dark 938f99 against 948f99), selected fill e8def8 exact (dark 4a4458 exact), hover ece5ed against ebe6ee (dark 252229 against 242228), disabled outline e3dde4 against e2dce4.
- time_picker (dial dialog), Android and dark: dialog height 512 (512), dial 256 (256), inactive minute fill e6e0e9 exact (dark 36343b against 36343a), period selector 52 x 80 (52 x 80), handle 48 (flat 46 after anti-aliasing, Flutter 47). Active hour fill eaddff against e9ddff (dark 4f378b against 4d3d75) is the palette.
- date_range_picker, Android and dark: band e8def8 and 4a4458 exact, day circle 40 (flat colour area 1079 px against 1241 for Flutter's 42).
- tab_bar, Cupertino and dark (shapes only, the bar cells of `page_control.png`): face f9f9f9 equal (dark 1d1d1d against 1b1b1b), hairline d2d2d3 against d3d3d3, 49 + hairline = 50 as Flutter's 50, 10 pt labels, accent 007aff.
- list_box, Cupertino and dark (shapes only, against CupertinoListSection; the manifest maps the wheel picker instead): card corner radius 10 (corner-area estimate 10.6 against 10.9), light card ffffff equal, rows 43 + a 1 px rule.

## Deviations, intended or unresolved (control, state, what differs, why)

- slider and range_slider, Android: active track 4 against Flutter's 6 (inactive 4 in both); M3 (Material Web) draws 4 and 4. State layer 40 against 48; M3 is 40. Spec kept. Range focus puts the halo on both handles, Flutter on the first only (the runtime does not say which handle holds the focus). Range disabled: active track a9a3aa (Flutter b5b0b7), dark 646067 (58545b): M3 draws 38 % on-surface, kept.
- slider, labeled cells: the value label is cut at the cell top in the Material Web ref and in ours alike (capture clip); Flutter has no counterpart.
- activity_indicator, Android: Flutter's frame is an indeterminate arc at one phase, ours is frozen at phase 0.25 (arc length differs). Cupertino has no Flutter ref and stays `review`.
- tab_bar, Android: a primary tab with icon and label is 64 high (M3, Material Web), Flutter 72 (kTextAndIconTabHeight). In the secondary tab the indicator stands on the divider row (ours 1 px higher) where Flutter overdraws it. Indicator width ours 40 against label ink 44 (Flutter equals the label), as Material Web. Tab width follows the sheet (100 against 120).
- tab_bar, Cupertino: icon box 25 (ink 17) against Flutter's 30 (ink 24 to 30), HIG says 25; inactive colour 8e8e93 against b7b7b7 (HIG systemGray); dark hairline 2f2f30 visible where Flutter's dark bar has none. The macOS strip cells have no Flutter counterpart and were not measured, so `page_control` stays `review` for Cupertino.
- segmented_control, Android: the cell focuses the middle segment (Flutter the first); both show a layer of the label colour at 8 to 10 %. Segment width follows the sheet cell (83 against 78).
- time_picker, Android: dialog 328 (M3 container) against Flutter's 358, so Flutter's selectors stretch to 111 where the spec says 96; gap selector row to dial 24 against 38 and dial to actions 24 against 11 (sum equal, dialog height equal); no keyboard toggle in the sheet (Flutter shows one); the typed input form is not on the sheet.
- date_range_picker, Android: a field with a popup month against Flutter's full-screen scrolling dialog; day cell 40 (M3) against 42 (Flutter's row height), band 40 against 42. Recorded as the desktop form.
- list_box, Cupertino: row pitch 44 (HIG) against Flutter's 45; the rule is a 0.5 pt hairline (e3e3e4 at 1x) against a 1 px c7c7c9; dark card 2c2c2e on a 1c1c1e page (elevated grouped) against 1c1c1e on black; Flutter's tiles carry a leading icon and trailing text, ours none.

## Still `review`, with the reason

- hint, Android: plain tooltip 24 high on inverse-surface 322f35 against Flutter's 32 high grey 707070 (M3: 24, inverse-surface); the rich tooltip's left edge column is half a pixel off Material Web (the round 33 gap, not touched); Flutter has no rich tooltip.
- list, Android and Cupertino: `list_rows.png` is the static text-row container (21 px rows); Flutter's ListTile is an item. The item form (`list.png`, a `list_box` row) was measured: tile 72 high, leading icon ink x 20 to 35 and y 28 to 43, label x 57, as Flutter; hover layer ece5ed (8 %) against Flutter's f3edf5 (4 %), focus e8e1e9 (10 %) against ded9e0, trailing padding 16 (M3) against 24, selected fill secondary-container against none. No item sheet exists for the container, so the rows stay.
- popup_menu, Cupertino: the macOS menu (r8, 22 rows) against Flutter's iOS context menu (r14, 43 rows, trailing icons); no macOS ref exists, not changed.
- toast, Android: severity card (surface container, 16 radius, info well) against the M3 snackbar (inverse-surface, 4 radius); a different component, no change.
- large_title and search_field, Android: the iOS-idiom large title and the shared search field have no Flutter counterpart (Flutter's large app bar is `top_app_bar`, matched).
