// The half a single thread cannot check: that the locks actually exclude and the
// waits actually block and wake.

use e.mem
use e.os
use e.sync
use e.atomic
use e.time

error Failed

type Guarded = struct {
    lock: sync.Mutex,
    plain: i64,
}

fn hammer(g: *Guarded) {
    var at = 0usize
    while at < 20000usize {
        sync.mutex_lock(&g.lock)
        // Not atomic on purpose: only the mutex makes this safe, so a lock that does
        // not exclude loses increments and the total comes out short.
        g.plain += 1i64
        sync.mutex_unlock(&g.lock)
        at += 1usize
    }
}

type Shared = struct {
    gate: sync.Semaphore,
    done: sync.Semaphore,
    ran: Atomic[u32],
    once: sync.Once,
    calls: Atomic[u32],
    readers: sync.RwLock,
    inside: Atomic[u32],
    overlap: Atomic[u32],
}

fn gated(s: *Shared) {
    sync.semaphore_wait(&s.gate)
    let bumped = atomic.add(&s.ran, 1u32, .Release)
    let posted = sync.semaphore_post(&s.done, 1u32)
}

fn once_racer(s: *Shared) {
    let call_error = sync.once_call[Shared](&s.once, s, count_once)
    let posted = sync.semaphore_post(&s.done, 1u32)
}

fn count_once(s: *Shared) -> err {
    let bumped = atomic.add(&s.calls, 1u32, .Release)
    ret ok
}

fn reader(s: *Shared) {
    var at = 0usize
    while at < 200usize {
        sync.rwlock_read_lock(&s.readers)
        let entered = atomic.add(&s.inside, 1u32, .AcqRel) + 1u32
        if entered > 8u32 { let bad = atomic.add(&s.overlap, 1u32, .Release) }
        let left = atomic.sub(&s.inside, 1u32, .AcqRel)
        sync.rwlock_read_unlock(&s.readers)
        at += 1usize
    }
    let posted = sync.semaphore_post(&s.done, 1u32)
}

fn writer(s: *Shared) {
    var at = 0usize
    while at < 200usize {
        sync.rwlock_write_lock(&s.readers)
        // A writer must be alone: any reader inside here is a broken lock.
        let seen = atomic.load(&s.inside, .Acquire)
        if seen != 0u32 { let bad = atomic.add(&s.overlap, 1u32, .Release) }
        sync.rwlock_write_unlock(&s.readers)
        at += 1usize
    }
    let posted = sync.semaphore_post(&s.done, 1u32)
}

type Meeting = struct {
    point: sync.Barrier,
    lasts: Atomic[u32],
    rounds: Atomic[u32],
}

fn meet(m: *Meeting) {
    var round = 0usize
    while round < 50usize {
        if sync.barrier_wait(&m.point) { let last = atomic.add(&m.lasts, 1u32, .Release) }
        round += 1usize
    }
    let done = atomic.add(&m.rounds, 1u32, .Release)
}

fn join_all(workers: []os.Thread, count: usize) -> err {
    var at = 0usize
    while at < count {
        let join_error = os.thread_join(workers[at])
        if join_error != ok { ret join_error }
        at += 1usize
    }
    ret ok
}

// A raw futex wake is allowed to be spurious: it must not make either condition
// wait return until the generation changes, and the mutex must be reacquired first.
type ConditionProbe = struct {
    condition: sync.Condition,
    lock: sync.Mutex,
    entered: Atomic[u32],
    answer: Atomic[u32],
    held: Atomic[u32],
    done: sync.Semaphore,
}

fn condition_probe() -> ConditionProbe {
    var probe: ConditionProbe = zero
    probe.condition = sync.condition()
    probe.lock = sync.mutex()
    probe.done = sync.semaphore(0u32)
    ret probe
}

fn wait_for_condition_entry(probe: *ConditionProbe) {
    while atomic.load(&probe.entered, .Acquire) == 0u32 {}
}

fn raw_wake_condition(probe: *ConditionProbe) {
    var wakes = 0usize
    while wakes < 4096usize {
        os.wake_one_u32(&probe.condition.state)
        wakes += 1usize
    }
}

fn condition_waiter(probe: *ConditionProbe) {
    sync.mutex_lock(&probe.lock)
    atomic.store(&probe.entered, 1u32, .Release)
    sync.condition_wait(&probe.condition, &probe.lock)
    let held = !sync.mutex_try_lock(&probe.lock)
    if !held { sync.mutex_unlock(&probe.lock) }
    if held { atomic.store(&probe.held, 1u32, .Release) }
    atomic.store(&probe.answer, 1u32, .Release)
    if held { sync.mutex_unlock(&probe.lock) }
    let posted = sync.semaphore_post(&probe.done, 1u32)
}

fn timed_condition_waiter(probe: *ConditionProbe) {
    sync.mutex_lock(&probe.lock)
    atomic.store(&probe.entered, 1u32, .Release)
    let signalled = sync.condition_wait_for(&probe.condition, &probe.lock, time.millis(150i64))
    let held = !sync.mutex_try_lock(&probe.lock)
    if !held { sync.mutex_unlock(&probe.lock) }
    if held { atomic.store(&probe.held, 1u32, .Release) }
    if signalled {
        atomic.store(&probe.answer, 1u32, .Release)
    } else {
        atomic.store(&probe.answer, 2u32, .Release)
    }
    if held { sync.mutex_unlock(&probe.lock) }
    let posted = sync.semaphore_post(&probe.done, 1u32)
}

fn check_condition_spurious_wakes() -> err {
    // An untimed wait ignores raw wakes and returns only after the true signal.
    var signal_probe = condition_probe()
    let (signal_worker, signal_create_error) = os.thread_create[ConditionProbe](condition_waiter, &signal_probe, 1048576usize)
    if signal_create_error != ok { ret signal_create_error }
    wait_for_condition_entry(&signal_probe)
    raw_wake_condition(&signal_probe)
    if sync.semaphore_wait_for(&signal_probe.done, time.millis(25i64)) {
        let signal_join_error = os.thread_join(signal_worker)
        if signal_join_error != ok { ret signal_join_error }
        ret Failed
    }
    sync.mutex_lock(&signal_probe.lock)
    sync.condition_signal(&signal_probe.condition)
    sync.mutex_unlock(&signal_probe.lock)
    sync.semaphore_wait(&signal_probe.done)
    let signal_join_error = os.thread_join(signal_worker)
    if signal_join_error != ok { ret signal_join_error }
    if atomic.load(&signal_probe.answer, .Acquire) != 1u32 { ret Failed }
    if atomic.load(&signal_probe.held, .Acquire) != 1u32 { ret Failed }

    // A timed wait ignores the same raw wakes, then reports false only after expiry.
    var timeout_probe = condition_probe()
    let (started, start_error) = time.monotonic()
    if start_error != ok { ret start_error }
    let (timeout_worker, timeout_create_error) = os.thread_create[ConditionProbe](timed_condition_waiter, &timeout_probe, 1048576usize)
    if timeout_create_error != ok { ret timeout_create_error }
    wait_for_condition_entry(&timeout_probe)
    raw_wake_condition(&timeout_probe)
    if sync.semaphore_wait_for(&timeout_probe.done, time.millis(25i64)) {
        let timeout_join_error = os.thread_join(timeout_worker)
        if timeout_join_error != ok { ret timeout_join_error }
        ret Failed
    }
    sync.semaphore_wait(&timeout_probe.done)
    let timeout_join_error = os.thread_join(timeout_worker)
    if timeout_join_error != ok { ret timeout_join_error }
    if atomic.load(&timeout_probe.answer, .Acquire) != 2u32 { ret Failed }
    if atomic.load(&timeout_probe.held, .Acquire) != 1u32 { ret Failed }
    if time.since(started).nanos < 100000000i64 { ret Failed }
    ret ok
}

fn main(a: *mem.Arena) -> err {
    // A mutex that does not exclude loses increments.
    var g: Guarded = zero
    g.lock = sync.mutex()
    var hammers: [4]os.Thread = zero
    var started = 0usize
    while started < 4usize {
        let (worker, create_error) = os.thread_create[Guarded](hammer, &g, 1048576usize)
        if create_error == os.Unsupported { ret ok }
        if create_error != ok { ret create_error }
        hammers[started] = worker
        started += 1usize
    }
    try join_all(hammers[..], 4usize)
    if g.plain != 80000i64 { ret Failed }

    // A semaphore blocks until it is posted, and every waiter is released exactly once.
    var s: Shared = zero
    s.gate = sync.semaphore(0u32)
    s.done = sync.semaphore(0u32)
    s.once = sync.once()
    s.readers = sync.rwlock()
    var workers: [8]os.Thread = zero
    started = 0usize
    while started < 4usize {
        let (worker, create_error) = os.thread_create[Shared](gated, &s, 1048576usize)
        if create_error != ok { ret create_error }
        workers[started] = worker
        started += 1usize
    }
    // Nothing may have run yet: the gate is shut.
    if !sync.semaphore_wait_for(&s.done, time.millis(50i64)) {
        if atomic.load(&s.ran, .Acquire) != 0u32 { ret Failed }
    } else {
        ret Failed
    }
    let opened = sync.semaphore_post(&s.gate, 4u32)
    if opened != ok { ret opened }
    var released = 0usize
    while released < 4usize {
        sync.semaphore_wait(&s.done)
        released += 1usize
    }
    try join_all(workers[..], 4usize)
    if atomic.load(&s.ran, .Acquire) != 4u32 { ret Failed }

    // `once_call` under contention runs its body exactly once.
    started = 0usize
    while started < 4usize {
        let (worker, create_error) = os.thread_create[Shared](once_racer, &s, 1048576usize)
        if create_error != ok { ret create_error }
        workers[started] = worker
        started += 1usize
    }
    released = 0usize
    while released < 4usize {
        sync.semaphore_wait(&s.done)
        released += 1usize
    }
    try join_all(workers[..], 4usize)
    if atomic.load(&s.calls, .Acquire) != 1u32 { ret Failed }

    try check_condition_spurious_wakes()

    // Readers share and a writer excludes them.
    started = 0usize
    while started < 6usize {
        let (worker, create_error) = os.thread_create[Shared](reader, &s, 1048576usize)
        if create_error != ok { ret create_error }
        workers[started] = worker
        started += 1usize
    }
    let (scribe, scribe_error) = os.thread_create[Shared](writer, &s, 1048576usize)
    if scribe_error != ok { ret scribe_error }
    released = 0usize
    while released < 7usize {
        sync.semaphore_wait(&s.done)
        released += 1usize
    }
    let scribe_join_error = os.thread_join(scribe)
    let readers_join_error = join_all(workers[..], 6usize)
    if scribe_join_error != ok { ret scribe_join_error }
    if readers_join_error != ok { ret readers_join_error }
    if atomic.load(&s.overlap, .Acquire) != 0u32 { ret Failed }

    // Exactly one participant is told it was last, once per generation.
    var meeting: Meeting = zero
    let (point, barrier_error) = sync.barrier(a, 4u32)
    if barrier_error != ok { ret barrier_error }
    meeting.point = point
    var party: [4]os.Thread = zero
    started = 0usize
    while started < 4usize {
        let (worker, create_error) = os.thread_create[Meeting](meet, &meeting, 1048576usize)
        if create_error != ok { ret create_error }
        party[started] = worker
        started += 1usize
    }
    try join_all(party[..], 4usize)
    if atomic.load(&meeting.rounds, .Acquire) != 4u32 { ret Failed }
    if atomic.load(&meeting.lasts, .Acquire) != 50u32 { ret Failed }
    ret ok
}
