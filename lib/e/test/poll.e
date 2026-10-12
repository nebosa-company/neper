// Async test-condition polling in the manner of Awaitility: wait until a condition holds
// (`until`), or check that it keeps holding for a period (`during`), polling at an interval
// with optional initial delay, backoff and ignoring of condition errors.
//
// The condition is `fn(*void) -> (bool, err)`. `until` polls: wait `initial_delay`, then
// evaluate; true ends successfully; otherwise sleep the interval (never past the deadline) and
// evaluate again, until the clock reaches `timeout` after the start, when it makes one last
// evaluation and answers `Timeout`. The interval is multiplied by `backoff_percent / 100`
// after every sleep (100 or 0 is constant) and capped at `max_interval_ns` when that is
// non-zero. An error from the condition ends the wait with that error unless `ignore_errors`,
// in which case the last such error is kept in the outcome and polling continues.
// `during` is the converse: every evaluation must be true up to the deadline (`Failed` on the
// first false, the condition's error on an error), and it succeeds at the deadline.
//
// Time comes from a `Clock` so tests of waiting code are deterministic: `real_clock` is the
// monotonic clock with sleeping, and any `{ctx, now, sleep}` is accepted.

use e.mem
use e.sync
use e.time

type Clock = struct { ctx: *void, now: fn(*void) -> i64, sleep: fn(*void, i64) }
type RealClock = struct { nap: sync.Semaphore }
type Options = struct { timeout_ns: i64, interval_ns: i64, initial_delay_ns: i64, backoff_percent: u32, max_interval_ns: i64, ignore_errors: bool }
type Outcome = struct { attempts: u32, elapsed_ns: i64, last_error: err }
error Timeout
error Failed
error Invalid

fn real_now(ctx: *void) -> i64 {
    let (t, e) = time.monotonic()
    if e != ok { ret 0i64 }
    ret t.nanos
}

fn real_sleep(ctx: *void, nanos: i64) {
    if nanos <= 0i64 { ret }
    var c = mem.cast[*RealClock](ctx)
    let woke = sync.semaphore_wait_for(&c.nap, time.nanos(nanos))
}

fn real_clock(c: *RealClock) -> Clock {
    c.nap = sync.semaphore(0u32)
    ret Clock { ctx: mem.cast[*void](c), now: real_now, sleep: real_sleep }
}

fn next_interval(current: i64, o: Options) -> i64 {
    var next = current
    if o.backoff_percent != 0u32 && o.backoff_percent != 100u32 {
        // saturating multiply: stay below the i64 limit
        let factor = i64(o.backoff_percent)
        if current > 9223372036854775807i64 / factor {
            next = 9223372036854775807i64
        } else {
            next = current * factor / 100i64
        }
    }
    if o.max_interval_ns > 0i64 && next > o.max_interval_ns { next = o.max_interval_ns }
    if next < 1i64 { next = 1i64 }
    ret next
}

fn until(clock: Clock, ctx: *void, cond: fn(*void) -> (bool, err), o: Options) -> (Outcome, err) {
    var out: Outcome = zero
    if o.timeout_ns < 0i64 || o.interval_ns <= 0i64 { ret (out, Invalid) }
    let start = clock.now(clock.ctx)
    let deadline = start + o.timeout_ns
    if o.initial_delay_ns > 0i64 { clock.sleep(clock.ctx, o.initial_delay_ns) }
    var interval = o.interval_ns
    while true {
        out.attempts += 1u32
        let (holds, e) = cond(ctx)
        let now = clock.now(clock.ctx)
        out.elapsed_ns = now - start
        if e != ok {
            out.last_error = e
            if !o.ignore_errors { ret (out, e) }
        } else if holds {
            ret (out, ok)
        }
        if now >= deadline { break }
        var nap = interval
        if nap > deadline - now { nap = deadline - now }
        clock.sleep(clock.ctx, nap)
        interval = next_interval(interval, o)
    }
    ret (out, Timeout)
}

fn during(clock: Clock, ctx: *void, cond: fn(*void) -> (bool, err), o: Options) -> (Outcome, err) {
    var out: Outcome = zero
    if o.timeout_ns < 0i64 || o.interval_ns <= 0i64 { ret (out, Invalid) }
    let start = clock.now(clock.ctx)
    let deadline = start + o.timeout_ns
    if o.initial_delay_ns > 0i64 { clock.sleep(clock.ctx, o.initial_delay_ns) }
    var interval = o.interval_ns
    while true {
        out.attempts += 1u32
        let (holds, e) = cond(ctx)
        let now = clock.now(clock.ctx)
        out.elapsed_ns = now - start
        if e != ok {
            out.last_error = e
            ret (out, e)
        }
        if !holds { ret (out, Failed) }
        if now >= deadline { break }
        var nap = interval
        if nap > deadline - now { nap = deadline - now }
        clock.sleep(clock.ctx, nap)
        interval = next_interval(interval, o)
    }
    ret (out, ok)
}
