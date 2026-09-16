// A lock held as a resource (D379, H04): `sync.guard` takes the mutex and the guard
// is owed to `sync.release` on every exit, so a `defer` releases it at the block's
// end and workers that hold guards exclude each other; a failed `try_guard` is
// `Invalid` and owes nothing, as every acquiring call's err path does.
use e.mem
use e.os
use e.sync
use e.atomic

error Failed

type Counter = struct {
    lock: sync.Mutex,
    plain: i64,
    tries: Atomic[u32],
}

fn bump(c: *Counter) {
    var at = 0usize
    while at < 20000usize {
        let g = sync.guard(&c.lock)
        c.plain = c.plain + 1i64
        sync.release(g)
        at += 1usize
    }
}

fn worker(c: *Counter) {
    bump(c)
    let (g, held) = sync.try_guard(&c.lock)
    if held == ok {
        let previous = atomic.add(&c.tries, 1u32, .Relaxed)
        sync.release(g)
    }
}

fn deferred(c: *Counter, fail: bool) -> err {
    let g = sync.guard(&c.lock)
    defer sync.release(g)
    if fail { ret Failed }
    c.plain = c.plain + 1i64
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (storage, storage_error) = mem.alloc[Counter](a, 1usize)
    if storage_error != ok { ret storage_error }
    var fresh: Counter = zero
    fresh.lock = sync.mutex()
    storage[0usize] = fresh
    let c = &storage[0usize]
    let (t1, e1) = os.thread_create[Counter](worker, c, 262144usize)
    if e1 != ok { ret e1 }
    let (t2, e2) = os.thread_create[Counter](worker, c, 262144usize)
    if e2 != ok {
        let abandoned = os.thread_join(t1)
        ret e2
    }
    let j1 = os.thread_join(t1)
    let j2 = os.thread_join(t2)
    if c.plain != 40000i64 { ret Failed }
    // The lock is free after every guard: a failed `deferred` released it too.
    let failed = deferred(c, true)
    if failed != Failed { ret Failed }
    try deferred(c, false)
    if c.plain != 40001i64 { ret Failed }
    if !sync.mutex_try_lock(&c.lock) { ret Failed }
    sync.mutex_unlock(&c.lock)
    ret ok
}
