# Rating

A rating sets or shows a small whole-number score as a row of stars, for feedback on templates, extensions or builds; the read-only form displays an average to the half star.

## Anatomy
1. Group: one focus stop holding the stars, `radius-full` so the focus ring hugs the row.
2. Star: `star` (empty) or `star-filled` 24 (`icon-md`) centred in a 40 state-layer circle.
3. Filled stars: `primary`; empty stars: outline `on-surface-variant`.
4. Hover preview: stars up to the pointer at `primary` 60%.
5. Read-only form: 16px stars 2 apart, the average in `label-large` and the count in `body-small`.

## Variants and when to use
| Variant | Size | Use for |
|---|---|---|
| Input | 24 stars in 40 cells | Asking a person for a score. |
| Read-only | 16 stars, halves allowed | Showing an average in lists and cards, always with the number. |
| Compact read-only | one `star-filled` 16 + "4.5" | Dense tables and list trailing meta. |

Use a Slider for continuous values, a Segmented button for 2 to 5 named levels (Low, Medium, High), and a thumbs-up/down Icon button pair for binary feedback. Never use stars for severity or priority.

## Specs
| Part | Input (default) | Input (density -1) | Read-only |
|---|---|---|---|
| Star icon | `icon-md` 24 | 20 | 16 |
| Cell (state layer) | `control-md` 40 circle, no gap | `control-sm` 32 | none |
| Target | 40 visual, padded to 48 on touch | 32 | not interactive |
| Filled colour | `primary` | `primary` | `primary` |
| Empty colour | `on-surface-variant` (stroke 1.75) | same | same |
| Preview colour | `primary` at 60% | same | n/a |
| Number / count | optional, `label-large` / `body-small` `on-surface-variant`, `space-2` after | same | always shown |
| Max | 5 (3 to 10 allowed) | | |

## States
- Rest: filled up to the value.
- Hover (pointer): stars up to the hovered one preview at 60% `primary`, and the hovered star gets a `state-hover` layer.
- Focus: ring round the whole group (2px outside); the current star gets `state-focus`.
- Pressed: `state-pressed` on the star; ripple on touch.
- Disabled: all stars `on-surface` 38%, not focusable.
- Unset (0): all empty; the group's value reads "Not rated".
- Read-only never shows hover or focus.

## Behaviour
- Click or tap a star to set the value to it; tapping the current value again clears to 0 (only when clearing is allowed).
- Drag across the stars on touch to scrub; the value commits on release.
- Keyboard: the group is one Tab stop; Right/Up +1, Left/Down -1 (mirrored in right-to-left), Home 0 (or 1 when clearing is not allowed), End max, digits 0 to 9 set directly.
- A new value fills stars with a `duration-short-3` `ease-standard` scale pulse (1 to 1.15 to 1) on the chosen star.
- The value is committed immediately; if it is sent somewhere, confirm with a snackbar, not by changing the stars.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1 (32 cells, 20 stars); matches WinUI RatingControl: hover preview and clear-by-reclick. |
| macOS | Density -1; NSLevelIndicator rating style: no hover preview, drag to set; arrows work when focused (Full Keyboard Access). |
| Linux | Density -1; no native rating widget, use this spec. |
| Android | Default, 48 targets, ripple, drag to scrub. |
| iOS | Default, 44pt cells; haptic tick per star while scrubbing; no ripple. |
| Web | Default; `role="slider"` with `aria-valuetext`; radio group semantics are an allowed alternative. |

## Accessibility
- Input: role slider, name = the question ("Rate this template"), value now/min/max, value text "3 of 5 stars" (or "Not rated"). Actions Increment, Decrement, SetValue.
- The stars are not separate focus stops or nodes.
- Read-only: role image with name "4.5 out of 5 stars, 128 ratings".
- Filled vs empty differs by shape (fill), not only colour; `primary` and `on-surface-variant` both meet 3:1 on `surface`.
- Reduced motion: no pulse on selection.

## Content
Pair the input with a question or label that says what is rated: "Rate this template". Show the number beside read-only stars ("4.5") and the count in words ("128 ratings"). Do not label individual stars unless the scale needs it ("Poor" to "Excellent" as the value text).

## e.ui today
`control.rating` paints `max` five-point stars 24 square with no gap, filled or outlined in `primary` with a 1px mitred stroke; the row takes focus but draws no focus look and there are no hover or press looks. To reach this design:
- Draw the Neper `star`/`star-filled` icons, empty ones in `on-surface-variant`, each in a 40 state-layer cell.
- Draw the focus ring round the group (today invisible) and the hover preview.
- Add Home/End and digit keys, clear-by-reclick and touch scrubbing.
- Publish value text "3 of 5 stars" instead of bare digits.
- Add the read-only form with half stars, the number and the count, and density -1 sizing.
