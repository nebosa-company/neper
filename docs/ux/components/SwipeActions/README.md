# SwipeActions

Swipe actions put one to three quick actions behind a list row on touch hosts, revealed by swiping the row sideways, with the same actions on hover and in the context menu everywhere.

## Anatomy
1. Row: a Row that slides horizontally over its actions, on `surface`.
2. Trailing actions (swipe left): up to three action tiles at the row's end, each an icon over a `label-medium` label.
3. Leading action (swipe right): one action tile at the row's start.
4. Action tile: 80 wide, the row's height, filled with its role colour: neutral `secondary-container`, accent `primary`, destructive `error`, each with its `on-` pair.
5. Full-swipe action: the outermost action stretches to fill the row as the swipe passes 60% of the width.
6. Hover actions (pointer hosts): the same actions as 32 icon buttons at the row's end on hover and focus.

## Variants and when to use
| Variant | Use for |
|---|---|
| Trailing actions | Per-row actions such as Archive and Delete in inboxes, notifications, build queues. |
| Leading action | One reversible toggle: Mark read, Pin, Flag. |
| Full swipe | The one action people repeat all day on that list (Archive, Delete); only when it is undoable. |

Put actions in the row's trailing icon button or a Menu when there are more than three, when they need confirmation before they run, or when the list is on a pointer-only host. Use List's multi-select for bulk actions. Never hide the only way to do something behind a swipe.

## Specs
| Part | Value |
|---|---|
| Action tile | 80 wide, full row height; `icon-md` 24 above a `label-medium` label, `space-1` 4 apart, centred |
| Neutral | `secondary-container` / `on-secondary-container` |
| Accent | `primary` / `on-primary` |
| Destructive | `error` / `on-error`; always the outermost trailing tile |
| Reveal stop | the sum of the tile widths (160 for two) |
| Open threshold | 40% of the reveal stop, or a fling faster than 500 px/s |
| Full-swipe threshold | 60% of the row width; the outermost tile stretches, its content pinned to the far edge, `space-6` 24 in |
| Hover actions | icon buttons `control-sm` 32, `icon-sm` 18, `space-1` 4 apart, `on-surface-variant`, replacing the trailing meta |
| Settle | `duration-medium-1` with `ease-emphasized-decelerate`; close with `ease-standard` |

## States
- Rest: the row covers its actions; no hint on the row itself.
- Dragging: the row follows the finger 1:1 up to the reveal stop, then at 0.3x (rubber band) unless a full swipe is allowed.
- Revealed: the row rests at the reveal stop; tiles are focusable buttons; any other touch on the list closes it.
- Full swipe armed: past 60% the outermost tile stretches with a haptic tick; releasing commits it.
- Committed: a destructive commit slides the row out and collapses its height (`duration-short-4`, `ease-emphasized-accelerate`), then shows an Undo snackbar.
- Tile pressed: `state-pressed` layer in the tile's content colour. Tile focused: inset 3px ring.
- Hover (pointer): hover actions replace the trailing meta; they also show while the row has keyboard focus.
- Disabled action: not shown in the swipe (never a dead tile); in the hover set it is at 38%.

## Behaviour
- Touch: a horizontal drag that starts on the row reveals; vertical drags scroll the list. The gesture locks after 8 px.
- Only one row is revealed at a time; revealing another closes the first. Scrolling closes it.
- Pressing a revealed tile runs its action and closes the row. A committed destructive action is undoable for the snackbar's duration.
- Keyboard: the actions are also the row's context menu (Shift+F10, Menu key) and shortcuts: Delete deletes the focused row, E archives (if the app binds it). With the row revealed, Tab moves between tiles and Escape closes it.
- Pointer: hover actions; right-click opens the same set as a context menu. Trackpad two-finger horizontal swipe reveals on macOS, as in Mail.
- Screen readers get every action as a custom action on the row (see Accessibility).
- Reduced motion: no slide; the revealed state cross-fades in `duration-short-2`; commit removes the row with a fade.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Hover actions and the context menu; touchscreens may swipe (as WinUI SwipeControl); Delete key deletes. |
| macOS | Hover actions; two-finger trackpad swipe reveals as in Mail; Control-click menu; ⌘⌫ deletes. |
| Linux | Hover actions and the context menu; touch swipe only on touch devices. |
| Android | Swipe with full-swipe to archive or delete and an Undo snackbar; long press opens the menu. |
| iOS | Native trailing and leading swipe actions with full swipe and rubber band; destructive action on the outermost edge; long press shows the context menu with a preview. |
| Web | Swipe on touch (Pointer Events, `touch-action: pan-y` on the row); hover actions and a context menu with a pointer. |

## Accessibility
- The row is a list item; each action is a custom action on it ("Archive", "Delete", "Mark read"), so VoiceOver's actions rotor, TalkBack's actions menu and Narrator reach them without swiping.
- Revealed tiles are buttons named by their labels; hover actions are icon buttons named "Archive Ravi Okafor's message" (the action plus the row).
- Destructive commits announce "Deleted. Undo available" politely.
- Contrast: labels and icons on their fills hold 4.5:1 (`on-error` on `error`, etc.); colour is not the only cue: every tile has a label.
- Target: tiles are 80 wide by the row height (56 or more); hover icon buttons are 32 in a 32 target.
- Reduced motion as in Behaviour.

## Content
- Action labels: one verb, sentence case: "Archive", "Delete", "Mark read", "Pin".
- Undo snackbar: "Message deleted" with "Undo".
- The same words in the swipe, hover, menu and accessibility action.

## e.ui today
`collection.swipe_actions` shows the content with a plain "More" button; while `revealed` it swaps the button for the caller's actions as filled buttons side by side, revealed by a left swipe past a quarter of the width and hidden by a right swipe. Nothing slides. To reach this design:
- Put the actions behind the row as 80-wide tiles and slide the row over them, following the finger, with the open threshold, rubber band and full-swipe commit.
- Colour tiles by role (neutral, accent, destructive in `error`); today every action is Filled and two filled buttons sit with no gap.
- Close on Escape, on another touch, on scroll and after an action; today once revealed only a swipe right hides the actions, so keyboard and pointer users cannot close them.
- Replace "More" with hover icon buttons and the context menu on pointer hosts, and add the leading action.
- Expose every action as a custom accessibility action on the row.
- Create the swipe state on the first frame; today a swipe in that frame does nothing.
