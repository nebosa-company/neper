# ReorderableList

A reorderable list is a list whose rows the person drags, or moves by keyboard, into the order they want: build steps, priorities, a playlist.

## Anatomy
1. List: a List of one- or two-line rows.
2. Drag handle: `drag-handle` icon, `icon-md` 24 in `on-surface-variant`, trailing on touch, leading on pointer hosts, in a 48 (touch) or 32 (pointer) target.
3. Lifted row: while dragged, `surface-container-high`, `elevation-4`, `state-dragged` layer, `radius-sm` corners, inset `space-2` from the list edges.
4. Gap: the space the lifted row will land in, opened by the other rows moving; `surface-container-low`.
5. Drop line (pointer hosts, long lists): 2px `primary` with an 8 ring at its start, `space-4` inset, between the rows where the drop lands.
6. Moving tag (keyboard): a `nu-tag` "Moving" on the picked-up row.

## Variants and when to use
| Variant | Use for |
|---|---|
| Handle-only | Lists whose rows also open or select on tap: only the handle starts a drag. The default. |
| Whole-row drag | Lists that exist only to be ordered (a priority ranking): a press anywhere on the row lifts it after a long press on touch, immediately with a pointer. |
| Edit mode (iOS style) | Lists that are normally read-only: an Edit button reveals handles (and delete controls); Done hides them. |

Use a plain List when order is fixed or sorted. Use Header row's column drag to reorder table columns. Use Tree drag and drop to move items between parents.

## Specs
| Part | Touch | Pointer (density -1) |
|---|---|---|
| Row | Row specs, one line 56, two line 72 | 48 / 64 |
| Handle | `icon-md` 24 in a 48 target, trailing | `icon-md` 24 in a 32 target, leading, shown on row hover and focus |
| Lifted row | `surface-container-high`, `elevation-4`, `state-dragged` (16%), `radius-sm` 8, inset `space-2` | same |
| Lift | scale 1.02 and 4 up, `duration-short-3`, `ease-standard` | no scale |
| Gap | the row's height, `surface-container-low` | same, or the drop line in lists longer than a screen |
| Drop line | `outline-focused` 2 `primary`, an 8 ring at the start, `space-4` inset | same |
| Auto-scroll | starts 48 from the viewport's edge, speed rising to 1 screen per second | same |
| Long press to lift | 400ms, with a haptic tick | not used |

## States
- Rest: handles visible (touch) or hidden until hover (pointer).
- Hover on a row (pointer): the handle appears; hover on the handle shows the grab cursor.
- Focus: the row's inset ring; the handle has no separate tab stop.
- Lifted: as Anatomy 3; other rows animate out of the way in `duration-short-4` with `ease-standard`.
- Picked up by keyboard: the row takes the lifted look plus the Moving tag, and keeps its focus ring.
- Dropped: the row settles into the gap over `duration-short-4` (`ease-emphasized-decelerate`) and loses its shadow.
- Cancelled (Escape, or a drop outside the list): the row returns to its origin with the same motion.
- Disabled (the order is locked): handles are hidden and the list reads as a plain List.

## Behaviour
- Pointer: press on the handle and move 4 px to lift; the row follows the pointer on the vertical axis only; release to drop. With whole-row drag, the row lifts after 4 px of movement.
- Touch: press the handle and move to lift (no long press needed on the handle); whole-row drag lifts after a 400ms long press.
- Keyboard: Space (or Ctrl+Up/Down directly) picks up the focused row; Up and Down move it one place; Home and End move it to the first and last place; Space or Enter drops; Escape cancels and returns it.
- Context menu on every row: Move up, Move down, Move to top, Move to bottom, so the order can change without dragging.
- The list reports one move `{ from, to }` on drop, never during the drag; a drop at the origin reports nothing.
- Auto-scroll when the lifted row nears the viewport's edge.
- Reduced motion: rows jump to their new places without sliding; the lifted row keeps its shadow but does not scale.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer metrics; leading handle on hover; drag uses the system drag threshold; Alt+Shift+Up/Down also move, per Office convention. |
| macOS | Pointer metrics; rows drag directly from anywhere in source lists (no handle), with the drop line as in Finder sidebars; ⌘⌥Up/Down move. |
| Linux | Pointer metrics; GNOME uses a leading `drag-handle` in boxed lists; the drop line shows between rows. |
| Android | Touch metrics; trailing handle; haptic tick on lift and on each place change. |
| iOS | Touch metrics; Edit mode reveals trailing reorder handles (and leading delete controls); lifted rows scale slightly. |
| Web | Pointer or touch metrics by input; Pointer Events with `touch-action: none` on the handle; the keyboard model above with a live region. |

## Accessibility
- Role list (or listbox) as List; each row has custom actions Move up, Move down, Move to top, Move to bottom, exposed to Narrator, VoiceOver, TalkBack and Orca.
- The handle is decorative in the tree (the row carries the actions); its hit target still meets 48 touch, 32 pointer.
- Announce on pick up ("Compile, picked up, position 2 of 4"), on each move ("Moved to position 3 of 4") and on drop or cancel ("Compile, dropped at position 3 of 4" / "Move cancelled"), in a polite live region.
- Nothing is drag-only: the context menu and the keyboard give the same result.
- Contrast: the handle in `on-surface-variant` holds 3:1; the lifted row's content keeps 4.5:1 on `surface-container-high`.
- Reduced motion as in Behaviour.

## Content
- Row names are the things being ordered; do not number them in the headline (the position is announced and changes).
- Menu items: "Move up", "Move down", "Move to top", "Move to bottom".
- Announcements: "Compile, moved to position 3 of 4".

## e.ui today
`collection.reorderable_list` stacks the caller's fixed-`extent` rows, each a focusable drag region; a drop reports `Reorder { from, to }` from the pointer's y, and Alt+Up and Alt+Down move by one. Nothing is drawn during a drag. To reach this design:
- Draw the drag: lift the row (`surface-container-high`, `elevation-4`, `state-dragged`), open the gap as the others move, show the drop line in long lists, and settle on drop.
- Add drag handles (trailing on touch, leading on hover with a pointer) and the handle-only and whole-row variants.
- Add the keyboard pick-up model (Space, arrows, Home, End, Escape) alongside the direct Ctrl+Up/Down move.
- Expose Move up, Move down, Move to top and Move to bottom as accessibility actions and context-menu items; today the move is reachable only by pointer or Alt+arrows.
- Paint the focus ring on the focused row, add auto-scroll near the edges, and announce every move.
