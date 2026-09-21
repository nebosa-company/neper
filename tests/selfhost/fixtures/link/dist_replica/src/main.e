// `e.dist.replica`: `quorum` says which (r, w) overlap on five replicas;
// an LCG sequence of writes, reads with repair, crashes and recoveries
// runs once at r = w = 3 (no read ever answers a version older than the
// last successful write) and once at r = w = 2 (two do); hinted handoff
// queues two writes for a down replica and replays them in order; read
// repair lists and fixes the stale replica of a read set. Hashes and
// counts come from the Python replica. Each check exits with its own code.

use e.dist.replica
use e.io
use e.mem
use e.os

type Run = struct { lcg: u64, h: u64, stale_reads: usize, failed: usize, repaired: usize, replayed: usize, max_hints: usize }

fn draw(r: *Run) -> u64 {
    r.lcg = r.lcg *% 6364136223846793005u64 +% 1442695040888963407u64
    ret r.lcg >> 33u32
}

fn fold(r: *Run, x: u64) { r.h = r.h *% 31u64 +% x }

fn before(a: []const u64, b: []const u64) -> bool {
    var less = false
    var greater = false
    var i = 0usize
    while i < a.len {
        if a[i] < b[i] { less = true }
        if a[i] > b[i] { greater = true }
        i += 1usize
    }
    ret less && !greater
}

fn scenario(r: *Run, s: *replica.Store, h: *replica.Handoff, steps: usize) -> err {
    var last_ok: [5]u64 = zero
    var have_last = false
    var stale: [8]usize = zero
    var up_count = 5usize
    var step = 0usize
    while step < steps {
        let op = draw(r) % 8u64
        let who = usize(draw(r) % 5u64)
        if op < 3u64 {
            let value = i64(draw(r) % 1000u64)
            if !s.replicas[who].up {
                fold(r, 98u64)
                step += 1usize
                continue
            }
            let (acks, write_error) = replica.quorum_write(s, who, value, h)
            if write_error != ok && write_error != replica.NoQuorum { ret write_error }
            fold(r, u64(acks))
            if write_error == ok {
                var i = 0usize
                while i < 5usize {
                    last_ok[i] = s.replicas[who].clock[i]
                    i += 1usize
                }
                have_last = true
            } else {
                r.failed += 1usize
            }
            if h.len > r.max_hints { r.max_hints = h.len }
        } else if op == 3u64 || op == 4u64 {
            let (best, _, read_error) = replica.quorum_read(s)
            if read_error == replica.NoQuorum {
                fold(r, 99u64)
                step += 1usize
                continue
            }
            if read_error != ok { ret read_error }
            fold(r, u64(best))
            fold(r, u64(s.replicas[best].value))
            if have_last && before(s.replicas[best].clock, last_ok[..]) { r.stale_reads += 1usize }
            let (count, repair_error) = replica.read_repair(s, stale[..])
            if repair_error != ok { ret repair_error }
            r.repaired += count
            fold(r, u64(count))
        } else if op == 5u64 {
            if s.replicas[who].up && up_count > 2usize {
                s.replicas[who].up = false
                up_count -= 1usize
            }
            fold(r, u64(up_count))
        } else {
            if !s.replicas[who].up {
                r.replayed += replica.handoff_replay(h, s, u32(who))
                up_count += 1usize
            }
            fold(r, u64(up_count))
        }
        step += 1usize
    }
    var i = 0usize
    while i < 5usize {
        fold(r, u64(s.replicas[i].value))
        var k = 0usize
        while k < 5usize {
            fold(r, s.replicas[i].clock[k])
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn fresh(replicas: []replica.Replica, clocks: []u64) {
    var i = 0usize
    while i < 25usize {
        clocks[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        replicas[i] = replica.replica(clocks[i * 5usize..i * 5usize + 5usize])
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: quorum arithmetic.
    let (c33, e33) = replica.quorum(5usize, 3usize, 3usize)
    let (c22, e22) = replica.quorum(5usize, 2usize, 2usize)
    let (c23, e23) = replica.quorum(5usize, 2usize, 3usize)
    let (c24, e24) = replica.quorum(5usize, 2usize, 4usize)
    if e33 != ok || e22 != ok || e23 != ok || e24 != ok { os.exit(1i32) }
    if !c33 || c22 || c23 || !c24 { os.exit(1i32) }
    let (_, bad) = replica.quorum(5usize, 6usize, 1usize)
    let (_, zero_r) = replica.quorum(5usize, 0usize, 3usize)
    if bad != replica.Invalid || zero_r != replica.Invalid { os.exit(1i32) }

    var clocks: [25]u64 = zero
    var replicas: [5]replica.Replica = zero
    var targets: [64]u32 = zero
    var values: [64]i64 = zero
    var hint_clocks: [320]u64 = zero

    // 2: r = w = 3 over 120 LCG steps: no stale read.
    fresh(replicas[..], clocks[..])
    var s = replica.store(replicas[..], 3usize, 3usize)
    var h = replica.hinted_handoff(targets[..], values[..], hint_clocks[..], 5usize)
    var run: Run = zero
    run.lcg = 42u64
    if scenario(&run, &s, &h, 120usize) != ok { os.exit(2i32) }
    if run.h != 11829185544117281390u64 { os.exit(2i32) }
    if run.stale_reads != 0usize || run.failed != 3usize || run.repaired != 7usize || run.replayed != 31usize { os.exit(2i32) }
    if run.max_hints != 28usize || h.len != 9usize { os.exit(2i32) }
    if replicas[0usize].value != 656i64 || replicas[1usize].value != 909i64 || replicas[3usize].value != 909i64 || replicas[4usize].value != 325i64 { os.exit(2i32) }

    // 3: r = w = 2 over the same steps: two stale reads.
    fresh(replicas[..], clocks[..])
    s = replica.store(replicas[..], 2usize, 2usize)
    h = replica.hinted_handoff(targets[..], values[..], hint_clocks[..], 5usize)
    var run2: Run = zero
    run2.lcg = 42u64
    if scenario(&run2, &s, &h, 120usize) != ok { os.exit(3i32) }
    if run2.h != 5878222014429192379u64 { os.exit(3i32) }
    if run2.stale_reads != 2usize || run2.failed != 0usize || run2.repaired != 9usize || run2.replayed != 31usize { os.exit(3i32) }
    if replicas[3usize].value != 333i64 { os.exit(3i32) }

    // 4: hinted handoff: two writes queued for replica 4, replayed in order.
    fresh(replicas[..], clocks[..])
    s = replica.store(replicas[..], 3usize, 3usize)
    h = replica.hinted_handoff(targets[..], values[..], hint_clocks[..], 5usize)
    replicas[4usize].up = false
    let (acks1, w1) = replica.quorum_write(&s, 0usize, 10i64, &h)
    let (acks2, w2) = replica.quorum_write(&s, 1usize, 20i64, &h)
    if w1 != ok || w2 != ok || acks1 != 3usize || acks2 != 3usize { os.exit(4i32) }
    if h.len != 2usize || targets[0usize] != 4u32 || targets[1usize] != 4u32 || values[0usize] != 10i64 || values[1usize] != 20i64 { os.exit(4i32) }
    if hint_clocks[0usize] != 1u64 || hint_clocks[1usize] != 0u64 || hint_clocks[5usize] != 1u64 || hint_clocks[6usize] != 1u64 { os.exit(4i32) }
    if replica.handoff_replay(&h, &s, 4u32) != 2usize { os.exit(4i32) }
    if !replicas[4usize].up || replicas[4usize].value != 20i64 || clocks[20usize] != 1u64 || clocks[21usize] != 1u64 || h.len != 0usize { os.exit(4i32) }
    let (_, down_write) = replica.quorum_write(&s, 4usize, 1i64, &h)
    if down_write == replica.Invalid { os.exit(4i32) }
    replicas[2usize].up = false
    let (_, down_coord) = replica.quorum_write(&s, 2usize, 1i64, &h)
    if down_coord != replica.Invalid { os.exit(4i32) }

    // 5: read repair: replica 1 missed a write while down and is fixed by a read.
    fresh(replicas[..], clocks[..])
    s = replica.store(replicas[..], 3usize, 3usize)
    h = replica.hinted_handoff(targets[..], values[..], hint_clocks[..], 5usize)
    replicas[1usize].up = false
    let (_, w7) = replica.quorum_write(&s, 0usize, 7i64, &h)
    if w7 != ok { os.exit(5i32) }
    replicas[1usize].up = true
    replicas[0usize].up = false
    let (best, conflict, read_error) = replica.quorum_read(&s)
    if read_error != ok || best != 2usize || conflict || replicas[best].value != 7i64 { os.exit(5i32) }
    var stale: [4]usize = zero
    let (count, repair_error) = replica.read_repair(&s, stale[..])
    if repair_error != ok || count != 1usize || stale[0usize] != 1usize { os.exit(5i32) }
    if replicas[1usize].value != 7i64 || clocks[5usize] != 1u64 { os.exit(5i32) }
    replicas[2usize].up = false
    replicas[3usize].up = false
    let (_, _, no_quorum) = replica.quorum_read(&s)
    if no_quorum != replica.NoQuorum { os.exit(5i32) }

    try io.print("dist replica ok\n")
    ret ok
}
