// `e.ui.animation` (D800): a controller is a start instant, a duration and a curve,
// and its value at an instant is a number in `0..1` -- the eased fraction of the
// way through, held at the ends, reversed on the way back when `reverse` is set,
// wrapped when `repeating`. Nothing runs by itself: a widget reads `value` when it
// builds and asks for the next frame through `request` while it is not finished,
// which is `widget.invalidate` under another name.

use e.time
use e.ui.widget

type Curve = enum u8 { Linear, EaseIn, EaseOut, EaseInOut }
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
    if curve == .EaseIn { ret t * t }
    if curve == .EaseOut { ret 1.0 - (1.0 - t) * (1.0 - t) }
    if curve == .EaseInOut {
        if t < 0.5 { ret 2.0 * t * t }
        let u = 1.0 - t
        ret 1.0 - 2.0 * u * u
    }
    ret t
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

// The element wants another frame: the same wish `widget.invalidate` records.
fn request(runtime: *widget.Runtime, element: widget.ElementId) {
    widget.invalidate(runtime, element)
}
