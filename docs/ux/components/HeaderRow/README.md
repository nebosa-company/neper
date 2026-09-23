# HeaderRow

A header row names the columns of a Table, Data grid or Tree table and is where the person sorts, filters, resizes and reorders them.

## Anatomy
1. Container: full width, `surface-container`, a 1px `outline-variant` line below; sticky at the top of the table's viewport.
2. Header cell: the column's title in `title-small`, `on-surface-variant`; `on-surface` when the column is sorted.
3. Sort arrow: `arrow-up` (ascending) or `arrow-down` (descending), `icon-sm` 18, after the title (before it in numeric columns); a faint arrow on hover shows the column can sort.
4. Filter mark: `filter` icon, `icon-sm`, after the title while a filter is applied to the column.
5. Select-all checkbox (selectable tables): unchecked, checked or mixed, in a 52 wide first column.
6. Resize divider: a 1px `outline-variant` line at each cell's end, inset 12 top and bottom; on hover and while dragging a full-height 3px `primary` handle.
7. State layer and focus ring: `on-surface` over the cell; inset 3px ring.

## Variants and when to use
| Variant | Use for |
|---|---|
| Sortable | Columns whose order the person chooses: press to sort. |
| Static | Columns that do not sort (actions, thumbnails): no hover arrow, no pointer cursor. |
| Grouped (two tiers) | Related columns under a spanning group title ("Timing": Started, Duration); the group row is `control-md` 40 with the same styling. |

Header row only appears inside Table, Data grid and Tree table. For a list's section title use a List subheader.

## Specs
| Part | Touch | Pointer (density -1) | Dense (density -2) |
|---|---|---|---|
| Height | `control-xl` 56 | `control-lg` 48 | `control-md` 40 |
| Cell padding | `space-4` 16 sides | `space-4` 16 | `space-3` 12 |
| Title | `title-small`, `on-surface-variant`; `on-surface` when sorted | same | same |
| Arrow / filter | `icon-sm` 18, `space-1` 4 from the title; hover arrow at 50% | same | same |
| Numeric columns | right-aligned, arrow before the title | same | same |
| Fill | `surface-container` | same | same |
| Bottom line | `divider` 1px `outline-variant` | same | same |
| Divider | 1px `outline-variant`, 12 inset top and bottom | same | 8 inset |
| Resize handle | 3px `primary`, full height; a 8 wide hit area centred on the divider | same | same |
| Minimum column width | 64 (enough for the title's first word and the arrow) | 56 | 48 |
| Select-all column | 52 wide, checkbox in a 40 state-layer circle | 52 | 40, 32 circle |

## States
- Hover: `state-hover` layer over the cell; sortable cells show the faint arrow.
- Focus: inset 3px ring on the cell (the row is edge to edge).
- Pressed: `state-pressed` layer.
- Sorted: title in `on-surface`, the arrow at full strength, and the column's cells unchanged (no tint): sort is shown by the arrow and reported as a state, not by colour.
- Resizing: the handle turns `primary` and spans the whole table height while dragged; the cursor is the resize cursor.
- Reordering: the dragged cell lifts (`surface-container-highest`, `elevation-4`) and follows the pointer; a 2px `primary` line marks the landing edge.
- Filtered: the filter mark shows; the table's toolbar also names the filter, so it is not only an icon.
- Disabled sorting (while loading): no hover arrow, cells not pressable.

## Behaviour
- Press a sortable cell: sort ascending; press again: descending; a third press returns to the table's default order (if it has one). Shift+press adds a secondary sort key (desktop).
- Resize: drag the divider; double-click it to fit the column to its widest visible content. Columns never go below the minimum width.
- Reorder: drag a cell sideways past half of its neighbour's width; the first (selection) column and pinned columns do not move.
- Keyboard: the header row is part of the table's grid navigation: arrow keys move between header cells; Enter or Space sorts; Alt+Left and Alt+Right (⌥ on macOS) resize the focused column by 16; Ctrl+Shift+Left and Right move it one place. Shift+F10 or the Menu key opens the column menu (Sort ascending, Sort descending, Filter, Hide column, Pin column, Fit to content).
- The header row stays pinned while the body scrolls; it scrolls horizontally with the body.
- Motion: sort-arrow flips rotate over `duration-short-3` with `ease-standard`; reordered columns slide into place in `duration-short-4`. Reduced motion: no rotation or slide.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer 48 (Explorer-style dense tools 40); sort arrow in the cell like WinUI DataGrid; the column menu on right-click. |
| macOS | Dense 40 with `body-medium` titles in data tools (NSTableView headers are compact); sort arrow at the trailing edge; ⌥-click sorts descending directly. |
| Linux | Pointer 48; GNOME column views use this header style; KDE dense views 40. |
| Android | Touch 56; resize and reorder hidden (use the column menu from a long press); sort by tap. |
| iOS | Touch 56; sort from the column menu (long press) or a sort button in the toolbar; no resize by drag. |
| Web | 48 with a fine pointer, 56 with a coarse one; `role="columnheader"` with `aria-sort`; resize handles are `role="separator"` with `aria-valuenow`. |

## Accessibility
- The header row is role row; each cell is role columnheader, named by its title (never including the arrow), with `aria-sort` ascending, descending or none, and a description "Sortable" on sortable columns.
- Sorting announces "Sorted by Name, ascending" politely.
- Resize handles are separators with the column width as their value; keyboard resize reports the new width.
- The select-all checkbox is named "Select all builds" and reports mixed.
- Filtered columns describe the filter ("Status, filtered: Failed").
- Contrast: titles `on-surface-variant` hold 4.5:1 on `surface-container`; dividers are decorative; the resize handle and landing line in `primary` hold 3:1.
- Target: header cells are full height (48 on pointer); resize handles are 8 wide by the row height, which meets 32 only vertically, so resizing is also in the column menu and on the keyboard.
- Reduced motion as in Behaviour.

## Content
- Titles: nouns, sentence case, one or two words: "Name", "Started", "Duration". Units in the title when the cells omit them: "Size (MB)".
- No trailing punctuation; no "Sort by" in the title.
- Column menu items: "Sort ascending", "Sort descending", "Filter", "Hide column", "Pin column", "Fit to content".

## e.ui today
`collection.header_row` draws one `surface-variant` cell per column (`width - space-xs`, `control-height` tall, Label-role titles cut with "..."), a `space-xs` `border` grip after every cell, and appends " ^" or " v" to the sorted title; tap sorts, a header drag reorders, a grip drag resizes. To reach this design:
- Draw real sort arrows (`arrow-up`, `arrow-down`) and report `aria-sort`; today direction is ASCII text and reaches the tree only as Selected.
- Restyle: `surface-container` fill, `title-small` titles, 1px `outline-variant` dividers, 48 tall (56 touch, 40 dense), numeric columns right-aligned.
- Make resizing keyboard-reachable (Alt+Left/Right) and expose the grips as separators; today they are pointer-only and not in the tree.
- Draw hover, focus (inset ring), pressed, resizing and reordering feedback; today there is none.
- Key the grips from their column's key instead of `key + 64 + i`, which collides with header keys past 63 columns (`tree_table` has no cap).
- Add the select-all checkbox, filter mark and column menu.
