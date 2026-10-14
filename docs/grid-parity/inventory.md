# Grid parity inventory (G012)

One row per v3 grid feature of `docs/grid.md` section 2.3 / 2.5. **Status**: *matched* = recorded in
mtgstudio.exe and replayed in the sample or a fixture (evidence named); *differs* = recorded, a known
difference remains; *untested* = not recorded from v3 in this ledger yet; *app* = belongs to the
application, not the grid widget. Written 2026-10-14; the evidence column names the trace
(`traces.json`), the screenshot in `docs/grid-parity/`, or the decision.

## Columns and editors

| Feature | Status | Evidence |
|---|---|---|
| Text, read-only, centre/right alignment | matched | header Alignment popup, C1 menus |
| Spin editor, step arrows in the current row | matched | E1-edit-sequence, `decorate_editors`|
| Button editor (three dots) | matched | E1 |
| Memo / preview row (Card Rules) | matched | R1-card-rules (D2431); the frame round both lines of the current card is not drawn yet |
| Image combo: favourite star (two values) | matched | ST1-favourite-star (D2435) |
| Image combo: desired (drop-down: Junk, Needed, Needed Badly, Normal, Not Needed, Unassigned) | recorded in v3 (IC1-desired-dropdown-v3.png: the cell shows its value with a down-arrow button while edited, the list opens below with the current value highlighted blue, each value has a small picture); neper's `choice` editor (select with picks, dictionaries of up to 24 entries, covered by ui_datagrid section 27) has the same structure; no sample column uses it, the pool grid is read-only and the collection's dictionaries (editions) exceed 24 entries, a tap now opens the select editor in the sample (D2445, IC2-select-editor-v5.png) and and with the v3 look it is now v3's box with arrow button and plain list, current value highlighted blue (IC3-select-v3-look-v5.png, D2446); per-value pictures not built | IC1, IC2, IC3 |
| Check box, date edit, hyperlink, label editors | untested | |
| Focused row editors of the collection (Qty spin, Used spin, Buy at and Sell at buttons) | matched | ED1-collection-row-editors-v3 / v5 |
| Header image + header hint | matched | T1/T2 hint (delay measured 1045 ms vs 1101 ms, D2430) |
| Per-column alignment of header, cell, footer, group summary | matched (cell, header) / untested (footer, group summary) | A-series |
| Width, min width, best fit, best fit all | matched | A1-best-fit |
| Hidden column not offered in the chooser | untested | |
| Per-column option switches (Moving, Sorting, Grouping...) | untested | |
| Filter popup switches (MRU, multi-select) | untested | no filter drop-down in the grid |
| Display text hook, display format, row ordinal | app | sample `custom_cell`, `$#0.00` |

## View level

| Feature | Status | Evidence |
|---|---|---|
| Bands (fixed left band) | untested | `set_bands` exists, no v3 recording |
| Navigator (buttons, n of N, filter button) | matched | N2-navigator-count (D2428) |
| Footer, summary text, footer count | matched | P020 footer probes |
| Group-by box and its chips | matched | D1-group-box-drop, chip tap/drag |
| Row indicator, quick column list | matched | quick list, C1 |
| Row indicator custom-drawn warnings (deck) | untested | deck grid only |
| Preview row | untested | |
| Grid lines Both/Horizontal/Vertical/None | matched | V1-view-toggles, P017 |
| Header, indicator, auto width toggles | matched | V1 |
| Cell end ellipsis | matched | every captured grid |
| "No data" text | untested | |
| Font size scale (Options > Grids > Font Size: Small, Medium, Large, Extra Large) | matched at Extra Large (cells 1.5x, row 40.5 px, headers unchanged); Small and Large interpolated | FS1-font-size-xl-v3, FS1-font-size-v5b (D2444) |
| Options > Grids: Row Color (Against Card Color / Rarity / none), Show Foil Symbol | app | O1-options-grids-v3 |
| Options > Grids: Incremental search from start / within | matched | `search_within` in the grid; S3, S5 |
| Options > Grids: Enter key action (move to next column / next row) | untested | O1-options-grids-v3 |
| Zebra, selection, inactive colours | matched | (selection #D5E4EE, frame #212121) |
| Row colour by card colour / rarity | app | sample `ink_of`, compared by eye |
| Conditional formatting rules manager | matched (list, delete, order) / differs (New/Edit rule wizard, stop-if-true, working copy) | CF1-rules-manager (D2433) |
| Customisation form (Column) | matched | chooser panel, close block colours |
| Multi-select, row-select, CellSelect=false | matched | M1, M2-shift-range-v3 |
| Select-ability gate (group rows) | matched | N1-group-row-click, P1 |
| Editing policy, immediate editor, Tab order | matched | E1 |
| Drag and drop of cards between grids | matched (drag, ghost over the target, drop adds) / differs (v3 shows the card picture) | DD1-card-drag (D2438) |
| Hints (header, indicator) | matched (header) / untested (indicator) | T1, T2 |
| Context menus by hit test | matched (cell, header, group box, quick, chooser) | C1-*-v3/v5 |
| Keyboard: arrows, Page, Home/End over group rows | matched | P1-group-row-keys (D2425) |
| Keyboard: Ins/Enter/Space add, Del remove (deck) | app | |
| Mouse: wheel (3 rows a notch) | matched | W1-wheel (D2436) |
| Mouse: hover over a row | matched (v3 draws no hover fill on a row and the side card panel shows the current card, not the hovered one: HV1-hover-v3, 2.5 s over two rows) / app (the card panel and the optional preview tooltip) | HV1 |

## Data controller level

| Feature | Status | Evidence |
|---|---|---|
| Sort by header click, reverse | matched | S1 |
| Multi-sort Shift+click, Ctrl+click remove / clear | matched | S4-multi-sort, S6-clear-sort (D2426, D2429) |
| Sort dialog (View > Sort...) | matched (list, cycle, Clear/OK/Cancel) / differs (scroll, close box, own window) | SD1-sort-dialog (D2432) |
| Custom comparers (cost, symbol, colour, P/T, collector no.) | app | sample sorts text columns; domain keys not compared |
| Group by Edition / Type / Colour / Rarity, expand/collapse all | matched | G1, expand all command |
| Group row focus, double click, box | matched | N1 (D2424) |
| Group footers (29 px) | matched | F3-group-footer-height (D2423) |
| Group summaries and footer summaries (format strings) | untested | `Count: #`, `$#0.00` formats compared once, not exhaustively |
| Filter row (Options > Grids, Show Filter Row) | matched (white 28 px row under the header, `=` sign and flat editor per column, funnel in the indicator column, light blue while an editor has the keyboard, the twelve operators with v3's pictures, typing is not a search) / untested (the 1000 ms delay, per-type default operators, Enter in the editor) | FR1-FR7 (D2475-D2479) |
| Advanced Filter (criteria editor) | matched (structure, conditions, group operator) / differs (the group, column and operator words open lists, D2449 and D2450, v3's lists of the last two not recorded; no nesting, no Open/Save) | AF1-advanced-filter (D2434) |
| Filter Card Pool dialog (blocks / formats / editions) | app | AF1-filter-card-pool-v3 |
| Incremental search, next/previous, prefix mark, no timeout | matched | S3, S5-search-prefix (D2427) |
| Bookmark (one per view) | matched | S3 |
| Selection API (select all, Ctrl+A, Shift+arrows) | matched | M1 |
| Layout persistence (column order, widths, hidden, filter row, navigator across runs) | matched (own `cardgrid.layout` text via `save_layout` / `load_layout`, now with the Shift+click sorts, D2437) / differs (v3 also keeps grouping, expansion, view toggles) | LP1-layout-restored |
| Export: CSV, Plain Text, XML, HTML; Copy as Text (Copy All) | matched (content, via `export_string`; sample menu; Copy Selected and Copy Card Name in the fixture, D2441, clipboard not read back) | EX1 (D2439) |
| Export: PDF, Excel; Print, Page Setup, Print Preview, Designer | untested | EX1-cards-menu-v3 |
| Best fit | matched | A1 |

## Open differences, in the order they matter

1. The conditional formatting rules manager (dialog).
3. Filter dialog / criteria editor, filter row pixel look.
4. Image combo drop-down, check box, date edit editors.
6. PDF / Excel export, printing.

Verified live 2026-10-14 (screen unlocked): the Advanced Filter's Save As... wrote `cardgrid.filter` (`filter 1 / group 0 / cond ...`) and Open... restored the condition value `mox` (AF4-open-save-v5.png, D2452).

Verified live 2026-10-14: the wizard's Maximum = Number 2 on the CMC data bar makes every bar of a value of 2 or more full width (CF6-max-effect-v5.png, before and after; D2454).

Recorded 2026-10-14 (AF5-operator-list-v3.png): v3's operator list of a condition on the Favorite column holds six entries with an icon each - Equals (=), Does not equal (≠), Is blank (dotted green circle), Is not blank (filled green disc), Is any of (two green discs), Is none of (two red discs) - the current one light blue. The list depends on the column type (this is an image combo column). neper's operator popup (D2450) offers one list of eight text operators for every column; the per-type lists, the icons and the blank / any-of / none-of operators are not built.

Verified live 2026-10-14: an `Is blank` condition on Favorite filters the pool (status line `0 of 120283 cards (filtered in 6 ms)`, AF5-blank-live-v5.png, D2456). The sample's Favorite cells are false, not null, so nothing is blank; v3 treats an unset favourite as blank, which would need a null for false in the loader (application data, not the grid).

Verified live 2026-10-14: `Is none of R, G` on Color shows 89225 of 120283 cards, the complement of Is any of's 31058 (AF6-none-of-v5.png, D2457).

Verified live 2026-10-14: a two colour scale created in the wizard with the white-to-green Format... set and Applies to: CMC paints the CMC cells green (CF9-scale-live-v5.png, D2463). All five visible cells came out the same dark green, where a scale over the column's 0..max range should grade them; the scale's statistics for that column (refresh after adding a rule from the wizard) are the first suspect and are not yet looked at.
