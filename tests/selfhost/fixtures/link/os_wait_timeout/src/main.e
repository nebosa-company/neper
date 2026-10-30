// `os.wait_u32` on a word nobody changes: a word that already differs ends the wait at once, a zero
// timeout polls once, and a finite timeout sleeps for (about) that long on the real clock and
// answers `Timeout`. The second half is the same through `e.sync`'s timed forms. A wake with no
// waiter is a no-op. On wasm32-wasi (one thread) these are the cases the module can reach; a wait
// with no timeout on an unchanged word would sleep for ever and is not run.
use e.atomic
use e.mem
use e.os
use e.sync
use e.time

fn elapsed_ms(since: time.Instant) -> i64 {
    let (now, clock_error) = time.monotonic()
    if clock_error != ok { ret -1i64 }
    ret (now.nanos - since.nanos) / 1000000i64
}

fn main(a: *mem.Arena) -> err {
    var word = atomic.init(7u32)

    // The word is not what the caller expected: back at once, whatever the timeout, even none.
    if os.wait_u32(&word, 8u32, -1i64) != ok { os.exit(10i32) }
    if os.wait_u32(&word, 8u32, 0i64) != ok { os.exit(11i32) }

    // Zero polls once.
    if os.wait_u32(&word, 7u32, 0i64) != os.Timeout { os.exit(12i32) }

    // A finite timeout lasts about that long and then says so.
    let (start, start_error) = time.monotonic()
    if start_error != ok { os.exit(13i32) }
    if os.wait_u32(&word, 7u32, 60000000i64) != os.Timeout { os.exit(14i32) }
    let waited = elapsed_ms(start)
    if waited < 55i64 { os.exit(15i32) }
    if waited > 5000i64 { os.exit(16i32) }

    // A wake with nobody waiting does nothing; a changed word ends a wait that would have timed out.
    os.wake_one_u32(&word)
    os.wake_all_u32(&word)
    atomic.store(&word, 9u32, .Release)
    if os.wait_u32(&word, 7u32, 1000000000i64) != ok { os.exit(17i32) }

    // e.sync over the same call: a held mutex and a condition that nobody signals time out.
    var m = sync.mutex()
    sync.mutex_lock(&m)
    let (lock_start, lock_error) = time.monotonic()
    if lock_error != ok { os.exit(20i32) }
    if sync.mutex_lock_for(&m, time.millis(40i64)) { os.exit(21i32) }
    if elapsed_ms(lock_start) < 35i64 { os.exit(22i32) }
    var c = sync.condition()
    let (cond_start, cond_error) = time.monotonic()
    if cond_error != ok { os.exit(23i32) }
    if sync.condition_wait_for(&c, &m, time.millis(40i64)) { os.exit(24i32) }
    if elapsed_ms(cond_start) < 35i64 { os.exit(25i32) }
    sync.mutex_unlock(&m)
    ret ok
}
