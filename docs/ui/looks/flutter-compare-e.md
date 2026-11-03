# Flutter comparison, lane e (the 15 rows audit 33 downgraded)

References: `ref/flutter/material` (seed #6750A4) for the Android pair, `ref/flutter/cupertino` for the macOS / iOS pair (shapes only, its text is Roboto). Comparer: own python (numpy, scipy), not committed: flat-colour components, hole-filled corner radius, corner coverage area for radius, colour runs down a column, ink bands. Palette difference of Android primary (G4 of flutter-compare.md, accepted) applies to every Android row and is not repeated. The black outline on the popup menu ref is the harness artifact and was ignored.

## Fixed

- Android popup menu: rows are 48 dp (M3 menu item, Flutter PopupMenuItem), were 56 (md-menu). Measured after: label pitch 48 (ref 48), panel padding 8 top and bottom (ref 8), radius 4 (ref 4), fill f3edf7 against f2ecf4 (palette), dark 211f26 against 211f24. Changes `material/menu*` and the dark pair only; the earlier md-menu pixel match (56 rows) no longer holds by decision.
- Cupertino navigation bar: transparent with no hairline at rest, the bar face and the 0.5 pt hairline only once scrolled (iOS 15 scroll edge appearance; Flutter's automaticBackgroundVisibility). Ref has no edge at rest; ours now has none. Title ink centre 0.5 px from the bar centre (ref 22 of 44), trailing action 20 px from the right edge (ref glyph 21). Changes `cupertino*/large_title` and `toolbar_button` (nav cells).
- Cupertino radio unselected (radio, radio_group): 14 px disc, white with a 3.5 % dark rim in light, flat 383838 and no rim in dark (ref: f7f7f8 rim on white, 383838 disc). Selected unchanged: 14 px disc, 4 px ring, 6 px dot, as the ref.
- Cupertino action sheet: cards now radius 14 (was 10; ref reads 13.5 to 14, ours 14.4 to 14.7 by corner area); dark actions card 1f1f1f and Cancel card 2c2c2c (were 3a3a3c and 48484a), both equal to the ref. Light unchanged apart from the radius.
- `scripts/cupertino_spec_check.py`: the navigation bar height check read the face fill, which is now absent at rest; removed.

## Deviations, intended or unresolved (control, state, what differs, why)

- top_app_bar, Android: small bar 64 dp against Flutter's 56 (ref hamburger ink rows 22 to 33, ours 26 to 37 in a 64 bar; icon is centred in both). 64 is the M3 spec small top app bar container and the gallery reference. Leading icon x 19 to 37 against 19 to 38; title starts at x 56 against 72 (Flutter leading width 56 plus 16 title spacing); last action centre 332 against 340. Kept.
- popup_menu, Android: 168 wide with icons and a shortcut column against Flutter's 112 wide text-only menu (content, not shape); has an elevation shadow where the ref shows none outside the harness outline; rows with a supporting line stay 72.
- alert_dialog and bottom_sheet, Android: scrim 32 % black (M3 `md.sys.color.scrim` modal opacity; page fef7ff gives ada8ad) against Flutter's 54 % (747175; dark 0e0c10 against 09080b). Kept the spec value. Alert sheet is 380 wide with three actions against 298 (recorded in round 70).
- navigation_bar, Cupertino: back chevron ink starts 19 px from the bar edge (HIG 16 pt margin) against 30 in the ref; no Apple reference exists to decide, kept.
- large_title, Cupertino: the ref (CupertinoNavigationBar outside a sliver scroll view) draws only the inline row, so the 34 pt bold large title has no counterpart; only the bar row, transparency and hairline were compared. Large title cells keep the HIG numbers.
- radio, Cupertino dark selected: ours 0a84ff (iOS system blue) against the ref's 3264d7; kept the HIG colour. Dark unselected disc is flat where the ref has a faint top-to-bottom gradient (202020 to 383838). The light unselected radio is nearly invisible on white in Flutter and is a white disc with a faint rim on the f2f2f7 sheet here.
- action_sheet, Cupertino: cancel and rows 56 against 57; light and dark card fill is opaque where UIKit is translucent (e9e9eb against f2f2f2 light, recorded in round 70).
