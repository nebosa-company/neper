# TreeTable

A tree table is a table whose rows nest: the first column is a tree of expandable rows, and the other columns show each node's attributes, for hierarchies that people compare by value, like files with sizes or tasks with owners.

## Anatomy
1. Header row: a HeaderRow over all columns, sticky.
2. Tree column: the first column; each cell holds the indent, a twisty (`chevron-right`, rotating when open), an optional icon and the node's name.
3. Attribute columns: TableRow cells, aligned per column across all levels.
4. Rows: TableRows with 1px `outline-variant` dividers, full width (not inset like Tree items).
5. Loading row: a child row with a progress ring and "Loading" while a branch fetches.
6. Footer (optional): counts ("11 items shown · 1 selected").

## Variants and when to use
| Variant | Use for |
|---|---|
| Browsing | File browsers, dependency trees: expand, sort, open. |
| Selectable | Bulk operations across levels: a checkbox column before the tree column; checking a parent checks its loaded children and shows mixed for partial. |
| Aggregating | Totals roll up: a parent's cells show the sum of its children (sizes, estimates) in `on-surface-variant` until expanded. |

Use Tree when there is one column. Use Table when rows do not nest. Use Data grid when attribute cells are edited in place (a tree table's cells may also be editable with the Data grid's model when needed).

## Specs
| Part | Touch | Pointer (density -1) | Dense (density -2) |
|---|---|---|---|
| Header / row height | 56 / 48 | 48 / 40 | 40 / 32 |
| Cell padding | `space-4` 16 | `space-4` 16 | `space-3` 12 |
| Indent step | `space-6` 24 | `space-5` 20 | `space-5` 20 |
| Twisty | 24 box, `icon-sm` chevron, `on-surface-variant`, starting `space-2` 8 into the cell | same | same |
| Icon | `icon-sm` 18, `on-surface-variant` | same | same |
| Name | `body-medium`, ellipsised (middle for file names) | same | same |
| Attribute cells | as TableRow: numbers right-aligned, secondary values `on-surface-variant` | same | same |
| Dividers | 1px `outline-variant`, full width | same | same |
| Selected | `secondary-container` / `on-secondary-container` | same | same |
| Loading row | 18 ring in the icon slot, "Loading" in `on-surface-variant`, other cells empty | same | same |
| Tree column minimum | 200 | 200 | 160 |

## States
- Row states as TableRow: hover, focus (inset ring), pressed, selected, disabled, dragged.
- Expanded / collapsed branches; loading children; load failed (a child row "Couldn't load. Retry").
- Sorted: sorting orders siblings within each parent; the hierarchy never flattens. Folders-first ordering is an app option.
- Filtered: matches show with their ancestors; ancestors dimmed to `on-surface-variant`; branches containing matches auto-expand.
- Empty branch: an expanded branch with no children shows a child row "Empty folder" in `on-surface-variant`.

## Behaviour
- Pointer: click the twisty to toggle; click the row to select; double-click a leaf opens it, a branch toggles.
- Keyboard (row focus, one tab stop): Up and Down move; Right expands or moves to the first child; Left collapses or moves to the parent; Home and End; `*` expands all siblings; Enter opens; Space selects; typeahead on the tree column. Ctrl+Right and Ctrl+Left (⌘ on macOS) move a cell focus across columns when cells are interactive.
- Column sort, resize and reorder as HeaderRow; the tree column cannot move from first place.
- Virtualised like Virtual list: rows are built only in view, whatever the tree's size; expand state is kept by node key.
- Drag and drop: rows move between branches with the Tree's drop-target look on the target row.
- Motion: expand and collapse as Tree (`duration-medium-2`, emphasized easings), twisty rotation `duration-short-3`. Reduced motion: instant.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer density; Explorer details-view manners; numpad `+`/`-` expand and collapse; F2 renames. |
| macOS | Dense (32) as Finder's list view with disclosure triangles; ⌥-click a twisty expands all descendants; ⌘→ and ⌘← expand and collapse. |
| Linux | Pointer density; GTK column view with tree expanders; KDE Dolphin details view. |
| Android | Compact: a Tree with the most important attribute as meta; expanded widths: touch density. |
| iOS | Compact: a drill-in List or Tree; iPad: Files' list view style with outline disclosure. |
| Web | `role="treegrid"` with `aria-level`, `aria-expanded`, `aria-setsize`, `aria-posinset` on rows and `gridcell` cells. |

## Accessibility
- Role treegrid named by its title ("Project files"), with the row count of visible rows and column count.
- Rows report level, position among siblings, set size, Expanded, Selected, Busy while loading.
- Cells are tied to column headers: moving across announces "Size, 48 KB".
- Expanding announces the number of children; sorting announces "Sorted by name within each folder".
- Contrast and targets as Table and Tree; the twisty's hit area is the full row height.
- Reduced motion as in Behaviour.

## Content
- Names as stored; sizes in the largest sensible unit with one decimal above 1 MB ("4.2 MB", "48 KB"); dates relative within a week.
- Empty cells: an en dash for not-applicable values (a folder's type), blank for unknown.
- Footer: counts with nouns.

## e.ui today
`collection.tree_table` puts a `header_row` over the tree's visible rows; the first column holds the indent, the triangle mark and the node's content, the rest are built by a `CellSource`; no guides and no scroll viewport. To reach this design:
- Put the rows in a virtualised vertical viewport and remove the 512-visible-row cap inherited from `tree_rows`; today a large expanded tree is cut silently and cannot scroll.
- Cap or re-key columns: `columns` is not capped, so more than 63 make grip keys (`key + 64 + i`) collide with header keys.
- Report role treegrid with rows as rows (today rows are tree items holding groups of cells) and tie cells to their column headers.
- Adopt Tree's twisty, indent steps and keyboard model, and TableRow's dividers, padding, focus ring and selection look.
- Sort within each parent, and add loading, empty-branch and failed-load child rows.
