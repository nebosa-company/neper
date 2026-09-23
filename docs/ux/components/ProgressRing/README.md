# ProgressRing

A progress ring shows progress round a circle: how much of a task is done, or that work is happening. It fits where a bar does not, such as square spaces, buttons, list rows and loading panes.

## Anatomy
1. Active indicator: a `primary` arc from 12 o'clock clockwise, with round caps.
2. Track: a `secondary-container` arc over the rest of the circle, with a gap on either side of the indicator (determinate only).
3. Optional value: the percent in `label-medium` inside the ring, at 64 and larger only.
4. Optional label: a line of `body-medium` beside or below the ring, for loading panes.

## Variants and when to use
| Variant | Use for |
|---|---|
| Determinate | A task with a known size in a compact space: a test run in a row, a sync in a toolbar. |
| Indeterminate | Unknown-length work: a pane or list loading, a button waiting for a result, a refresh. No track. |
| With value (64+) | A single dominant task in a dialog or empty pane: "65%". |
| In a button | In place of the label (the button keeps its width) or of an icon button's icon. The ring takes the content colour. |

Use a Progress bar when there is width for it, or when the reader must read the amount at a glance. Use a Placeholder when the layout of the incoming content is known. Use Pull to refresh for the refresh gesture itself. Show nothing for waits under 300 ms.

## Specs
| Size | Use | Stroke | Gap either side |
|---|---|---|---|
| 48 (default) | panes, dialogs, empty states | 4 | 4 |
| 36 | cards, sheets | 3 | 3 |
| 24 | list rows, toolbars, inline with `body-medium` | 2 | 2 |
| 18 / 20 | inside buttons (18) and icon buttons (20) | 2.25 | none (indeterminate only) |
| 64 | with the value inside | 4.5 | 4 |

| Part | Value |
|---|---|
| Geometry | the arc is centred on radius (size - stroke) / 2; round caps; the gap is measured between cap ends |
| Start | 12 o'clock, clockwise (counter-clockwise in right-to-left layouts only when the ring means a clock; otherwise keep clockwise) |
| Minimum visible arc | 4% of the turn, so a small non-zero value still shows |
| Label | `body-medium`, `on-surface-variant`, `space-3` 12 from the ring |
| Value inside | `label-medium` 12/16 weight 600, tabular figures, `on-surface` |

| Part | Colour role |
|---|---|
| Indicator | `primary`; in a button, the button's content colour (`on-primary` on filled) |
| Track | `secondary-container` |
| Error | indicator `error`, track `error-container`, plus an `error` icon and a word next to it: rings never carry failure alone, so replace the ring with the icon once it fails |
| Value and label | `on-surface`, `on-surface-variant` |

## States
Running (determinate or indeterminate), complete, and failed. When the task completes, the ring is replaced by a `check-circle` icon in `success` or by the result itself. When it fails, the ring is replaced by an `error` icon and a word ("Failed"). It never stays at 100%. It is never disabled: remove it instead.

## Behaviour
- Determinate: the arc eases to each value over `duration-medium-2` with `ease-standard`. It never runs backwards.
- Indeterminate: the arc spins once per 1.5 s (`ease-linear`) while its length grows from 10% to 75% and shrinks again (`ease-standard`), and the start advances each cycle. With reduced motion it does not spin: a 75% arc pulses between 38% and 100% opacity every 2 s.
- Appear after 300 ms and stay at least 500 ms. A pane shows its label after 1 s of loading.
- In a button: the button is not pressable while it shows a ring (it reports Busy, not Disabled) and keeps its width.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | The same ring (Fluent ProgressRing). 3px stroke at 32 is acceptable in Fluent-styled apps. The indeterminate motion follows the spec. |
| macOS | The ring as specified for determinate. Indeterminate may use the system spinner (radial ticks) where the app follows macOS closely: keep the size and placement. |
| Linux | The same ring. GNOME's spinner is a single arc and matches it. |
| Android | Material 3 circular indicator as specified. |
| iOS | The system activity indicator (radial ticks) for indeterminate in navigation bars and lists. The ring for determinate. |
| Web | `role="progressbar"` on the SVG or its wrapper, with `aria-valuenow` for determinate. Honour `prefers-reduced-motion`. |

## Accessibility
- Role progressbar, named for the task ("Tests on Linux x64"), with value and value text when determinate. Indeterminate has no value, and the region it loads is Busy.
- A ring in a button makes the button Busy, and the button's name gains the state ("Deploy, busy").
- Announce politely at start (if the wait passes 1 s), on completion and on failure. Never on each value.
- Contrast: the indicator is 3:1 against the surface and the track. A ring next to a word ("Running") does not rely on its colour.
- Reduced motion: no spin, a pulse in place.

## Content
Pair a ring with a word when it stands for a state in a list or table ("Running", "Queued"). Give a loading pane a label after 1 s that names what is loading: "Loading build history", not "Loading…" or "Please wait". Use the value inside only for whole percents.

## e.ui today
`control.progress_ring` strokes a full `surface-variant` circle of `size` and, over it, a `primary` arc from the top through `value` of the turn, with a stroke `space-xs` wide and butt caps. It is a Custom node (key + 1) painting a `Ring` from the frame arena, with role Progress named by the label and Busy when indeterminate. To reach this design:
- Switch to round caps, a `secondary-container` track, and the gap either side of the arc. Drop the track when indeterminate.
- Scale the stroke with the size (4 at 48, 3 at 36, 2 at 24).
- Animate indeterminate (spin plus grow and shrink, and a pulse under reduced motion). Today it is a static quarter arc, indistinguishable from `value = 0.25`.
- Put `value` and a value text in the semantics. Today a reader hears the label but not the amount.
- Enforce a 4% minimum visible arc, and add error colours plus the replacement icon on completion or failure.
- Add a button-content mode that takes the content colour and marks its button Busy.
- Replace the ten-chord fan for the partial quarter with a true arc segment (cubic), so a thick ring's end is smooth.
