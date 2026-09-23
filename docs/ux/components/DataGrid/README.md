# DataGrid

A data grid is an editable table: records in rows, fields in columns, where the person moves cell by cell with the keyboard and edits values in place, as in a spreadsheet.

## Anatomy
1. Header row: a HeaderRow at dense metrics, sticky.
2. Row headers: a 40 wide first column of row numbers on `surface-container-low`, sticky during horizontal scroll.
3. Cells: `body-medium` values (mono for identifiers), 1px `outline-variant` vertical and horizontal grid lines.
4. Active cell: the one cell with keyboard focus, ringed with the inset 3px `focus-ring`.
5. Editor: the active cell in edit mode: `surface-container-highest` fill with a 2px `primary` inset outline and the text cursor; selects and dates show their chevron and open a menu or picker.
6. Invalid cell: a 2px `error` inset outline, an `error` icon before the value, and the message as a tooltip on hover or focus.
7. Range: selected cells filled `primary-container` with `on-primary-container` content.
8. Status bar: the error count and a summary of the selection ("2 cells selected · Sum 11,244").

## Variants and when to use
| Variant | Use for |
|---|---|
| Cell editing | Lists of configuration records (hosts, prices, translations): edit any cell in place. |
| Row editing | Records whose fields must be valid together: an edited row shows Save and Cancel at its end before it commits. |
| Sheet editing (touch) | Android, iOS and compact widths: a tapped row opens its fields in a bottom sheet or full-screen form. |

Use Table when cells are read-only. Use Property grid to edit one object's properties. Use Key-value editor for a user-built list of name-value pairs. Use a Form when the fields are few and belong to a task.

## Specs
| Part | Pointer (density -2, the default) | Pointer (density -1) | Touch (sheet editing) |
|---|---|---|---|
| Header height | `control-md` 40 | 48 | 56 |
| Row height | `control-sm` 32 | 40 | 48 |
| Cell padding | `space-3` 12 | `space-4` 16 | `space-4` |
| Grid lines | 1px `outline-variant` both ways | same | horizontal only |
| Row header | 40 wide, `label-medium` tabular, `on-surface-variant` on `surface-container-low`, right-aligned | same | none |
| Active cell | inset 3px `focus-ring` | same | row focus |
| Editor | `surface-container-highest`, inset 2px (`outline-focused`) `primary`, caret `primary` | same | Text field in a sheet |
| Invalid | inset 2px `error`, `error` icon `icon-sm` before the value; tooltip message `body-small` on `inverse-surface` | same | field's supporting text in `error` |
| Range | `primary-container` / `on-primary-container`; the active cell keeps its ring inside the range | same | none |
| Read-only cells | `on-surface-variant` text, no editor, a description "Read only" | same | same |
| Checkbox cells | 18 checkbox in a 32 circle, centred | 40 circle | 48 |
| Status bar | `control-md` 40, `body-medium` `on-surface-variant`, error count in `error` with its icon | same | none |

## States
- Cell rest, hover (`state-hover` on the cell under the pointer, row layer too), active (ring), editing (editor look), invalid, read-only, in a range; rows can also be selected (TableRow) and hovered.
- Dirty: an edited value not yet saved to the source shows a 2px `primary` bar at the cell's start edge and "Edited" in its description; the app's Save commits all.
- Saving: the edited cells show a 16 progress ring at the end; failures turn them invalid with the server's message.
- Disabled grid (while saving everything): cells read-only, the status bar says "Saving 3 changes".
- Loading, empty and error: as Table.

## Behaviour
- Navigation mode (default): arrows move the active cell; Tab and Shift+Tab move right and left and wrap to the next row; Enter moves down (Shift+Enter up); Home and End go to the row's first and last cell, Ctrl+Home and Ctrl+End to the grid's; Page Up and Page Down by a screen.
- Enter edit mode: F2 or Enter (edits keeping the value, caret at the end), typing a character (replaces the value), or a double-click. Space toggles a checkbox cell; Alt+Down opens a select or date cell's menu.
- In edit mode: arrows move the caret; Enter commits and moves down; Tab commits and moves right; Escape cancels and restores the value. Leaving the cell commits.
- Validation runs on commit; an invalid value stays in the cell (it is not reverted) with the message, and the status bar counts errors. F8 moves to the next error.
- Selection: Shift+arrows or Shift+click extend a rectangular range from the anchor; Ctrl+A (⌘A) selects all cells; clicking a row header selects the row, a column header's menu selects the column.
- Clipboard: Ctrl+C / Ctrl+V (⌘ on macOS) copy and paste ranges as tab-separated text; paste into a range repeats a single value; Delete clears editable cells in the range. Ctrl+Z (⌘Z) undoes the last edit or paste.
- Fill: dragging the range's corner handle (desktop) copies the value down.
- Touch: tapping a row opens it in a sheet with its fields; Save validates and commits.
- Motion: the active ring moves instantly; edited values cross-fade in `duration-short-2`. Reduced motion: no cross-fade.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -2 with Excel-compatible keys (F2, Enter, Tab, Ctrl+Enter fills a range, Ctrl+D fills down); Delete clears. |
| macOS | Density -2; ⌘C, ⌘V, ⌘Z; Return edits and commits; Fn+Delete clears forward; row headers optional. |
| Linux | Density -2; Ctrl shortcuts as Windows; GNOME apps rarely use grids, so prefer row editing. |
| Android | Sheet editing; the grid is read-only in place with row focus; long press selects rows. |
| iOS | Sheet editing; compact widths show a List; a tapped row pushes an edit form. |
| Web | Density -2 with a fine pointer; `role="grid"` with `aria-activedescendant` or roving focus on `gridcell`; `aria-invalid` and `aria-errormessage` on invalid cells; `aria-readonly`. |

## Accessibility
- Role grid named by the app ("Build hosts"), with full row and column counts; row headers are role rowheader, column headers columnheader.
- Each cell announces its column, value and state: "Port, 22a, invalid entry, Port must be a number from 1 to 65535"; read-only cells say "read only"; edited cells "edited".
- Entering edit mode announces "Editing"; commit and cancel are announced politely; the error count in the status bar is a polite live region.
- Every pointer action has a keyboard path (ranges, fill via Ctrl+D, row selection via Shift+Space, column via Ctrl+Space).
- Contrast: values 4.5:1 on `surface`, `surface-container-highest` and `primary-container`; grid lines are decorative; the invalid state uses an icon and a message as well as the red outline.
- Target: dense rows are 32 (the pointer minimum); touch hosts edit in sheets with 48 targets.
- Reduced motion as in Behaviour.

## Content
- Error messages say what is valid: "Port must be a number from 1 to 65535", not "Invalid value".
- Status bar: counts with nouns: "1 error", "2 cells selected · 6 hosts".
- Empty cells: blank in editable cells (typing fills them); an en dash only in read-only ones.

## e.ui today
`collection.data_grid` is `collection.table` with role grid: the source builds its cells (usually `control.text_field`s the caller keys and owns), and the row tap region and the fields are both focusable. To reach this design:
- Add cell-to-cell keyboard navigation (arrows, Tab, Enter, Home, End, Page keys) with one active cell; today no arrow keys are bound, so the role says grid but the keyboard model is a table's.
- Separate navigation and edit modes (F2, Enter, typing, Escape to cancel) instead of always-live text fields in every cell.
- Draw the active-cell ring, editor, invalid (outline, icon, message), range and dirty looks, and add the row-number column and status bar.
- Add range selection, clipboard copy and paste as tab-separated text, fill down and undo.
- Report `aria-invalid`, read-only and edited states per cell; on touch hosts edit rows in a sheet.
