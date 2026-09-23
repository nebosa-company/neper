# Dial

A dial sets a bounded continuous value by turning a handle around a 270° arc, with the value written in its centre, for compact controls in inspectors and media tools: a limit, a hue, an opacity.

## Anatomy
1. Track: a 270° arc from lower left (minimum) clockwise to lower right (maximum), 6 stroke in `secondary-container`, round caps.
2. Active arc: from the minimum to the value, 6 stroke in `primary`.
3. Handle: a 14 circle in `primary` on the arc at the value (18 while dragged).
4. Readout: the value in the centre, `title-large` (default) or `label-large` (small), with its unit in `body-small` `on-surface-variant`.
5. Label: below the dial, `label-medium` `on-surface-variant`.
6. State layer (a 30 halo round the handle) and focus ring round the handle.

## Variants and when to use
| Variant | Size | Use for |
|---|---|---|
| Default | 120 | A prominent single value in a panel or dialog. |
| Small | 72 | Rows of dials in dense inspectors and toolbars (density -1 and -2). |
| Bipolar | 120 or 72 | Values centred on zero (pan, balance): the active arc runs from the top to the value. |

Use a Slider in forms and whenever the value should read along a line; a Spin box when precision matters; a Gauge to show a value that people cannot set. On touch hosts prefer a Slider unless the dial is the domain's convention.

## Specs
| Part | Default | Small |
|---|---|---|
| Size | 120 | 72 |
| Arc | radius 40% of size, 270° sweep, start 135° | same |
| Track | 6 (of 100) stroke `secondary-container`, round caps | same |
| Active arc | 6 stroke `primary` | same |
| Handle | 14 circle `primary`; 18 dragged | 16 of 100 |
| Hover halo | 30 circle `primary` at `state-hover` | same |
| Focus ring | 3px `focus-ring`, 2px outside the handle | same |
| Readout | `title-large` 22/28, tabular, `on-surface`; unit `body-small` `on-surface-variant` | `label-large`, unit inline |
| Label | `label-medium`, `on-surface-variant`, `space-1` below | same |
| Target | the whole face (120 or 72); pads to 48 on touch | 72 |

## States
- Rest: arc and handle.
- Hover (on the face): the halo round the handle at `state-hover`.
- Focus: ring round the handle; halo at `state-focus`.
- Dragged: handle grows to 18, halo at `state-dragged`; the readout updates live.
- Disabled: arc and handle `on-surface` 38%, track 12%, readout 38%; not focusable.
- Indeterminate (mixed selection): no active arc or handle; readout "Mixed".

## Behaviour
- Pointer: drag anywhere on the face. Vertical drag is the default gesture (up increases, 200px for the full range, Shift for 10x finer); circular drag (following the pointer's angle) is an option for hue-like values. A click on the arc jumps to that point.
- Double-click resets to the default value.
- Wheel over a focused dial steps by 1% of the range (Shift 0.1%).
- Keyboard: Up/Right +1%, Down/Left -1% (Shift 10%), Page Up/Down 10%, Home/End to the bounds. Typing a digit or Enter turns the readout into an inline field; Enter commits, Escape cancels.
- The handle follows the pointer without easing; value changes from keys animate the arc over `duration-short-3` with `ease-standard`.
- The value wraps only for cyclic quantities (hue): 360° goes to 0°.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Small size in dense tools; vertical drag; the cursor hides while dragging and reappears where it began. |
| macOS | Small; NSSlider circular style convention: vertical drag and ⌥ for fine; Full Keyboard Access for focus. |
| Linux | Small; no native dial on GTK; follow this spec. |
| Android | Default size; circular drag (a vertical drag conflicts with scrolling) after a 8px slop; haptic tick at each 10%. |
| iOS | Default; circular drag; haptic at the bounds and at the default value. |
| Web | `role="slider"` on the face; pointer capture during drag; `touch-action: none` on the face only. |

## Accessibility
- Role slider, name = label ("CPU limit"), value now/min/max, value text with unit ("65 percent"). Actions Increment, Decrement, SetValue.
- The readout and the arc are hidden from the tree (the value text carries them).
- The active arc (`primary`) and handle meet 3:1 against `surface` and against the track.
- Announce the value on keyboard steps; throttle announcements during a drag to the committed value on release.
- Reduced motion: no arc animation on key steps.

## Content
Label with the quantity ("CPU limit", "Hue"), not the gesture. The readout shows the number with a short unit: "65%", "180°", "9 px". No label inside the arc.

## e.ui today
`control.dial` draws a `size` circle stroked 2px in `border` and a 2px `primary` pointer line from the centre; it draws no label, no value, and no hover, press or focus look, and the knob takes focus invisibly. To reach this design:
- Replace the circle and pointer with the 270° `secondary-container` track, the `primary` active arc and a handle dot.
- Draw the readout (value and unit) inside and the label below.
- Draw hover, focus (ring round the handle), dragged and disabled states.
- Switch the default gesture to vertical drag with Shift-fine, add wheel steps, Page Up/Down, Home/End, double-click reset and inline typing.
- Publish value text with the unit, not bare digits; add the small and bipolar variants.
