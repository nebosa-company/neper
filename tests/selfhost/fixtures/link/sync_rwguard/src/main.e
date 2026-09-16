// A read or write lock held as a resource (D433, H04): readers hold `sync.ReadGuard`s
// together, a writer holds the `sync.WriteGuard` alone, each owed to its own release
// on every exit, so a failed writer under `defer` releases too and a failed
// `try_write_guard` owes nothing.
use e.mem
use e.os
use e.sync
use e.atomic

error Failed

type Table = struct {
    lock: sync.RwLock,
    value: i64,
    reads: Atomic[u32],
}

fn reader(t: *Table) {
    var at = 0usize
    while at < 5000usize {
        let g = sync.read_guard(&t.lock)
        if t.value % 2i64 == 0i64 { let previous = atomic.add(&t.reads, 1u32, .Relaxed) }
        sync.read_release(g)
        at += 1usize
    }
}

fn writer(t: *Table) {
    var at = 0usize
    while at < 5000usize {
        let g = sync.write_guard(&t.lock)
        // Two steps under one write guard: a reader never sees the odd middle.
        t.value = t.value + 1i64
        t.value = t.value + 1i64
        sync.write_release(g)
        at += 1usize
    }
}

fn deferred(t: *Table, fail: bool) -> err {
    let g = sync.write_guard(&t.lock)
    defer sync.write_release(g)
    if fail { ret Failed }
    t.value = t.value + 2i64
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (storage, storage_error) = mem.alloc[Table](a, 1usize)
    if storage_error != ok { ret storage_error }
    var fresh: Table = zero
    fresh.lock = sync.rwlock()
    storage[0usize] = fresh
    let t = &storage[0usize]
    let (r1, e1) = os.thread_create[Table](reader, t, 262144usize)
    if e1 != ok { ret e1 }
    let (r2, e2) = os.thread_create[Table](reader, t, 262144usize)
    if e2 != ok {
        let abandoned = os.thread_join(r1)
        ret e2
    }
    let (w, e3) = os.thread_create[Table](writer, t, 262144usize)
    if e3 != ok {
        let abandoned1 = os.thread_join(r1)
        let abandoned2 = os.thread_join(r2)
        ret e3
    }
    let j1 = os.thread_join(r1)
    let j2 = os.thread_join(r2)
    let j3 = os.thread_join(w)
    if t.value != 10000i64 { ret Failed }
    // Every read saw an even value: the reads counted are the reads made.
    if atomic.load(&t.reads, .Relaxed) != 10000u32 { ret Failed }
    // The lock is free after every guard: a failed `deferred` released it too.
    let failed = deferred(t, true)
    if failed != Failed { ret Failed }
    try deferred(t, false)
    if t.value != 10002i64 { ret Failed }
    let (held, held_error) = sync.try_write_guard(&t.lock)
    if held_error != ok { ret Failed }
    // A reader cannot join while the writer holds it, and owes nothing for trying.
    let (blocked, blocked_error) = sync.try_read_guard(&t.lock)
    if blocked_error == ok {
        sync.read_release(blocked)
        sync.write_release(held)
        ret Failed
    }
    sync.write_release(held)
    let (again, again_error) = sync.try_read_guard(&t.lock)
    if again_error != ok { ret Failed }
    sync.read_release(again)
    ret ok
}
