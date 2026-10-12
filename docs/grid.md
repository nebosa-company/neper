# Neper data grid — requirements from MTG Studio v3 and the DevExpress `TcxGrid`

Status: **research + design proposal**. Nothing here is implemented, enqueued or decided; no `D<n>` row was
added. Section 9 proposes queue items for the owner to accept.

Purpose: MTG Studio v3 (Delphi) is to migrate to Neper. Its UI is built on the DevExpress VCL Quantum Grid
(`TcxGrid`). This document records (a) exactly which grid features MTG Studio uses, (b) how DevExpress makes
~120k–150k rows fast, so the data-model classes can be matched or beaten, and (c) what a Neper grid needs.

Sources read (all paths local):

| What | Where |
|---|---|
| DevExpress VCL 23.2.6 grid | `D:\tools\DevExpress VCL 23.2.6\VCL\ExpressQuantumGrid\Sources` (316 files) |
| DevExpress data controller / storage | `…\ExpressDataController\Sources` (`cxCustomData.pas` 17.9k lines, `cxDataStorage.pas`, `cxFilter.pas`, `cxVariants.pas`, `cxLike.pas`) |
| DevExpress sort/thread core | `…\ExpressCore Library\Sources\dxCoreClasses.pas`, `dxThreading.pas` |
| DevExpress conditional formatting | `…\ExpressSpreadSheet Core\Sources\cxDataControllerConditionalFormatting*.pas`, `dxSpreadSheetConditionalFormattingRules.pas` |
| MTG Studio v3 source | `D:\repos\mtg.studio.src\version-3\src` (the requested `version3` is `version-3`) |
| MTG Studio feature inventory | `D:\repos\mtg.studio.src\version-3\docs\migration-inventory.md` |
| Neper UI today | `lib/e/ui/collection.e`, `lib/e/ui/sheet.e`, `lib/e/algo/view.e`, `docs/widget-library-proposal.md` |

Caveat: MTG Studio's README says it builds against DevExpress **20.2.5**; the source available here is
**23.2.6**. Everything MTG Studio calls exists in both (checked by name), but internals quoted in §3 are 23.2.6.

---

## 1. The requirement in one paragraph

A grid that holds **150,000 records** (MTG Studio's card pool is `CardPoolSize = 119117 + 1000` printings,
`src/shared/models/mtgstudio.app.pas:34`; 150k is the headroom the user asked for) and re-sorts, re-filters,
re-groups, re-summarises and incrementally searches them *interactively*, with ~24–40 typed columns, three views
open at once (card pool, deck, collection), custom comparers, custom cell painting, in-place editing with
write-through, persisted layout and filters, and export. The Delphi build does this today on every keystroke of the
filter row (1 s delayed) and every header click; the Neper grid must not feel slower.

---

## 2. How MTG Studio v3 uses the grid

### 2.1 Grid instances

`TcxGrid` components: 19 in DFMs. Real, user-facing ones:

| Grid (form) | Views (levels) | Data | Notes |
|---|---|---|---|
| `dbgCards` (main) | `btvCards` (card pool, **~120k rows**), `btvCollection` (top, when mode = Deck-from-Collection) | unbound, bulk-loaded | the 150k case |
| `dbgDeck` (main) | `btvDeckCards` (deck, small), `btvCollection` (bottom, mode = Collection-from-Pool) | unbound | editable qty |
| `dbgPrices` (main) | `tvPrices` (live store prices, small) | unbound | hyperlink + button column |
| `dbgEditions`, `dbgSelectEdition` (filter / select-edition forms) | `FtvEditionInfo`, `FtvSelectEdition` (banded, built in code) | unbound | check-box select lists |
| `dbgSort` (sort dialog) | `tvSort` | unbound | user picks sort columns |
| `gdShortcuts` (options) | `tvShortcuts` | unbound | editable shortcut column |
| Statistics form ×8 | probability, mana slots, starting hand, deck, in-play, discard, advanced … | unbound | small; totals/footers |
| Import wizard `dbgPreview` | 12 per-format preview views (MTGO, Deckbox, Magic Assistant …; 9 table + 3 DB-bound) | unbound or DB | column set per format |
| Messages, Abilities forms | simple read-only lists | unbound | double-click |

Also: `TcxVerticalGrid` (deck properties), `TcxTreeList` (abilities filter, 2 columns). They share editors and
styles with the grid and should be covered by the same editor/style layer (§5.6), but are not the table grid.

The three main views are built **in code** in `TMainForm.FormCreate`
(`ui/vcl/main.vcl.form.pas:1551`: `CreateCardPoolView` 1553, `CreateDeckCardsView` 2471,
`CreateCollectionView` 3430) as `TcxGridBandedTableView` — the DFM ones are the small dialogs.

Same grid, swapped view: `dbgCards.ActiveLevel := lvlCards | lvlTopCollection; FocusedView := …`
(`SetMode`, line 12516). MTG Studio uses **Levels as a view switch, not as master-detail**; there is no
master-detail data anywhere (all `TcxGridLevel` have one view, no children).

### 2.2 Data feeding (the performance-critical path)

Unbound mode, no `DataSource`. `TMtgStudioDatabase.FillCardPool` (`shared/models/database/mtgstudio.database.pas:1687`):

```
DataController.BeginUpdate;
RecordCount := CardPoolSize;                 // pre-size once
while Reader.Read do begin                   // SQLite cursor
  Values[i, 0..22] := Reader.GetInt/GetString/…;   // ~23 typed cells per row
  Inc(i);
end;
RecordCount := i;
DataController.EndUpdate;                    // one sort/filter/group/summary pass
```

`LoadCollection` (`main.vcl.form.pas:1476`) is the same with ~38 cells per row, plus `OnRecordChanged := nil`
during the load so write-through handlers do not fire. A status line reports
`Loaded %d cards in %.3f sec` — **that is the existing performance baseline to measure**.

Requirement R-LOAD: bulk columnar append with a single deferred recompute; per-cell setters must not trigger
change notification while a batch is open; `RecordCount` can be pre-set (capacity hint) and corrected after.

### 2.3 Feature usage matrix

Legend: **U** used (code or DFM), **C** configured-but-trivial, **N** not used (DevExpress has it).

#### Columns and editors

| Feature | MTG Studio usage | DevExpress API |
|---|---|---|
| Value types | Integer, Float, Boolean, String, DateTime (`Added`) | `DataBinding.ValueTypeClass := TcxIntegerValueType / TcxBooleanValueType …` |
| Text | 47× `TcxTextEditProperties` (read-only, centre/right alignment, `IncrementalSearch`) | `PropertiesClassName` |
| Spin | 7× (deck qty/sideboard qty with `MaxValue = MaxSameCardsInDeck`, collection qty, mana-slot qty) | `TcxSpinEditProperties` |
| Memo | 7× (rules text, flavor, artist; also feeds the `Preview` row) | `TcxMemoProperties` |
| Image combo | 5× (favorite star, condition, desired, print type; image per value) | `TcxImageComboBoxProperties` |
| Check box | 12× (foil, buy/sell flags; `ValueChecked/Unchecked`, even `'F'/'NF'` strings) | `TcxCheckBoxProperties` |
| Button edit | 2× (Buy-At / Sell-At with `OnButtonClick`) | `TcxButtonEditProperties` |
| Date edit | 1× | `TcxDateEditProperties` |
| Hyperlink / Label | store URL, `LabelEffect` | `TcxHyperLinkEditProperties`, `TcxLabelProperties` |
| Header image + hint | star header glyph; per-column `HeaderHint` shown via MouseMove hit-test | `HeaderImageIndex`, `HeaderHint` |
| Per-column alignment (header / cell / footer / group-summary) | all four used | `HeaderAlignmentHorz/Vert`, `Properties.Alignment`, `FooterAlignmentHorz`, `GroupSummaryAlignment` |
| Width, min width, best-fit max width, `AutoWidthSizable` | U | `Width`, `MinWidth`, `BestFitMaxWidth` |
| Column hidden but not offered in chooser | many (`Id`, `MtgoId`, …) | `Visible=False`, `VisibleForCustomization=False` |
| Per-column option switches | `Editing, Filtering, Focusing, Grouping, Moving, Sorting, HorzSizing, VertSizing, IncSearch, ShowCaption, ShowEditButtons` all toggled per column | `Options.*` |
| Per-column filter-popup switches | `FilteringPopup, FilteringMRUItemsList, FilteringFilteredItemsList, FilteringPopupMultiSelect, FilteringAddValueItems` | `Options.Filtering*` |
| Display text hook | ~30 `OnGetDisplayText` (row number, `$` formatting, flavor newline strip, empty→'' for 0) | `OnGetDisplayText` |
| Value display format | `'$#0.00'`, `'#0.00'`, `'#0'` | `Properties.DisplayFormat` |
| Computed ("Row") column | row ordinal from `ARecord.Index` | `OnGetDisplayText` |
| Column position / band / order | `Position.BandIndex/ColIndex` set for every column | banded view |

#### View-level

| Feature | Usage | DevExpress API |
|---|---|---|
| Bands | 2 bands per main view; band 0 `FixedKind := fkLeft` ("Card Name" / "Key"); headers hidden (`BandHeaders := false`) | `Bands.Add`, `FixedKind`, `FixedBandSeparatorWidth` |
| Navigator | on, info panel on; First/Prior/Next/Last/PriorPage/NextPage + Filter custom button; all edit buttons hidden; Refresh visible in collection | `View.Navigator.*`, `OnButtonClick` |
| Footer | on (deck, collection, most dialogs) | `OptionsView.Footer` |
| Group-by box | off in all (grouping is by menu / sort dialog) | `OptionsView.GroupByBox := false` |
| Row indicator | `IndicatorWidth := 20` in deck (custom-drawn warnings: banned/restricted/legal-reprint/token) | `OnCustomDrawIndicatorCell`, `TIndicatorPainter` |
| Preview row | "Card Text" toggle shows rules text under each row; column + max line count persisted | `Preview.Visible/Column/MaxLineCount` |
| Grid lines | Both / Horizontal / Vertical / None via menu | `OptionsView.GridLines` |
| Header on/off, indicator on/off, auto-width on/off | menu toggles, persisted | `OptionsView.Header/Indicator/ColumnAutoWidth` |
| Cell end-ellipsis | on | `CellEndEllipsis` |
| "No data" text | per view (`<No cards in card pool>`, `Loading...`) | `NoDataToDisplayInfoText` |
| Fonts | whole-grid font size changed at runtime (`ChangeGridsAndTreesFontSize`) | styles / font |
| Zebra + selection + inactive colours | via style sheets (`TableView`, `BandedTableView`, `PriceView`) | `Styles.StyleSheet`, `ContentEven/Odd`, `Selection`, `Inactive` |
| Row colouring | foreground by card colour or rarity (setting) in `OnCustomDrawCell`; replicates zebra manually in `CellBackgroundColor` | `OnCustomDrawCell` |
| Conditional formatting | rules manager dialog on all three main views | `ConditionalFormatting.ShowRulesManagerDialog` |
| Customisation form (field chooser) | opened from menu; made top-most (DevExpress KB1500 workaround) | `Controller.Customization`, `OnCustomization` |
| Quick customisation | column drop-down with reordering enabled | `ColumnsQuickCustomization*` |
| Multi-select, row-select | `MultiSelect`, `CellSelect := false`, `HideFocusRectOnExit := false` | `OptionsSelection.*` |
| Select-ability gate | group rows not selectable | `OnCanSelectRecord` |
| Editing policy | card pool: no edit (`Editing := false`, "needed for filter row"); deck: edit qty; collection: `Editing := not Locked` (runtime lock) | `OptionsData.Editing` |
| Focus rules | `FocusCellOnTab`, `FocusCellOnCycle`, `ImmediateEditor` (on in pool for filter row, off elsewhere) | `OptionsBehavior.*` |
| Drag & drop | grid-to-grid card drag, drag text = card name, no highlight, no auto-scroll | `DragMode`, `OnStartDrag/DragOver/DragDrop`, `DragDropText`, `OnGetDragDropText` |
| Hints | column header hints, row-indicator hints, hint style controller | `HintStyleController`, hit test |
| Context menus | by hit test: `[gvhtNone, gvhtCell, gvhtRecord, gvhtPreview]` → card menu, `[gvhtFilter]` → filter menu; `AlwaysFireOnPopup` | `TcxGridPopupMenu` |
| Keyboard | Ins/Enter/Num+/Space add; Num-/Del remove; Num÷/× sideboard; Ctrl+Tab deck switch; Apps = menu; gated on `not IsIncSearching` | `OnKeyDown`, `Controller.IsIncSearching` |
| Mouse | row-indicator click clears filter row; hover → card preview; wheel → card step | `OnMouseDown/Move/Wheel/Leave`, `GetHitTest` |
| Level / view switching | one grid, three modes, view swapped per mode | `ActiveLevel`, `FocusedView` |

#### Data-controller-level

| Feature | Usage | API |
|---|---|---|
| **Sort** | header click; multi-column via `Sort(Columns[])` helper (clear then `SortIndex := i, soAscending`); sort dialog; "Edition & Name", "Name & Edition"; clear; case-insensitive (`dcoCaseInsensitive`), optional `dcoAnsiSort` | `SortIndex/SortOrder`, `ClearSorting`, `BeginSortingUpdate` |
| **Custom comparers** | 7 per view: Cost (colour+CMC+cost string), Edition symbol (release order, then collector no.), Colour (WUBRG order), Power, Toughness (`*`, `X`, numbers), Collector number (`12a`, `★`), Edition abbr (release order) | `DataController.OnCompare` |
| **Group** | by Edition / Type / Colour / Rarity; expand/collapse all; remember expansion (`dcoSaveExpanding`); group footers `gfVisibleWhenExpanded`; Office-11 group style; group summary alignment | `GroupIndex`, `Groups.FullExpand/FullCollapse`, `OptionsView.GroupFooters/GroupRowStyle` |
| **Summary** | footer: Sum, Count, Average over typed columns with format strings `'Cards: #0'`, `'$#0.00'`, `'Avg: #0%'`; default group summary Sum(DeckQty); events to override text; `OnAfterSummary` | `Summary.FooterSummaryItems`, `DefaultGroupSummaryItems`, `OnGetText`, `OnAfterSummary` |
| **Filter row** | visible by setting; delayed apply (`fracDelayed`, 1000 ms); operator customisation; info text; clicking indicator clears; `*`/`?` wildcards | `FilterRow.*`, `Filter.PercentWildcard/UnderscoreWildcard` |
| **Filter dialog** | stock `FilterControl` dialog, re-skinned; Open/Save/Apply | `OnFilterControlDialogShow`, filter `.filter` files via properties store |
| **Programmatic filter tree** | `Root.AddItemList(fboAnd/fboOr)` nested 3–4 deep; `AddItem(column, op, value, displayText)` with `foEqual, foNotEqual, foLess, foGreater, foLike, foNotLike, foInList` (`filter.vcl.form.pas`, ~80 operator uses) | `TcxDataFilterCriteria` |
| **Filter value list override** | rarity / colour popup lists are replaced by fixed "C - Common" style items | `Filter.OnGetValueList` |
| Filter state | persisted per grid; `FilteredRecordCount`, `Filter.IsFiltering`, `Filter.Clear`; status bar "x of y" | `Filter.*`, `FilteredRecordCount` |
| Incremental search | on a chosen column (`IncSearchItem`), mode *begins-with / within*; next/prev (`Locate`, `LocateNext`); wrap by `FocusedRecordIndex := -1`; result scrolled to top | `OptionsBehavior.IncSearch*`, `DataController.Search.*` |
| Navigation | `FocusedRecordIndex`, `FocusedRowIndex`, `TopRecordIndex`, first/last/page; bookmarks | `GotoFirst`, `SaveBookmark/GotoBookmark/IsBookmarkAvailable` |
| Selection API | `SelectedRecordCount`, `SelectAll`, `SelectRows`, `DeleteSelection`, `DeleteRecord`, `AppendRecord` | `Controller`, `DataController` |
| Change events | `OnFocusedRecordChanged` (drives morph preview), `OnSelectionChanged`, `OnRecordChanged(rec, item)` (write-through) , `OnBeforeDelete`, `OnFilterChanged` | events |
| Edit write-through | `OnRecordChanged` dispatches per column: qty→DB + recompute `MarketValue = qty × price`; foil→DB + reprice; notes/storage/used/needed/excess/target/buy/sell/… | event |
| Layout persistence | per column: `GroupIndex, Position, SortIndex, SortOrder, Visible, Width, AlignHorizontal`; per view: `ColumnAutoWidth, Footer, GridLines, GroupByBox, Header, Indicator, Navigator, Preview.*`; stored in `.desk` per host | `TcxPropertiesStore` |
| Export | Text, XML, HTML, XLSX (`ExportGridToXLSX(...)`), copy as text, print/preview via component printer | `cxGridExportLink` |
| Best fit | menu "Best fit" on all three views | `ApplyBestFit(nil)` |

Not used by MTG Studio (do **not** build first): master-detail, card/layout/chart/tile/WinExplorer/carousel views,
server mode, grid mode, DB-bound views, fixed data rows, inplace/detached edit form, cell merging, cell multi-select,
find panel, Excel-style filter popup, date-range grouping, scrollbar annotations, sparkline/rating editors,
unbound expressions.

### 2.4 Behaviours MTG Studio relies on (acceptance semantics)

1. **Stable sort.** Ties resolve by original record index (`CompareEqualRecords`, §3.4). Users see deterministic
   order after multi-column sort and re-sort.
2. **Nulls sort first ascending** (`TcxValueDef.CompareValues`: null < any value; null = null).
3. **Case-insensitive** string compare via upper-casing (`dcoCaseInsensitive`), not locale collation, unless
   `dcoAnsiSort`.
4. **Like semantics**: `*` = any run, `?` = one char (configured wildcards); `foLike` with `*x*` is "contains".
   **Case:** `foLike` is *case-sensitive* in the Delphi grid (measured, §6.1.1: `*creature*` → 0 rows,
   `*Creature*` → 56,095) although sort is case-insensitive. **Decision (owner, 2026-10-12): the Neper grid does
   NOT keep this quirk — Like / Contains / Begins / Ends and equality-on-text are case-insensitive by default**
   (a per-criterion "match case" flag stays available; default off). Parity tests must therefore expect
   `*creature*` → 56,095, not 0.
5. **Custom order columns** (cost, symbol, colour, P/T, collector no.) sort by a domain key, not text.
6. **Filter row is a pseudo-record** in the same view (`RecordIndex = -1`); MTG's draw code guards against it
   (`DisplayTexts[...] = ''`). Neper should expose it as a separate region, not a fake row.
7. **Record index ≠ row index.** `ARecord.Index` is the visible position (used for the "Row" column and zebra);
   `RecordIndex` is the storage index. Both must be available to cell callbacks.
8. **Group rows are visible rows** that cannot be selected, count in the row total, and do not count in
   `FilteredRecordCount`.
9. **Editing is interlocked with sort/filter**: editing a cell that is the sort key must not teleport the row
   under the cursor until commit (DX: `dcoImmediatePost` + re-sort on post).
10. **Expansion state survives re-sort/re-filter** (`dcoSaveExpanding`), keyed by the group's value path.

### 2.5 Menu-driven grid features (scraped from the bar manager and action handlers)

Source: `main.vcl.form.dfm` bar manager (`bmMainMenu`, 10 toolbars, 9 popup menus) and the `ac*Execute/Update`
handlers in `main.vcl.form.pas`. Shortcuts are decoded from the numeric `ShortCut` property. Full menu dump:
File · Cards · Search · View · Card Art · Online · Reports · Tools · Admin · Help.

**Scoping rule (applies to every row below).** Almost every View/Search/Cards grid command is *view-scoped*: it
acts on `FSelectedView` ∈ {CardPool, Deck, Collection} = whichever of the three grids last had focus, and its
enabled/checked state is re-read from that view on each `Update`. The grid API must therefore expose each option
as a **read/write property on the view** (not a global), and a command layer picks the focused view.

| Menu → item (shortcut) | Grid behaviour | DevExpress call | Neper need |
|---|---|---|---|
| **View → Sort by Edition, Card Name** / **Sort by Card Name, Edition** | multi-key sort: `[Symbol, Name]` or `[Name, EditionAbbr]`; clears previous sort | `View.Sort([cols])` helper = `BeginSortingUpdate; ClearSorting; SortIndex/SortOrder; EndSortingUpdate` | `sort_by(cols)` atomic replace |
| **View → Sort…** | dialog listing all non-hidden columns with a 3-state order (none / asc / desc, coloured), OK applies, Clear resets | per column `SortOrder := …` inside `BeginSortingUpdate` | multi-sort editor (also "user sort levels", `e.algo.view` already has level edits) |
| **View → Clear Sort Order** | | `Sort([])` | |
| **View → Group by Edition / Type / Color / Rarity / Remove Grouping** | single-level grouping; shows the group box; adds a per-group `Count: #` summary; Remove hides group box and clears group summaries | `GroupBy` helper (`BeginGroupingUpdate`, `SummaryGroups`, `GroupIndex`) | group + group summary spec as one atomic edit |
| **View → Show Group Box** (toggle) | drag-column-to-group panel | `OptionsView.GroupByBox` | group box region (drop target for headers) |
| **View → Full Expand / Full Collapse** | expand/collapse all groups; Expand shows busy status | `Groups.FullExpand/FullCollapse` | O(groups) bulk expansion |
| **View → Legality** (Ctrl+L, toggle) | shows/hides the Legality column of the current view | `Column.Visible` | column visibility API |
| **View → Card Rules** (Ctrl+T, toggle) | shows rules text as a preview row under each card (all three views independently) | `View.Preview.Visible` (+ `Preview.Column`) | preview row |
| **View → Show Columns…** (Ctrl+Alt+C) | opens the column chooser (hidden columns); forced top-most | `Controller.Customization := true` | customisation panel |
| **View → Best Fit (all columns)** | fits every column to its content | `ApplyBestFit(nil)` | `best_fit` over sampled rows (`BestFitMaxRecordCount`) |
| **View → Columns Auto Width** (toggle, with busy status) | stretch columns to the viewport | `OptionsView.ColumnAutoWidth` | auto-width mode (relayout of 24+ columns must be cheap) |
| **View → Show Header** (toggle) | hide/show column headers | `OptionsView.Header` | |
| **View → Show Indicator** (toggle) | row-indicator column; **coupled to** `ColumnsQuickCustomization` — turning the indicator on enables the quick column menu in the indicator header (DevExpress Q589867 requires the quick-customisation flag be set *first*) | `OptionsView.Indicator`, `OptionsCustomize.ColumnsQuickCustomization` | indicator header = column-menu button |
| **View → Show Grid Lines** ▸ Both / Horizontal / Vertical / None | split button + 4 radio items | `OptionsView.GridLines := glBoth/glHorz/glVert/glNone` | |
| **View → Conditional Formatting…** | rule manager dialog | `ConditionalFormatting.ShowRulesManagerDialog` (requires `cxDataControllerConditionalFormattingRulesManagerDialog` linked) | rules model + manager UI |
| **View → Show Summary Footer** (toggle) | | `OptionsView.Footer` | |
| **View → Show Navigator** (toggle) | grid navigator bar | `Navigator.Visible` | |
| **Search → Search…** (Ctrl+F) | dialog "Search for Card": text, target (Card Pool / Deck / Collection, limited by mode), seeded from the current incremental-search text | `Controller.IncSearchingText`, then `QuickSearch` | search dialog + `locate` |
| **Search → Next / Previous** (Ctrl+↓ / Ctrl+↑) | next/prev match; wrap forward by resetting focus; match is scrolled to the top | `Search.Locate/LocateNext`, `TopRecordIndex := FocusedRecordIndex` | |
| **Search → Cancel** (Ctrl+Shift+F, Esc) | cancel incremental search, clears quick-search box; enabled only while searching | `Controller.CancelIncSearching`, `IsIncSearching` | search mode state |
| **Search toolbar quick-search combo** | type-ahead on the focused view's `IncSearchItem`; mode *from start* / *within* from Options | `Search.Locate(item, text, isAnywhere)` | |
| **Search → Toggle Bookmark** (Ctrl+Shift+1; checked when set) / **Go to Bookmark** (Ctrl+1) | **one bookmark per view**; stored on the record (survives sort/filter); go-to deselects old focused row, selects the new | `IsBookmarkAvailable`, `SaveBookmark`, `ClearBookmark`, `GotoBookmark` | per-view single bookmark keyed by row id |
| **Search → First / Previous Page / Previous Card / Next Card / Next Page / Last** (also Navigator bar) | focus movement with busy status | `Controller.GotoFirst/…/GotoLast` | page size = visible rows |
| **Search → Filter Top… (F3) / Filter Bottom… (Shift+F3)** | opens MTG's own filter form for card pool / deck / collection (depends on mode) | app dialog → builds DX criteria | filter form + criteria API |
| **Search → Advanced Filter…** (Ctrl+Alt+F) | opens the stock criteria editor on the *selected* view | `Filtering.RunCustomizeDialog` | criteria tree editor (nested AND/OR/NOT, operators, value editors) |
| **Search → Reset All Filters** | clears all three grids' filters **and** the data scope (`ShowUniqueCards := false`, `CardPoolValidCards := All`) and reloads the pool | settings + `FilterCardPool` + `ClearFilterForm` | |
| **Search → Show Latest Reprints Only / All Cards / MTG Online Only / Wagic Only** (radio) | *data-scope* filters applied at **load** time (SQL), not grid filters: reload card pool through `FillCardPool(ShowUnique, ValidCards)` | `LoadCardPool` | reload must be fast (the 150k load path is user-visible here) |
| **Filter bar popup** (right-click filter box: Active / Copy / Clear / Customize) | toggle filter on/off without losing criteria; copy human-readable filter text; clear; open editor | `Filter.Active`, `Filter.FilterCaption`, `Filter.Clear`, `Filtering.RunCustomizeDialog` | `Filter.active` is separate from `Filter.criteria`; a text rendering of the tree |
| **Cards → Select All** (Ctrl+A) | selects every visible record (busy status) | `DataController.SelectAll` | O(1) "all selected" representation |
| **Cards → Cut / Copy / Paste** (Ctrl+X/C/V) | card clipboard (app-level, not text) | selection → card ids | selection → id list |
| **Cards → Copy as Text ▸ Copy Card Name / Copy Selected / Copy All** | grid's text clipboard of selected or all rows | `View.CopyToClipboard(ACopyAll)` | TSV clipboard for selected/all |
| **Cards → Export ▸ HTML / PDF / Excel / CSV / Plain Text / XML**, **Print ▸ Print / Page Setup / Preview / Designer** | export & print of the current view (§5.6) | `ExportGridTo*`, `TdxComponentPrinter` | export + print link |
| **Cards → Lock Collection** | toggles `btvCollection.OptionsData.Editing` (caption flips to *Unlock*); enabled only in collection-editing mode | `OptionsData.Editing` | `editing` flag |
| **Cards → Add / Add 4 / Add Foil / Add to Sideboard / Remove / Increase / Decrease / Toggle Quantity / Set as Companion / Batch Update / Delete All** | commands on the *selected rows* of the focused grid; enable rules depend on mode, selection, lock, "no inline editor open" | `Controller.SelectedRecordCount`, `IsEditing`, `FocusedRecord.Values[]` | row-command surface; `is_editing` guard |
| **Cards → Next Deck / Previous Deck** (Ctrl+→ / Ctrl+←) | switch deck tab (also Ctrl+Tab when a grid has focus) | n/a (page control) | |
| **Context menus** | `pmCards` (pool), `pmDeckCards`, `pmCollection`, `pmFilter`/`pmFilterDeck` (by hit-test: *filter box* ↔ rows) | `TcxGridPopupMenu`, `HitTypes` | hit-region → menu |
| **Options (F10) → Grids (F9)** | row colour (none / by card colour / by rarity), foil symbol on name, font size (Small 7, Medium 8, Large 10, Extra-large 12 pt for all grids and trees), incremental search (*from start* / *within*), **Enter key** (move to next column, wrapping to next row / move down) | `TGridVisualization` → draw handlers, `ChangeGridsAndTreesFontSize`, `VK_RETURN` handler | grid-wide settings object |
| **Options → Shortcuts (F4)** | grid of commands with editable shortcut column | `gdShortcuts` | editable key-capture cell |
| **Show filter row** (setting `ShowCardPoolFilterRow`) | card pool only | `btvCards.FilterRow.Visible` | |

Observations that change the design:

* **Selection scope vs. view scope.** Three views, one command layer. A single `DataGrid` instance must be cheap
  to hold three of (≈ 3 × 150k worth of state is *not* required: only the pool is 150k).
* **Busy status.** Long operations (expand all, best fit, auto width, goto, select all, group, sort) are wrapped in
  `Statused("…", proc)` which sets the status bar text and a wait cursor. The grid should expose
  `on_busy(begin/end, text)` or take a cancellable job so the shell can show progress rather than freezing.
* **Everything a toolbar toggles is persisted** (`OptionsView.*`, `Preview.*`, column visibility/width/sort/group),
  per view, per host (§5.6).
* **Settings feed the painters** (row colour, foil symbol, font size) — the grid needs a *theme/size scale* hook,
  not a per-cell font property.
* **Enter-key navigation** is custom (move to next column wrapping rows, or move down) on deck and collection
  grids; the grid must let the app override Enter without losing in-place editing behaviour.
* **Bookmark** is one slot per view, not a list; `Toggle` clears-then-sets.

---

## 3. How DevExpress keeps 150k records fast

Every number below was read from source; file:line are 23.2.6.

### 3.1 Layered model

```
TcxGrid
 └ TcxGridView (Table / Banded / Card / …)         cxGridTableView.pas, cxGridCustomTableView.pas
    ├ ViewData   : lazy TcxCustomGridRecord objects          (cxGridCustomTableView.pas:21044)
    ├ ViewInfo   : only visible rows get cell view-infos
    └ DataController : TcxCustomDataController               (cxCustomData.pas:2228)
        ├ Provider  : unbound storage | DB dataset | custom data source | server mode
        ├ DataStorage: TcxDataStorage, record buffers         (cxDataStorage.pas:445)
        └ Info      : TcxCustomDataControllerInfo             (cxCustomData.pas:981)
            ├ RecordList : TdxFastList of record indexes      ← the sorted/filtered *order*
            ├ SortingFieldList / GroupingFieldList
            ├ DataGroups : group ranges                        (cxCustomData.pas:751)
            ├ Selection, FocusingInfo, ExpandingInfos
            └ Summary    : footer + group summaries            (cxCustomData.pas:1843)
```

### 3.2 Storage (`cxDataStorage.pas`)

* **Row-wise byte buffers.** `TcxDataStorage.FRecordBuffers: TList` — one `PAnsiChar` buffer per record; each
  `TcxValueDef` has `Offset`, `DataSize`, `BufferSize` inside it (`:316-379`); record size = sum, plus a
  per-record flag byte (null / error / text-stored). `RecordCount` setter allocates buffers; `AppendRecord`,
  `InsertRecord`, `DeleteRecord`.
* **Typed value classes** (class-function vtables, no instances): `String`, `WideString`, `Smallint`, `Integer`,
  `Word`, `Boolean`, `Single`, `Float`, `Currency`, `DateTime`, `LargeInt`, `FMTBcd`, `SQLTimeStamp`, `Variant`,
  `BLOB`, `Object`. Each provides `CompareValues(P1,P2)`, `GetDataValue`, `SetDataValue` — **comparison is a
  direct pointer compare of typed memory, no Variant.** Strings are stored as `string` references inside the
  buffer (managed).
* **Null** is a flag byte in the buffer, not a value.
* **Optional display-text cache** per cell (`TextStored`) for columns whose display differs from the value.
* **Record IDs** optional (`UseRecordID`) for stable identity across delete/insert.

Weaknesses to avoid: one heap block per record (150k allocations, poor locality for single-column scans);
managed string per cell; `Variant` at every public boundary (`Values[i,j]`, `OnCompare(V1,V2: Variant)`,
summaries); no dictionary encoding, so `Contains` and value lists re-scan strings.

### 3.3 Index list, not data movement

`FRecordList` is a `TdxFastList` (raw pointer array). `DoLoad` fills it `0..RecordCount-1`
(`cxCustomData.pas:8575`). **Sorting, filtering and grouping only permute/shrink this index array**; the buffers
never move. Filtering marks dropped entries `cxDeletedRecord` then `Pack` (`:12627-12686`).

### 3.4 Update pipeline

`DoUpdate` (`cxCustomData.pas:8616`) — only the stages whose change flag is set run:

```
if Load    : DoLoad ; DoFilter                       (re-index, apply filter)
if summary : DoBeginSummary
if Sorting|Grouping : DoSort                         (index list sort)
if RowFixing|order : DoFixRows
if Grouping: DoGrouping                              (one linear pass → group ranges)
ResetFocusing ; CheckInfo
if summary : DoEndSummary ; (sort-by-summary → DoSortBySummary)
find-panel update
```

* **Sort** (`:8584`): `PrepareSorting` per field, then
  `FRecordList.Sort(CompareRecords, MultiThreaded and fields.SupportsMultiThreading)`.
  `CompareRecords` (`:9521`) loops the sort fields, then falls back to `CompareEqualRecords` = compare record
  indexes → **stable**. Per field: `OnCompare` if assigned (with two `Variant`s) else `InternalDefaultCompare`
  → `NativeCompareRecords` → `TcxValueDef.Compare` on the two buffers (`:14105`). Descending = negate.
* **Grouping** (`:8382 CreateGroups`): one pass over the *sorted* list; a new group opens when
  `CompareGroupRecords` differs from the open group at that level. Result: array of
  `TcxDataGroupInfo { RowIndex, Level, FirstRecordListIndex, LastRecordListIndex, Expanded }`. Group rows and data
  rows are addressed by **visible row index** through `GetRowInfo` — a lookup over the group array (no per-row
  objects).
* **Summary** (`:7273-7300`): linear loops over index ranges; accumulators are `Variant` arrays + integer counts.
  Group summaries are computed per group range. Multi-threaded option exists
  (`TcxDataControllerMultiThreadedOptions: Filtering, Sorting, Summary`, `:1934`).
* **Defaults**: `dxDefaultMultiThreadedFiltering = True`, `dxDefaultMultiThreadedSorting = True` (`:47-48`).

### 3.5 The sorter (`dxCoreClasses.pas`, `dxThreading.pas`)

* Single thread: a **modified quicksort** (median-of-3, tail recursion on the smaller half) that switches to
  **insertion sort below 35 elements** (`dxInsertionSortCount = 35`, `:711-820`). Comparator is a function
  pointer (`TListSortCompare`).
* Multi-thread (`TdxMultithreadedSort`, `dxThreading.pas:805-1125`): used when `Count > dxMaxUserWorkItems (32)`
  and `CPUCount > 1`. Splits into **16 chunks** (4+ threads; 8 for 2–3), each chunk quick-sorted on a Windows
  thread-pool work item (`QueueUserWorkItem`), then a **pairwise parallel merge tree** (`MergeChunks`, temp buffer
  of `Count` pointers). A lock guards one multithreaded sort at a time; fallback is single-thread.
* Filtering multi-thread: `dxListIterator.Iterate` over `RecordList` in chunks, each worker evaluating
  `DoGlobalFilterRecord` (`:12660-12666`); allowed only if every filter item satisfies
  `TcxDataFilterCriteriaItem.SupportsMultiThreading` (`:4148`): the field is not an expression and **not
  "conversion needed for compare"** (string columns when the controller is case-insensitive/ANSI-sorting,
  or sort-by-display-text), and the column's editor properties allow repository sharing.
* **Sort eligibility** is narrower (`TcxSortingFieldList.SupportsMultiThreading`, `:3389`;
  `TcxCustomDataField.SupportsMultiThreading`, `:15000`): every sort field must not be an expression and
  must not sort by display text. **An assigned `OnCompare` does *not* disable the parallel sorter** — the
  event is simply called from the worker threads (`CompareByField`, `:13915`), so a handler must be
  thread-safe. *(An earlier revision of this document stated the opposite; that was an unverified inference
  and is corrected here.)* Whether the sorter actually engages for MTG's views is therefore **not known**
  from the source alone; §6.1.2 has the harness experiment that answers it.

Consequence for MTG Studio: its seven `OnCompare` handlers box every cell into a `Variant` per comparison,
upper-case two strings per comparison (default branch), and `CompareEditionRelease` additionally scans the
`Editions` array linearly **per comparison**. If the parallel sorter *is* engaged, these handlers also hammer the
memory manager from up to 16 threads, which can erase the gain. These are the hot spots a Neper design should
remove by construction (§5.3).

### 3.6 View layer laziness

* `ViewData.Refresh(RecordCount)` sets `FRecords.Count := n` — a sparse pointer array — and destroys previous
  record objects (`cxGridCustomTableView.pas:21253`). **Record objects are created on first access**
  (`GetRecord`, `:21044`) via `DataController.GetRowInfo(index)`.
* Only rows intersecting the viewport get `ViewInfo` cells; scrolling offsets existing view-infos by a row delta
  (`Offset`, `CanOffsetView`) and creates the new edge rows.
* Row heights are fixed (`DataRowHeight`) unless `CellAutoHeight` / preview; fixed height means the scrollbar
  position ↔ row index is O(1). Variable heights switch to a per-row height cache.
* `BeginUpdate/EndUpdate` (view and data controller), `BeginSortingUpdate/EndSortingUpdate` coalesce passes.

### 3.7 Search and value lists (the slow parts)

* Incremental search / `Locate`: **linear scan** over the filtered rows, calling `GetInternalDisplayText` (a
  `string` allocation per probe) and `DataCompareText` (`FindRecordIndexByText`, `:11718-11767`). Fine for a
  keystroke at 120k rows because it starts at the focused row and usually hits early; worst case is O(n) per key.
* Column filter drop-down value list (`TcxDataFilterValueList.Load`, `:4196`): `PopulateFilterValues` scans all
  (or all filtered) records collecting unique display texts, then sorts them. O(n log u) per open.
* `Filter.OnGetValueList` post-edits the list (MTG replaces it for rarity/colour).

### 3.8 What this tells us

| DevExpress design | Keep | Change |
|---|---|---|
| Index array over immovable storage; stages recomputed only when flagged | **keep** | — |
| Stable multi-key sort with record-index tie-break | **keep** | — |
| Group = ranges over the sorted index; rows addressed by group array | **keep** | add prefix-sum so row→(group, offset) is O(log g) |
| Chunked parallel sort + parallel merge | **keep idea** | use Neper's pool (`e.thread.pool` `fork_join`) and radix on precomputed integer keys |
| Lazy record/view-info creation | **keep** | per-frame arena build (already the `e.ui.collection` model) |
| Row-wise heap buffers + managed strings + `Variant` API | **drop** | columnar typed arrays, dictionary-encoded strings, typed accessors |
| Comparer callback per comparison | **drop** | comparer = *sort-key derivation* (rank per distinct value), then integer sort |
| Linear display-text search | **improve** | dictionary lookup + sorted-dictionary prefix range for begins-with |
| Value list by scanning | **drop** | the dictionary *is* the value list; filtered variant = bitset of used ids |
| Filter evaluated on every record from scratch | **improve** | narrow previous result when the new filter is stricter (typed-ahead) |
| Summary via `Variant` accumulators | **improve** | typed accumulators; parallel partial reduce |

---

## 4. DevExpress `TcxGrid` capability catalogue (for scoping)

Counts are from the source option classes
(`cxGridTableView.pas`, `cxGridCustomTableView.pas`, `cxGridCustomView.pas`). Tier: **A** = MTG Studio needs it;
**B** = expected of "a very powerful grid", cheap once A exists; **C** = DevExpress-specific, defer.

### 4.1 Views and data modes

| Capability | Tier | Notes |
|---|---|---|
| Table view | A | |
| Banded table view (bands, fixed bands, band moving) | A | `cxGridBandedTableView.pas` 11.5k lines |
| Row-level multi-select, cell select, cell multi-select | A / B | |
| Master–detail levels, multiple details, detail tabs | C | not used by MTG |
| Card / Layout / WinExplorer / Tile / Carousel / Chart views | C | not used; chart view is its own product (`e.chart`) |
| Unbound (stored) data | A | the MTG mode |
| Bound to dataset; "grid mode"; server mode (SQL paging) | B | Neper analogue: `TableSource` over `e.db` cursor; paging source |
| Custom data source (`TcxCustomDataSource`) | A | the callback source `e.ui.collection` already has |
| Unbound columns / calculated expressions | B | |

### 4.2 Table-view options (property names from source)

* **Behavior (≈30)**: `AlwaysShowEditor, BestFitMaxRecordCount, CellHints, CopyCaptionsToClipboard,
  CopyRecordsToClipboard, DragDropText, DragFocusing, DragHighlighting, DragOpening, DragScrolling,
  EditAutoHeight, EditMode, FocusCellOnCycle, FocusCellOnTab, FocusFirstCellOnNewRecord, GoToNextCellOnEnter,
  HotTrack, HotTrackSelection, ImmediateEditor, IncSearch, IncSearchItem, NavigatorHints, PullFocusing,
  RecordScrollMode, ColumnHeaderHints, ColumnMergedGrouping, ExpandMasterRowOnDblClick, FixedGroups,
  ShowLockedStateImageOptions, SuppressHintOnMouseDown`.
* **Customize (≈17)**: `ColumnFiltering, ColumnGrouping, ColumnHiding, ColumnHidingOnGrouping, ColumnHorzSizing,
  ColumnMoving, ColumnSorting, ColumnsQuickCustomization(+Reordering,+Sorted,+ShowCommands,+MaxDropDownCount),
  DataRowFixing, DataRowSizing, GroupBySorting, GroupRowSizing, ColumnExpressionEditing`.
* **Data**: `Appending, CancelOnExit, Deleting, DeletingConfirmation, Editing, Inserting`.
* **Selection**: `CellMultiSelect, CellSelect, CheckBoxPosition, CheckBoxVisibility,
  ClearPersistentSelectionOnOutsideClick, HideFocusRect, HideFocusRectOnExit, HideSelection, InvertSelect,
  MultiSelect, MultiSelectMode, ShowCheckBoxesDynamically, UnselectFocusedRecordOnExit`.
* **View (≈40)**: `CellAutoHeight, CellEndEllipsis, CellTextMaxLineCount, ColumnAutoWidth, DataRowHeight,
  FixedColumn{HighlightColor,SeparatorColor,SeparatorWidth}, Footer, FooterAutoHeight, FooterMultiSummaries,
  GridLineColor, GridLines, GroupByBox, GroupByHeaderLayout, GroupFooterMultiSummaries, GroupFooters,
  GroupRowHeight, GroupRowStyle, GroupSummaryLayout, Header, HeaderAutoHeight, HeaderEndEllipsis,
  HeaderFilterButtonShowMode, HeaderHeight, HighlightFixedColumns, Indicator, IndicatorWidth,
  MergedGroupSeparator, NavigatorOffset, NoDataToDisplayInfoText, RowSeparatorColor/Width, ScrollBars,
  ShowColumnFilterButtons, ShowEditButtons, FocusRect`.
* **Filtering (≈20)**: `ColumnPopup(+Mode), ColumnExcelPopup, ColumnMRUItemsList(+Count),
  ColumnFilteredItemsList(+ShowFilteredItemsOnly), ColumnAddValueItems, CustomizeDialog, ExpressionEditing,
  FilterBox visible/position/MRU, DropDownWidth, MaxDropDownCount`.
* **Filter row**: `ApplyChanges (immediate|onEnter|delayed), ApplyInputDelay, OperatorCustomization, InfoText,
  Visible, Position`.
* **Find panel**: `DisplayMode, Behavior, Position, ApplyInputDelay, UseDelayedFind, UseExtendedSyntax,
  HighlightSearchResults, ClearFindFilterTextOnClose, ShowClear/Close/Find/Next/PreviousButton, MRU, Layout,
  SearchInGroupRows, SearchInPreview`.
* **Preview**: `Visible, Column, MaxLineCount, AutoHeight, Place (top|bottom), LeftIndent, RightIndent`.
* **Column**: `Caption, AlternateCaption, FilterCaption, Width, MinWidth, BestFitMaxWidth, Visible,
  VisibleForCustomization, GroupIndex, SortIndex, SortOrder, DateTimeGrouping, HeaderAlignment*, HeaderHint,
  HeaderGlyph, Options (22 booleans/modes), Summary (FooterKind, FooterFormat, GroupKind, GroupFormat,
  GroupFooterKind, GroupFooterFormat, SortByGroupSummary, SortByGroupFooterSummary), Properties (editor),
  RepositoryItem (shared editor), per-column styles, events`.
* **Fixed data rows**: `PinClickAction, PinSize, PinVisibility, SeparatorColor/Width` (top/bottom pinned rows).
* **Summary kinds**: `None, Sum, Min, Max, Count, Average` (+ custom via `OnSummary` event).
* **Filter operators** (`cxFilter.pas:80-572`): `Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual, Like,
  NotLike, Contains, NotContains, BeginsWith, EndsWith, Between, NotBetween, InList, NotInList, Null, NotNull`
  plus ~23 relative-date operators (`Yesterday, Today, Tomorrow, LastNDays, Last7Days, LastWeek, Last14Days,
  LastTwoWeeks, Last30Days, LastMonth, LastYear, InPast, ThisWeek/Month/Year, NextNDays, Next7Days, NextWeek,
  Next14Days, NextTwoWeeks, Next30Days, NextMonth, NextYear, InFuture`) and `CustomFunction`. Boolean tree
  `And / Or / NotAnd / NotOr`.
* **Data-controller options**: `dcoAnsiSort, dcoCaseInsensitive, dcoAssignGroupingValues, dcoSaveExpanding,
  dcoSortByDisplayText, dcoFocusTopRowAfterSorting, dcoGroupsAlwaysExpanded, dcoImmediatePost,
  dcoMultiSelectionSyncGroupWithChildren`.
* **Conditional formatting rules** (`dxSpreadSheetConditionalFormattingRules.pas`, reused by the grid):
  cell-is (comparison), expression, above/below average, top/bottom N / N%, duplicate values, unique values,
  two- and three-colour scale, data bar, icon set.
* **Editors usable in cells** (`ExpressEditors Library`): text, mask, spin, currency, calc, date, time, combo,
  image-combo, lookup-combo, check-box, check-combo, radio group, memo, rich edit, button edit, hyperlink,
  progress bar, track bar, colour combo, font combo, image, BLOB, label, MRU, shell combo, plus a
  `TcxEditRepository` of shared editors.
* **Export** (`cxGridExportLink.pas`, 7k lines): XLS, XLSX, HTML, XML, text/CSV, with styles, summaries, grouping.
* **Print** (`ExpressPrinting System`): grid link with page setup, headers/footers, preview, band/column
  fit-to-page.
* **Persistence**: `TcxPropertiesStore`, `StoreToIniFile`, view `StoreToStream`/`RestoreFromStream`, per-item
  `OnGetStoredProperties`.
* **Misc**: `IcxNavigator` navigator control, `GetHitTest` (≈25 hit-test classes), drag-and-drop of columns
  between header / group box / chooser, column header popup menu, scroll animation, skins/look-and-feel, RTL,
  accessibility (`IAccessible`), touch scrolling.

---

## 5. Proposed Neper architecture

### 5.1 Where Neper is today

| Existing | What it gives | Gap for 150k / MTG |
|---|---|---|
| `e.ui.collection` `virtual_list`, `TableSource` (`count/key/cell`), `Column`, `header_row` with sort / reorder / resize (`ColumnResize`, `HeaderDrag`), `HeaderGroup`, `TableDetail`, row actions, `TableToolbar`, `table_row_full(... conditions)` | **View-side virtualisation and header behaviours** — visible rows only, arena-built per frame, keyed selection, bulk menu, empty/loading states | *no data model*: sorting is the caller's job; no filter/group/summary; per-cell `widget.Node` build is the only cell contract (no typed painters, no editors per column kind); no bands/footer/indicator/preview/filter-row/navigator |
| `e.ui.collection` `GridSource/GridState/GridEvent` (editable cells: `Text, Checkbox, Select, Date`, `FillDown`, `Undo`, `Paste`) | **Editable grid** interaction model | cell text only; no typed value, no in-place spin/image-combo/button; no write-through events per column |
| `e.ui.sheet` (`Axis`, `Merge`, frozen rows/cols, `visible_range`, `hit_test`, `navigate`, `reveal`) | **Cell geometry / frozen panes / hit-testing** with prefix sums | spreadsheet semantics (rows are not records) |
| `e.ui.collection` `SortedTree`, `FilteredTree`, tree table | sort + filter *over a tree source* | per-node text compare; not columnar |
| `e.algo.view` (`filter_rows`, `sort_rows`, `group_rows`, summaries, `apply_view`; appdor L032) | **The semantics of a view pipeline** (nested AND/OR filters, multi-sort, grouping with "No value", summary functions, collation) | rows are `[]Field` of boxed `formula.Value`, looked up **by name with a linear scan** (`cell_of`), a merge-sort over `usize` order with a `f64` comparer callback — right semantics, wrong cost model at 150k × interactive |
| `e.algo.sort` (`radix_u32/u64`, `radix_bytes`, `counting`, `bucket`, `stable_in_place_by`, `external_merge`) | integer radix sorts | no key-extraction layer, no parallel driver |
| `e.thread.pool` (`fork_join`, work-stealing deque) | parallel loops | not yet wired to sort |
| `e.algo.page`, `pivot`, `fulltext` | paging, pivot, text index | candidates for value-list / search acceleration |

### 5.2 Module split (proposal)

```
lib/e/data/table.e        // columnar store: typed columns, null bitmaps, string dictionaries, row ids, journal
lib/e/data/tableview.e    // the "data controller": order index, filter, sort, group, summary, search, selection
lib/e/ui/datagrid.e       // the "grid": columns/bands/footer/filter-row/navigator/indicator/preview + editing,
                          //   built on e.ui.collection table primitives and e.ui.sheet geometry
lib/e/ui/datagrid_io.e    // layout/filter persistence (e.fmt.json), export (e.fmt.csv/…, xlsx), clipboard
```

Rule: `tableview` has **no UI imports** and is fixture-testable headless; `datagrid` has no sorting or
filtering logic of its own.

### 5.3 Data model (`e.data.table`)

* **Columns are typed, contiguous arrays**: `i32, i64, f64, bool(bitset), date/time(i64 µs), str, enum/i8…`.
  `Option` is a separate null bitmap per column (null sorts first, §2.4-2).
* **Strings are dictionary-encoded** per column when cardinality is low relative to rows (set/rarity/colour/
  type/artist/condition: tens to thousands of distinct), otherwise stored in an offset-array + byte-heap
  (name, rules text, flavor). Dictionary id arrays are `u16/u32`. A dictionary stores *lowercased fold* and
  *sort rank* lazily so case-insensitive equality and sort never touch strings per row.
* **Row identity**: dense `row: u32` storage index plus an optional stable `RowId: u64` column; deletions are
  tombstones with periodic compaction (the index list is rebuilt anyway).
* **Typed accessors only** in the hot API (`get_i32(col,row)`, `get_str(col,row) -> str`); a boxed `Value`
  accessor exists for generic code (export, expressions), never in sort/filter/summary loops.
* **Bulk loader**: `begin_load(capacity)`, `append_row` or column-wise `fill_column`, `end_load` → one
  recompute (§2.2 R-LOAD). A cursor adapter feeds this straight from `e.db`.
* **Change journal**: set-cell returns `(row, col, old-version)`; consumers (view) mark `Dirty{Data, Sort, Filter,
  Group, Summary}` by whether the changed column participates in each stage.
* **Memory** (estimate, to be measured): 150k rows × (≈14 numeric columns × 4–8 B + ≈10 dictionary columns ×
  2–4 B + ≈6 text columns averaging ≈40–150 B) ≈ **30–45 MB**, one allocation per column instead of
  `150k × 1` buffers plus `150k × strings` in Delphi.

### 5.4 View engine (`e.data.tableview`)

State: `order: []u32` (visible storage rows in display order), `filtered: bitset`, `sort: []SortKey`,
`group_levels: []Level`, `groups: []Group`, `summary: Summary`, `selection`, `focus`, `expansion`, `search`.

Pipeline (same staging as §3.4, with dirty flags):

1. **Filter** → `bitset` over rows. A filter is a *compiled predicate tree* (`And/Or/Not` of leaves
   `Column op Operand`). Compilation specialises per column kind:
   * dictionary column + `=`/`in`/`like` → evaluate the operator **once per distinct value** to build an
     "accepted id" bitset, then the per-row test is `accepted[id[row]]` (O(rows), branch-free; text `Like`
     becomes O(dict + rows));
   * numeric/date → typed compare loop (SIMD-able with `e.simd`);
   * text (non-dictionary) `contains` → `e.text` substring/regex scan over the heap.
   Parallel: chunk rows across `fork_join`; each worker writes a disjoint word-range of the bitset. A filter
   that is a **refinement** of the previous one (typed-ahead in the filter row; AND-ing a condition) scans only
   the previous accepted rows.
2. **Sort** → `order`. Keys are derived, never compared as text per pair:
   * numeric / bool / date → the value (flipped for signed/float order, descending by key negation);
   * dictionary string → **rank of the distinct value** under the active collation (sort the dictionary once,
     O(d log d));
   * **custom comparer (MTG's seven)** → a *key function* `fn(row) -> u64` or a *ranked domain table*
     (edition → release order, colour → WUBRG, collector number → `(number, suffix)` packed, P/T → `(kind,
     number)`, cost → `(color, cmc, cost-rank)`). These are derived columns computed **once per load or per
     distinct value**, then sorted as integers.
   Multi-key: pack up to 64 bits of leading keys (rank widths are known) and run one LSD radix
   (`algo.sort.radix_u64` over `(key, row)` pairs, stable by construction); fall back to a comparer-based
   stable merge for >64-bit composites or opaque comparers. Parallel: partition + per-chunk sort + k-way merge
   (DevExpress's 16-chunk shape), or parallel radix passes.
3. **Group** → one linear pass over `order` comparing group-key columns' dictionary ids (not strings), producing
   `Group { level, first, last, row_offset, expanded, key_path, summary_ref }`; visible-row ↔ `(group,
   offset)` via a prefix-sum of visible lengths (collapsed group = 1 row). Expansion keyed by key path so it
   survives re-sort/re-filter (§2.4-10).
4. **Summary** → typed accumulators per `(column, kind)`: `sum/count/min/max/avg` (+ distinct count via
   dictionary). Footer = over the filtered set; group = per group range; both parallelisable by chunk with a
   merge of partials. Format strings (`'Cards: #0'`, `'$#0.00'`) are a presentation concern, applied by the grid.
5. **Search** (incremental, `Locate/LocateNext`): on a dictionary column, binary-search the sorted dictionary for
   the prefix range (begins-with) or scan the dictionary (within) → set of ids; then walk `order` from the
   focused row for the first row whose id is in the set. O(d + n) worst case, usually O(distance).
6. **Value list for the column popup**: the dictionary (or the used-ids bitset of the *filtered* rows) — no row
   scan for text columns.
7. **Single-cell edit** (collection qty, foil, notes): update the column; if the edited column is not a sort/
   group/filter key, only summaries are adjusted (delta add/sub for sum/count); if it is, re-position **that
   row** by binary search in `order` (stable tie-break by row id) instead of a full re-sort, honouring the
   "don't teleport until commit" rule.

Public contract sketch (illustrative — **not compiled**; shapes follow `e.ui.collection`'s style; check
`docs/llm-neper-card.md` traps before turning any of this into source):

```
type Kind     = enum u8 { I32, I64, F64, Bool, Date, Text, Enum }
type ColumnId = u32
type SortKey  = struct { column: ColumnId, descending: bool, collation: u8, key: KeyFn /* optional */ }
type Op       = enum u8 { Eq, Ne, Lt, Le, Gt, Ge, Like, NotLike, Contains, NotContains, Begins, Ends,
                          Between, In, NotIn, Null, NotNull, DateRel /* + relative-date family */ }
type Leaf     = struct { column: ColumnId, op: Op, a: Operand, b: Operand }
type Node     = struct { kind: u8 /* And Or Not Leaf */, leaf: Leaf, first: u32, count: u32 }
type View     = struct { /* order, filtered, groups, summary … */ }

fn load_begin(t: *Table, capacity: usize) -> err
fn load_end(t: *Table) -> err                      // single recompute
fn apply(v: *View, filter: []const Node, sort: []const SortKey,
         group: []const ColumnId, summaries: []const SummarySpec, pool: *thread.Pool) -> err
fn row_count(v: *const View) -> usize              // visible rows incl. group rows
fn row_at(v: *const View, visible: usize) -> RowRef   // group header | data row(storage row)
fn locate(v: *const View, column: ColumnId, text: str, mode: SearchMode, from: usize) -> (usize, bool)
```

### 5.5 Grid view layer (`e.ui.datagrid`)

* Reuses `e.ui.collection` virtual body and header behaviours; adds what DevExpress calls
  **Bands** (fixed-left band, band headers optional), **Footer** (typed cells bound to summaries),
  **Group rows** (expand/collapse, group summary cells, group footers, "Office 11" style),
  **Filter row** (per-column editor + operator picker + delayed apply + info text), **Row indicator**
  (width, custom glyph callback, hit-test region), **Preview row** (multi-line under a record), **Navigator**
  (first/prev/next/last/page + custom buttons + info text), **No-data / loading text**, **Customization
  panel** (hidden-column list, drag back), **Quick customization** drop-down, **column header context menu**.
* **Cell contract**: a column declares a *cell kind* (`Text, Number, Currency, Bool, ImageCombo, Spin, Memo,
  Button, Hyperlink, Date, Custom`) with format and alignment; the grid draws it without creating a widget
  per cell. `Custom` is a callback `paint(ctx, rect, row_ref, state)` that can draw the default content first
  (MTG's mana-cost, legality and foil-symbol painters). **In-place editors** instantiate only for the focused
  cell.
* **Row-wide callbacks**: `row_style(row_ref) -> {fg,bg,font style}` (MTG's colour-by-rarity and conditional
  formatting), `cell_hint`, `header_hint`.
* **Records vs rows**: callbacks always receive `(storage_row, visible_index)` (§2.4-7).
* **Events** (typed, one per kind): `focused_changed`, `selection_changed`, `cell_click/double`, `value_changed
  (row, col, old, new)` (write-through, with `begin_batch` suppression), `before_delete`, `filter_changed`,
  `sort_changed`, `group_changed`, `drag_start/over/drop` (payload = card ids), `key` / `mouse` pass-through.
* **Selection** keyed by storage row id (survives sort/filter), `can_select(row) -> bool`, `select_all`,
  `invert`, shift/ctrl semantics from `collection.ListSelect`.
* **Keyboard**: the existing grid/sheet navigation (`Move`, `reveal`) plus type-ahead gated by an
  `is_incremental_searching` flag (so Space/Del/Num- keep their command meaning when not searching).
* **Accessibility**: row/column count and header metadata through `e.ui.accessibility` (already specified in
  `widget-library-proposal.md` §collection metadata).

### 5.6 Persistence, export, clipboard

* **Layout**: versioned JSON (`e.fmt.json`) of per-column `{id, band, col_index, visible, width, sort_index,
  sort_order, group_index, align}` + view flags (`footer, header, indicator, grid_lines, auto_width, group_box,
  navigator, preview{visible,column}`), keyed by view id and host (MTG keys by hostname). Unknown ids are
  ignored; new columns get defaults.
* **Filter**: serialise the predicate tree (operator names above) — a `.filter` round-trip is required because
  MTG Studio ships users' saved filters (import of DevExpress `.filter` streams is *not* a goal; offer a
  one-shot converter from MTG's own filter form fields instead).
* **Export**: CSV/Text, XML, HTML, XLSX of the *visible* columns × *filtered, sorted, grouped* rows with
  summaries (DevExpress exports what the view shows). Reuse `e.fmt.csv`; XLSX via the existing spreadsheet
  writer if present, else a minimal OOXML writer. Printing is a separate item (reports).
* **Clipboard**: selected rows as TSV with optional captions (`CopyRecordsToClipboard`,
  `CopyCaptionsToClipboard`), card-id payload for in-app drag.

---

## 6. Performance budget and how to prove it

The Delphi baseline is **measured** (§6.1); the Neper targets (§6.2) are **design goals, not measurements** —
there is no Neper benchmark yet.

**Baseline harness (added to the Delphi source, not yet compiled).** Admin ▸ Debug… ▸ tab **Grid baseline** ▸
*Compute grid baseline…* runs `TMainForm.RunGridBaseline` (`main.vcl.form.pas`) against the live card-pool view
(`btvCards`): load via `FillCardPool`, 11 sort cases (incl. the custom comparers and a 3-key sort), 4 group-by
cases + expand-all, 7 filter cases (like/equal/in-list/AND), 4 incremental-search cases (hit, miss, within),
footer recalculation, column value lists, a Variant read of all names, select-all; each case is run 3× and
reported as min / median ms, with record count, build flags, CPU count and private memory. The result is shown in
a message box and copied to the clipboard; the view's sort/group/filter state is restored. **Only available in
DEBUG builds** (the Admin menu is compiled out of release), so numbers are debug-build numbers — check
`optimization ON/OFF` in the report header. Data-controller time only; painting is not included.

### 6.1 Measured Delphi baseline (2026-10-12, 119,121 records, 24 columns)

DEBUG build, optimization OFF, range checks OFF, 16 CPUs, process private memory 278 MB. Data-controller time
only; min / median of 3 runs. (Raw output is the harness message box; paint time excluded.)

| Operation | min ms | median ms | Note |
|---|---:|---:|---|
| Load card pool (SQLite → 119k × 23 cells, incl. EndUpdate) | 1,495 | 2,195 | |
| Sort Name | 1,263 | 1,406 | string, via `OnCompare` → `UpperCase` ×2 per compare |
| Sort Cost (custom) | 436 | 442 | |
| Sort Symbol (custom, release order) | 1,036 | 1,143 | linear scan of `Editions` per compare |
| Sort Type | 1,004 | 1,031 | |
| Sort CMC (integer) | 204 | 230 | **floor for the Variant/`OnCompare` path** |
| Sort Power (custom) | 261 | 283 | |
| Sort Rarity | 1,166 | 1,210 | 7 distinct values — still ~1.2 s |
| Sort Color (custom) | 1,002 | 1,107 | |
| Sort Text (long strings) | 1,469 | 1,473 | |
| Sort Symbol, Name (3-key "Edition & Name") | 1,823 | 2,346 | |
| Sort Color, Cost, Name | 4,070 | 4,158 | |
| Group by Rarity / Color / Edition / Type | 3,810 / 3,917 / 3,600 / 5,096 | 3,849 / 4,484 / 3,647 / 7,860 | incl. (group key, Name) sort; 38,318 / 28,019 / 552 / 13,206 visible rows |
| Expand all groups (Type) | 9.7 | 11.3 | 125,419 visible rows |
| Filter Name like `*dragon*` | 2,124 | 2,126 | 9 rows |
| Filter Name = `Lightning Bolt` | 1,821 | 1,832 | 27 rows |
| Filter Text like `*destroy target creature*` | 1,340 | 1,757 | 173 rows |
| Filter Rarity = R | 1,797 | 1,885 | 42,910 rows |
| Filter CMC > 5 | 1,807 | 2,195 | 11,806 rows |
| Filter Type like `*creature*` AND CMC > 3 | 2,030 | 2,031 | **0 rows** (see below) |
| Filter Edition in (LEA, LEB) | 2,791 | 2,815 | 597 rows |
| Incremental search "Lig" / "Lightning Bolt" | 44 / 42 | 45 / 45 | found |
| Incremental search "bolt" (within) | 10 | 11 | found early |
| Incremental search "zzzz" (miss, full scan) | 140 | 144 | |
| Footer summary recalculation | 101 | 101 | |
| Column value list — Name / Edition | 1,150 / 215 | 1,167 / 229 | filter-popup open cost |
| Read all Name values via `Values[]` | 17 | 18 | ≈ 145 ns per Variant read |
| Select all | 26 | 26 | |

What the numbers say:

1. **Every operation that re-orders or re-filters costs 1–5 s at 119k rows**, and a *trivial* filter (27 rows,
   or 43k rows) costs the same ≈ 1.8–2.1 s. *(Correction, 2026-10-12: an earlier revision attributed this to
   a re-sort of the whole list. The `OnFilterRecord` experiment in §6.1.2 shows the filter is dominated by
   DevExpress's **criteria evaluation** — ≈ 7–12 µs per record — and the sort afterwards only orders the
   survivors: `DoUpdate` = `DoLoad`, `DoFilter` (pack), then `DoSort` of the packed list.)*
2. **The sort floor is the comparison path, not the algorithm.** Sorting an *integer* column takes 204 ms
   (≈ 119k × 17 compares ≈ 2 M compares → ≈ 100 ns/compare), i.e. `OnCompare` with two `Variant`s. Strings cost
   5–6× more because `DefaultCompare` upper-cases both values per comparison (`CompareStr(UpperCase(V1),
   UpperCase(V2))`, allocating two strings). Rarity (7 distinct values) taking 1.2 s is the clearest sign:
   all the time is per-compare overhead.
3. **Whether the parallel sorter is engaged is unproven.** Source says an assigned `OnCompare` does not
   switch it off (§3.5, corrected); MTG's sort options do not obviously exclude it either. Wall-clock times
   of 1.0–1.5 s for 119k strings are, however, consistent with either "single-threaded Variant compares" or
   "parallel but contending on allocations". The A/B harness (§6.1.2) settles it.
4. **Group-by ≈ 3.6–5 s** is a (group key, Name) multi-sort plus summary-group creation; the Edition case has
   only 552 groups, so the cost is sorting, not grouping.
5. **Search is cheap** (linear display-text scan, ≤ 144 ms miss) — not a bottleneck, but our dictionary
   prefix range makes begins-with O(log d).
6. **Column value list for Name takes 1.15 s** — user-visible on opening the filter drop-down; with a
   dictionary it is a copy of d strings.
7. **Memory did not change** across the reload because the buffers were already allocated; total process
   is 278 MB. The per-column estimate in §5.3 stays unvalidated — measure with a *cold* load next time.
8. **Semantics confirmed (release run):** **`foLike` is case-sensitive** in this configuration even though
   `dcoCaseInsensitive` is set (it governs sorting only): `*dragon*` → 9 rows, `*Dragon*` → 1,319;
   `*creature*` → 0, `*Creature*` → 56,095 of 119,117. MTG Studio's own filter form therefore only matches
   what users type in the exact case. Decision item (§8): match this, or make Like case-insensitive by
   default (almost certainly what users expect).

### 6.1.1 Release build (2026-10-12, 119,117 records; optimization ON, 16 CPUs)

Same harness, RELEASE build. Optimization is worth only **~10–25 %**, so §6.1's conclusions stand: the cost is
architectural (Variant compare path, re-sort after filter), not compiler settings.

| Operation | DEBUG min ms | RELEASE min ms | RELEASE median ms | Note |
|---|---:|---:|---:|---|
| Load card pool | 1,495 | 1,175 | 1,392 | |
| Sort Name | 1,263 | 1,108 | 1,453 | |
| Sort Cost (custom) | 436 | 375 | 449 | |
| Sort Symbol (custom) | 1,036 | 951 | 1,026 | |
| Sort Type | 1,004 | 984 | 1,040 | |
| Sort CMC (integer) | 204 | 239 | 293 | no gain: pure Variant overhead |
| Sort Power (custom) | 261 | 345 | 356 | |
| Sort Rarity (7 distinct values) | 1,166 | 990 | 1,082 | |
| Sort Color (custom) | 1,002 | 1,013 | 1,093 | |
| Sort Text | 1,469 | 1,720 | 1,909 | |
| Sort Symbol, Name | 1,823 | 1,619 | 1,667 | |
| Sort Color, Cost, Name | 4,070 | 3,300 | 3,613 | |
| Group by Rarity / Color / Edition / Type | 3,810 / 3,917 / 3,600 / 5,096 | 2,916 / 2,661 / 2,735 / 3,131 | 2,922 / 2,691 / 2,893 / 3,243 | |
| Expand all groups | 9.7 | 9.7 | 11.9 | |
| Filter Name like `*dragon*` | 2,124 | 1,603 | 1,944 | 9 rows |
| Filter Name like `*Dragon*` | — | 2,017 | 2,058 | 1,319 rows |
| Filter Type like `*creature*` | — | 1,898 | 1,935 | 0 rows |
| Filter Type like `*Creature*` | — | 2,613 | 2,881 | 56,095 rows |
| Filter Name = Lightning Bolt | 1,821 | 1,829 | 1,861 | 27 rows |
| Filter Text like `*destroy target creature*` | 1,340 | 1,992 | 2,072 | 173 rows |
| Filter Rarity = R | 1,797 | 1,748 | 2,007 | 42,909 rows |
| Filter CMC > 5 | 1,807 | 1,494 | 1,548 | 11,806 rows |
| Filter Type like `*Creature*` AND CMC > 3 | — | 2,349 | 2,361 | 26,209 rows |
| Filter Edition in (LEA, LEB) | 2,791 | 2,155 | 2,177 | 597 rows |
| Incremental search "Lig" / "Lightning Bolt" | 44 / 42 | 37 / 39 | 40 / 40 | |
| Incremental search "bolt" (within) / "zzzz" (miss) | 10 / 140 | 9 / 132 | 10 / 138 | |
| Footer summary recalculation | 101 | 98 | 107 | |
| Column value list — Name / Edition | 1,150 / 215 | 737 / 186 | 759 / 189 | |
| Read all Name values (Variant) | 17 | 13.5 | 14.6 | |
| Select all | 26 | 21 | 26 | |

Reading the release numbers:

* **A filter costs 1.5–2.6 s regardless of selectivity** (27 rows ≈ 1.8 s, 56,095 rows ≈ 2.6 s). *(Corrected:
  this is DevExpress criteria evaluation over all 119k records plus a sort of the survivors, not a re-sort
  of everything — see §6.1.2, where the same filter through a typed verdict array takes 81 ms.)* A filter
  that keeps more rows costs more only because more survivors are sorted.
* **The cheapest sort is 239 ms (an integer column).** The user-visible budget for "feels instant" is ~100 ms;
  *nothing* in the Delphi grid meets it except search, footer and select-all.
* **Group-by costs 2.7–3.1 s** and does not depend on the number of groups (552 vs 38k): it is the sort.
* **Variance:** median is often 5–25 % above min (GC-free, but allocator and cache effects of the Variant
  path): a flat-array design should be tighter.
* **Core usage is unconfirmed.** An earlier note here claimed the 16 cores were idle; that was inferred, not
  measured, and the source does not support it (§3.5). See §6.1.2.

### 6.1.2 Improving the Delphi v3 grid (what to try, in order)

Findings from the source (§3.4–3.5) and the baseline:

1. **Measure whether the parallel sorter is engaged** — harness section "multithreading A/B":
   `DC.MultiThreadedOptions.Sorting/Filtering := bFalse` vs `bTrue` on Name, Type, CMC, Color/Cost/Name sorts and
   the CMC filter. If OFF ≈ ON, the sorter is not parallel in practice (or the handler contends); if ON ≪ OFF
   it is already parallel and the remaining cost is per-compare work.
2. **Make the comparer cheap and thread-safe (largest likely win).** The handler runs ~2 M times per sort and
   today boxes Variants, upper-cases strings (two allocations) and scans arrays. Precompute **integer rank keys
   per record index at load** (and rebuild after delete/insert in deck/collection): rank of `UpperCase(Name)`;
   `CostKey` (colour, CMC, cost string); `SymbolKey` (edition release index, then collector-number key);
   `ColorKey`, `PowerKey`, `ToughnessKey`. The handler then becomes `CompareValue(Key[a], Key[b])`:
   no Variant, no string, no allocation, read-only arrays → safe for the parallel sorter. The harness
   experiment "rank-key comparer for Name" measures exactly this for Name; the rank build is one sort of the
   distinct names (≈ O(n log n), once per load).
3. **Do not touch `OnCompare` for plain columns' default branch** — route non-custom columns through the same
   rank trick (Type, Rarity, Text, Artist…), or the default branch's `UpperCase`×2 remains the bottleneck.
4. **Avoid the options that force the single-thread path:** keep `Options.SortByDisplayText` off on every
   column, no `dcoSortByDisplayText`, no unbound-expression columns in sort/group keys; leave
   `MultiThreadedOptions.*` at `bDefault`/`bTrue`. For *filters* on string columns the case-insensitive
   conversion makes the filter single-threaded; the scan is a small part of the 1.5–2.6 s anyway.
5. **The 1.5–2.6 s per filter is criteria evaluation, not the sort** (corrected; see the third run below):
   rank keys speed the sort of the survivors, but the evaluation needs the `OnFilterRecord` + typed-array route.
6. **Group-by** is the same sort (group key, then Name) → item 2.
7. **Reduce the data-load cost** (1.2–1.5 s): `Values[i,j]` goes through `Variant` → typed storage with
   per-cell notification suppressed by `BeginUpdate`. Cheaper: a **custom data source**
   (`TcxCustomDataSource`: own typed arrays, `GetValue` by record handle; DX asks for values lazily, and
   `IsNativeCompare` / `IsMultiThreadingSupported` / `NativeCompareFunc` let you give DX a typed comparer
   directly). Large refactor of every `Values[]` caller; consider only if 2–5 are not enough.
8. **Value list** (0.7–1.2 s on Name): `OnGetValueList`/popup builds distinct names by scanning; pre-supply
   from a distinct set computed at load, or disable `FilteringPopup` for Name (users filter via filter row).
9. **Incremental search:** fine (≤ 140 ms miss); optional `Locate` on the rank array for begins-with.
10. **Do the cheap things first:** 2 + 3 for Name/Type/Cost/Symbol/Color are ~150 lines in one unit, no UI
    change, and benefit every sort, group and filter in all three grids.

**Experiment results (DEBUG build, 119,121 records, 2026-10-12 17:54).**

| Case (min ms) | threads OFF | threads ON | OFF ÷ ON |
|---|---:|---:|---:|
| Sort Name, original handler (`UpperCase`×2) | 3,227 | 2,590 | 1.2× |
| Sort Type | 2,714 | 3,170 | 0.9× |
| Sort CMC (integer) | 1,530 | 682 | 2.2× |
| Sort Color, Cost, Name | 5,447 | 4,807 | 1.1× |
| Filter CMC > 5 | 4,526 | 5,185 | 0.9× |
| **Sort Name, rank-key handler** | **2,761** | **658** | **4.2×** |
| Sort Type, rank handler (default branch only) | 2,725 | 2,261 | 1.2× |
| Filter CMC > 5, rank handler | 3,152 | 2,593 | 1.2× |

Reading it, with the caveat first:

* **The run drifted.** The same default-threads sorts in the earlier section took Name 1,111 ms, CMC 176 ms;
  inside the A/B block "threads ON" (which should equal the default) took 2,590 / 682 ms, i.e. 2.3–3.9× slower,
  and later sections (value list 1.8 s vs 1.15 s) are slower too. Something changed over the run (allocator
  fragmentation in a long-lived debug process, background load, or CPU throttling). **Absolute numbers inside the
  A/B block are therefore not comparable to the sort section; only the adjacent OFF/ON pairs are.** The
  harness now repeats a sort before and after the block ("drift control") to quantify this.
* **Parallel sorting is real and engaged** (`dxCanUseMultiThreading = True`; the integer sort gets 2.2×).
* **The original handler barely scales (1.1–1.2×, sometimes slower).** It allocates two upper-cased strings per
  comparison, so 16 threads serialise on the memory manager. This is the "contention" hypothesis, now
  supported.
* **Removing the allocations makes the same sorter scale 4.2×** (rank-key Name: 2,761 → 658 ms), and 658 ms
  is also 1.7× faster than the original handler's *default* run (1,111 ms) even though it ran in the slower
  phase. So the fix is worth about 2–4× on Name, more on the multi-key sorts that include Name or Cost.
* **A rank handler cannot remove the Variant boxing.** `CompareByField` (`cxCustomData.pas:13915-13921`)
  builds two `Variant`s with `GetComparedValue` *before* calling `OnCompare`, whatever the handler does. Hence
  single-thread rank-key (2,761) is only ~15 % better than the original (3,227): the per-compare framework
  overhead remains, and only the parallel scaling is unlocked. To drop the Variants entirely DevExpress needs the
  native path (no `OnCompare`; or a `TcxCustomDataSource` with `NativeCompareFunc`/`IsNativeCompare`).
* **Building the rank keys at runtime costs 1.3 s (debug)** — as much as the sort it saves. Do not build them
  per load: **materialise them in the shipped card database** (`NameRank`, `CostKey`, `SymbolKey`, `ColorKey`,
  `PowerKey`, `ToughnessKey`, `CollectorKey` columns on `Cards`, computed once at DB build with the same
  ordering rules, e.g. `dense_rank() over (order by upper(Name))`). The collection already carries `CardId`, so
  its rows take their keys from the pool by `CardId` — no ranking at load or after inserts. `FillCardPool`
  just reads six more integers per row.

So the recommended v3 change is, in order: (1) key columns in the card DB + integer-key comparer (parallel
sorter then scales); (2) keep `MultiThreadedOptions` at default; (3) re-measure (§6.1.3 controls) before
deciding on the heavier custom-data-source route.

**Second run — RELEASE, optimization ON, 119,117 records (2026-10-12 18:10), with drift controls.**

Drift was small this time: sort CMC 255 ms (sort section) → 292 (control 1) → 285 (control 2); sort Name
1,576 → 1,953 → 1,840 ms. So ±15–25 % between sections; the A/B pairs below are directly comparable.

| Case (min ms) | threads OFF | threads ON | OFF ÷ ON |
|---|---:|---:|---:|
| Sort Name, original handler | 2,032 | 1,827 | 1.1× |
| Sort Type (default branch, `UpperCase`×2) | 1,714 | 1,551 | 1.1× |
| Sort CMC (integer, cheap handler) | 905 | 290 | 3.1× |
| Sort Color, Cost, Name | 4,125 | 3,493 | 1.2× |
| Filter CMC > 5 (original handler) | 4,593 | 3,813 | 1.2× |
| **Sort Name, rank-key handler** | **1,174** | **385** | **3.0×** |
| Sort Type, rank handler (not ranked) | 1,474 | 1,504 | 1.0× |
| Filter CMC > 5, rank handler | 1,781 | 1,850 | 1.0× |
| Build Name rank keys (once) | 759 | | |

What this settles:

1. **Rank keys + the parallel sorter: Name 1,827 → 385 ms (4.7×)**, and 5.3× against the original single-thread
   2,032 ms. Even single-threaded the rank handler is 1.7× faster (1,174 vs 2,032 ms): in RELEASE the
   `UpperCase` allocation *is* a large share of the cost (an earlier debug run suggested only 15 %).
2. **The parallel sorter scales whenever the handler does not allocate**: the integer column (CMC) goes
   905 → 290 ms (3.1×). Columns that still hit the `UpperCase` branch (Type, Rarity, Text, multi-key sorts that
   include them) stay at 1.0–1.2×. **Every string column needs a rank/integer key**, not only Name and Cost.
3. **The filter is a second, separate cost.** With the Name rank sort at 385 ms, a CMC > 5 filter still takes
   1.85 s, and `threads ON` is no faster than OFF (1,781 vs 1,850 ms). So ≈ 1.4 s per filter is DevExpress's
   criteria evaluation + refresh machinery on 119k rows (≈ 12 µs per record), not the sort. Candidate causes
   (unverified): per-record `Variant` build and operator dispatch, display-text comparison for text-edit
   columns, and filtering-info/selection/focus recalculation. This is the next thing to cut.
4. **Runtime rank build = 759 ms** (release) — about two sorts; ranks must be materialised in the card DB, as
   proposed, or keyed by `CardId`.
5. Searches improved in release (begins-with 27 ms, miss 94 ms) and footer summary 72 ms: not bottlenecks.

**Third run — RELEASE, quieter machine (2026-10-12 18:59), 119,117 records.** Drift controls: CMC 196 →
176 → 180 ms, Name 1,389 → 1,043 → 1,037 ms (the controls repeat well; this run was faster overall).

| Case (min ms) | threads OFF | threads ON |
|---|---:|---:|
| Sort Name, original handler | 1,192 | 1,122 |
| Sort CMC | 624 | 155 |
| **Sort Name, rank-key handler** | **611** | **204** |
| Filter CMC > 5, DevExpress criteria + rank-key sort | 973 | 1,124 |
| **Filter CMC > 5 via `OnFilterRecord` + typed verdict array + rank-key sort** | **81** | 242 |
| Build verdict array (once per criterion) | 6 | |
| Build Name rank keys (once) | 332 | |

* **Filter: 973 → 81 ms (12×); 2,734 → 81 ms (34×) against the original handler.** The same filter, same rows
  (11,806), same rank-key sort of the survivors. DevExpress criteria evaluation costs ≈ 0.9 s per 119k records.
  The typed verdict array takes 6 ms to build; the remaining 75 ms is DevExpress's refresh plus sorting the
  11.8k survivors.
* **Threads ON is slower for the event filter** (242 vs 81 ms): spawning and joining workers for a trivial
  per-record check costs more than the check. Set `MultiThreadedOptions.Filtering := bFalse` on views that
  filter through `OnFilterRecord`.
* **Name sort with rank keys: 1,122 → 204 ms (5.5×) with threads, 1,192 → 611 ms (2×) without.** Other
  string columns (Type 924 ms) are unchanged until they get keys too.
* The remaining per-operation costs in this run: Group by 1.8–2.0 s (a full (key, Name) sort, so rank keys fix it),
  load 1.45 s, Name value list 369 ms, search ≤ 70 ms.

**So the Delphi v3 plan has two independent parts**, each with a measured effect on this machine:

1. *Sorting / grouping:* integer rank keys for every sortable string/custom column, stored in the card DB
   (or keyed by `CardId`), with the allocation-free handler → 3–5× on sorts with threads on, similar on group-by.
2. *Filtering:* evaluate MTG Studio's own filter conditions (filter form, quick filters, search) natively on
   typed arrays and publish the verdict through `OnFilterRecord` → 20–30× on every filter. Keep DevExpress's own
   filter row / criteria dialog on the slow path (or translate single-column Equal/Like/In/compare criteria).

### 6.1.4 Implemented in the Delphi source (2026-10-12; built, verified and measured, see "Measured outcome")

New unit `src/mtgstudio/windows/grid_native.pas`, no database change.

**Sort keys (`TGridSortKeys`).** Per view (card pool, collection; the deck view is small and unchanged), every
sortable column gets integer ranks per record index, built lazily on the first sort of that column:

| Column kind | Ranked under exactly | Notes |
|---|---|---|
| Text (Name, Type, Rarity, Text, Flavor, Artist, Edition name, P/T, Legality, Abilities, Notes, Storage, Group) | `TCustomSort.DefaultCompare` semantics: `CompareStr(UpperCase(a), UpperCase(b))` when `dcoCaseInsensitive` and not `dcoAnsiSort`, otherwise `DefaultCompare` itself | distinct strings only are compared |
| Edition abbreviation / Set | `TCustomSort.CompareEditionRelease` | the linear `Editions` scan runs once per distinct value |
| Color, Power, Toughness, Collector number | `TCardColorHelper.Compare`, `TCardPower.Compare`, `TCardToughness.Compare`, `TCollectorNumber.Compare` | |
| Cost | `TManaCost.Compare(cmc, color, cost)` over distinct (color, CMC, cost) triples | |
| Symbol | edition release rank × collector rank | lexicographic, as the original handler |

* The existing `OnCompare` handlers of the card pool and the collection first call `TryCompare`; columns without
  keys, and the deck view, fall through to the original code. The comparers themselves are *called*, not
  re-implemented: a rank is the position of a distinct value under them, so the order is the same by construction.
* **Thread safety.** The parallel sorter calls the handler from worker threads. `TryCompare` reads read-only arrays;
  the first build is serialised by a lock (other workers wait), and replaced arrays are parked, never freed, while
  a sort may still read them. Keys follow the data: `LoadCardPool`/`LoadCollection` invalidate before the load (the
  re-sort at `EndUpdate` must not see old keys), the record count is checked on every use, and for the collection the
  data controller's `OnRecordChanged`/`OnDataChanged` are chained (inserts, deletes and edits of a key's source
  columns invalidate; quantity, price and similar edits do not).
* **Verification built in.** The baseline harness first sorts each key column with and without keys and reports
  `identical order` or the number of positions that differ.

**Native filter (`NativeFilter*`).** `TcxDataFilterCriteria` trees built by the filter form are compiled into a
snapshot of typed leaves and evaluated through `DataController.OnFilterRecord`, while DevExpress's own
`Filter.Active` is kept `False` so that it does not evaluate them again:

* Supported leaves: Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual, Like, NotLike, InList, NotInList
  (DevExpress has no separate Null kind: a null-valued Equal/NotEqual/Like/NotLike becomes its null operator and
  is left to DevExpress), combined with the criteria's And / Or / NotAnd / NotOr rules (same short-circuit). The value
  preparation of `TcxFilterCriteria.PrepareValue` (currency → double, `AnsiUpperCase` when `fcoCaseInsensitive`) and
  the Like matcher `cxLike.LikeStr` with the criteria's wildcards are the ones DevExpress uses. Numeric columns
  compared with a number (or an integer-literal string such as the form's "3") use a double compare; everything
  else uses `VarCompare`, as the operators do. InList over text uses a hash set (ordinal equality).
* **Not compiled, so DevExpress evaluates as before:** expressions, custom functions, compare-by-display-value,
  `fcoIgnoreNull`/`fcoSoftCompare`, null-valued Equal/Like, Between, Contains/Begins/Ends, date operators, and any
  item link that is not a data column.
* Wiring: the filter form's apply and its three "restore at startup" sites call `NativeFilterSetActive`; the
  main form's filter-active menu, status/persist and quick-search texts use `NativeFilterIsActive` /
  `NativeFilterIsFiltering`. A change made through DevExpress's own UI (filter row, criteria dialog, Clear, case
  option) is reconciled in `Filter.OnChanged`: the native filter steps aside, or is recompiled when only the
  criteria changed.
* Known semantic differences (negligible, stated): string equality inside the InList hash set is ordinal
  rather than the OS's linguistic compare; an `EVariantError` raised by a leaf yields "no match" instead of
  DevExpress's error dialog.

**Harness (removed).** A temporary Admin ▸ Debug ▸ *Grid baseline* page produced every number in §6.1; it, its `GRIDBASELINE` define and the experiment handlers were deleted after the measurements.

**Measured outcome (RELEASE, 119,117 rows, 16 CPUs, 2026-10-12, in-run A/B so machine drift cancels).**

| Sort (min of runs) | Original comparers | Integer keys | Gain |
|---|---|---|---|
| Name | 1555 ms | 438 ms | 3.6× |
| Color | 998 ms | 341 ms | 2.9× |
| Symbol (edition & collector no.) | 912 ms | 258 ms | 3.5× |
| Color, Cost, Name | 2253 ms | 583 ms | 3.9× |
| Cost | 520 ms | 412 ms | 1.3× |

* Order is identical to the original comparers on all 13 key columns (verification section). **Kept.**
* **The native filter was a null result and was deleted** (code and call sites; it is in the session history and
  the 2026-10-12 description above). Filter evaluation itself is cheap (≈ 40–65 ms for 119k records with no sort active), but
  with a sort active DevExpress re-sorts the *full* list on every filter change (Name filter, 27 rows kept:
  371 ms ≈ one Name sort; sorted by CMC: 179 ms ≈ one CMC sort). DevExpress's own criteria, evaluated in parallel,
  already hide their cost: native 352–507 ms against criteria 363–523 ms. Forcing `Filtering` single-threaded,
  tried first, changed nothing.
* Design consequence for Neper: the sorted order of the unfiltered table must survive a filter change (filter the
  sorted index, never re-sort), which is where the 40 ms against ≈ 360 ms comes from.
* Not addressed in Delphi: grouping (≈ 1.0–1.4 s, DevExpress's grouping pass) and the column value list
  (≈ 0.5 s for Name; a cached distinct list is the open item 4). Filter form text/number semantics are therefore
  exactly the original's.

Process private memory is still 278 MB before and after the reload (buffers already allocated); a cold-start
number remains unmeasured.

### 6.2 Design targets (vs. the baseline above)

| Operation (150k rows, 24 cols) | Target (single-thread / pool) | Why it is plausible |
|---|---|---|
| Bulk load from cursor, 23 cells/row | ≤ 250 ms | typed column append, no per-cell notifications; SQLite read dominates |
| Sort by int / dictionary-string column | ≤ 15 ms / ≤ 30 ms | radix on 32-bit rank + row id; dictionary sort is O(d log d) |
| Sort by custom-order column (cost, symbol) | ≤ 30 ms after derived key built (≤ 100 ms once) | integer sort instead of 17M × Variant comparer calls |
| 3-key sort | ≤ 60 ms | packed 64-bit key, one radix |
| Filter: `contains` on text column (heap scan) | ≤ 25 ms (≤ 10 ms on 4 workers) | linear SIMD-able scan; narrowing for typed-ahead |
| Filter: equality / in-list / like on dictionary column | ≤ 5 ms | per-dictionary evaluation then bitset lookup |
| Group by edition / colour | ≤ 8 ms after sort | one pass over dictionary ids |
| Footer + group summaries | ≤ 5 ms | typed accumulators |
| Incremental search keystroke | ≤ 1 ms typical | dictionary prefix range |
| Scroll frame (visible ~60 rows × 12 cols) | ≤ 4 ms CPU build | arena-built visible rows only |
| Memory | ≤ 60 MB | §5.3 estimate |

Proof plan: a synthetic **150k-row generator** in the MTG schema (distribution-matched: ~1k editions, 7
rarities, 6 colours, long-tailed names, 2–3 duplicate names per card, 30 % empty flavor), fixtures at 1k /
10k / 150k, and `cachegrind` instruction counts (this repo's timing rule: the host is loaded; see memory
*neper perf instruments*) plus wall-clock on an unloaded run. Parity tests compare order, group boundaries and
summaries against golden output captured from the Delphi grid on the same dataset (sort stability, null
placement, case folding, Like wildcards, custom orders).

---

## 7. MTG Studio → Neper mapping (acceptance checklist)

| MTG Studio feature | Neper element | Tier |
|---|---|---|
| 24-col card pool, 2 bands, fixed-left band | `datagrid` bands + `table` typed columns | A |
| Bulk load 120k+ rows, "Loaded in X s" | `load_begin/end` + cursor adapter | A |
| Header click / multi-sort / sort dialog / clear | `View.apply(sort)`; `SortKey` list; stable | A |
| 7 custom comparers | derived key columns (edition rank, colour rank, collector-no key, P/T key, cost key) | A |
| Group by edition/type/colour/rarity, expand/collapse all, group summary/footer | `group` + group rows, `dcoSaveExpanding`-style key path | A |
| Footer Sum/Count/Avg with formats | summaries + format strings | A |
| Filter row (delayed, operators, wildcards) | filter-row region, `Like` with `*`/`?` | A |
| Advanced filter dialog / nested AND-OR tree / saved filters | predicate tree + editor + JSON | A |
| Column-popup value lists with overrides | dictionary-backed value list + `value_list_override` hook | A |
| Incremental search + next/prev + "within" mode | `locate` | A |
| Navigator + custom Filter button | navigator region | A |
| Multi-select, can-select gate, select-all, delete selection | keyed selection | A |
| In-place edit: spin/image-combo/check/button/date/text + write-through | editors for focused cell + `value_changed` | A |
| Collection lock (runtime read-only) | `editing: bool` on the view, per-column override | A |
| Custom cell painters (mana cost, legality, expansion symbol, foil mark), row indicator painter | `Custom` paint callback + indicator callback | A |
| Row colouring + conditional-formatting manager | `row_style` + rules (cell-is, expression, top/bottom, duplicates, scales, data bar, icons) | A (rules), B (full manager UI) |
| Preview row (card text) | preview region | A |
| Customisation form + quick customisation + hide/show columns | customization panel | A |
| Layout persistence per host | JSON layout | A |
| Context menus by hit-test | `hit_test` regions → menu callback | A |
| Drag cards between grids; drag text | drag payload API | A |
| Hints (header, indicator) | hint callbacks | A |
| Grid lines / fonts / zebra / selection colours / look & feel | theme + view flags | A |
| Export TXT/XML/HTML/XLSX, copy | export layer | A |
| Best fit | `best_fit(sample_rows)` over visible rows | A |
| Vertical grid (deck properties), tree list (abilities) | reuse `PropertyGrid`, `TreeTable` | separate |

---

## 8. Risks and open questions

1. **Baseline (mostly resolved).** §6.1 (DEBUG) and §6.1.1 (RELEASE) are measured; case-sensitivity is
   confirmed (`foLike` is case-sensitive). Still unmeasured: a cold-start private-memory delta and paint/scroll
   cost. Decided: Like is case-insensitive by default (§2.4-4).
2. **Collation.** DevExpress uses upper-casing compare (`CompareStr(UpperCase)`), MTG's `TString.Compare` for
   `dcoAnsiSort`. Neper's `e.algo.view.collate_text` is a different (root-collation approximation). Decide: which
   is canonical for sort *and* for equality/filter, because parity tests depend on it.
3. **Custom comparer API.** Do we expose only key-derivation (fast, disables arbitrary comparers) or also a
   comparer callback (compat, slower, single-threaded)? Recommendation: key-derivation primary; comparer as a
   documented slow path that the engine refuses above a row threshold unless opted in.
4. **Edit-in-place + incremental re-position** (§5.4-7) is the subtlest semantics; DevExpress re-sorts on post.
   Need a fixture for "edit sort key, row moves after commit, focus follows".
5. **XLSX writer** presence in Neper not verified; confirm before promising export parity.
6. **Filter-file migration.** MTG users have `.filter` files in DevExpress stream format. Decide whether a
   converter is in scope (stream format is undocumented; reading it means parsing `TcxFilterCriteria` streams).
7. **Threading in UI frames.** Sorting 150k on the UI thread is fine at the targets; the 16-chunk parallel path
   must not hold the arena the frame uses. Decide ownership (own arena per recompute).
8. **Bootstrap limits.** Past experience in this repo: `MAX_DECLS`/arena/bootstrap-token capacities are full
   (see memory *capacities sit at their limit*, *bootstrap decls full*). A module of this size must be planned
   as several small files, built with neper-self, not the C bootstrap path.

---

## 9. Work items (enqueued as G001–G011 in `docs/work-queue.json`, 2026-10-12)

Per `AGENTS.md`, the first item in `docs/work-queue.json` is the only one to work; they are appended at the end of the
queue (appended at the end of the queue when enqueued), score 0, each with its acceptance list.

| Id | Item | Acceptance |
|---|---|---|
| G001 | `e.data.table`: typed columns, null bitmaps, string dictionary + heap, bulk load, journal | 150k × 24 load fixture; typed get/set round-trip; dictionary rank/fold correct; memory ≤ budget |
| G002 | `e.data.tableview` sort: key derivation, stable radix, multi-key, comparer slow path | stable tie-break by row; null first; case-insensitive parity; ≤ budget at 150k (cachegrind) |
| G003 | filter tree compile + evaluate (dictionary fast path, narrowing, parallel) | every operator in §4.2; `*`/`?` wildcards; **text operators case-insensitive by default, `match_case` opt-in** (`*creature*` → 56,095 on the MTG pool); nested depth 6; ≤ budget |
| G004 | group + summary engine, expansion keyed by path, group summaries/footers | group boundaries equal golden; summaries equal; sort-by-summary |
| G005 | search / locate / value list | begins-with and within; next/prev with wrap; value list = dictionary |
| G006 | `e.ui.datagrid` v1: bands, footer, group rows, filter row, navigator, indicator, preview, no-data | pixel-level offline screenshot fixtures (per `neper offline UI screenshot` recipe); keyboard/pointer fixtures |
| G007 | editing: cell kinds + editors + write-through + lock | edit-then-commit fixtures incl. sort-key edit |
| G008 | custom painters + row style + conditional formatting rules | mana-cost/legality/foil painter fixtures from MTG assets |
| G009 | layout + filter persistence, customization panel, quick customization | round-trip; unknown/new column tolerance |
| G010 | export + clipboard (+ print hand-off) | CSV/XML/HTML/XLSX of filtered+grouped view equals golden |
| G011 | MTG Studio reference app: card-pool/deck/collection views over a 150k fixture | all §7 rows exercised; benchmark table filled with measured numbers |

---

## Appendix A — MTG Studio column inventory (from source)

**Card pool** (`FillCardPool`, `mtgstudio.database.pas:1706-1728`; cells 0–22 + computed): `CardId, Favorite(bool),
Symbol(calc: set+rarity), Name, Abilities, Legality, EditionAbbreviation, ColorAbbreviation, Type,
RarityAbbreviation, Cost, PT, Text, Flavor, Artist, EditionName, CollectorNo, Power, Toughness, CMC, Mtgo3Id,
MtgIEId, MtgoId, Row(calc)`.

**Collection** (`LoadCollection`): `Id, CardId, Name, Set, Qty, Used, BuyAt, SellAt, PriceLow, MarketPrice,
PriceHigh, MarketValue(calc), SellAtValue(calc), Needed, Excess, Target, Condition, Foil, Notes, Storage,
Desired, Group, PrintType, Buy, Sell, Legality, ColorAbbreviation, Type, RarityAbbreviation, Cost, Text, Flavor,
Artist, CollectorNo, Power, Toughness, CMC, Added(datetime)` + `Symbol, PT, Row`.

**Deck** (`btvDeckCards*`): `Symbol, DeckQty, SideboardQty, EditionName, EditionAbbreviation, ColorAbbreviation,
Cost, RarityAbbreviation, PT, Type, Name, CardId, Legality, Row, Text, GeneralCardType, MtgoId, MtgieId,
Mtgo3Id, Flavor, Artist, Power, Toughness, CMC, CollectorNo`; bands `Key` (fixed left) / `Data`.

## Appendix B — DevExpress source map (23.2.6)

| Concern | File:lines |
|---|---|
| Data controller class | `cxCustomData.pas:2228-2986` |
| Controller info (index list, sorting/grouping lists) | `cxCustomData.pas:981-1179` |
| Update pipeline, sort, filter, grouping | `cxCustomData.pas:8547-8654`, `8382-8496`, `9521-9578` |
| Filter record list (multi-thread) | `cxCustomData.pas:12638-12694` |
| Compare dispatch | `cxCustomData.pas:13912-13951`, `14105-14119` |
| Search / value list | `cxCustomData.pas:11712-11767`, `4196-4236`, `3903-3960` |
| Summary | `cxCustomData.pas:7017-7300`, class `1843` |
| Multi-thread options | `cxCustomData.pas:1934-1952`, `7641` |
| Record storage, value types | `cxDataStorage.pas:59-300`, `316-523` |
| Filter operators / criteria tree | `cxFilter.pas:80-572`, `581-709`, `822` |
| Like matcher | `cxLike.pas` |
| Quick-sort + insertion sort | `dxCoreClasses.pas:711-870` |
| Parallel sort + merge, thread init | `dxThreading.pas:805-1125`, `2087-2103` |
| Lazy view records | `cxGridCustomTableView.pas:21044-21071`, `21253` |
| Table-view option classes | `cxGridTableView.pas:3374-4290` |
| Banded view | `cxGridBandedTableView.pas` |
| Export | `cxGridExportLink.pas` |
| Conditional formatting | `cxDataControllerConditionalFormatting.pas`, `dxSpreadSheetConditionalFormattingRules.pas` |
| Feature demos (behaviour reference) | `ExpressQuantumGrid\Demos\Delphi\*` — `FilterDemo`, `FindPanelDemo`, `SummaryGroupDemo`, `FixedGroupsDemo`, `UnboundModeDemo`, `CustomDrawTableViewDemo`, `ConditionalFormattingDemo`, `ViewBandedFixedDemo` |

## Appendix C — MTG Studio source map

| Concern | File |
|---|---|
| View construction (card pool, deck, collection) | `src/mtgstudio/ui/vcl/main.vcl.form.pas:1553 / 2471 / 3430` |
| Load | `…main.vcl.form.pas:1476`, `src/shared/models/database/mtgstudio.database.pas:1687` |
| Custom compare handlers | `…main.vcl.form.pas:12455`, `13067`, `11146`; `src/mtgstudio/windows/custom_sort.pas` |
| Custom draw (mana cost, legality, foil) | `src/mtgstudio/windows/custom_draw.pas` |
| Row indicator painter | `src/mtgstudio/windows/indicator_painter.pas` |
| Filter builder (tree) | `src/mtgstudio/ui/vcl/filter.vcl.form.pas:2040-2640` |
| Quick search | `…main.vcl.form.pas:9825` |
| Export | `src/mtgstudio/ui/vcl/main.vcl.data.pas:1336` |
| Grid helper (sort, customization top-most) | `src/mtgstudio/windows/quantum_grid.helper.pas` |
| Feature inventory | `docs/migration-inventory.md` §C, §D, §K |
