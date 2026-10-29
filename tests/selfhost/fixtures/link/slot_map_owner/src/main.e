// Generation-tagged handles with their owner (D1560, H02): a key answers only in the
// map that issued it, only while its slot holds the value it was issued for. A key
// from another map, a key after `remove` or `clear`, and a key from a map whose arena
// was reset and whose storage a new map reuses all answer nothing.
use e.mem
use e.os
use e.atomic
use e.sync
use e.data.slot_map

error Failed

const PARALLEL_WORKERS: usize = 8usize
const PARALLEL_ROUNDS: usize = 64usize

type ParallelControl = struct {
    start: sync.Event,
    run: Atomic[u32],
    gate: sync.Barrier,
}

type ParallelWorker = struct {
    control: *ParallelControl,
    storage: [512]u8,
    keys: [64]slot_map.Key,
    map: slot_map.SlotMap[i64],
    failed: Atomic[u32],
}

// Every worker owns its arena, so the only shared state here is slot_map's owner
// allocator. The two barriers make each map creation a concurrent wave.
fn initialize_parallel(w: *ParallelWorker) {
    sync.event_wait(&w.control.start)
    if atomic.load(&w.control.run, .Acquire) == 0u32 { ret }
    var round = 0usize
    while round < PARALLEL_ROUNDS {
        let _ = sync.barrier_wait(&w.control.gate)
        var private_arena = mem.arena_from(w.storage[..])
        let (made, init_error) = slot_map.init[i64](&private_arena, 1usize)
        if init_error != ok {
            atomic.store(&w.failed, 1u32, .Release)
        } else {
            w.map = made
            let (key, insert_error) = slot_map.insert[i64](&w.map, 10i64)
            if insert_error != ok {
                atomic.store(&w.failed, 1u32, .Release)
            } else {
                w.keys[round] = key
            }
        }
        let _ = sync.barrier_wait(&w.control.gate)
        round += 1usize
    }
}

fn join_workers(workers: []os.Thread, count: usize) -> err {
    var at = 0usize
    while at < count {
        let join_error = os.thread_join(workers[at])
        if join_error != ok { ret join_error }
        at += 1usize
    }
    ret ok
}

fn check_parallel_owners(a: *mem.Arena) -> err {
    var control: ParallelControl = zero
    control.start = sync.event(true, false)
    let (gate, gate_error) = sync.barrier(a, u32(PARALLEL_WORKERS))
    if gate_error != ok { ret gate_error }
    control.gate = gate
    var workers: [8]ParallelWorker = zero
    var threads: [8]os.Thread = zero
    var started = 0usize
    while started < PARALLEL_WORKERS {
        workers[started].control = &control
        let (thread, create_error) = os.thread_create[ParallelWorker](initialize_parallel, &workers[started], 1048576usize)
        if create_error != ok {
            atomic.store(&control.run, 0u32, .Release)
            sync.event_set(&control.start)
            let joined = join_workers(threads[..], started)
            if joined != ok { ret joined }
            if create_error == os.Unsupported { ret ok }
            ret create_error
        }
        threads[started] = thread
        started += 1usize
    }
    atomic.store(&control.run, 1u32, .Release)
    sync.event_set(&control.start)
    try join_workers(threads[..], PARALLEL_WORKERS)

    var first_worker = 0usize
    while first_worker < PARALLEL_WORKERS {
        if atomic.load(&workers[first_worker].failed, .Acquire) != 0u32 { ret Failed }
        var first_round = 0usize
        while first_round < PARALLEL_ROUNDS {
            let first_key = workers[first_worker].keys[first_round]
            if first_key.owner == 0u32 || first_key.slot != 0u32 || first_key.generation != 0u32 { ret Failed }
            var second_worker = first_worker
            var second_round = first_round + 1usize
            while second_worker < PARALLEL_WORKERS {
                while second_round < PARALLEL_ROUNDS {
                    let second_key = workers[second_worker].keys[second_round]
                    if first_key.owner == second_key.owner { ret Failed }
                    second_round += 1usize
                }
                second_worker += 1usize
                second_round = 0usize
            }
            first_round += 1usize
        }
        first_worker += 1usize
    }

    // Last-round maps all hold their one value in slot 0 at generation 0. Their owners
    // are therefore the only reason a key from a different map cannot be accepted.
    var map_index = 0usize
    while map_index < PARALLEL_WORKERS {
        let key = workers[map_index].keys[PARALLEL_ROUNDS - 1usize]
        var other_index = 0usize
        while other_index < PARALLEL_WORKERS {
            if other_index != map_index {
                let (_, crossed) = slot_map.get[i64](&workers[other_index].map, key)
                if crossed { ret Failed }
            }
            other_index += 1usize
        }
        map_index += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (first_map, first_error) = slot_map.init[i64](a, 4usize)
    if first_error != ok { ret first_error }
    var first = first_map
    let (second_map, second_error) = slot_map.init[i64](a, 4usize)
    if second_error != ok { ret second_error }
    var second = second_map
    let (k1, e1) = slot_map.insert[i64](&first, 11i64)
    let (k2, e2) = slot_map.insert[i64](&second, 22i64)
    if e1 != ok || e2 != ok { os.exit(2i32) }
    // Same slot and generation in both maps; only the owner tells them apart.
    if k1.slot != k2.slot || k1.generation != k2.generation || k1.owner == k2.owner { os.exit(3i32) }
    let (v1, h1) = slot_map.get[i64](&first, k1)
    let (_, crossed) = slot_map.get[i64](&second, k1)
    if !h1 || *v1 != 11i64 || crossed { os.exit(4i32) }
    let (removed, was) = slot_map.remove[i64](&first, k1)
    let (_, stale) = slot_map.get[i64](&first, k1)
    if !was || removed != 11i64 || stale { os.exit(5i32) }
    slot_map.clear[i64](&second)
    let (_, cleared) = slot_map.get[i64](&second, k2)
    if cleared { os.exit(6i32) }
    // A map made after a reset reuses the storage a key's map had.
    let mark = mem.mark(a)
    let (old_map, old_error) = slot_map.init[i64](a, 2usize)
    if old_error != ok { os.exit(7i32) }
    var old = old_map
    let (old_key, old_insert) = slot_map.insert[i64](&old, 5i64)
    if old_insert != ok { os.exit(7i32) }
    mem.reset(a, mark)
    let (new_map, new_error) = slot_map.init[i64](a, 2usize)
    if new_error != ok { os.exit(8i32) }
    var fresh = new_map
    let (new_key, new_insert) = slot_map.insert[i64](&fresh, 6i64)
    if new_insert != ok || new_key.slot != old_key.slot || new_key.generation != old_key.generation { os.exit(9i32) }
    let (_, reused) = slot_map.get[i64](&fresh, old_key)
    if reused { os.exit(10i32) }
    try check_parallel_owners(a)
    ret ok
}
