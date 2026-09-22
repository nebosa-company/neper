// `e.thread`'s fibers: four fibers of fifty yields interleave in exactly the round-robin
// order the replica predicts and never two at once (the shared counter inside every
// critical region peaks at one), uneven fiber lengths keep that order as fibers drop out,
// `yield_to` drives a 0-2-1 schedule a round robin would never make, a suspended fiber
// stalls `run` with `Invalid` until it is resumed, a body that never yields runs once and
// is never picked again, and exhausted storage is `Full` while an unknown id is `Invalid`.
// Every expected order comes from scratchpad/thread_fiber/ref.py. Each check exits with
// its own code; `join_fiber` leaves no thread parked.

use e.atomic
use e.io
use e.mem
use e.os
use e.thread

type World = struct { sched: *void, order: [256]u32, filled: usize, steps: [4]u32, ran: [4]u32, concurrent: Atomic[u32], peak: u32, fault: u32, mode: u32, hold: u32, hold_at: u32, sink: u64 }

fn reset(w: *World, mode: u32, s0: u32, s1: u32, s2: u32, s3: u32) {
    w.filled = 0usize
    w.peak = 0u32
    w.fault = 0u32
    w.mode = mode
    w.hold = 4u32
    w.hold_at = 0u32
    w.steps[0usize] = s0
    w.steps[1usize] = s1
    w.steps[2usize] = s2
    w.steps[3usize] = s3
    var i = 0usize
    while i < 4usize {
        w.ran[i] = 0u32
        i += 1usize
    }
    atomic.store(&w.concurrent, 0u32, .Release)
}

// The critical region: one fiber is inside it at a time or `peak` says otherwise, and the
// spin widens the window a second runner would have to show up in.
fn record(w: *World, id: u32) {
    let inside = atomic.add(&w.concurrent, 1u32, .AcqRel) + 1u32
    if inside > w.peak { w.peak = inside }
    if w.filled < 256usize {
        w.order[w.filled] = id
        w.filled += 1usize
    }
    var x = u64(id) + 1u64
    var q = 0u32
    while q < 64u32 {
        x = x *% 6364136223846793005u64 +% 1442695040888963407u64
        q += 1u32
    }
    w.sink = w.sink +% x
    let left = atomic.sub(&w.concurrent, 1u32, .AcqRel)
}

fn switch_after(w: *World, s: *thread.Scheduler[World], id: u32, k: u32) -> err {
    if w.mode == 1u32 {
        let t = (id + 2u32) % 3u32
        let (st, state_error) = thread.fiber_state[World](s, t)
        if state_error == ok && t != id && st == .Ready { ret thread.yield_to[World](s, t) }
        ret thread.yield_now[World](s)
    }
    if w.mode == 2u32 && id == w.hold && k == w.hold_at { ret thread.suspend[World](s) }
    if w.mode == 3u32 { ret ok }
    ret thread.yield_now[World](s)
}

fn body(w: *World, id: u32) {
    let s = mem.cast[*thread.Scheduler[World]](w.sched)
    w.ran[usize(id)] += 1u32
    var k = 0u32
    while k < w.steps[usize(id)] {
        record(w, id)
        let switch_error = switch_after(w, s, id, k)
        if switch_error != ok { w.fault += 1u32 }
        k += 1u32
    }
}

fn matches(w: *World, expect: str) -> bool {
    if w.filled != expect.len { ret false }
    var i = 0usize
    while i < expect.len {
        if w.order[i] != u32(expect[i] - 48u8) { ret false }
        i += 1usize
    }
    ret true
}

// Every fiber Done, every thread joined, nothing left inside a critical region.
fn settled(w: *World, s: *thread.Scheduler[World], count: u32) -> bool {
    var id = 0u32
    while id < count {
        let (st, state_error) = thread.fiber_state[World](s, id)
        if state_error != ok || st != .Done { ret false }
        if thread.join_fiber[World](s, id) != ok { ret false }
        id += 1u32
    }
    if thread.current[World](s) != 4294967295u32 { ret false }
    ret atomic.load(&w.concurrent, .Acquire) == 0u32
}

// 1..9: four fibers, fifty yields each, in the replica's order and one at a time.
fn even_round(w: *World, expect: str) -> i32 {
    reset(w, 0u32, 50u32, 50u32, 50u32, 50u32)
    var slots: [4]thread.Fiber = zero
    var bodies: [4]fn(*World, u32) = zero
    let (made, scheduler_error) = thread.scheduler[World](w, slots[..], bodies[..], 0usize)
    if scheduler_error != ok { ret 1i32 }
    var s = made
    w.sched = mem.cast[*void](&s)
    var i = 0usize
    while i < 4usize {
        let (id, fiber_error) = thread.fiber[World](&s, body)
        if fiber_error != ok { ret 2i32 }
        if id != u32(i) { ret 3i32 }
        i += 1usize
    }
    if thread.current[World](&s) != 4294967295u32 { ret 4i32 }
    if thread.yield_now[World](&s) == ok { ret 5i32 }
    if thread.run[World](&s) != ok { ret 6i32 }
    if !matches(w, expect) { ret 7i32 }
    if w.peak != 1u32 || w.fault != 0u32 { ret 8i32 }
    if !settled(w, &s, 4u32) { ret 9i32 }
    ret 0i32
}

// 10..12: fibers of different lengths keep the same rule as they drop out.
fn uneven_round(w: *World, expect: str) -> i32 {
    reset(w, 0u32, 3u32, 7u32, 5u32, 11u32)
    var slots: [4]thread.Fiber = zero
    var bodies: [4]fn(*World, u32) = zero
    let (made, scheduler_error) = thread.scheduler[World](w, slots[..], bodies[..], 0usize)
    if scheduler_error != ok { ret 10i32 }
    var s = made
    w.sched = mem.cast[*void](&s)
    var i = 0usize
    while i < 4usize {
        let (id, fiber_error) = thread.fiber[World](&s, body)
        if fiber_error != ok { ret 10i32 }
        i += 1usize
    }
    if thread.run[World](&s) != ok { ret 11i32 }
    if !matches(w, expect) || w.peak != 1u32 || w.fault != 0u32 { ret 12i32 }
    if !settled(w, &s, 4u32) { ret 12i32 }
    ret 0i32
}

// 13..15: `yield_to` names its successor, so the order is 0-2-1 and not 0-1-2.
fn directed(w: *World, expect: str) -> i32 {
    reset(w, 1u32, 4u32, 4u32, 4u32, 0u32)
    var slots: [4]thread.Fiber = zero
    var bodies: [4]fn(*World, u32) = zero
    let (made, scheduler_error) = thread.scheduler[World](w, slots[..], bodies[..], 3usize)
    if scheduler_error != ok { ret 13i32 }
    var s = made
    w.sched = mem.cast[*void](&s)
    var i = 0usize
    while i < 3usize {
        let (id, fiber_error) = thread.fiber[World](&s, body)
        if fiber_error != ok { ret 13i32 }
        i += 1usize
    }
    let (extra, extra_error) = thread.fiber[World](&s, body)
    if extra_error != thread.Full { ret 14i32 }
    if thread.run[World](&s) != ok { ret 14i32 }
    if !matches(w, expect) || w.peak != 1u32 || w.fault != 0u32 { ret 15i32 }
    if !settled(w, &s, 3u32) { ret 15i32 }
    ret 0i32
}

// 16..22: a suspended fiber stalls the schedule until it is resumed.
fn held(w: *World, part: str, whole: str) -> i32 {
    reset(w, 2u32, 4u32, 4u32, 4u32, 0u32)
    w.hold = 1u32
    w.hold_at = 1u32
    var slots: [4]thread.Fiber = zero
    var bodies: [4]fn(*World, u32) = zero
    let (made, scheduler_error) = thread.scheduler[World](w, slots[..], bodies[..], 3usize)
    if scheduler_error != ok { ret 16i32 }
    var s = made
    w.sched = mem.cast[*void](&s)
    var i = 0usize
    while i < 3usize {
        let (id, fiber_error) = thread.fiber[World](&s, body)
        if fiber_error != ok { ret 16i32 }
        i += 1usize
    }
    if thread.run[World](&s) != thread.Invalid { ret 17i32 }
    let (st, state_error) = thread.fiber_state[World](&s, 1u32)
    if state_error != ok || st != .Suspended { ret 18i32 }
    if !matches(w, part) { ret 19i32 }
    if thread.join_fiber[World](&s, 1u32) != thread.Invalid { ret 20i32 }
    if thread.resume[World](&s, 1u32) != ok { ret 20i32 }
    if thread.resume[World](&s, 1u32) != thread.Invalid { ret 20i32 }
    if thread.run[World](&s) != ok { ret 21i32 }
    if !matches(w, whole) || w.peak != 1u32 || w.fault != 0u32 { ret 22i32 }
    if !settled(w, &s, 3u32) { ret 22i32 }
    ret 0i32
}

// 23..25: a body that never yields runs once, is Done, and is never picked again.
fn plain_done(w: *World) -> i32 {
    reset(w, 3u32, 1u32, 1u32, 0u32, 0u32)
    var slots: [4]thread.Fiber = zero
    var bodies: [4]fn(*World, u32) = zero
    let (made, scheduler_error) = thread.scheduler[World](w, slots[..2usize], bodies[..2usize], 0usize)
    if scheduler_error != ok { ret 23i32 }
    var s = made
    w.sched = mem.cast[*void](&s)
    var i = 0usize
    while i < 2usize {
        let (id, fiber_error) = thread.fiber[World](&s, body)
        if fiber_error != ok { ret 23i32 }
        i += 1usize
    }
    if thread.run[World](&s) != ok { ret 24i32 }
    if !matches(w, "01") { ret 24i32 }
    if w.ran[0usize] != 1u32 || w.ran[1usize] != 1u32 { ret 25i32 }
    if thread.run[World](&s) != ok { ret 25i32 }
    if w.ran[0usize] != 1u32 || w.ran[1usize] != 1u32 || w.filled != 2usize { ret 25i32 }
    if !settled(w, &s, 2u32) { ret 25i32 }
    ret 0i32
}

// 26..29: the storage bounds and the unknown id.
fn limits(w: *World) -> i32 {
    reset(w, 3u32, 1u32, 1u32, 0u32, 0u32)
    var slots: [4]thread.Fiber = zero
    var bodies: [4]fn(*World, u32) = zero
    let (empty_one, none_error) = thread.scheduler[World](w, slots[..0usize], bodies[..], 0usize)
    if none_error != thread.Invalid { ret 26i32 }
    let (short_one, short_error) = thread.scheduler[World](w, slots[..], bodies[..1usize], 0usize)
    if short_error != thread.Invalid { ret 26i32 }
    let (made, scheduler_error) = thread.scheduler[World](w, slots[..], bodies[..], 2usize)
    if scheduler_error != ok { ret 27i32 }
    var s = made
    w.sched = mem.cast[*void](&s)
    var i = 0usize
    while i < 2usize {
        let (id, fiber_error) = thread.fiber[World](&s, body)
        if fiber_error != ok { ret 27i32 }
        i += 1usize
    }
    let (extra, extra_error) = thread.fiber[World](&s, body)
    if extra_error != thread.Full { ret 28i32 }
    if thread.yield_to[World](&s, 9u32) != thread.Invalid { ret 29i32 }
    if thread.resume[World](&s, 9u32) != thread.Invalid { ret 29i32 }
    if thread.join_fiber[World](&s, 9u32) != thread.Invalid { ret 29i32 }
    let (st, state_error) = thread.fiber_state[World](&s, 9u32)
    if state_error != thread.Invalid { ret 29i32 }
    if thread.run[World](&s) != ok { ret 29i32 }
    if !settled(w, &s, 2u32) { ret 29i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var w: World = zero
    let even = "01230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123012301230123"
    let code1 = even_round(&w, even)
    if code1 != 0i32 { os.exit(code1) }
    let code2 = uneven_round(&w, "01230123012312312313133333")
    if code2 != 0i32 { os.exit(code2) }
    let code3 = directed(&w, "021021021021")
    if code3 != 0i32 { os.exit(code3) }
    let code4 = held(&w, "0120120202", "012012020211")
    if code4 != 0i32 { os.exit(code4) }
    let code5 = plain_done(&w)
    if code5 != 0i32 { os.exit(code5) }
    let code6 = limits(&w)
    if code6 != 0i32 { os.exit(code6) }
    try io.print("thread fiber ok\n")
    ret ok
}
