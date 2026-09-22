// `e.concurrent.deque` and `e.concurrent.stack`. The deque single-threaded: LIFO
// for the owner, an LCG script of push/pop/steal folded against a Python replica,
// `Full` and `Invalid`; then the main thread as owner pushing 20000 items and popping
// every third while three thieves steal until the owner is done and the deque is
// drained -- every item taken exactly once, by sum and by count. The stack
// single-threaded: LIFO, `Full`, `len`, `is_empty`; then four threads each pushing
// 5000 distinct values and popping until empty, with a bitmap marked by the popper
// and checked after the joins. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.thread
use e.atomic
use e.concurrent.deque as deque
use e.concurrent.stack as stack

type Shared = struct { d: deque.Deque[u64], done: Atomic[u32] }
type Thief = struct { s: *Shared, sum: u64, count: u64 }

fn thieve(t: *Thief) {
    var finished = false
    while true {
        let (v, outcome) = deque.steal[u64](&t.s.d)
        if outcome == .Stolen {
            t.sum +%= v
            t.count += 1u64
            continue
        }
        if outcome == .Retry { continue }
        if finished { ret }
        finished = atomic.load(&t.s.done, .Acquire) == 1u32
    }
}

type Pool = struct { st: stack.Stack, seen: []u8 }
type Pusher = struct { p: *Pool, base: u64, popped: u64, failed: bool }

fn push_then_pop(w: *Pusher) {
    var i = 0u64
    while i < 5000u64 {
        if stack.push(&w.p.st, w.base + i) != ok { w.failed = true }
        i += 1u64
    }
    while true {
        let (v, got) = stack.pop(&w.p.st)
        if !got { ret }
        w.p.seen[usize(v)] += 1u8
        w.popped += 1u64
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // --- 1: the deque, single-threaded.
    var small: [4]u64 = zero
    var twelve: [12]u64 = zero
    var big: [16]u64 = zero
    let (bad, e1) = deque.deque[u64](twelve[..])
    if e1 != deque.Invalid { os.exit(1i32) }
    let (bad0, e2) = deque.deque[u64](big[..0usize])
    if e2 != deque.Invalid { os.exit(2i32) }
    let (d0, e3) = deque.deque[u64](big[..])
    if e3 != ok { os.exit(3i32) }
    var d = d0
    if deque.capacity[u64](&d) != 16usize || deque.len[u64](&d) != 0usize { os.exit(4i32) }
    var i = 1u64
    while i <= 10u64 {
        if deque.push[u64](&d, i) != ok { os.exit(5i32) }
        i += 1u64
    }
    if deque.len[u64](&d) != 10usize { os.exit(6i32) }
    i = 10u64
    while i >= 1u64 {
        let (v, got) = deque.pop[u64](&d)
        if !got || v != i { os.exit(7i32) }
        i -= 1u64
    }
    let (nothing, got_nothing) = deque.pop[u64](&d)
    if got_nothing || deque.len[u64](&d) != 0usize { os.exit(8i32) }
    let (nothing2, outcome0) = deque.steal[u64](&d)
    if outcome0 != .Empty { os.exit(9i32) }
    // Full: sixteen in, the seventeenth refused, and the deque intact.
    i = 0u64
    while i < 16u64 {
        if deque.push[u64](&d, 100u64 + i) != ok { os.exit(10i32) }
        i += 1u64
    }
    if deque.push[u64](&d, 999u64) != deque.Full { os.exit(11i32) }
    if deque.len[u64](&d) != 16usize { os.exit(12i32) }
    let (oldest, outcome1) = deque.steal[u64](&d)
    if outcome1 != .Stolen || oldest != 100u64 { os.exit(13i32) }
    let (newest, got_newest) = deque.pop[u64](&d)
    if !got_newest || newest != 115u64 { os.exit(14i32) }
    // The LCG script over a deque of four, folded as the Python replica folds it.
    let (s0, e4) = deque.deque[u64](small[..])
    if e4 != ok { os.exit(15i32) }
    var sd = s0
    var state = 12345u64
    var fold = 0u64
    var fulls = 0u64
    var step = 0usize
    while step < 240usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r = state >> 33u32
        let op = r % 3u64
        if op == 0u64 {
            let pushed = deque.push[u64](&sd, r)
            if pushed == deque.Full {
                fold +%= 7u64
                fulls += 1u64
            } else if pushed != ok {
                os.exit(16i32)
            }
        } else if op == 1u64 {
            let (v, got) = deque.pop[u64](&sd)
            if got {
                fold = fold *% 31u64 +% v
            } else {
                fold +%= 1u64
            }
        } else {
            let (v, outcome) = deque.steal[u64](&sd)
            if outcome == .Stolen {
                fold = fold *% 37u64 +% v
            } else if outcome == .Empty {
                fold +%= 3u64
            } else {
                os.exit(17i32)
            }
        }
        step += 1usize
    }
    if fold != 17887017211796918251u64 { os.exit(18i32) }
    if fulls != 2u64 || deque.len[u64](&sd) != 0usize { os.exit(19i32) }

    // --- 2: the stack, single-threaded.
    var next4: [4]u32 = zero
    var value4: [4]u64 = zero
    var value3: [3]u64 = zero
    let (badstack, e5) = stack.stack(next4[..], value3[..])
    if e5 != stack.Invalid { os.exit(20i32) }
    let (st0, e6) = stack.stack(next4[..], value4[..])
    if e6 != ok { os.exit(21i32) }
    var st = st0
    if !stack.is_empty(&st) || stack.len(&st) != 0usize || stack.capacity(&st) != 4usize { os.exit(22i32) }
    let (nope, got_nope) = stack.pop(&st)
    if got_nope { os.exit(23i32) }
    i = 1u64
    while i <= 4u64 {
        if stack.push(&st, i * 11u64) != ok { os.exit(24i32) }
        i += 1u64
    }
    if stack.push(&st, 55u64) != stack.Full { os.exit(25i32) }
    if stack.is_empty(&st) || stack.len(&st) != 4usize { os.exit(26i32) }
    i = 4u64
    while i >= 1u64 {
        let (v, got) = stack.pop(&st)
        if !got || v != i * 11u64 { os.exit(27i32) }
        i -= 1u64
    }
    let (gone, got_gone) = stack.pop(&st)
    if got_gone || !stack.is_empty(&st) || stack.len(&st) != 0usize { os.exit(28i32) }
    // Recycled nodes: push and pop again after a full drain.
    if stack.push(&st, 7u64) != ok || stack.push(&st, 8u64) != ok { os.exit(29i32) }
    let (eight, got_eight) = stack.pop(&st)
    if !got_eight || eight != 8u64 { os.exit(30i32) }

    // --- 3: the deque under threads, main as owner.
    let (ring, e7) = mem.alloc[u64](a, 32768usize)
    if e7 != ok { os.exit(31i32) }
    let (shared_deque, e8) = deque.deque[u64](ring)
    if e8 != ok { os.exit(32i32) }
    var sh = Shared { d: shared_deque, done: atomic.init(0u32) }
    var thieves: [3]Thief = zero
    var workers: [3]thread.Thread = zero
    var k = 0usize
    while k < 3usize {
        thieves[k] = Thief { s: &sh, sum: 0u64, count: 0u64 }
        let (started, start_error) = thread.spawn[Thief](thieve, &thieves[k], 0usize)
        if start_error != ok { os.exit(33i32) }
        workers[k] = started
        k += 1usize
    }
    var owner_sum = 0u64
    var owner_count = 0u64
    i = 1u64
    while i <= 20000u64 {
        if deque.push[u64](&sh.d, i) != ok { os.exit(34i32) }
        if i % 3u64 == 0u64 {
            let (v, got) = deque.pop[u64](&sh.d)
            if got {
                owner_sum +%= v
                owner_count += 1u64
            }
        }
        i += 1u64
    }
    atomic.store(&sh.done, 1u32, .Release)
    while true {
        let (v, got) = deque.pop[u64](&sh.d)
        if !got { break }
        owner_sum +%= v
        owner_count += 1u64
    }
    k = 0usize
    while k < 3usize {
        if thread.join(workers[k]) != ok { os.exit(35i32) }
        k += 1usize
    }
    var total_sum = owner_sum
    var total_count = owner_count
    k = 0usize
    while k < 3usize {
        total_sum +%= thieves[k].sum
        total_count += thieves[k].count
        k += 1usize
    }
    if total_count != 20000u64 { os.exit(36i32) }
    if total_sum != 200010000u64 { os.exit(37i32) }
    if deque.len[u64](&sh.d) != 0usize { os.exit(38i32) }

    // --- 4: the stack under threads.
    let (nexts, e9) = mem.alloc[u32](a, 20000usize)
    if e9 != ok { os.exit(39i32) }
    let (values, e10) = mem.alloc[u64](a, 20000usize)
    if e10 != ok { os.exit(40i32) }
    let (seen, e11) = mem.alloc[u8](a, 20000usize)
    if e11 != ok { os.exit(41i32) }
    var z = 0usize
    while z < 20000usize {
        seen[z] = 0u8
        z += 1usize
    }
    let (pool_stack, e12) = stack.stack(nexts, values)
    if e12 != ok { os.exit(42i32) }
    var pool = Pool { st: pool_stack, seen: seen }
    var pushers: [4]Pusher = zero
    var hands: [4]thread.Thread = zero
    k = 0usize
    while k < 4usize {
        pushers[k] = Pusher { p: &pool, base: u64(k) * 5000u64, popped: 0u64, failed: false }
        let (started, start_error) = thread.spawn[Pusher](push_then_pop, &pushers[k], 0usize)
        if start_error != ok { os.exit(43i32) }
        hands[k] = started
        k += 1usize
    }
    k = 0usize
    while k < 4usize {
        if thread.join(hands[k]) != ok { os.exit(44i32) }
        k += 1usize
    }
    var popped = 0u64
    k = 0usize
    while k < 4usize {
        if pushers[k].failed { os.exit(45i32) }
        popped += pushers[k].popped
        k += 1usize
    }
    if popped != 20000u64 { os.exit(46i32) }
    var at2 = 0usize
    while at2 < 20000usize {
        if seen[at2] != 1u8 { os.exit(47i32) }
        at2 += 1usize
    }
    if !stack.is_empty(&pool.st) || stack.len(&pool.st) != 0usize { os.exit(48i32) }
    try io.print("concurrent deque stack ok\n")
    ret ok
}
