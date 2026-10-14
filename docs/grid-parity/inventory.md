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
| Image combo (favourite star, condition) | differs | star column drawn; the combo drop-down not recorded |
| Check box, date edit, hyperlink, label editors | untested | |
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
| Font size scale | untested | sizes small/medium/large/extra-large |
| Zebra, selection, inactive colours | matched | (selection #D5E4EE, frame #212121) |
| Row colour by card colour / rarity | app | sample `ink_of`, compared by eye |
| Conditional formatting rules manager | matched (list, delete, order) / differs (New/Edit rule wizard, stop-if-true, working copy) | CF1-rules-manager (D2433) |
| Customisation form (Column) | matched | chooser panel, close block colours |
| Multi-select, row-select, CellSelect=false | matched | M1, M2-shift-range-v3 |
| Select-ability gate (group rows) | matched | N1-group-row-click, P1 |
| Editing policy, immediate editor, Tab order | matched | E1 |
| Drag and drop of cards between grids | untested | |
| Hints (header, indicator) | matched (header) / untested (indicator) | T1, T2 |
| Context menus by hit test | matched (cell, header, group box, quick, chooser) | C1-*-v3/v5 |
| Keyboard: arrows, Page, Home/End over group rows | matched | P1-group-row-keys (D2425) |
| Keyboard: Ins/Enter/Space add, Del remove (deck) | app | |
| Mouse: wheel, hover preview | untested | wheel step and preview hover |

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
| Filter row (extra, delayed apply 1000 ms) | untested | the pool has none (F1 n/a) |
| Filter dialog, Advanced Filter, criteria tree | untested | |
| Incremental search, next/previous, prefix mark, no timeout | matched | S3, S5-search-prefix (D2427) |
| Bookmark (one per view) | matched | S3 |
| Selection API (select all, Ctrl+A, Shift+arrows) | matched | M1 |
| Layout persistence | untested | |
| Export, copy as text, print | untested | |
| Best fit | matched | A1 |

## Open differences, in the order they matter

1. The conditional formatting rules manager (dialog).
3. Filter dialog / criteria editor, filter row pixel look.
4. Image combo drop-down, check box, date edit editors.
5. Drag and drop of cards between grids; mouse wheel step.
6. Export / copy as text / print.
