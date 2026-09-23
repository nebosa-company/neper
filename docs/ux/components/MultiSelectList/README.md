# MultiSelectList

A multi-select list lets people choose any number of options from a visible, scrollable list, with a count and select-all bar, for targets, files, members and other sets too long for checkboxes in a form.

## Anatomy
1. Container: `surface`, 1px `outline-variant`, `radius-md`, clipped.
2. Count bar: `surface-container-low`, 48 tall, "3 of 6 selected" in `title-small`, and a Select all / Clear text button.
3. Row: a List item; touch rows lead with a checkbox in a 40 cell, pointer rows may omit it.
4. Selected row: `secondary-container` / `on-secondary-container`, checkbox checked.
5. Optional leading icon, supporting line, trailing meta.
6. State layer and inset focus ring per row.

## Variants and when to use
| Variant | Selection shown by | Use for |
|---|---|---|
| Checkbox list (default) | checkbox and row fill | Touch hosts, and any list where people may not know modifier keys. |
| Fill list (pointer) | row fill; Ctrl/Shift/⌘ extend | File lists and tool UIs on desktop; checkboxes appear on hover or in selection mode. |
| Selection mode (touch) | long-press enters it; the app bar becomes a contextual bar with the count | Lists whose rows otherwise open something. |

Use Checkboxes for up to 7 options in a form, a Token field when options are open-ended, a Picker for a single choice, and a Data grid when rows have many columns.

## Specs
| Part | Default (touch) | Dense (density -1) |
|---|---|---|
| Row height | `control-xl` 56 (72 with supporting line) | `control-md` 40 |
| Row padding | `space-2` 8 start (checkbox cell), `space-6` 24 end | `space-4` 16 start |
| Checkbox | 18 box in a 40 cell, `on-surface-variant`; checked `primary` | 18 box, cell 32, or none |
| Row text | `body-large` `on-surface`; supporting `body-medium` `on-surface-variant` | `body-medium`; trailing meta `label-small` |
| Selected row | `secondary-container` / `on-secondary-container` | same |
| Count bar | 48, `surface-container-low`, `title-small`, bottom 1px `outline-variant` | 40 |
| Container | `radius-md`, 1px `outline-variant`; height = the caller's visible rows | same |
| Focus ring | inset 3px | same |

## States
- Row hover `state-hover`, pressed `state-pressed`, focus `state-focus` plus the inset ring; the focused row and the selected rows are independent.
- Selected: fill and checked box; never fill alone on touch.
- Disabled row: `on-surface` 38%, not selectable, with the reason as the supporting line.
- Mixed select-all: the bar's action reads "Select all" until everything is selected, then "Clear".
- Empty (filtered to nothing): an Empty state inside the container ("No targets match "arm"").
- Loading: Skeleton rows.

## Behaviour
- Touch: tapping a row toggles it. Pointer, checkbox list: clicking toggles. Pointer, fill list: click selects only that row; Ctrl (⌘ on macOS) click toggles; Shift click selects the range from the anchor; drag in empty space marquee-selects.
- Keyboard: Up/Down move focus; Space toggles the focused row; Shift+Up/Down extends; Ctrl+Up/Down moves focus without selecting (fill list); Ctrl/⌘+A selects all; Escape clears the selection (fill list); Home/End and Page Up/Down move focus; typeahead jumps.
- The count bar updates live. Selection survives scrolling and filtering; filtered-out selections still count ("3 of 6 selected, 1 hidden").
- Toggling a checkbox animates the tick (`duration-short-2`); the fill changes with `ease-standard` `duration-short-3`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense fill list; Ctrl and Shift modifiers; checkboxes on hover (WinUI ListView multiple mode). |
| macOS | Dense fill list; ⌘ and Shift modifiers; selection fill uses the accent when the list is focused, grey when not (map to `secondary-container` and `surface-container-highest`). |
| Linux | Dense; Ctrl and Shift; GNOME boxed lists use trailing checkboxes (allowed). |
| Android | Checkbox list, or long-press selection mode with a contextual app bar. |
| iOS | Edit mode: circular checkmarks at the start; a toolbar with Select all; swipe with two fingers to select a range. |
| Web | `role="listbox" aria-multiselectable="true"` with options, or a grid for rich rows; checkbox list on touch. |

## Accessibility
- Role listbox, multiselectable, named by the caller ("Build targets"), with the row count. Rows are options with selected state and position ("3 of 6").
- Announce the count when it changes ("3 selected"). The count bar is a status region.
- The checkbox is part of the option, not a separate node.
- Rows 56 on touch, 40 with a pointer. Selected fill meets 3:1 against `surface`; the check mark carries the state for colour-blind users.
- Reduced motion: no tick animation; selection changes instantly.

## Content
Rows use the item's name as people know it. The bar says the count and total ("3 of 6 selected"). Disabled rows explain why ("Needs a macOS runner"). Bar actions are verbs: "Select all", "Clear".

## e.ui today
`control.multi_select_list` builds `list_box` rows `control-height` tall with Body text, selected rows filled with `selection`, inside a bordered `radius-sm` viewport that clips; rows overflow the border by twice `border-regular`, losing their right padding, and no list-level multiselect state reaches the tree. To reach this design:
- Size rows to the viewport's inner width (inside the border), 56/40 tall, with the checkbox cell on touch.
- Draw selected rows in `secondary-container` with a checked box; add hover, pressed and inset focus looks.
- Add the count bar with Select all / Clear, the disabled-row reason, and empty and loading states.
- Add modifier selection (Ctrl/⌘, Shift, range, marquee), Space to toggle, Ctrl+A and Escape.
- Publish the list as multiselectable with the selected count.
