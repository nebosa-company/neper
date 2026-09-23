# Snackbar

A snackbar briefly confirms the result of something the person just did, with at most one action such as Undo; its desktop sibling, the toast, reports background events at the window's top end.

## Anatomy
1. Snackbar container: `inverse-surface`, `radius-xs`, 48 min, `elevation-3`, up to 560 wide.
2. Message: `body-medium` in `inverse-on-surface`, one or two lines.
3. Action (optional): a text button in `inverse-primary`.
4. Close (optional): an icon button with `close` in `inverse-on-surface`.
5. Toast container: `surface-container-high`, `radius-md`, `elevation-3`, 340 wide.
6. Toast parts: a 32 status well with an icon, a `title-small` title, a `body-medium` message in `on-surface-variant`, one or two text-button actions, and a close button.

## Variants and when to use
| Variant | Where | Use for |
|---|---|---|
| Snackbar | bottom | The outcome of the person's own action: "3 files moved to Trash. Undo". |
| Snackbar, two lines | bottom | A result that needs a sentence of reason; the action moves under the text. |
| Toast | top end, desktop | Events that happen while the person does something else: a build finishing, a download done. |

Use a Banner for conditions that persist until resolved (offline, licence expiring), a Dialog when a decision is needed now, and the Notification list for history. Never put errors that block work in a snackbar only.

## Specs
| Part | Snackbar | Toast |
|---|---|---|
| Size | min height 48 (68 two-line); width 288 to 560, compact: window width less 2x16 | 340 wide (300 min) |
| Padding | `space-4` 16 start, `space-2` 8 end, `space-1` 4 vertical | `space-3` 12 vertical, `space-4` 16 start, `space-2` 8 end |
| Shape / elevation | `radius-xs`, `elevation-3` | `radius-md`, `elevation-3` |
| Colours | `inverse-surface` / `inverse-on-surface`; action `inverse-primary` | `surface-container-high` / `on-surface`; message `on-surface-variant`; well in the status container pair |
| Type | `body-medium` | title `title-small`, message `body-medium` |
| Action | text button 40 (`label-large`), `space-2` from the text | text buttons `sm` 32 |
| Placement | compact: bottom centre, 16 above the navigation bar or FAB; medium and up: bottom start, 24 from the edges | top end, 12 below the title bar, 12 from the edge; stack 8 apart, newest on top, max 3 |
| Timeout | 4 s text only; 7 s with an action; none while hovered or focused | 6 s; none with actions until dismissed or hovered away |

## States
- Enter: fades and rises 8 from the edge over `duration-medium-1` with `ease-emphasized-decelerate`.
- Rest: counting down; hover or keyboard focus pauses the timer.
- Action focus: the text button's focus ring (drawn in `focus-ring`, which holds 3:1 on `inverse-surface`).
- Replaced: a new snackbar replaces the current one after it leaves (`duration-short-4`, `ease-emphasized-accelerate`); they never stack.
- Toast severity: the well uses `success-container`, `warning-container`, `error-container` or `primary-container`, with the matching icon.

## Behaviour
- One snackbar at a time; queued ones follow in order. Toasts stack up to 3; older ones collapse into "2 more notifications".
- Pressing the action runs it and dismisses. The close button, Escape (while focus is inside), a swipe sideways (touch) or the timeout dismiss.
- Snackbars do not take focus. F6 (Windows, Linux) or ⌃F6 moves focus into the newest snackbar or toast; after dismissal focus returns where it was.
- Keep a snackbar above the FAB, navigation bar and on-screen keyboard; the FAB moves up to make room on compact.
- Timeouts extend to at least 10 s when the host's accessibility setting asks for longer notification times; an action's snackbar with a screen reader running does not time out.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Snackbar bottom start in the window; background events go to a system toast (Windows notification) when the window is not focused, the in-app toast when it is. |
| macOS | In-app snackbar bottom centre of the window's content; background events use a system notification (UserNotifications) when inactive, the in-app toast otherwise. |
| Linux | Snackbar as Adwaita toast (bottom centre, `radius-xs`); background events through the desktop notification service when unfocused. |
| Android | Snackbar bottom, above the navigation bar; swipe to dismiss; background events are system notifications. |
| iOS | No snackbar idiom: show a small banner-style HUD at the top for confirmations with Undo, and use shake-to-undo; background events are system notifications. |
| Web | `role="status"` region for snackbars, `role="alert"` for error toasts; placement as desktop on pointer layouts, compact on touch. |

## Accessibility
- The snackbar region is a status (polite live region); its text is read when it appears, followed by the action's name ("3 files moved to Trash. Undo, button").
- Error toasts use an alert (assertive). Everything else is polite.
- The action must also be reachable elsewhere (Undo in the Edit menu, Ctrl+Z), because the snackbar may disappear.
- Contrast: `inverse-on-surface` and `inverse-primary` on `inverse-surface` meet 4.5:1 in every theme.
- Reduced motion: fade in and out over 100ms without the rise.

## Content
State the result in the past tense, short: "Settings saved", "3 files moved to Trash". One action, a verb: "Undo", "View", "Retry". No "OK" or "Dismiss" as the action (use the close button). Toast titles name the event ("Build 4128 passed"); the message adds one fact.

## e.ui today
`control.snackbar` and `control.toast` show the head of the caller's `Notice` queue in a `text`-filled `radius-sm` sheet with no shadow, Body text in `on-primary`, a Plain action and a Plain close labelled "x"; the margin is lost to the window clamp (toast flush right, snackbar flush bottom-left), and `primary` action labels sit on a `text` ground. To reach this design:
- Draw the snackbar in `inverse-surface` / `inverse-on-surface` with the action in `inverse-primary`, `radius-xs`, `elevation-3`.
- Fix placement: apply the offsets after clamping so the snackbar sits 16 above the bottom (centred on compact, start on desktop) and the toast 12 in from the top end.
- Make the toast its own design: `surface-container-high`, `radius-md`, status well, title, message and actions.
- Replace the "x" with a `close` icon button named "Dismiss"; add timeouts that pause on hover and focus, and F6 to reach it.
- Add enter and exit motion, two-line layout, and the one-at-a-time queue for snackbars and a stack of 3 for toasts.
