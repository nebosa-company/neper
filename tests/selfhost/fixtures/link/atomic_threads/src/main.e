// The one test a single thread cannot make: whether `lock` is really on the
// instruction. Four threads each add one a hundred thousand times; a non-atomic
// read-modify-write loses updates and the total comes out short.

use e.mem
use e.os
use e.atomic

error Failed

type Shared = struct {
    total: Atomic[u64],
    plain: u64,
}

fn bump(s: *Shared) {
    var at = 0usize
    while at < 100000usize {
        let ignored = atomic.add(&s.total, 1u64, .Relaxed)
        at += 1usize
    }
}

fn main(a: *mem.Arena) -> err {
    var counters: Shared = zero
    var workers: [4]os.Thread = zero
    var started = 0usize
    while started < 4usize {
        let (worker, create_error) = os.thread_create[Shared](bump, &counters, 1048576usize)
        if create_error == os.Unsupported { ret ok }
        if create_error != ok { ret create_error }
        workers[started] = worker
        started += 1usize
    }
    var joined = 0usize
    while joined < 4usize {
        let join_error = os.thread_join(workers[joined])
        if join_error != ok { ret join_error }
        joined += 1usize
    }
    if atomic.load(&counters.total, .Acquire) != 400000u64 { ret Failed }
    ret ok
}
