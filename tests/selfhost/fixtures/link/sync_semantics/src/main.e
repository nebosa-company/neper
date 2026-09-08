// Every `e.sync` primitive's uncontended behaviour, which is where the fence's
// promises live: a timed wait returns false only on timeout, a negative duration is
// refused, `semaphore_post` reports `Invalid` rather than wrapping, an auto-reset
// event is consumed by one taker and a manual one is not, and `once_call` publishes
// completion only on `ok` so a failing body leaves the once runnable.
//
// Each timed case is also a way to hang if the wait is wrong, so they run first and
// with short timeouts: a broken one fails the suite in milliseconds instead of
// blocking it.
use e.mem
use e.sync
use e.time

error Failed

type Counter = struct { value: i64 }

fn bump(c: *Counter) -> err {
    c.value += 1i64
    ret ok
}

fn fails(c: *Counter) -> err {
    c.value += 1i64
    ret Failed
}

fn main(a: *mem.Arena) -> err {
    // Mutex: the uncontended paths and a timeout that must fire rather than hang.
    var m = sync.mutex()
    if !sync.mutex_try_lock(&m) { ret Failed }
    if sync.mutex_try_lock(&m) { ret Failed }
    if sync.mutex_lock_for(&m, time.millis(20i64)) { ret Failed }
    if sync.mutex_lock_for(&m, time.millis(-1i64)) { ret Failed }
    sync.mutex_unlock(&m)
    if !sync.mutex_lock_for(&m, time.millis(20i64)) { ret Failed }
    sync.mutex_unlock(&m)
    sync.mutex_lock(&m)
    sync.mutex_unlock(&m)

    // RwLock: readers share, a writer excludes both.
    var l = sync.rwlock()
    if !sync.rwlock_try_read_lock(&l) { ret Failed }
    if !sync.rwlock_try_read_lock(&l) { ret Failed }
    if sync.rwlock_try_write_lock(&l) { ret Failed }
    sync.rwlock_read_unlock(&l)
    sync.rwlock_read_unlock(&l)
    if !sync.rwlock_try_write_lock(&l) { ret Failed }
    if sync.rwlock_try_read_lock(&l) { ret Failed }
    if sync.rwlock_write_lock_for(&l, time.millis(20i64)) { ret Failed }
    sync.rwlock_write_unlock(&l)
    if !sync.rwlock_read_lock_for(&l, time.millis(20i64)) { ret Failed }
    sync.rwlock_read_unlock(&l)
    sync.rwlock_write_lock(&l)
    sync.rwlock_write_unlock(&l)

    // Semaphore: counted, and a post that would wrap is refused.
    var s = sync.semaphore(2u32)
    if !sync.semaphore_try_wait(&s) { ret Failed }
    sync.semaphore_wait(&s)
    if sync.semaphore_try_wait(&s) { ret Failed }
    if sync.semaphore_wait_for(&s, time.millis(20i64)) { ret Failed }
    let post_error = sync.semaphore_post(&s, 1u32)
    if post_error != ok { ret post_error }
    if !sync.semaphore_wait_for(&s, time.millis(20i64)) { ret Failed }
    var full = sync.semaphore(4294967295u32)
    if sync.semaphore_post(&full, 1u32) != sync.Invalid { ret Failed }
    if sync.semaphore_post(&full, 0u32) != ok { ret Failed }

    // Event: manual stays set, auto is consumed by one taker.
    var manual = sync.event(true, false)
    if sync.event_wait_for(&manual, time.millis(20i64)) { ret Failed }
    sync.event_set(&manual)
    if !sync.event_wait_for(&manual, time.millis(20i64)) { ret Failed }
    if !sync.event_wait_for(&manual, time.millis(20i64)) { ret Failed }
    sync.event_reset(&manual)
    if sync.event_wait_for(&manual, time.millis(20i64)) { ret Failed }
    var auto = sync.event(false, true)
    if !sync.event_wait_for(&auto, time.millis(20i64)) { ret Failed }
    if sync.event_wait_for(&auto, time.millis(20i64)) { ret Failed }

    // Once: the body runs once, and a failing body leaves it runnable.
    var counter: Counter = zero
    var o = sync.once()
    if sync.once_call[Counter](&o, &counter, bump) != ok { ret Failed }
    if sync.once_call[Counter](&o, &counter, bump) != ok { ret Failed }
    if counter.value != 1i64 { ret Failed }
    var retried: Counter = zero
    var r = sync.once()
    if sync.once_call[Counter](&r, &retried, fails) != Failed { ret Failed }
    if sync.once_call[Counter](&r, &retried, bump) != ok { ret Failed }
    if retried.value != 2i64 { ret Failed }

    // Barrier: one party is released immediately and told it was last.
    let (solo, barrier_error) = sync.barrier(a, 1u32)
    if barrier_error != ok { ret barrier_error }
    var solo_handle = solo
    if !sync.barrier_wait(&solo_handle) { ret Failed }
    if !sync.barrier_wait(&solo_handle) { ret Failed }
    sync.barrier_close(&solo_handle)
    if sync.barrier_wait(&solo_handle) { ret Failed }
    var zero_parties: sync.Barrier = zero
    let (bad, bad_error) = sync.barrier(a, 0u32)
    if bad_error != sync.Invalid { ret Failed }
    ret ok
}
