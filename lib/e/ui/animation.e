// `e.ui.animation` (D800): a controller is a start instant, a duration and a curve,
// and its value at an instant is a number in `0..1` -- the eased fraction of the
// way through, held at the ends, reversed on the way back when `reverse` is set,
// wrapped when `repeating`. Nothing runs by itself: a widget reads `value` when it
// builds and asks for the next frame through `request` while it is not finished.
// The runtime clock gives every control one shared instant per frame; `cycle` and
// `pulse` both keep the application presenting until their caller stops asking.

use e.time
use e.ui.widget

// (D1376) The emphasized pair: `ease-emphasized-decelerate` is the cubic
// Bezier (0.05, 0.7, 0.1, 1), `ease-emphasized-accelerate` (0.3, 0, 0.8, 0.15).
type Curve = enum u8 { Linear, EaseIn, EaseOut, EaseInOut, EmphasizedDecelerate, EmphasizedAccelerate }
type Controller = struct { start: time.Instant, duration: time.Duration, curve: Curve, repeating: bool, reverse: bool }

fn controller(now: time.Instant, duration: time.Duration, curve: Curve) -> Controller {
    var d = duration
    if d.nanos < 0i64 { d = time.Duration { nanos: 0i64 } }
    ret Controller { start: now, duration: d, curve: curve, repeating: false, reverse: false }
}

// The raw fraction, before the curve: elapsed over the duration, wrapped for a
// repeating controller, mirrored for a reversing one.
fn fraction(c: *const Controller, now: time.Instant) -> f32 {
    let elapsed = time.instant_diff(now, c.start).nanos
    if elapsed <= 0i64 { ret 0.0 }
    if c.duration.nanos <= 0i64 { ret 1.0 }
    if !c.repeating && !c.reverse {
        if elapsed >= c.duration.nanos { ret 1.0 }
        ret f32(elapsed) / f32(c.duration.nanos)
    }
    var period = c.duration.nanos
    if c.reverse { period = period * 2i64 }
    var t = elapsed
    if c.repeating {
        t = elapsed % period
    } else {
        if t >= period { ret 0.0 }
    }
    if c.reverse && t >= c.duration.nanos { t = period - t }
    ret f32(t) / f32(c.duration.nanos)
}

fn ease(curve: Curve, t: f32) -> f32 {
    if curve == .EmphasizedDecelerate { ret bezier(0.05, 0.7, 0.1, 1.0, t) }
    if curve == .EmphasizedAccelerate { ret bezier(0.3, 0.0, 0.8, 0.15, t) }
    if curve == .EaseIn { ret t * t }
    if curve == .EaseOut { ret 1.0 - (1.0 - t) * (1.0 - t) }
    if curve == .EaseInOut {
        if t < 0.5 { ret 2.0 * t * t }
        let u = 1.0 - t
        ret 1.0 - 2.0 * u * u
    }
    ret t
}

// (D1376) A CSS cubic Bezier from (0, 0) to (1, 1) through (x1, y1) and
// (x2, y2): the y where the curve's x is `t`, found by halving the parameter.
fn bezier(x1: f32, y1: f32, x2: f32, y2: f32, t: f32) -> f32 {
    if !(t > 0.0) { ret 0.0 }
    if !(t < 1.0) { ret 1.0 }
    var lo: f32 = 0.0
    var hi: f32 = 1.0
    var s: f32 = t
    var step = 0usize
    while step < 24usize {
        s = (lo + hi) * 0.5
        let u = 1.0 - s
        let x = 3.0 * u * u * s * x1 + 3.0 * u * s * s * x2 + s * s * s
        if x < t { lo = s } else { hi = s }
        step += 1usize
    }
    let u = 1.0 - s
    ret 3.0 * u * u * s * y1 + 3.0 * u * s * s * y2 + s * s * s
}

fn value(c: *const Controller, now: time.Instant) -> f32 {
    ret ease(c.curve, fraction(c, now))
}

// A repeating controller never finishes; a reversing one finishes after its round trip.
fn finished(c: *const Controller, now: time.Instant) -> bool {
    if c.repeating { ret false }
    let elapsed = time.instant_diff(now, c.start).nanos
    var period = c.duration.nanos
    if c.reverse { period = period * 2i64 }
    ret elapsed >= period
}

fn restart(c: *Controller, now: time.Instant) {
    c.start = now
}

// The instant shared by every animation in the current frame.
fn frame_time(runtime: *widget.Runtime) -> time.Instant {
    ret widget.frame_time(runtime)
}

// A repeating linear turn in `0..1` on the shared clock.
fn cycle(runtime: *widget.Runtime, period: time.Duration) -> f32 {
    if period.nanos <= 0i64 { ret 1.0 }
    widget.request_animation_frame(runtime)
    var at = frame_time(runtime).nanos % period.nanos
    if at < 0i64 { at += period.nanos }
    ret f32(at) / f32(period.nanos)
}

// A 0 -> 1 -> 0 wave over one turn.
fn triangle(turn: f32) -> f32 {
    var t = turn - f32(i64(turn))
    if t < 0.0 { t += 1.0 }
    if t < 0.5 { ret t * 2.0 }
    ret (1.0 - t) * 2.0
}

fn pulse(runtime: *widget.Runtime, period: time.Duration, low: f32, high: f32) -> f32 {
    ret low + (high - low) * triangle(cycle(runtime, period))
}

// The element wants another frame and must not reuse its previous scene.
fn request(runtime: *widget.Runtime, element: widget.ElementId) {
    widget.invalidate(runtime, element)
    widget.request_animation_frame(runtime)
}
