# FormField

A form field wraps one control with its label, help and validation message, and wires the relationships between them. Every control in a Form goes in one.

## Anatomy
1. Label: the control's own floating label (56 and 48 Text fields), or a Field label above or leading it (every other control, and dense fields).
2. Required or optional mark: on the label, following the form's "mark the minority" rule.
3. Control: any input: text field, select, list box, checkbox or radio group, switch, slider, date picker.
4. Message: a Field message below: help, pending, warning, error or success.
5. Group: for a set of checkboxes or radios, the label names the group and each option keeps its own label.

## Variants and when to use
| Variant | Label | Use for |
|---|---|---|
| Floating | inside the text field | Touch hosts and 48 fields on pointer hosts. Text controls only. |
| Above | Field label, 6px above | Dense 40 fields, and every non-text control on every host. |
| Leading | Field label in a label column | macOS preference windows and wide settings dialogs (see Form). |
| Group | Field label as the group's legend | Checkbox and radio groups, and several related inputs such as a date range. |

A single checkbox or switch with its own label ("Run tests before pushing") needs no Form field label. Wrap it only to add a message. For a heading over several form fields use a Group box or a form section heading.

## Specs
| Part | Value |
|---|---|
| Label to control | 6 (above) or `space-4` 16 (leading) |
| Control to message | `space-1` 4 |
| Message inset | 16 under a boxed field with its own label, 0 otherwise |
| Width | fills its Form column. A field never sizes to its content. |
| Between form fields | `space-5` 20 on pointer hosts, `space-6` 24 on touch (set by Form) |
| Group options | 40 rows (pointer) or 48 (touch), with the option's 40 state circle aligned to the label edge by pulling it out 8 |

Colours come from the parts: the label follows the control's state, and the message follows its variant. The form field draws nothing itself: no background, border or padding.

## States
The state is owned by the form field and passed down: Invalid (with a message), Required, Disabled, Read-only, Pending. When one of these is set on the form field, the label, the control and the message all follow it together. They never disagree: an invalid control without an error message, or an error message under a valid control, is a bug.

## Behaviour
- A press on the label focuses the control (for a group, the first or the checked option).
- Validation runs per form field. On the first blur or submit the error appears, and after that it updates live until fixed. Fixing it restores the help text.
- A pending asynchronous check blocks submit for this field only, and the Form's submit button explains that it is waiting ("Checking handle").
- Disabled fields keep their message visible and at full strength, because it says why.
- Motion: messages cross-fade in place (`duration-short-2`, `ease-standard`). The form never animates reflow.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Above labels and 40 dense controls in settings and tool windows. 48 floating fields in content. |
| macOS | Leading labels in preference windows, above in content. Groups of checkboxes are left-aligned under a leading label. |
| Linux | Above (GNOME). Leading with a colon under KDE Plasma. |
| Android | Floating labels on filled fields. Above for sliders, groups and selects. |
| iOS | Inside grouped lists: the label leads the row, the control trails, and the message becomes the section footer. |
| Web | `<label for>` or `<fieldset>` and `<legend>` for groups. `aria-describedby` for help, `aria-errormessage` and `aria-invalid` for errors, `aria-required`. |

## Accessibility
- Control name = label. Description = help or warning message. Error message = the message when invalid. The control carries Required, Invalid, Disabled and Read-only.
- A group is a Group (fieldset) named by its label. The group, not each option, carries Required and Invalid, and the error is announced once.
- The required mark is not read: "required" comes from the state. "(optional)" is read as part of the name.
- Focus order is label-less: Tab goes control to control, never to a label, except the label's help button.
- After a failed submit, focus goes to the Validation summary, not to the first invalid field, so the reader hears how many problems there are first.

## Content
Follow Field label and Field message. The label names the value, the help says what or why, and the error says how to fix it. Keep the three from repeating each other: if the label is "Port", the help is not "Enter the port".

## e.ui today
`control.form_field` stacks a `field_label` (key + 1), the caller's `control_node`, and a `field_message` (key + 2) in a vertical flex with gap `space-xs`. It is a Group named by the label and described by the message while help shows, and it carries Required and Invalid. To reach this design:
- Own the state: take `invalid`, `enabled` and `read_only` once and pass them to the label, the control and the message. Today the caller must set `invalid` in the control's `FieldOptions` separately, and the two can disagree.
- Skip the outside label for a text field that floats its own, instead of asking the caller to pass an empty label to the field.
- Relate a Warning message as a description. Today a Warning is related to nothing.
- Render help as a plain description, not through `field_message`'s live Status. Today changing the help is announced.
- Add the group variant (fieldset semantics, Required and Invalid on the group) for checkbox and radio groups.
- Use 6 between label and control and 4 to the message, with the 16 inset under boxed fields.
