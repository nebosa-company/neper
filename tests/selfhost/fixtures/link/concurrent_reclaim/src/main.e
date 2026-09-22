// `e.concurrent.reclaim`: the epoch scheme single-threaded against a Python replica
// (nothing freed before two advances, a pinned thread blocks the advance, Invalid
// unpinned, Full, collect); hazard pointers single-threaded (a protected node survives
// the scan, the threshold R = 2H triggers a scan, Full); then four threads over the
// lock-free list under each scheme, every pop marking the node in use while it reads
// it and the free hook counting a free of a marked node -- zero violations, every
// retired node freed exactly once, and the survivors still on the list.
use e.atomic
use e.io
use e.mem
use e.os
use e.thread
use e.concurrent.reclaim as reclaim

const THREADS: usize = 4usize
const PER: usize = 10000usize
const NODES: usize = 40000usize

type Shared = struct { l: reclaim.List, e: reclaim.Epoch, hz: reclaim.Hazards, inuse: []Atomic[u32], violations: Atomic[u64] }
type Worker = struct { s: *Shared, t: usize, retired: usize, failed: bool }

fn on_freed(ctx: *void, node: u32) {
    let s = mem.cast[*Shared](ctx)
    if atomic.load(&s.inuse[usize(node)], .SeqCst) != 0u32 { let bumped = atomic.add(&s.violations, 1u64, .Relaxed) }
}

fn read_head(l: *reclaim.List) -> u32 {
    ret reclaim.list_head(l)
}

fn ebr_worker(w: *Worker) {
    let s = w.s
    var i = 0usize
    while i < PER {
        reclaim.pin(&s.e, w.t)
        reclaim.list_push_front(&s.l, u32(w.t * PER + i))
        let h = reclaim.list_head(&s.l)
        if h != reclaim.NONE {
            let up = atomic.add(&s.inuse[usize(h)], 1u32, .SeqCst)
            let won = reclaim.list_try_pop(&s.l, h)
            let down = atomic.sub(&s.inuse[usize(h)], 1u32, .SeqCst)
            if won {
                if reclaim.retire(&s.e, w.t, h) != ok { w.failed = true }
                w.retired += 1usize
            }
        }
        if i % 64usize == 63usize { let advanced = reclaim.try_advance(&s.e, w.t) }
        reclaim.unpin(&s.e, w.t)
        i += 1usize
    }
}

fn hp_worker(w: *Worker) {
    let s = w.s
    var i = 0usize
    while i < PER {
        reclaim.list_push_front(&s.l, u32(w.t * PER + i))
        let h = reclaim.protect_validated[reclaim.List](&s.hz, w.t, 0usize, read_head, &s.l)
        if h != reclaim.NONE {
            let up = atomic.add(&s.inuse[usize(h)], 1u32, .SeqCst)
            let won = reclaim.list_try_pop(&s.l, h)
            let down = atomic.sub(&s.inuse[usize(h)], 1u32, .SeqCst)
            reclaim.clear(&s.hz, w.t, 0usize)
            if won {
                if reclaim.retire_hazard(&s.hz, w.t, h) != ok { w.failed = true }
                w.retired += 1usize
            }
        } else {
            reclaim.clear(&s.hz, w.t, 0usize)
        }
        i += 1usize
    }
}

// No free of a node marked in use (exit 100 + the count, 200 past a hundred); every
// freed node a distinct index below NODES; the survivors on the list plus the freed
// ones are all of them. Otherwise the exit code is `base` + the check that failed.
fn audit(s: *Shared, sink: *reclaim.Sink, seen: []u8, retired: usize, base: i32) {
    let bad = atomic.load(&s.violations, .SeqCst)
    if bad != 0u64 {
        if bad > 100u64 { os.exit(200i32) }
        os.exit(100i32 + i32(bad))
    }
    let freed = reclaim.freed_count(sink)
    if freed != retired || freed > sink.freed.len { os.exit(base) }
    var at = 0usize
    while at < NODES {
        seen[at] = 0u8
        at += 1usize
    }
    at = 0usize
    while at < freed {
        let node = usize(sink.freed[at])
        if node >= NODES || seen[node] != 0u8 { os.exit(base + 1i32) }
        seen[node] = 1u8
        at += 1usize
    }
    var remaining = 0usize
    var cursor = reclaim.list_head(&s.l)
    while cursor != reclaim.NONE {
        if seen[usize(cursor)] != 0u8 { os.exit(base + 2i32) }
        remaining += 1usize
        cursor = atomic.load(&s.l.next[usize(cursor)], .Relaxed)
    }
    if remaining + freed != NODES { os.exit(base + 3i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // --- 1: the epoch script.
    var local: [2]Atomic[u64] = zero
    var retired: [12]u32 = zero
    var counts: [3]Atomic[u64] = zero
    var freed: [16]u32 = zero
    let (bad_threads, e1) = reclaim.epoch(local[0..], retired[0..], counts[0..], freed[0..], 0usize)
    if e1 != reclaim.Invalid { os.exit(1i32) }
    let (too_small, e2) = reclaim.epoch(local[0..], retired[0..], counts[0..], freed[0..], 3usize)
    if e2 != reclaim.TooSmall { os.exit(2i32) }
    let (ep0, e3) = reclaim.epoch(local[0..], retired[0..], counts[0..], freed[0..], 2usize)
    if e3 != ok || ep0.bucket_cap != 4usize { os.exit(3i32) }
    var ep = ep0
    reclaim.pin(&ep, 0usize)
    if reclaim.retire(&ep, 0usize, 10u32) != ok || reclaim.retire(&ep, 0usize, 11u32) != ok { os.exit(4i32) }
    reclaim.unpin(&ep, 0usize)
    if !reclaim.try_advance(&ep, 0usize) || reclaim.global_epoch(&ep) != 1u64 || reclaim.freed_count(&ep.sink) != 0usize { os.exit(5i32) }
    reclaim.pin(&ep, 1usize)
    if reclaim.retire(&ep, 1usize, 20u32) != ok { os.exit(6i32) }
    if !reclaim.try_advance(&ep, 0usize) || reclaim.global_epoch(&ep) != 2u64 { os.exit(7i32) }
    if reclaim.freed_count(&ep.sink) != 2usize || freed[0] != 10u32 || freed[1] != 11u32 { os.exit(8i32) }
    if reclaim.try_advance(&ep, 0usize) || reclaim.global_epoch(&ep) != 2u64 || reclaim.freed_count(&ep.sink) != 2usize { os.exit(9i32) }
    reclaim.unpin(&ep, 1usize)
    if !reclaim.try_advance(&ep, 0usize) || reclaim.global_epoch(&ep) != 3u64 { os.exit(10i32) }
    if reclaim.freed_count(&ep.sink) != 3usize || freed[2] != 20u32 { os.exit(11i32) }
    if reclaim.retire(&ep, 0usize, 30u32) != reclaim.Invalid { os.exit(12i32) }
    reclaim.pin(&ep, 0usize)
    var k = 0u32
    while k < 4u32 {
        if reclaim.retire(&ep, 0usize, 40u32 + k) != ok { os.exit(13i32) }
        k += 1u32
    }
    if reclaim.retire(&ep, 0usize, 44u32) != reclaim.Full { os.exit(14i32) }
    reclaim.unpin(&ep, 0usize)
    if reclaim.collect(&ep, 0usize) != 7usize || reclaim.global_epoch(&ep) != 6u64 { os.exit(15i32) }
    if freed[3] != 40u32 || freed[4] != 41u32 || freed[5] != 42u32 || freed[6] != 43u32 { os.exit(16i32) }
    // --- 2: hazard pointers, single-threaded. threads=2, k=2: H=4, R=8.
    var slots: [4]Atomic[u32] = zero
    var hretired: [20]u32 = zero
    var hcounts: [2]usize = zero
    var hfreed: [16]u32 = zero
    let (no_k, e4) = reclaim.hazards(slots[0..], hretired[0..], hcounts[0..], hfreed[0..], 2usize, 0usize)
    if e4 != reclaim.Invalid { os.exit(17i32) }
    let (few_slots, e5) = reclaim.hazards(slots[0..], hretired[0..], hcounts[0..], hfreed[0..], 2usize, 3usize)
    if e5 != reclaim.TooSmall { os.exit(18i32) }
    let (h0, e6) = reclaim.hazards(slots[0..], hretired[0..], hcounts[0..], hfreed[0..], 2usize, 2usize)
    if e6 != ok || h0.threshold != 8usize || h0.retire_cap != 10usize { os.exit(19i32) }
    var h = h0
    reclaim.protect(&h, 0usize, 0usize, 5u32)
    if reclaim.retire_hazard(&h, 0usize, 5u32) != ok || reclaim.retire_hazard(&h, 0usize, 6u32) != ok { os.exit(20i32) }
    if reclaim.scan(&h, 0usize) != 1usize || hfreed[0] != 6u32 || h.retired_count[0] != 1usize { os.exit(21i32) }
    if !reclaim.is_protected(&h, 5u32) || reclaim.is_protected(&h, 6u32) { os.exit(22i32) }
    reclaim.clear(&h, 0usize, 0usize)
    if reclaim.is_protected(&h, 5u32) { os.exit(23i32) }
    if reclaim.scan(&h, 0usize) != 1usize || hfreed[1] != 5u32 || h.retired_count[0] != 0usize { os.exit(24i32) }
    k = 0u32
    while k < 8u32 {
        if reclaim.retire_hazard(&h, 1usize, 100u32 + k) != ok { os.exit(25i32) }
        k += 1u32
    }
    if h.retired_count[1] != 8usize || reclaim.freed_count(&h.sink) != 2usize { os.exit(26i32) }
    if reclaim.retire_hazard(&h, 1usize, 108u32) != ok { os.exit(27i32) }
    if h.retired_count[1] != 0usize || reclaim.freed_count(&h.sink) != 11usize { os.exit(28i32) }
    var tiny: [6]u32 = zero
    let (h3, e7) = reclaim.hazards(slots[0..], tiny[0..], hcounts[0..], hfreed[0..], 2usize, 2usize)
    if e7 != ok || h3.retire_cap != 3usize { os.exit(29i32) }
    var hz3 = h3
    k = 0u32
    while k < 3u32 {
        if reclaim.retire_hazard(&hz3, 0usize, k) != ok { os.exit(30i32) }
        k += 1u32
    }
    if reclaim.retire_hazard(&hz3, 0usize, 3u32) != reclaim.Full { os.exit(31i32) }
    // --- 3: four threads over the list under epochs.
    let (next_store, m1) = mem.alloc[Atomic[u32]](a, NODES)
    if m1 != ok { ret m1 }
    let (inuse, m2) = mem.alloc[Atomic[u32]](a, NODES)
    if m2 != ok { ret m2 }
    let (big_retired, m3) = mem.alloc[u32](a, 3usize * NODES)
    if m3 != ok { ret m3 }
    let (big_freed, m4) = mem.alloc[u32](a, NODES)
    if m4 != ok { ret m4 }
    let (seen, m5) = mem.alloc[u8](a, NODES)
    if m5 != ok { ret m5 }
    var locals: [4]Atomic[u64] = zero
    var big_counts: [3]Atomic[u64] = zero
    var sh: Shared = zero
    sh.l = reclaim.list(next_store)
    sh.inuse = inuse
    var z = 0usize
    while z < NODES {
        atomic.store(&inuse[z], 0u32, .Relaxed)
        z += 1usize
    }
    let (big_epoch, e8) = reclaim.epoch(locals[0..], big_retired, big_counts[0..], big_freed, THREADS)
    if e8 != ok { os.exit(32i32) }
    sh.e = big_epoch
    reclaim.on_free(&sh.e.sink, on_freed, mem.cast[*void](&sh))
    var workers: [4]Worker = zero
    var handles: [4]os.Thread = zero
    var t = 0usize
    while t < THREADS {
        workers[t] = Worker { s: &sh, t: t, retired: 0usize, failed: false }
        t += 1usize
    }
    t = 0usize
    while t < THREADS {
        let (started, spawn_error) = thread.spawn[Worker](ebr_worker, &workers[t], 0usize)
        if spawn_error == os.Unsupported {
            try io.print("concurrent reclaim ok\n")
            ret ok
        }
        if spawn_error != ok { os.exit(33i32) }
        handles[t] = started
        t += 1usize
    }
    t = 0usize
    var total_retired = 0usize
    while t < THREADS {
        if thread.join(handles[t]) != ok { os.exit(34i32) }
        if workers[t].failed { os.exit(35i32) }
        total_retired += workers[t].retired
        t += 1usize
    }
    let drained = reclaim.collect(&sh.e, 0usize)
    audit(&sh, &sh.e.sink, seen, total_retired, 40i32)
    // --- 4: the same under hazard pointers, one slot per thread.
    var hslots: [4]Atomic[u32] = zero
    var hcount4: [4]usize = zero
    let (hp_retired, m6) = mem.alloc[u32](a, THREADS * 64usize)
    if m6 != ok { ret m6 }
    let (hp_freed, m7) = mem.alloc[u32](a, NODES)
    if m7 != ok { ret m7 }
    sh.l = reclaim.list(next_store)
    let (big_hz, e9) = reclaim.hazards(hslots[0..], hp_retired, hcount4[0..], hp_freed, THREADS, 1usize)
    if e9 != ok { os.exit(50i32) }
    sh.hz = big_hz
    reclaim.on_free(&sh.hz.sink, on_freed, mem.cast[*void](&sh))
    t = 0usize
    while t < THREADS {
        workers[t] = Worker { s: &sh, t: t, retired: 0usize, failed: false }
        let (started, spawn_error) = thread.spawn[Worker](hp_worker, &workers[t], 0usize)
        if spawn_error != ok { os.exit(51i32) }
        handles[t] = started
        t += 1usize
    }
    t = 0usize
    total_retired = 0usize
    while t < THREADS {
        if thread.join(handles[t]) != ok { os.exit(52i32) }
        if workers[t].failed { os.exit(53i32) }
        total_retired += workers[t].retired
        t += 1usize
    }
    t = 0usize
    while t < THREADS {
        let swept = reclaim.scan(&sh.hz, t)
        if sh.hz.retired_count[t] != 0usize { os.exit(54i32) }
        t += 1usize
    }
    audit(&sh, &sh.hz.sink, seen, total_retired, 60i32)
    try io.print("concurrent reclaim ok\n")
    ret ok
}
