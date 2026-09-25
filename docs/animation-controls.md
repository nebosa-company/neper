# e.ui motion framework — motion table for every control (next release)

This is the companion to [`animation-spec.md`](animation-spec.md) (§7.3,
§12.8). It lists every motion of every e.ui control, each as one row:

- the **pattern** from the effect vocabulary,
- its **duration** and **easing** tokens, in and out,
- the **reduced** behaviour.

**Sources**

- Rows for the 112 components with a design spec are taken from their
  `docs/ux/components/<Name>/README.md`. That README is the authority, and a
  row that disagrees with it is a bug in this table.
- For controls and behaviours with no README (§4, §5), this table is the
  design (D1214).
- §6 records how the conflicts and gaps in the design language were resolved
  (D1214–D1218). The READMEs now carry the fixes.

`scripts/check_motion_spec.py` (spec §12.8) will parse this table against
the READMEs and against the `Transition` constants in code.

## 1. Legend

**Durations** (tokens `duration-*`): **S1** short-1 (50 ms), **S2** short-2
(100), **S3** short-3 (150), **S4** short-4 (200), **M1** medium-1 (250),
**M2** medium-2 (300), **M3** medium-3 (350), **M4** medium-4 (400), **L1**
long-1, **L2** long-2 (500).
**Easings** (tokens `ease-*`): **Std** standard, **EmD** emphasized-decelerate,
**EmA** emphasized-accelerate, **Lin** linear.
**—** means there is no animation in that direction. **1:1** means the motion
follows a gesture or a scroll position, not time.
**Reduced** values (spec §10.2): **Fade** (a 100 ms fade in place), **XFade**
(a cross-fade, with the duration if one is given), **Instant**, **Static** (a
documented still frame and no frames requested), **Same** (unchanged, because
it is colour or opacity, or follows the user).

## 2. Patterns

These are the 14 patterns of spec §7.3, plus 9 that the table below needed.
§7.3 is updated to list all 23.

| Pattern | What moves | Framework pieces |
|---|---|---|
| FadeScale | fade + scale from a factor (0 for appear) at an origin | `Effect { fade, scale_from, origin }` |
| MenuGrow | fade + scale Y from 80% at the anchor edge | `Effect { scale_y_only }` |
| DropFade | fade + slide a few px | `Effect { slide }` |
| DialogEnter | scrim fade + scale 90% + height grow from the top | `Effect { scrim, scale_from, grow }` |
| EdgeSlide | slide from an edge, often with a scrim | `Effect { slide_fraction, scrim }` |
| Expand / Collapse | height (or width) grows or shrinks, with a fade | `SizeTransition` + `Faded` |
| XFade | old value fades out under the new one | `AnimatedSwitcher`, `AnimatedCrossFade` |
| FadeThrough | out, then in with scale 92% | `RouteTransition.FadeThrough` |
| SharedAxis | slide (X/Y) or scale (Z) with a fade, in the direction of travel | `RouteTransition.SharedAxis*` |
| ContainerTransform | rect and radius morph, content cross-fades | `RouteTransition.ContainerTransform` |
| Indicator | a rect or pill lerps between positions | `animated[geometry.Rect]` |
| Rotate | a glyph rotates | `RotationTransition` |
| Stroke | a path draws by length | `animated_f32` into the path's dash |
| FollowGesture | 1:1 with a pointer, then settles | `VelocityTracker` + `Simulation` |
| **Ripple** | a circle spreads from the press point and fades | `Controller` + state layer |
| **ValueEase** | a value (fill, arc, angle, number) eases to its new value | `animated_f32` |
| **Morph** | shape, radius, width or elevation changes in place | `AnimatedDecoration` |
| **Reflow** | siblings slide to their new places (FLIP) | spec §8.2 moves |
| **Pulse** | a one-off scale or colour pulse (1 → 1.15 → 1) | `Sequence[f32]` |
| **Loop** | a repeating animation (spinner, shimmer, caret) | `repeat(count = 0)`, `Static` under reduced |
| **ScrollTo** | a programmatic smooth scroll | `animate_to` on the scroll offset |
| **ScrollLinked** | a value is a function of the scroll offset, not of time | a plain function of the offset; no controller |
| **Stagger** (modifier) | siblings offset in time | `stagger` (spec §8.1, D1207) |

## 3. Components with a design spec

### 3.1 Foundations (`e.ui.widget`, P5-02)

These have no README. Their rows come from how the controls below use them.

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| StateLayer | hover, focus and press layers | XFade | S2 Std | S2 Std | Same |
| PressRipple | a press on touch hosts (Button, Row) | Ripple | M2 Std | S2 Std | Instant: layer only, no ripple (per IconButton) |
| FocusRing | focus moves | — (never animated, D1214) | — | — | — |

### 3.2 Actions (`e.ui.control`, P5-03)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| ActionRow | More's menu | MenuGrow | M1 EmD | S3 EmA | XFade |
| ActionRow | restacking when the width crosses a threshold | — | — | — | — |
| Button | press | Ripple | M2 Std | S2 Std | Instant (no ripple, D1218) |
| Fab | the menu opens: the FAB morphs to a circle with `close` | Morph | M1 EmD | S4 EmA | XFade |
| Fab | menu items enter bottom-up and leave top-down | DropFade + Stagger 30 ms | M1 EmD | S4 EmA | Fade, no stagger |
| Fab | the extended label collapses and expands on scroll | Morph (width + label fade) | M1 EmD | M1 EmD | Fade |
| Fab | hide and show (under a snackbar, sheet or keyboard) | FadeScale from 0 | S4 EmD | S4 EmA | Fade |
| Fab | a press opens the new item's view | ContainerTransform | L2 EmD | — | XFade |
| IconButton | a toggle's icon morph | XFade | S3 Std | S3 Std | Instant |
| IconButton | press | Ripple | M2 Std | S2 Std | Instant |
| Link | hover wash | XFade | S2 Std | S2 Std | Instant |
| SpeedDial | items enter from the FAB, bottom to top | DropFade + Stagger 30 ms | M1 EmD | S4 EmA | Fade together, no stagger |
| SpeedDial | the FAB morphs to a circle | Morph | M2 Std | S4 EmA | Instant |
| SplitButton | the menu scales from the button's edge | MenuGrow | M1 EmD | S4 EmA | Fade |
| SplitButton | the trailing part morphs to round | Morph | S3 Std | S3 Std | Instant |
| ToggleButton | on/off corner radius and colour | Morph | S3 Std | S3 Std | Instant |
| Toolbar | the floating toolbar hides on scroll | EdgeSlide | M2 EmD | S4 EmA | Fade |

### 3.3 Inputs (`e.ui.control`, P5-04)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| Autocomplete | the list opens | DropFade 4 px | M1 EmD | S2 EmA | Fade, no drop |
| Autocomplete | rows while filtering | — | — | — | — |
| Dial | a key step moves the arc | ValueEase | S3 Std | — | Instant |
| Dial | dragging the handle | FollowGesture | 1:1 | — | Same |
| FieldLabel | the help button's rich tooltip or popover | see Tooltip, Popover | | | |
| FieldMessage | the message changes | XFade | S2 Std | S2 Std | Same |
| FieldMessage | the height change | — (no animation, to avoid wobble) | — | — | — |
| Form | a failed submit scrolls to the summary | ScrollTo | M2 Std | — | Instant |
| Form | messages appear | XFade | S2 Std | — | Instant |
| Form | reflow between 1 and 2 columns at 840 | — | — | — | — |
| FormField | messages | XFade | S2 Std | S2 Std | Same |
| FormattedField | the error appears | XFade | S2 | — | Same |
| Rating | the chosen star pulses | Pulse (scale 1 → 1.15 → 1) | S3 Std | — | Instant |
| SearchBar | compact: the bar grows into the full-screen view | ContainerTransform | M4 EmD | S4 EmA | XFade |
| SearchBar | docked: the view grows from the bar | MenuGrow (fade + grow) | M1 EmD | S4 EmA | XFade |
| ShortcutRecorder | entering recording | — (explicitly none) | — | — | — |
| SpinBox | the value changes | — (none, as Stepper; D1214) | — | — | — |
| Stepper | the value changes | — (explicitly none) | — | — | — |
| TextField | the label floats and sinks | Morph (position + size) | S4 Std | S4 Std | XFade between the positions |
| TextField | the caret blinks | Loop | — | — | Static (no blink) |
| TokenField | chips enter and leave | FadeScale | S3 EmD | EmA | Instant |
| TokenField | the other chips reflow | Reflow | Std | Std | Instant |
| TokenField | a duplicate highlights the existing chip | Pulse (colour) | S4 | — | Same |
| ValidationSummary | appears after a failed submit | XFade | S4 EmD | — | Instant |
| ValidationSummary | the view scrolls to it | ScrollTo | *(as Form)* M2 Std | — | Instant |

### 3.4 Choices (`e.ui.control`, P5-05)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| Chip | a filter's check grows in and the label shifts | Morph | S3 Std | S3 Std | Instant |
| Chip | a removed input chip collapses its space | Collapse | — | S4 EmA | Instant |
| Choice | the checkbox fills and the tick draws | Stroke | S2 Std | S2 Std | XFade |
| Choice | the radio dot scales from 0 | FadeScale from 0 | S3 Std | S3 Std | XFade |
| ComboBox | the list opens | MenuGrow | M1 EmD | S2 EmA | Fade |
| ComboBox | the chevron turns | Rotate | S3 Std | S3 Std | Instant swap |
| ListBox | the selection fill and checkbox | XFade | S2 Std | S2 Std | Same |
| MultiSelectList | the tick | Stroke | S2 | S2 | Instant |
| MultiSelectList | the fill | XFade | S3 Std | S3 Std | Instant |
| SegmentedControl | the thumb slides | Indicator | M1 Std | — | Instant |
| SegmentedControl | the check replaces the icon and the label shifts | Morph | S3 Std | S3 Std | Instant |
| SegmentedControl | the view below updates | XFade | S4 Std | — | Same |
| Select | the menu scales down from the field in Y | MenuGrow | M1 EmD | S4 EmA | XFade |
| Select | the sheet on touch | EdgeSlide | M4 *(easing as Sheet)* | as Sheet | XFade |
| Slider | the value label on focus or drag | XFade | S2 Std | S2 *(after an S4 delay)* | XFade |
| Slider | a track press glides the handle | ValueEase | S3 Std | — | Instant |
| Slider | dragging | FollowGesture | 1:1 | — | Same |
| Switch | the thumb slides and resizes | Indicator + Morph | S3 Std | S3 Std | Instant |
| Switch | the track colour and the icon | XFade | S3 Std | S3 Std | Same |

### 3.5 Pickers (`e.ui.control`, P5-06)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| Calendar | a month change slides the grid, following the direction | SharedAxis X | M2 Std | M2 Std | XFade |
| Calendar | the year view | XFade | S4 | S4 | Same |
| ColorPicker | the panel | see Flyout | | | |
| ColorPicker | a keyboard step moves the thumb | ValueEase | S3 Std | — | Instant |
| ColorPicker | dragging | FollowGesture | 1:1 | — | Same |
| DatePicker | docked: grows from the field | MenuGrow | M1 EmD | as Menu | Fade |
| DatePicker | modal | DialogEnter | M4 EmD | S4 EmA | Fade |
| DatePicker | full screen: slides up | EdgeSlide | M4 EmD | S4 EmA | Fade |
| DurationPicker | the modal | DialogEnter | M4 EmD | S4 EmA | Fade |
| FontPicker | the popover and sheet | see Menu, Sheet; nothing inside animates | | | |
| Picker | docked menu | MenuGrow | M1 EmD | S2 | Fade |
| Picker | the sheet (it closes 150 ms after a pick) | EdgeSlide | M4 EmD | EmA | Fade |
| TimePicker | the hand and knob move | ValueEase (angle) | M2 Std | — | Instant |
| TimePicker | the hour ↔ minute switch | XFade | S4 | S4 | Instant |

### 3.6 Content (`e.ui.control`, P5-07)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| Avatar | the photo replaces the initials once decoded | XFade | S3 | — | Instant |
| Avatar | a presence change | XFade | S3 | S3 | Instant |
| Canvas | a series draws in (first data only) | Stroke | L2 EmD | — | Static (the final frame) |
| Canvas | transitions between data | ValueEase | M2 Std | M2 Std | Instant |
| Icon | a morph between two forms | XFade | S3 Std | S3 Std | Instant |
| Image | fades in once decoded | XFade | S4 Std | — | Instant |
| Image | an animated image plays once, then stops on its first frame | Loop (count 1) | — | — | Static, no autoplay |
| RichText | hover wash | XFade | S2 Std | S2 Std | Instant |
| SelectableText | the touch toolbar enters | DropFade 4 px | S4 EmD | — | Instant |
| SelectableText | the caret blinks | Loop | — | — | Static |
| Text | an in-place value change (a counter, a status) | XFade | S3 Std | S3 Std | Instant |

### 3.7 Containers (`e.ui.control`, P5-08)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| Accordion | open and close; the page keeps the header in place | Expand | M2 EmD | S4 EmA | XFade 100 |
| Accordion | the chevron | Rotate | S3 Std | S3 Std | Instant swap |
| Card | drag lift: 102% scale, 1.5° tilt (D1192) | Morph | S3 Std | S3 Std | Instant, no tilt |
| Card | Escape returns a dragged card | Reflow | M1 Std | — | Instant |
| Card | open into the detail view | ContainerTransform | L2 EmD | — | XFade |
| Card | the rise on hover | Morph (elevation) | S3 Std | S3 Std | Instant |
| Disclosure | open and close | Expand | M2 EmD | S4 EmA | XFade 100 |
| Disclosure | the chevron turns | Rotate | S3 Std | S3 Std | Instant swap |
| Divider | — | — (none; D1214) | — | — | — |
| DockLayout | the guide and the preview | XFade | S3 Std | S3 Std | Same |
| DockLayout | the preview slides between targets | Indicator | S4 | — | Instant |
| DockLayout | docking snaps | Reflow | M1 EmD | — | Instant |
| DockLayout | collapse | Collapse (width) | — | S4 | Instant |
| DockPanel | collapse and expand | Expand (height) | S4 Std | S4 Std | Instant |
| DockPanel | a torn-off panel follows the pointer | FollowGesture | 1:1 | — | Same |
| DockPanel | docking snaps | Reflow | M1 EmD | — | Instant |
| GroupBox | expand and collapse | Expand | M2 EmD | EmA | Instant |
| GroupBox | the chevron turns 180° | Rotate | S3 Std | S3 Std | Instant |
| MultiDocumentWorkspace | switching documents | — (instant, to hide typing latency) | — | — | — |
| MultiDocumentWorkspace | a new split opens | Expand (width) | M1 EmD | — | Instant |
| ResizablePane | the grip on sash hover | XFade | S2 | S2 | Instant |
| ResizablePane | collapse and reopen (also snap-to-close) | Expand (width) | M2 EmD | M2 EmA | Instant |
| SplitView | the divider snaps within 16 px of a point | Reflow | S3 Std | — | Instant |
| SplitView | stacked: the detail pushes and pops | SharedAxis X | L2 EmD | EmA | XFade 100 |

### 3.8 Status (`e.ui.control`, P5-09)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| Badge | appear and disappear | FadeScale from 0 | S3 EmD | S2 EmA | Fade (no scaling) |
| Badge | the number changes; the pill's width follows | XFade + Morph | S2 / Std | S2 | Same |
| Banner | enters and leaves by height; content below moves | Expand | M2 EmD | S4 EmA | Instant |
| EmptyState | replaces the list after a filter | XFade | S4 | — | Same |
| Gauge | the arc follows a value change | ValueEase | M2 Std | — | Instant |
| Gauge | the number counts up on first load only | ValueEase (number) | M2 Std | — | Instant |
| Level | the fill (and its threshold colour) follows a value | ValueEase | M2 Std | — | Instant |
| Level | segmented: fills segment by segment, never backwards | ValueEase | S3 each | — | Instant |
| NotificationList | a new notice slides in at the top | Reflow (insert) | M1 EmD | — | Instant |
| NotificationList | the flyout | MenuGrow | M1 | S4 | Fade |
| Placeholder | the region-wide sweep, every 1.5 s | Loop (Lin, 0.5 s pause; Skeleton's, D1217) | — | — | Static |
| Placeholder | content replaces it | XFade | S4 Std | — | Same |
| ProgressBar | determinate: eases to each value, never backwards | ValueEase | M2 Std | — | Instant |
| ProgressBar | indeterminate: two segments on a 2 s loop | Loop (Lin position, Std width) | — | — | opacity pulse 38–100% every 2 s at 10 fps (D1216) |
| ProgressBar | done: holds 2 s, then leaves (300 ms show delay, 500 ms minimum) | XFade | — | S4 EmA | Same |
| ProgressRing | determinate | ValueEase | M2 Std | — | Instant |
| ProgressRing | indeterminate: a 1.5 s spin while the length grows and shrinks | Loop (Lin spin, Std length) | — | — | a 75% arc pulsing 38–100% at 10 fps (D1216) |
| Skeleton | the shimmer: 1.5 s sweep + 0.5 s pause, in sync | Loop (Lin) | — | — | Static (D1217) |
| Skeleton | content replaces blocks one by one | XFade | S4 Std | — | Same |
| Snackbar | enters: fades and rises 8 | DropFade | M1 EmD | S4 EmA | Fade 100, no rise |
| Snackbar | a replacement waits for the current one to leave | sequence | | | |
| StatusBar | a mode change recolours the bar | XFade | S4 Std | S4 Std | Same |

### 3.9 Navigation (`e.ui.navigation`, P5-10)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| AppBar | the scrolled container colour | XFade | S4 Std | S4 Std | Same |
| AppBar | medium and large collapse with the scroll; the headline cross-fades over 40 px | ScrollLinked | 1:1 | 1:1 | Instant snap at the collapse point |
| AppBar | the contextual bar | DropFade 4 px | M2 EmD | S4 EmA | XFade S3 |
| Breadcrumbs | navigation | — (explicitly none) | — | — | — |
| Breadcrumbs | the edit field | XFade | S3 Std | S3 Std | Same |
| DestinationBar | the active pill fills from the centre | Indicator (grow) | M1 EmD | — | Instant (no growth) |
| DestinationBar | the content change between destinations | FadeThrough | M1 EmD | S3 EmA | XFade |
| DocumentTabs | tabs slide apart for a drop | Reflow | S4 Std | — | Instant |
| DocumentTabs | a new tab expands from zero width | Expand (width) | S4 EmD | — | Instant |
| DocumentTabs | a closed tab collapses | Collapse (width) | — | S3 EmA | Instant |
| MenuBar | menus appear | DropFade 4 px | S4 EmD | S2 EmA | Fade |
| MenuBar | switching between titles | — (instant) | — | — | — |
| NavigationDrawer | modal: slides in with the scrim | EdgeSlide | M2 EmD | S4 EmA | Fade the drawer and scrim |
| NavigationDrawer | standard: hides by width | Collapse (width) | M1 Std | M1 Std | Instant |
| NavigationSplit | single pane: the detail pushes in while the list shifts 30% and fades | SharedAxis X | M2 EmD | M1 EmA | XFade |
| NavigationSplit | predictive back scales the detail to 90% | FollowGesture | 1:1 | | no scale |
| NavigationSplit | side by side: the detail changes | XFade | S3 | S3 | Same |
| NavigationStack | push and pop | SharedAxis X (spec §9.1) | M2 EmD | M1 EmA | XFade S3 |
| NavigationStack | predictive back: follows, then commits or cancels | FollowGesture | commit S4 EmD | cancel S4 Std | XFade, no scale |
| PageIndicator | the pill slides and stretches between dots | Indicator | M2 Std | — | XFade S2, no stretch |
| Pagination | the current fill | XFade | S2 | S2 | Same |
| Tabs | the indicator slides and resizes | Indicator | M2 Std | — | Instant |
| Tabs | the page (compact touch: slides with the swipe) | XFade / FollowGesture | S4 | S4 | XFade 100 |
| Wizard | the content slides 8% and fades in the direction of travel | SharedAxis X | M1 EmD | — | XFade |
| Wizard | the connector fills; the progress bar advances | ValueEase | M2 Std | — | Instant |

### 3.10 Overlays (`e.ui.overlay`, P5-11)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| ActionSheet | slides up with the scrim | EdgeSlide | M4 EmD | S4 EmA | Fade |
| CommandPalette | fades and moves down 8 px into place | DropFade | S4 EmD | S2 EmA | Fade |
| CommandPalette | results | — | — | — | — |
| ContextMenu | pointer: fade and scale 0.95 at the pointer corner | FadeScale | S4 EmD | S2 EmA | Fade |
| ContextMenu | touch: the target lifts, the scrim fades, the menu grows from the target | Morph + MenuGrow | M1 EmD | S2 EmA | Fade |
| Dialog | the scrim, scale 90%, height grow | DialogEnter | M4 EmD | S4 EmA (fade) | XFade |
| Dialog | full screen: slides up | EdgeSlide | M4 EmD | S4 EmA | XFade |
| Flyout | fade and grow from the anchor edge | MenuGrow | M1 EmD | S3 EmA | Fade |
| Menu | scale Y from 80% at the anchor edge | MenuGrow | M1 EmD | S3 EmA | Fade |
| Popover | scale 90% with the beak as origin | FadeScale | M1 EmD | S3 EmA | Fade |
| Popup | fade and grow 8 from the anchor edge; results do not animate | DropFade | S4 EmD | S2 EmA | Fade |
| Sheet | slides from the edge with the scrim | EdgeSlide | M4 EmD | S4 EmA | Fade in place |
| Sheet | detent changes | ValueEase / FollowGesture | M2 Std | M2 Std | Instant |
| Tooltip | fade and scale 80% at the anchor side | FadeScale | S4 EmD | S2 EmA | Fade |
| WindowSwitcher | fade and scale 0.95; the selection moves instantly | FadeScale | S4 EmD | S2 EmA | Fade |

### 3.11 Collections (`e.ui.collection`, P5-12)

| Component | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| Carousel | snap and step | FollowGesture + settle | M4 EmD | — | Instant |
| Carousel | items resize with the scroll | ScrollLinked | 1:1 | 1:1 | one width (uncontained) |
| DataGrid | the active ring | — (instant) | — | — | — |
| DataGrid | an edited value | XFade | S2 | — | Instant |
| GridView | the selection inset of 8 | Morph | S3 Std | S3 Std | Instant |
| GridView | images once decoded | XFade | S4 | — | Same |
| GridView | tiles move when the column count changes | Reflow | M1 Std | — | Instant |
| HeaderRow | the sort arrow flips | Rotate | S3 Std | — | Instant |
| HeaderRow | reordered columns slide into place | Reflow | S4 | — | Instant |
| KeyValueEditor | a removed row collapses (Undo snackbar) | Collapse | — | S4 EmA | Instant |
| List | inserted rows grow and fade in | Expand | M1 EmD | — | XFade |
| List | removed rows collapse | Collapse | — | S4 EmA | XFade |
| Outline | the current marker slides | Indicator | M2 Std | — | Instant |
| Outline | a jump scrolls the document | ScrollTo | L2 | — | Instant |
| PageView | the strip settles after a release (back to rest with Std) | FollowGesture + settle | M4 EmD | Std | XFade S2, no slide |
| PageView | Previous and Next on hover | XFade | S2 | S2 | Same |
| PropertyGrid | groups expand and collapse | Expand | M2 EmD | M2 EmA | Instant |
| PropertyGrid | Reset | XFade | S2 | — | Instant |
| PullToRefresh | the pull follows the finger | FollowGesture | 1:1 | — | Same |
| PullToRefresh | released early: springs back | Reflow | S4 Std | — | Instant |
| PullToRefresh | refreshing | Loop (Lin spin) | — | — | Static 25% arc + "Refreshing" |
| PullToRefresh | done: the indicator scales out | FadeScale | — | S4 EmA | Fade |
| ReorderableList | lift: scale 1.02 and 4 up | Morph | S3 Std | — | no scale, shadow kept |
| ReorderableList | the other rows move out of the way | Reflow | S4 Std | — | Instant |
| ReorderableList | the drop settles into the gap | Reflow | S4 EmD | — | Instant |
| Row | press on touch | Ripple | M2 Std | S2 | Instant |
| Row | the selection fill | XFade | S3 Std | S3 Std | XFade S2 (D1218) |
| SwipeActions | settle open or closed | FollowGesture + settle | M1 EmD | Std | XFade S2 |
| SwipeActions | a destructive commit slides the row out and collapses it | EdgeSlide + Collapse | — | S4 EmA | Fade |
| Table | a live update to a cell | XFade | S4 | — | Instant |
| Table | new rows insert without moving the row under the pointer | Expand | M1 EmD | — | Instant |
| TableRow | the detail row expands and collapses | Expand | M2 EmD | M2 EmA | Instant |
| TableRow | the chevron | Rotate | S3 | S3 | Instant |
| Tree | children grow and fade | Expand | M2 EmD | S4 EmA | Instant |
| Tree | the twisty | Rotate | S3 Std | S3 Std | Instant flip |
| TreeTable | as Tree | Expand, Rotate | M2 / S3 | | Instant |
| VirtualGrid | tiles move on a size change | Reflow | M2 Std | — | XFade |
| VirtualGrid | images once decoded | XFade | S4 Std | — | Instant |
| VirtualList | the overlay thumb fades out after 1.5 s idle | XFade | — | M1 Std | Same |
| VirtualList | sticky headers push each other off | ScrollLinked | 1:1 | | Same |
| VirtualList | programmatic jumps (Home, End, "Jump to latest") | ScrollTo | M2 Std | | Instant |

The remaining `P5-12` specs (ListSpec, TableSpec, TableRowSpec, HeaderRowSpec,
RowSpec, …) are the rows above.

## 4. Controls without a design spec (D1214)

These are in the widget plan but have no README. Each row follows the
nearest specified control, and the row is the design (D1214).

| Component | Follows | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|---|
| Checkbox | Choice | tick | Stroke | S2 Std | S2 Std | XFade |
| Radio, RadioGroup | Choice | dot | FadeScale from 0 | S3 Std | S3 Std | XFade |
| AlertDialog | Dialog | enter and leave | DialogEnter | M4 EmD | S4 EmA | XFade |
| BottomSheet | Sheet | enter, leave, detents | EdgeSlide | M4 EmD | S4 EmA | Fade |
| Expander | Disclosure | open and close; chevron | Expand, Rotate | M2 EmD / S3 Std | S4 EmA | XFade 100 |
| RangeSlider | Slider | both thumbs, value labels | ValueEase, FollowGesture | S3 Std | S2 | Instant |
| TabView | Tabs | indicator and page | Indicator, XFade | M2 Std / S4 | S4 | XFade 100 |
| DateRangePicker | DatePicker | docked, modal, full screen; the range fill | MenuGrow, DialogEnter, EdgeSlide; ValueEase | as DatePicker | | Fade |
| NavigationRail, BottomNavigation, AdaptiveDestinationBar | DestinationBar | pill; content | Indicator; FadeThrough | M1 EmD | S3 EmA | XFade |
| Toast | Snackbar | enter and leave | DropFade | M1 EmD | S4 EmA | Fade |
| InfoBar | Banner | enter and leave by height | Expand | M2 EmD | S4 EmA | Instant |
| MenuButton | Select, ComboBox | menu; chevron | MenuGrow; Rotate | M1 EmD / S3 Std | S3 EmA | Fade; Instant swap |
| Sidebar | NavigationDrawer (standard) | collapse by width | Collapse (width) | M1 Std | M1 Std | Instant |
| PasswordField | TextField, Icon | label; reveal-icon morph | Morph; XFade | S4 Std / S3 Std | | XFade; Instant |
| SearchField | TextField | label; the clear button appears | Morph; XFade | S4 Std / S2 | S2 | XFade; Same |
| TextArea | TextField, FieldMessage | label; auto-grow height | Morph; — (no animation, as FieldMessage) | S4 Std | | XFade |
| Panel, Surface | — | none: static containers | — | — | — | — |

Layout primitives (Box, Row, Column, Flex, Wrap, Grid, Stack, Positioned,
Align, Center, Padding, Spacer, Constrained, AspectRatio, Fitted,
Responsive, SafeArea) have no motion of their own. Their values can be driven
by `animated[T]`. Infrastructure (FocusScope, GestureArena, OverlayPortal,
SemanticsNode, …) has none either.

## 5. Behaviours no spec covers (D1214)

| Behaviour | Motion | Pattern | In | Out | Reduced |
|---|---|---|---|---|---|
| Scrollbar / ScrollView | the overlay thumb fades after 1.5 s idle (as VirtualList); it widens on hover | XFade; Morph | S2 Std | M1 Std | Same |
| ScrollView | overscroll and fling per profile (spec §7.4); wheel smooth scrolling | FollowGesture, ScrollTo | S3 Std per notch | | discrete wheel; jumps Instant |
| ZoomView | pinch and pan follow 1:1; a pan flings with friction; zoom steps (Ctrl +/−, fit) ease | FollowGesture; ValueEase | M2 Std | | Instant steps |
| DragSource | lift: scale 1.02 + elevation (as ReorderableList); a cancelled drag returns | Morph; Reflow | S3 Std; M1 Std | | no scale; Instant return |
| DropTarget | the accept highlight; an accepted drop settles | XFade; Reflow | S2 Std; S4 EmD | | Same; Instant |
| KeyboardAvoiding | content follows the on-screen keyboard, using the host's reported curve and duration, else M2 EmD | ValueEase | host / M2 EmD | host / S4 EmA | Instant |

## 6. Resolved conflicts and gaps

| # | Issue | Resolution | Row |
|---|---|---|---|
| 1 | Nine components ask for Instant colour changes under reduced motion, while the general rule keeps them | A component's own `Reduced` value wins; "Same" is only the default | D1215 |
| 2 | Indeterminate progress wants an opacity pulse under reduced motion; spec §10.2 wanted Static | An opacity-only loop may run at 10 fps under reduced motion; every other loop is Static (amends §10.2) | D1216 |
| 3 | Placeholder and Skeleton had two different shimmers | One shimmer (1.5 s Lin + 0.5 s pause), Static under reduced motion for both; the Placeholder README is updated | D1217 |
| 4 | Row contradicted itself under reduced motion | XFade S2; "changes it at once" is withdrawn from the README | D1218 |
| 5 | Button, FieldMessage and FormattedField had no reduced line | Button: no ripple. The other two keep their fades (Same). The READMEs are updated | D1218 |
| 6 | Missing durations and easings | chevrons S3 Std; Card lift and rise S3 Std; Fab hide/show S4 EmD / S4 EmA; Slider glide S3 Std; Autocomplete and ComboBox exits EmA; Canvas data M2 Std; SelectableText toolbar and AppBar contextual bar fade with a 4 px drop; Table inserts as List; VirtualList jumps M2 Std. All are written into the READMEs | D1218 |
| 7 | Stagger was a literal 30 ms | Fab and SpeedDial cite `duration-stagger` (30 ms) | D1218 |
| 8 | `docs/ux/components/Cover` has no README | It is the catalog's cover page, not a component; motion checks skip it | D1218 |
| 9 | Timers mixed in with motion | Hover and show delays, minimum display times, close-after-pick and drop-hold times are frame-clock timers, never reduced | D1218 |
