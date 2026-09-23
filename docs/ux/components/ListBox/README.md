# ListBox

A list box shows a list of options that stays open and lets the reader choose one, or several with checkboxes, without opening anything.

## Anatomy
1. Container: `surface-container-lowest` with a 1px `outline-variant` edge, `radius-sm`, 4px vertical padding. It is a fixed number of rows tall and scrolls.
2. Group header (optional): `label-medium`, `on-surface-variant`, 16 inset.
3. Option row: a full-width list row with a label in `body-large` (`body-medium` when dense), plus optional leading icon, supporting text and trailing meta.
4. Selection mark: a trailing check on a `secondary-container` row (single), or a leading checkbox (multiple).
5. Scroll indicator: a 4px `on-surface-variant` 50% thumb, 2px from the edge, shown while scrolling and on hover.
6. Label and message: a Field label above and a Field message below, supplied by Form field.

## Variants and when to use
| Variant | Use for |
|---|---|
| Single select | One choice from about 6 to 50 options that the reader benefits from seeing together. |
| Multi-select | Several choices from a list. Each row carries a checkbox and the message counts the choices ("2 of 5 selected"). |
| Rich rows | Options that need an icon or a second line to tell them apart. |
| Dense (32) | Inspectors and tool windows. Label only, no second line. |

Use Select when space is short and the list can hide. Use Radio buttons for two to five options. Use Checkboxes in a group for up to about seven independent options. Past 50 options, or when filtering matters, use a Multi-select list with a search field or Autocomplete. For navigation or content lists that are not a form value, use List.

## Specs
| Part | Touch | Pointer (density -1) | Dense (density -2) |
|---|---|---|---|
| Row height | 48 (`control-lg`), 64 with a second line | 40 (`control-md`) | 32 (`control-sm`) |
| Row padding | 16 sides | 16 sides | 12 sides |
| Label | `body-large` | `body-large` | `body-medium` |
| Leading icon | 24, 16 gap | 24, 16 gap | 18, 8 gap |
| Checkbox (multi) | 18 box in a 40 state circle, row padding 4 on the leading side | same | 18 in 32 |
| Selected check | 24 trailing | 18 trailing | 18 trailing |
| Container | `radius-sm` 8, 1px `outline-variant`, 4 vertical padding | same | same |
| Visible rows | caller sets `rows`, default 5, plus half a row when it scrolls (the cut-off row signals more) | same | same |
| Width | fills its Form column | same | same |

| Part | Colour role |
|---|---|
| Container | `surface-container-lowest`, edge `outline-variant`; invalid edge `error` 2px |
| Row label | `on-surface`; icon `on-surface-variant` |
| Hover, pressed | `on-surface` at `state-hover` or `state-pressed` |
| Selected row (single) | `secondary-container` / `on-secondary-container`, with a check |
| Selected row (multi) | no fill, a checked `primary` checkbox |
| Group header, meta | `on-surface-variant` |
| Disabled row | `on-surface` 38% |

## States
- Row: rest, hover, pressed, focused (the 3px ring inset in the row, because rows are edge to edge), selected, disabled.
- Container: invalid (2px `error` edge plus the Field message), disabled (every row at 38%, not focusable), empty (a centred line in `body-medium`, `on-surface-variant`, at the list's height, so the layout does not jump).
- Loading more: a 2px indeterminate progress bar under the last row.

## Behaviour
- Pointer: a click chooses a row (single) or toggles it (multi). In multi-select, Shift+click extends a range and Ctrl+click (⌘ on macOS) toggles without moving the anchor.
- Touch: a tap chooses or toggles, and a drag scrolls. Touch never starts a range.
- Keyboard: Tab enters the list at the selected row (or the first). Up and Down move focus. Single-select follows focus: moving selects. Multi-select moves focus only, and Space toggles. Home and End go to the first and last row, Page Up and Page Down move by a page, and typing jumps to the next row starting with the typed prefix (500 ms buffer). Ctrl+A selects all in multi-select. Tab leaves the list.
- Scrolling keeps the focused row fully visible, with a margin of half a row.
- Motion: the selection fill and the checkbox change over `duration-short-2` with `ease-standard`. Nothing moves.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer 40 rows (32 dense). A selected row may use a 3px `primary` leading pill instead of the check (Fluent ListView). Keep the fill. Ctrl+Space toggles in multi-select. |
| macOS | 32 rows, and selection is a full `primary` fill with `on-primary` text while the list has focus, `secondary-container` without. ⌘A selects all. Type-select is always on. |
| Linux | GTK list box: 40 rows with a trailing check. KDE: 32 rows with a fill. |
| Android | 48 rows (56 with an avatar). Radio or checkbox leading instead of the trailing check, following Material list selection. |
| iOS | Grouped inset list with a trailing checkmark for single select. Multi-select uses leading circle checks. Rows are 44pt minimum. |
| Web | `role="listbox"` with `aria-activedescendant` or roving `tabindex`, `aria-multiselectable` for multi. 40 rows with a fine pointer, 48 on touch. |

## Accessibility
- Role listbox, named by its Field label, multiselectable when multi, required and invalid from Form field. Rows are options with Selected, Disabled, position and set size ("3 of 6").
- Group headers make groups: each is a group named by its header, so the reader hears "Desktop, group".
- Focus shows on the row (inset ring), never only as a fill. Single-select announces the new selection as focus moves.
- Contrast: row text 4.5:1 on its fill, and the container edge is decorative (the list is also identified by its label).
- Targets: rows are the full width and meet 48 (touch) and 32 (pointer).
- Reduced motion: no change, because nothing animates beyond colour.

## Content
Options are parallel noun phrases in sentence case, under 40 characters, ordered logically. Keep disabled options visible with a short reason in the trailing slot ("Soon", "Needs an admin"), and never hide them if the reader might look for them. Empty state: say why it is empty and what to change: "No branches match "fix/arena"".

## e.ui today
`control.list_box` builds rows as tap regions in a clamped vertical scroll view `rows` tall, through `listed` (which `multi_select_list` shares). Rows are `control-height` tall with `space-xs` by `space-sm` padding and Body text. The selected row is filled with `selection`, and the viewport has a `border` edge and `radius-sm`. To reach this design:
- Paint focus: `listed` resolves each row's focus state and never paints it, so keyboard focus is invisible today. Draw the inset 3px ring.
- Replace the Plain look mixes with state layers, and the `selection` fill with `secondary-container` plus a trailing check.
- Size rows 48, 40 or 32 by density, with 16 side padding, and show half a row at the bottom when the list scrolls.
- Add `enabled` for the list and per row, and an `invalid` state with a 2px `error` edge.
- Add group headers, leading icons, supporting text and the empty state.
- Implement the keyboard model: arrows, Home, End, Page keys, typeahead, selection following focus in single-select, and Space, Shift and Ctrl in multi-select.
- Make it a listbox with options (not a Group with ListItems), with Selected, position and size.
