# Gauge

A gauge is a read-only 270° meter that shows one measured value within a known range, with the number in its centre and a threshold band, for dashboards and monitors: CPU, memory, a cache's fill.

## Anatomy
1. Track: a 270° arc from lower left (minimum) clockwise to lower right (maximum), 8 stroke `surface-container-highest`, round caps.
2. Threshold band (optional): the track from the warning threshold to the maximum in `warning-container`.
3. Value arc: from the minimum to the value in `primary`; `warning` above the warning threshold, `error` above the critical one.
4. Readout: the number, `display-small` (default) or `title-large` (small), with the unit or context under it in `body-small`.
5. Name: below, `title-small` `on-surface`.
6. Status line: below the name, a word (and icon when not normal) in `body-small`.

## Variants and when to use
| Variant | Size | Use for |
|---|---|---|
| Default | 160 | A dashboard's key measures, 1 to 4 on a screen. |
| Small | 96 | Rows of measures in cards and side panels. |
| With thresholds | either | Measures with a safe range and a limit. |

Use a Level for bars (storage, quotas) and whenever several measures are compared side by side; a Progress indicator for task progress toward done; a Dial when people set the value. Do not use a gauge for values without a meaningful maximum.

## Specs
| Part | Default | Small |
|---|---|---|
| Size | 160 | 96 |
| Arc | radius 40% of size, 270° from 135° | same |
| Stroke | 8 of 80 (10% of size), round caps | same |
| Track | `surface-container-highest` | same |
| Band | `warning-container`, from the warning threshold to the maximum | same |
| Value arc | `primary`; `warning` past the warning threshold; `error` past the critical threshold | same |
| Readout | `display-small` 36/44, tabular, `on-surface` | `title-large` 22/28 |
| Unit / context | `body-small`, `on-surface-variant` | same |
| Name | `title-small`, `on-surface`, `space-1` below | same |
| Status line | `body-small`, `on-surface-variant`; icon 16 in the status role | same |

## States
- Normal: `primary` arc; status "Normal" (or omitted when the dashboard has no thresholds).
- Warning: `warning` arc, `warning` icon, word "High" and the threshold ("High, above 80%").
- Critical: `error` arc and icon, word ("Full", "Critical").
- No data: track only, readout "–" and "No data" in `on-surface-variant`.
- Stale: the readout and arc at `on-surface-variant`, status "Updated 5 min ago".
- Loading: the track with a Skeleton block in the readout.

## Behaviour
- Read-only: no hover, press or focus look. If the gauge opens detail, the whole card is the button, not the gauge.
- Value changes animate the arc over `duration-medium-2` with `ease-standard`; the number counts only on the first load, later changes swap instantly (numbers that roll are hard to read).
- Crossing a threshold changes the arc colour with the same transition, and the status line updates at once.
- Values are clamped to the range for drawing; the readout shows the true value ("104%") when it is over.
- Updates faster than once a second are throttled to 1 Hz for display.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Same design; honour the high-contrast theme by drawing the track in `outline` (it is otherwise too faint). |
| macOS | Same design; NSLevelIndicator's continuous style is the bar (Level), not this. |
| Linux | Same design. |
| Android | Same; widgets and wear surfaces use the small size. |
| iOS | Same; the Gauge circular style in widgets (accessoryCircular) uses the small size without the band. |
| Web | `role="meter"` with `aria-valuenow/min/max` and `aria-valuetext`; the SVG is `aria-hidden`. |

## Accessibility
- Role meter (progress indicator where the host has no meter), name = the measure ("Memory"), value now/min/max, value text with unit and status ("92 percent, high").
- One node per gauge: the arc and readout are hidden from the tree.
- Status is never colour alone: the warning and critical states always add an icon and a word.
- The value arc meets 3:1 against the track and against `surface` in every theme; the track is decorative.
- Changes are not announced unless the status changes; a threshold crossing is announced politely ("Memory high").
- Reduced motion: the arc jumps to the new value.

## Content
Name the measure in one or two words ("Memory", "Build cache"). Put the scale in the context line ("% of 32 GB"). Status words are short and plain: "Normal", "High", "Full". Round to whole numbers unless the decimal matters.

## e.ui today
`control.gauge` draws `progress_ring` at `size` (a `space-xs` track in `surface-variant` with butt caps, the arc from the top clockwise in `primary`) with the value as Label digits under it; the inner ring publishes a second, valueless Progress node, and the track is barely visible in light theme. To reach this design:
- Draw a 270° arc (open at the bottom) with round caps, stroke 10% of size, on a `surface-container-highest` track.
- Put the readout (number and context) inside the arc and the name and status line below.
- Add warning and critical thresholds: band, arc colour, icon and word.
- Publish a single meter node with value text; hide the inner ring's semantics.
- Add the no-data, stale and loading states and animate value changes.
