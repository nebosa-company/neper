# e.ui motion framework — plan (next release)

**Status: next release.** Nothing here is scheduled for the current release.
Widget-plan phase `P6` carries the inventory and is blocked by the external
blocker `next-release`, so `check_widget_plan.py --next` never selects it and
its components do not count toward the current widget KPI. To open it, add
`next-release` to `resolved_blockers` in `docs/widget-plan.json` and remove the
phase's `"release": "next"`.

## Where we are

`e.ui.animation` (D800) is about 100 lines: a `Controller` (start, duration,
curve, `repeating`, `reverse`), four quadratic curves, `cycle`/`triangle`/`pulse`,
and a frame clock that all widgets share, requested with `request_animation_frame`.
Its only callers are the loaders and progress indicators. Every other motion is written by hand inside
its widget: the press ripple, the scroll overshoot spring, tooltip timing and
reorder feedback. The theme already carries motion tokens (`fast`/`normal`/`slow`,
`reduced`, `stagger`). `e.gfx.scene` already has `OpacityLayer`, and the
widget layer has `VisualTransform` (D1192), a paint-only scale, rotation and
offset that leaves layout, hit testing and semantics alone. Those are the
pieces the transitions below need.

## Target: parity with Flutter's animation stack

| Flutter | e.ui (P6 item) |
|---|---|
| `Curves.*`, `Cubic`, `Interval`, `Threshold`, `FlippedCurve` | P6-01 curves |
| `Tween<T>`, `ColorTween`, `RectTween`, `TweenSequence` | P6-02 tweens |
| `AnimationController`, `AnimationStatus`, `TickerMode`, `timeDilation` | P6-03 controller v2 |
| `SpringSimulation`, `FrictionSimulation`, `GravitySimulation`, `fling` | P6-04 physics |
| `AnimatedContainer`, `AnimatedOpacity`, `AnimatedSwitcher`, `TweenAnimationBuilder` | P6-05 implicit animations |
| `FadeTransition`, `SlideTransition`, `ScaleTransition`, `SizeTransition` | P6-06 explicit transitions |
| staggered `Interval`s, `AnimatedList`, `AnimatedGrid` | P6-07 choreography |
| `Hero`, `animations` package (shared axis, fade through, container transform), predictive back | P6-08 shared element and routes |
| `WidgetTester.pump(Duration)`, slow animations, reduced motion | P6-09 testing and policy |

Out of scope: vector animation players (Lottie, Rive). They are a separate
asset format and belong beside `e.ui.asset` if they are ever wanted.

## Design rules

1. **Pull, not push.** A widget reads an animated value when it builds, at the
   frame instant the runtime provides. There are no listener callbacks. A status
   change is an edge that the caller detects with `status_changed(c, before, now)`. This
   keeps D800's model and needs no closures.
2. **A controller is plain data in the model.** It is a struct that the model owns,
   with no registration and no ticker objects. `TickerScope` is a runtime flag
   per subtree (hidden, off-screen or muted): while it is set, frames are not
   requested and the scope's clock is frozen.
3. **Retarget from where you are.** Every implicit animation and every
   simulation starts from the current value *and velocity*, so an interrupted
   animation never jumps.
4. **Compositor-only when possible.** Opacity and transform transitions patch
   the retained scene's `OpacityLayer` or transform without layout or rebuild,
   reusing D914/D916 damage repaint. Size and layout transitions re-run layout
   for the animated subtree only.
5. **Reduced motion is a policy, not a flag each widget checks.** With
   `motion.reduced` set, controllers finish immediately, and transitions that
   move, scale or share an element degrade to a `fast` cross-fade.
6. **Durations and curves come from tokens.** Components default to theme
   motion tokens; literal durations are for callers only.

## Inventory

- **P6-01 Curves** — `CubicBezierCurve` (solved by Newton iteration with a
  bisection fallback), `CurveCatalog` (Flutter's named set, including the
  sine, quad, cubic, quart, quint, expo, circ, back, elastic and bounce
  families plus the Material standard, emphasized, decelerate and accelerate
  curves), `IntervalCurve`, `StepCurve`, and `CurveTransforms` (flip, reverse,
  threshold). Each curve is a tagged value, so no function pointers are needed.
- **P6-02 Tweens** — a generic `TweenValue` `Tween[T]` over `T.lerp`, the way
  e.test uses `T.eq`. Also `ColorTween` (mixed in linear light, not sRGB),
  `GeometryTweens` for point, size, rect, insets and radii, `TransformTween`
  (decompose, interpolate, recompose, so rotations do not shear) and
  `TweenSequence` (weighted segments).
- **P6-03 Controller v2** — `AnimationStatus` (dismissed, forward, reverse,
  completed), `ControllerDriving` (`forward`, `reverse`, `animate_to`, `stop`,
  and `repeat` with bounds, each able to take a simulation), `AnimationVelocity`,
  `TickerScope` and `TimeDilation` (debug slow motion). D800's `Controller`
  stays source-compatible.
- **P6-04 Physics** — `SpringSimulation` (the critically damped, underdamped and
  overdamped cases solved in closed form, with a tolerance-based `done`),
  `FrictionSimulation`, `GravitySimulation`, and `FlingGesture` (from a pointer
  velocity tracker to a simulation). Then `ScrollPhysicsOnSprings`: move
  `widget.e`'s hand-written overshoot onto `SpringSimulation`.
- **P6-05 Implicit animations** — `AnimatedValue` (a model slot that retargets
  when its target changes; everything else in this item is built on it),
  `AnimatedOpacity`, `AnimatedLayout` (align, padding, size), `AnimatedDecoration`
  (fill, border, radius, elevation), `AnimatedTextStyle`, `AnimatedSwitcher`
  and `AnimatedCrossFade`.
- **P6-06 Explicit transitions** — `FadeTransition`, `ScaleTransition`,
  `RotationTransition`, `SlideTransition`, `SizeTransition`, and
  `CompositorOnlyUpdate`, which is the rule-4 fast path with its damage-rect
  fixture. Scale, rotation and slide drive `VisualTransform` (D1192), and fade
  drives `OpacityLayer`. Only `SizeTransition` touches layout.
- **P6-07 Choreography** — `StaggeredGroup` (intervals derived from the
  `stagger` token), `SequenceGroup`, `AnimatedListChanges` (insert and remove in
  `e.ui.collection`, keyed so a removed row animates out after it has left the
  model) and `AnimatedGridChanges`.
- **P6-08 Shared element and routes** — `HeroFlight` (a keyed element flies
  between two routes on an overlay layer, interpolating rect, radius and
  opacity), `SharedAxisTransition`, `FadeThroughTransition`,
  `ContainerTransform` and `PredictiveBack` (a route transition driven by the
  back gesture's progress, which cancels back to its start).
- **P6-09 Testing and policy** — `FakeClockPump` (`testing.pump_for(h, duration)`
  and `pump_until_settled`), `FrameSampling` (assert a subtree's value or paint
  at an instant), `ReducedMotionPolicy` (rule 5, with one fixture per P6 item),
  `AnimationFrameStats` (frames requested, compositor-only frames, rebuilds per
  animation) and `HandRolledMotionMigration` (move the press ripple, tooltip
  timing, reorder feedback and loaders onto the framework, then delete the
  duplicate code).

## Order and acceptance

P6-01 → 02 → 03 → 04 is the core and has no UI. The remaining items are built on it,
roughly in this order: 09 (`FakeClockPump` first, because every later fixture
needs it), 05, 06, 07, 08, and 09's migration last. Each component is delivered
the way P0–P5 were: a fixture on both hosts. Every value-level check (curves,
tweens, springs) is compared against a reference sampled from Flutter's own
formulas at fixed instants. Every visual check is a frame sampled with
`FrameSampling` at fixed instants of the fake clock.
