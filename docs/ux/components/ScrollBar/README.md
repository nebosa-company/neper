# ScrollBar

A scroll bar shows how much of a scrollable surface is visible and where, and lets a pointer move it. It belongs to a viewport; it never scrolls anything by itself.

## Anatomy
1. Track: the full length of the viewport's axis, `surface-container` on a pointer host.
2. Thumb: its length is the visible fraction of the content (never under 24), its position the scroll offset; `outline` at rest, `on-surface-variant` on hover and while dragged.
3. Arrow buttons (optional, Windows look): a step button at each end of the track.

## Variants and when to use
| Variant | Where |
|---|---|
| Vertical | Lists, documents, trees, grids |
| Horizontal | Wide tables, code, canvases; shown only when the content overflows that axis |
| Overlay (thin, fades) | Touch and macOS hosts: appears while scrolling, 4 wide, expands to 10 on pointer approach |
| Classic (always shown) | Windows and Linux pointer hosts: 12 to 17 wide with arrows |

## States
- Rest, hover (thumb darkens), pressed and dragged (thumb at full emphasis), focus (3px `focus-ring`, keyboard-focusable bars only), disabled (content fits: track kept, thumb hidden).

## Behaviour
- Dragging the thumb sets the offset in proportion; clicking the track pages toward the pointer; arrows step one line and repeat on hold.
- The wheel, touch fling and keyboard (Page Up/Down, Home/End, arrows) scroll the viewport and move the thumb; the bar only reflects the offset.
- The thumb length and position are computed from the viewport and content sizes, so resizing the window or changing the content updates the bar without a separate call.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Classic with arrows; thin overlay in modern apps |
| macOS | Overlay, shown by default when a mouse is attached |
| Linux | Classic, GTK metrics |
| Android, iOS | Overlay indicator only, not draggable except for a fast-scroll handle on long lists |
| Web | The host's own bar; custom bars keep the same roles |

## Accessibility
- Role scroll bar with orientation, value now/min/max as a percentage and the viewport it controls.
- Everything a bar does is also reachable by keyboard in the viewport; the bar itself is optional in the tab order.
- The thumb holds 3:1 against the track in every theme.

## e.ui today
`widget.scrollbar(key, viewport, axis, value_style)` draws the track and thumb for a named viewport; scrolling itself lives in the layout's viewport.
