// `e.test.sim`: a ping-pong of two actors delivers exactly 100 messages
// in 100 steps (50 pings, 50 pongs, the clock at 100), a three-actor gossip
// with random delays and drops replays to the same trace hash from the same
// seed, differs from another seed, and both traces, counts and drops match
// the Python replica of the scheduler on the same PCG stream. Each check
// exits with its own code.

use e.io
use e.mem
use e.os
use e.test.sim as sim

type Ctx = struct { pings: usize, pongs: usize, count: [3]usize, timers: usize, failed: bool }

fn pingpong(c: *Ctx, s: *sim.Sim, actor: u32, m: sim.Message) {
    if m.kind == 1u32 {
        c.pings += 1usize
        if sim.send(s, actor, m.from, 2u32, m.value + 1i64) != ok { c.failed = true }
    } else {
        c.pongs += 1usize
        if sim.send(s, actor, m.from, 1u32, m.value + 1i64) != ok { c.failed = true }
    }
}

fn gossip(c: *Ctx, s: *sim.Sim, actor: u32, m: sim.Message) {
    c.count[usize(actor)] += 1usize
    if m.kind == 1u32 && m.value < 4i64 {
        if sim.send(s, actor, (actor + 1u32) % 3u32, 1u32, m.value + 1i64) != ok { c.failed = true }
        if sim.send(s, actor, (actor + 2u32) % 3u32, 1u32, m.value + 1i64) != ok { c.failed = true }
    }
    if m.kind == 9u32 { c.timers += 1usize }
}

fn gossip_run(seed: u64, pool: []sim.Message, flags: []u8, c: *Ctx) -> (usize, u64, u64, u64) {
    var s = sim.sim(3usize, pool, flags, seed, 3u64, 100u64)
    var actor = 0u32
    while actor < 3u32 {
        if sim.send(&s, actor, (actor + 1u32) % 3u32, 1u32, 0i64) != ok { c.failed = true }
        if sim.send(&s, actor, (actor + 2u32) % 3u32, 1u32, 0i64) != ok { c.failed = true }
        actor += 1u32
    }
    if sim.timer(&s, 0u32, 2u64, 9u32, 7i64) != ok { c.failed = true }
    let n = sim.run[Ctx](&s, c, 500usize, gossip)
    ret (n, s.trace, s.dropped, s.clock)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var pool: [64]sim.Message = zero
    var flags: [64]u8 = zero

    // 1: ping-pong.
    var c = Ctx { pings: 0usize, pongs: 0usize, count: zero, timers: 0usize, failed: false }
    var s = sim.sim(2usize, pool[..16usize], flags[..16usize], 5u64, 0u64, 0u64)
    if sim.send(&s, 0u32, 1u32, 1u32, 0i64) != ok { os.exit(1i32) }
    let n = sim.run[Ctx](&s, &c, 100usize, pingpong)
    if n != 100usize || c.failed || c.pings != 50usize || c.pongs != 50usize { os.exit(1i32) }
    if sim.pending(&s) != 1usize || s.clock != 100u64 || s.delivered != 100u64 || s.trace != 10454497793893370333u64 { os.exit(1i32) }
    if sim.send(&s, 0u32, 2u32, 1u32, 0i64) != sim.Invalid || sim.timer(&s, 5u32, 1u64, 1u32, 0i64) != sim.Invalid { os.exit(1i32) }
    var tiny = sim.sim(2usize, pool[..1usize], flags[..1usize], 5u64, 0u64, 0u64)
    if sim.send(&tiny, 0u32, 1u32, 1u32, 0i64) != ok || sim.send(&tiny, 0u32, 1u32, 1u32, 0i64) != sim.TooSmall { os.exit(1i32) }

    // 2: gossip replays from its seed.
    var c1 = Ctx { pings: 0usize, pongs: 0usize, count: zero, timers: 0usize, failed: false }
    let (n1, t1, d1, k1) = gossip_run(5u64, pool[..], flags[..], &c1)
    var c2 = Ctx { pings: 0usize, pongs: 0usize, count: zero, timers: 0usize, failed: false }
    let (n2, t2, d2, k2) = gossip_run(5u64, pool[..], flags[..], &c2)
    var c3 = Ctx { pings: 0usize, pongs: 0usize, count: zero, timers: 0usize, failed: false }
    let (n3, t3, d3, k3) = gossip_run(6u64, pool[..], flags[..], &c3)
    if c1.failed || c2.failed || c3.failed { os.exit(2i32) }
    if n1 != n2 || t1 != t2 || d1 != d2 || k1 != k2 { os.exit(2i32) }
    if t1 == t3 { os.exit(2i32) }
    if n1 != 125usize || t1 != 4190594722926912117u64 || d1 != 10u64 || k1 != 17u64 || c1.timers != 1usize { os.exit(2i32) }
    if c1.count[0usize] != 41usize || c1.count[1usize] != 43usize || c1.count[2usize] != 41usize { os.exit(2i32) }
    if n3 != 97usize || t3 != 9054711580117236124u64 || d3 != 14u64 || k3 != 18u64 { os.exit(2i32) }
    if c3.count[0usize] != 34usize || c3.count[1usize] != 32usize || c3.count[2usize] != 31usize { os.exit(2i32) }

    try io.print("test sim ok\n")
    ret ok
}
