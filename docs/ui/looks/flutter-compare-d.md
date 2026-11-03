# Flutter comparison, lane d (controls)

Neper and Material against the Flutter Material 3 refs, Cupertino against Flutter Cupertino (shapes only; its text is Roboto). The black outline on hovered buttons and on snackbar, menu and dropdown surfaces in the refs is a harness artifact and was ignored (none of the refs used here show it).

Fixed: Neper outlined fields (memo, mask edit, token edit, button edit, text edit, spin edit, date edit, password) did not darken their outline on hover because the runtime hovers regions, not editors; the Neper profile now uses the same hover region the Android field has (`control.e`). Hover outline is now on-surface (1a1b20 against Flutter 1a1c20).

Compared with no gap: Material field outline 1 px 79747e vs 7a757f, height 56, dark 938f99 vs 948f99; Material checkbox 18x18; Cupertino radio 14 px disc; Material group outline cac4d0 vs cac4cf.

Not compared, no Flutter widget: label, status bar, status button, splitter, scroll bar, tree list, vertical grid. Image combo box (ListTile) and the date edit calendar were not measured.

Deviations (control, state, what differs, why):

- Neper fields, all states: 48 px high against 56; desktop height of the Delphi edits.
- Neper fields, focus: 3 px ring against Flutter's 2 px; Neper focus-ring rule (3 px solid).
- Neper fields, palette: primary 145db2 against 425e91, outline 737784 against 74777f, error b42431 against ba1a1a; Neper's own tokens.
- Material fields, focus: 3 px, 6750a4 against 2 px, 65558f (seed-derived); baseline token and the 3 px rule.
- Cupertino fields: macOS hairline field with a blue ring against the iOS field (2 px e6e6e6, no ring); the look is AppKit.
- Cupertino check list box: 22 px circle against CupertinoCheckbox's 14 px square; the iOS list multi-select idiom.
- Neper and Material radio group: ring 20, dot 10 against Flutter's 18 and 8; the M3 spec is 20 and 10.
- Neper hint: 24 px inverse-surface 2f3035 against Flutter's 32 px grey 700 at 90%; Flutter's tooltip default is not the M3 token.
- Neper data grid: rows 28 px and a dense header against 48 and 56; divider c3c6d5 against c4c6d0; v3 grid parity.
- Neper group box: captioned row list with a 2 px soft d8dbe6 edge against Card outlined 1 px c4c6d0; no Flutter group box.
