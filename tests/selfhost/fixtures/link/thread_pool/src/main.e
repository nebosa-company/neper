// `e.thread.pool`: a thousand tasks through four workers add up and each runs once;
// fork_join sums an LCG array leaf by leaf to the sequential total; work_stealing runs
// two thousand uneven tasks exactly once across at least two workers; run_dag orders
// every edge of a 200-node random DAG and refuses a cycle; edf_order sorts by deadline
// with ties by id and edf on one worker completes in that order. Expected values come
// from scratchpad/thread_pool/ref.py. Each check exits with its own code.

use e.atomic
use e.io
use e.mem
use e.os
use e.thread.pool as pool

type Adder = struct { sum: Atomic[u64], marks: []u8 }
type Summer = struct { values: []u64, total: Atomic[u64] }
type Spinner = struct { ran: []u8, spun: []u64 }
type Dag = struct { counter: Atomic[u32], seq: []u32 }
type Recorder = struct { order: []u32, filled: usize }

fn add_task(s: *Adder, id: u32) {
    let before = atomic.add(&s.sum, u64(id), .Relaxed)
    s.marks[usize(id)] += 1u8
}

fn sum_leaf(s: *Summer, lo: usize, hi: usize) {
    var part = 0u64
    var i = lo
    while i < hi {
        part = part +% s.values[i]
        i += 1usize
    }
    let before = atomic.add(&s.total, part, .Relaxed)
}

fn spin_task(s: *Spinner, id: u32) {
    var x = u64(id)
    var k = 0u64
    let rounds = (u64(id) % 97u64) * 200u64
    while k < rounds {
        x = x *% 6364136223846793005u64 +% 1442695040888963407u64
        k += 1u64
    }
    s.spun[usize(id)] = x
    s.ran[usize(id)] += 1u8
}

fn dag_task(d: *Dag, id: u32) {
    let ticket = atomic.add(&d.counter, 1u32, .AcqRel)
    d.seq[usize(id)] = ticket
}

fn record_task(r: *Recorder, id: u32) {
    r.order[r.filled] = id
    r.filled += 1usize
}

fn lcg(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var ids: [2000]u32 = zero
    var i = 0usize
    while i < 2000usize {
        ids[i] = u32(i)
        i += 1usize
    }

    // 1: run -- 1,000 tasks over four workers, each adding its id and marking a byte.
    var marks: [1000]u8 = zero
    var adder = Adder { sum: atomic.init(0u64), marks: marks[..] }
    let (p1, e1) = pool.pool[Adder](a, 4usize, 64usize, &adder, add_task)
    if e1 != ok { os.exit(1i32) }
    var pa = p1
    if pool.run[Adder](&pa, ids[..1000usize]) != ok { os.exit(2i32) }
    if pool.shutdown[Adder](&pa) != ok { os.exit(3i32) }
    if atomic.load(&adder.sum, .Acquire) != 499500u64 { os.exit(4i32) }
    i = 0usize
    while i < 1000usize {
        if marks[i] != 1u8 { os.exit(5i32) }
        i += 1usize
    }

    // 2: fork_join -- 100,000 LCG values summed in leaves of 4,096.
    let (values, values_error) = mem.alloc[u64](a, 100000usize)
    if values_error != ok { ret values_error }
    var state = 12345u64
    var sequential = 0u64
    i = 0usize
    while i < 100000usize {
        values[i] = lcg(&state)
        sequential = sequential +% values[i]
        i += 1usize
    }
    var summer = Summer { values: values, total: atomic.init(0u64) }
    if pool.fork_join[Summer](a, 4usize, &summer, 0usize, 100000usize, 4096usize, sum_leaf) != ok { os.exit(6i32) }
    if atomic.load(&summer.total, .Acquire) != 107338214866498u64 { os.exit(7i32) }
    if sequential != 107338214866498u64 { os.exit(8i32) }

    // 3: work_stealing -- 2,000 tasks of uneven cost over four thieves.
    var ran: [2000]u8 = zero
    let (spun, spun_error) = mem.alloc[u64](a, 2000usize)
    if spun_error != ok { ret spun_error }
    var spinner = Spinner { ran: ran[..], spun: spun }
    var counts: [4]u32 = zero
    if pool.work_stealing[Spinner](a, 4usize, &spinner, spin_task, ids[..], counts[..]) != ok { os.exit(9i32) }
    var spin_xor = 0u64
    i = 0usize
    while i < 2000usize {
        if ran[i] != 1u8 { os.exit(10i32) }
        spin_xor ^= spun[i]
        i += 1usize
    }
    var busy = 0usize
    var total_ran = 0u32
    i = 0usize
    while i < 4usize {
        if counts[i] > 0u32 { busy += 1usize }
        total_ran += counts[i]
        i += 1usize
    }
    if busy < 2usize { os.exit(11i32) }
    if total_ran != 2000u32 { os.exit(12i32) }
    if spin_xor != 8608579266641554048u64 { os.exit(13i32) }

    // 4: run_dag -- a 200-node DAG with edges from lower to higher ids.
    var deps: [600]u32 = zero
    var dep_starts: [201]usize = zero
    var indegree: [200]Atomic[u32] = zero
    var seq: [200]u32 = zero
    state = 777u64
    var m = 0usize
    var u = 0usize
    while u < 200usize {
        if u + 1usize < 200usize {
            let c = lcg(&state) % 3u64
            var e = 0u64
            while e < c {
                let v = u + 1usize + usize(lcg(&state) % u64(199usize - u))
                deps[m] = u32(v)
                m += 1usize
                e += 1u64
            }
        }
        dep_starts[u + 1usize] = m
        u += 1usize
    }
    var dag = Dag { counter: atomic.init(0u32), seq: seq[..] }
    let (p2, e2) = pool.pool[Dag](a, 4usize, 256usize, &dag, dag_task)
    if e2 != ok { os.exit(14i32) }
    var pd = p2
    if pool.run_dag[Dag](&pd, deps[..m], dep_starts[..], indegree[..]) != ok { os.exit(15i32) }
    u = 0usize
    while u < 200usize {
        var k = dep_starts[u]
        while k < dep_starts[u + 1usize] {
            if seq[u] >= seq[usize(deps[k])] { os.exit(16i32) }
            k += 1usize
        }
        u += 1usize
    }
    if atomic.load(&dag.counter, .Acquire) != 200u32 { os.exit(17i32) }
    var cycle_deps: [3]u32 = [3]u32{ 1u32, 2u32, 0u32 }
    var cycle_starts: [4]usize = [4]usize{ 0usize, 1usize, 2usize, 3usize }
    if pool.run_dag[Dag](&pd, cycle_deps[..], cycle_starts[..], indegree[..]) != pool.Invalid { os.exit(18i32) }
    if pool.shutdown[Dag](&pd) != ok { os.exit(19i32) }
    if m != 204usize { os.exit(20i32) }

    // 5: edf_order and edf -- ten deadlines with ties, one worker.
    var deadlines: [10]u64 = zero
    state = 99u64
    i = 0usize
    while i < 10usize {
        deadlines[i] = lcg(&state) % 5u64
        i += 1usize
    }
    var order: [10]u32 = zero
    if pool.edf_order(deadlines[..], order[..]) != ok { os.exit(21i32) }
    let expected: [10]u32 = [10]u32{ 7u32, 9u32, 1u32, 2u32, 3u32, 8u32, 0u32, 5u32, 6u32, 4u32 }
    i = 0usize
    while i < 10usize {
        if order[i] != expected[i] { os.exit(21i32) }
        i += 1usize
    }
    var done: [10]u32 = zero
    var recorder = Recorder { order: done[..], filled: 0usize }
    let (p3, e3) = pool.pool[Recorder](a, 1usize, 16usize, &recorder, record_task)
    if e3 != ok { os.exit(22i32) }
    var pr = p3
    if pool.edf[Recorder](&pr, deadlines[..], ids[..10usize], order[..]) != ok { os.exit(23i32) }
    if recorder.filled != 10usize { os.exit(24i32) }
    i = 1usize
    while i < 10usize {
        if deadlines[usize(done[i - 1usize])] > deadlines[usize(done[i])] { os.exit(25i32) }
        i += 1usize
    }
    if pool.shutdown[Recorder](&pr) != ok { os.exit(26i32) }

    try io.print("thread pool ok\n")
    ret ok
}
