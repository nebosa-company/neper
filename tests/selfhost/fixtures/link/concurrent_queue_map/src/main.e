// `e.concurrent.queue` and `e.concurrent.map`: the queue single-threaded through its
// try forms, len and capacity; a producer thread pushing 200 items through a queue of
// four while the main thread pops them all with blocking pops; the timed forms timing
// out on an empty and a full queue; close draining what is buffered and then Closed
// for everything. The map single-threaded through put, get, replace, remove, len, Full
// and Closed; then two threads putting 400 distinct keys each into sixteen shards
// while the main thread reads. Every check has its own exit code.
use e.os
use e.atomic
use e.mem
use e.str
use e.sync
use e.time
use e.thread
use e.concurrent.queue as queue
use e.concurrent.map as cmap

type Producer = struct { q: queue.Queue[u64], base: u64, count: u64, failed: bool }

fn produce(p: *Producer) {
    var i = 0u64
    while i < p.count {
        if queue.push[u64](&p.q, p.base + i) != ok { p.failed = true }
        i += 1u64
    }
}

type Filler = struct { m: cmap.Map[u64, u64], base: u64, count: u64, failed: bool }

// The getter pauses inside its hash protocol after map.get has joined the map's
// admission generation. This makes close's wait observable without scheduling luck.
type CloseControl = struct { entered: sync.Event, release: sync.Event }
type BlockingKey = struct { id: u64, control: *CloseControl, block: bool }
type BlockingGet = struct { map: cmap.Map[BlockingKey, u64], key: BlockingKey, value: u64, found: bool, failure: err }
type MapCloser = struct { map: cmap.Map[BlockingKey, u64], started: sync.Event, finished: Atomic[u32], failure: err }
const CLOSE_PENDING: u32 = 2147483648u32
const ACTIVE_OPERATIONS: u32 = 2147483647u32

fn blocking_key_hash(key: BlockingKey) -> u64 {
    if key.block {
        sync.event_set(&key.control.entered)
        sync.event_wait(&key.control.release)
    }
    ret key.id
}

fn blocking_key_eq(a: BlockingKey, b: BlockingKey) -> bool { ret a.id == b.id }

fn run_blocking_get(w: *BlockingGet) {
    let (value, found, failure) = cmap.get[BlockingKey, u64](&w.map, w.key)
    w.value = value
    w.found = found
    w.failure = failure
}

fn run_map_close(w: *MapCloser) {
    sync.event_set(&w.started)
    w.failure = cmap.close[BlockingKey, u64](&w.map)
    atomic.store(&w.finished, 1u32, .Release)
}

fn close_state(s: *cmap.State[BlockingKey, u64]) -> (bool, usize) {
    let phase = atomic.load(&s.admission, .Acquire)
    ret ((phase & CLOSE_PENDING) != 0u32, usize(phase & ACTIVE_OPERATIONS))
}

fn fill(f: *Filler) {
    var i = 0u64
    while i < f.count {
        let (fresh, put_error) = cmap.put[u64, u64](&f.m, f.base + i, (f.base + i) * 2u64)
        if put_error != ok || !fresh { f.failed = true }
        i += 1u64
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // --- The queue, single-threaded.
    let (none, e1) = queue.init[u64](a, 0usize)
    if e1 != queue.Invalid { os.exit(1) }
    let (q0, e2) = queue.init[u64](a, 4usize)
    if e2 != ok { os.exit(2) }
    var q = q0
    if queue.capacity[u64](&q) != 4usize || queue.len[u64](&q) != 0usize { os.exit(3) }
    var i = 0u64
    while i < 4u64 {
        let (pushed, push_error) = queue.try_push[u64](&q, i + 10u64)
        if push_error != ok || !pushed { os.exit(4) }
        i += 1u64
    }
    let (overflow, e3) = queue.try_push[u64](&q, 99u64)
    if e3 != ok || overflow { os.exit(5) }
    if queue.len[u64](&q) != 4usize { os.exit(6) }
    let (full_timeout, e4) = queue.push_for[u64](&q, 99u64, time.Duration { nanos: 20000000i64 })
    if e4 != ok || full_timeout { os.exit(7) }
    let (first, got_first, e5) = queue.try_pop[u64](&q)
    if e5 != ok || !got_first || first != 10u64 { os.exit(8) }
    let (second, e6) = queue.pop[u64](&q)
    if e6 != ok || second != 11u64 { os.exit(9) }
    let (third, got_third, e7) = queue.pop_for[u64](&q, time.Duration { nanos: 20000000i64 })
    if e7 != ok || !got_third || third != 12u64 { os.exit(10) }
    let (fourth, got_fourth, e8) = queue.try_pop[u64](&q)
    if e8 != ok || !got_fourth || fourth != 13u64 { os.exit(11) }
    let (empty, got_empty, e9) = queue.try_pop[u64](&q)
    if e9 != ok || got_empty { os.exit(12) }
    let (empty_timeout, got_timeout, e10) = queue.pop_for[u64](&q, time.Duration { nanos: 20000000i64 })
    if e10 != ok || got_timeout { os.exit(13) }
    // --- A producer thread through the small queue.
    var producer = Producer { q: q, base: 1000u64, count: 200u64, failed: false }
    let (worker, e11) = thread.spawn[Producer](produce, &producer, 0usize)
    if e11 != ok { os.exit(14) }
    var sum = 0u64
    i = 0u64
    while i < 200u64 {
        let (value, pop_error) = queue.pop[u64](&q)
        if pop_error != ok { os.exit(15) }
        sum += value
        i += 1u64
    }
    // The join is its own statement (D365): what the thread was lent is read after it.
    let joined = thread.join(worker)
    if joined != ok || producer.failed { os.exit(16) }
    if sum != 200u64 * 1000u64 + 199u64 * 200u64 / 2u64 { os.exit(17) }
    // --- Close: the buffered item comes out, then Closed.
    let (pushed_last, e12) = queue.try_push[u64](&q, 7u64)
    if e12 != ok || !pushed_last { os.exit(18) }
    if queue.close[u64](&q) != ok { os.exit(19) }
    if queue.close[u64](&q) != queue.Closed { os.exit(20) }
    let (refused, e13) = queue.try_push[u64](&q, 8u64)
    if e13 != queue.Closed { os.exit(21) }
    if queue.push[u64](&q, 8u64) != queue.Closed { os.exit(22) }
    let (last, e14) = queue.pop[u64](&q)
    if e14 != ok || last != 7u64 { os.exit(23) }
    let (after, e15) = queue.pop[u64](&q)
    if e15 != queue.Closed { os.exit(24) }
    let (after_try, got_after, e16) = queue.try_pop[u64](&q)
    if e16 != queue.Closed { os.exit(25) }
    let (after_for, got_after_for, e17) = queue.pop_for[u64](&q, time.Duration { nanos: 1000i64 })
    if e17 != queue.Closed { os.exit(26) }
    // --- The map, single-threaded.
    let (no_map, e18) = cmap.init[u64, u64](a, 0usize, 4u16)
    if e18 != cmap.Invalid { os.exit(27) }
    let (no_shards, e19) = cmap.init[u64, u64](a, 8usize, 0u16)
    if e19 != cmap.Invalid { os.exit(28) }
    // Capacity is an aggregate bound even when it cannot divide among shards.
    let (limited0, e38) = cmap.init[u64, u64](a, 1usize, 2u16)
    if e38 != ok { os.exit(53) }
    var limited = limited0
    let (first_limited, e39) = cmap.put[u64, u64](&limited, 1u64, 10u64)
    if e39 != ok || !first_limited { os.exit(54) }
    let (second_limited, e40) = cmap.put[u64, u64](&limited, 2u64, 20u64)
    if e40 != cmap.Full || second_limited { os.exit(55) }
    let (limited_count, e41) = cmap.len[u64, u64](&limited)
    if e41 != ok || limited_count != 1usize { os.exit(56) }
    let (m0, e20) = cmap.init[u64, u64](a, 8usize, 1u16)
    if e20 != ok { os.exit(29) }
    var m = m0
    let (fresh1, e21) = cmap.put[u64, u64](&m, 1u64, 100u64)
    if e21 != ok || !fresh1 { os.exit(30) }
    let (fresh2, e22) = cmap.put[u64, u64](&m, 1u64, 101u64)
    if e22 != ok || fresh2 { os.exit(31) }
    let (v1, has1, e23) = cmap.get[u64, u64](&m, 1u64)
    if e23 != ok || !has1 || v1 != 101u64 { os.exit(32) }
    let (v2, has2, e24) = cmap.get[u64, u64](&m, 2u64)
    if e24 != ok || has2 { os.exit(33) }
    i = 2u64
    while i <= 8u64 {
        let (fresh, put_error) = cmap.put[u64, u64](&m, i, i * 10u64)
        if put_error != ok || !fresh { os.exit(34) }
        i += 1u64
    }
    let (count1, e25) = cmap.len[u64, u64](&m)
    if e25 != ok || count1 != 8usize { os.exit(35) }
    let (over, e26) = cmap.put[u64, u64](&m, 9u64, 90u64)
    if e26 != cmap.Full { os.exit(36) }
    let (replaced, e27) = cmap.put[u64, u64](&m, 8u64, 81u64)
    if e27 != ok || replaced { os.exit(37) }
    let (removed, was_there, e28) = cmap.remove[u64, u64](&m, 3u64)
    if e28 != ok || !was_there || removed != 30u64 { os.exit(38) }
    let (gone, still, e29) = cmap.get[u64, u64](&m, 3u64)
    if e29 != ok || still { os.exit(39) }
    let (again, e30) = cmap.put[u64, u64](&m, 9u64, 90u64)
    if e30 != ok || !again { os.exit(40) }
    let (count2, e31) = cmap.len[u64, u64](&m)
    if e31 != ok || count2 != 8usize { os.exit(41) }
    if cmap.close[u64, u64](&m) != ok || cmap.close[u64, u64](&m) != cmap.Closed { os.exit(42) }
    let (v3, has3, e32) = cmap.get[u64, u64](&m, 1u64)
    if e32 != cmap.Closed { os.exit(43) }
    let (count3, e33) = cmap.len[u64, u64](&m)
    if e33 != cmap.Closed { os.exit(44) }
    // --- Two threads filling a sharded map while the main thread reads.
    let (big0, e34) = cmap.init[u64, u64](a, 2000usize, 16u16)
    if e34 != ok { os.exit(45) }
    var big = big0
    var left = Filler { m: big, base: 0u64, count: 400u64, failed: false }
    var right = Filler { m: big, base: 100000u64, count: 400u64, failed: false }
    let (t1, e35) = thread.spawn[Filler](fill, &left, 0usize)
    if e35 != ok { os.exit(46) }
    let (t2, e36) = thread.spawn[Filler](fill, &right, 0usize)
    if e36 != ok { os.exit(47) }
    var reads = 0usize
    while reads < 1000usize {
        let (seen, has, read_error) = cmap.get[u64, u64](&big, 5u64)
        if read_error != ok || (has && seen != 10u64) { os.exit(48) }
        reads += 1usize
    }
    if thread.join(t1) != ok || thread.join(t2) != ok { os.exit(49) }
    if left.failed || right.failed { os.exit(50) }
    let (total, e37) = cmap.len[u64, u64](&big)
    if e37 != ok || total != 800usize { os.exit(51) }
    i = 0u64
    while i < 400u64 {
        let (lv, lh, le) = cmap.get[u64, u64](&big, i)
        let (rv, rh, re) = cmap.get[u64, u64](&big, 100000u64 + i)
        if le != ok || re != ok || !lh || !rh || lv != i * 2u64 || rv != (100000u64 + i) * 2u64 { os.exit(52) }
        i += 1u64
    }
    // --- Close waits for an admitted operation before publishing Closed.
    var control: CloseControl = zero
    control.entered = sync.event(true, false)
    control.release = sync.event(true, false)
    let (blocked0, blocked_error) = cmap.init[BlockingKey, u64](a, 1usize, 1u16)
    if blocked_error != ok { os.exit(57i32) }
    var blocked = blocked0
    let stored_key = BlockingKey { id: 77u64, control: nil, block: false }
    let (stored, store_error) = cmap.put[BlockingKey, u64](&blocked, stored_key, 900u64)
    if store_error != ok || !stored { os.exit(58i32) }
    var getter: BlockingGet = zero
    getter.map = blocked
    getter.key = BlockingKey { id: 77u64, control: &control, block: true }
    let (getter_thread, getter_spawn_error) = thread.spawn[BlockingGet](run_blocking_get, &getter, 0usize)
    if getter_spawn_error == os.Unsupported { ret ok }
    if getter_spawn_error != ok { os.exit(59i32) }
    sync.event_wait(&control.entered)
    var closer: MapCloser = zero
    closer.map = blocked
    closer.started = sync.event(true, false)
    let (closer_thread, closer_spawn_error) = thread.spawn[MapCloser](run_map_close, &closer, 0usize)
    if closer_spawn_error != ok {
        sync.event_set(&control.release)
        let joined_getter = thread.join(getter_thread)
        if closer_spawn_error == os.Unsupported { ret ok }
        os.exit(60i32)
    }
    sync.event_wait(&closer.started)
    var waiting = false
    while !waiting {
        let (closing, active) = close_state(mem.cast[*cmap.State[BlockingKey, u64]](blocked.state))
        if closing {
            if active != 1usize {
                sync.event_set(&control.release)
                let joined_getter = thread.join(getter_thread)
                let joined_closer = thread.join(closer_thread)
                os.exit(61i32)
            }
            waiting = true
        }
    }
    if atomic.load(&closer.finished, .Acquire) != 0u32 {
        sync.event_set(&control.release)
        let joined_getter = thread.join(getter_thread)
        let joined_closer = thread.join(closer_thread)
        os.exit(62i32)
    }
    sync.event_set(&control.release)
    if thread.join(getter_thread) != ok || thread.join(closer_thread) != ok { os.exit(63i32) }
    if getter.failure != ok || !getter.found || getter.value != 900u64 { os.exit(64i32) }
    if closer.failure != ok || atomic.load(&closer.finished, .Acquire) != 1u32 { os.exit(65i32) }
    let (_, _, after_close_error) = cmap.get[BlockingKey, u64](&blocked, stored_key)
    if after_close_error != cmap.Closed { os.exit(66i32) }
    ret ok
}
