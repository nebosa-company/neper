# TableRow

A table row is one record in a Table, Data grid or Tree table: its cells aligned under the header's columns, read and picked as a unit.

## Anatomy
1. Container: full width, square, `surface`; a 1px `outline-variant` line below (none under the last row).
2. Cells: one per column, the column's width, `space-4` 16 side padding, content centred vertically, one line.
3. Selection cell (selectable tables): a checkbox in a 40 state-layer circle in the 52 first column.
4. Disclosure (expandable rows): a `chevron-right` in the first column that turns down when open.
5. Row actions (optional): up to two icon buttons and a More button at the end, shown on hover and focus on pointer hosts.
6. Detail row (expanded): a full-width row below on `surface-container-low`, indented to the first text column.
7. State layer: `on-surface` over the whole row; focus ring inset 3px.

## Variants and when to use
| Variant | Use for |
|---|---|
| Plain | Read-only records. |
| Selectable | Records with bulk actions: leading checkbox, selection fill. |
| Expandable | Records with detail too long for a cell (an error, a description): a disclosure and a detail row. |
| With row actions | Two or three frequent per-row actions (Rerun, Download) that would crowd a toolbar. |

Use Row for a list item with no columns. Use the Data grid's editable cell when cells change in place. Use Tree table rows when records nest.

## Specs
| Part | Touch | Pointer (density -1) | Dense (density -2) |
|---|---|---|---|
| Height | `control-lg` 48 | `control-md` 40 | `control-sm` 32 |
| Cell padding | `space-4` 16 | `space-4` 16 | `space-3` 12 |
| Text | `body-medium`, `on-surface` | same | same (`body-small` for secondary columns) |
| Secondary cells | `body-medium`, `on-surface-variant` (dates, IDs) | same | same |
| Numbers | right-aligned, tabular figures | same | same |
| Code values | `code` (mono 13/20) | same | same |
| Status | `nu-tag` with icon and word (`success`, `error`, secondary) | same | same |
| Divider | 1px `outline-variant` | same | same |
| Selection column | 52, checkbox in a 40 circle | 52 | 40, 32 circle |
| Row actions | icon buttons `control-sm` 32, `icon-sm` 18, `space-1` apart, `space-2` from the end | same | `control-xs` 24 |
| Detail row | `surface-container-low`, `body-medium`, padding `space-3` 12 by `space-4` 16, indented 68 | same | same |
| Selected | `secondary-container`, content `on-secondary-container`, checkbox checked | same | same |

## States
- Hover: `state-hover` layer over the row; row actions replace the last cell's content.
- Focus: inset 3px ring round the row (row focus mode) or round one cell (cell focus mode, Data grid); row actions show.
- Pressed: `state-pressed` layer.
- Selected: `secondary-container` fill and a checked checkbox, so selection reads by shape too.
- Expanded: disclosure points down; the detail row follows; the pair shares one hover layer.
- Dragged (reorderable tables): `surface-container-high`, `elevation-4`, `state-dragged`.
- Disabled (not actionable, e.g. queued behind a lock): content at 38%, tags at 38% opacity, checkbox disabled, still focusable for reading so the reason can be read ("Queued behind build 4122").
- Loading row: skeleton bars in each cell at the row height.

## Behaviour
- Click or tap the row runs its primary action (open the record) unless the table is in selection mode, where it toggles selection.
- Checkbox click toggles without opening. Shift+click selects a range; Ctrl-click (⌘-click) toggles one.
- Keyboard (row focus): Up and Down move; Home and End go to first and last; Space toggles selection; Enter opens; Right expands and Left collapses an expandable row; Shift+F10 opens the row's menu.
- Row actions are reachable with Tab from the focused row, and are also in the row's context menu.
- Cells truncate with an ellipsis at the end; a hover (or focus) tooltip shows the full value after `duration-medium-1`. File paths and IDs truncate in the middle.
- Motion: expand and collapse the detail row over `duration-medium-2` with `ease-emphasized-decelerate` / `ease-emphasized-accelerate`; the chevron rotates in `duration-short-3`. Reduced motion: no height animation.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer 40; row actions on hover; Fluent-style selection with a leading 3px `primary` pill in addition to the fill. |
| macOS | Dense 32 is typical (NSTableView); alternating row fills are allowed as an app option (`surface-container-lowest`); selection fill in `secondary-container`, Control-click menu. |
| Linux | Pointer 40; GTK column views; KDE dense 32. |
| Android | Touch 48; no hover actions (use a trailing More button or swipe actions); long press selects. |
| iOS | Touch 48 (44pt); tables collapse to a List of two-line rows on compact width; swipe actions for row actions. |
| Web | 40 with a fine pointer, 48 with a coarse one; `role="row"` inside `role="table"` or `grid`, `aria-selected`, `aria-expanded`. |

## Accessibility
- Role row with row index and count; cells are role cell tied to their column headers, so screen readers announce "Status, Failed" when moving across.
- States: Selected, Expanded, Disabled.
- Name: the first text column's value ("Build 4127"); the row's description is not duplicated.
- Row actions are buttons named with the row ("Rerun build 4127"); the same actions are custom actions on the row.
- Status tags carry an icon and a word; never a tinted row alone.
- Contrast: text 4.5:1 on `surface` and on `secondary-container`; secondary cells `on-surface-variant` hold 4.5:1.
- Target: 48 on touch; on pointer the row is 40 and row-action buttons 32.
- Reduced motion as in Behaviour.

## Content
- Cells hold values, not sentences: "6m 12s", "Yesterday", "main".
- Relative times up to a week, then dates; durations in the largest two units.
- Empty values: an en dash "—", never "N/A" or blank.
- Detail rows: one or two sentences with the next step as a text button: "View log".

## e.ui today
`collection.table_row` lays the caller's cells side by side at their column widths, padded `space-xs`, `extent` tall, fills `selection` when selected, and is a focusable tap region that fires `pick` with the row key. To reach this design:
- Paint the focus ring (today the row is focusable but shows no focus) and bind Up, Down, Home, End, Space and Enter; today there is no arrow-key movement between rows.
- Add hover, pressed, dragged and disabled looks; replace `selection` with `secondary-container` plus the checkbox.
- Pad cells `space-4` (16), add 1px `outline-variant` dividers, right-align numeric columns and ellipsise instead of cutting clipped text.
- Add the selection column, disclosure and detail row, and hover row actions.
- Set heights from density (48 / 40 / 32) instead of the caller's `extent`.
