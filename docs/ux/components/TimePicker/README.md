# TimePicker

A time picker sets a time of day: a typed field with a list of times on pointer hosts, a dial on Android and touch Web, and wheels on iOS, all in the locale's 12- or 24-hour clock.

## Anatomy
1. Field (every host): a text field labelled with what the time is ("Starts"), the value in the locale's clock, a `clock` icon at the end.
2. Time list (pointer): a dropdown of times in steps (15 or 30 minutes), each with its offset from a related time ("30 min") when there is one.
3. Modal picker (touch): "Select time" label, the hour and minute boxes, the AM/PM selector (12-hour locales only), the dial, a mode toggle, and Cancel / OK.
4. Hour and minute boxes: 80 by 64, `display-small` digits; the one being set is `primary-container`.
5. AM/PM selector: two stacked segments, 48 by 64, the chosen one `tertiary-container`.
6. Dial: a 224 circle of `surface-container-highest`, twelve numbers (hours, or minutes in fives), a `primary` hand from the centre to a 44 `primary` knob over the chosen number.
7. Wheels (iOS): one column per part with a selection band across the middle.

## Variants and when to use
| Variant | Host | Use for |
|---|---|---|
| Field with time list | Windows, macOS, Linux, desktop Web | Every time on pointer hosts: typing is fastest, the list covers the common steps. |
| Dial | Android, touch Web | Choosing a time by touch in a modal. |
| Input mode | Android, touch Web | The dial's alternative: two boxes and the keyboard, one tap away. |
| Wheels | iOS, iPadOS compact | The native idiom; inline or in a popover from the field. |

Use Duration picker for a length of time ("1 h 30 min"), never a time picker. Use Date picker beside it for a date-time. For a small fixed set of times use Select or chips.

## Specs
| Part | Value |
|---|---|
| Field | text field 40 dense on pointer hosts, 56 on touch; `clock` 18 trailing |
| Time list | Menu at pointer density: 32 rows, `body-medium`, offset in `body-medium` `on-surface-variant` at the end, selected row `secondary-container`; 6 rows visible, scrolls to the current value |
| Modal container | `surface-container-high`, `radius-xl` 28, `elevation-3`, 328 wide, `space-6` 24 padding |
| Title label | `label-medium` in `on-surface-variant` |
| Boxes | 80 by 64, `radius-sm` 8, `display-small` 36/44; rest `surface-container-highest` / `on-surface`; active `primary-container` / `on-primary-container`; focused in input mode a 2px `primary` outline |
| Separator | `:` in `display-small`, 16 wide |
| AM/PM | 48 by 64, `radius-sm`, `divider` in `outline`; selected `tertiary-container` / `on-tertiary-container`; `label-large` |
| Dial | 224 diameter, `surface-container-highest`; numbers `body-large` in `on-surface`, on the knob `on-primary`; hand 2 wide `primary`; centre dot 8; knob 44 `primary` |
| Wheels | rows 36, 5 visible (180); centre 20/36 `body` face in `on-surface`, neighbours `on-surface-variant`, outer rows smaller and faded; band `surface-container-highest`, `radius-sm` |
| Input labels | `body-small` in `on-surface-variant` under each box |
| Actions | mode toggle icon button at the start; Cancel and OK text buttons at the end |

## States
- Field: as Text field (rest, hover, focus, filled, invalid, disabled). Invalid shows the error icon and "Enter a time from 00:00 to 23:59".
- Dial: hour mode then minute mode; the active box shows which. Dragging shows the knob following the finger; between five-minute marks a small knob shows the exact minute.
- Boxes: rest, active (being set on the dial), focused (input mode, with caret), invalid (`error` outline, message below).
- AM/PM: one selected, the other with a hover layer on pointer.
- List row: rest, hover, selected; times before a related start time are omitted, not disabled.

## Behaviour
- Field: type in any common form ("1430", "2:30 pm", "14.30", "noon") and it reformats on blur to the locale's clock; Up and Down step the part under the caret by 1 (minutes by the step with Shift); Alt+Down opens the list.
- List: opens on focus or the icon, scrolled to the value; Up/Down move, Enter picks, Escape closes; typing keeps filtering the list to matching times.
- Dial: press or drag on the dial to choose the hour; releasing moves to minutes; minutes snap to 5 unless dragged slowly (1-minute resolution). Pressing a box returns to that mode. Arrow keys move the knob by one hour or one minute; Page Up/Down by 5 minutes.
- Input mode: digits fill the hour, then jump to the minute after two digits (or one digit greater than 1 in 12-hour, 2 in 24-hour); Tab moves; "a" and "p" set AM/PM.
- Modal: OK commits, Cancel and the scrim discard; Enter is OK, Escape Cancel.
- Wheels: flick to spin with momentum and detents; each detent gives a light haptic on iOS; VoiceOver swipes up and down adjust.
- Motion: hand and knob move over `duration-medium-2` with `ease-standard`; the hour-to-minute switch cross-fades the numbers over `duration-short-4`. Reduced motion: no hand sweep, instant change.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Field with the time list (the Outlook idiom); the region's 12/24-hour setting and separator. WinUI's flipper TimePicker is not used. |
| macOS | The textual `NSDatePicker` field with a stepper: each part is a segment that takes digits and Up/Down; the list is optional. |
| Linux | Field with the time list; GNOME's 12/24-hour setting from the desktop. |
| Android | Dial in a modal by default, input mode one tap away; 12/24-hour from the system setting. |
| iOS | Native `UIDatePicker` (`.time`): `.compact` in forms (a button that opens wheels in a popover), `.wheels` inline where there is room. |
| Web | Field with the time list on fine pointers; the dial modal on coarse pointers; `<input type="time">` is an acceptable fallback on mobile browsers. |

## Accessibility
- The field is a Text field (a Combobox when it has the list) labelled by its label, the value announced as a time ("2:30 PM", "14:30").
- The modal is a Dialog labelled "Select time"; the hour and minute boxes are SpinButtons named "Hour" and "Minute" with value and range; AM/PM is a RadioGroup.
- The dial is a Slider-like control named "Hour" or "Minute" with Increment / Decrement and Set-value; its numbers are not separate stops.
- Wheels are SpinButtons (Adjustable on iOS).
- Screen readers announce the new value on every change and the mode switch ("Minute").
- Contrast: digits 4.5:1 on their boxes; the knob `on-primary` on `primary`; the hand and knob 3:1 against the dial face.
- Targets: dial numbers have 48 hit areas; boxes and AM/PM exceed 48. Reduced motion: no sweep.

## Content
- Label: what happens at that time: "Starts", "Ends", "Run nightly build at". Never just "Time".
- Values in the locale's clock: "14:30" or "2:30 PM"; AM and PM in the locale's words.
- Offsets in the list: "15 min", "1 h", "1.5 h".
- Errors say the valid range: "Enter a time from 00:00 to 23:59".

## e.ui today
`overlay.time_picker` is a row of `control.stepper`s for the hour, minute and optional second (Outlined `-` and `+` buttons around the digits) with `:` between, each step reporting the whole `time.Time`. To reach this design:
- Replace the steppers with a typed time field and the time list on pointer hosts; add the dial modal with input mode for Android and touch Web, and native wheels on iOS.
- Zero-pad and format by locale: today 9:05 shows as `9 : 5`, and there is no 12-hour clock or AM/PM.
- Wrap instead of clamping (59 minutes plus one goes to the next hour), and step minutes by a configurable increment.
- Paint the part labels (Hour, Minute) and localise them; today they are fixed English strings and only in the tree.
- Expose the parts as SpinButtons instead of Sliders, with Up/Down on the part itself.
