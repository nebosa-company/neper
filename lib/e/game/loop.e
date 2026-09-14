// The fixed timestep, and the easing curves that go with it (D249).
//
// The clock is given the elapsed time rather than reading one. That is the whole point:
// a simulation driven by a scripted clock replays exactly, which is what makes a
// deterministic engine testable without a machine to render on, and what rollback needs.
//
// `advance` returns how many whole steps to run; `alpha` is the leftover fraction, for
// interpolating a render between two simulated states. Easing lives here rather than in
// a module of its own -- these are a handful of Q16 curves, and `e.ui.animation` is layer
// 6 and bound to the widget tree, so the game core cannot reach it.

use e.mem
use e.math.fixed

type Clock = struct {
    step: fixed.Fx,
    accumulator: fixed.Fx,
    ticks: u64,
}

type Timer = struct {
    remaining: fixed.Fx,
    period: fixed.Fx,
    repeating: bool,
}

error Invalid

fn init(c: *Clock, step: fixed.Fx) -> err {
    if step <= 0i32 { ret Invalid }
    c.step = step
    c.accumulator = 0i32
    c.ticks = 0u64
    ret ok
}

// Accumulate, then hand back the whole steps owed, at most `max_steps` of them. When the
// cap is hit the backlog is dropped rather than carried: a machine that cannot keep up
// would otherwise fall further behind every frame, each frame owing more than the last.
fn advance(c: *Clock, elapsed: fixed.Fx, max_steps: usize) -> usize {
    if elapsed > 0i32 { c.accumulator = c.accumulator + elapsed }
    var steps = 0usize
    while c.accumulator >= c.step && steps < max_steps {
        c.accumulator = c.accumulator - c.step
        c.ticks = c.ticks + 1u64
        steps += 1usize
    }
    if c.accumulator >= c.step { c.accumulator = c.step - 1i32 }
    ret steps
}

// The leftover as a fraction of one step, in [0, ONE).
fn alpha(c: Clock) -> fixed.Fx {
    if c.step <= 0i32 { ret 0i32 }
    let (share, share_error) = fixed.div(c.accumulator, c.step)
    if share_error != ok { ret 0i32 }
    ret share
}

fn timer(period: fixed.Fx, repeating: bool) -> Timer {
    ret Timer { remaining: period, period: period, repeating: repeating }
}

// True on exactly the step the timer comes due. A repeating timer carries the overshoot
// into the next period, so a period that is not a whole number of steps does not drift.
fn tick(t: *Timer, step: fixed.Fx) -> bool {
    if t.period <= 0i32 { ret false }
    if t.remaining <= 0i32 { ret false }
    t.remaining = t.remaining - step
    if t.remaining > 0i32 { ret false }
    if t.repeating { t.remaining = t.remaining + t.period }
    ret true
}

fn ready(t: Timer) -> bool {
    ret t.remaining <= 0i32
}

fn reset(t: *Timer) -> err {
    t.remaining = t.period
    ret ok
}

// The curves below all take and return Q16 in [0, ONE] and are exact at both ends.
fn ease_in(t: fixed.Fx) -> fixed.Fx {
    ret fixed.mul(t, t)
}

fn ease_out(t: fixed.Fx) -> fixed.Fx {
    let inverse = fixed.ONE - t
    ret fixed.ONE - fixed.mul(inverse, inverse)
}

fn ease_in_out(t: fixed.Fx) -> fixed.Fx {
    if t < fixed.HALF { ret fixed.mul(fixed.mul(t, t), 131072i32) }
    let inverse = fixed.ONE - t
    ret fixed.ONE - fixed.mul(fixed.mul(inverse, inverse), 131072i32)
}

// Overshoots once and settles: t*t*((s+1)t - s) with the usual s of 1.70158.
fn ease_back(t: fixed.Fx) -> fixed.Fx {
    let overshoot = 111514i32
    let scaled = fixed.mul(overshoot + fixed.ONE, t) - overshoot
    ret fixed.mul(fixed.mul(t, t), scaled)
}

// A cubic decay against two and a half turns of cosine. The usual curve damps with a
// power of two, which would want an exponential; a cube is table-free, lands exactly on
// 0 and ONE, and rings the same way.
fn ease_elastic(t: fixed.Fx) -> fixed.Fx {
    let inverse = fixed.ONE - t
    let damping = fixed.mul(fixed.mul(inverse, inverse), inverse)
    let angle = fixed.mul(t, 163840i32)
    ret fixed.ONE - fixed.mul(damping, fixed.cos(angle))
}
