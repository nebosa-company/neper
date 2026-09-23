# Chip

A chip is a compact element for a contextual action, a filter, an entered value or a suggestion, usually shown in a set.

## Anatomy
1. Container: 32 tall, `radius-sm` 8, 1 px `outline` edge (none when selected or elevated).
2. Label: `label-large`, one line.
3. Optional leading element: an 18 icon in `primary`, a 24 avatar, or the check of a selected filter.
4. Optional trailing element: an 18 chevron (menu filter) or a 24 remove button (input).
5. State layer and focus ring.

## Variants and when to use
| Kind | Look | Use for |
|---|---|---|
| Assist | outlined (or elevated), leading `primary` icon | A smart, contextual action: "Open in terminal", "Share build". |
| Filter | outlined; selected `secondary-container` with a check | Narrowing a list or search: several can be on. A menu filter shows its value and a chevron. |
| Input | outlined, leading avatar or icon, trailing remove | A value the person entered or picked: recipients, paths, tags in a Token field. |
| Suggestion | outlined, label only | Generated next steps or replies: "Retry failed tests". |

Use Segmented button when exactly one of 2-5 options must be chosen. Use Button for a primary or fixed action. Use a status label (tag, see Badge) for a read-only state. Use Checkbox in a form.

## Specs
| Part | Default | Dense (density -2) |
|---|---|---|
| Height | `control-sm` 32 | `control-xs` 24 |
| Side padding | `space-4` 16; `space-2` 8 on a side with an icon, avatar or remove | `space-2` 8 |
| Label | `label-large` 14/20 | 12/16 |
| Leading icon | `icon-sm` 18, `primary` (`on-secondary-container` when selected) | 16 |
| Avatar | 24, 4 px from the edge | 18 |
| Trailing remove | 24 circle round an 18 `close`, `on-surface-variant`; its own target | 18 |
| Gap | icon to label `space-2` 8; between chips `space-2` 8 | `space-1` 4 |
| Radius | `radius-sm` 8 | `radius-xs` 4 |
| Edge | 1 px `outline` (rest), none selected or elevated | same |
| Selected | `secondary-container`, `on-secondary-container` | same |
| Elevated | `surface-container-low`, `elevation-1` | not used |
| Target | pads to `target-touch` 48 on touch hosts, 32 with a pointer | 32 |

## States
- Hover: state layer at `state-hover` in the label colour.
- Focus: `state-focus` layer and the ring, 3 px `focus-ring`, 2 px outside.
- Pressed: `state-pressed`; ripple on touch.
- Selected (filter): container and check; the check makes the state visible without colour. The check grows in and the label shifts over `duration-short-3` with `ease-standard`.
- Dragged (input chips in a token field, reorderable sets): `state-dragged`, `surface-container-high`, `elevation-4`, no edge.
- Invalid (input): `error` edge and label with the `error` icon leading; the reason in the field's support text.
- Disabled: label and icon 38% `on-surface`, edge 12%, not focusable.

## Behaviour
- Assist and suggestion chips act on press. Filter chips toggle on press. Input chips select on press (to edit or delete) and remove through their remove button.
- Keyboard: a chip set is one Tab stop; Left and Right move between chips, Home and End to the ends; Enter or Space presses or toggles. On an input chip, Backspace or Delete removes it and focus moves to the next chip (or the field).
- A menu filter chip opens a Menu below it; the chip keeps its focus ring while the menu is open and shows the chosen value when it closes.
- Sets: on touch hosts a set is one line that scrolls horizontally with a fade at the end; on pointer hosts it wraps. Selected filters never reorder themselves.
- Removing an input chip collapses its space over `duration-short-4` with `ease-emphasized-accelerate`; offer Undo in a snackbar for removals the person may regret.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | 32 tall, filters wrap; token fields use input chips with a remove button on hover and focus only (always shown on touch). |
| macOS | 28-32 tall token look in fields (like NSTokenField) with `radius-sm`; filters in a toolbar may use the thumb Segmented style when exclusive. |
| Linux | 32 tall; GNOME uses pill-shaped toggle buttons for filters: keep chips, which fit the same place. |
| Android | 32 tall with a 48 target; single-line scrolling sets; ripple. |
| iOS | 32 tall with a 44 pt target; scrolling sets; no ripple; menu filters open a pull-down menu. |
| Web | `<button aria-pressed>` for filters, a `role="listbox"` or grid for input chip sets; the remove button has its own name. |

## Accessibility
- Assist and suggestion: role Button. Filter: role Button with Pressed (toggle) or a Checkbox in a group named by the set ("Status"). Input: a list item in a list named by the field, with a Remove action and a separate remove Button named "Remove Ada Lovelace".
- Menu filter: Button that reports Has popup and Expanded.
- Removal is announced ("Ada Lovelace removed").
- Contrast: labels 4.5:1; the outline edge 3:1 against the ground so unselected chips are findable.
- Invalid input chips expose the error in their description.
- Reduced motion: no check growth, no collapse animation.

## Content
- 1-3 words, sentence case, no punctuation: "Failed", "Open in terminal".
- Filters are nouns or adjectives; a menu filter shows "Name: value" ("Branch: main").
- Values in input chips are shown as entered (paths and addresses keep their case).

## e.ui today
`control.chip` builds one of four `ChipKind`s (Assist, Filter, Input, Suggestion) from the Button look (`Outlined`, `Plain` for suggestion, `Filled` for a selected filter), rounded to half the control height; an input chip adds an `x` in the Label style as a remove region keyed `key + 1`, at least `space-lg` square. To reach this design:
- Use `radius-sm` corners and 32 height, not a pill; outline edge 1 px `outline`.
- Draw a selected filter as `secondary-container` with a leading check, not the Filled `primary` button.
- Replace the text `x` with the `close` icon in a 24 remove button, and add leading icon and avatar slots.
- Add the elevated assist look, the dragged, invalid and disabled states, and the focus ring (`pressable_states` drops it).
- Add chip sets with roving focus and Backspace removal, and the menu filter with its chevron.
