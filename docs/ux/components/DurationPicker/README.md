# DurationPicker

A duration picker sets a length of time (a timeout, a timer, a retention period) in hours, minutes and seconds: one forgiving typed field with presets on pointer hosts, a box per unit on touch, and countdown wheels on iOS.

## Anatomy
1. Field (pointer): a text field labelled with what the duration limits ("Build timeout"), the value written with units ("1 h 30 min"), a `clock` icon at the end, and supporting text that shows how the typed text reads ("Reads as 45 min").
2. Presets (optional): filter chips with common values beside or under the field; the one matching the value is selected.
3. Modal picker (touch): a title label, a box per unit (hours, minutes, seconds) with `:` between, the unit written under each box, presets as chips, and Cancel / OK.
4. Wheels (iOS): one wheel per unit with its unit label to the right of the selection band.

## Variants and when to use
| Variant | Use for |
|---|---|
| Typed field | Pointer hosts, and settings forms everywhere: the fastest way to enter "90m" or "1:30". |
| Field with presets | When a few values cover most cases (15 min, 30 min, 1 h). |
| Unit boxes | Touch hosts: a modal from the field, digits only. |
| Wheels | iOS (the countdown timer idiom), inline or in a popover. |

Use Time picker for a time of day, Date picker for a calendar span. For a coarse choice ("1 day", "1 week", "Never") use Select; for durations beyond days (retention in days or months) use a number field with a unit select.

## Specs
| Part | Value |
|---|---|
| Field | text field, 40 dense on pointer hosts, 56 on touch; `clock` 18 trailing |
| Value format | units written, largest first, zero parts dropped: "1 h 30 min", "45 s", "2 h"; `body-medium` / `body-large` |
| Supporting text | `body-small` in `on-surface-variant`: the input hint at rest, the reading while typing, the error when invalid |
| Presets | filter chips, 32 tall, `space-2` 8 apart, `space-3` 12 below the field; selected `secondary-container` with a check |
| Modal container | `surface-container-high`, `radius-xl` 28, `elevation-3`, 360 wide, `space-6` 24 padding |
| Unit boxes | 72 by 64, `radius-sm` 8, 32/40 `display` face; rest `surface-container-highest` / `on-surface`; focused `primary-container` / `on-primary-container` with a 2px `primary` outline and caret |
| Separators | `:` in `display-small`, 16 wide |
| Unit labels | `body-small` in `on-surface-variant`, under each box, start-aligned |
| Wheels | as Time picker: 36 rows, 5 visible, band `surface-container-highest`; unit label `label-large` in `on-surface` beside each wheel |
| Actions | Cancel and OK text buttons, end-aligned |

## States
- Field: rest, hover, focus, filled, invalid, disabled as Text field specifies; disabled keeps the value readable and says why ("Set by the organisation policy").
- Typing: the supporting text shows the reading live ("Reads as 45 min"); when the text cannot be read, it shows the hint instead, not an error, until blur.
- Invalid: out of range or unreadable on blur; `error` outline and icon, and a message with the limit ("Enter 999 hours or less", "Enter at least 10 s").
- Preset chip: rest, hover, focus, selected (matching the value exactly).
- Unit box: rest, focused (with caret), invalid (`error` outline).

## Behaviour
- Parsing: accepts "90m", "90 min", "1:30" (h:mm), "1:30:00", "1h30", "1.5h", "2 hours"; normalises on blur to the canonical written form; rolls over (90 min shows as "1 h 30 min").
- Field keys: Up and Down add or remove one unit of the part under the caret (with Shift, 10); Enter commits; Escape reverts to the last committed value.
- Presets: a press sets the value; typing a preset's value selects its chip.
- Unit boxes: two digits per box then focus moves on; minutes and seconds cap at 59 and roll into the next unit on blur (75 min becomes 1 h 15 min); hours up to the maximum (999 by default).
- Modal: OK commits, Cancel and the scrim discard; Enter is OK, Escape Cancel.
- Wheels: spin each unit; hours to the maximum, minutes and seconds 0-59; haptic detents on iOS.
- Keeps fractions it cannot show: a value with milliseconds is shown rounded but committed unchanged unless edited.
- Motion: none beyond the field's; the modal enters like a Dialog. Reduced motion: fade.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Typed field with presets; 32 chips; the list of presets may also be a dropdown on the field. |
| macOS | Typed field; Up/Down step the part under the caret (the `NSDatePicker` textual feel); presets as a pop-up menu on the icon. |
| Linux | Typed field with presets. |
| Android | The field opens the unit-box modal; the number keyboard. |
| iOS | Native countdown wheels (`UIDatePicker .countDownTimer`, hours and minutes) or ours with seconds; in forms, a compact button showing the value that opens the wheels in a popover. |
| Web | Typed field on fine pointers; the unit-box modal on coarse pointers; `inputmode="numeric"` in the boxes. |

## Accessibility
- The field is a Text field labelled by its label, described by the supporting text; the value is announced in words ("1 hour 30 minutes").
- The live reading ("Reads as 45 min") is a polite announcement after typing pauses; the error is assertive on blur.
- Unit boxes and wheels are SpinButtons named "Hours", "Minutes", "Seconds" with value, minimum and maximum.
- Presets are a group of toggle chips labelled "Presets"; the selected one reports Selected.
- Contrast: digits 4.5:1 on their boxes; supporting text 4.5:1.
- Targets: 48 on touch (boxes exceed it), 32 on pointer hosts.
- Reduced motion: fade.

## Content
- Label: what the duration limits: "Build timeout", "Idle timeout", "Cache retention".
- Units abbreviated with a space: "h", "min", "s" ("1 h 30 min"); spelled out for screen readers.
- Hint: show two or three accepted forms: "Type 90m, 1:30 or 1h 30m".
- Errors give the limit: "Enter 999 hours or less".

## e.ui today
`overlay.duration_picker` is a row of three `control.stepper`s (hours up to 999, minutes, seconds) with `:` between; each step rebuilds the `time.Duration` from whole seconds. To reach this design:
- Replace the steppers with a typed field that parses the forms above and normalises on blur; add optional presets as chips.
- Add the unit-box modal for touch hosts and wheels for iOS.
- Keep the fraction of a second in `value` unless the user edits it; today every step drops it.
- Show a value over the maximum as invalid with a message instead of clamping it to 999 on the first `-`.
- Write the value with units and zero-pad the boxes (today `1 : 30 : 0`); paint and localise the unit labels.
- Roll 60 minutes or seconds into the next unit instead of clamping at 59.
