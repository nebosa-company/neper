// Section 8's synchronisation primitives. Every one of them is an `Atomic[u32]` and
// the three `e.os` blocking calls over it: the fast paths are a compare-and-swap or an
// exchange and never enter the kernel, and only a thread that actually has to block
// calls `os.wait_u32`.
//
// Every wait rechecks its own state after waking, because `wait_u32` promises spurious
// wakes and promises no count from a wake. That recheck is what makes the loops below
// correct rather than merely usual, so none of them is written as a single wait.
//
// The timed forms take a deadline once and pass what is left of it to each wait, so a
// spurious wake cannot extend the timeout. A negative duration cannot be reported as
// `Invalid` -- they return `bool` -- so it is an immediate `false`, and zero polls once.

use e.atomic
use e.mem
use e.os
use e.time

type Mutex = struct { state: Atomic[u32] }
type RwLock = struct { state: Atomic[u32] }
type Condition = struct { state: Atomic[u32] }
type Semaphore = struct { state: Atomic[u32] }
type Event = struct { state: Atomic[u32], manual_reset: bool }
type Once = struct { state: Atomic[u32] }
type Barrier = struct { state: *void }

error Invalid

// The bit that says a writer holds the lock; the rest of the word counts readers, so
// the two never need separate words and a reader's arrival is one atomic add.
const WRITER_HELD: u32 = 2147483648u32
const READER_MASK: u32 = 2147483647u32
const COUNT_MAX: u32 = 4294967295u32

// An absolute monotonic deadline. A clock that fails leaves the caller polling rather
// than blocking forever, which is the safe direction for a call that promises to
// return by a time it can no longer measure.
fn deadline_for(timeout: time.Duration) -> i64 {
    let (start, clock_error) = time.monotonic()
    if clock_error != ok { ret 0i64 }
    ret start.nanos + time.as_nanos(timeout)
}

fn remaining_for(deadline: i64) -> i64 {
    let (current, clock_error) = time.monotonic()
    if clock_error != ok { ret 0i64 }
    let left = deadline - current.nanos
    if left < 0i64 { ret 0i64 }
    ret left
}

// ---- Mutex ----------------------------------------------------------------
//
// Three states: 0 free, 1 held with no waiter, 2 held and someone is waiting. The
// exchange to 2 is what makes the unlock cheap -- an uncontended unlock sees 1 and
// wakes nobody.

fn mutex() -> Mutex {
    ret Mutex { state: atomic.init(0u32) }
}

fn mutex_lock(m: *Mutex) {
    let (won, seen) = atomic.cas(&m.state, 0u32, 1u32, .Acquire, .Relaxed)
    if won { ret }
    while true {
        let previous = atomic.xchg(&m.state, 2u32, .Acquire)
        if previous == 0u32 { ret }
        let ignored = os.wait_u32(&m.state, 2u32, -1i64)
    }
}

fn mutex_try_lock(m: *Mutex) -> bool {
    let (won, seen) = atomic.cas(&m.state, 0u32, 1u32, .Acquire, .Relaxed)
    ret won
}

fn mutex_lock_for(m: *Mutex, timeout: time.Duration) -> bool {
    if time.as_nanos(timeout) < 0i64 { ret false }
    let (won, seen) = atomic.cas(&m.state, 0u32, 1u32, .Acquire, .Relaxed)
    if won { ret true }
    let deadline = deadline_for(timeout)
    while true {
        let previous = atomic.xchg(&m.state, 2u32, .Acquire)
        if previous == 0u32 { ret true }
        let left = remaining_for(deadline)
        let waited = os.wait_u32(&m.state, 2u32, left)
        if left == 0i64 {
            // One more attempt after the poll, so a lock freed during it is still won.
            let (late, late_seen) = atomic.cas(&m.state, 0u32, 2u32, .Acquire, .Relaxed)
            ret late
        }
    }
    ret false
}

fn mutex_unlock(m: *Mutex) {
    let previous = atomic.xchg(&m.state, 0u32, .Release)
    if previous == 2u32 { os.wake_one_u32(&m.state) }
}

// ---- RwLock ---------------------------------------------------------------
//
// ponytail: a writer can be starved by a stream of readers, because a reader joins
// whenever the writer bit is clear. Add a queued or phase-fair lock if that shows up
// in practice -- it costs a second word and this one is the whole fence.

fn rwlock() -> RwLock {
    ret RwLock { state: atomic.init(0u32) }
}

fn rwlock_read_lock(l: *RwLock) {
    while true {
        let seen = atomic.load(&l.state, .Acquire)
        if seen & WRITER_HELD == 0u32 {
            if seen & READER_MASK != READER_MASK {
                let (won, current) = atomic.cas(&l.state, seen, seen + 1u32, .Acquire, .Relaxed)
                if won { ret }
                continue
            }
        }
        let ignored = os.wait_u32(&l.state, seen, -1i64)
    }
}

fn rwlock_try_read_lock(l: *RwLock) -> bool {
    let seen = atomic.load(&l.state, .Acquire)
    if seen & WRITER_HELD != 0u32 { ret false }
    if seen & READER_MASK == READER_MASK { ret false }
    let (won, current) = atomic.cas(&l.state, seen, seen + 1u32, .Acquire, .Relaxed)
    ret won
}

fn rwlock_read_lock_for(l: *RwLock, timeout: time.Duration) -> bool {
    if time.as_nanos(timeout) < 0i64 { ret false }
    let deadline = deadline_for(timeout)
    while true {
        if rwlock_try_read_lock(l) { ret true }
        let left = remaining_for(deadline)
        let seen = atomic.load(&l.state, .Acquire)
        let waited = os.wait_u32(&l.state, seen, left)
        if left == 0i64 { ret rwlock_try_read_lock(l) }
    }
    ret false
}

fn rwlock_read_unlock(l: *RwLock) {
    let previous = atomic.sub(&l.state, 1u32, .Release)
    // The last reader out is the only one a waiting writer needs to hear from.
    if previous & READER_MASK == 1u32 { os.wake_all_u32(&l.state) }
}

fn rwlock_write_lock(l: *RwLock) {
    while true {
        let (won, seen) = atomic.cas(&l.state, 0u32, WRITER_HELD, .Acquire, .Relaxed)
        if won { ret }
        let ignored = os.wait_u32(&l.state, seen, -1i64)
    }
}

fn rwlock_try_write_lock(l: *RwLock) -> bool {
    let (won, seen) = atomic.cas(&l.state, 0u32, WRITER_HELD, .Acquire, .Relaxed)
    ret won
}

fn rwlock_write_lock_for(l: *RwLock, timeout: time.Duration) -> bool {
    if time.as_nanos(timeout) < 0i64 { ret false }
    let deadline = deadline_for(timeout)
    while true {
        let (won, seen) = atomic.cas(&l.state, 0u32, WRITER_HELD, .Acquire, .Relaxed)
        if won { ret true }
        let left = remaining_for(deadline)
        let waited = os.wait_u32(&l.state, seen, left)
        if left == 0i64 {
            let (late, late_seen) = atomic.cas(&l.state, 0u32, WRITER_HELD, .Acquire, .Relaxed)
            ret late
        }
    }
    ret false
}

fn rwlock_write_unlock(l: *RwLock) {
    atomic.store(&l.state, 0u32, .Release)
    os.wake_all_u32(&l.state)
}

// ---- Condition ------------------------------------------------------------
//
// The state is a generation counter, never a flag: a waiter reads it before releasing
// the mutex and waits for it to change, so a signal delivered in that window is not
// lost -- the value it waits on has already moved and the wait returns at once.

fn condition() -> Condition {
    ret Condition { state: atomic.init(0u32) }
}

fn condition_wait(c: *Condition, m: *Mutex) {
    let generation = atomic.load(&c.state, .Acquire)
    mutex_unlock(m)
    let ignored = os.wait_u32(&c.state, generation, -1i64)
    mutex_lock(m)
}

fn condition_wait_for(c: *Condition, m: *Mutex, timeout: time.Duration) -> bool {
    if time.as_nanos(timeout) < 0i64 { ret false }
    let generation = atomic.load(&c.state, .Acquire)
    mutex_unlock(m)
    let waited = os.wait_u32(&c.state, generation, time.as_nanos(timeout))
    mutex_lock(m)
    ret atomic.load(&c.state, .Acquire) != generation
}

fn condition_signal(c: *Condition) {
    let previous = atomic.add(&c.state, 1u32, .Release)
    os.wake_one_u32(&c.state)
}

fn condition_broadcast(c: *Condition) {
    let previous = atomic.add(&c.state, 1u32, .Release)
    os.wake_all_u32(&c.state)
}

// ---- Semaphore ------------------------------------------------------------

fn semaphore(initial: u32) -> Semaphore {
    ret Semaphore { state: atomic.init(initial) }
}

fn semaphore_wait(s: *Semaphore) {
    while true {
        let seen = atomic.load(&s.state, .Acquire)
        if seen == 0u32 {
            let ignored = os.wait_u32(&s.state, 0u32, -1i64)
            continue
        }
        let (won, current) = atomic.cas(&s.state, seen, seen - 1u32, .Acquire, .Relaxed)
        if won { ret }
    }
}

fn semaphore_try_wait(s: *Semaphore) -> bool {
    let seen = atomic.load(&s.state, .Acquire)
    if seen == 0u32 { ret false }
    let (won, current) = atomic.cas(&s.state, seen, seen - 1u32, .Acquire, .Relaxed)
    ret won
}

fn semaphore_wait_for(s: *Semaphore, timeout: time.Duration) -> bool {
    if time.as_nanos(timeout) < 0i64 { ret false }
    let deadline = deadline_for(timeout)
    while true {
        if semaphore_try_wait(s) { ret true }
        let left = remaining_for(deadline)
        let waited = os.wait_u32(&s.state, 0u32, left)
        if left == 0i64 { ret semaphore_try_wait(s) }
    }
    ret false
}

// The count is a `u32` and the fence gives an error rather than a wrap, so a post that
// would carry it past the top is refused and the semaphore is left alone.
fn semaphore_post(s: *Semaphore, count: u32) -> err {
    if count == 0u32 { ret ok }
    while true {
        let seen = atomic.load(&s.state, .Acquire)
        if seen > COUNT_MAX - count { ret Invalid }
        let (won, current) = atomic.cas(&s.state, seen, seen + count, .Release, .Relaxed)
        if won { break }
    }
    if count == 1u32 {
        os.wake_one_u32(&s.state)
    } else {
        os.wake_all_u32(&s.state)
    }
    ret ok
}

// ---- Event ----------------------------------------------------------------

fn event(manual_reset: bool, signaled: bool) -> Event {
    var initial = 0u32
    if signaled { initial = 1u32 }
    ret Event { state: atomic.init(initial), manual_reset: manual_reset }
}

fn event_set(e: *Event) {
    atomic.store(&e.state, 1u32, .Release)
    os.wake_all_u32(&e.state)
}

fn event_reset(e: *Event) {
    atomic.store(&e.state, 0u32, .Release)
}

// An auto-reset event is consumed by exactly one waiter, so the wait is the exchange
// that takes it; a manual-reset one stays set and every waiter passes.
fn event_take(e: *Event) -> bool {
    if e.manual_reset { ret atomic.load(&e.state, .Acquire) == 1u32 }
    let (won, seen) = atomic.cas(&e.state, 1u32, 0u32, .Acquire, .Relaxed)
    ret won
}

fn event_wait(e: *Event) {
    while true {
        if event_take(e) { ret }
        let ignored = os.wait_u32(&e.state, 0u32, -1i64)
    }
}

fn event_wait_for(e: *Event, timeout: time.Duration) -> bool {
    if time.as_nanos(timeout) < 0i64 { ret false }
    let deadline = deadline_for(timeout)
    while true {
        if event_take(e) { ret true }
        let left = remaining_for(deadline)
        let waited = os.wait_u32(&e.state, 0u32, left)
        if left == 0i64 { ret event_take(e) }
    }
    ret false
}

// ---- Once -----------------------------------------------------------------
//
// 0 not run, 1 running, 2 done. A failing `f` puts the state back to 0 rather than to
// 2, so the next caller retries it -- completion is published only on `ok`.

fn once() -> Once {
    ret Once { state: atomic.init(0u32) }
}

fn once_call[Ctx: type](o: *Once, ctx: *Ctx, f: fn(*Ctx) -> err) -> err {
    while true {
        if atomic.load(&o.state, .Acquire) == 2u32 { ret ok }
        let (won, seen) = atomic.cas(&o.state, 0u32, 1u32, .Acquire, .Acquire)
        if won {
            let call_error = f(ctx)
            if call_error != ok {
                atomic.store(&o.state, 0u32, .Release)
                os.wake_all_u32(&o.state)
                ret call_error
            }
            atomic.store(&o.state, 2u32, .Release)
            os.wake_all_u32(&o.state)
            ret ok
        }
        if seen == 1u32 {
            let ignored = os.wait_u32(&o.state, 1u32, -1i64)
        }
    }
    ret ok
}

// ---- Barrier --------------------------------------------------------------
//
// The handle is a `*void` because the state outlives the call that made it and has to
// be shared by every participant; it comes from the caller's arena and is freed with
// it, so `barrier_close` only marks the barrier unusable.

type BarrierState = struct {
    parties: u32,
    waiting: Atomic[u32],
    generation: Atomic[u32],
    open: Atomic[u32],
}

fn barrier(a: *mem.Arena, parties: u32) -> (Barrier, err) {
    var empty: Barrier = zero
    if parties == 0u32 { ret (empty, Invalid) }
    let (storage, allocation_error) = mem.alloc[BarrierState](a, 1usize)
    if allocation_error != ok { ret (empty, allocation_error) }
    storage[0usize] = BarrierState { parties: parties, waiting: atomic.init(0u32), generation: atomic.init(0u32), open: atomic.init(1u32) }
    ret (Barrier { state: mem.cast[*void](&storage[0usize]) }, ok)
}

// Exactly one participant of each generation is told it was the last to arrive.
fn barrier_wait(b: *Barrier) -> bool {
    let state = mem.cast[*BarrierState](b.state)
    if atomic.load(&state.open, .Acquire) == 0u32 { ret false }
    let generation = atomic.load(&state.generation, .Acquire)
    let arrived = atomic.add(&state.waiting, 1u32, .AcqRel) + 1u32
    if arrived == state.parties {
        atomic.store(&state.waiting, 0u32, .Release)
        let released = atomic.add(&state.generation, 1u32, .Release)
        os.wake_all_u32(&state.generation)
        ret true
    }
    while atomic.load(&state.generation, .Acquire) == generation {
        if atomic.load(&state.open, .Acquire) == 0u32 { ret false }
        let ignored = os.wait_u32(&state.generation, generation, -1i64)
    }
    ret false
}

fn barrier_close(b: *Barrier) {
    let state = mem.cast[*BarrierState](b.state)
    atomic.store(&state.open, 0u32, .Release)
    let released = atomic.add(&state.generation, 1u32, .Release)
    os.wake_all_u32(&state.generation)
}
