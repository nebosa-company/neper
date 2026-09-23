# SplitView

A split view divides one area between two contents that trade space across a draggable divider, typically a list and its detail, and folds into a stack on compact windows.

## Anatomy
1. First pane: the list or source (`surface-container-low` when it is navigation, `surface` when both are content).
2. Divider sash: the Resizable pane's sash (8px hit, 1px `outline-variant` line, 4x48 grip on hover, focus and drag).
3. Second pane: fills the rest, `surface`.
4. Compact stack: the second pane pushed over the first with a top app bar and a back button.

## Variants and when to use
| Variant | Use for |
|---|---|
| List-detail (horizontal) | A collection and the selected item: builds, mail, files. Default. |
| Editor-output (vertical) | Two views of one task stacked: source above, preview or output below. |
| Fixed ratio with snap points | Comparisons (diff, before/after): snap at 1/3, 1/2 and 2/3. |

Use Resizable pane for one panel beside content that is not a peer (a sidebar); Navigation split for app-level navigation that becomes a drawer; Dock layout for three or more rearrangeable panes.

## Specs
| Part | Value |
|---|---|
| Default split | first pane 40% (list-detail) or 50% (editor-output) |
| Minimum first / second | 240 / 320 on pointer hosts; the view stacks when both minimums do not fit |
| Stack breakpoint | below `window-expanded` 840 for list-detail; below `window-medium` 600 for editor-output |
| Sash | 8 hit (pointer), 24 (touch); keyboard step `space-2` 8, Shift 48 |
| Divider | `divider` 1 `outline-variant`; dragged 2 `primary` |
| Grip | 4x48 `radius-full`; `outline` hover and focus, `primary` dragged |
| Pane padding | the caller's; lists run edge to edge, detail `space-4` 16 (`space-6` 24 on large) |
| Snap points | within 16px of a point the divider snaps with `ease-standard`, `duration-short-3` |
| Compact app bar | the Top app bar, 64 (56 dense), back `arrow-back` icon button |

## States
- Sash rest, hover, focus, dragged and locked exactly as the Resizable pane.
- Selected row in the first pane: `secondary-container` (List's selected row), kept while focus is in the detail.
- Empty detail (nothing selected): an Empty state centred in the second pane ("Select a build to see its log").
- Stacked: only one pane is visible; selection pushes the detail.

## Behaviour
- Dragging resizes both panes live; neither drops below its minimum. Double-click the divider to restore the default ratio.
- Keyboard: F6 moves focus between the panes; the sash is in the Tab order between them with the arrow, Shift, Home/End and Escape behaviour of the Resizable pane.
- Resizing the window keeps the ratio, not the pixel size, until a minimum binds.
- Crossing the stack breakpoint keeps the selection: the detail stays shown if an item was selected.
- Stacked: selecting pushes the detail in from the end edge over `duration-long-2` with `ease-emphasized-decelerate`; back (button, Escape, system back or edge swipe) pops it with `ease-emphasized-accelerate`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense list rows; the divider is a thin line; F6 cycles panes; stacked views use the title bar's back button. |
| macOS | NSSplitView thin divider; the detail's toolbar items sit above the second pane; stacked is rare (windows are wide). |
| Linux | GNOME: Adwaita split views collapse to a navigation view with a header-bar back button; KDE: a column view. |
| Android | Stacked on compact; list-detail on medium and up with the 24 touch handle; predictive back previews the pop. |
| iOS | UISplitViewController behaviour: stack on compact width with an edge-swipe back, side-by-side on regular width. |
| Web | Stacked uses history: each push adds a history entry so the browser's back pops it. |

## Accessibility
- Each pane is a region named by its content ("Builds", "Build 4128"). The sash is a separator with value, range and a name ("Resize build list").
- Focus moves into the detail only when the person asks (Enter on a row or tapping it on touch); arrowing through the list updates the detail without stealing focus.
- In a stack, the pushed view takes focus on its title; back returns focus to the row that opened it.
- Reduced motion: push and pop cross-fade in 100ms.

## Content
Name panes for screen readers after what they show, not their position ("Builds", not "Left pane"). The empty detail tells people what to do: "Select a build to see its log".

## e.ui today
`control.split_view` builds `first` in a resizable pane at `position`, a `space-xs` handle filled in `border`, and `second` filling a fixed `width` by `height` box. To reach this design:
- Use the redesigned Resizable pane sash, with hover, focus and dragged looks (today it draws no focus).
- Name the separator from the caller (the name is the literal "Divider"), and publish its value and range.
- Size from the parent, keep a ratio across window resizes, and add snap points and double-click reset.
- Stack below the breakpoint into a push navigation with a back button, and keep the selection across the switch.
- Add F6 pane cycling and an empty-detail slot.
