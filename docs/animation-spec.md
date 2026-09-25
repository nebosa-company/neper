# e.ui motion framework — design specification (next release)

**Status: next release, design only.** Nothing in this document is
implemented. The work is inventoried as widget-plan phase `P6` (blocked by
`next-release`), and [`animation-plan.md`](animation-plan.md) holds the
inventory and order (D1198). This document describes what the framework is:
the modules and components, how they behave, the transition effects, how
existing widgets adopt it, and how every part is tested.

API sketches are written in neper, but they are **proposals**. They are not in
`docs/module-apis.md`, so they create no fence debt. Each sketch moves into
`module-apis.md` when its P6 item opens. Settled choices are marked
**Decided (D<n>)**. All nine were locked in D1201–D1209.

---

## 1. Goals and non-goals

**Goals**

1. Match Flutter's animation stack, feature for feature: curves, tweens,
   controllers, physics, implicit animations, explicit transitions,
   choreography, shared-element (hero) and route transitions, and test tooling.
   §15 is the parity table.
2. Let the motion already specified by the v2 design language
   (`docs/ux/components/*/README.md`, 100+ `Motion:` lines using
   `duration-*`/`ease-*` tokens) be written as **data**, one line per
   component, instead of hand-rolled code in each widget.
3. Make reduced motion a single framework policy with a host source (§10), so
   it is not a flag each widget has to check.
4. Keep idle apps idle: zero frames are requested once every animation has
   settled.
5. Make it deterministic: an animated value is a pure function of state and a
   frame instant, identical on Windows and Linux, and testable at any instant
   without real time passing.

**Non-goals**

- Vector animation players (Lottie, Rive), animated icon morphs (Flutter's
  `AnimatedIcon`) and 3D or particle effects. These are later work beside
  `e.ui.asset`.
- A retained, mutable widget tree. The framework keeps e.ui's immediate build
  model.
- Callbacks as the primary API (§2, P1).

---

## 2. Principles

- **P1 — Pull, not push.** A widget reads an animated value while it builds,
  at the frame instant the runtime provides. There are no listeners and no
  `AnimatedBuilder`. A status change (started, completed, dismissed) is an
  *edge* that the caller detects by comparing the status at the previous and
  current frame instants. Where a callback is natural, such as a route that
  finished popping, it is a `widget.Change[T]` / `widget.Submit` like
  everywhere else in e.ui, and it is invoked once, from the frame that
  crossed the edge.
- **P2 — Explicit animations are caller-owned data.** A `Controller` is a
  plain struct in the application's model. There is no registration, no
  ticker object and no dispose.
- **P3 — Implicit animations are runtime-owned and keyed.** An implicit
  widget, such as `animated_opacity(key, 0.4, spec, child)`, stores its
  `from`/`to`/controller state in the widget runtime under the element's
  stable key, the same way drag cells and hover state are stored. The caller
  writes only the target value.
  **Decided (D1201):** runtime-keyed state (Flutter ergonomics, and nothing for the
  caller to own) over caller-owned `*AnimState` fields. The capacity is bounded
  by `widget.Limits.animations`. On overflow the animation snaps to its target
  and is counted in `AnimationFrameStats`, and never fails.
- **P4 — Retarget from where you are.** Changing a target mid-flight starts
  the new animation from the current value *and velocity*. Every animation is
  C0-continuous across a retarget. Simulations are also C1-continuous
  (velocity carries over).
- **P5 — Compositor-only when possible.** Opacity and transform changes patch
  the retained scene: an `OpacityLayer` (`e.gfx.scene`) or a
  `VisualTransform` (D1192). They need no rebuild or layout, and damage is the
  union of the old and new painted bounds (D914/D916). Only size and layout
  transitions re-run layout, and only for the animated subtree.
- **P6 — Paint moves, semantics does not.** Following D1192, visual
  transforms leave hit testing and the accessibility tree at their layout
  geometry. Layout-affecting animations (size, list insert) report their
  *target* geometry to accessibility at once. Screen readers never see
  intermediate frames.
- **P7 — Tokens first.** Components take durations and curves from theme
  tokens (`duration-short-1` … `duration-long-2`, `ease-standard`,
  `ease-emphasized-decelerate`, `ease-emphasized-accelerate`, `ease-linear`).
  Literal durations are for application code only.
- **P8 — One clock.** All animation time comes from `widget.frame_time`.
  Nothing reads the wall clock. A frozen scope freezes its own clock (§4.4).

---

## 3. Architecture

```
 host vsync / timer ──► app loop ──► widget.set_frame_time(now)
                                        │
                   ┌────────────────────┴─────────────────────┐
                   │ build (caller code + e.ui builders)      │
                   │   Controller / Simulation ─► fraction    │
                   │   Curve ─► eased fraction                │
                   │   Tween[T] ─► value                      │
                   │   implicit slots (runtime, keyed)        │
                   └────────────────────┬─────────────────────┘
                                        │ nodes: Faded, Transformed,
                                        │        Sized, ordinary layout
                   ┌────────────────────┴─────────────────────┐
                   │ reconcile ─► compositor-only patch? ─yes─► patch scene layer
                   │                      │no                 │
                   │                   layout ─► paint ─► damage
                   └────────────────────┬─────────────────────┘
                                        │
                  any active animation? ─yes─► request_animation_frame
                                        └─no──► sleep until input
```

**Frame lifecycle**

1. The host wakes up on input, on a timer or on vsync after a requested
   frame, and calls `set_frame_time(now)`, a monotonic instant.
2. Build runs. Every animated read goes through `animation.*` and marks the
   runtime *active* when it is not settled (`request` or
   `request_animation_frame`).
3. Reconcile compares keyed nodes. When a subtree differs *only* in a
   `Faded` opacity or a `Transformed` value, it is patched in the retained
   scene (P5).
4. After paint, the runtime asks the host for another frame only if some read
   in this frame was active. Otherwise the loop blocks on input (goal 4).

---

## 4. `e.ui.animation`: the core (extended from D800)

This part has no UI. It depends on `e.time` and `e.ui.widget` (for the frame
clock and frame requests). It also uses `e.gfx.paint`/`e.gfx.geometry` for the
built-in tween types.

### 4.1 Curves (P6-01)

A curve maps `t ∈ [0,1]` to an eased fraction. The fraction may overshoot for
the back and elastic curves. A curve is a **value**, not a function pointer,
so it can live in a theme token, be compared and be hashed into a node key.

```neper
type CubicBezier = struct { x1: f32, y1: f32, x2: f32, y2: f32 }
type CurveName = enum u8 {
    Linear, Decelerate, Ease, EaseIn, EaseOut, EaseInOut, FastOutSlowIn,
    EaseInSine, EaseInQuad, EaseInCubic, EaseInQuart, EaseInQuint, EaseInExpo, EaseInCirc, EaseInBack,
    EaseOutSine, EaseOutQuad, EaseOutCubic, EaseOutQuart, EaseOutQuint, EaseOutExpo, EaseOutCirc, EaseOutBack,
    EaseInOutSine, EaseInOutQuad, EaseInOutCubic, EaseInOutQuart, EaseInOutQuint, EaseInOutExpo, EaseInOutCirc, EaseInOutBack,
    EaseInToLinear, LinearToEaseOut, FastLinearToSlowEaseIn, FastEaseInToSlowEaseOut, SlowMiddle,
    EaseInOutCubicEmphasized, BounceIn, BounceOut, BounceInOut, ElasticIn, ElasticOut, ElasticInOut,
    Standard, EmphasizedDecelerate, EmphasizedAccelerate
}
type CurveShape = union enum u8 { Named: CurveName, Cubic: CubicBezier, Steps: u16, Threshold: f32 }
// Interval, flip and reverse compose onto any shape without recursion.
type Curve = struct { shape: CurveShape, begin: f32, end: f32, flipped: bool, reversed: bool }

fn curve(name: CurveName) -> Curve
fn cubic(x1: f32, y1: f32, x2: f32, y2: f32) -> (Curve, err)    // x1, x2 in [0,1], else Invalid
fn interval(c: Curve, begin: f32, end: f32) -> (Curve, err)      // 0 <= begin <= end <= 1
fn flipped(c: Curve) -> Curve                                    // 1 - c(1 - t)
fn reversed(c: Curve) -> Curve                                   // c(1 - t)
fn steps(count: u16) -> Curve
fn transform(c: Curve, t: f32) -> f32                            // the one evaluator
fn token_curve(t: *const style.ThemeTokens, token: style.EaseToken) -> Curve
```

**Behaviour**

- `transform` clamps `t` to `[0,1]`, applies the interval (0 before `begin`,
  1 after `end`, rescaled between them), then `reversed`/`flipped`, then the
  shape. It always returns exactly 0 at `t = 0` and exactly 1 at `t = 1` for
  every shape except `Threshold` and `Steps`, whose ends are also exact.
- **Cubic solving:** Newton–Raphson on `x(s)`, up to 8 iterations with an
  epsilon of 1e-6, with a bisection fallback when the derivative is below
  1e-6. The result is correct to 1e-5 in `y` for every control-point set,
  including `x1 = x2` and overshooting `y1`/`y2`.
- **The named catalog** matches Flutter's `Curves` constants: the same cubic
  control points, the same closed forms for Decelerate, Bounce and Elastic
  (period 0.4), and the same three-point cubics for `FastEaseInToSlowEaseOut`
  and `EaseInOutCubicEmphasized`. The reference values are generated from
  Flutter's `curves.dart` formulas (§12.1), not typed by hand.
- `Standard`, `EmphasizedDecelerate` and `EmphasizedAccelerate` are the v2
  tokens (`cubic-bezier(0.2,0,0,1)`, `(0.05,0.7,0.1,1)` and
  `(0.3,0,0.8,0.15)`), generated from `docs/ux/tokens.json` into
  `style.e`'s theme block the way the colours are (D938).
- D800's `Curve` enum (`Linear`, `EaseIn`, `EaseOut`, `EaseInOut`) keeps its
  quadratic meaning under the names `QuadIn`/`QuadOut`/`QuadInOut` for source
  compatibility. **Decided (D1202):** alias the old enum members to the new
  constructors and mark them deprecated, rather than changing their shape
  silently.

### 4.2 Tweens (P6-02)

```neper
type Tween[T: type] = struct { begin: T, end: T }
fn at[T: type](tw: *const Tween[T], t: f32) -> T              // T.lerp(begin, end, t)
fn tween[T: type](begin: T, end: T) -> Tween[T]

type Segment[T: type] = struct { tween: Tween[T], weight: f32, curve: Curve }
type Sequence[T: type] = struct { segments: []const Segment[T] }
fn sequence_at[T: type](s: *const Sequence[T], t: f32) -> T

// Provided lerps (T.lerp(a, b, t) is the whole contract, like T.eq in e.test):
//   f32, f64            linear, extrapolates outside [0,1]
//   i32, i64            round-half-away of the f64 lerp
//   bool, enums         discrete: a below t = 0.5, b from 0.5 on
//   paint.Color         premultiplied linear light, then back to sRGB
//   geometry.Point/Size/Rect/Insets, style.Radii   per component
//   geometry.Transform  decompose (translate, rotate, scale, skew), lerp, recompose;
//                       rotation takes the shorter arc
//   style.Shadow / elevation                        per component; count mismatch pads with transparent
//   paint.Brush         same kind and stop count: per stop; otherwise a cross-fade
//   layout.Style (text) size, weight, colour and spacing lerp; family is discrete
```

**Behaviour**

- `at(tw, 0)` returns `begin` and `at(tw, 1)` returns `end`, bit for bit, for
  every provided `T`.
- Values of `t` outside `[0,1]` (from back or elastic curves) extrapolate for
  continuous types and clamp for discrete ones. Colour channels clamp after
  conversion.
- `Sequence` normalises the weights. A segment's local `t` goes through its own
  curve. A zero total weight is `Invalid`.
- **Decided (D1203):** colour interpolates in *premultiplied linear light* (no
  muddy midpoints, and it matches the renderer's linear blending). The
  alternative is Oklab: better for hue changes, but it costs more and would be
  different from blending.

### 4.3 Controller v2 (P6-03)

```neper
type Status = enum u8 { Dismissed, Forward, Reverse, Completed }
type Drive = union enum u8 { Idle, Timed: Timed, Physics: sim.Simulation, Repeat: Repeat }
type Controller = struct {
    lower: f32, upper: f32,              // default 0 and 1
    duration: time.Duration, reverse_duration: time.Duration,
    curve: Curve, drive: Drive, status: Status,
    origin: f32, origin_velocity: f32, started: time.Instant, scope: ScopeId
}

fn controller(now: time.Instant, duration: time.Duration, curve: Curve) -> Controller   // D800 signature kept
fn forward(c: *Controller, now: time.Instant)
fn reverse(c: *Controller, now: time.Instant)
fn animate_to(c: *Controller, now: time.Instant, target: f32, duration: time.Duration, curve: Curve)
fn animate_with(c: *Controller, now: time.Instant, s: sim.Simulation)                   // fling, spring
fn repeat(c: *Controller, now: time.Instant, lower: f32, upper: f32, mirror: bool, count: u32)  // 0 = forever
fn stop(c: *Controller, now: time.Instant)                                              // freezes value
fn jump(c: *Controller, value: f32)                                                     // no animation
fn value(c: *const Controller, now: time.Instant) -> f32
fn velocity(c: *const Controller, now: time.Instant) -> f32                             // units per second
fn status(c: *const Controller, now: time.Instant) -> Status
fn status_changed(c: *const Controller, before: time.Instant, now: time.Instant) -> (Status, bool)
fn settled(c: *const Controller, now: time.Instant) -> bool
fn watch(runtime: *widget.Runtime, c: *const Controller, element: widget.ElementId)     // request while !settled
```

**Behaviour**

- **Status transitions.** From `Dismissed`, `forward` gives `Forward`, then
  `Completed` at `upper`. From `Completed`, `reverse` gives `Reverse`, then
  `Dismissed` at `lower`. `animate_to` gives `Forward` or `Reverse` by
  direction, and a target equal to the current value keeps the status. `stop`
  keeps the direction's status but stops time. `repeat` reports `Forward` (or
  alternates in mirror mode) and completes after `count` turns.
- **Retarget (P4).** Every driving call captures `origin = value(now)` and
  `origin_velocity = velocity(now)` first. A timed drive then runs from
  `origin`, so there is no jump. A physics drive starts with
  `origin_velocity`.
- **Remaining duration.** `forward` from 0.6 runs for 40% of `duration`,
  matching Flutter. `reverse` uses `reverse_duration` when it is non-zero.
- **Settling.** A timed drive is settled at its end instant. A physics drive is
  settled when the simulation's `done` holds (§5). `repeat(count = 0)` never
  settles, which is why loops must respect reduced motion (§10.2).
- **Compatibility.** D800's `value`, `finished`, `restart`, `cycle`, `pulse`
  and `triangle` keep their signatures and meanings.

### 4.4 Clock, scopes and dilation (P6-03)

```neper
type ScopeId = struct { slot: u32, generation: u32 }
fn ticker_scope(key: widget.Key, enabled: bool, children: []const widget.Node) -> widget.Node
fn scope_time(runtime: *widget.Runtime, scope: ScopeId) -> time.Instant
fn set_time_dilation(runtime: *widget.Runtime, factor: f32)     // debug slow motion; 1 = normal
```

- A disabled `ticker_scope`, and a subtree that is hidden, off-screen in a
  lazy viewport or in a background document tab, **freezes its scope clock**:
  `scope_time` stops advancing and its reads never request frames. When the
  scope is enabled again, the clock resumes from where it stopped, so
  animations continue rather than jumping to their end. (This is Flutter's
  `TickerMode`.)
- The runtime keeps one accumulated pause offset per scope. It is bounded by
  `Limits.scopes`, and a subtree beyond that inherits its parent's scope.
- Time dilation divides elapsed time for every scope. It is a debug tool,
  exposed in the example gallery and never persisted.

---

## 5. `e.ui.animation`: physics (P6-04)

This lives in the same module (`sim` below is a namespace inside
`e.ui.animation`, not a separate module).
**Decided (D1204):** keep physics in `e.ui.animation` and not in a new module: it
has no other consumers, and `modules.json` gains no row.

```neper
type Spring = struct { mass: f32, stiffness: f32, damping: f32 }
type Tolerance = struct { distance: f32, velocity: f32, time: f32 }       // default 1e-3, 1e-3, 1e-3
type Simulation = union enum u8 {
    Spring: SpringSim, Friction: FrictionSim, BoundedFriction: BoundedFrictionSim,
    Gravity: GravitySim, ScrollSpring: SpringSim, Clamped: ClampedSim
}
fn spring(mass: f32, stiffness: f32, damping: f32) -> (Spring, err)       // all > 0 (damping >= 0)
fn spring_ratio(mass: f32, stiffness: f32, ratio: f32) -> (Spring, err)   // damping = ratio * 2 * sqrt(m k)
fn spring_sim(s: Spring, start: f32, end: f32, velocity: f32, tol: Tolerance) -> Simulation
fn friction_sim(drag: f32, position: f32, velocity: f32, tol: Tolerance) -> Simulation
fn gravity_sim(acceleration: f32, start: f32, end: f32, velocity: f32) -> Simulation
fn clamped(s: Simulation, min_x: f32, max_x: f32, min_dx: f32, max_dx: f32) -> Simulation
fn x(s: *const Simulation, seconds: f64) -> f32
fn dx(s: *const Simulation, seconds: f64) -> f32
fn done(s: *const Simulation, seconds: f64) -> bool

type VelocityTracker = struct { samples: [20]Sample, count: usize, head: usize }
fn track(v: *VelocityTracker, at: time.Instant, position: geometry.Point)
fn estimate(v: *const VelocityTracker) -> (geometry.Point, f32)           // px/s, confidence 0..1
```

**Behaviour**

- **Spring:** the closed-form solution of `m x'' + c x' + k (x − end) = 0` in
  all three regimes: critically damped (`c² = 4mk` within 1e-6 relative),
  underdamped and overdamped. It is never integrated numerically. `done`
  holds when `|x − end| < tol.distance` and `|dx| < tol.velocity`.
- **Friction:** `x(t) = x0 + v0·(dragᵗ − 1)/ln drag`. `done` holds when
  `|dx| < tol.velocity`. `BoundedFriction` clamps x to its bounds and is done
  on reaching one.
- **Gravity:** constant acceleration, done at `end`.
- **ScrollSpring:** the underdamped spring used for overscroll return (the
  iOS/macOS feel), with Flutter's default description.
- **VelocityTracker:** a least-squares quadratic fit over the samples of the
  last 100 ms, with at most 20 samples, as in Flutter's
  `VelocityTracker`. Samples older than 40 ms after the latest one (a pointer
  that paused) give zero velocity. The confidence is R².
- **Fling** (`FlingGesture`): a `DragEnd` carries the tracker's estimate.
  Scroll views, page views, carousels, sheets, drawers, swipe actions and
  pull-to-refresh start a friction or spring simulation with it (§7.4). The
  hand-written overshoot in `widget.e` (`// offset past an end springs back`)
  is replaced by `ScrollSpring` (`ScrollPhysicsOnSprings`).

---

## 6. Implicit animations (P6-05)

An implicit animation takes a **target** and a **MotionSpec**. When the
target changes between builds, the animation runs from the current value to
the new one (P3, P4).

```neper
type MotionSpec = struct { duration: style.DurationToken, curve: style.EaseToken,
                           exit_duration: style.DurationToken, exit_curve: style.EaseToken }
fn motion(d: style.DurationToken, c: style.EaseToken) -> MotionSpec                  // same both ways
fn enter_exit(d_in: style.DurationToken, c_in: style.EaseToken,
              d_out: style.DurationToken, c_out: style.EaseToken) -> MotionSpec

// The primitive every implicit widget uses. The runtime keys it by `key`.
fn animated_f32(runtime: *widget.Runtime, key: widget.Key, target: f32, spec: MotionSpec) -> f32
fn animated[T: type](runtime: *widget.Runtime, key: widget.Key, target: T, spec: MotionSpec) -> T
```

**Components** (each is a `widget.Node` builder that takes
`a: *mem.Arena, key: widget.Key` first, like every e.ui builder):

| Component | Animates | Notes |
|---|---|---|
| `AnimatedValue` | `animated_f32` / `animated[T]` | the primitive; available to custom widgets |
| `AnimatedOpacity` | opacity | compositor-only (`Faded`); at 0 it paints nothing and is not hit-testable |
| `AnimatedLayout` | alignment, padding, size | `animated_align`, `animated_padding`, `animated_size` (clips while it grows; a spec picks the alignment of the clip) |
| `AnimatedDecoration` | fill, border, radii, elevation, width and height constraints | Flutter's `AnimatedContainer`; lerps a `style.Style` field by field |
| `AnimatedTextStyle` | text size, weight, colour, letter spacing | relayout per frame only while it is running |
| `AnimatedSwitcher` | child identity (the key of `child`) | when the child's key changes, the old child becomes a paint-only *ghost* (§8.3) that exits while the new child enters; the effect comes from §7 (default: `Fade`); children stack at the larger size |
| `AnimatedCrossFade` | a boolean choosing between two children | fades both children and lerps the size between them |

**Behaviour**

- **First build:** there is no animation. The value starts at the target.
  (**Decided (D1205):** `appear: bool` in the spec opts into an entrance from a
  given start value. Flutter makes you wrap in `TweenAnimationBuilder` for
  this.)
- **Keys:** implicit state lives under `key ^ fnv1a64("anim")`, derived with
  the same helper as D1121, so it can never collide with the caller's row
  keys. A widget that leaves the tree frees its slot at the end of that frame.
- **Reduced motion:** the value jumps to the target, and `AnimatedSwitcher` /
  `AnimatedCrossFade` use the reduced fallback (§10.2).

---

## 7. Transition effects (P6-06)

### 7.1 Node kinds

One kind is added to `widget.Kind`, and one existing kind is reused:

```neper
// widget.Kind gains:  Faded: f32        -- subtree opacity, maps to scene.OpacityLayer
fn faded(key: Key, opacity: f32, value_style: style.Style, children: []const Node) -> Node
// existing (D1192):   Transformed: VisualTransform { scale, rotation, offset }
```

**Decided (D1206):** make opacity a node kind, not a `style.Style` field. A kind
lets reconcile identify an opacity-only change without diffing every style
field, and it matches `Transformed`. Both are paint-only (P6).

### 7.2 Explicit transitions

Each transition takes a value that the caller computed, usually a
`Controller` through a curve and a tween, and wraps a child:

| Component | Parameter | Maps to |
|---|---|---|
| `FadeTransition` | opacity `f32` | `Faded` |
| `ScaleTransition` | scale `f32`, origin `Alignment` | `Transformed` (scale about the origin) |
| `RotationTransition` | turns `f32` | `Transformed` |
| `SlideTransition` | offset as a fraction of the child's own size | `Transformed` (offset = fraction × laid-out size) |
| `SizeTransition` | axis, factor `f32`, alignment | layout (clip + size); the only one that relayouts |
| `AlignTransition`, `DecoratedBoxTransition`, `TextStyleTransition` | value | the implicit primitives (§6) with an external value |

`CompositorOnlyUpdate` is the rule-P5 fast path. Its acceptance fixture
asserts `rebuilt_elements == 0` and `layouts == 0` for every frame of a fade
and a slide, and a damage rectangle equal to the union of the old and new
bounds.

### 7.3 The effect vocabulary

The v2 design language writes motion as a combination of a few effects. The
framework names them as data, so a component's motion is one `Effect` value:

```neper
type Origin = enum u8 { Center, AnchorEdge, Pointer, TopStart, Top, Bottom, Start, End }
type Effect = struct {
    fade: bool,
    scale_from: f32,          // 1 = none; 0.8 tooltip, 0.9 dialog/popover, 0.95 context menu, window switcher
    scale_y_only: bool,       // menus grow in Y from the anchor edge
    slide: geometry.Point,    // px; (0, 8) popup, (0, 4) menu bar, (0, -8) command palette
    slide_fraction: geometry.Point,  // fraction of size; sheets and drawers slide from the edge = 1.0
    grow: bool,               // height grows from the origin (dialog, disclosure, tree children)
    origin: Origin,
    scrim: bool               // the modal scrim fades with the container
}
type Transition = struct { enter: Effect, exit: Effect, spec: MotionSpec, reduced: Reduced }
type Reduced = enum u8 { Fade, CrossFade, Instant, StaticFrame }
```

The named patterns below cover every `Motion:` line in `docs/ux/components`:

| Pattern | Enter | Exit | Used by (examples) |
|---|---|---|---|
| **FadeScale** | fade + scale from 0.8–0.95 at an origin | fade | Tooltip, ContextMenu, Popover, WindowSwitcher |
| **MenuGrow** | fade + scale Y from 80% at the anchor edge | fade | Menu, Select, ActionRow's More |
| **DropFade** | fade + slide 4–8 px | fade | Popup, MenuBar, CommandPalette |
| **DialogEnter** | scrim fade + scale from 90% + height grows from the top | fade | Dialog, modal DatePicker |
| **EdgeSlide** | slide from an edge (fraction 1) + scrim fade | slide back + fade | Sheet, BottomSheet, ActionSheet, NavigationDrawer |
| **Expand** | height grows + fade | height shrinks | Accordion, Disclosure, Tree, TreeTable, TableRow detail, PropertyGrid groups, DockPanel |
| **CrossFade** | fade in over the old value | fade out | FormField messages, DataGrid edits, ListBox fill, Switch track |
| **FadeThrough** | the old content fades out (accelerate, short), then the new fades in and scales from 92% (decelerate, medium) | — | DestinationBar content, route changes between peers |
| **SharedAxis** (X/Y/Z) | the new content slides 30 px (or scales for Z) and fades in while the old slides and fades out, in the direction of travel | mirrored | Wizard (8%), Calendar months, NavigationSplit |
| **ContainerTransform** | the container morphs its rect and radius from the source to the destination, and its content cross-fades | the reverse | Card → detail, FAB → sheet |
| **Indicator** | a rect or pill lerps between positions | — | Tabs, DestinationBar pill, Outline marker, SegmentedControl |
| **Rotate** | a chevron rotates 90° or 180° | — | Tree twisty, HeaderRow sort arrow, Expander |
| **Stroke** | a path draws by length fraction | — | Checkbox tick, the connector in Wizard |
| **FollowGesture** | tracks the pointer 1:1, then settles by spring or friction | — | PageView, Carousel, Sheet detents, SwipeActions, PullToRefresh, predictive back |

**Behaviour**

- The exit always uses `exit_duration`/`exit_curve`, which default to
  `duration-short-2`–`4` with `ease-emphasized-accelerate` per the language.
- **Interrupting an exit** (reopening a closing menu) reverses from the
  current value (P4) and never restarts from zero.
- A container that is entering or exiting is **inert to input** until it
  has fully entered, except for the scrim, whose press dismisses at once.
  Focus moves when the transition *starts*: into an entering container, and
  back to the invoker on exit.

### 7.4 Scroll physics per profile

| `style.Profile` | Overscroll | Fling | Wheel |
|---|---|---|---|
| `Neper`, `DesktopDense` | clamp, no glow | friction (drag 0.135) | smooth: each notch animates over `duration-short-3` with `ease-standard`, and further notches retarget (P4) |
| `Touch`, `MaterialLike` | stretch (content scales up to 1.05 along the axis at the edge) | friction | discrete |
| `CupertinoLike` | bounce (`ScrollSpring`, rubber-band resistance 0.52) | friction with bounce at the ends | discrete |

Reduced motion: wheel scrolling is discrete, programmatic jumps (Home, End,
"Jump to latest") are instant, and flings still coast, because a fling
continues the user's own motion (WCAG 2.3.3 covers motion the user did not
start).

---

## 8. Choreography (P6-07)

### 8.1 Staggered and sequenced groups

```neper
fn stagger(t: *const style.ThemeTokens, index: usize, count: usize, spec: MotionSpec) -> (Curve, time.Duration)
fn sequence_of(parts: []const f32) -> []const Curve   // weights -> contiguous intervals over one controller
```

`stagger` returns an `interval` curve for item `index` and the total
duration: `duration + stagger × (count − 1)`, where `stagger` is the token
(`Durations.stagger`). It is capped at 8 steps, so long lists do not wait.
**Decided (D1207):** the cap is 8, the Material guidance. Items past the cap enter
together with the eighth.

### 8.2 Keyed list and grid changes (`AnimatedListChanges`, `AnimatedGridChanges`)

`List`, `VirtualList`, `GridView`, `VirtualGrid`, `Table` and
`ReorderableList` gain an `animate: MotionSpec` option. The runtime diffs the
previous and current **key sequences** of the built rows:

| Change | Motion |
|---|---|
| Inserted key | the row's height grows from 0 (`SizeTransition`) and it fades in, using `ease-emphasized-decelerate` |
| Removed key | the row becomes a **ghost** (§8.3) that shrinks and fades, using `ease-emphasized-accelerate` |
| Moved key | **FLIP**: the row is laid out at its new place and painted with a `Transformed` offset from the old rect to the new one, which animates to zero |
| Same key, same place | nothing |

Moves use the offset only, so they are compositor-only (P5). Inserts and
removes relayout the rows below them. Rows outside the built window
(`VirtualList`) snap. Reduced motion cross-fades inserts and removes, and
snaps moves.

### 8.3 Ghosts

A widget that leaves the tree while its exit transition runs can no longer be
rebuilt, because its builder and caller data are gone. The runtime therefore
keeps its **retained scene subtree** (the paint commands, which the damage
repaint already retains since D916) and plays the exit on that snapshot.

- A ghost is paint-only. It is not hit-testable, not focusable and absent from
  the accessibility tree (P6).
- A ghost is freed when its exit settles, or at once when its parent leaves.
- Capacity: `Limits.ghosts`. On overflow the oldest ghost ends immediately.
- `AnimatedSwitcher`, the removes in keyed lists, and closing overlays all use
  ghosts. With ghosts, the caller never has to keep "closing" state for a menu
  or dialog.

---

## 9. Shared elements and routes (P6-08, `e.ui.navigation`)

### 9.1 Route transitions

`navigation_stack_of`, `NavigationSplit`, `Wizard` and `PageView` take a
`RouteTransition`:

```neper
type RouteTransition = enum u8 { Platform, None, FadeThrough, SharedAxisX, SharedAxisY, SharedAxisZ,
                                 FadeUpwards, Zoom, Cupertino, ContainerTransform }
```

| Transition | Push | Pop | Default for |
|---|---|---|---|
| `Platform` | resolves by `style.Profile` | | everything, unless told otherwise |
| `SharedAxisX` | the new page slides in 30 px from the end and fades; the old page slides 30 px toward the start and fades out | mirrored | `Neper`, `DesktopDense` (NavigationStack spec: decelerate `duration-medium-2`, pop accelerate `duration-medium-1`) |
| `Zoom` | the new page scales 0.85 → 1 and fades; the old page scales 1 → 1.05 and fades | reversed | `MaterialLike`, `Touch` |
| `Cupertino` | the new page slides in from the end, full width, with an edge shadow; the old page shifts 30% with parallax and dims | follows the edge-swipe gesture | `CupertinoLike` |
| `FadeThrough` | out 90 ms, then in 210 ms with scale from 92% | same | peer destinations (DestinationBar, Tabs) |
| `ContainerTransform` | §7.3, from the pushing element's key | reverse, to the same key if it is still built, else `FadeThrough` | card → detail |

**Behaviour**

- During a route transition, pointer input to **both** routes is absorbed,
  and keyboard focus is already in the incoming route (on pop, focus returns
  to the element that pushed).
- Pushing again mid-transition retargets from the current value. The route
  that is no longer involved becomes a ghost.
- Accessibility sees the final stack at once, and the route change is
  announced by the existing polite region.

### 9.2 Predictive back

A back gesture drives the pop transition's controller *by progress* instead of
by time. The gesture is an edge swipe on touch, a horizontal two-finger swipe
on a touchpad where the host reports one, and `Alt+Left`/`Backspace` (instant)
on the keyboard.

- Progress follows the gesture 1:1 (Cupertino) or through the Material
  predictive-back shrink (scale down to 90%, with a gap from the edge).
- On release, the route commits when progress is at least 0.5 *or* the
  velocity is above 800 px/s toward the edge. It then completes with
  `ease-emphasized-decelerate` over the remaining fraction of
  `duration-medium-2`. Otherwise it cancels back with a spring.
- A cancel leaves the stack and focus untouched. The existing `back_scope`
  still receives exactly one `Submit` on commit.

### 9.3 Hero (`HeroFlight`)

```neper
fn hero(a: *mem.Arena, tag: widget.Key, child: widget.Node) -> (widget.Node, err)
type HeroFlightKind = enum u8 { Rect, MaterialArc }
```

- When a route transition starts, the runtime pairs `hero` tags between the
  outgoing and incoming routes. A tag that appears twice in one route is an
  error, reported once as `E-UI-HERO-DUPLICATE`, and that tag does not fly.
- For each pair, the **destination** subtree is built into the overlay layer
  and flies from the source rect to the destination rect: `RectTween`, or the
  Material arc path when `MaterialArc`. Radius and elevation lerp along the
  way. Both originals are hidden (painted at 0 opacity, kept in layout) for
  the whole flight.
- When the source and destination differ in shape or content, the source
  snapshot cross-fades out during the first 30% of the flight.
- A pop runs the flight in reverse. A predictive back scrubs it. An
  interrupted flight retargets from its current rect.
- Reduced motion: no flight. Both routes use the reduced route fallback
  (`Fade`).

---

## 10. Host integration and policy

### 10.1 Sources of the reduced-motion setting

| Host | Source | Change notification |
|---|---|---|
| Windows | `SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION)` (the "Animation effects" setting) | `WM_SETTINGCHANGE` with `SPI_SETCLIENTAREAANIMATION` |
| Linux (GNOME and GTK) | `org.gnome.desktop.interface enable-animations` through the settings portal `org.freedesktop.portal.Settings` over D-Bus; the XSETTINGS `Gtk/EnableAnimations` as a fallback | the portal's `SettingChanged` signal, or the XSETTINGS property change |
| Linux (KDE) | `kdeglobals` `[KDE] AnimationDurationFactor` = 0 | the portal |

These arrive through `e.os.shell` and appear as `style.Capabilities.reduced_motion`,
alongside the host capabilities of P0-08. An application can override the
setting in either direction. `style.Motion.reduced` is the effective value.

### 10.2 The reduced-motion policy (`ReducedMotionPolicy`)

The runtime applies the policy. Components only declare their `Reduced` value:

| Motion class | Reduced behaviour |
|---|---|
| Movement, scale, grow or rotate that the app started (enter/exit, routes, hero, list moves) | the component's `Reduced`: default `Fade` over 100 ms (the v2 language), or `Instant` |
| Colour and opacity changes (state layers, cross-fades) | unchanged, because they are not motion |
| Loops (indeterminate progress, skeleton sweep, pulses, carousel autoplay) | `StaticFrame`: the documented static frame, and **no frames are requested** |
| Motion that follows the user (drag, fling coast, scrubbing, predictive back) | unchanged |
| Programmatic scrolls (jump to latest, Home or End, smooth wheel) | instant or discrete |

`repeat(count = 0)` under reduced motion settles immediately at its
documented static value. This is the rule that keeps idle apps idle for
people who ask for less motion.

### 10.3 Frame pacing

- Frames are requested only while something is active (§3). The host paces
  them to the display: `DwmFlush` or waitable swap chains on Windows, and the
  refresh rate from XRandR with a timer at that period on X11. When no rate is
  known, the timer runs at 60 Hz.
- A frame that arrives late never makes an animation skip ahead
  inconsistently. Values are functions of the frame instant, so a late frame
  simply shows a later state.
- When the window is minimised or occluded, every scope freezes (§4.4). Nothing
  is requested until the window is visible again.

### 10.4 Accessibility and safety (WCAG 2.2)

- **2.3.1 Three Flashes:** no framework effect flashes more than 3 times a
  second. `pulse` and `cycle` refuse periods under 334 ms with an error.
- **2.2.2 Pause, Stop, Hide:** auto-playing content that runs longer than
  5 s (carousel autoplay, marquee-like loops) must show a pause control. The
  Carousel spec already provides one, and fixtures check it.
- **2.3.3 Animation from Interactions:** §10.2.
- Semantics never animate (P6), and focus moves at the start of transitions
  (§7.3).

---

## 11. Adopting the framework in existing widgets (`HandRolledMotionMigration`)

Each existing widget moves to the framework and loses its private timing
code. Its `Motion:` line in `docs/ux/components` becomes a `Transition` or
`MotionSpec` constant beside the widget.

| Where | Today | Becomes |
|---|---|---|
| `widget.e` press ripple (`duration-medium-2`, eased by D800) | hand-timed | `AnimatedValue` on the state layer |
| `widget.e` scroll overshoot spring-back | hand-rolled damping | `ScrollSpring` (§5) |
| `widget.e` tooltip touch timing (1500 ms release) | timestamp fields in `State` | `Controller` + `Transition` FadeScale |
| `collection.e` reorder lift, drop line, settle (D1192–D1194) | offsets per frame | FLIP (§8.2) + `AnimatedValue` |
| `collection.e` PageView and Carousel turn and snap | release thresholds | `FlingGesture` + spring |
| `collection.e` PullToRefresh damped pull | custom curve | kept as the resistance function; release uses a spring |
| `control.e` / `navigation.e` loaders (`cycle`, `triangle`) | D800 | unchanged API, now under `StaticFrame` reduced motion |
| Tree twisty rotation (D1192, a reduced-motion glyph swap) | instant | `Rotate` over `duration-short-3` |
| overlays (Menu, Dialog, Sheet, Popover, …) | appear instantly | their `Transition` and ghost exits |

The migration is the last P6 item. It must delete the duplicated code, and
each touched widget's existing fixtures must still pass unchanged at the
settled state.

---

## 12. Testing plan

The same rules apply as for every e.ui item: each component is a fixture on
**both hosts**, and full suites run on the D845 cadence. The motion-specific
layers are below.

### 12.1 Value tests (pure, no UI), for P6-01, P6-02 and P6-04

| Subject | Reference | Checks |
|---|---|---|
| every `CurveName` | `scripts/gen_motion_refs.py`: Flutter's `curves.dart` formulas and control points, sampled at 65 points (`t = k/64`), written into the fixture as hex floats | \|Δ\| ≤ 1e-5; exact 0 and 1 at the ends; monotonic for non-overshooting curves; peak overshoot of the back and elastic curves within 1e-4 of the reference |
| `cubic` solver | the same script with random control points (fixed seed, 256 sets, including `x1 = x2`, `y` outside [0,1] and near-vertical tangents) | \|Δy\| ≤ 1e-5; ≤ 8 Newton steps or a bisection fallback taken |
| `interval`, `flipped`, `reversed`, `steps`, `Threshold` | the algebraic identities | `flipped(flipped(c)) == c`; interval edges exact; step counts |
| design tokens | `docs/ux/tokens.json` | the generated `Standard`/`Emphasized*` constants equal the token strings (the generator is the check) |
| every provided `T.lerp` | the endpoints and midpoints by hand; colours by the reference script in linear light | bit-exact endpoints; extrapolation for t = −0.2 and 1.3; shortest-arc rotation (350° → 10° passes through 0°) |
| `Sequence` | weights 1:2:1 | segment boundaries at 0.25 and 0.75 exact |
| `Spring` (three regimes) | closed forms in mpmath, plus an RK4 integration at 1e-6 steps as an independent check | \|Δx\| ≤ 1e-4 over 0–2 s; `done` time within one 1 ms step of the reference; energy non-increasing when damping > 0 |
| `Friction`, `Gravity`, `Clamped`, `BoundedFriction` | formulas | final position, the `done` instant, and bounds never crossed |
| `VelocityTracker` | synthetic samples at known velocities, with jitter and a 50 ms pause | estimate within 1% of the true velocity; zero after the pause; confidence below 0.5 for noise |

These run as one `ui_motion_values` fixture that prints per-check exit codes
(the 58-check lesson from `e.fmt.ini`). Values are compared **bit-for-bit
between Windows and Linux**, not just against a tolerance, because the same
f32 operations must give the same bits (P8).

### 12.2 Controller state machine (P6-03)

- A table-driven fixture: every `(status, call)` pair → the expected status,
  value and velocity at fixed instants.
- **Retarget continuity:** retarget at 10%, 50% and 90% of the flight; the
  value difference between the frames on either side of the retarget is
  ≤ the largest single-frame step of the original animation (C0). Physics
  drives also need a velocity difference ≤ 1e-3 (C1).
- `repeat` with `count` 1, 3 and 0, and mirror on and off. Completion edges
  are reported exactly once by `status_changed`.
- **Scopes:** disable a scope at 40%, advance 10 s, re-enable, and the value
  continues from 40%. A disabled scope requests no frames.
- **Dilation:** factor 5 makes a 200 ms animation take 1 s of frame time.

### 12.3 Widget fixtures with a fake clock (`FakeClockPump`, `FrameSampling`)

New `e.ui.testing` helpers:

```neper
fn pump_for(h: *Harness, root_of: BuildFn, ctx: *void, span: time.Duration, step: time.Duration) -> err
fn pump_until_settled(h: *Harness, root_of: BuildFn, ctx: *void, cap: time.Duration) -> (time.Duration, err)  // err when cap is hit
fn sample(h: *Harness, key: widget.Key) -> Sample                  // painted opacity, transform, rect of an element
fn filmstrip(h: *Harness, a: *mem.Arena, root_of: BuildFn, ctx: *void, at: []const time.Duration) -> (image.Image, err)
fn frames_requested(h: *const Harness) -> bool
fn motion_stats(h: *const Harness) -> MotionStats                  // rebuilds, layouts, patched layers, ghosts, snaps
```

Every component that has a `Transition` gets a fixture that:

1. **Samples** 0, 25, 50, 75 and 100% of enter and of exit, and asserts
   `sample` against the values the `MotionSpec` implies (for example, the
   Tooltip's scale at 50% = `lerp(0.8, 1, EmphasizedDecelerate(0.5))`).
2. **Settles:** `pump_until_settled` returns within `duration + 1 frame`, and
   afterwards `frames_requested` is false for 3 more frames (**idle check**).
3. **Interrupts:** it reverses at 50%, and no frame moves more than the
   largest frame step of the uninterrupted run.
4. **Checks semantics:** the accessibility tree at 0% and 50% equals the tree
   at 100% (P6), and a ghost is absent.
5. **Checks input:** a tap during an enter is refused (inert), a scrim tap is
   accepted, and focus is where §7.3 says at the first frame.
6. **Runs twice**, with reduced motion off and on (§12.4).

### 12.4 The reduced-motion matrix

Generated from the `Transition` constants: for each component, reduced motion
must (a) settle within its `Reduced` behaviour (≤ 1 frame for `Instant`,
100 ms for `Fade`), (b) for loops, request **zero** frames after the first
build, and (c) leave motion that follows the user unchanged (a drag fixture
gives identical samples with reduced motion on and off).

### 12.5 Composition and stress

- `AnimatedSwitcher` with 10 key changes within 100 ms: the ghost count stays
  ≤ `Limits.ghosts`, the final child is correct and nothing leaks after
  settling (the slot and ghost counts return to zero).
- Keyed lists: every combination of insert, remove and move on 8 rows (a
  generated table), a remove while an insert runs, a key that is removed and
  re-added within one animation (it reverses the ghost instead of making a
  new row), and a move outside the built window (it snaps).
- Routes: push, push, pop inside one transition; a hero with no destination
  (no flight, no error); duplicate hero tags (one diagnostic, no flight);
  predictive back cancelled at 0.49 and committed at 0.51, and committed by
  velocity at 0.2.
- **Capacity:** exhaust `Limits.animations` and `Limits.ghosts`; the extra
  animations snap and `motion_stats().snaps` counts them, with no error.

### 12.6 Performance

- `CompositorOnlyUpdate`: `motion_stats` asserts zero rebuilds and layouts
  across a 300 ms fade and a slide of a full page (`ui_motion_compositor`).
- Instruction counts under cachegrind (the C033 method, counts not time): a
  compositor-only frame costs ≤ 15% of a rebuild frame for the same page, and
  the settled-idle loop costs 0 frames. The baseline is recorded in the D row
  of the item that lands it.
- `pump_until_settled` has a hard cap in every fixture (the memory rule: cap
  every wait loop).

### 12.7 Visual review

`filmstrip` tiles the sampled frames into one PNG per component
(`build/ux/motion-<component>-segoe.png`), for the same human review the
static widgets get. Each item's D row names its strip.

### 12.8 Spec conformance

`scripts/check_motion_spec.py` parses every `Motion:` line in
`docs/ux/components/*/README.md` for its duration and easing tokens, and
checks that the component's `Transition` constant uses the same tokens. A
language edit that the code doesn't follow, or the reverse, fails the check.
It runs in `render_progress.py` next to `check_widget_plan.py`.

### 12.9 Example

`examples/ui` gains a **Motion** page: the curve catalog plotted, a spring
editor (mass, stiffness and damping, with a live trace), every `Transition`
on a button, list changes, a route demo with hero and predictive back, and
toggles for reduced motion and dilation. This page is the manual check on
both hosts.

---

## 13. Diagnostics

| Condition | Result |
|---|---|
| `cubic` with x1 or x2 outside [0,1]; `interval` with begin > end; `Sequence` with zero weight | `Invalid` from the constructor |
| `spring` with mass ≤ 0, stiffness ≤ 0 or damping < 0 | `Invalid` |
| `pulse` or `cycle` period < 334 ms | `Invalid` (WCAG 2.3.1) |
| duplicate hero tag in one route | `E-UI-HERO-DUPLICATE` once per tag; that tag does not fly |
| `Limits.animations` / `Limits.ghosts` exhausted | the animation snaps; counted, never an error |
| `pump_until_settled` cap reached | `err` naming the keys still active (catches an accidental infinite loop) |

---

## 14. Modules touched

| Module | Change |
|---|---|
| `e.ui.animation` | curves, tweens, controller v2, scopes, physics, `MotionSpec`, `Effect`/`Transition`, implicit primitives and transitions (§4–§7) |
| `e.ui.widget` | the `Faded` kind; runtime slots for implicit state, ghosts and scope clocks; the compositor-only reconcile path; FLIP for keyed children; `Limits.animations`, `Limits.ghosts`, `Limits.scopes` |
| `e.ui.style` | `EaseToken`/`DurationToken` enums and the generated curve constants; `Capabilities.reduced_motion`; scroll physics per profile |
| `e.ui.collection` | the `animate` option on lists and grids; fling, spring and FLIP in PageView, Carousel, ReorderableList and SwipeActions |
| `e.ui.navigation` | `RouteTransition`, predictive back, `hero` |
| `e.ui.overlay` | a `Transition` for each overlay; exits by ghost |
| `e.ui.control` | a `Transition` or `MotionSpec` for each control per its `Motion:` line; loops under `StaticFrame` |
| `e.ui.testing` | the fake-clock pump, sampling, filmstrip, stats |
| `e.os.shell` | reading and watching the host's reduced-motion setting (§10.1) |
| `e.gfx.scene` | none: `OpacityLayer` and transforms already exist |

---

## 15. Flutter parity

| Flutter | e.ui | Notes |
|---|---|---|
| `Curves.*` (41 constants), `Cubic`, `ThreePointCubic` | `CurveName`, `cubic` | the same set and the same numbers |
| `Interval`, `Threshold`, `FlippedCurve`, `ReverseCurve`, `SawTooth` | `interval`, `Threshold`, `flipped`, `reversed`, `repeat` on a linear curve | |
| `CurvedAnimation`, `ReverseAnimation`, `ProxyAnimation`, `TrainHoppingAnimation`, `CompoundAnimation` | `transform(curve, value(c))`, `1 − v`, arithmetic on values | the pull model makes these plain expressions |
| `AlwaysStoppedAnimation` | a constant | |
| `Tween`, `ColorTween`, `RectTween`, `SizeTween`, `IntTween`, `StepTween`, `ConstantTween`, `MaterialRectArcTween` | `Tween[T]` + provided lerps, `HeroFlightKind.MaterialArc` | |
| `TweenSequence` | `Sequence[T]` | |
| `AnimationController` (`forward`, `reverse`, `animateTo`, `animateWith`, `repeat`, `fling`, `stop`) | `Controller` v2 | `fling` = `animate_with(spring_sim …)` |
| `AnimationStatus`, status listeners | `Status`, `status_changed` | edges, not callbacks |
| `Ticker`, `TickerProvider`, `TickerMode` | the frame clock, `ticker_scope` | no objects to dispose |
| `timeDilation` | `set_time_dilation` | |
| `SpringSimulation`, `ScrollSpringSimulation`, `FrictionSimulation`, `BoundedFrictionSimulation`, `GravitySimulation`, `ClampedSimulation`, `SpringDescription.withDampingRatio` | `Simulation`, `spring_ratio` | |
| `VelocityTracker` | `VelocityTracker` | |
| `BouncingScrollPhysics`, `ClampingScrollPhysics`, `PageScrollPhysics`, stretch overscroll | per-profile scroll physics (§7.4) | |
| `ImplicitlyAnimatedWidget`, `TweenAnimationBuilder` | `animated[T]`, `appear` | |
| `AnimatedOpacity`, `AnimatedAlign`, `AnimatedPadding`, `AnimatedSize`, `AnimatedContainer`, `AnimatedDefaultTextStyle`, `AnimatedPhysicalModel`, `AnimatedScale`, `AnimatedRotation`, `AnimatedSlide`, `AnimatedPositioned`, `AnimatedFractionallySizedBox`, `AnimatedTheme` | §6 components; `animated[T]` over `VisualTransform`, `Positioned` and theme tokens for the last five | |
| `AnimatedSwitcher`, `AnimatedCrossFade`, `PageTransitionSwitcher` | §6 + ghosts | |
| `FadeTransition`, `ScaleTransition`, `RotationTransition`, `SlideTransition`, `SizeTransition`, `AlignTransition`, `DecoratedBoxTransition`, `DefaultTextStyleTransition`, `PositionedTransition`, `RelativePositionedTransition`, `MatrixTransition` | §7.2 | |
| `AnimatedList`, `SliverAnimatedList`, `AnimatedGrid` | keyed list changes (§8.2) | no `removeItem` builder: ghosts replace it |
| staggered animations (the Interval idiom) | `stagger`, `sequence_of` | |
| `Hero`, `HeroMode`, `HeroFlightShuttleBuilder` | `hero`, reduced motion; the shuttle is always the destination | **Decided (D1208):** no custom shuttle builders in v1 |
| `PageRouteBuilder`, `PageTransitionsTheme` (FadeUpwards, OpenUpwards, Zoom, Cupertino, PredictiveBack) | `RouteTransition` (§9.1), predictive back (§9.2) | `OpenUpwards` is omitted (superseded by Zoom) |
| `animations` package: `OpenContainer`, `SharedAxisTransition`, `FadeThroughTransition`, `FadeScaleTransition` | `ContainerTransform`, `SharedAxis*`, `FadeThrough`, FadeScale | |
| `AnimationStyle` (per-call overrides of popups and routes) | the `Transition` argument on overlays and routes | |
| `MediaQuery.disableAnimations` | `Capabilities.reduced_motion` + the policy | enforced by the framework, not by each widget |
| `AnimatedIcon`, `AnimatedModalBarrier` | out of scope; the scrim is part of the `Effect` | |
| `WidgetTester.pump(Duration)`, `pumpAndSettle` | `pump_for`, `pump_until_settled` | with a mandatory cap |

---

## 16. Locked decisions

| # | Decision | Row |
|---|---|---|
| 1 | Implicit state is runtime-keyed (P3), with snap on overflow | D1201 |
| 2 | D800's quadratic curves are renamed and aliased (§4.1) | D1202 |
| 3 | Colour interpolates in premultiplied linear light (§4.2) | D1203 |
| 4 | Physics stays inside `e.ui.animation` (§5) | D1204 |
| 5 | Implicit animations opt into an entrance with `appear` (§6) | D1205 |
| 6 | Opacity is a node kind, `Faded` (§7.1) | D1206 |
| 7 | The stagger cap is 8 (§8.1) | D1207 |
| 8 | There are no custom hero shuttles in v1 (§15) | D1208 |
| 9 | Pointer input is absorbed by both routes during a route transition (§9.1) | D1209 |
