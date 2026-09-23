# ProgressBar

A progress bar shows how far a task has come along a horizontal track: how much is done (determinate), that work is happening (indeterminate), or how much is done and how much is ready (buffer).

## Anatomy
1. Active indicator: `primary`, rounded, as long as the done share.
2. Gap: 4px between the indicator and the track, and between segments.
3. Track: `secondary-container`, rounded, the remaining share.
4. Stop indicator: a 4px `primary` dot at the track's end (determinate and buffer), marking where 100% is.
5. Buffer segment (buffer only): `primary` 32% over `secondary-container`, between the indicator and the track.
6. Label row (optional): the task in `body-medium`, and the percent or position at the end in tabular figures.
7. Detail line (optional): `body-small`, `on-surface-variant`: amounts, time left, or the reason for a failure.

## Variants and when to use
| Variant | Use for |
|---|---|
| Determinate | Work with a known size: uploads, downloads, indexing, test runs with a known count. |
| Indeterminate | Work of unknown length that should finish soon: resolving, connecting, loading a page. Switch to determinate as soon as the size is known. |
| Buffer | Two measures on one scale: played and loaded, processed and received. |
| Thick (8) | The main task of a view or card, such as a first-run setup or an import screen. |
| Full-bleed | Page loading under an app bar or at the top of a pane: square ends, no gaps, the width of the container. |

Use a Progress ring where the space is square, inside a button, or beside a small label. Use a Placeholder (skeleton) when the layout of the incoming content is known and the wait is short. Show nothing for waits under 300 ms. For steps of a process the reader moves through, use a Stepper.

## Specs
| Part | Value |
|---|---|
| Height | 4 (default), 8 (thick); `radius-full` |
| Gap | 4 between segments (0 full-bleed) |
| Stop indicator | 4 dot, `primary`, at the track's end; 2 inset on the thick bar |
| Width | fills its container. At least 120 when standalone. |
| Label row | `body-medium`, `on-surface`; percent `on-surface-variant`, tabular; `space-2` 8 above the bar |
| Detail line | `body-small`, `on-surface-variant`, `space-2` 8 below |
| Status icon | `icon-sm` 18 leading the label for complete, error and paused |
| In a list row | under the headline, `space-2` 8 gap, percent as the trailing meta |
| Indeterminate segment | two segments of 10% to 60% width travel the track in sequence |

| Part | Colour role |
|---|---|
| Indicator, stop | `primary` |
| Track | `secondary-container` |
| Buffer | `primary` 32% mixed into `secondary-container` |
| Error | indicator and stop `error`, track `error-container`, icon and detail `error`, and the word "failed" in the label |
| Paused | indicator and stop `on-surface-variant`, track `surface-container-highest`, and the word "Paused" |
| Complete | a `success` check icon and a past-tense label. The bar fills and then leaves after 2 s unless the view is about the task. |

## States
Running (determinate or indeterminate), complete, paused, error. Status never rests on colour: error and paused each carry an icon and a word in the label, and the detail line says why. A disabled progress bar does not exist: hide it instead.

## Behaviour
- Determinate: the indicator eases to each new value over `duration-medium-2` with `ease-standard`. It never moves backwards. If the work restarts, the bar resets from empty with a cross-fade.
- Indeterminate: two segments travel from start to end, growing then shrinking, on a 2 s loop with `ease-linear` position and `ease-standard` width. With reduced motion, the segments fade in and out in place, pulsing 38% to 100% opacity every 2 s, and the label says the task is running.
- Appear after 300 ms of waiting to avoid a flash, and once shown stay at least 500 ms.
- Buffer: both segments ease independently.
- Error: the bar stops where it failed. A text-button action (Retry, Resume) sits at the end of the label row.
- Done: the complete state holds for 2 s, then the bar leaves with a fade (`duration-short-4`, `ease-emphasized-accelerate`), unless the view is about the task.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | 4px bar (Fluent's 3px is acceptable when the app follows Fluent throughout). Taskbar progress mirrors the main task (normal, paused, error states). |
| macOS | The same bar. The Dock icon shows the main task's progress. Indeterminate uses the pulse, never a barber pole. |
| Linux | The same bar. Launchers that support the Unity launcher API show progress on the app icon. |
| Android | Material 3 linear indicator as specified. Long tasks also post an ongoing notification with progress. |
| iOS | The same bar in content. A navigation-bar progress under the bar for page loads. Long tasks may show a Live Activity. |
| Web | `<progress>` or `role="progressbar"` with `aria-valuenow`, `aria-valuemin`, `aria-valuemax` and `aria-valuetext`. No value when indeterminate. |

## Accessibility
- Role progressbar, named by its label ("Uploading build-4128.zip"), with value 0 to 100 and a value text that carries the detail ("62%, about 20 s left"). Indeterminate has no value and is Busy.
- The region the bar loads (a list, a pane) is Busy while it runs.
- Announce politely at start, at each 25%, on completion ("Upload complete") and on failure ("Upload failed at 41%"). Never announce every tick.
- Contrast: the indicator is 3:1 against the track and the surface. Labels are 4.5:1.
- Reduced motion: indeterminate pulses in place and determinate jumps to each value.

## Content
- Label: what is happening, as a present participle with the object: "Uploading build-4128.zip", "Resolving dependencies".
- Percent: whole numbers, no decimals. Show a position instead when that means more ("1:12 / 4:30", "14 of 52 tests").
- Detail: amounts and time left in the reader's units. Say "about" for estimates. Omit the estimate when it swings.
- Error: "Upload failed at 41%" plus the cause and an action.
- Complete: past tense: "Indexed 1,232 files".

## e.ui today
`control.progress_bar` paints a `surface-variant` track `space-sm` tall, rounded to half its height, with a `primary` fill as wide as `value` (key + 1). Indeterminate draws a quarter-width segment a quarter of the way in (static) and sets Busy. The role is ProgressIndicator, named by the label. To reach this design:
- Make it 4 tall (8 thick), with a `secondary-container` track, the 4px gap, and the stop indicator.
- Animate indeterminate (two travelling segments, and a pulse under reduced motion). Today the static segment reads as 25% done.
- Add the buffer variant (`buffer: f32`) and the error, paused and complete looks with their icons.
- Put `value`, the range and a value text in the semantics. Today a reader hears the label without the amount.
- Add an optional label row and detail line, or document composing them with Text.
- Ease value changes over `duration-medium-2`, and add the 300 ms show delay and 500 ms minimum.
