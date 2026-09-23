# Autocomplete

An autocomplete is a text field that suggests matching values in a list below it as people type, for free text where known values save typing: people, tags, paths, commands.

## Anatomy
1. Field: the Text field, focused, with a trailing clear button once it has text.
2. Suggestion list: a Menu surface (`surface-container`, `radius-sm`, `elevation-2`) 4 below the field's frame, as wide as the field.
3. Suggestion row: optional leading avatar or icon, the text with the matched part in weight 600 `on-surface`, optional trailing meta.
4. Active row: the keyboard's current row, `state-focus` layer.
5. Empty row: "No people match "zq"" plus an escape action when one exists.
6. Inline completion (pointer, optional): the rest of the top match after the caret, selected (`primary` 20% highlight).

## Variants and when to use
| Variant | Use for |
|---|---|
| List suggestions | People, tags, cities: the default. |
| Inline completion | Paths and commands, where the top match is usually right and Tab accepts it. |
| Grouped suggestions | Mixed kinds (people and teams): group headers in `label-medium`. |

Use a Combo box when the full list should also open on demand, a Select when only listed values are allowed, a Token field for several values, a Search bar for queries that lead to results rather than a value.

## Specs
| Part | Default (touch) | Dense (density -1) |
|---|---|---|
| Field | Text field, 56 | 40 |
| List offset | `space-1` 4 below the frame (never over it) | same |
| List | `surface-container`, `radius-sm`, `elevation-2`, padding `space-2` 8 vertical; width = field; max 6 rows visible then scroll | same, max 8 rows |
| Row | 48 (`control-lg`), `space-3` 12 sides, gap `space-3` | 36 |
| Row text | `body-medium` `on-surface`; match `on-surface` weight 600, the rest `on-surface` 400 | same |
| Leading | `nu-avatar sm` 24 or `icon-md` 24 `on-surface-variant` | 20 |
| Trailing meta | `body-small`, `on-surface-variant` | same |
| Active row | `state-focus` layer of `on-surface` | same |
| Empty text | `body-medium`, `on-surface-variant`, padding `space-3` | same |
| Inline completion | selected text, `primary` 20% background | same |

## States
- Closed: the Text field.
- Open: list below; the field keeps focus and its ring.
- Active row: `state-focus` layer; hover gives other rows `state-hover`.
- Loading suggestions (remote): a 2px linear progress along the list's top edge; keep the previous rows until new ones arrive.
- No matches: the empty row, with an action when there is a way out ("Invite by email").
- Error loading: "Couldn't load suggestions. Retry" row; typing still works.

## Behaviour
- The list opens after the first typed character (or on focus, for recent values), debounced 150ms for remote sources; it filters as people type and closes when the field is empty.
- Down/Up move the active row (the field keeps focus; the row is the active descendant); Home/End stay in the text. Enter picks the active row; with no active row, Enter keeps the typed text.
- Tab or Right (inline completion) accepts the completion; Escape closes the list, a second Escape clears the text.
- Pointer: click a row to pick it. Touch: tap; the list scrolls independently and the keyboard stays up.
- Picking fills the field with the value and closes the list; focus stays in the field.
- The list opens with `duration-medium-1` and `ease-emphasized-decelerate` (fade and 4px drop), closes with `duration-short-2`. Rows do not animate as they filter.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense; WinUI AutoSuggestBox behaviour; list max 8 rows; inline completion in path fields. |
| macOS | Dense; NSComboBox-style completion inline for paths, list below for tokens; the list has the menu's vibrancy only when the host menu uses it. |
| Linux | Dense; GtkEntryCompletion shape: list below, inline completion optional. |
| Android | Default; the list is limited so it stays above the keyboard; opening scrolls the field to the top of the window on compact. |
| iOS | Default; on compact, the list may take the space above the keyboard full width; QuickType suggestions are left to the system. |
| Web | `role="combobox"` with `aria-autocomplete="list"` (or `both`), `aria-controls`, `aria-activedescendant`; the list `role="listbox"`. |

## Accessibility
- Field role combo box (autocomplete list or both), name = label, expanded while the list shows; the list is a listbox named after the field; rows are options, the active one selected via active descendant.
- Announce the number of suggestions when it changes ("3 suggestions"), politely and debounced.
- The match emphasis is weight, not colour; the matched and unmatched parts both meet 4.5:1.
- Rows 48 on touch; the clear button has the name "Clear".
- Reduced motion: the list appears with a 100ms fade, no drop.

## Content
Rows show the value as it will be entered, plus one short meta ("Owner"). The empty row quotes the query: No people match "zq". Keep suggestion text to one line; truncate the meta first.

## e.ui today
`control.autocomplete` draws the caller's suggestions as centred Plain or Filled `button`s in a `surface` sheet with a border and elevation 2, anchored to the editor inside the frame. To reach this design:
- Anchor the list 4 below the field's frame (today it covers the frame's bottom border), full field width.
- Draw rows as start-aligned 48/36 menu rows with leading and trailing slots, match emphasis and a `state-focus` active row instead of Filled buttons.
- Use the Menu surface (`surface-container`, `radius-sm`, `elevation-2`) with a max row count and scrolling.
- Add the empty, loading and error rows, the clear button and inline completion (Tab accepts).
- Publish the field as a combo box with expanded state and suggestion-count announcements.
