# SegmentedControl

A segmented control (segmented button) is a joined row of 2-5 options where one (or, in its multi-select form, several) is chosen, for switching a view, a mode or a filter in place.

## Anatomy
1. Container: one outlined pill, 1 px `outline`, `radius-full` (touch) or `radius-sm` (pointer density).
2. Segments: equal-width, divided by 1 px `outline` lines.
3. Label: `label-large`, one line.
4. Optional icon: `icon-sm` 18; in the selected segment it is replaced by the check.
5. Selected fill: `secondary-container` with the `check` icon.
6. State layer per segment; focus ring inset in the focused segment.

## Variants and when to use
| Variant | Behaviour | Use for |
|---|---|---|
| Single select | exactly one on, like radios | Switching views or modes: Day / Week / Month, Code / Preview / Split. |
| Multi select | any number on, like checkboxes | A few independent toggles of one kind: target platforms. |
| Icons only | same, no labels | Toolbars with well-known view icons (list / thumbnails / details); each segment has a tooltip. |
| Thumb (macOS, iOS) | sliding thumb on a track | The same control on Apple hosts, matching NSSegmentedControl and UISegmentedControl. |

Use Tabs when the options are separate destinations with their own content and history. Use Radio group for more than five options or long labels. Use filter chips for many optional filters. Use Toggle buttons for unrelated on/off actions.

## Specs
| | Default (touch) | Small (pointer, density -1) | Thumb (Apple) |
|---|---|---|---|
| Height | `control-md` 40 | `control-sm` 32 | `control-sm` 32 (28 inner) |
| Radius | `radius-full` | `radius-sm` 8 | track `radius-sm` 8, thumb 6 |
| Segment min width | 88 (56 icons only) | 72 | 80 |
| Side padding | `space-3` 12 | `space-3` 12 | `space-3` 12 |
| Label | `label-large` 14/20 600 | 13/20 600 | 13/18, 600 when selected |
| Icon / check | `icon-sm` 18, `space-2` 8 gap; icons-only segments keep their icon (no check) and show selection by the fill alone plus Checked in the tree, so use them only where the fill contrast is 3:1 | 18 | none |
| Edge and dividers | 1 px `outline` | 1 px `outline` | none; dividers `outline-variant` between unselected segments |
| Selected | `secondary-container` / `on-secondary-container` + check | same | thumb `surface-container-lowest` + `elevation-1` on a `surface-container-highest` track |
| Unselected label | `on-surface` | `on-surface` | `on-surface` |
| Target | 48 on touch hosts | 32 | 32 |
| Count | 2-5 segments | 2-5 | 2-5 |

## States
- Hover: state layer at `state-hover` in the segment's label colour.
- Focus: `state-focus` layer and the focus ring inset 3 px inside the segment (segments are edge-to-edge in the container).
- Pressed: `state-pressed`; ripple on touch.
- Selected: fill and check; the check replaces the icon over `duration-short-3` with `ease-standard`, and the label shifts to make room. The thumb slides over `duration-medium-1` with `ease-standard`.
- Disabled segment: label 38% `on-surface`; not focusable, skipped by arrows.
- Disabled control: labels 38%, edges and dividers `on-surface` 12%, a selected segment's fill `on-surface` 12%.

## Behaviour
- Single select: the control is one Tab stop on the selected segment; Left and Right move and select (selection follows focus, as radios), Home and End go to the first and last; Space and Enter also select.
- Multi select: one Tab stop; arrows move focus without changing state; Space or Enter toggles the focused segment.
- A single-select control never has zero selected; a multi-select control may.
- Segments share width equally; when the longest label does not fit, the control is the wrong component (use a Select or Radio group), never truncate.
- A press applies the change at once; the view below updates in place with a cross-fade in `duration-short-4` with `ease-standard`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Small, `radius-sm`; WinUI "SelectorBar"-like pages may use Tabs instead; arrows select. |
| macOS | Thumb style, 28-32 tall, matching NSSegmentedControl; in toolbars the icons-only form with tooltips. |
| Linux | Small, `radius-sm`; GNOME uses linked toggle buttons (the same geometry) in header bars. |
| Android | Default 40 with 48 targets, `radius-full`, check on selection (Material segmented button). |
| iOS | Thumb style (UISegmentedControl), 32 tall; no check; haptic tick on change. |
| Web | Default at touch widths, small at pointer widths; single select is a `radiogroup` of `radio`s, multi select a `group` of `aria-pressed` buttons. |

## Accessibility
- Single select: role Radio group named by the control's label ("Range"), segments are Radio buttons with Checked.
- Multi select: role Group named by the label, segments are toggle Buttons with Pressed.
- Icons-only segments are named ("List view") and have tooltips.
- Selection never relies on colour: the check (or the elevated thumb and bold label on Apple hosts) shows it.
- Contrast: labels 4.5:1 on their fill; the outline 3:1 against the ground.
- Target: 48 on touch hosts by segment height or padding.
- Reduced motion: the check and thumb swap without sliding.

## Content
- 1-2 words per segment, parallel in form, sentence case: "Day, Week, Month", "Code, Preview, Split".
- Similar lengths; the control is as wide as its longest label times the count.
- The group label names the dimension ("Range"), shown as a Text before the control or used only for accessibility when the context is obvious.

## e.ui today
`control.segmented_control` lays out one `toggle_button` per label with no gap, keyed `key + 1 + index`: the selected one Filled (plus the 50% `selection` tint), the rest Outlined, each with its own `radius-md` corners, in a Group named `label`. To reach this design:
- Join the segments into one outlined container with shared dividers and outer rounded ends, instead of separate buttons.
- Fill the selected segment with `secondary-container` and add the check; drop the Filled `primary` look and the `selection` tint.
- Report a Radio group with Checked radios, and add arrow-key selection with one Tab stop.
- Add the multi-select, icon and icons-only forms, per-segment disabled, and the focus ring inset in the segment.
- Add the thumb style for macOS and iOS hosts.
