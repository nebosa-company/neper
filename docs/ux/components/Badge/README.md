# Badge

A badge is a small mark on an icon or at the end of a row that says something waits there: a dot for "new", a number for how many; its sibling, the status label, names a state in one word.

## Anatomy
1. Container: a pill, `radius-full`; a 6 px disc for the dot.
2. Count: `label-small`, 1-3 characters, centred.
3. Anchor: the icon (or avatar) it sits on; the badge overlaps the icon's top end corner.
4. Status label (tag): `radius-xs` container, optional 14 px icon, `label-medium` word.

## Variants and when to use
| Variant | Container / content | Use for |
|---|---|---|
| Dot | `error`, 6 px | Something new or changed, when the count does not matter: a new notification, an update ready. |
| Count, urgent | `error` / `on-error` | Items that need the person's action: unread mentions, failed builds, review requests. The default. |
| Count, emphasis | `primary` / `on-primary` | Non-urgent counts that still invite a look: new comments in a thread. |
| Count, neutral | `surface-container-highest` / `on-surface-variant` | Plain totals in a list: 128 files. Often just a trailing Text. |
| Status label | `*-container` / `on-*-container` + icon + word | A state: Passed, Flaky, Failed, Queued, New. |

A badge never takes a press; the thing it sits on does. For a dismissible or selectable token use Chip. For a message use Banner or Snackbar.

## Specs
| Part | Value |
|---|---|
| Dot | 6 × 6, anchored with its centre 3 px in from the icon's top end corner |
| Count | 16 tall, minimum 16 wide, padding 0 `space-1` 4, `label-small` 11/16 |
| Count anchor | top -2, start at icon width - 12 (overlaps the icon's corner) |
| Maximum | "99+" (3 characters incl. the plus); pass the real count to accessibility |
| Ring | none on `surface`; a 2 px ring in the ground colour when the icon sits on a tonal pill or image |
| Inline (row) | trailing, vertically centred, `space-3` from the label |
| Status label | 24 tall, `radius-xs` 4, padding 0 `space-2` 8, gap `space-1` 4, `label-medium` 12/16, icon 14 |
| Status label colours | success, warning, error, tertiary (new) and secondary (neutral) containers with their `on-*-container` |

## States
- Appear: scales from 0 to 1 over `duration-short-3` with `ease-emphasized-decelerate`.
- Change: the number cross-fades in `duration-short-2`; the pill's width animates with `ease-standard`.
- Disappear: scales to 0 over `duration-short-2` with `ease-emphasized-accelerate`.
- Disabled anchor: the badge hides (a disabled destination has nothing to act on).
- A badge has no hover, focus or pressed state.

## Behaviour
- The count clears when the person has seen the items (opened the destination), not when they hover.
- Counts above 99 show "99+"; above 999 in a neutral count use "1.2k".
- Only one badge per anchor. A dot and a count never appear together.
- On a navigation item the badge anchors to the icon inside the indicator pill, so it stays put when the item is selected.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Mirror the app's total into the taskbar overlay badge (the count glyph) when the window is minimised. |
| macOS | Mirror the total into the Dock tile badge; macOS menu bar extras use a dot. |
| Linux | Mirror into the launcher count (Unity/KDE `com.canonical.Unity.LauncherEntry`) where the desktop supports it. |
| Android | Launcher badge follows the notification channel; in-app badges as here. |
| iOS | App icon badge through the notification settings; tab bar badges use this count style (UITabBarItem badge) in `error`. |
| Web | Optionally mirror into the page title ("(3) Builds") and the favicon dot. |

## Accessibility
- The badge is not a separate node; its meaning is appended to the anchor's name: "Builds, 2 failed", "Activity, new", "Terminal, more than 99".
- Status labels are Text with the word; the icon is decorative.
- Count changes are announced politely only when the person caused them or when urgent; otherwise the next focus reads them.
- Contrast: `on-error` on `error` 4.5:1; the dot 3:1 against the anchor's ground.
- Status is never colour alone: counts have numbers, dots have the name suffix, labels have a word.
- Reduced motion: appear and disappear without scaling.

## Content
- Counts are numerals. No words in a count badge.
- Status labels are one word or two, sentence case: "Passed", "Needs review". No trailing period, no ALL CAPS.
- The accessible suffix says what the number counts: "2 failed", not "2".

## e.ui today
`control.badge` draws `value` in the Caption role and `on-primary` on a `primary` pill with `space-xs` padding, as a Status-role node labelled by the value. To reach this design:
- Add the dot and the three count kinds (urgent `error`, emphasis `primary`, neutral) and make urgent the default; today every badge is `primary`.
- Fix the count to 16 tall with `label-small`, and cap it at "99+".
- Anchor it to an icon (a `badge_anchor` or a badge option on `icon_button` and the navigation items) instead of laying it out beside the name.
- Split one-word states out into the status label (tag) with an icon.
- Fold the badge into its anchor's accessible name instead of a separate Status node that reads just "3".
