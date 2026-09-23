# Canvas

A canvas is a sized region the app paints itself (charts, diagrams, waveforms, live previews), framed and made accessible by the system.

## Anatomy
1. Frame: `surface-container-lowest`, 1 px `outline-variant`, `radius-md`, clipping the paint.
2. Paint area: the app's drawing, inset by the frame's padding (0 by default; charts use `space-4`).
3. Optional overlays drawn by the system: cursor line, focused-point marker, rich tooltip.
4. Optional legend and text alternative below: `label-medium` series keys and a "Show as table" text button.
5. Focus ring: 3 px `focus-ring`, 2 px outside the frame, when the canvas takes keyboard input.
6. State content: loading ring or empty message, centred.

## Variants and when to use
| Variant | Takes input | Use for |
|---|---|---|
| Static | no | A chart or illustration that only shows data. Not focusable. |
| Interactive | pointer and keyboard | Charts with inspectable points, editors, maps, timelines. Focusable, with a keyboard model. |
| Bare | depends | A canvas inside another component that already frames it (a card's media, a full-window editor): no frame, no radius. |

Use Image when the picture already exists as a file or texture. Use the Progress, Gauge or Sparkline-style components before drawing your own. Do not draw text-heavy UI on a canvas: use real controls.

## Specs
| Part | Value |
|---|---|
| Frame | `surface-container-lowest`, 1 px `outline-variant`, `radius-md` 12 (bare: none) |
| Minimum size | 48 × 48; charts 240 wide at least |
| Chart padding | `space-4` 16; axis labels in the padding |
| Grid lines | 1 px `outline-variant` |
| Axis labels | `label-small` 11/16, `on-surface-variant`; tabular figures |
| Series | 2 px strokes: first `primary`, second `tertiary` dashed 5/4, third `secondary` dotted; area fills at 12% of the series colour |
| Marker | 5 px radius dot in the series colour with a 2 px ring in the frame colour |
| Cursor | 1 px `on-surface-variant` dashed 2/3 |
| Tooltip | Rich tooltip (`surface-container`, `radius-md`, `elevation-2`), `space-3` from the point, flips to stay inside the frame |
| Legend | `label-medium`, key swatch 16 × 2 in the series' stroke style, `space-4` apart, `space-3` below the frame |
| Loading | Progress ring 32, centred |
| Empty | `icon-md`, `body-small` message, a text button; centred, `space-1` apart |

## States
- Rest: the paint.
- Hover (interactive): the cursor line and the nearest point's marker and tooltip after `duration-short-2`.
- Focus (interactive): the focus ring on the frame, and a focused element (point, node) with its own marker; the tooltip shows for it.
- Pressed and dragged: owned by the app's model (panning, selecting a range); dragged items lift with `elevation-4` if they are objects.
- Disabled: the paint at 38% opacity and no input.
- Loading, Empty, Error: the state content; Error uses the `error` icon and a Retry text button.

## Behaviour
- The system asks the app to paint only when its state changes; paint is never on the input thread.
- Keyboard (interactive charts): Tab focuses the canvas; Left and Right move between points, Home and End to the first and last, Up and Down between series, Enter opens the point's detail, Escape leaves the point and returns to the frame.
- Pointer: hover inspects; wheel scrolls the page unless the canvas is zoomable and the pointer has been pressed inside first (no scroll traps); Ctrl/Cmd+wheel or pinch zooms zoomable canvases.
- Touch: a tap selects the nearest point (48 search radius); a horizontal drag scrubs; a vertical drag scrolls the page.
- Resize repaints at the new size; charts re-flow ticks, never stretch.
- Animated paint (a series drawing in) runs `duration-long-2` with `ease-emphasized-decelerate` once, on first data only; reduced motion shows the final frame.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Paint through the shared renderer on the window's swap chain; per-monitor scale; honour Windows high contrast by using the high-contrast tokens for strokes. |
| macOS | Backing scale 2×; trackpad pinch and two-finger scroll; the tooltip follows the pointer with a short delay as in macOS charts. |
| Linux | Fractional scaling on Wayland; the same keyboard model. |
| Android | Touch model; TalkBack explores points by swipe as a list of elements. |
| iOS | Touch model; VoiceOver audio graphs (Chart descriptor) for charts; a drag scrubs with haptic ticks at each point. |
| Web | A `<canvas>` or inline SVG inside a `role="img"` or `role="application"` group; an adjacent data table for the text alternative. |

## Accessibility
- Static: role Image with a name that states the takeaway ("Build time last week, peaked at 66 s on Thursday").
- Interactive: a Group (or Application region) named like the static one, whose points or nodes are exposed as child elements with names and values ("Thursday, build 66 s, target 53 s") the reader can move through.
- Always offer the data another way: a "Show as table" button or a linked table.
- Series differ by stroke style (solid, dashed, dotted) as well as colour; markers differ by shape when there are more than two series.
- Contrast: strokes and markers 3:1 against the frame; labels 4.5:1.
- Reduced motion: no draw-in, no animated transitions between data.

## Content
- Title the chart outside the canvas with a Text (`title-small`), sentence case: "Build time, last 7 days".
- Axis labels carry units once ("90 s"), not on every tick.
- Legend names are nouns: "Build time", "Target".
- Empty messages say why and what to do: "No builds in this range", "Show last 30 days".

## e.ui today
`control.canvas` wraps the caller's `widget.Custom { ctx, measure, paint, state }` in an Image-role node labelled `label`; its style is `style.defaults()`, so it is sized only by `measure` or a parent. To reach this design:
- Add the frame (`surface-container-lowest`, `outline-variant`, `radius-md`, clip) with a bare option.
- Add an interactive form: focusable, with the focus ring, keyboard routing to the app, and child semantics for points or nodes; today it is always a leaf Image.
- Give it loading, empty and error states and a size in the options instead of relying on `measure`.
- Supply the chart overlays (cursor, marker, tooltip) and series styles as tokens so apps do not hand-pick colours.
- Keep the rule that paths are built in the frame arena (the scene copies them after `paint`).
