// e.sync.flight: concurrent callers for one key share one execution (D2802). The leader's work blocks
// on a semaphore until the test has seen every other caller queued, so the sharing is deterministic;
// then: one execution, all callers see its value and error, sequential calls re-run, distinct keys
// run independently, `forget` makes the next caller a new leader, and a full table answers `Full`.
use e.io
use e.mem
use e.os
use e.sync
use e.sync.flight
use e.atomic
use e.thread
use e.time

type Work = struct { runs: Atomic[u32], hold: sync.Semaphore, entered: sync.Semaphore, fail: bool, label: str }
type Caller = struct { g: *flight.Group, work: *Work, key: str, value: str, joint: bool, failure: err, done: Atomic[u32] }

error Boom

fn work(ctx: *void) -> (str, err) {
    var w = mem.cast[*Work](ctx)
    let n = atomic.add(&w.runs, 1u32, .AcqRel)
    let posted = sync.semaphore_post(&w.entered, 1u32)
    sync.semaphore_wait(&w.hold)
    if w.fail { ret ("", Boom) }
    ret (w.label, ok)
}

fn instant(ctx: *void) -> (str, err) {
    var w = mem.cast[*Work](ctx)
    let n = atomic.add(&w.runs, 1u32, .AcqRel)
    ret ("instant", ok)
}

fn call(c: *Caller) {
    let (value, joint, failure) = flight.do(c.g, c.key, mem.cast[*void](c.work), work)
    c.value = value
    c.joint = joint
    c.failure = failure
    let stored = atomic.add(&c.done, 1u32, .Release)
}

fn text_is(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// Waits (bounded) until `key` has `want` queued waiters.
fn await_waiters(g: *flight.Group, key: str, want: u32) -> bool {
    var nap = sync.semaphore(0u32)
    var spins = 0usize
    while spins < 4000usize {
        if flight.waiting(g, key) >= want { ret true }
        let slept = sync.semaphore_wait_for(&nap, time.millis(5i64))
        spins += 1usize
    }
    ret false
}

fn start(a: *mem.Arena, callers: []Caller) -> (thread.Group, err) {
    let (group, spawn_error) = thread.spawn_all[Caller](a, call, callers, 65536usize)
    ret (group, spawn_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var slots: [4]flight.Call = zero
    var g = flight.group(slots[0usize..4usize])
    var w: Work = zero
    w.hold = sync.semaphore(0u32)
    w.entered = sync.semaphore(0u32)
    w.label = "result"
    // 1: eight callers, one execution, all joint.
    let (callers, callers_error) = mem.alloc[Caller](a, 8usize)
    if callers_error != ok { os.exit(1i32) }
    var i = 0usize
    while i < 8usize {
        var c: Caller = zero
        c.g = &g
        c.work = &w
        c.key = "k"
        callers[i] = c
        i += 1usize
    }
    let (group, spawn_error) = start(a, callers)
    if spawn_error != ok { os.exit(2i32) }
    sync.semaphore_wait(&w.entered)
    if !await_waiters(&g, "k", 7u32) { os.exit(3i32) }
    let released = sync.semaphore_post(&w.hold, 1u32)
    let joined = thread.join_all(group)
    if joined != ok { os.exit(4i32) }
    if atomic.load(&w.runs, .Acquire) != 1u32 { os.exit(5i32) }
    i = 0usize
    while i < 8usize {
        if !text_is(callers[i].value, "result") || !callers[i].joint || callers[i].failure != ok { os.exit(6i32) }
        i += 1usize
    }
    // 2: a later call is a new execution and is not joint.
    var single: Caller = zero
    single.g = &g
    single.work = &w
    single.key = "k"
    let released2 = sync.semaphore_post(&w.hold, 1u32)
    call(&single)
    if atomic.load(&w.runs, .Acquire) != 2u32 || single.joint || !text_is(single.value, "result") { os.exit(7i32) }
    // 3: the error reaches every caller.
    var w2: Work = zero
    w2.hold = sync.semaphore(0u32)
    w2.entered = sync.semaphore(0u32)
    w2.fail = true
    let (callers2, callers2_error) = mem.alloc[Caller](a, 3usize)
    if callers2_error != ok { os.exit(8i32) }
    i = 0usize
    while i < 3usize {
        var c: Caller = zero
        c.g = &g
        c.work = &w2
        c.key = "bad"
        callers2[i] = c
        i += 1usize
    }
    let (group2, spawn2_error) = start(a, callers2)
    if spawn2_error != ok { os.exit(9i32) }
    sync.semaphore_wait(&w2.entered)
    if !await_waiters(&g, "bad", 2u32) { os.exit(10i32) }
    let released3 = sync.semaphore_post(&w2.hold, 1u32)
    let joined2 = thread.join_all(group2)
    if joined2 != ok { os.exit(11i32) }
    i = 0usize
    while i < 3usize {
        if callers2[i].failure != Boom || callers2[i].value.len != 0usize { os.exit(12i32) }
        i += 1usize
    }
    if atomic.load(&w2.runs, .Acquire) != 1u32 { os.exit(13i32) }
    // 4: distinct keys do not share: two leaders at once, each waiting for its own release.
    var wa: Work = zero
    wa.hold = sync.semaphore(0u32)
    wa.entered = sync.semaphore(0u32)
    wa.label = "alpha"
    var wb: Work = zero
    wb.hold = sync.semaphore(0u32)
    wb.entered = sync.semaphore(0u32)
    wb.label = "beta"
    let (callers3, callers3_error) = mem.alloc[Caller](a, 2usize)
    if callers3_error != ok { os.exit(14i32) }
    var ca: Caller = zero
    ca.g = &g
    ca.work = &wa
    ca.key = "a"
    callers3[0usize] = ca
    var cb: Caller = zero
    cb.g = &g
    cb.work = &wb
    cb.key = "b"
    callers3[1usize] = cb
    let (group3, spawn3_error) = start(a, callers3)
    if spawn3_error != ok { os.exit(15i32) }
    sync.semaphore_wait(&wa.entered)
    sync.semaphore_wait(&wb.entered)
    let released4 = sync.semaphore_post(&wa.hold, 1u32)
    let released5 = sync.semaphore_post(&wb.hold, 1u32)
    let joined3 = thread.join_all(group3)
    if joined3 != ok { os.exit(16i32) }
    if !text_is(callers3[0usize].value, "alpha") || !text_is(callers3[1usize].value, "beta") { os.exit(17i32) }
    if callers3[0usize].joint || callers3[1usize].joint { os.exit(18i32) }
    // 5: forget makes the next caller a new leader while the first still runs.
    var w3: Work = zero
    w3.hold = sync.semaphore(0u32)
    w3.entered = sync.semaphore(0u32)
    w3.label = "first"
    var first: Caller = zero
    first.g = &g
    first.work = &w3
    first.key = "f"
    let (callers4, callers4_error) = mem.alloc[Caller](a, 1usize)
    if callers4_error != ok { os.exit(19i32) }
    callers4[0usize] = first
    let (group4, spawn4_error) = start(a, callers4)
    if spawn4_error != ok { os.exit(20i32) }
    sync.semaphore_wait(&w3.entered)
    flight.forget(&g, "f")
    var second: Caller = zero
    second.g = &g
    second.work = &w3
    second.key = "f"
    w3.label = "second"
    // a new leader: run it on this thread, with the hold already posted for it
    let released6 = sync.semaphore_post(&w3.hold, 2u32)
    call(&second)
    let joined4 = thread.join_all(group4)
    if joined4 != ok { os.exit(21i32) }
    if atomic.load(&w3.runs, .Acquire) != 2u32 { os.exit(22i32) }
    // 6: a full table answers Full.
    var tiny: [1]flight.Call = zero
    var small = flight.group(tiny[0usize..1usize])
    var w4: Work = zero
    w4.hold = sync.semaphore(0u32)
    w4.entered = sync.semaphore(0u32)
    w4.label = "x"
    var holder: Caller = zero
    holder.g = &small
    holder.work = &w4
    holder.key = "one"
    let (callers5, callers5_error) = mem.alloc[Caller](a, 1usize)
    if callers5_error != ok { os.exit(23i32) }
    callers5[0usize] = holder
    let (group5, spawn5_error) = start(a, callers5)
    if spawn5_error != ok { os.exit(24i32) }
    sync.semaphore_wait(&w4.entered)
    let (_, _, full_error) = flight.do(&small, "two", mem.cast[*void](&w4), instant)
    if full_error != flight.Full { os.exit(25i32) }
    let released7 = sync.semaphore_post(&w4.hold, 1u32)
    let joined5 = thread.join_all(group5)
    if joined5 != ok { os.exit(26i32) }
    try io.print("sync flight ok")
    ret ok
}
