# TokenField

A token field collects several short values in one field, each committed value becoming a removable input chip, for recipients, reviewers, labels and keywords.

## Anatomy
1. Container: an outlined field box, `radius-xs`, 56 min, that grows by lines as chips wrap.
2. Floated label: in the outline's notch, `body-small`.
3. Input chips: outlined `nu-chip` 32 tall, `radius-sm`, optional avatar or icon, label, trailing remove (`close` 18).
4. Text input: after the last chip, `body-large`, min 96 wide, wraps to its own line when needed.
5. Suggestion list: the Autocomplete's list, 4 below the frame.
6. Overflow count: "+3 more" in `label-medium` when unfocused and collapsed to one line.
7. Supporting text: hint, count ("3 of 10"), or the error for an invalid token.

## Variants and when to use
| Variant | Use for |
|---|---|
| Suggested tokens | People, labels from a known set; unknown values allowed or refused per field. |
| Free tokens | Keywords, email addresses; commit on Enter, comma, or paste of a list. |
| Collapsed (read view) | A field showing its tokens on one line with "+N more" until focused. |

Use a Multi-select list or Checkboxes when every option can be shown, an Autocomplete for a single value, and Filter chips for toggling a fixed set of filters.

## Specs
| Part | Default (touch) | Dense (density -1) |
|---|---|---|
| Container | min `control-xl` 56; padding `space-3` 12; 1px `outline`, 2px `primary` focused, 2px `error` invalid | min 40, padding `space-1` 4 vertical |
| Chips | `nu-chip` 32, `radius-sm`, 1px `outline`, `label-large` `on-surface`; avatar 24; remove `icon-sm` 18 `on-surface-variant` in a 24 hit, padded to 48 on touch | 24 tall, `label-medium` |
| Gap | `space-2` 8 both ways | `space-1` 4 |
| Input | `body-large`, min width 96 | `body-medium` |
| Invalid chip | 1px `error` outline, `error` label and leading `error` icon | same |
| Overflow count | `label-medium`, `on-surface-variant` | same |
| Label | floated, `body-small`; `primary` focused, `error` invalid | same |
| Max lines while focused | 4, then the box scrolls | 3 |

## States
- Rest: chips and label; collapsed to one line with "+N more" if the field is not focused.
- Focus: 2px `primary` outline; all chips shown; caret after the last chip.
- Chip hover `state-hover`; chip focus: `state-focus` plus the ring 2px outside the chip.
- Invalid token: the chip keeps the text so it can be fixed, drawn in `error` with an icon; the supporting text names it and the rule.
- Limit reached: the input hides; supporting text says "10 of 10".
- Disabled: the Text field's disabled look; chips 38%, no remove buttons.

## Behaviour
- Enter, Tab (when text is present) or a comma commits the typed text as a chip; pasting "a, b; c" or lines creates one chip each. Picking a suggestion commits it.
- Backspace in an empty input focuses the last chip; a second Backspace removes it. Left/Right move between chips and the input; Delete or Backspace removes the focused chip; Home and End go to the first chip and the input.
- Pressing a chip focuses it (it does not open anything unless the chip has a details view); its remove button removes it.
- Double-click or Enter on a focused invalid chip turns it back into text for editing.
- Duplicate values are refused with a brief highlight of the existing chip (`duration-short-4`).
- Chips enter with a `duration-short-3` scale and fade (`ease-emphasized-decelerate`) and leave with `ease-emphasized-accelerate`; the rest reflow with `ease-standard`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense (24 chips); Ctrl+A selects all chips; the WinUI token-box behaviour for Backspace. |
| macOS | Dense; NSTokenField conventions: tokens are rounded capsules, a comma or Return commits, tokens can be dragged between fields. |
| Linux | Dense; no native token field; follow this spec. |
| Android | Default; chips 32 with 48 remove targets; commit also on the keyboard's action key. |
| iOS | Default; tokens as in Mail's To field: a collapsed "and 3 more" summary when unfocused. |
| Web | A `listbox` or list of `button` chips plus a `combobox` input; the remove button is a separate focusable button. |

## Accessibility
- The field is a group named by the label with the count ("Reviewers, 3 items"); each chip is a button (or option) named by its value, with a remove button named "Remove <value>".
- The input is a combo box as in Autocomplete.
- Announce additions and removals politely ("Grace Hopper added", "Adria Kovac removed"); announce invalid tokens assertively with the message.
- Chips and remove buttons: 48 targets on touch through padding; 32 minimum with a pointer.
- Reduced motion: chips appear and go without scaling; the reflow is instant.

## Content
The label names the collection in the plural ("Reviewers", "Labels"). Chips show the value as people know it (the name, not the ID). Errors name the token and the rule: "mira@exmaple is not a valid address".

## e.ui today
`control.token_field` flows Outlined input `chip`s (radius half `control-height`, a literal "x") and a 64-wide `text_field` whose own label is drawn inside the flow, making it taller than the chips; each chip's press is a zero action, and every remove button is named "Remove". To reach this design:
- Draw one outlined field container with a floated label; put chips and a bare text input inside it (no nested `text_field` label).
- Use `nu-chip` input chips (`radius-sm`, avatar slot, `close` icon remove) and the invalid chip state.
- Name remove buttons "Remove <token>"; make chip press focus the chip (or remove it from the Tab order) instead of a no-op.
- Add Backspace-to-last-chip, Left/Right navigation, comma and paste splitting, duplicate refusal and the collapsed "+N more" view.
- Lift the fixed 30-token and key-arithmetic limits (`key + 62`) or report the limit as "N of M".
