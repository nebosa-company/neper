// A group of threads as one resource (D434, H04): `thread.spawn_all` starts a
// thread per context and the group is owed to `thread.join_all` on every exit,
// so an array of threads is joined as one thread is; a failed start joins what
// it started before it answers, and owes the caller nothing.
use e.mem
use e.thread
use e.atomic

error Failed

type Slot = struct { hits: Atomic[u32], id: u32 }

fn work(s: *Slot) {
    let previous = atomic.add(&s.hits, s.id, .Relaxed)
}

fn run(a: *mem.Arena, slots: []Slot, fail: bool) -> err {
    let (group, spawn_error) = thread.spawn_all[Slot](a, work, slots, 65536usize)
    if spawn_error != ok { ret spawn_error }
    defer let _ = thread.join_all(group)
    if fail { ret Failed }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (slots, slots_error) = mem.alloc[Slot](a, 8usize)
    if slots_error != ok { ret slots_error }
    var at = 0usize
    while at < 8usize {
        var fresh: Slot = zero
        fresh.id = u32(at) + 1u32
        slots[at] = fresh
        at += 1usize
    }
    try run(a, slots, false)
    // The early return joined too: every thread ran once, then once more.
    let failed = run(a, slots, true)
    if failed != Failed { ret Failed }
    at = 0usize
    while at < 8usize {
        if atomic.load(&slots[at].hits, .Relaxed) != 2u32 * (u32(at) + 1u32) { ret Failed }
        at += 1usize
    }
    // Nothing to start is a group of none, joined at no cost.
    let (empty, empty_error) = thread.spawn_all[Slot](a, work, slots[0usize..0usize], 0usize)
    if empty_error != ok { ret empty_error }
    try thread.join_all(empty)
    ret ok
}
