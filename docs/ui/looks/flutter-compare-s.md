# Round 80 lane s: Android menu bar at standard density, Cupertino citations

Own scratch comparers (python, numpy, PIL, not committed): colour runs along columns and rows, tone extents, ink boxes against Segoe UI rendered by PIL.

## Android menu bar (raised to `matched`, light and dark)

Density chosen: standard (Android's `VisualDensity.defaultDensityForPlatform`), as Flutter's `MenuBar` uses on a phone. Source: `D:/flutter/packages/flutter/lib/src/material/menu_anchor.dart`: `_MenuButtonDefaultsM3` (minimum 64 x 48, `_scaledPadding` = max(8, 12 + density dx) = 12), `_MenuBarDefaultsM3` (4 px bar padding, 4 px corners), `_MenuDefaultsM3`, and `_SubmenuButtonState.build` (a top-level panel is offset by the menu padding horizontally only: no gap under the title).

Changed (all Android only, hooks in `navigation.e`, code in `looks_q79.e`):
- Title padding 8 to 12. Measured: File 64, Cards 64, Search 68, View 64 wide, text ink 12 px inside the box, titles at whole pixels.
- Panel flush under the title (was 2 px below) and no slide-in. The slide left the panel on a fraction of a pixel at capture, which blurred the separators over two rows and put the hovered row on 202.5. Now rows 48 (hovered row 201 to 248, e2dce6 light, 312e36 dark), separators one row each (cac4d0, dark 49454f), whole pixels at 1x.
- Sheet: the hover and pressed cells targeted a shifted bar that was clipped to 356 wide; they now hover and press the View title and the bar is 480 wide in all four cells (captions "Hover (View)", "Pressed (View)").
- Still exact: bar 48 high, f3edf7 (dark 211f26), hover 8 % and pressed or focus 10 % of on-surface (ded8e2, dark 35323a), panel 280 wide, disabled rows 38 %.

Recorded deviations: menu shade level 2 (M3 token) against Flutter's 3; the bar fills its container where Flutter's hugs its content; no Flutter MenuBar frame exists, so the numbers are the published source.

## Cupertino: what could be cited

The Apple Human Interface Guidelines pages were read as JSON from `developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json` on 2026-11-01 (the documentation JSON for UIKit and AppKit symbols gives no point values). Cited and read:

| Page | Number |
|---|---|
| Typography | iOS Body 17/22, Headline 17 semibold, Title 2 22, Large Title 34 bold, Footnote 13, Caption 1 12; macOS Body 13/16, Headline 13 bold |
| Buttons | hit region at least 44 x 44 pt |
| The menu bar | height 24 pt |
| Split views | thin divider one point wide |
| Color | iOS 26 system colours (blue 0088FF, red FF383C ...): this look keeps iOS 17 / macOS 14 values (blue 007AFF), so colours are never claimed |

Pages with no usable number: Tab bars (tvOS 68 only), Page controls, Segmented controls, Progress indicators, Scroll views, Lists and tables, Menus, Steppers, Toolbars, Text fields, Labels, Boxes, Layout. UITableView.rowHeight is `automaticDimension` in the docs.

From memory, unverified, not used to claim anything: UISwitch 51 x 31, UISegmentedControl 32, UITableViewCell 44, NSButton regular 22 and small 19, NSTextField 22, NSTableView row 24, UITabBar 49, UIToolbar 44, page sheet radius 10, NSStepper 19 x 27.

### Raised to `matched` (shapes only, both looks)

- label: every one of the 12 cells equals the cited type size. Ink boxes against Segoe UI at the cited size: heights within 1 px (17 pt 14 against 13, 22 pt 18 against 17, 34 pt 35 against 34, 13 pt 10 to 14 against 9 to 13), widths 0 to 4 px narrower (Library 110 against 114, Deck Properties 117 against 122). Recorded: Segoe UI for SF, semibold drawn bold, iOS 17 colours.

### Measured, fixed, still `review`

- vertical_grid: rows were 44 plus a 0.5 hairline drawn as a whole pixel, so 45 apart; now 44 apart (a section of six rows is 264). The cited minimum is the 44 pt hit region; the 44 row itself, the section radius 10 and the 16 pt insets are from memory.
- menu_bar: bar 24 high (rows 32 to 55) matches the cited 24 pt. The logo is drawn from discs and does not look like the glyph, the open chip colour and radius have no number, the hover and pressed cells draw a bar clipped narrower than the rest cell (sheet geometry, not measured further), no menu is shown open.
- splitter: the cited number is a 1 pt thin divider; the sheet draws a divider about 6 px wide with a grip and no thin cell.
- toolbar_button: the 44 pt hit region is not visible in a picture (the chip is 32).

### Left at `review`, no citable number

spin_edit, combo_box, image_combo_box, date_edit, progress_bar, group_box, page_control, status_bar, popup_menu, hint, scroll_bar, tree_list, data_grid. Each carries a note saying so. Not changed.

## Regression

Re-rendered with the new code, byte-identical to the committed PNGs apart from the rows above: see the commit message for the list of sheets.
