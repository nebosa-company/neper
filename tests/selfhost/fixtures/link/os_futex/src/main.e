// `os.wait_u32` / `wake_one_u32` / `wake_all_u32`, section 8's blocking primitives.
// Linux calls futex(2) directly; Windows resolves `WaitOnAddress` through KernelBase,
// because it is not in kernel32 and this linker emits one import descriptor.
//
// The three cheap cases are checked first because each is a separate way to hang: a
// value that already differs must return at once, a timeout must fire, and zero must
// poll. Only then does a real wake get tested, where a bug costs the suite a deadlock
// rather than a failure.
use e.mem
use e.os
use e.atomic

error Failed

type Shared = struct {
    flag: Atomic[u32],
    seen: Atomic[u32],
}

fn waiter(s: *Shared) {
    // Recheck after every wake: the fence promises spurious ones.
    while atomic.load(&s.flag, .Acquire) == 0u32 {
        let ignored = os.wait_u32(&s.flag, 0u32, -1i64)
    }
    let bumped = atomic.add(&s.seen, 1u32, .Release)
}

fn main(a: *mem.Arena) -> err {
    // A value that already differs returns at once, not after the timeout.
    var s: Shared = zero
    atomic.store(&s.flag, 7u32, .Release)
    let immediate = os.wait_u32(&s.flag, 0u32, -1i64)
    if immediate != ok { ret immediate }

    // A timeout fires rather than blocking forever.
    atomic.store(&s.flag, 0u32, .Release)
    let timed = os.wait_u32(&s.flag, 0u32, 20000000i64)
    if timed != os.Timeout { ret Failed }

    // Zero polls once.
    let polled = os.wait_u32(&s.flag, 0u32, 0i64)
    if polled != os.Timeout { ret Failed }

    // And a real wake releases three blocked threads.
    var workers: [3]os.Thread = zero
    var started = 0usize
    while started < 3usize {
        let (worker, create_error) = os.thread_create[Shared](waiter, &s, 1048576usize)
        if create_error == os.Unsupported { ret ok }
        if create_error != ok { ret create_error }
        workers[started] = worker
        started += 1usize
    }
    atomic.store(&s.flag, 1u32, .Release)
    os.wake_all_u32(&s.flag)
    var joined = 0usize
    while joined < 3usize {
        let join_error = os.thread_join(workers[joined])
        if join_error != ok { ret join_error }
        joined += 1usize
    }
    if atomic.load(&s.seen, .Acquire) != 3u32 { ret Failed }
    ret ok
}
