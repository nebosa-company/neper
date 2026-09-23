# FieldLabel

A field label names a control from outside it. It sits above the control, or leading it in forms with a label column, and can mark the control required or optional and offer a help button.

## Anatomy
1. Label text: `title-small` (14/20, weight 600) above a control, or `body-medium` when leading.
2. Required mark: an asterisk in `error`, 4px after the text. It is decorative (see Accessibility).
3. Optional mark: "(optional)" in `body-medium`, `on-surface-variant`, 4px after the text.
4. Optional help button: an 18px info icon in a 24px round target. It opens a rich tooltip or popover that explains the field.

## Variants and when to use
| Variant | Layout | Use for |
|---|---|---|
| Above | Label over the control, 6px gap | Dense fields (40) on pointer hosts, and any control without a label of its own: select, list box, slider, radio group. The default in Form on Windows, Linux and desktop Web. |
| Leading, end-aligned | Label column (fixed width, at least 120) beside the control, text end-aligned, `space-4` gap | macOS preference windows and wide settings dialogs where many short fields share a column. |
| With help | Either, plus the info button | A field whose meaning needs more than a supporting line, such as units, limits or consequences. |

A 56 or 48 Text field carries its own floating label: don't add a Field label to it. For the help and error text under a control use Field message. To get label, control and message wired together use Form field.

Mark the minority. In a form where most fields are required, mark the optional ones "(optional)" and nothing else. Where most are optional, mark the required ones with an asterisk and say once, at the top of the form, "* Required". Never mix both in one form.

## Specs
| Part | Value |
|---|---|
| Type (above) | `title-small`: 14/20, weight 600, letter-spacing 0.1 |
| Type (leading) | `body-medium`: 14/20, weight 400 |
| Colour | `on-surface`; invalid `error`; disabled `on-surface` 38% |
| Required mark | `*`, weight 600, `error`, `space-1` 4 after the text |
| Optional mark | "(optional)", `body-medium`, `on-surface-variant`, `space-1` 4 after |
| Help button | `icon-sm` 18 in a `control-xs` 24 round target (pads to 32 with a pointer, 48 on touch), `on-surface-variant` |
| Gap to control (above) | 6 (`space-1` plus 2) |
| Leading column | at least 120 wide, end-aligned, vertically centred on the control's first line |
| Wrapping | wraps to two lines at most, then ellipsizes; the full text goes in the tooltip |

## States
- Default: `on-surface`.
- Invalid: the label turns `error` along with its control. The error icon and message live in the Field message, not here.
- Disabled: text and marks at `on-surface` 38%. The help button stays enabled, so a reader can still learn why the field is unavailable.
- Help button: hover `state-hover` layer, focus `state-focus` layer plus the ring (inset to its 24px circle), pressed `state-pressed` layer.

## Behaviour
- A click or tap on the label focuses its control. For a checkbox or switch it toggles, as native labels do.
- The help button opens a rich tooltip on hover (after `duration-short-4`) and focus, and a popover on click or tap. Escape closes it and returns focus to the button.
- The label never changes to show a state. The words stay put and only the colour follows the control.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Above, `title-small`. On Alt, access keys underline the mnemonic letter in the label and the key focuses the control. |
| macOS | Leading and end-aligned in preference windows and sheets, with no trailing colon (current macOS style). Above for stacked forms in content. |
| Linux | Above on GNOME (Adwaita forms, 6px gap). KDE's FormLayout puts labels leading and end-aligned with a trailing colon: follow KDE when running under Plasma. Mnemonics with Alt. |
| Android | Rarely used: filled fields float their own labels. Use above for sliders, radio groups and selects in lists. |
| iOS | Grouped lists put the label leading inside the row and the value trailing. Use above only outside grouped lists. |
| Web | A real `<label for>` element, or `aria-labelledby` for composite controls. A click on it focuses the control. |

## Accessibility
- The label is the control's accessible name, related through `for` or labelled-by, not placed beside the control by position alone.
- The asterisk is hidden from assistive technology. The control itself carries the Required state, so a screen reader says "required" once, in its own words.
- "(optional)" is part of the name ("Description, optional"), which is correct and wanted.
- The help button is a button named "About <label>" and describes nothing on its own. Its tooltip text becomes an extra description of the control.
- Contrast: 4.5:1 for the label and 3:1 for the asterisk (it is not the only signal).
- Leading labels must not be truncated at 200% text size: they wrap above the control instead.

## Content
Name the value, not the action: "Default branch", not "Enter default branch". Sentence case, one to four words, no trailing colon on any host except KDE, no period. Use the same word the product uses elsewhere for the same thing.

## e.ui today
`control.field_label` lays out the label in the Label role and `text`, followed by an `error` asterisk when `required` (gap `space-xs`, no wrap). It is a Text node controlling `for_key`, and `form_field` builds one keyed `key + 1`. To reach this design:
- Set the label in `title-small` (above) or `body-medium` (leading), with a 6px gap to the control.
- Add the "(optional)" mark and a `mark` option (required, optional, none) so a form can mark the minority.
- Add an optional help button with its tooltip and popover, named "About <label>".
- Colour the label `error` when its control is invalid and 38% when disabled. Today it never follows the control.
- Make it the control's accessible name (labelled-by), so a press on it focuses or toggles the control. Today it only controls `for_key`.
- Allow two lines before ellipsizing. Today it never wraps.
- Add the leading, end-aligned layout for Form's label column.
