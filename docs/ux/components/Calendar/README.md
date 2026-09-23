# Calendar

A calendar shows one month as a grid of days under a month header, for choosing a date or a range inline when the date is the point of the view (scheduling, booking, a report period); it is also the body of the date picker.

## Anatomy
1. Month header: the month and year as a text button with `chevron-down` (opens the year view), then Previous and Next month icon buttons at the end.
2. Weekday row: one narrow label per column (M T W, or Su Mo Tu on pointer hosts), starting on the locale's first day of the week.
3. Week-number column (optional): ISO or locale week numbers at the start.
4. Day cell: a circular disc the size of the cell, the digits centred.
5. Today marker: a 1px `primary` ring and `primary` digits.
6. Selection: a `primary` disc with `on-primary` digits.
7. Range band: `primary-container` between the two ends, half a cell under each end disc.
8. Event dot (optional): a 4 `tertiary` dot under the digits.
9. Year view: a 3-column grid of year pills replacing the days.

## Variants and when to use
| Variant | Use for |
|---|---|
| Single date | Pick one day inline: a due date on a planning page. |
| Range | Pick a span: a report period, a leave request. The first press sets the start, the second the end. |
| With week numbers | Planning tools where people talk in weeks (Wk 38). Pointer hosts. |
| With event dots | When days carry content (builds, meetings); the dot is a hint, the day's content is shown elsewhere. |

Put the calendar behind a field with Date picker when the date is one input among others. Use a List or Table for a schedule with content per day.

## Specs
| Part | Touch | Pointer (density -1) |
|---|---|---|
| Cell and disc | 40 by 40 (`control-md`); 48 target with row gap | 32 by 32 (`control-sm`) |
| Row gap | `space-1` 4 | 0 |
| Grid width | 7 x 40 = 280 (+40 with week numbers) | 7 x 32 = 224 (+32) |
| Header height | 48 (`control-lg`) | 32, with 8 below |
| Month button | text button, `label-large` in `on-surface-variant`, `chevron-down` 18 | `title-small` label in `on-surface` (no year view button on Windows; see Platform) |
| Previous / Next | icon buttons 40, `chevron-left` / `chevron-right` in `on-surface-variant` | icon buttons 32, icons 18 |
| Weekday labels | `label-medium` in `on-surface-variant` | `label-medium` in `on-surface-variant` |
| Week numbers | `label-small` in `on-surface-variant` | same |
| Day digits | `body-medium` in `on-surface` | 13px `body-medium` |
| Today | 1px ring in `primary`, digits `primary` | same |
| Selected | disc `primary`, digits `on-primary` weight 600 | same |
| Range band | `primary-container`, digits `on-primary-container` | same |
| Event dot | 4 in `tertiary`, 4 above the cell bottom | same |
| Year pill | 72 by 36, `radius-full`, `body-large` in `on-surface-variant`; selected `primary` / `on-primary` | 64 by 32 |

## States
- Day rest, hover (`on-surface` layer at `state-hover` on the disc), focus (`state-focus` layer plus the focus ring on the disc, offset 0 so it stays in the cell), pressed (`state-pressed`).
- Today, selected, range start and end, in range, as above; selected wins over today (the ring is dropped).
- Unavailable (before the minimum, after the maximum, or excluded): digits at `on-surface` 38%, no state layer, skipped by arrow keys only when the whole week is unavailable.
- Days of the neighbouring months are not drawn; the cells stay empty so weeks stay aligned.
- Range in progress: after the first press, hovering a later day previews the band in `primary-container` at 50%.

## Behaviour
- Pointer and touch: press a day to select it; in range mode, the first press sets the start, the second the end (a second press before the start restarts the range). Swipe left and right on touch to change month.
- Keyboard: the grid has one tab stop, the focused day (selected, else today, else the first available). Arrows move by a day and a week and cross into the next or previous month; Home and End go to the start and end of the week; Page Up and Page Down change the month, with Shift the year; Enter and Space select.
- Header: Previous and Next change the month; the month button toggles the year view, where arrows move by a year and by a row, Enter picks the year and returns to the days.
- Changing month keeps the focused day's number (clamped to the month's length).
- Motion: month changes slide the grid horizontally over `duration-medium-2` with `ease-standard` (direction follows Next or Previous); the year view cross-fades over `duration-short-4`. Reduced motion: cross-fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | 32 cells, Sunday or Monday first from the region settings; the CalendarView idiom: the header text steps up to year and decade views on press. Week numbers optional. |
| macOS | 32 cells in the style of the graphical `NSDatePicker`; the header shows month and year with ‹ › and a today dot button; Monday or Sunday from the locale. |
| Linux | 32 cells; GTK Calendar shows month and year with separate steppers; week numbers optional. |
| Android | 40 cells, touch density; month swipe; the year view as specified. |
| iOS | Use the native inline calendar (`UIDatePicker .inline`) or ours at 40 cells; month-and-year chooser is a wheel. |
| Web | Ours in a `role="grid"`; first day from `Intl.Locale.getWeekInfo()` where available. |

## Accessibility
- Role Grid labelled with the month and year ("September 2026"); rows are Rows; weekday labels are ColumnHeaders with full names ("Monday"); each day is a GridCell holding a Button.
- A day's name is the full date ("Friday, 25 September 2026"), not its digits; it reports Selected, Current (today) and Disabled (unavailable).
- Previous and Next are named "Previous month" and "Next month"; the month button reports Expanded while the year view is open.
- Screen readers announce the new month on change (polite) and the range as it forms ("Start date, 14 September", "End date, 18 September, 5 days").
- Contrast: digits 4.5:1 on the surface they sit on; `on-primary` on `primary`; the today ring 3:1.
- Targets: 40 cells with 4 row gaps reach 44 on touch; 32 on pointer hosts.
- Reduced motion: cross-fade.

## Content
- Month header: the month name in full and the year ("September 2026"), formatted by the locale; never "2026-09".
- Weekday labels: the locale's narrow names on touch (M, T), short names on pointer hosts (Mo, Tu).
- A range summary under the grid when useful: "Sep 14 – 18 · 5 days", with an en dash.

## e.ui today
`overlay.calendar` lays out one month, Monday first, as rows of `hit-target` Plain day buttons under a header of `<`, `YYYY-MM` and `>`; the selected day is Filled, and in range mode the others between `from` and `to` take a `selection` fill. The Grid holds Buttons in unlabelled rows. To reach this design:
- Add the weekday header row and take the first day of the week from the locale; today there is no weekday row, so the Monday-first layout is invisible.
- Show the month name and year, name Previous and Next "Previous month" and "Next month" with chevron icons, and add the year view.
- Centre the digits in circular discs (they sit top-start today), mark today with a ring, and draw the range band with half-cell ends.
- Name each day by its full date and expose GridCells in Rows with ColumnHeaders instead of bare Buttons.
- Add roving keyboard focus (arrows, Home/End, Page Up/Down) and minimum/maximum/unavailable days.
- Add density: 40 cells on touch, 32 on pointer hosts.
