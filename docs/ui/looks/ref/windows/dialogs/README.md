# v3 dialog and window references

Captured 2026-10-15 from the real MTG Studio v3 (a copy of mtgstudio.exe with its own db3) by `scripts/grab_v3_dialogs.ps1`, with no physical input: menu items are opened by posting mouse messages to the dxBar windows, windows are saved with PrintWindow(flag 2), and closed with WM_CLOSE. Every PNG is 100 % pixels at its true window size (v3 is DPI unaware and the script is too, so no crop is needed on a 150 % desktop). Each captured window has a `<name>.controls.json` beside it: its class, title, size and every child window (class, text, visible, x/y/w/h relative to the window, dialog control id). Only windowed controls appear; DevExpress lightweight parts (grid cells, tab captions, tree nodes, menu items) are not separate windows, so crop those from the PNG. `main-window@1x.png` here is pixel-identical to `../main-window@1x.png`.

State: the app starts in Card Pool, Collection from Pool mode. Deck dialogs were captured after File > Mode > Deck from Card Pool (a deck was already loaded, "New Deck"), so ``main-window-end`` is in Deck mode. Options pages and dialogs show what they display on open; no value was typed or changed.

| File | How reached | Form class | Title | Size |
|---|---|---|---|---|
| main-window@1x.png | launch | TMainForm | MTG Studio - Card Pool [Assertions] [No Optimization] | 800x600 |
| menu-File@1x.png | click 'File' on the Main Menu bar | TdxBarSubMenuControl |  | 251x580 |
| menu-Cards@1x.png | click 'Cards' on the Main Menu bar | TdxBarSubMenuControl |  | 217x496 |
| menu-Search@1x.png | click 'Search' on the Main Menu bar | TdxBarSubMenuControl |  | 227x488 |
| menu-View@1x.png | click 'View' on the Main Menu bar | TdxBarSubMenuControl |  | 214x618 |
| menu-CardArt@1x.png | click 'Card Art' on the Main Menu bar | TdxBarSubMenuControl |  | 189x332 |
| menu-Online@1x.png | click 'Online' on the Main Menu bar | TdxBarSubMenuControl |  | 162x86 |
| menu-Reports@1x.png | click 'Reports' on the Main Menu bar | TdxBarSubMenuControl |  | 228x206 |
| menu-Tools@1x.png | click 'Tools' on the Main Menu bar | TdxBarSubMenuControl |  | 255x166 |
| menu-Admin@1x.png | click 'Admin' on the Main Menu bar | TdxBarSubMenuControl |  | 100x26 |
| menu-Help@1x.png | click 'Help' on the Main Menu bar | TdxBarSubMenuControl |  | 191x216 |
| search-filter-top@1x.png | Search menu, item at popup y=13 | TFilterForm | Filter Card Pool | 708x493 |
| search-filter-bottom@1x.png | Search menu, item at popup y=33 | TFilterForm | Filter Collection | 708x493 |
| search-advanced-filter@1x.png | Search menu, item at popup y=53 | TfmFilterControlDialog | Advanced Filter | 560x355 |
| search-search@1x.png | Search menu, item at popup y=221 | TSearchForm | Search for Card | 325x257 |
| view-sort@1x.png | View menu, item at popup y=75 | TSortColumnsForm | Sort [Card Pool] | 367x347 |
| view-legality-main@1x.png | View item y=263 : NO NEW WINDOW | TMainForm | (main window after the click) |  |
| view-card-rules-main@1x.png | View item y=283 : NO NEW WINDOW | TMainForm | (main window after the click) |  |
| view-show-columns@1x.png | View menu, item at popup y=303 | TcxGridBandedTableCustomizationForm | Customization | 180x300 |
| view-conditional-formatting@1x.png | View menu, item at popup y=483 | TfrmDataControllerConditionalFormattingRulesManagerDialog | Conditional Formatting Rules Manager | 700x421 |
| cardart-preview@1x.png | Card Art menu, item at popup y=33 | TPreviewForm | Preview | 1280x800 |
| reports-missing-set-cards@1x.png | Reports menu, item at popup y=103 | TMissingSetCardsForm | Missing Set Cards | 266x503 |
| reports-combos-from-collection@1x.png | Reports menu, item at popup y=123 | TfrxPreviewForm | Combos from Collection | 1296x768 |
| reports-edition-availability@1x.png | Reports menu, item at popup y=143 | TfrxPreviewForm | Edition Availability | 1296x768 |
| reports-card-quantities@1x.png | Reports menu, item at popup y=163 | TfrxPreviewForm | Card Quantities | 1296x768 |
| reports-scorepad@1x.png | Reports menu, item at popup y=193 | TfrxPreviewForm | Scorepad | 1296x768 |
| tools-locate-my-collection-main@1x.png | Tools item y=13 : NO NEW WINDOW | TMainForm | (main window after the click) |  |
| options-01-interface@1x.png | Tools menu, item at popup y=153 (page 1) | TOptionsForm | Options | 728x494 |
| options-02-decks@1x.png | Tools menu, item at popup y=153, then click page 2 in the left category list | TOptionsForm | Options | 728x494 |
| options-03-shortcuts@1x.png | Tools menu, item at popup y=153, then click page 3 in the left category list | TOptionsForm | Options | 728x494 |
| options-04-passwords@1x.png | Tools menu, item at popup y=153, then click page 4 in the left category list | TOptionsForm | Options | 728x494 |
| options-05-internet-authentication@1x.png | Tools menu, item at popup y=153, then click page 5 in the left category list | TOptionsForm | Options | 728x494 |
| options-06-rules@1x.png | Tools menu, item at popup y=153, then click page 6 in the left category list | TOptionsForm | Options | 728x494 |
| options-07-prices@1x.png | Tools menu, item at popup y=153, then click page 7 in the left category list | TOptionsForm | Options | 728x494 |
| options-08-grids@1x.png | Tools menu, item at popup y=153, then click page 8 in the left category list | TOptionsForm | Options | 728x494 |
| options-09-defaults@1x.png | Tools menu, item at popup y=153, then click page 9 in the left category list | TOptionsForm | Options | 728x494 |
| options-10-card-art@1x.png | Tools menu, item at popup y=153, then click page 10 in the left category list | TOptionsForm | Options | 728x494 |
| options-11-morph@1x.png | Tools menu, item at popup y=153, then click page 11 in the left category list | TOptionsForm | Options | 728x494 |
| help-game-rules@1x.png | Help menu, item at popup y=53 | TfrxPreviewForm | Comprehensive Rules | 1296x768 |
| help-version-history-main@1x.png | Help item y=73 : NO NEW WINDOW | TMainForm | (main window after the click) |  |
| help-report-missing-card-main@1x.png | Help item y=183 : NO NEW WINDOW | TMainForm | (main window after the click) |  |
| help-about@1x.png | Help menu, item at popup y=203 | TAboutForm | About MTG Studio | 452x372 |
| main-window-deck-mode@1x.png | File > Mode > Deck from Card Pool (y=317) | TMainForm | MTG Studio - Deck [Assertions] [No Optimization] | 800x600 |
| deck-properties@1x.png | File menu, item at popup y=213 | TDeckPropertiesForm | Deck Properties | 364x552 |
| deck-legality@1x.png | File menu, item at popup y=233 | TDeckLegalityForm | Deck Legality | 555x486 |
| deck-statistics@1x.png | File menu, item at popup y=253 | TStatisticsForm | Statistics | 957x509 |
| main-window-end@1x.png | after all dialogs closed | TMainForm | MTG Studio - Deck [Assertions] [No Optimization] | 800x600 |

## Reached but nothing opened
Those rows ending in `-main@1x.png` show the main window after the click: View > Legality and View > Card Rules (toggle docked panes, no window), Tools > Locate My Collection, Help > Version History and Help > Report Missing Card (no window of the process within 20 s; they hand off to Explorer, a browser or mail, or are inert here).

## Skipped on purpose (not opened)
- File > New/Open/Reopen/Save/Save As/Save All/Close/Close All/Delete Deck -- edit or delete data (and disabled in this mode)
- File > Print Proxies -- prints
- File > Import / Update Prices -- imports data / goes online
- File > Mode items, Full Screen, Minimize, Stay on Top -- change app state, not dialogs
- File > Exit -- exits
- Cards > Add/Remove/Quantity/Batch Update/Delete All/Cut/Copy/Paste -- edit data
- Cards > Print, Export, Copy as Text -- print/export (submenus)
- Cards > Lock Collection, Next/Previous Deck -- state change
- Search > Reset All Filters, General Filter toggles, Next/Previous/Cancel, Go to, Bookmarks -- state change / navigation, no dialog
- View > Sort Order/Group By/Show* toggles, Toolbars, Status Bar -- toggles change layout, no dialog
- Card Art > Export, Open Containing Folder, Copy to Clipboard, sizes, align, Download All Art -- export / explorer / clipboard / network / toggles
- Online > Gatherer, Boardgames Rules, eBay Sales, Google Images -- go online (disabled)
- Reports > Deck Registration Sheets, Deck Availability, Deck Combos -- deck-only (disabled in Collection from Pool mode)
- Tools > Check Collection Integrity, Backup Collection, Open Installation/Configuration/My Decks Folder -- maintenance / writes / launches Explorer
- Admin > Debug -- admin
- Help > MTG Studio Help, Discord, Homepage, Bug Report, Request a Feature -- launch external viewer/browser
- Help > Check for Update -- goes online
- Not captured: the Statistics tabs beyond Colors, Filter dialog tabs beyond the first, Toolbars > Customize, the View menu entries below the scroll arrow (Legend), nested sub-menus (Reopen, Print, Export, Copy as Text).

## What MSAA/UIA could not reach
dxBar controls (TdxBarControl, TdxBarSubMenuControl) expose only a stub IAccessible: child ids 1..n all answer with the parent bar, accDoDefaultAction on them does nothing, UIA shows bare panes. So items are clicked by posting WM_MOUSEMOVE/WM_LBUTTONDOWN/WM_LBUTTONUP at hand-measured client coordinates (menu titles at x = 25, 60, 105, 149, 197, 249, 299, 347, 390, 431, y = 13; item y read from the menu-*@1x.png images). Options pages are clicked in its TCategoryButtons at y = 23 + 36 * page index. If a menu changes, re-measure the y values in `$Targets`.

## Re-run
    pwsh -NoProfile -File scripts\grab_v3_dialogs.ps1 [-Exe D:\Temp\claude\v3run\mtgstudio.exe] [-Out <dir>]

Needs a copy of v3 with its own mtgstudio.db3 (never run the repo or installed copy; re-copy the db3 from version-3\bin if damaged). Takes about 3 minutes; it kills and relaunches the process if it hangs. Traps: a window rect read by a DPI-aware process is 1.5x on this desktop and PrintWindow then leaves a black margin, so keep the script DPI unaware; modal dialogs do not block because only messages are posted; the Reports and Game Rules windows are 1296x768 FastReport previews.
