# Sheet

A sheet is a surface anchored to an edge of the window that holds secondary content or a task beside the page: a bottom sheet on compact and touch windows, a side sheet on wider ones, either modal (over a scrim) or standard (living alongside the page).

## Anatomy
1. Container: `surface-container-low`; bottom sheets round their top corners `radius-xl`, modal side sheets round the open edge `radius-lg`; standard side sheets are square with a divider.
2. Drag handle (bottom sheets): 32 by 4, `on-surface-variant` at 40%, 16 from the top, inside a 48 target; it is a button that cycles the detents.
3. Header: the title in `title-large`, an optional Back icon button at the start and a Close icon button at the end (side sheets; bottom sheets close by dragging, the scrim or Back).
4. Content: lists, fields, controls, text; scrolls inside the sheet.
5. Actions (optional): a footer row after a divider, the main action filled then an outlined Cancel, start-aligned.
6. Scrim (modal only): `scrim` at 32%.

## Variants and when to use
| Variant | Use for |
|---|---|
| Bottom, modal | Choices and short tasks on compact windows: sort and filter, share targets, a flyout's or popover's content on touch. Blocks the page. |
| Bottom, standard | Persistent, glanceable content that coexists with the page: a running build, a now-playing bar, map results. Peeks, expands, never blocks. |
| Side, standard | Details or tools beside the main content on medium and expanded windows: file details, an inspector. Docked; the content narrows. |
| Side, modal | A secondary task on medium and up that should not lose the page: edit a target, filters with many fields. Over a scrim. |

Use Dialog for a short question that needs an answer, Action sheet for a list of actions about one thing on iOS, Navigation drawer for navigation (not content), and a full-screen dialog for a long form on compact.

## Specs
| Part | Bottom sheet | Side sheet |
|---|---|---|
| Size | full width up to 640 (centred above that); detents: peek (content-defined, 64 min), half, full minus 72 top | 256 min, 400 max width; full height |
| Container | `surface-container-low`; modal `elevation-3`, standard `elevation-1` | `surface-container-low`; modal `elevation-3`, standard `elevation-0` with a `divider` in `outline-variant` on the inner edge |
| Radius | `radius-xl` 28 top corners | modal `radius-lg` 16 on the open edge; standard 0 |
| Drag handle | 32 by 4, `radius-full`, `on-surface-variant` at 40%, 16 from the top, 48 target | none |
| Header | `title-large`, `space-4` 16 sides, 56 tall | 56 tall (48 on pointer hosts), `space-2` 8 start with Back, `space-4` without; Close at the end |
| Content padding | `space-4` 16 sides | `space-4` 16 sides (`space-6` 24 on expanded) |
| Actions | footer after a divider, `space-4` 16 padding, buttons `space-2` apart | same; 32 buttons on pointer hosts |
| Scrim | `scrim` at 32% (modal) | `scrim` at 32% (modal) |

## States
- Detents (bottom): peek, half, full. The sheet settles on the nearest detent after a drag.
- Scrolled: at full height the header gains a divider when the content scrolls under it.
- Drag: the handle shows `state-dragged` while held; the sheet follows the finger 1:1.
- Handle focus: the focus ring round the handle (offset 6, since the handle is tiny).
- Standard side sheet closed: the content takes the full width; a toolbar toggle reopens it with its selected state.
- Actions take their own states; the main action disables until the form is valid.

## Behaviour
- Opening: modal sheets open over the scrim from their edge; standard bottom sheets rise to peek; standard side sheets push the content aside.
- Touch: drag the handle or the header to move between detents; drag down past peek (or past half with velocity) to dismiss a modal sheet; content scrolling hands off to the sheet when it reaches its top.
- Keyboard: focus moves into a modal sheet (to the first control, else the handle) and is trapped; Escape closes it; the handle cycles detents with Enter or Space. A standard sheet is a landmark region reached with F6 or Tab and does not trap focus.
- Dismissal (modal): Escape, the scrim, Close, system back, or dragging down. With unsaved input, a dismissal asks to discard first.
- Focus returns to the control that opened a modal sheet.
- The on-screen keyboard pushes a bottom sheet's content up; the sheet never ends under it.
- Motion: enter over `duration-medium-4` with `ease-emphasized-decelerate` sliding from the edge (the scrim fades in with it); leave over `duration-short-4` with `ease-emphasized-accelerate`. Detent changes use `duration-medium-2` with `ease-standard`. Reduced motion: fade the sheet in place.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Side sheets, not bottom sheets. A standard side sheet is a pane with a splitter (resizable, 256-400); a modal side sheet slides from the end edge like the Settings panel. 48 headers, 32 buttons. |
| macOS | Side sheets as an inspector pane (standard) toggled from the toolbar. Do not confuse with the macOS sheet, which is a document-modal Dialog from the title bar. |
| Linux | GNOME: side sheets as a sidebar or `AdwBottomSheet` on narrow windows; KDE: a side pane. |
| Android | Bottom sheets at touch density; predictive back previews the dismissal; edge-to-edge with the navigation bar inset below the content. |
| iOS | Use native sheet presentation with detents (medium, large) and the grabber; standard sheets map to a non-modal sheet with the largest undimmed detent. |
| Web | Modal: `<dialog>` with `showModal()`; standard: a `complementary` region. Bottom sheets below 600 wide, side sheets from 600. Honour `prefers-reduced-motion`. |

## Accessibility
- Modal: role Dialog with the Modal state, labelled by the title; the page behind is inert. Standard: role Complementary (side) or Region (bottom), labelled.
- The drag handle is a Button named "Resize sheet" whose value is the detent ("half height"); its action cycles detents, so dragging is never the only way.
- Close and Back are icon buttons named "Close" and "Back".
- Screen readers announce the title on open and the detent when it changes.
- Contrast: text 4.5:1 on `surface-container-low`; the handle is decorative beside its accessible button.
- Targets: 48 for the handle and header buttons on touch; 32 on pointer hosts.
- Reduced motion: fade instead of slide.

## Content
- Title: what the sheet is about, a noun phrase: "Sort builds", "Build target", "Details".
- Standard bottom sheets lead with status in one line ("Building neper-compiler") and a detail line with numbers ("Stage 3 of 8: lowering · 41 s").
- Action labels as in Dialog: verbs for the outcome, "Cancel" to leave.

## e.ui today
`overlay.sheet` draws a square `surface` panel `width` wide along the right edge, full height, `elevation-3`, with a title row (title and a Plain `x` button) above the content; `overlay.bottom_sheet` does the same along the bottom, `height` tall. Both are modal Dialogs labelled by the title. To reach this design:
- Paint the 32% scrim for modal sheets (none today) and add a standard, non-modal presentation for both edges (a side pane that narrows the content, a peeking bottom sheet).
- Round the corners: `radius-xl` on a bottom sheet's top, `radius-lg` on a modal side sheet's open edge; today every panel is square.
- Repaint as `surface-container-low`, `title-large` titles, and replace the `x` glyph with a Close icon button named "Close".
- Add the drag handle, detents (peek, half, full) and drag-to-dismiss for bottom sheets, with the handle as a keyboard-operable button.
- Add an optional Back button and an actions footer; confirm before dismissing unsaved input.
