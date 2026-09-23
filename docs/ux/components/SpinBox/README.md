# SpinBox

A spin box is a numeric text field that also steps its value, for integers people either type or nudge: a port, a year, a timeout.

## Anatomy
1. Field: the Text field (outlined or filled) with its label, value and supporting text.
2. Value: the number, `body-large` (touch) or `body-medium` (dense), tabular figures; an optional unit suffix in `on-surface-variant`.
3. Stepper arrows (pointer): a stacked pair of 24x18 buttons with `chevron-up` / `chevron-down` 16 at the field's end.
4. Step buttons (touch): 40 icon buttons with `remove` at the start and `add` at the end, inside the field.
5. Supporting text: the range, or the error.

## Variants and when to use
| Variant | Where | Use for |
|---|---|---|
| Dense outlined with arrows | Pointer hosts | Forms and inspectors; keyboard-first editing. |
| Filled with end buttons | Touch hosts | Forms on phones and tablets, where 18px arrows are too small. |
| Inline (no label) | Tables, toolbars | A value in a grid cell; name it through the column header. |

Use a Stepper when typing is not needed, a Slider for continuous or approximate values, a Formatted field for patterned text (dates, codes), and a Text field with numeric keyboard for identifiers that are not quantities (a PIN).

## Specs
| Part | Dense (pointer) | Default (touch) |
|---|---|---|
| Height | `control-md` 40 | `control-xl` 56 |
| Field | outlined, `radius-xs`, 1px `outline` (2px `primary` focused) | filled, `surface-container-highest`, top `radius-xs`, 1px indicator (2px `primary` focused) |
| Width | fits the longest valid value plus the arrows; 96 to 160 | 160 to 280 |
| Value | `body-medium`, tabular, start-aligned | `body-large`, tabular, centred between the buttons |
| Arrows | 24x18 each, `radius-xs`, `chevron-up`/`-down` 16, `on-surface-variant`; flush to the end with `space-2` less end padding | n/a |
| End buttons | n/a | `control-md` 40 icon buttons, `on-surface-variant`, padded to 48 |
| Unit suffix | `body-medium` `on-surface-variant`, `space-1` after the number | same |
| Supporting text | `body-small`, range or error | same |

## States
- Field rest, hover, focus, invalid and disabled are the Text field's.
- Arrows and end buttons have their own hover `state-hover` and pressed `state-pressed` layers. At a bound the matching arrow is `on-surface` 38% and inert.
- Invalid: typed text that is not a number, or out of range after commit: `error` outline, error supporting text that says the fix ("Use 1024 or higher"). While typing, do not flag a partial number.
- Disabled: the Text field's disabled look; explain why in the supporting text.

## Behaviour
- Typing accepts digits, a leading minus when the range allows negatives, and the locale's decimal separator for decimal spin boxes. Other characters are ignored, not shown as errors.
- The value commits on Enter, blur, or a step. On commit an out-of-range value clamps to the nearest bound if the field is lenient (and says so in supporting text for 3 seconds), or is flagged invalid if strict.
- Up/Down step by `step`, Page Up/Down by 10 steps, Home/End (when the field is empty or the whole text is selected) go to the bounds. The scroll wheel steps only while the field has focus.
- Arrows and end buttons repeat on press and hold (400ms delay, then every 80ms). They do not take focus: focus stays in the text.
- Escape reverts to the last committed value.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense; WinUI NumberBox "compact" spin placement (arrows in the field). Wheel steps when focused. |
| macOS | Dense; NSTextField + NSStepper convention: the arrows sit just outside the field's end as a separate 18 wide control; ⌥-arrow steps by 10. |
| Linux | Dense; GTK SpinButton places − and + buttons at the end on GNOME: allowed as the touch look at dense height. |
| Android | Filled with end buttons; numeric keyboard (`number` or `numberSigned`); no arrows. |
| iOS | Filled with end buttons; number pad keyboard with a toolbar "Done"; no arrows. |
| Web | `input type="text" inputmode="numeric"` with `role="spinbutton"` (not `type="number"`, whose wheel and validation differ by browser). |

## Accessibility
- Role spin button, name = label, value now/min/max, value text with the unit ("30 minutes"). Actions Increment, Decrement, SetValue.
- The arrows are hidden from the tree (the keyboard does the same); the touch end buttons are real buttons named "Increase timeout" and "Decrease timeout".
- Errors are announced when shown and linked as the field's error message.
- Targets: touch end buttons 48; arrows are pointer-only helpers, the field itself is the 40 target.

## Content
Label names the quantity ("Timeout", "Port"). Supporting text gives the range in words ("5 to 120 minutes"). Errors say the fix: "Use 1024 or higher", not "Invalid value".

## e.ui today
`control.spin_box` places a 64-wide `text_field` between the stepper's Outlined "-" and "+" buttons; the buffer is rewritten with `value` on every build, and the field's label inside the row pushes the buttons half a line below the frame's centre. To reach this design:
- Build on the redesigned text field: dense outlined with stacked in-field arrows on pointer hosts, filled with in-field end buttons on touch.
- Keep the typed text as an edit buffer until commit (Enter, blur, step) instead of overwriting it each build.
- Place the label on the field (floated) so buttons align with the frame, not the label and frame together.
- Add Page Up/Down, Home/End, Escape-to-revert, wheel stepping while focused, clamping versus strict modes and a unit suffix.
- Name the step buttons "Increase/Decrease <label>" and publish the spin button value with its unit.
