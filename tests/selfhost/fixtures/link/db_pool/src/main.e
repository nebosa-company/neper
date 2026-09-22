// `e.db.pool`: an empty pool asks for a connection then reuses it (MRU), a full
// pool queues waiters and releases hand off FIFO, a broken release is replaced,
// the housekeeper evicts by idle timeout and lifetime exactly as the Python
// replica, queued waiters time out, a 300-event LCG script folds to the replica's
// hash and stats, and Full/Invalid/TooSmall are refused. Each check exits with its own code.

use e.db.pool
use e.io
use e.mem
use e.os

fn config(min_idle: usize, max_size: usize, lifetime: u64, idle: u64, wait: u64) -> pool.Config {
    ret pool.Config { min_idle: min_idle, max_size: max_size, max_lifetime: lifetime, idle_timeout: idle, connection_timeout: wait, validation_interval: 30u64 }
}

fn fold(h: u64, v: u64) -> u64 {
    ret (h ^ v) *% 0x100000001b3u64
}

// Four connections acquired by four waiters at t=0..3 and released at t=10..13.
fn fill(p: *pool.Pool) -> bool {
    var k = 0usize
    while k < 4usize {
        let (i, o, e) = pool.acquire(p, u32(k) + 1u32, u64(k))
        if e != ok || o != .NeedsCreate || usize(i) != k { ret false }
        if pool.attach(p, i, 200u64 + u64(k), u64(k)) != ok { ret false }
        let (i2, o2, e2) = pool.acquire(p, u32(k) + 1u32, u64(k))
        if e2 != ok || o2 != .Acquired || usize(i2) != k { ret false }
        k += 1usize
    }
    k = 0usize
    while k < 4usize {
        let (w, e) = pool.release(p, u32(k), 10u64 + u64(k), false)
        if e != ok || w != pool.NONE { ret false }
        k += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var handle: [4]u64 = zero
    var state: [4]u8 = zero
    var created: [4]u64 = zero
    var used: [4]u64 = zero
    var uses: [4]u32 = zero
    var waiters: [8]u32 = zero
    var since: [8]u64 = zero
    var out: [8]u32 = zero

    // 1: empty pool: NeedsCreate, attach, acquire, release, MRU reuse.
    var (p, pe) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..], since[..], config(1usize, 3usize, 500u64, 120u64, 60u64))
    if pe != ok { os.exit(1i32) }
    let (i1, o1, e1) = pool.acquire(&p, 1u32, 0u64)
    if e1 != ok || o1 != .NeedsCreate || i1 != 0u32 { os.exit(1i32) }
    if pool.attach(&p, 0u32, 77u64, 0u64) != ok { os.exit(1i32) }
    let (i2, o2, e2) = pool.acquire(&p, 1u32, 1u64)
    if e2 != ok || o2 != .Acquired || i2 != 0u32 || p.handle[0] != 77u64 { os.exit(1i32) }
    let (w1, re1) = pool.release(&p, 0u32, 2u64, false)
    if re1 != ok || w1 != pool.NONE { os.exit(1i32) }
    let (i3, o3, e3) = pool.acquire(&p, 2u32, 3u64)
    if e3 != ok || o3 != .Acquired || i3 != 0u32 { os.exit(1i32) }

    // 2: max_size 3, five waiters: two queued; releases hand off to 4 then 5.
    let (p2, pe2) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..], since[..], config(1usize, 3usize, 500u64, 120u64, 60u64))
    if pe2 != ok { os.exit(2i32) }
    p = p2
    var w = 1u32
    while w <= 5u32 {
        var (i, o, e) = pool.acquire(&p, w, 10u64)
        if e != ok { os.exit(2i32) }
        if o == .NeedsCreate {
            if pool.attach(&p, i, 100u64 + u64(w), 10u64) != ok { os.exit(2i32) }
            let (ia, oa, ea) = pool.acquire(&p, w, 10u64)
            i = ia
            o = oa
            e = ea
        }
        if w <= 3u32 && (o != .Acquired || i != w - 1u32) { os.exit(2i32) }
        if w > 3u32 && (o != .Queued || i != pool.NONE) { os.exit(2i32) }
        w += 1u32
    }
    let (h4, rh4) = pool.release(&p, 0u32, 11u64, false)
    let (h5, rh5) = pool.release(&p, 1u32, 12u64, false)
    if rh4 != ok || h4 != 4u32 || rh5 != ok || h5 != 5u32 { os.exit(2i32) }
    let (t2, id2, b2, q2) = pool.stats(&p)
    if t2 != 3usize || id2 != 0usize || b2 != 3usize || q2 != 0usize { os.exit(2i32) }

    // 3: a broken release closes the slot; the next acquire NeedsCreate again.
    let (hb, rb) = pool.release(&p, 2u32, 13u64, true)
    if rb != ok || hb != pool.NONE { os.exit(3i32) }
    let (t3, id3, b3, q3) = pool.stats(&p)
    if t3 != 2usize || id3 != 0usize || b3 != 2usize || q3 != 0usize { os.exit(3i32) }
    let (ib, ob, eb) = pool.acquire(&p, 4u32, 14u64)
    if eb != ok || ob != .NeedsCreate || ib != 2u32 { os.exit(3i32) }
    if pool.attach(&p, 2u32, 9u64, 14u64) != ok { os.exit(3i32) }
    let (ic, oc, ec) = pool.acquire(&p, 4u32, 15u64)
    if ec != ok || oc != .Acquired || ic != 2u32 { os.exit(3i32) }

    // 4: housekeeper: idle_timeout keeps min_idle (the newest); max_lifetime evicts idle, in-use closes at release.
    let (p4, pe4) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..], since[..], config(1usize, 4usize, 500u64, 120u64, 60u64))
    if pe4 != ok { os.exit(4i32) }
    p = p4
    if !fill(&p) { os.exit(4i32) }
    let n4 = pool.evict_expired(&p, 140u64, out[..])
    if n4 != 3usize || out[0] != 0u32 || out[1] != 1u32 || out[2] != 2u32 { os.exit(4i32) }
    let (t4, id4, b4, q4) = pool.stats(&p)
    if t4 != 1usize || id4 != 1usize || b4 != 0usize || q4 != 0usize { os.exit(4i32) }
    let (p4b, pe4b) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..], since[..], config(1usize, 4usize, 500u64, 120u64, 60u64))
    if pe4b != ok { os.exit(4i32) }
    p = p4b
    if !fill(&p) { os.exit(4i32) }
    let (i4, o4, e4) = pool.acquire(&p, 9u32, 400u64)
    if e4 != ok || o4 != .Acquired || i4 != 3u32 { os.exit(4i32) }
    let n4b = pool.evict_expired(&p, 502u64, out[..])
    if n4b != 3usize || out[0] != 0u32 || out[1] != 1u32 || out[2] != 2u32 { os.exit(4i32) }
    let (t4b, id4b, b4b, _) = pool.stats(&p)
    if t4b != 1usize || id4b != 0usize || b4b != 1usize { os.exit(4i32) }
    let (h4b, rh4b) = pool.release(&p, 3u32, 503u64, false)
    if rh4b != ok || h4b != pool.NONE { os.exit(4i32) }
    let (t4c, _, _, _) = pool.stats(&p)
    if t4c != 0usize { os.exit(4i32) }
    if pool.validate_due(&p, 0u32, 600u64) { os.exit(4i32) }

    // 5: queued waiters past connection_timeout.
    let (p5, pe5) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..], since[..], config(0usize, 1usize, 0u64, 0u64, 60u64))
    if pe5 != ok { os.exit(5i32) }
    p = p5
    let (i5, _, _) = pool.acquire(&p, 1u32, 0u64)
    if pool.attach(&p, i5, 1u64, 0u64) != ok { os.exit(5i32) }
    let (_, o5, _) = pool.acquire(&p, 1u32, 0u64)
    if o5 != .Acquired { os.exit(5i32) }
    let (_, o5b, _) = pool.acquire(&p, 2u32, 5u64)
    let (_, o5c, _) = pool.acquire(&p, 3u32, 20u64)
    if o5b != .Queued || o5c != .Queued { os.exit(5i32) }
    if pool.timeouts(&p, 64u64, out[..]) != 0usize { os.exit(5i32) }
    if pool.timeouts(&p, 80u64, out[..]) != 2usize || out[0] != 2u32 || out[1] != 3u32 { os.exit(5i32) }
    let (_, o5d, e5d) = pool.acquire(&p, 3u32, 81u64)
    let (t5, id5, b5, q5) = pool.stats(&p)
    if e5d != ok || o5d != .Queued || t5 != 1usize || id5 != 0usize || b5 != 1usize || q5 != 1usize { os.exit(5i32) }

    // 6: the 300-event script's outcome fold and final stats equal the replica.
    let (p6, pe6) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..], since[..], config(1usize, 4usize, 500u64, 120u64, 60u64))
    if pe6 != ok { os.exit(6i32) }
    p = p6
    var seed = 12345u64
    var t = 0u64
    var h = 0xcbf29ce484222325u64
    var step = 0usize
    var cands: [4]u32 = zero
    while step < 300usize {
        seed = seed *% 6364136223846793005u64 +% 1442695040888963407u64
        let r = seed >> 33u32
        let kind = r % 8u64
        if kind < 3u64 {
            let wid = u32((r >> 8u32) % 6u64 + 1u64)
            let (i6, o6, e6) = pool.acquire(&p, wid, t)
            if e6 == pool.Full {
                h = fold(h, 5u64)
            } else if o6 == .Acquired {
                h = fold(fold(h, 1u64), u64(i6))
            } else if o6 == .NeedsCreate {
                if pool.attach(&p, i6, 1000u64 + u64(step), t) != ok { os.exit(6i32) }
                h = fold(fold(h, 2u64), u64(i6))
            } else if o6 == .Queued {
                h = fold(h, 3u64)
            } else {
                h = fold(h, 4u64)
            }
        } else if kind < 6u64 {
            var n = 0usize
            var j = 0usize
            while j < 4usize {
                if p.state[j] == pool.IN_USE {
                    cands[n] = u32(j)
                    n += 1usize
                }
                j += 1usize
            }
            if n == 0usize {
                h = fold(h, 6u64)
            } else {
                let pick = cands[usize((r >> 8u32) % u64(n))]
                let broken = ((r >> 16u32) % 10u64) == 0u64
                let (hw, he) = pool.release(&p, pick, t, broken)
                if he != ok { os.exit(6i32) }
                if hw != pool.NONE { h = fold(fold(h, 7u64), u64(hw)) } else { h = fold(h, 8u64) }
            }
        } else if kind == 6u64 {
            t += (r >> 8u32) % 300u64
            h = fold(h, 9u64)
        } else {
            let ne = pool.evict_expired(&p, t, out[..4usize])
            h = fold(fold(h, 10u64), u64(ne))
            var j = 0usize
            while j < ne {
                h = fold(h, u64(out[j]))
                j += 1usize
            }
            let nt = pool.timeouts(&p, t, out[..])
            h = fold(fold(h, 11u64), u64(nt))
            j = 0usize
            while j < nt {
                h = fold(h, u64(out[j]))
                j += 1usize
            }
            h = fold(fold(h, 12u64), u64(pool.warm(&p)))
            var due = 0u64
            if pool.validate_due(&p, u32((r >> 8u32) % 4u64), t) { due = 1u64 }
            h = fold(fold(h, 13u64), due)
        }
        step += 1usize
    }
    let (t6, id6, b6, q6) = pool.stats(&p)
    if h != 1782850722722251739u64 || t6 != 4usize || id6 != 1usize || b6 != 3usize || q6 != 0usize || t != 6019u64 { os.exit(6i32) }

    // 7: Full, Invalid, TooSmall.
    let (p7, pe7) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..2usize], since[..], config(0usize, 1usize, 0u64, 0u64, 60u64))
    if pe7 != ok { os.exit(7i32) }
    p = p7
    let (i7, _, _) = pool.acquire(&p, 1u32, 0u64)
    if pool.attach(&p, i7, 1u64, 0u64) != ok { os.exit(7i32) }
    let (_, o7, _) = pool.acquire(&p, 1u32, 0u64)
    let (_, o7b, _) = pool.acquire(&p, 2u32, 0u64)
    let (_, o7c, _) = pool.acquire(&p, 3u32, 0u64)
    let (_, _, e7d) = pool.acquire(&p, 4u32, 0u64)
    if o7 != .Acquired || o7b != .Queued || o7c != .Queued || e7d != pool.Full { os.exit(7i32) }
    let (h7a, _) = pool.release(&p, 0u32, 0u64, false)
    let (h7b, _) = pool.release(&p, 0u32, 0u64, false)
    if h7a != 2u32 || h7b != 3u32 { os.exit(7i32) }
    if pool.attach(&p, 0u32, 5u64, 0u64) != pool.Invalid { os.exit(7i32) }
    let (_, r7) = pool.release(&p, 7u32, 0u64, false)
    if r7 != pool.Invalid { os.exit(7i32) }
    if pool.close_all(&p) != 1usize { os.exit(7i32) }
    let (t7, _, _, q7) = pool.stats(&p)
    if t7 != 0usize || q7 != 0usize { os.exit(7i32) }
    let (_, x1) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..], since[..], config(0usize, 0usize, 0u64, 0u64, 60u64))
    let (_, x2) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..], since[..], config(3usize, 2usize, 0u64, 0u64, 60u64))
    let (_, x3) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..], since[..], config(0usize, 5usize, 0u64, 0u64, 60u64))
    let (_, x4) = pool.pool(handle[..], state[..], created[..], used[..], uses[..], waiters[..0usize], since[..], config(0usize, 4usize, 0u64, 0u64, 60u64))
    if x1 != pool.Invalid || x2 != pool.Invalid || x3 != pool.TooSmall || x4 != pool.TooSmall { os.exit(7i32) }

    try io.print("db pool ok\n")
    ret ok
}
