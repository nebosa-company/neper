# ResizablePane

A resizable pane is a panel whose size along one axis people set by dragging or nudging the sash at its edge, for sidebars, inspectors and bottom panels that share a window with the main content.

## Anatomy
1. Pane: the caller's content, sized along the axis, filling across it; `surface-container-low` when it is chrome (explorer, inspector), `surface` when it is content.
2. Sash: the 8px hit strip on the pane's inner edge (24 on touch).
3. Divider line: 1px `outline-variant`, centred in the sash; 2px `primary` while dragged.
4. Grip: a 4x48 `radius-full` pill centred on the line; hidden at rest with a fine pointer, always shown on touch.
5. Size readout: a plain Tooltip with the size while dragging (optional).
6. Focus ring round the grip.

## Variants and when to use
| Variant | Axis | Use for |
|---|---|---|
| Side pane | horizontal | Explorer, outline, inspector on the start or end edge. |
| Bottom panel | vertical | Terminal, output, problems under the editor. |
| Collapsible | either | A pane that snaps shut below its minimum and reopens from a toolbar button or a double-click on the sash. |

Use Split view when two contents share an area and trade space both ways (list and detail); use Dock layout for many panes that also rearrange. On compact windows, replace a side pane with a Navigation drawer or a Sheet.

## Specs
| Part | Pointer (Windows, macOS, Linux, Web) | Touch (Android, iOS, touch Web) |
|---|---|---|
| Sash width (hit) | 8, cursor `col-resize` / `row-resize` | 24 |
| Divider | 1px `outline-variant`; dragged 2px `primary` | none (panes separate by tone) |
| Grip | 4x48 `outline` on hover and focus, `primary` dragged | 4x48 `on-surface-variant` at rest; 12x52 `on-surface` pressed |
| Keyboard step | `space-2` 8 per arrow; 48 with Shift | n/a (arrows when a keyboard is attached) |
| Minimum pane size | caller's `low`, default 160; content never clips below it | 240 |
| Snap-to-close | below half of `low` | below half of `low` |
| Readout | `nu-tooltip` plain, `body-small`, 8 from the top, "240 px" | none |
| Pane padding | `space-3` 12 | `space-4` 16 |

## States
- Rest: only the 1px divider (pointer). No grip.
- Hover (sash): grip fades in over `duration-short-2`; the cursor changes to the resize cursor.
- Focus: grip shown with the 3px ring 2px outside it.
- Dragged: divider 2px `primary`, grip `primary`, readout shown; the content resizes live.
- At a limit: the sash stops; on the snap-to-close side the pane collapses with `ease-emphasized-accelerate`.
- Disabled (layout locked): no hover, no cursor change, not focusable.

## Behaviour
- Drag the sash to resize; the pane tracks the pointer 1:1, clamped to `low..high`, and the other side never drops below its own minimum.
- Double-click the sash: reset to the default size (or reopen a collapsed pane).
- Keyboard: the sash is in the Tab order after the pane's content. Left/Right (horizontal) or Up/Down (vertical) move it by 8, Shift by 48; Home and End go to `low` and `high`; Enter toggles collapse; Escape during a drag restores the size it had when the drag began.
- Sizes persist per window and per layout.
- Collapse and reopen animate width over `duration-medium-2` (`ease-emphasized-decelerate` to open, `ease-emphasized-accelerate` to close).

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | 8px sash, resize cursor, the divider line; F6 cycles focus between panes. |
| macOS | Thin 1px divider (NSSplitView thin style) with a 8px hit area; sidebars collapse by dragging past their minimum and reopen with the toolbar's sidebar button (⌃⌘S). |
| Linux | GTK Paned style: 8px sash, the grip dots are not drawn; F6 cycles panes. |
| Android | 24 target with the always-visible 4x48 handle (Material pane drag handle); pressing widens it to 12. |
| iOS | Same handle; sidebars in split views follow UISplitViewController and collapse into a stack on compact width. |
| Web | Pointer events with capture; `role="separator"` focusable; touch Web uses the touch column. |

## Accessibility
- The sash is role separator, focusable, orientation set, with value now/min/max in pixels or percent, name = "Resize" + the pane's name ("Resize explorer"). Actions Increment, Decrement, SetValue.
- Announce the new size on keyboard steps ("Explorer, 240 pixels").
- Target: 8 is below `target-pointer`, so the hit area extends 12px into each pane (32 total) where no other control sits; 24 plus padding to 48 on touch.
- The divider and grip meet 3:1 when shown (`outline` on `surface`).
- Reduced motion: collapse and reopen are instant; the grip appears without fading.

## Content
The sash has no visible text. Its accessible name is "Resize" and the pane name. The readout shows the number and unit ("240 px"); hide it when sizes are meaningless to people.

## e.ui today
`control.resizable_pane` draws the content at `size` and a `space-xs`-thick handle filled in `border`, with no hover, press or focus look; the Slider it publishes carries no value. To reach this design:
- Make the handle an 8px transparent sash with a centred 1px `outline-variant` line and a 4x48 grip that shows on hover, focus and drag (always on touch).
- Draw the focus ring round the grip (today a focused handle shows nothing) and the dragged `primary` state.
- Publish the separator role with its value and range, and a name from `label` ("Resize " + label).
- Add Shift steps, Home/End, Escape-to-cancel, double-click reset and snap-to-close.
- Set the resize cursor on hover through `input`.
