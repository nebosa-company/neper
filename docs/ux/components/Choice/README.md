# Choice

Choice covers checkboxes and radio buttons. A checkbox turns an independent option on or off, or shows that a group is chosen in part. A radio button picks exactly one option from a small visible set.

## Anatomy
1. Mark: an 18px checkbox (2px outline, 2px corners) or a 20px radio ring (2px), centred in a 40px state-layer circle.
2. Tick or dash: a 14px `check` (checked) or `remove` (indeterminate) in `on-primary` on the filled box. For a radio, a 10px dot inside the ring.
3. Label: `body-medium` on pointer hosts and `body-large` on touch, 4px after the state circle. It wraps under itself, not under the mark.
4. Row: the label and mark together are one target, at least 48 tall on touch and 40 with a pointer.
5. Group (radios, related checkboxes): a Form field label naming the set, and one Field message for the set.

## Variants and when to use
| Variant | Use for |
|---|---|
| Checkbox | An option that can be on or off independently of others, applied when the form is submitted: "Run tests before merging". |
| Checkbox, indeterminate | A parent whose children are chosen in part ("All hosts", 2 of 3). A press on it checks all, and a second press clears all. |
| Checkbox list rows | Choosing several items in a list or table. The checkbox leads the row. |
| Radio group | One of two to five mutually exclusive options that the reader should compare. Always one selected, or none only before the first choice. |
| Radio list rows | Radios with supporting text, in a settings list or a sheet. |

Use a Switch for a setting that takes effect immediately. Use a Select for more than five exclusive options or when space is short. Use a Segmented button for two to three short options that change a view. Use a Chip (filter) for toggles in a toolbar over content. Never use a single radio button.

## Specs
| Part | Touch | Pointer (density -1) | Dense (density -2) |
|---|---|---|---|
| State circle | `control-md` 40 | 40 | `control-sm` 32 |
| Checkbox box | 18, 2px outline, radius 2 | 18 | 16 |
| Radio ring and dot | 20 ring, 10 dot | 20 and 10 | 16 and 8 |
| Row min height | `target-touch` 48 | 40 | 32 |
| Label | `body-large` | `body-medium` | `body-medium` |
| Mark to label gap | `space-1` 4 (after the 40 circle) | 4 | 4 |
| Between options (stacked) | 0 (rows abut) | 0 | 0 |
| Between options (inline) | `space-4` 16 | 16 | 12 |
| In a list row | circle at 4 from the leading edge, 8 to the text; children indent 32 | same | same |

| Part | Colour role |
|---|---|
| Unchecked box and ring | `on-surface-variant` outline |
| Checked box | `primary` fill and outline, `on-primary` tick |
| Selected radio | `primary` ring and dot |
| State layer | `on-surface` when unchecked, `primary` when checked, at the state opacity |
| Error | `error` outline, or `error` fill when checked |
| Disabled | outline `on-surface` 38%; a checked box is `on-surface` 38% fill with a `surface` tick; label `on-surface` 38% |
| Label | `on-surface` (not coloured by error: the Field message says what is wrong) |

## States
- Unchecked, checked, indeterminate (checkbox). Selected, unselected (radio).
- Hover: `state-hover` layer on the circle. Focus: `state-focus` layer and the 3px ring on the circle (in a list row, the ring goes inset on the row instead). Pressed: `state-pressed` layer and a ripple from the centre on touch.
- Error: the outline turns `error` and a Field message below the group says why ("Choose at least one host"). Colour alone never carries the error.
- Disabled: 38% outline and label. Keep the checked state visible.

## Behaviour
- A press anywhere on the row (mark or label) toggles or selects.
- Checkbox: Space toggles. Enter submits the form, as in any field. Indeterminate goes to checked on press, and a later press clears it. The indeterminate state itself is never a press result, only a consequence of the children.
- Radio group: one tab stop, on the selected radio or on the first when none is selected. Up and Left select the previous radio, Down and Right the next, wrapping at the ends. Home and End are not used. Selection follows focus. Space selects the focused radio when none is selected.
- Motion: the box fills and the tick draws over `duration-short-2` (`ease-standard`). The radio dot scales from 0 over `duration-short-3`. With reduced motion, they cross-fade.
- A parent checkbox's count ("2 of 3") updates with its children.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | 40 rows, 18 box (Fluent's 20 with a 4 radius is acceptable when the app follows Fluent throughout). Space toggles. Radio arrows as above. |
| macOS | 32 rows (dense) with `body-medium`. The label is on the right. In macOS preference windows, checkboxes stack under a leading group label (see Form). No ripple. |
| Linux | 40 rows. GTK checkboxes and radios follow the same keyboard model. KDE's leading label column. |
| Android | 48 rows, ripple on press, Material 18 box and 20 ring. |
| iOS | No native checkbox: inside grouped lists, use a trailing checkmark for single choice and leading circle checks for multiple. Outside lists, use this checkbox with 44pt rows. Prefer a Switch for settings. |
| Web | Native `<input type="checkbox|radio">` styled, or `role="checkbox|radio"` with `aria-checked` (including `mixed`). A `<fieldset>` with a `<legend>` for groups. |

## Accessibility
- Checkbox: role checkbox, name = label, checked true, false or mixed, and a Toggle action. Radio: role radio in a radiogroup named by the group label, with selected and position in set ("2 of 3").
- Required and Invalid sit on the group (or the single checkbox) and the error message is related to it.
- A parent checkbox controls its children, and its name includes the count through its description ("2 of 3 selected").
- Contrast: the unchecked outline is 3:1 against the surface, and the tick is 4.5:1 on `primary`.
- Targets: the whole row, 48 on touch, and 40 (never under 32) with a pointer.
- Reduced motion: no tick draw or dot scale.

## Content
- Checkbox labels state the "on" condition positively: "Run tests before merging", not "Don't skip tests".
- Radio labels are parallel and short, sentence case, without trailing punctuation. Put details in supporting text, not in the label.
- A group label names the choice: "Merge strategy", "Run tests on".

## e.ui today
`control.checkbox` and `control.radio` (through `choosable`) draw a mark `control-height / 2` square with a `border` edge and `radius-sm`, beside a Body label in a region at least `hit-target` square. When chosen, the mark tints toward `selection` and fills with `primary`. Mixed is a 30%-tall `primary` bar. Disabled is opacity 0.5. `radio_group` stacks radios with a `space-xs` gap. To reach this design:
- Draw an 18px box with 2px `on-surface-variant` outlines and radius 2, and a 20px ring with a 10px dot. Today the radio is a disc and the checkbox has no tick glyph (a filled square).
- Draw the `check` and `remove` glyphs in `on-primary` on a `primary` fill. Drop the `selection` tint.
- Add the 40px state-layer circle with hover, focus (ring), and pressed looks. Today there are none.
- Replace opacity 0.5 with the 38% disabled colours, keeping the checked state legible.
- Add an `invalid` state, with the error outline and a message owned by the group.
- `radio_group`: one tab stop with arrow keys and selection following focus. Rows abut (0 gap) at 40 or 48. Give the group role radiogroup, not Group.
- Add list-row variants (leading mark, supporting text, parent and child indent).
