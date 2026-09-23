# Select

A select picks one value from a fixed list. At rest it looks like a text field with a chevron. Open, it shows its options in a menu docked below it (pointer) or in a bottom sheet (touch).

## Anatomy
1. Field: a filled or outlined Text field box with the same label, supporting text and states. It is read-only and shows no caret.
2. Value: the chosen option's label in `body-large`. With no choice, the label rests in the box like an empty text field (never a fake value such as "Select…").
3. Trailing chevron: `chevron-down`, and `chevron-up` while open, in `on-surface-variant` (`primary` while open).
4. Options menu (pointer): a Menu of the field's width, docked 4px below, or above when there is no room.
5. Options sheet (touch): a bottom sheet with a title and one radio row per option.
6. Selected option: `secondary-container` row with a leading check (menu), or the checked radio (sheet).

## Variants and when to use
| Variant | Use for |
|---|---|
| Filled or outlined | Match the Text fields in the same form. |
| Dense (40, label above) | Tool windows, inspectors and toolbars. |
| Menu (pointer hosts) | Up to about 12 options. Past 12, add typeahead filtering at the top of the menu. |
| Sheet (touch, compact) | Any length. The sheet scrolls and gets a search field past 12 options. |

Use Radio buttons for two to five options the reader should compare at a glance. Use a Segmented button for two or three short options that switch a view. Use a List box when the list should stay visible. Use Autocomplete or a Combo box when the reader may type a value that is not in the list, or the list is long and searchable (countries, time zones). Use a Menu for actions, never a Select.

## Specs
| Part | Touch | Pointer (density -1) | Dense (density -2) |
|---|---|---|---|
| Field height | 56 | 48 | 40 |
| Field | as Text field (padding 16, `radius-xs`) | same | 12 padding |
| Chevron | `icon-md` 24 | 24 | `icon-sm` 18 |
| Menu item height | 48 | 36 (`nu-menu dense`) | 32 |
| Menu | `surface-container`, `radius-sm` 8, `elevation-2`, 8 vertical padding, 12 sides | same | same |
| Menu width | the field's width (at least 112, up to 400) | same | same |
| Menu max height | 8 items, then scrolls | same | same |
| Selected mark | leading `check` 24, `on-secondary-container` on a `secondary-container` row. Rows without a mark indent by 24 + 12 to align. | same | 18 check |
| Sheet | `surface-container-low`, top `radius-xl` 28, handle, `title-medium` title, 48 radio rows | – | – |

| Part | Colour role |
|---|---|
| Field | as Text field |
| Value | `on-surface`; resting label `on-surface-variant` |
| Chevron | `on-surface-variant`; open `primary`; disabled `on-surface` 38% |
| Menu item | `on-surface`; hover `state-hover` of `on-surface`; selected `secondary-container` / `on-secondary-container` |
| Disabled option | `on-surface` 38%, with its reason in the trailing slot |

## States
- Closed, empty: the label rests in the box.
- Closed, with a value: the label floats and the value shows.
- Hover: as Text field (a filled layer or a darker outline).
- Focused (closed): the 2px `primary` outline or indicator and a `primary` label. Arrow keys work without opening.
- Open: focused look, `chevron-up`, and the menu or sheet showing.
- Invalid: as Text field. The error message goes in the supporting text ("Choose a region").
- Disabled: as Text field, not focusable. Explain why in the supporting text.
- Disabled option: dimmed, not selectable, with a short reason ("Needs an admin").

## Behaviour
- Pointer: a click on the field opens the menu with the selected option highlighted and scrolled into view. A click on an option chooses it and closes the menu. A click outside or Escape closes the menu with no change. A press-drag-release on an option also chooses it, as native menus do.
- Keyboard (closed): Space, Enter or Alt+Down open the menu. Up and Down change the value in place without opening (Windows and Linux; macOS opens instead). Typing a letter jumps to the next option starting with it.
- Keyboard (open): Up and Down move the highlight, Home and End go to the first and last, typeahead matches a prefix typed within 500 ms, Enter or Space chooses, Escape closes and restores, and Tab chooses the highlighted option and moves on.
- Touch: a tap opens the sheet. A tap on a row chooses it and closes the sheet after `duration-short-3` so the reader sees the radio change. Dragging the sheet down or a tap on the scrim dismisses it.
- Motion: the menu opens over `duration-medium-1` with `ease-emphasized-decelerate` (scaling down from the field in y, fading in) and closes over `duration-short-4` with `ease-emphasized-accelerate`. The sheet slides up over `duration-medium-4`. With reduced motion, both cross-fade.
- The field fires its change when a choice is made, never on highlight.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense 40 with the label above in dialogs and settings. The menu opens over the field with the selected item aligned to the field (Fluent ComboBox), or docked below when space is short. Up and Down change the value while closed. |
| macOS | The pop-up button convention: the menu opens over the field with the chosen item under the pointer and a check before it. Up and Down open the menu. The menu takes the system's vibrancy material, drawn in `surface-container`. |
| Linux | GTK dropdown: a popover below with a check on the chosen row. KDE: a combo box menu over the field. Follow the running desktop. |
| Android | 56 filled field. The Material exposed dropdown menu is docked below on medium windows. On compact windows, a bottom sheet when there are more than five options, and a menu below otherwise. |
| iOS | A pull-down menu anchored to the field (UIMenu) for short lists, and a pushed list screen with a checkmark on the chosen row inside grouped settings. Use a wheel only for ordered numeric values. |
| Web | Build it as a custom combobox (button plus listbox) with this look on pointer. On touch, use native `<select>` so the platform picker appears. |

## Accessibility
- Role: combobox (button type, not editable), named by the label, with the value as its value, and expanded or collapsed. The menu is a listbox and each option is an option with Selected on the chosen one and Disabled where it applies.
- Opening moves focus to the selected option. Closing returns focus to the field.
- The disabled option's reason is its description.
- Contrast: as Text field. The selected row's `on-secondary-container` text is 4.5:1 on `secondary-container`.
- Target: the whole field. Menu items are 48 on touch and 32 or more with a pointer.
- Screen readers announce "Visibility, Private to the team, combo box, collapsed". After a change they announce only the new value.
- Reduced motion: menus and sheets cross-fade.

## Content
- Label: the setting's name as a noun: "Visibility", "Target platform".
- Options: parallel, sentence case, short (under 40 characters), ordered logically (by size, time or frequency, alphabetical only for names). No trailing punctuation.
- Don't add a "None" option unless none is a real choice. When it is, name it for what it means: "Don't sign".

## e.ui today
`control.select` renders an outlined `button` showing the chosen label, and a modal overlay (key + 1) below it with one menu-item `button` per option (key + 2 + index), the selected one filled. The caller keeps `open` and flips it through `toggle`. To reach this design:
- Draw the head as a Text field box (filled or outlined, with a label, supporting text and invalid and disabled states) with a trailing chevron. Today it cannot be told from an outlined button.
- Show the resting label with no value instead of `label` in `primary`, which reads as a value.
- Stretch menu items to the menu width, 36 or 48 tall, and mark the selected one with `secondary-container` and a check instead of a filled `primary` button.
- Size the menu to the field and dock it 4px below, with `surface-container`, `radius-sm` and `elevation-2`. Present a bottom sheet of radio rows on compact touch hosts.
- Add keyboard handling: Up and Down on the closed field, arrows, Home, End and typeahead in the menu, Escape to restore, and Tab to choose.
- Give it combobox, listbox and option semantics with expanded and selected. Today the head is a Button and the sheet a Menu of MenuItems.
- Add `enabled`, `invalid`, disabled options and `supporting` to its options.
