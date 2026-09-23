# Level

A level is a read-only bar that shows how full a bounded quantity is, with its limit marked and its state in words, for storage, quotas, strength and signal.

## Anatomy
1. Header: the name in `label-large` at the start and the value with its scale ("27 of 64 GB") in `body-medium` `on-surface-variant` at the end.
2. Bar: an 8 tall track split into the fill and the rest, 4 apart, both `radius-full`.
3. Fill: `primary`; `warning` past the warning threshold; `error` past the critical threshold.
4. Rest: `surface-container-highest`.
5. Limit mark (optional): a 2x16 `on-surface-variant` tick at the warning threshold.
6. Status line: what the level means now, `body-small`, with an icon in the status colour when not normal.
7. Discrete form: 2 to 5 segments (or rising bars for signal) instead of a continuous fill.

## Variants and when to use
| Variant | Use for |
|---|---|
| Continuous | Storage, quotas, usage against a limit. Default. |
| Small (4 tall, no header) | Trailing a list row or a table cell, beside a text value. |
| Segmented | Qualitative levels: passphrase strength, risk, 2 to 5 steps. |
| Bars | Signal or connection quality (3 or 4 rising bars). |

Use a Progress indicator for work toward completion, a Gauge for a single headline measure, and a Slider when people set the value.

## Specs
| Part | Continuous | Small | Segmented / bars |
|---|---|---|---|
| Bar height | 8 | 4 | segments 6 tall, 32 wide; bars 6 wide, 6/10/14/18 tall |
| Gap | 4 between fill and rest | 4 | 4 between segments |
| Width | the container's (min 160) | 120 to 200 | intrinsic |
| Fill | `primary`; `warning`; `error` | same | `success`, `warning` or `error` by level; `primary` for neutral scales |
| Rest | `surface-container-highest` | same | same |
| Limit mark | 2x16, `radius` 1, `on-surface-variant` | none | none |
| Header | `label-large` name, `body-medium` value, `space-2` apart; 6 above the bar | none | `label-large` |
| Status line | `body-small`; icon 16 in `warning`/`error`/`success` | none | same |

## States
- Normal: `primary` fill; status gives the useful remainder ("37 GB free").
- Warning: `warning` fill, `warning` icon, words that say what it means and when it changes ("Almost used up. Resets on 1 October").
- Critical: `error` fill, `error` icon, the consequence ("Full. New artifacts will not be cached").
- Over the maximum: the bar is full; the value shows the true number ("10.4 of 10 GB").
- Unknown: rest only, value "–", status "Usage unavailable".
- Levels are read-only: no hover, focus or pressed looks. If it opens detail, the row or card is the control.

## Behaviour
- Value changes animate the fill over `duration-medium-2` with `ease-standard`; crossing a threshold transitions the colour in the same motion and updates the status line.
- Segmented levels fill segment by segment (`duration-short-3` each) as a passphrase is typed; never animate backwards through the colours, jump.
- The fill never shows less than 4px when the value is above zero, so a small use is visible.
- Values arrive from the caller; the level does not poll.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Same; in high-contrast mode the rest is outlined 1px `outline` because the fill tone alone may vanish. |
| macOS | Same; maps to NSLevelIndicator (continuous and discrete styles) semantics; the warning and critical thresholds match its warning/critical values. |
| Linux | Same; GtkLevelBar offsets map to the thresholds. |
| Android | Same; the small form suits list rows. |
| iOS | Same; the bars form matches the system's signal glyph shape. |
| Web | `role="meter"` with `aria-valuetext`; `<meter>` semantics (low, high, optimum) map to the thresholds. |

## Accessibility
- Role meter (level indicator), name = the measure, value now/min/max, value text with units and state ("1,720 of 2,000 minutes used, almost used up").
- One node per level; the header and status line are its name, value and description, not separate nodes.
- State is never colour alone: warning and critical add an icon and words; segmented levels always show the word ("Strong").
- The fill meets 3:1 against the rest and against `surface`.
- Threshold crossings are announced politely; ordinary value changes are not.
- Reduced motion: the fill jumps.

## Content
Name the quantity ("Storage"). The value reads "used of total" with the unit once ("27 of 64 GB"). The status line says what people care about: what is left, when it resets, or what will stop working. Segment words are single adjectives: "Weak", "Fair", "Strong".

## e.ui today
`control.level` draws a `space-sm` (8) `surface-variant` track with a fill in `primary`, `secondary` from `warn` and `error` from `danger`; it draws no label or value, and the warning state reaches the tree only as colour. To reach this design:
- Split the bar into fill and rest with a 4 gap and draw the rest in `surface-container-highest`; draw the limit mark.
- Use `warning` (not `secondary`) past `warn`, and add the status line with icon and words for warning and critical.
- Draw the header (name, value with scale) and the small, segmented and bars variants.
- Publish value text with units and state, and a warning state alongside the existing Invalid at `danger`.
- Keep a minimum 4px fill above zero and animate value changes.
