# Flutter comparison, navigation and overlay controls (round 70, lane c)

References: `ref/flutter/<neper|material|cupertino>/<light|dark>`. Neper look = Flutter M3 seed #1b3a6b, Material = seed #6750A4, Cupertino = Flutter Cupertino (Roboto stands in for SF, so text is excluded; shapes, sizes, fills only). Method: a scratch python comparer (not committed) lists every flat fill (exact colour, 4-connected, at least 60 px) of the Neper sheet and the Flutter ref with bounding box and corner radius, matches fills within 2 levels, then ink extents on single rows for widths. Light and dark gave the same results unless a line says otherwise.

Controls with no Flutter reference (not compared, rows untouched): sidebar, bottom_app_bar, breadcrumbs, menu_bar, popover, flyout, side_sheet, title_bar, document_tabs, toolbar (command bar), Windows and GNOME looks.

## Harness artifacts ignored

The black outline of the headless run (not M3) is in these refs, in both families: menu-popup-open, menu-anchor-open, dropdownmenu-open (surface), searchbar-focus and searchbar-disabled (a black 390 by 68 box around the bar), navigationrail-focus and navigationrail-pressed (around the FAB), the hovered bar tooltip in navigationbar-hover. Flutter hover, focus and pressed frames are also caught while the state layer is still fading in (rail hover on an unselected pill is 3 % of onSurface, spec is 8 %), so state layer colours are compared against Neper's spec values 8/10/10 only by direction.

## Deviations kept (control, state, what differs, why)

- all Neper rows, rest: secondary container is d6e3ff, Flutter fromSeed gives dae2f9 (6 levels on B). Neper tokens are its own palette, not generated from the seed; a token change would move every Neper sheet.
- all Material rows, rest: surfaceContainer f3edf7 (published M3 baseline), Flutter fromSeed f2ecf4 (3 levels on B). Same reason, token level.
- navigation_rail, Neper and Material, all: no icon slot, the label sits in the 56 by 32 pill; Flutter stacks icon over label and has a FAB. The library rail takes labels only.
- navigation_rail, focus: Neper draws the 3 px solid ring 2 px outside (design system); Flutter shows only the state layer.
- navigation_drawer, rest: drawer 256 wide (sheet choice), ref 300; no header text or icons. Indicator height 56, inset 12, end corners 16 match.
- alert_dialog, Neper and Material: sheet card 380 wide against 298, and the three-action example uses filled action pills; radius 28 and fills match.
- popup_menu, Neper: the v3 command menu, r8 with a stepped 4 px shadow, 48 px rows with shortcut column; M3 menu is r4 with a soft shadow (not measurable, the ref draws the black artifact there).
- popup_menu, Cupertino: macOS menu (r8, small rows); Flutter shows the iOS context menu (r14, 250 wide, trailing icons). Kept, not matched; row stays review.
- search_field, Neper: 200 by 52 with a text Clear button; M3 SearchBar is 56 high with icons. Not the same control, kept.
- toolbar and large_title, Neper: desktop command toolbar and header, not an M3 AppBar.
- Cupertino alert_dialog and action_sheet: Flutter fills are translucent over the barrier (f1f1f1 and f2f2f2 over its grey); ours are opaque tokens (f4f4f6, e9e9eb). Sheet ground is f2f2f7 (dark 1c1c1e) against Flutter white (black), which also explains the search field fill e3e3e9 against efeff0 (same 12 % tertiary rule).

## Fixed

- action_sheet, Cupertino and Cupertino dark: was the generic bottom sheet with handle and left-aligned rows; now the library's grouped iOS cards (`overlay.action_sheet_ios`: inset 8, r14, 56 px rows, centred blue actions, separate Cancel card). The Cancel card is now the lighter one as in Flutter (white, 2c2c2c). `surf_overlay.e` picks the iOS form for the Cupertino profile; all other looks re-render byte-identical.
