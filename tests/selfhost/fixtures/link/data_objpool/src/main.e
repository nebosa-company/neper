// `e.data.objpool`: hand-checked scenarios (exhaustion, LIFO and FIFO idle choice,
// FIFO waiter hand-off with an unhealthy return, max_idle destruction, eviction timing
// down to `min_idle`, leak listing and reclaim, waiter expiry, arena construction and
// the Invalid/TooSmall refusals) and a 400-operation LCG-driven differential whose
// rolling hash of every answer equals the independent Python model's
// (scripts/gen_objpool_test.py: 16383318164073944778, final states 0/0/0/5, 43 created,
// 38 destroyed, 3 evicted, 18 leaked). Every check has its own exit code.
use e.os
use e.mem
use e.data.objpool as pool

type Obj = struct { v: u64 }

fn config(max_total: usize, max_idle: usize, min_idle: usize, idle: u64, leak: u64, lifo: bool, wait: bool) -> pool.Config {
    ret pool.Config { max_total: max_total, max_idle: max_idle, min_idle: min_idle, idle_ticks: idle, leak_ticks: leak, lifo: lifo, wait: wait }
}

fn checks_basic(a: *mem.Arena) -> i32 {
    let (made, made_error) = pool.pool_in[Obj](a, config(2usize, 2usize, 0usize, 0u64, 0u64, true, false), 2usize)
    if made_error != ok { ret 10i32 }
    var p = made
    let g0 = pool.acquire[Obj](&p, 0u64, 0u32)
    let g1 = pool.acquire[Obj](&p, 0u64, 1u32)
    if g0.outcome != .NeedsCreate || g0.slot != 0u32 || g1.outcome != .NeedsCreate || g1.slot != 1u32 { ret 11i32 }
    if pool.attach[Obj](&p, 0u32, Obj { v: 100u64 }, 1u64) != ok || pool.attach[Obj](&p, 1u32, Obj { v: 101u64 }, 1u64) != ok { ret 12i32 }
    // Exhausted under the fail policy, queueing is off.
    let g2 = pool.acquire[Obj](&p, 2u64, 2u32)
    if g2.outcome != .Exhausted || g2.slot != pool.NONE { ret 13i32 }
    if pool.object[Obj](&p, 1u32).v != 101u64 { ret 14i32 }
    // Release the older (slot 0, t=3) then the newer (slot 1, t=4): LIFO takes slot 1.
    let (r0, e0) = pool.release[Obj](&p, 0u32, 3u64, true)
    let (r1, e1) = pool.release[Obj](&p, 1u32, 4u64, true)
    if e0 != ok || e1 != ok || r0.destroy || r1.destroy { ret 15i32 }
    let back = pool.acquire[Obj](&p, 5u64, 3u32)
    if back.outcome != .Reused || back.slot != 1u32 { ret 16i32 }
    // The object came back as it was, with its use counted.
    if pool.object[Obj](&p, 1u32).v != 101u64 || p.uses[1] != 2u32 { ret 17i32 }
    // A slot not borrowed refuses a release; so does an unknown one.
    let (_, bad) = pool.release[Obj](&p, 0u32, 6u64, true)
    if bad != pool.Invalid { ret 18i32 }
    let (_, worse) = pool.release[Obj](&p, 9u32, 6u64, true)
    if worse != pool.Invalid { ret 19i32 }
    if pool.count[Obj](&p, pool.BORROWED) != 1usize || pool.count[Obj](&p, pool.IDLE) != 1usize { ret 20i32 }
    ret 0i32
}

fn checks_order(a: *mem.Arena) -> i32 {
    // FIFO idle choice hands out the oldest idle object.
    let (made, made_error) = pool.pool_in[Obj](a, config(3usize, 3usize, 0usize, 0u64, 0u64, false, false), 1usize)
    if made_error != ok { ret 30i32 }
    var p = made
    var i = 0u32
    while i < 3u32 {
        let g = pool.acquire[Obj](&p, 0u64, i)
        if g.outcome != .NeedsCreate { ret 31i32 }
        if pool.attach[Obj](&p, g.slot, Obj { v: u64(i) }, 0u64) != ok { ret 32i32 }
        i += 1u32
    }
    let (_, e2) = pool.release[Obj](&p, 2u32, 10u64, true)
    let (_, e0) = pool.release[Obj](&p, 0u32, 20u64, true)
    let (_, e1) = pool.release[Obj](&p, 1u32, 15u64, true)
    if e0 != ok || e1 != ok || e2 != ok { ret 33i32 }
    let first = pool.acquire[Obj](&p, 30u64, 9u32)
    if first.outcome != .Reused || first.slot != 2u32 { ret 34i32 }
    let second = pool.acquire[Obj](&p, 30u64, 9u32)
    if second.slot != 1u32 { ret 35i32 }
    ret 0i32
}

fn checks_wait(a: *mem.Arena) -> i32 {
    let (made, made_error) = pool.pool_in[Obj](a, config(1usize, 1usize, 0usize, 0u64, 0u64, true, true), 2usize)
    if made_error != ok { ret 40i32 }
    var p = made
    let owner = pool.acquire[Obj](&p, 0u64, 7u32)
    if owner.outcome != .NeedsCreate { ret 41i32 }
    if pool.attach[Obj](&p, owner.slot, Obj { v: 1u64 }, 0u64) != ok { ret 42i32 }
    let w1 = pool.acquire[Obj](&p, 1u64, 8u32)
    let w2 = pool.acquire[Obj](&p, 2u64, 9u32)
    let w3 = pool.acquire[Obj](&p, 3u64, 10u32)
    if w1.outcome != .Queued || w2.outcome != .Queued { ret 43i32 }
    // The queue holds two: a third requester is refused outright.
    if w3.outcome != .Exhausted { ret 44i32 }
    // A healthy return goes straight to the first waiter.
    let (h, he) = pool.release[Obj](&p, owner.slot, 5u64, true)
    if he != ok || !h.handoff || h.who != 8u32 || h.needs_create || h.destroy { ret 45i32 }
    if pool.count[Obj](&p, pool.BORROWED) != 1usize { ret 46i32 }
    // An unhealthy one hands the second waiter a slot it must refill.
    let (u, ue) = pool.release[Obj](&p, owner.slot, 6u64, false)
    if ue != ok || !u.handoff || u.who != 9u32 || !u.needs_create || !u.destroy { ret 47i32 }
    if pool.count[Obj](&p, pool.PENDING) != 1usize { ret 48i32 }
    if pool.attach[Obj](&p, u.slot, Obj { v: 2u64 }, 7u64) != ok { ret 49i32 }
    // Expiry: queue a waiter at t=10 and drop it at t=40 after a 25-tick limit.
    let (_, rl) = pool.release[Obj](&p, owner.slot, 8u64, true)
    if rl != ok { ret 50i32 }
    let g = pool.acquire[Obj](&p, 9u64, 11u32)
    if g.outcome != .Reused { ret 51i32 }
    let late = pool.acquire[Obj](&p, 10u64, 12u32)
    if late.outcome != .Queued { ret 52i32 }
    var gone: [4]u32 = zero
    if pool.expire_waiters[Obj](&p, 30u64, 25u64, gone[0..]) != 0usize { ret 53i32 }
    if pool.expire_waiters[Obj](&p, 40u64, 25u64, gone[0..]) != 1usize || gone[0] != 12u32 { ret 54i32 }
    if p.wait_len != 0usize { ret 55i32 }
    ret 0i32
}

fn checks_eviction(a: *mem.Arena) -> i32 {
    let (made, made_error) = pool.pool_in[Obj](a, config(4usize, 1usize, 0usize, 100u64, 0u64, true, false), 1usize)
    if made_error != ok { ret 60i32 }
    var p = made
    // max_idle is 1: the second and third returns are destroyed, not kept.
    var i = 0u32
    while i < 3u32 {
        let g = pool.acquire[Obj](&p, 0u64, i)
        if pool.attach[Obj](&p, g.slot, Obj { v: 0u64 }, 0u64) != ok { ret 61i32 }
        i += 1u32
    }
    let (r0, _) = pool.release[Obj](&p, 0u32, 10u64, true)
    let (r1, _) = pool.release[Obj](&p, 1u32, 20u64, true)
    let (r2, _) = pool.release[Obj](&p, 2u32, 30u64, true)
    if r0.destroy || !r1.destroy || !r2.destroy { ret 62i32 }
    if pool.count[Obj](&p, pool.IDLE) != 1usize || p.destroyed != 2u64 { ret 63i32 }
    var out: [4]u32 = zero
    // Idle since t=10 with a 100-tick limit: nothing at 109, the object at 110.
    if pool.evict[Obj](&p, 109u64, out[0..]) != 0usize { ret 64i32 }
    if pool.evict[Obj](&p, 110u64, out[0..]) != 1usize || out[0] != 0u32 { ret 65i32 }
    if p.evicted != 1u64 || pool.count[Obj](&p, pool.EMPTY) != 4usize { ret 66i32 }
    // min_idle: three idle objects aged past the limit leave `min_idle` standing.
    let (made2, made2_error) = pool.pool_in[Obj](a, config(3usize, 3usize, 1usize, 50u64, 0u64, true, false), 1usize)
    if made2_error != ok { ret 67i32 }
    var q = made2
    i = 0u32
    while i < 3u32 {
        let g = pool.acquire[Obj](&q, 0u64, i)
        if pool.attach[Obj](&q, g.slot, Obj { v: 0u64 }, 0u64) != ok { ret 68i32 }
        i += 1u32
    }
    let (_, a0) = pool.release[Obj](&q, 0u32, 1u64, true)
    let (_, a1) = pool.release[Obj](&q, 1u32, 2u64, true)
    let (_, a2) = pool.release[Obj](&q, 2u32, 3u64, true)
    if a0 != ok || a1 != ok || a2 != ok { ret 69i32 }
    if pool.evict[Obj](&q, 51u64, out[0..]) != 1usize || out[0] != 0u32 { ret 70i32 }
    // At 100 all remaining are old but one must stay.
    if pool.evict[Obj](&q, 100u64, out[0..]) != 1usize || out[0] != 1u32 { ret 71i32 }
    if pool.count[Obj](&q, pool.IDLE) != 1usize { ret 72i32 }
    ret 0i32
}

fn checks_leaks(a: *mem.Arena) -> i32 {
    let (made, made_error) = pool.pool_in[Obj](a, config(3usize, 3usize, 0usize, 0u64, 50u64, true, false), 1usize)
    if made_error != ok { ret 80i32 }
    var p = made
    let g0 = pool.acquire[Obj](&p, 0u64, 0u32)
    if pool.attach[Obj](&p, g0.slot, Obj { v: 0u64 }, 0u64) != ok { ret 81i32 }
    let g1 = pool.acquire[Obj](&p, 40u64, 1u32)
    if pool.attach[Obj](&p, g1.slot, Obj { v: 0u64 }, 40u64) != ok { ret 82i32 }
    var out: [4]u32 = zero
    if pool.leaks[Obj](&p, 49u64, out[0..]) != 0usize { ret 83i32 }
    if pool.leaks[Obj](&p, 60u64, out[0..]) != 1usize || out[0] != 0u32 { ret 84i32 }
    if pool.leaks[Obj](&p, 100u64, out[0..]) != 2usize { ret 85i32 }
    let (_, reclaim_error) = pool.reclaim[Obj](&p, 0u32, 100u64)
    if reclaim_error != ok || p.leaked != 1u64 || pool.count[Obj](&p, pool.BORROWED) != 1usize { ret 86i32 }
    // A creation that fails frees the reserved slot.
    let g2 = pool.acquire[Obj](&p, 101u64, 2u32)
    if g2.outcome != .NeedsCreate { ret 87i32 }
    let (ab, abe) = pool.abort_create[Obj](&p, g2.slot, 102u64)
    if abe != ok || ab.handoff || pool.count[Obj](&p, pool.PENDING) != 0usize { ret 88i32 }
    // Storage is checked up front.
    var items: [1]Obj = zero
    var state: [1]u8 = zero
    var since: [1]u64 = zero
    var uses: [1]u32 = zero
    var waiters: [1]u32 = zero
    var waiter_at: [1]u64 = zero
    let (_, small) = pool.pool[Obj](items[0..], state[0..], since[0..], uses[0..], waiters[0..], waiter_at[0..], config(2usize, 1usize, 0usize, 0u64, 0u64, true, false))
    if small != pool.TooSmall { ret 89i32 }
    let (_, empty) = pool.pool[Obj](items[0..], state[0..], since[0..], uses[0..], waiters[0..], waiter_at[0..], config(0usize, 0usize, 0usize, 0u64, 0u64, true, false))
    if empty != pool.Invalid { ret 90i32 }
    ret 0i32
}

fn mix(h: u64, v: u64) -> u64 { ret (h ^ v) *% 1099511628211u64 }

fn code_of(o: pool.Outcome) -> u64 {
    if o == .Reused { ret 0u64 }
    if o == .NeedsCreate { ret 1u64 }
    if o == .Queued { ret 2u64 }
    ret 3u64
}

fn checks_differential(a: *mem.Arena) -> i32 {
    let (made, made_error) = pool.pool_in[Obj](a, config(5usize, 3usize, 1usize, 20u64, 30u64, true, true), 4usize)
    if made_error != ok { ret 100i32 }
    var p = made
    var h = 14695981039346656037u64
    var x = 7u64
    var now = 0u64
    var it = 0u32
    var out: [8]u32 = zero
    while it < 400u32 {
        x = x *% 6364136223846793005u64 +% 1442695040888963407u64
        let r = x >> 33u64
        now += r % 7u64
        let op = (r >> 3u64) % 8u64
        if op <= 2u64 {
            let g = pool.acquire[Obj](&p, now, it)
            h = mix(h, 1u64)
            h = mix(h, code_of(g.outcome))
            h = mix(h, u64(g.slot))
        } else {
            if op <= 4u64 {
                var borrowed: [5]u32 = zero
                var nb = 0usize
                var s = 0usize
                while s < 5usize {
                    if p.state[s] == pool.BORROWED {
                        borrowed[nb] = u32(s)
                        nb += 1usize
                    }
                    s += 1usize
                }
                if nb == 0usize {
                    h = mix(h, 2u64)
                } else {
                    let slot = borrowed[usize((r >> 8u64) % u64(nb))]
                    let healthy = ((r >> 16u64) % 5u64) != 0u64
                    let (rel, rel_error) = pool.release[Obj](&p, slot, now, healthy)
                    if rel_error != ok { ret 101i32 }
                    h = mix(h, 3u64)
                    h = mix(h, u64(slot))
                    if healthy { h = mix(h, 1u64) } else { h = mix(h, 0u64) }
                    if rel.destroy { h = mix(h, 1u64) } else { h = mix(h, 0u64) }
                    if rel.handoff { h = mix(h, 1u64) } else { h = mix(h, 0u64) }
                    h = mix(h, u64(rel.who))
                    if rel.needs_create { h = mix(h, 1u64) } else { h = mix(h, 0u64) }
                }
            } else {
                if op == 5u64 {
                    var pending = pool.NONE
                    var s = 0usize
                    while s < 5usize && pending == pool.NONE {
                        if p.state[s] == pool.PENDING { pending = u32(s) }
                        s += 1usize
                    }
                    if pending == pool.NONE {
                        h = mix(h, 4u64)
                    } else {
                        if pool.attach[Obj](&p, pending, Obj { v: now }, now) != ok { ret 102i32 }
                        h = mix(h, 5u64)
                        h = mix(h, u64(pending))
                    }
                } else {
                    if op == 6u64 {
                        let n = pool.evict[Obj](&p, now, out[0..])
                        h = mix(h, 6u64)
                        h = mix(h, u64(n))
                        var k = 0usize
                        while k < n {
                            h = mix(h, u64(out[k]))
                            k += 1usize
                        }
                    } else {
                        let n = pool.leaks[Obj](&p, now, out[0..])
                        h = mix(h, 7u64)
                        h = mix(h, u64(n))
                        var k = 0usize
                        while k < n {
                            h = mix(h, u64(out[k]))
                            k += 1usize
                        }
                        if n > 0usize {
                            let (rel, rel_error) = pool.reclaim[Obj](&p, out[0], now)
                            if rel_error != ok { ret 103i32 }
                            if rel.destroy { h = mix(h, 1u64) } else { h = mix(h, 0u64) }
                            if rel.handoff { h = mix(h, 1u64) } else { h = mix(h, 0u64) }
                            h = mix(h, u64(rel.who))
                            if rel.needs_create { h = mix(h, 1u64) } else { h = mix(h, 0u64) }
                        }
                    }
                }
            }
        }
        if it % 50u32 == 49u32 {
            let n = pool.expire_waiters[Obj](&p, now, 25u64, out[0..])
            h = mix(h, 8u64)
            h = mix(h, u64(n))
            var k = 0usize
            while k < n {
                h = mix(h, u64(out[k]))
                k += 1usize
            }
        }
        it += 1u32
    }
    h = mix(h, u64(pool.count[Obj](&p, pool.EMPTY)))
    h = mix(h, u64(pool.count[Obj](&p, pool.PENDING)))
    h = mix(h, u64(pool.count[Obj](&p, pool.IDLE)))
    h = mix(h, u64(pool.count[Obj](&p, pool.BORROWED)))
    h = mix(h, p.created)
    h = mix(h, p.destroyed)
    h = mix(h, p.evicted)
    h = mix(h, p.leaked)
    if p.created != 43u64 || p.destroyed != 38u64 || p.evicted != 3u64 || p.leaked != 18u64 { ret 104i32 }
    if h != 16383318164073944778u64 { ret 105i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var code = checks_basic(a)
    if code == 0i32 { code = checks_order(a) }
    if code == 0i32 { code = checks_wait(a) }
    if code == 0i32 { code = checks_eviction(a) }
    if code == 0i32 { code = checks_leaks(a) }
    if code == 0i32 { code = checks_differential(a) }
    if code != 0i32 { os.exit(code) }
    ret ok
}
