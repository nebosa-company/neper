# Slider

A slider picks a value, or a range with two handles, from a continuous or stepped scale by dragging along a track. Use it where position matters more than the exact number.

## Anatomy
1. Active track: 4px, `primary`, from the start (or from the lower handle) to the handle.
2. Inactive track: 4px, `secondary-container`, the rest. It leaves a 6px gap on each side of a handle.
3. Handle: a 4 by 44 `primary` bar, 2 wide while pressed.
4. Tick marks (discrete): 4px dots at each step. `on-primary` on the active track and `on-secondary-container` on the inactive one. Hidden within 6px of a handle.
5. Value label: an `inverse-surface` pill above the handle, shown while dragging or focused. It holds the value in `label-large`.
6. Optional icons at either end: 18 and 24 icons that show the scale's meaning (small and large).
7. Optional value box: a 64-wide outlined box at the end for typing an exact value.
8. Label and message: a Field label above and a Field message below.

## Variants and when to use
| Variant | Use for |
|---|---|
| Continuous | Values where any point is fine: zoom, opacity, volume. |
| Discrete (ticks) | A small number of steps (up to about 20) the reader should land on exactly: parallel jobs 0 to 16 by 2. |
| Range | A minimum and a maximum on one scale: build duration 4 to 13 min, a date span on a timeline. |
| With value box | When an exact value matters sometimes. Drag for the rough value, type for the exact one. |
| With end icons | When the scale's direction needs a picture (smaller or larger, quieter or louder). |

Use a Text field or Spin box when the reader must enter an exact value most of the time. Use a Segmented button or Radio buttons for a few named options. Use a Progress bar for a value the reader can't change. Never use a slider for a value with a huge range (bytes, dates in years) unless the scale is logarithmic and labelled.

## Specs
| Part | Touch | Pointer (density -1) |
|---|---|---|
| Container height | 44 (handle height), in a 48 target | 44, in a 32 target along the handle |
| Track | 4, `radius-full` | 4 |
| Handle | 4 x 44, `radius-full`; pressed 2 x 44 | same |
| Gap round a handle | 6 each side | 6 |
| Tick | 4 dot | 4 |
| Value label | `inverse-surface` pill, 12 by 16 padding, `label-large`, 8 above the handle | same |
| Minimum width | 120 | 120 |
| Default width | fills the column | fills the column, 200 to 320 in a toolbar |
| End icons | 18 and 24, `on-surface-variant`, 16 from the track | same |
| Value box | 64 x 40, 1px `outline`, `radius-xs`, `body-medium`, tabular figures, 16 from the track | same |
| Scale labels | `body-small`, `on-surface-variant`, under the ends | same |

| Part | Colour role |
|---|---|
| Active track, handle | `primary` |
| Inactive track | `secondary-container` |
| Ticks | `on-primary` on the active track, `on-secondary-container` on the inactive one |
| Value label | `inverse-surface` / `inverse-on-surface` |
| Hover | a 6px `primary` 8% halo round the handle |
| Disabled | active and handle `on-surface` 38%, inactive `on-surface` 12%, ticks 38% |

## States
- Rest, hover (halo), focused (the 3px ring 2px round the handle, plus the value label), pressed or dragging (a 2 wide handle and the value label), disabled.
- Range: each handle has its own states. The handles cannot cross. At equal values the one last moved stays on top.

## Behaviour
- Pointer: a press on the track moves the nearer handle there and starts a drag. Dragging snaps to steps when discrete. The change fires continuously while dragging (for previews), and a commit fires on release.
- Touch: the same, with the track as a 48 tall target. A vertical drag starting on the slider scrolls the page instead unless the slider already has the gesture.
- Keyboard: Left and Down decrease by one step (1% when continuous), Right and Up increase, Page Up and Page Down move by 10%, Home and End go to the minimum and maximum. In a range, Tab moves from the lower handle to the upper one. Right-to-left layouts mirror Left and Right.
- The value label appears on focus or drag over `duration-short-2` (`ease-standard`) and hides `duration-short-4` after release.
- The value box and the slider stay in sync. Typing commits on Enter or blur and clamps to the scale, with a Field message when the value is clamped ("Maximum is 16").
- With reduced motion the handle jumps on a track press instead of gliding, and the value label cross-fades.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | The same handle and track. Keyboard steps as above. The value label is shown as a tooltip above the handle (Fluent Slider). |
| macOS | Keep the handle design and a 32 target. Option+arrow moves by a large step. Ticks show below the track for discrete sliders when the app follows macOS closely. |
| Linux | GTK scale: the value can be drawn beside the track. Keep the handle and track. Page keys as above. |
| Android | As specified, 48 target and Material 3 expressive handle. |
| iOS | A round 28pt thumb is the native convention. Use it when the app follows iOS closely, with the same track colours. No value label (show the value in the row instead). |
| Web | `<input type="range">` styled, or `role="slider"` with `aria-valuemin`, `aria-valuemax`, `aria-valuenow` and `aria-valuetext`. A range is two sliders in a group. |

## Accessibility
- Role slider, named by its label, with the minimum, maximum, current value and a value text with units ("8 jobs", "13 min"). Increment, Decrement and Set value actions.
- A range is a Group named by the label, holding two sliders named "Minimum <label>" and "Maximum <label>", each with its own value. The upper handle's minimum is the lower handle's value.
- The value label is visible text but not announced separately: the value text carries it.
- Contrast: the handle and active track are 3:1 against the surface. The inactive track is decorative, and the ticks and value label carry the steps.
- Target: 48 on touch along the track. The handle's hit area is at least 32 wide with a pointer.
- Reduced motion: no glide.

## Content
Label the quantity with its unit in the value text, not the label: label "Parallel jobs", value "8". Scale labels show the minimum and maximum with units. Keep value labels to four characters where possible ("13 min" is fine, "13 minutes" is not).

## e.ui today
`control.slider` and `control.range_slider` (through `ranged`) put a `widget.slider` box 120 wide and `control-height` tall beside a Body label. `widget.place_slider` paints a 4px `border` rail, a `primary` fill and a 16px `primary` disc thumb. Disabled sets opacity 0.5. The role is Slider, with Increment, Decrement and Set value. To reach this design:
- Replace the disc thumb with the 4 x 44 handle bar and the 6px gaps. Paint the inactive track `secondary-container` instead of `border`.
- Draw ticks for `step > 0`, and the `inverse-surface` value label while focused or dragging.
- Add hover, focus (ring) and pressed looks. `ranged` resolves the outlined look only for its opacity, so keyboard focus on a slider is invisible today.
- Give the range slider's second handle its own semantics (two sliders in a group). Today it is one Slider node.
- Add a `width` parameter (today it is fixed at 120) and let the label sit above through Form field instead of beside.
- Add value text with units, Page Up, Page Down, Home and End, the value box option, and end icons.
- Replace opacity 0.5 with the specified disabled colours.
