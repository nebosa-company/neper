// `e.dist.mutex`: four Ricart-Agrawala nodes over a scripted schedule (two
// concurrent requests, then three more) enter in the order a Python replica
// computes, never two at once, at exactly 2(n-1) messages per entry with the
// whole message log folding to the replica's word; seven Raymond nodes on a
// binary tree do the same at the replica's message count. Each check exits
// with its own code.

use e.dist.mutex
use e.io
use e.mem
use e.os

fn kind_code(k: mutex.Kind) -> u64 {
    if k == .Request { ret 0u64 }
    if k == .Reply { ret 1u64 }
    ret 2u64
}

fn fold(s: *const mutex.Sent) -> u64 {
    var h = 0u64
    var i = 0usize
    while i < s.count {
        h = h *% 1000003u64 +% (kind_code(s.out[i].kind) * 4096u64 + u64(s.out[i].from) * 64u64 + u64(s.out[i].to))
        i += 1usize
    }
    ret h
}

fn ra_in_cs(r: *const mutex.Ra) -> usize {
    var n = 0usize
    var i = 0usize
    while i < r.nodes.len {
        if r.nodes[i].in_cs { n += 1usize }
        i += 1usize
    }
    ret n
}

fn ray_in_cs(t: *const mutex.Raymond) -> usize {
    var n = 0usize
    var i = 0usize
    while i < t.nodes.len {
        if t.nodes[i].in_cs { n += 1usize }
        i += 1usize
    }
    ret n
}

// Deliver everything pending; each node that enters leaves at once.
fn ra_drain(r: *mutex.Ra, s: *mutex.Sent, head: *usize, order: []usize, entered: *usize) -> bool {
    while *head < s.count {
        if *head >= s.out.len { ret false }
        let m = s.out[*head]
        *head += 1usize
        if mutex.ra_receive(r, m, s) {
            if ra_in_cs(r) != 1usize { ret false }
            order[*entered] = usize(m.to)
            *entered += 1usize
            mutex.ra_release(r, usize(m.to), s)
        }
    }
    ret true
}

fn ray_drain(t: *mutex.Raymond, s: *mutex.Sent, head: *usize, order: []usize, entered: *usize) -> bool {
    while *head < s.count {
        if *head >= s.out.len { ret false }
        let m = s.out[*head]
        *head += 1usize
        if mutex.raymond_receive(t, m, s) {
            if ray_in_cs(t) != 1usize { ret false }
            order[*entered] = usize(m.to)
            *entered += 1usize
            mutex.raymond_release(t, usize(m.to), s)
        }
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: Ricart-Agrawala over four nodes.
    var pool: [64]mutex.Message = zero
    var s = mutex.sent(pool[..])
    var ra_nodes: [4]mutex.RaNode = zero
    var deferred: [16]bool = zero
    let (r0, e1) = mutex.ra(ra_nodes[..], deferred[..])
    if e1 != ok { os.exit(1i32) }
    var r = r0
    var order: [8]usize = zero
    var entered = 0usize
    var head = 0usize
    mutex.ra_request(&r, 0usize, &s)
    mutex.ra_request(&r, 2usize, &s)
    if s.count != 6usize || !ra_drain(&r, &s, &head, order[..], &entered) { os.exit(1i32) }
    if entered != 2usize || s.count != 12usize || order[0usize] != 0usize || order[1usize] != 2usize { os.exit(1i32) }
    mutex.ra_request(&r, 1usize, &s)
    mutex.ra_request(&r, 3usize, &s)
    mutex.ra_request(&r, 0usize, &s)
    if !ra_drain(&r, &s, &head, order[..], &entered) { os.exit(1i32) }
    let want_ra = [5]usize { 0usize, 2usize, 0usize, 1usize, 3usize }
    if entered != 5usize || s.count != 30usize { os.exit(1i32) }
    var i = 0usize
    while i < 5usize {
        if order[i] != want_ra[i] { os.exit(1i32) }
        i += 1usize
    }
    if fold(&s) != 3074633797412637136u64 || ra_in_cs(&r) != 0usize { os.exit(1i32) }
    if r.nodes[0usize].clock != 6u64 || r.nodes[2usize].clock != 7u64 { os.exit(1i32) }
    var tiny: [2]bool = zero
    let (_, e2) = mutex.ra(ra_nodes[..], tiny[..])
    if e2 != mutex.TooSmall { os.exit(1i32) }

    // 2: Raymond's tree: 0 is the root with children 1 and 2, then 3 4 / 5 6.
    var ray_pool: [64]mutex.Message = zero
    var rs = mutex.sent(ray_pool[..])
    var ray_nodes: [7]mutex.RayNode = zero
    var queue: [49]u32 = zero
    let parent = [7]u32 { 0u32, 0u32, 0u32, 1u32, 1u32, 2u32, 2u32 }
    let (t0, e3) = mutex.raymond(ray_nodes[..], queue[..], parent[..], 0usize)
    if e3 != ok { os.exit(2i32) }
    var t = t0
    entered = 0usize
    head = 0usize
    if mutex.raymond_request(&t, 5usize, &rs) || mutex.raymond_request(&t, 3usize, &rs) { os.exit(2i32) }
    if !mutex.raymond_request(&t, 0usize, &rs) || ray_in_cs(&t) != 1usize { os.exit(2i32) }
    order[entered] = 0usize
    entered += 1usize
    mutex.raymond_release(&t, 0usize, &rs)
    if !ray_drain(&t, &rs, &head, order[..], &entered) || rs.count != 12usize || entered != 3usize { os.exit(2i32) }
    if mutex.raymond_request(&t, 4usize, &rs) || mutex.raymond_request(&t, 6usize, &rs) { os.exit(2i32) }
    if !ray_drain(&t, &rs, &head, order[..], &entered) { os.exit(2i32) }
    let want_ray = [5]usize { 0usize, 5usize, 3usize, 4usize, 6usize }
    if entered != 5usize || rs.count != 24usize { os.exit(2i32) }
    i = 0usize
    while i < 5usize {
        if order[i] != want_ray[i] { os.exit(2i32) }
        i += 1usize
    }
    if fold(&rs) != 8047156026161654552u64 || ray_in_cs(&t) != 0usize { os.exit(2i32) }
    let holders = [7]u32 { 2u32, 0u32, 6u32, 1u32, 1u32, 2u32, 6u32 }
    i = 0usize
    while i < 7usize {
        if t.nodes[i].holder != holders[i] || t.nodes[i].count != 0usize { os.exit(2i32) }
        i += 1usize
    }

    // 3: the token holder enters at once and hands over on release; bad shapes.
    if !mutex.raymond_request(&t, 6usize, &rs) || rs.count != 24usize { os.exit(3i32) }
    if mutex.raymond_request(&t, 2usize, &rs) || rs.count != 25usize { os.exit(3i32) }
    if mutex.raymond_receive(&t, rs.out[24usize], &rs) || rs.count != 25usize { os.exit(3i32) }
    mutex.raymond_release(&t, 6usize, &rs)
    if rs.count != 26usize || rs.out[25usize].kind != .Token || rs.out[25usize].to != 2u32 { os.exit(3i32) }
    let (_, e4) = mutex.raymond(ray_nodes[..], queue[..40usize], parent[..], 0usize)
    if e4 != mutex.TooSmall { os.exit(3i32) }
    let bad = [7]u32 { 0u32, 0u32, 9u32, 1u32, 1u32, 2u32, 2u32 }
    let (_, e5) = mutex.raymond(ray_nodes[..], queue[..], bad[..], 0usize)
    if e5 != mutex.Invalid { os.exit(3i32) }

    try io.print("dist mutex ok\n")
    ret ok
}
