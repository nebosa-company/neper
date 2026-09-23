# Popup

A popup is a non-modal floating surface attached to a control that shows live, related content (suggestions under a field, mention candidates, a preview) while the user keeps typing or working; it takes no focus and closes when its owner says so.

## Anatomy
1. Anchor: the control that owns it, usually a text field; it keeps focus the whole time.
2. Container: `surface-container`, `radius-sm`, `elevation-2`, 4 padding top and bottom.
3. Content: most often a list of options (dense list rows with a leading icon, the match in bold, trailing meta); or any caller content.
4. Footer row (optional): one action row after a divider ("Search file contents for …").
5. Progress (optional): a 4 linear progress along the top edge while results load.

## Variants and when to use
| Variant | Use for |
|---|---|
| Suggestion list | Autocomplete, "Go to file", tag and mention pickers: options that follow what is typed. Role Listbox. |
| Content popup | A live preview beside a control: a colour value, a link target, a hovered symbol's signature. Role Group, labelled. |

Use Flyout when the surface holds its own controls and should take focus, Popover when it needs a title and a close button, Menu for commands, Tooltip for a caption. For a fixed list of values in a form, use Select (its list is a popup with this look).

## Specs
| Part | Value |
|---|---|
| Width | the anchor's width by default; 200 min, 480 max |
| Max height | 8 rows (5 on compact), then it scrolls |
| Container | `surface-container`, `radius-sm` 8, `elevation-2` |
| Padding | `space-1` 4 top and bottom, none at the sides (rows are edge to edge) |
| Offset | 4 from the anchor |
| Row | list row, 40 (`control-md`) on pointer hosts, 48 on touch; `space-4` 16 sides; `body-medium` / `body-large` |
| Match highlight | the matched characters in weight 600 `on-surface`; never colour alone |
| Trailing meta | `label-small` in `on-surface-variant` |
| Footer row | after a `divider` in `outline-variant`; label in `primary` |
| Loading bar | linear progress, 4 tall, flush with the top edge |
| Empty and loading text | `body-medium` in `on-surface-variant`, `space-3` 12 by `space-4` 16 padding |

## States
- Closed: nothing is drawn.
- Open with results: the first result is active (highlighted) when the list is an autocomplete that Enter can accept; otherwise none is.
- Active option: `on-surface` state layer at `state-focus` (the virtual focus, since real focus stays in the field); pointer hover adds `state-hover` on the hovered row.
- Loading: shown only after 150 ms without results; keep the previous results under the bar rather than blanking the list.
- Empty: one line saying what found nothing ("No files match "ovrly""); never an empty box.
- Error: one line with the error icon and a Retry text button.

## Behaviour
- Opens when the owner decides: typically after the first character, or on Down in an empty field. Stays open while typing; the list updates in place without animation.
- Keyboard (focus stays in the field): Down and Up move the active option and wrap; Page Down and Page Up move by a page; Home and End stay in the field's text; Enter accepts the active option; Tab accepts it when the field is an autocomplete and moves on; Escape closes the popup (a second Escape clears the field).
- Pointer and touch: a press on an option accepts it; the popup does not steal focus from the field.
- It does not close on outside presses by itself; the owner closes it on blur, on accept or when the text is cleared.
- Placement: below-start of the anchor; flips above when the space below is less than 3 rows and above has more; kept 8 inside the window. It follows the anchor on scroll and closes if the anchor scrolls out of view.
- Motion: in over `duration-short-4` with `ease-emphasized-decelerate` (fade and grow 8 from the anchor edge); out over `duration-short-2` with `ease-emphasized-accelerate`. Result changes do not animate. Reduced motion: fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | 40 rows (32 in dense tool windows); the popup may take Acrylic where the host allows. |
| macOS | 32 rows in the style of the native completion list; the active row is the selection highlight; ⌘-Up/Down go to first and last. |
| Linux | 40 rows; GTK entry-completion keyboard model (Down opens, Enter accepts). |
| Android | 48 rows; the popup never covers the on-screen keyboard: it flips above or shortens; on compact it may fill the width of the window. |
| iOS | Show suggestions inline under the field or as a keyboard suggestion bar where the host provides one; the popup look is used on iPad. |
| Web | The field gets `role="combobox"` with `aria-expanded`, `aria-controls` and `aria-activedescendant`; the popup `role="listbox"`; results count announced through a polite live region. |

## Accessibility
- A suggestion popup is a Listbox of Options controlled by the field (a Combobox with Expanded); the active option is the field's active descendant.
- A content popup is a Group labelled by what it previews ("Colour preview").
- Screen readers hear the result count when it changes ("4 results"), politely, and each active option as it moves ("overlay.e, lib/e/ui, 1 of 4").
- The match highlight is also exposed as text, not only weight; nothing depends on colour.
- Contrast: row text 4.5:1 on `surface-container`; meta `on-surface-variant` 4.5:1.
- Targets: rows are full-width, 40 or 48 tall.
- Reduced motion: fade only.

## Content
- Show the thing, not a sentence: file names, people's handles with their name as meta.
- Empty: "No files match "ovrly"" quoting what was typed; loading: "Searching 1,204 files…" with a real count when known.
- Footer action as a verb phrase with the query: "Search file contents for "overl"".

## e.ui today
`overlay.popup` draws the caller's `content` on a bordered `surface` box with `radius-sm` and `elevation-2` at `placement` against `anchor`, 4 down, non-modal; its tree node is an unnamed Group. To reach this design:
- Repaint as `surface-container`, no border, 4 vertical padding with edge-to-edge rows; size to the anchor's width by default.
- Take a `label` and a `role` (Listbox or Group); today the Group is unnamed and the function takes no name.
- Add active-descendant support so the anchor field keeps focus while arrows move the highlight, and wire Enter, Tab and Escape through the owner.
- Flip above when the space below is short and close when the anchor scrolls away; today it is only clamped inside the window.
- Provide the loading, empty and error rows as parts instead of leaving them to each caller.
