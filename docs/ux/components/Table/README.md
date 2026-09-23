# Table

A table shows records as rows and their attributes as columns under a header, so people can scan, compare, sort, filter and act on many records at once.

## Anatomy
1. Container: `surface`, inside a pane or an outlined `radius-md` frame; square when it fills its pane.
2. Toolbar (optional): the table's title in `title-medium`, search, filter chips and a Columns menu; replaced by a selection bar while rows are selected.
3. Header row: a HeaderRow, sticky at the top of the viewport.
4. Body: TableRows in a vertical scroll viewport, virtualised.
5. Pinned column (optional): the first column fixed during horizontal scroll, with a shadow at the seam.
6. Footer (optional): rows per page, the range and previous and next (Pagination's table-footer variant), or a total.
7. Loading, empty and error states in place of the body.

## Variants and when to use
| Variant | Use for |
|---|---|
| Read-only | Reports, logs, results: sort, filter, open. |
| Selectable | Records with bulk actions: leading checkboxes and the selection bar. |
| Paged | Server-side sets browsed by page: the footer. Otherwise scroll continuously and show the total in the footer. |
| Wide | More columns than fit: horizontal scroll with the identifying column pinned. |

Use Data grid when cells are edited in place. Use Tree table when rows nest. Use List for one or two attributes, and GridView for visual items. On compact widths a table becomes a List of two-line rows: name as headline, the two most important attributes as supporting text, status as a trailing tag.

## Specs
| Part | Touch | Pointer (density -1) | Dense (density -2) |
|---|---|---|---|
| Header height | 56 | 48 | 40 |
| Row height | 48 | 40 | 32 |
| Cell padding | `space-4` 16 | `space-4` 16 | `space-3` 12 |
| Toolbar | `control-xl` 56, `space-4` start padding, `space-2` gaps; search is a 32 outlined field on pointer hosts | same | 48 |
| Selection bar | `secondary-container` / `on-secondary-container`, count in `title-small`, text buttons for actions (destructive in `error`) | same | same |
| Body text | `body-medium`; secondary columns `on-surface-variant`; numbers right-aligned tabular | same | same |
| Dividers | 1px `outline-variant` between rows and under the header; no vertical lines | same | same |
| Pinned seam | 1px `outline-variant` plus a 4 px `shadow` fade while scrolled | same | same |
| Scroll thumbs | overlay, as Virtual list; the horizontal thumb under the body | same | same |
| Footer | `control-lg` 48, `body-medium` `on-surface-variant`, 1px `outline-variant` above | same | 40 |
| Loading | an indeterminate linear progress under the header plus skeleton rows at row height | same | same |
| Minimum width | 360; below that use the compact list | | |

## States
- Default: header, rows, optional footer.
- Hover, focus, pressed, selected and disabled rows: see TableRow.
- Selection mode: the selection bar replaces the toolbar with the count and bulk actions; the header checkbox shows checked or mixed.
- Sorted and filtered: see HeaderRow; active filters also show as chips in the toolbar with a Clear filters action.
- Loading first page: skeleton rows; loading more or re-sorting: the linear progress under the header, rows stay.
- Empty: no data yet, an empty state with the action that creates data; empty after filtering, "No failed builds this week" with Clear filters.
- Error: a Banner in the body with Retry; the header stays.
- Scrolled horizontally: the pinned seam gains its shadow; the header scrolls with the body.

## Behaviour
- Keyboard: the table is one tab stop (then the toolbar and footer). Row focus: Up, Down, Home, End, Page Up, Page Down; Enter opens; Space selects; Ctrl+A (⌘A) selects all rows (all 1,284, not only the loaded ones, with a "Select all 1,284" confirmation in the bar); Escape clears the selection. Up from the first row enters the header.
- Pointer: click a row to open, a checkbox to select, Shift and Ctrl/⌘ modifiers for ranges and toggles; right-click for the row menu.
- Sorting and filtering keep the selection by key and keep the focused row in view if it survives the filter.
- Virtualisation: only visible rows and one screen each way are built; the scroll position is anchored to the focused row across updates.
- Live updates: changed cells cross-fade their new value in `duration-short-4`; new rows insert without moving the row under the pointer.
- Column settings (widths, order, hidden, sort) persist per table.
- Reduced motion: no cross-fades on updates; no animated insertions.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer density; WinUI DataGrid manners: column menu on right-click of the header, Ctrl+A, F2 does nothing (read-only). |
| macOS | Dense (32 rows) in data tools like Activity Monitor; optional alternating row fills; ⌘A; Space opens Quick Look when rows are files. |
| Linux | Pointer density; GTK column view manners; KDE dense. |
| Android | Compact: becomes a List; medium and up: touch density, no hover actions, column menu by long press on a header. |
| iOS | Compact: a List (UITableView style); regular width: touch density, sort from a toolbar menu. |
| Web | Density by pointer; `role="grid"` only when cells are interactive, otherwise a real `<table>`; `aria-rowcount` with the full count; sticky header via `position: sticky`. |

## Accessibility
- Role table (read-only) or grid (selectable, interactive), named by its title ("Builds"), with the full row and column counts, not the built ones.
- Header cells are column headers with sort state; the pinned column's cells are row headers, so a screen reader announces "Build 4127, Status, Failed".
- Selection announces "2 selected"; select-all announces the count; sort and filter changes announce the result count ("5 builds").
- Loading sets Busy; completion is announced once, politely.
- Keyboard as in Behaviour; all toolbar actions have shortcuts or are one Tab away.
- Contrast: body text 4.5:1, secondary `on-surface-variant` 4.5:1, dividers decorative; status as tags with icons and words.
- Target: 48 rows on touch; checkboxes keep a 48 target on touch.
- Reduced motion as in Behaviour.

## Content
- Title: the plural noun: "Builds". Selection bar: "2 selected". Empty states say what is missing and why: "No failed builds this week".
- Column titles: see HeaderRow. Cells: see TableRow.
- Footer range: "1–20 of 1,284".

## e.ui today
`collection.table` puts a `header_row` over a lazy vertical viewport of `table_row`s of one `extent`, as wide as the sum of its columns (1 to 60), with the 4px square `border` thumb. To reach this design:
- Add horizontal scrolling with a pinned first column; today the viewport scrolls vertically only and a wide table must be wrapped by the caller.
- Paint row focus and bind arrow, Home, End, Page, Space, Enter and Escape keys; today rows show no focus and have no arrow-key movement.
- Add the toolbar and selection bar, footer, loading (linear progress plus skeletons), empty and error states.
- Report role grid when selectable and the full row count; name the pinned column's cells as row headers.
- Adopt HeaderRow and TableRow restyling (dividers, padding, density heights) and replace `selection` with `secondary-container`.
- Collapse to a two-line List on compact widths.
