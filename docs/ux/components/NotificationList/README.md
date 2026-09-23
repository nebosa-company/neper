# NotificationList

A notification list is the history of an app's notices, grouped by day, where people review, act on and dismiss what they missed: failed builds, review requests, releases.

## Anatomy
1. Panel: `surface-container-low`, `radius-md` (square when docked full height), 380 wide.
2. Header bar: 56 tall, "Notifications" in `title-medium`, a "Mark all read" text button, and a settings icon button.
3. Group header: "Today", "Yesterday", "Earlier" in `label-medium` `on-surface-variant`.
4. Notification row: leading status well (40) or avatar, title, message, time, optional actions, trailing unread dot or dismiss button.
5. Unread marker: title weight 600 and an 8 `primary` dot; read rows use weight 400 and no dot.
6. Empty state: the compact Empty state ("You're all caught up").

## Variants and when to use
| Variant | Where | Use for |
|---|---|---|
| Flyout | from a bell icon button in the app bar or title bar | Desktop apps; 380 wide, max 560 tall. |
| Side sheet | docked at the end edge, full height | Expanded windows where people keep it open. |
| Full screen | pushed page | Compact windows (a destination in the navigation bar or behind the bell). |

Use Snackbar or Toast to show a new notice as it happens, a Banner for an unresolved condition, and an Activity log (a Table or List) for audit history people search.

## Specs
| Part | Value |
|---|---|
| Panel | `surface-container-low`, `radius-md` (flyout, `elevation-2` when floating), 380 wide (320 to 420) |
| Header | 56 (`control-xl`), `space-4` 16 start, `space-2` 8 end; title `title-medium`; divider 1px `outline-variant` below |
| Group header | `label-medium`, `on-surface-variant`, padding `space-2` 8 top, `space-4` 16 sides, `space-1` 4 bottom |
| Row | min 72; padding `space-3` 12 vertical, `space-4` 16 start, `space-2` 8 end; gap `space-3` 12 |
| Leading | status well 40 (`success-container`, `warning-container`, `error-container`, `primary-container` pairs) or `nu-avatar` 40 |
| Title | `title-small` (600) unread, `body-medium` weight 400 read; `on-surface` |
| Message | `body-medium`, `on-surface-variant`, 2 lines max |
| Time | `body-small`, `on-surface-variant` |
| Actions | up to 2 text buttons `sm` 32, `space-1` below the time |
| Unread dot | 8, `primary`, trailing |
| Dismiss | `close` icon button 32 on hover and focus (always shown on touch as swipe instead) |

## States
- Row hover `state-hover` (and the dismiss button appears), pressed `state-pressed`, focus `state-focus` plus the inset ring.
- Unread / read: weight and dot, and "Unread" in the accessible name. Opening a row or its action marks it read.
- Severity: the well's icon and colour and the title's words ("failed"); never the colour alone.
- Empty: compact Empty state in the panel.
- Loading older: Skeleton rows at the end; "Couldn't load older notifications. Retry" if it fails.
- Grouped: 3 or more notices from one source in a day collapse to one row "4 builds failed" that expands.

## Behaviour
- Press a row to open its target (and mark it read); actions run in place and leave the panel open.
- Dismiss by the close button, Delete on a focused row, or swipe sideways on touch (with a snackbar "Notification dismissed. Undo").
- "Mark all read" marks visible and older notices; there is no "Clear all" without Undo.
- Keyboard: Up/Down move between rows (groups are skipped), Tab moves into a row's actions, Home/End, Escape closes a flyout and returns focus to the bell.
- New notices insert at the top with a `duration-medium-1` `ease-emphasized-decelerate` slide; the list does not jump if the person has scrolled.
- The flyout opens with the Menu motion (`duration-medium-1`), closes with `duration-short-4`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Flyout from a bell in the title bar; app notices also go to the Windows notification centre, and dismissing in one clears the other where the API allows. |
| macOS | Flyout (popover) from a toolbar bell; system notifications live in Notification Center; do not duplicate its look. |
| Linux | Flyout; the desktop's notification daemon handles system banners; GNOME uses a popover from the header bar. |
| Android | Full-screen page on compact; swipe to dismiss; system notifications stay in the shade. |
| iOS | Full-screen page pushed from a bell; swipe actions trailing (Dismiss) and leading (Mark read). |
| Web | Flyout on pointer layouts, full page on compact; the panel is a `region` with a list of `article`s. |

## Accessibility
- The panel is a region named "Notifications" with the unread count ("Notifications, 2 unread"); rows are list items or articles named by title, with "Unread" and the severity in the name ("Unread, error, Build 4128 failed on Linux").
- The bell button's name includes the count ("Notifications, 2 unread").
- New notices are announced politely only when the panel is open; otherwise the snackbar or toast announces them.
- Rows at least 72 tall; actions 32 with a pointer, 48 on touch.
- Reduced motion: new rows appear without sliding.

## Content
Titles state the event with its subject: "Build 4128 failed on Linux", "Ada requested your review". The message adds the most useful fact ("3 tests failed in e.fs"). Relative times up to a week ("12 min ago", "Yesterday"), dates after. Actions are verbs ("View log", "Retry").

## e.ui today
`control.notification_list` stacks an Outlined "Clear all" button above a bordered, clipped viewport of one-line rows (Body text, a Plain action, a Plain close labelled "x"); rows overflow the border so the close touches it, an empty list is an empty box, and "Clear all" and "x" are English literals. To reach this design:
- Draw the panel on `surface-container-low` with a header bar (title, Mark all read, settings) instead of a bare button, and size rows inside the border.
- Redesign rows: status well or avatar, title/message/time, up to two actions, unread dot, dismiss on hover; add group headers by day.
- Add read/unread state, severity with icon and words, the compact empty state and loading older rows.
- Replace "Clear all" with "Mark all read" plus per-row dismiss with Undo; name the dismiss button "Dismiss" and localise both.
- Add keyboard navigation, the flyout, side-sheet and full-screen presentations, and the unread count in the region's name.
