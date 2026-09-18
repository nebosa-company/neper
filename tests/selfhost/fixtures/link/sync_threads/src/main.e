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
