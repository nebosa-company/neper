// The data a lock protects as a view of its guard (D1555, H04): `sync.data_guard`
// takes the mutex with the data, and the data is reached only through
// `sync.data_of`, whose result lives no longer than the guard. Two workers that
// reach the count only that way exclude each other, and a deferred release
// survives an early return.
use e.mem
use e.os
use e.sync

error Failed

type Tally = struct { hits: i64 }

type Shared = struct { lock: sync.Mutex, tally: Tally }

fn bump(s: *Shared) {
    var at = 0usize
    while at < 20000usize {
        let g = sync.data_guard[Tally](&s.lock, &s.tally)
        if at < 20000usize {
            let t = sync.data_of[Tally](&g)
            t.hits = t.hits + 1i64
        }
        sync.data_release(g)
        at += 1usize
    }
}

fn deferred(s: *Shared, fail: bool) -> err {
    let g = sync.data_guard[Tally](&s.lock, &s.tally)
    defer sync.data_release(g)
    if fail { ret Failed }
    let t = sync.data_of[Tally](&g)
    t.hits = t.hits + 1i64
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (storage, storage_error) = mem.alloc[Shared](a, 1usize)
    if storage_error != ok { ret storage_error }
    var fresh: Shared = zero
    fresh.lock = sync.mutex()
    storage[0usize] = fresh
    let s = &storage[0usize]
    let (t1, e1) = os.thread_create[Shared](bump, s, 262144usize)
    if e1 != ok { ret e1 }
    let (t2, e2) = os.thread_create[Shared](bump, s, 262144usize)
    if e2 != ok {
        let abandoned = os.thread_join(t1)
        ret e2
    }
    let j1 = os.thread_join(t1)
    let j2 = os.thread_join(t2)
    if j1 != ok { ret j1 }
    if j2 != ok { ret j2 }
    if deferred(s, true) != Failed { ret mem.Exhausted }
    try deferred(s, false)
    if s.tally.hits != 40001i64 { os.exit(3i32) }
    // The lock is free again: a fresh guard takes it at once.
    let g = sync.data_guard[Tally](&s.lock, &s.tally)
    sync.data_release(g)
    ret ok
}
