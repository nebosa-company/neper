# v3 reference captures at true 1:1

Same screens, same names and same capture scripts as `../windows/` (`main-window@1x.png`, `dialogs/`, `states/` with the hover captures), but the client area is the real 100 % pixels of v3 instead of a resample. `../windows/` is untouched and stays the committed reference until someone decides otherwise.

## Diagnosis

- The desktop is scaled to 150 %: registry `LogPixels` is 144 (`AppliedDPI` 144), the panel is 1920 x 1200. A DPI aware process sees 144; PowerShell and the capture scripts are unaware and see 96.
- v3 is DPI unaware: its manifest has no `dpiAware` element (the exe is a Delphi 12 build; the manifest only asks for Common Controls 6 and `asInvoker`). Windows therefore lets it draw at 96 dpi and DWM stretches the finished surface by 1.5.
- `GetWindowRect` of the main window is 800 x 600 and the old PNGs are 800 x 600, so the dimensions never showed a problem. The scripts call `PrintWindow(h, dc, 2)` (PW_RENDERFULLCONTENT), which returns the composed (stretched) surface, and because the caller is unaware it is minified back to 800 x 600. Every pixel of the old captures went through a 1.5x bilinear stretch and a 1/1.5 minification, with a phase that depends on the position. The title bar (drawn by DWM at 150 %) is blurred the same way; the Segoe UI caption in the old PNGs is as soft as the grid text.
- Evidence, main window, the word `Name` in the grid header, luma rows: flag 0 gives stems of 133 (solid) next to 198/139/190 ClearType edges; flag 2 of the same window gives 161, 179, 196, 152, 178 and so on, smeared over a third column. ClearType fringes are stronger in the new grab (largest channel spread inside the grid text 105 against 55), the focus rectangle is dotted in the new one and a solid grey line in the old one.

## Method (no system setting is touched, nothing to undo)

`PrintWindow(h, dc, 0)` sends `WM_PRINT` and the controls paint themselves at 96 dpi into the bitmap, which is exactly v3's own rendering. It draws the classic caption frame, so `scripts/v3_grab11.ps1` (`Grab11`) takes the flag 2 grab for the frame and replaces only the client rectangle by the flag 0 grab (a client that comes back flat is left as flag 2). Window and client geometry are identical to the old captures (an old crop of the new main window is found at the same offset). Title bar and borders are therefore still the old, soft DWM rendering; everything inside the client is 1:1.

Not used, and why: `__COMPAT_LAYER=HighDpiAware` or an AppCompatFlags value would make the copy DPI aware, and a VCL form then lays itself out at 144 dpi, which changes the geometry the whole reference set is measured in. Nothing was written to the registry and the process environment was not altered for v3.

Scripts: `scripts/grab_v3_dialogs.ps1` (dialogs, menus, `main-window`), `scripts/grab_v3_states.ps1` and `scripts/grab_v3_hover.ps1` (states and hover, through `v3_states_lib.ps1`) now call `Grab11`, write here by default, wait up to two minutes for the main window, and reset the copy to Collection from Card Pool mode (the mode is persisted; Deck mode makes the next launch and the grid screens differ). `main-window@1x.png` in this folder is a copy of `dialogs/main-window@1x.png`. The hook DLL was not rebuilt.

## What differs from `../windows/`

- The copy's collection: the maintainer's `mtgstudio.collection` is now schema 3238 and v3 3.235 refuses it ("Previous MTG Studio schema version ... found") and exits. `Prepare-Data` in `v3_states_lib.ps1` therefore uses `$env:V3_COLLECTION` when set; this run used the 8 collection rows copied into a fresh schema 366 file. `reports-*` and `deck-*` dialogs need it; the deck dialogs (`deck-legality`, `deck-statistics`, `deck-properties` as dialogs) were not reached this time, so only their `-main` fallbacks and the `states/dialog-deck-properties-rest` grabs exist.
- The copy's desk layout drifted since the old capture (the old main window was grouped by Rarity with an `ES` and a `Legal` column), so the old `data_grid_main` screen cannot be reproduced; the main window now shows the plain pool grid. The collection grid below it is the same.
- Not reached again: the cascading sub menus (`menu-submenu-open-cards-print-*`, `-view-show-grid-lines-*`, `-view-toolbars-*`) and two menu rows (`menu-item-selected-reports-4`, `-view-1`). Several old `hover-*` captures exist only in the old set (264 hover PNGs here against 332).
- Selected row: the pool grid is at row 1 here, row 4 (Swiftfoot Boots) in the old `data_grid_top` crops.

## Our renders against old and new (`scripts/looks_1to1_compare.py`)

The piece of our sheet is placed by correlation in the captures of each set, refined within 2 px; counted = pixels more than 2 levels off in any channel, glyphs included; sharp = mean absolute horizontal luma step of the capture piece (higher is crisper).

| crop (area px) | old counted / sharp | new counted / sharp |
|---|---|---|
| data_grid_main.collection (115,200) | 22,722 / 5.55 | 35,765 / 7.82 |
| data_grid_top left (151,630) | 31,389 / 6.25 | 41,654 / 8.72 |
| data_grid_hover left (151,630) | 31,481 / 6.26 | 41,143 / 8.72 |
| data_grid_group2 left (151,630) | 25,658 / 6.17 | 36,197 / 7.96 |
| data_grid_bottom left (168,740) | 47,682 / 5.91 | 61,231 / 7.88 |
| data_grid_top right | 46,468 | 48,584 |
| data_grid_hover right | 47,474 | 49,647 |
| data_grid_group2 right | 38,543 | 42,825 |
| check_list_box_dialog top 400 rows (209,600) | 22,669 / 6.11 | 24,885 / 8.58 |
| vertical_grid (140,250) | 16,053 / 9.13 | 24,756 / 10.80 |
| tree_list_expanded (233,772) | 123,871 / 8.52 | 129,060 / 9.08 |

Reading: the new captures are crisp (about 35 to 40 % more edge energy), and our renders, which were fitted to the resampled references, are 10 to 50 % farther from them in counted pixels. Re-targeting the text and the row marks at the crisp captures is what is left to do; the references are the easier thing to match now (integer stems, hinted Tahoma 8).
