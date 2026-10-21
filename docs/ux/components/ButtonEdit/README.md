# ButtonEdit

A button edit is a text field with one action button inside its end edge, for a value that is typed or chosen through a dialog: a folder path with "Browse", a colour with "Pick", a cell with "Choose".

## Anatomy
1. Field: the Text field (outlined or filled) with its label, value and supporting text.
2. Button: a 24 to 32 wide icon or text button inside the field's end edge, separated from the text by a 1px `outline-variant` divider.
3. Supporting text: the hint, or the error.

## Variants and when to use
| Variant | Where |
|---|---|
| Text button ("Browse…", "Choose") | Pointer hosts, when the verb is not obvious from an icon |
| Icon button (folder, calendar, palette) | Dense layouts and touch hosts, with a tooltip |

Use a Combo box when the choices are a list; use a Button edit when the choice opens something else.

## States
- Rest, hover and focus follow the Text field; the button has its own hover, pressed, focus and disabled states.
- Read-only: the text is not editable but the button still works.
- Disabled: field and button are both disabled; explain why in the supporting text.
- Error: the field's error look, with the message below.

## Behaviour
- Typing edits the value; Enter commits it. Pressing the button runs the action, which may replace the value; focus returns to the field afterwards.
- Alt+Down (or F4) runs the action from the keyboard when the field has focus.
- The button does not take focus from the text on a pointer press.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense; the button sits in the field with a divider; "…" for a dialog |
| macOS | Dense; a small bordered button at the field's end |
| Linux | GTK entry with a trailing icon |
| Android, iOS | Filled field with a 48 touch target for the end icon |
| Web | An `input` with an adjacent button inside one container |

## Accessibility
- The field is a text field named by its label; the button is a button named for the action and the field ("Browse for folder").
- Both are in the tab order, field first. The button's shortcut is announced in its description.
- The button holds 3:1 against the field in every theme.

## e.ui today
`control.button_edit` takes the label, buffer, change and submit callbacks, an action callback and a button label; it has Windows and Linux looks and is used by the data grid for choice cells.
