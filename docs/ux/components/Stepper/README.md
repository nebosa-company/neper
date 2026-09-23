# Stepper

A stepper changes a small bounded integer one step at a time with decrease and increase buttons around the value, for counts people nudge rather than type: copies, retries, parallel jobs.

## Anatomy
1. Container: a pill, 40 tall, 1px `outline` (outlined) or `surface-container-highest` fill (tonal), `radius-full`.
2. Decrease button: a 32 icon button with `remove`.
3. Value: `label-large`, tabular figures, centred, min 40 wide; an optional unit after the number ("13 pt").
4. Increase button: a 32 icon button with `add`.
5. State layers and focus ring on each button.

## Variants and when to use
| Variant | Container | Use for |
|---|---|---|
| Outlined | 1px `outline` | Settings rows and forms. Default. |
| Tonal | `surface-container-highest` | Toolbars and inspectors where outlines would add noise. |
| Small | 32 tall | Dense tool UIs (density -2) and table cells. |

Use a Spin box when people also type the number or the range is large (ports, years), a Slider for continuous or wide ranges, and a Segmented button for 2 to 5 named levels.

## Specs
| Part | Default | Small (density -1/-2) |
|---|---|---|
| Height | `control-md` 40 | `control-sm` 32 |
| Container | `radius-full`; 1px `outline` or `surface-container-highest` | same |
| Inner padding | `space-1` 4 | 2 |
| Buttons | `control-sm` 32 circles, `icon-md` 24 in `on-surface` | 28, `icon-sm` 18 |
| Gap | `space-1` 4 | same |
| Value | `label-large`, `on-surface`, tabular, min width 40 | same |
| Target | each button pads to `target-touch` 48 on touch (the pill grows to 48 tall invisibly) | `target-pointer` 32 |
| In a settings row | trailing, the row 48 min (`control-lg`) with label and range as supporting text | row 40 |

## States
- Button hover `state-hover`, focus `state-focus` plus the ring 2px outside the button, pressed `state-pressed` (ripple on touch).
- At a bound: that button disabled (`on-surface` 38%, not focusable); the other stays live.
- Disabled: container outline `on-surface` 12%, value and icons 38%.
- Invalid (the caller rejects the value): outline `error` 2px and a supporting message in the row.

## Behaviour
- Press steps once. Press and hold repeats after 400ms, every 80ms, accelerating to 5x steps after 2 seconds.
- Keyboard: both buttons are Tab stops; Up/Right increase and Down/Left decrease from either; Page Up/Down step by 10x; Home and End go to the bounds.
- The value changes instantly (tabular figures keep the width); no animation on the number.
- A step past a bound does nothing and fires nothing; the button is already disabled.
- The value commits on each step; debounce expensive saves by 500ms after the last step.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1 (32); matches NumberBox's inline spin buttons in spirit; Page Up/Down honoured. |
| macOS | Density -1; the native NSStepper is a tiny vertical pair next to a field; use Spin box there. The stepper form here suits inspectors and preferences. |
| Linux | Density -1; GTK SpinButton places − and + on the end; follow this spec but keep the order − then +. |
| Android | Default 40 with 48 targets, ripple, press-and-hold repeat. |
| iOS | Default; UIStepper-like behaviour with 44pt targets and a haptic tick at each bound. |
| Web | Default; two `button`s and an output; the group role spin button is on the value (see Accessibility). |

## Accessibility
- The control is a spin button named by its label ("Parallel jobs"), with value now/min/max and value text including the unit ("13 points"). Actions Increment, Decrement.
- The buttons are named with the action and label ("Increase parallel jobs"), never "+" or "-".
- Announce the new value after each step; announce "minimum" or "maximum" when a bound is reached.
- Targets: 48 on touch through padding; 32 minimum with a pointer.
- Reduced motion has no effect (nothing animates).

## Content
The label says what is counted ("Parallel jobs"); the range goes in supporting text ("1 to 64 workers"). Units are short and after the number ("13 pt", "5 min"). Never put the label inside the pill.

## e.ui today
`control.stepper` lays out Outlined `button`s labelled with the literal "-" and "+" around the value in the Body role; buttons disable at the bounds at half opacity, and their accessible names are "-" and "+". To reach this design:
- Draw the pill container (outlined or tonal) with 32 icon buttons using `remove` and `add`.
- Set the value in `label-large` with tabular figures and an optional unit.
- Disable at a bound with the on-surface 38% look instead of half opacity.
- Name the buttons "Increase <label>" and "Decrease <label>"; publish value text with the unit.
- Add press-and-hold repeat, Page Up/Down and Home/End, and the small size.
