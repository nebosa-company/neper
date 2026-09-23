# DatePicker

A date picker is a text field for a date (or a start and end date) with a calendar behind it: docked below the field on pointer hosts, a modal dialog on touch hosts, and always typeable.

## Anatomy
1. Field: an outlined or filled text field whose label names the date ("Release date"), the value in the locale's format, and a calendar icon button at the end.
2. Docked calendar (pointer): a dropdown below the field: month header, weekday row, day grid, and a footer with Today and Clear.
3. Modal picker (touch): a dialog with a header (a "Select date" label, the chosen date in `headline-large`, a mode toggle), the calendar, and Cancel / OK.
4. Input mode: the modal picker's calendar replaced by one text field (or two for a range) with the format as supporting text.
5. Range: two ends and the band between, a range summary in the header ("Sep 14 – Sep 18"); full screen on compact with months scrolling vertically.

## Variants and when to use
| Variant | Use for |
|---|---|
| Docked | Pointer hosts and wide windows: a date in a form or a toolbar. A press on a day commits at once. |
| Modal | Touch hosts: the field opens a dialog; the choice commits on OK. |
| Input mode | When the date is far away (a birth date, a contract end) or the user prefers typing; always one tap from the modal. |
| Range, modal | A span on touch: a dialog on medium and up, full screen on compact. |
| Range, docked | A span on pointer hosts: one month docked (two side by side from 600 wide). |

Use Calendar inline when choosing the date is the whole view. Use Time picker for a time, and a date field plus time field side by side for a date-time; never one combined control. For relative dates ("in 2 weeks") offer chips beside the field.

## Specs
| Part | Docked (pointer) | Modal (touch) |
|---|---|---|
| Field | text field, 40 tall dense (56 on touch), trailing calendar icon button 32 | text field 56, trailing icon button 40 |
| Container | `surface-container-high`, `radius-md` 12, `elevation-2`, 4 below the field | `surface-container-high`, `radius-xl` 28, `elevation-3`, over the 32% scrim |
| Width | 256 (7 x 32 cells + 2 x 12 padding + 8) | 328 (7 x 40 cells + padding) |
| Padding | `space-2` 8 top, `space-3` 12 sides | header `space-4` 16 top, `space-6` 24 start; calendar `space-3` 12 sides |
| Header | month `title-small`, Previous / Next 32 | "Select date" `label-medium` in `on-surface-variant`; date `headline-large` 32/40 in `on-surface`; mode toggle icon button 40; divider `outline-variant` |
| Calendar | Calendar at density -1 (32 cells) | Calendar at 40 cells |
| Footer | Today and Clear text buttons, 32, spread | Cancel and OK text buttons, end-aligned, `space-2` apart |
| Input field | none | outlined 56, `space-6` 24 sides, format in `body-small` supporting text |
| Range, compact | none | full screen on `surface-container-high`: 56 top bar with Close and Save, `label-medium` "Select range", the range in `headline-small`, a sticky weekday row with a divider, months as `title-small` headings |

## States
- Field: rest, hover, focus, filled, invalid, disabled as Text field specifies. The calendar icon button shows its selected state while the calendar is open.
- Empty: the field shows its label; the calendar opens on today's month with today focused.
- Invalid typed date: the field turns `error` with an error icon and a message that names the fix ("Choose a date from Sep 8, 2026", "Enter a date as mm/dd/yyyy"); OK stays enabled and re-shows the message.
- Out-of-range days in the calendar are unavailable (38%).
- Range in progress: after the start, the header shows "Sep 14 – End date" and hovering previews the band.

## Behaviour
- Typing is always allowed: the field parses the locale's formats and a few forgiving ones ("25 sep", "9/25", "today", "tomorrow"); it reformats to the canonical locale format on blur.
- Opening: the calendar icon button, or Alt+Down in the field (pointer); a press on the field on touch hosts. Focus moves to the selected day (else today).
- Docked: a press on a day commits and closes; Escape closes without change; Today selects today; Clear empties the field. Focus returns to the field.
- Modal: a press selects; OK commits, Cancel and the scrim discard. The mode toggle swaps calendar and input and keeps the value.
- Calendar keys as Calendar specifies (arrows, Page Up/Down, Home/End, Enter).
- Range: the first press sets the start and the second the end; pressing before the start moves the start. On compact the months scroll vertically and Save commits.
- Motion: docked opens like a Menu (`duration-medium-1`, `ease-emphasized-decelerate`, growing from the field); modal enters like a Dialog (`duration-medium-4`); full screen slides up. Reduced motion: fade.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Docked (CalendarDatePicker idiom): the field with a calendar button, 32 cells, first day from region settings. |
| macOS | The textual date field with a stepper (`NSDatePicker` text-and-stepper style) where each part is typed or stepped with Up/Down, plus the graphical calendar in a popover from the icon. |
| Linux | Docked; GTK calendar in a popover from the entry's icon. |
| Android | Modal with input mode as specified; full-screen range on compact. |
| iOS | Native `UIDatePicker` in `.compact` style: a button showing the date that opens the inline calendar in a popover; wheels (`.wheels`) where space is tight. |
| Web | Ours by default; on coarse pointers the native `<input type="date">` is acceptable when the page does not need ranges. |

## Accessibility
- The field is a Text field (or Combobox with HasPopup Dialog on pointer hosts) labelled by its label; its value is also announced in words ("Friday, 25 September 2026").
- The icon button is named "Choose date" and reports Expanded; the docked calendar is a Dialog labelled "Choose release date"; the modal is a Dialog labelled by its header.
- The mode toggle is named "Switch to text input" / "Switch to calendar".
- The format hint ("mm/dd/yyyy") is the field's description, not only its placeholder.
- Errors are announced (assertive) when they appear and are tied to the field (`error_message`).
- Calendar accessibility as Calendar specifies.
- Targets: 48 on touch; 32 on pointer hosts. Reduced motion: fade.

## Content
- Label: what the date is, never "Date": "Release date", "Start date", "End date".
- Value: the locale's medium format in the field ("25 Sep 2026" or "Sep 25, 2026"); the header uses weekday and day ("Fri, Sep 25").
- Format hint: the locale's pattern in lower case ("mm/dd/yyyy", "dd.mm.yyyy").
- Errors say what to do: "Choose a date from Sep 8, 2026", not "Invalid date".

## e.ui today
`overlay.date_picker` is an Outlined button showing `value` as `YYYY-MM-DD` (or `label` while empty) that opens `overlay.calendar` in a flyout below it; `overlay.date_range_picker` shows `YYYY-MM-DD - YYYY-MM-DD`. The Group is Expanded while open; `toggle` closes it. To reach this design:
- Replace the button with a text field: keep the label visible once a date is set (today the button shows only digits), accept typed dates, and add the calendar icon button.
- Format the value by locale instead of `YYYY-MM-DD`, and announce it in words.
- Move Expanded, HasPopup and Controls from the Group to the head control (today the head does not say Expanded).
- Add the modal presentation with header, OK / Cancel and input mode for touch hosts, and the full-screen range on compact.
- Add Today and Clear to the docked footer, minimum and maximum dates, and inline error messages.
- Let the range picker own which end a pick sets instead of leaving it to the caller.
