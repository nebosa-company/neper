# ComboBox

A combo box is a text field with a button that opens a list of preset values, where people either pick a preset or type their own, for values like zoom levels, font sizes and branch names.

## Anatomy
1. Field: the Text field, outlined or filled, holding the current value.
2. Chevron button: a 40 icon button inside the field's end with `chevron-down`; it turns 180° while the list is open.
3. List: a Menu surface 4 below the frame, as wide as the field.
4. Option row: the preset's text; the current value in `secondary-container` with a trailing `check`.
5. Active row: `state-focus` layer (keyboard position).
6. Separators and group headers (optional) for kinds of preset ("Fit to width").

## Variants and when to use
| Variant | Typing | Use for |
|---|---|---|
| Editable (default) | any value; the list filters while typing | Zoom, font size, a branch name. |
| Editable, strict | typing filters and must match an option on commit | Long known lists (time zones, languages) where typing is faster than scrolling. |

Use a Select (Picker) when typing is not allowed, an Autocomplete when there is no list to open on demand, and a Spin box for plain numbers without presets.

## Specs
| Part | Default (touch) | Dense (density -1) |
|---|---|---|
| Field height | `control-xl` 56 | `control-md` 40 |
| Chevron button | `control-md` 40 icon button, `icon-md` 24, `on-surface-variant`; field end padding `space-1` | `control-sm` 32, `icon-sm` 18 |
| List | `surface-container`, `radius-sm`, `elevation-2`, `space-2` 8 vertical padding; `space-1` below the frame; max 6 rows then scroll | max 10 rows |
| Row | `control-lg` 48, `space-3` 12 sides, `body-medium` | 36 |
| Selected row | `secondary-container` / `on-secondary-container`, trailing `check` 24 | same |
| Active row | `state-focus` layer | same |
| Separator | 1px `outline-variant`, `space-2` 8 vertical margin | same |
| Empty note | `body-medium` `on-surface-variant`, padding `space-3` | padding `space-2` `space-3` |

## States
- Closed: field rest, hover and focus are the Text field's; the chevron has its own hover and pressed layers.
- Open: chevron rotated; field keeps focus (the ring stays on the field).
- Filtering: rows that match remain; the current value stays checked if visible.
- No match (editable): a note saying the typed value will be kept ("No preset. Enter keeps 110%").
- Invalid (strict, no match on commit): the field's error look and message "Choose a time zone from the list".
- Disabled: the Text field's disabled look; chevron 38%.

## Behaviour
- Clicking the chevron, Alt+Down, or F4 opens the full list with the current value scrolled into view and active. Typing opens a filtered list.
- Down/Up move the active row; Enter picks it; Escape closes without changing the text; Alt+Up closes and picks the active row.
- With the list closed, Up/Down step to the previous or next preset (Windows and Linux convention).
- Pointer: clicking the field places the caret, it does not open the list (clicking the chevron does). Touch: tapping the chevron opens; tapping the field opens the keyboard.
- Commit on Enter or blur; the typed text is the value in editable mode.
- The list opens with `duration-medium-1` and `ease-emphasized-decelerate`; the chevron turns with `ease-standard` `duration-short-3`; closing takes `duration-short-2`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense; WinUI editable ComboBox: F4 and Alt+Down open, Up/Down step while closed. |
| macOS | Dense; NSComboBox: the chevron is a separate end button, the list is a pop-up below; no Up/Down stepping while closed. |
| Linux | Dense; GtkComboBox with entry; Up/Down step while closed on KDE. |
| Android | Default; Material exposed dropdown menu with editable text; the list stays above the keyboard. |
| iOS | Default; the chevron opens a UIMenu (short lists) or a sheet of options (long lists); typing uses the field alone. |
| Web | `role="combobox"` with `aria-autocomplete="list"`, the chevron a `button` with `aria-label` and `aria-expanded`, the list a `listbox`. |

## Accessibility
- Field role combo box, name = label, value = text, expanded state, active descendant = active row. Chevron: button named "Show <label> presets" / "Hide ...", excluded from the Tab order (Alt+Down does the same).
- List: listbox named by the label; rows are options, the current value selected.
- Announce "5 presets" on open, the filtered count while typing (debounced).
- Rows and chevron 48 on touch; the chevron alone is 40 visual.
- Reduced motion: the list fades in 100ms; the chevron swaps without turning.

## Content
Presets are written exactly as the value would be typed ("100%", "4 spaces"). Special presets are verbs or named modes in sentence case ("Fit to width"). Keep the list under 15 items; use Strict with filtering for longer lists.

## e.ui today
`control.combo_box` is the autocomplete plus an Outlined chevron pressable (`radius-md`, a 12px triangle) beside the field, whose row centres the chevron against the label and frame together so it sits low; the mark always points down, and the chevron is named with the English literal "Choices". To reach this design:
- Move the chevron inside the field's end as a 40 icon button with `chevron-down` that rotates while open.
- Use the Menu surface and rows with a checked current value, active-row layer, separators, max rows and scrolling; anchor the list below the frame.
- Add F4/Alt+Down/Alt+Up, Up/Down stepping while closed, and the strict mode with its error.
- Name the chevron "Show <label> presets" and localise it.
- Keep typed values that match no preset and show the "Enter keeps" note.
