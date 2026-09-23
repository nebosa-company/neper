# PullToRefresh

Pull to refresh lets the person reload a feed or list by dragging down past its top on touch hosts, with a visible Refresh command as the equivalent everywhere else.

## Anatomy
1. Scroll container: the list or feed being refreshed.
2. Indicator: a 40 circle on `surface-container-high` with `elevation-2`, centred, that slides down from under the top edge with the pull.
3. Arc: a 2.5 stroke `primary` arc inside the indicator; it grows with the pull (to 80% at the threshold), then spins while refreshing.
4. Armed look: past the threshold the indicator fills `primary-container` with an `on-primary-container` arc, so the state change reads by fill as well as length.
5. Content offset: the content moves down with the pull, at a damped rate.
6. Refresh command: a Refresh icon button in the app bar or toolbar, and a keyboard shortcut; on pointer hosts it is the only way.
7. Result: new rows appear in place with a "New" tag, and a snackbar counts them if they are out of view.

## Variants and when to use
| Variant | Use for |
|---|---|
| Pull gesture (touch) | Feeds, inboxes, build lists on Android, iOS and touch Web, where content changes on a server. |
| Refresh command (pointer) | The same lists on Windows, macOS, Linux and desktop Web: a toolbar button plus F5 / Ctrl+R / ⌘R, with a linear progress under the bar. |

Do not use pull to refresh for content that updates by itself (show a Snackbar or a "3 new builds" chip instead), for lists that are not at the top of a scroll container, or for anything that is not a reload (never pull to create or to go back).

## Specs
| Part | Value |
|---|---|
| Indicator | `control-md` 40 circle, `surface-container-high`, `elevation-2` |
| Armed indicator | `primary-container`, arc `on-primary-container` |
| Arc | 24 box, r 8, 2.5 stroke, round caps, `primary`; opacity 60% until 50% of the threshold, then 100% |
| Threshold | 80 of pull (after damping), about 1.4x the indicator's travel |
| Resting position while refreshing | 12 below the container's top; content offset by 64 |
| Damping | content moves at 0.5x the finger past 40, capped at 1.5x the threshold |
| Toolbar button | icon button `control-md` 40 (32 dense), `refresh` icon, named "Refresh builds" |
| Desktop progress | linear `nu-progress` indeterminate under the bar, full width |
| New-row tag | `nu-tag` (secondary) "New", cleared after the person scrolls past or in 10 s |

## States
- Rest: nothing shows.
- Pulling: the indicator follows the finger down; the arc grows proportionally; releasing before the threshold springs everything back (`duration-short-4`, `ease-standard`).
- Armed: threshold crossed; the indicator fills `primary-container`; a haptic tick on Android and iOS.
- Refreshing: on release, the indicator settles at 12 and the arc spins (indeterminate, `ease-linear`); the content stays offset by 64 so it does not jump under the finger.
- Done: the indicator scales out (`duration-short-4`, `ease-emphasized-accelerate`), content returns, new rows appear with the tag; "1 new build" snackbar if the new rows are above the viewport.
- Nothing new: done as above; "Up to date" as a snackbar only if the refresh took longer than 2 s.
- Failed: the indicator leaves; a snackbar "Couldn't refresh. Check your connection" with Retry. Existing rows stay.
- Busy: while refreshing, another pull does nothing and the Refresh command is disabled (38%) and reports Busy.

## Behaviour
- The pull starts only when the container is scrolled to the very top and the drag is downward; otherwise it is a normal scroll. On iOS the pull continues from overscroll.
- Release past the threshold refreshes once; one refresh per pull.
- Programmatic refresh (on app resume after 5 minutes) shows the indicator at rest position without a pull.
- Refresh command: F5 and Ctrl+R (Windows, Linux, Web), ⌘R (macOS); on touch hosts the command also lives in the overflow menu for switch and screen-reader users.
- Focus stays where it was; new rows do not steal focus.
- Motion: indicator enters with the finger, leaves with `ease-emphasized-accelerate`; spinning is linear. Reduced motion: the arc does not spin (it shows a static 25% arc and the word "Refreshing" in the bar's subtitle); no content offset animation.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | No pull; toolbar Refresh button and F5 / Ctrl+R; linear progress under the command bar. Touchscreens may enable the pull (as WinUI RefreshContainer). |
| macOS | No pull; toolbar Refresh button and ⌘R; progress in the toolbar area. |
| Linux | No pull; header bar Refresh button and F5 / Ctrl+R. |
| Android | Pull gesture with this indicator (as SwipeRefreshLayout) and haptics; Refresh also in the overflow menu. |
| iOS | Pull with the native spinner (UIRefreshControl) placed above the content, which moves with the overscroll; haptic tick at the threshold. |
| Web | Pull on touch with `overscroll-behavior-y: contain` to disable the browser's own; the Refresh button everywhere; F5 is left to the browser, so use the button and Alt+R. |

## Accessibility
- The pull is never the only way: the Refresh command is always in the app bar or overflow menu, named "Refresh builds".
- While refreshing, the list reports Busy and a progress named "Refreshing builds" is in the tree; completion announces politely ("1 new build" or "Up to date"); failure announces assertively with the snackbar.
- Screen-reader users on iOS and Android get the Refresh action as a custom action on the list.
- The indicator is decorative apart from the progress role; it holds 3:1 against the content by its container and shadow.
- Target: the Refresh button is 48 on touch, 32 on pointer.
- Reduced motion as in Behaviour.

## Content
- Command: "Refresh" (with the noun in the accessible name: "Refresh builds").
- Results: counts, not adjectives: "1 new build", "12 new messages"; "Up to date".
- Failure: what and what to do: "Couldn't refresh. Check your connection".

## e.ui today
`collection.pull_to_refresh` draws a plain "Refresh" button above the content; a drag down past a third of the height fires `refresh` once, and a progress ring sits over the top edge while `refreshing`. Nothing follows the finger. To reach this design:
- Replace the always-visible Refresh text button with the indicator that tracks the pull (arc, threshold, armed fill, damping) on touch hosts, and a toolbar icon button with F5 / Ctrl+R / ⌘R on pointer hosts.
- Start the pull only at the top of the scroll container, with the 80 threshold rather than a third of the height.
- Disable the command while refreshing (today it stays enabled, so a second refresh can start mid-load) and report Busy.
- Create the pull state on the first frame (today a pull in that frame fires nothing).
- Take "Refresh" and "Refreshing" from the caller for localisation, and add the done, nothing-new and failed outcomes.
