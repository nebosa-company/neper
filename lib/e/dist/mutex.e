// Distributed mutual exclusion simulated over nodes given as indices; every
// message a node would send lands in a caller `Sent` pool in sending order
// (as many as fit, every one counted) and the caller delivers them with the
// `*_receive` calls. Ricart-Agrawala (`ra_request`, `ra_receive`,
// `ra_release`): a request carries a Lamport stamp, a node replies at once
// unless it is requesting with an earlier (stamp, id), in which case the
// reply is deferred until it releases; a node enters when it holds n-1
// replies, so a critical section costs exactly 2(n-1) messages. Raymond's
// token tree (`raymond_request`, `raymond_receive`, `raymond_release`): each
// node points at the neighbour towards the token (`holder`, itself when it
// holds it) and keeps a FIFO of requesters; a request travels up the tree
// once per node that was not already asking and the token travels back
// down, so a critical section costs O(tree height) messages.

type Kind = enum u8 { Request, Reply, Token }
type Message = struct { kind: Kind, from: u32, to: u32, stamp: u64 }
type Sent = struct { out: []Message, count: usize }
type RaNode = struct { clock: u64, requesting: bool, stamp: u64, replies: usize, in_cs: bool }
type Ra = struct { nodes: []RaNode, deferred: []bool }
type RayNode = struct { holder: u32, asked: bool, in_cs: bool, head: usize, count: usize }
type Raymond = struct { nodes: []RayNode, queue: []u32 }
error TooSmall
error Invalid

fn sent(out: []Message) -> Sent { ret Sent { out: out, count: 0usize } }

fn push(s: *Sent, kind: Kind, from: usize, to: usize, stamp: u64) {
    if s.count < s.out.len { s.out[s.count] = Message { kind: kind, from: u32(from), to: u32(to), stamp: stamp } }
    s.count += 1usize
}

// `nodes` holds one record per node and `deferred` n*n flags.
fn ra(nodes: []RaNode, deferred: []bool) -> (Ra, err) {
    let n = nodes.len
    if deferred.len < n * n { ret (Ra { nodes: nodes, deferred: deferred }, TooSmall) }
    var i = 0usize
    while i < n {
        nodes[i] = RaNode { clock: 0u64, requesting: false, stamp: 0u64, replies: 0usize, in_cs: false }
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        deferred[i] = false
        i += 1usize
    }
    ret (Ra { nodes: nodes, deferred: deferred }, ok)
}

// Node `i` asks for the critical section: a stamped Request to every other node.
fn ra_request(r: *Ra, i: usize, s: *Sent) {
    r.nodes[i].clock += 1u64
    r.nodes[i].stamp = r.nodes[i].clock
    r.nodes[i].requesting = true
    r.nodes[i].replies = 0usize
    var j = 0usize
    while j < r.nodes.len {
        if j != i { push(s, .Request, i, j, r.nodes[i].stamp) }
        j += 1usize
    }
}

// Deliver `m` to its `to` node; answers whether that node just entered.
fn ra_receive(r: *Ra, m: Message, s: *Sent) -> bool {
    let n = r.nodes.len
    let i = usize(m.to)
    let j = usize(m.from)
    if m.kind == .Request {
        if m.stamp > r.nodes[i].clock { r.nodes[i].clock = m.stamp }
        r.nodes[i].clock += 1u64
        let mine_first = r.nodes[i].requesting && (r.nodes[i].stamp < m.stamp || (r.nodes[i].stamp == m.stamp && i < j))
        if mine_first { r.deferred[i * n + j] = true } else { push(s, .Reply, i, j, r.nodes[i].clock) }
        ret false
    }
    if m.kind == .Reply {
        r.nodes[i].replies += 1usize
        if r.nodes[i].requesting && r.nodes[i].replies == n - 1usize {
            r.nodes[i].in_cs = true
            ret true
        }
    }
    ret false
}

// Node `i` leaves the critical section and answers every deferred request.
fn ra_release(r: *Ra, i: usize, s: *Sent) {
    let n = r.nodes.len
    r.nodes[i].in_cs = false
    r.nodes[i].requesting = false
    var j = 0usize
    while j < n {
        if r.deferred[i * n + j] {
            r.deferred[i * n + j] = false
            push(s, .Reply, i, j, r.nodes[i].clock)
        }
        j += 1usize
    }
}

// `parent[i]` is the neighbour towards the token (`root` points at itself);
// `queue` holds n*n slots.
fn raymond(nodes: []RayNode, queue: []u32, parent: []const u32, root: usize) -> (Raymond, err) {
    let n = nodes.len
    let t = Raymond { nodes: nodes, queue: queue }
    if queue.len < n * n || parent.len != n || root >= n { ret (t, TooSmall) }
    var i = 0usize
    while i < n {
        if usize(parent[i]) >= n { ret (t, Invalid) }
        nodes[i] = RayNode { holder: parent[i], asked: false, in_cs: false, head: 0usize, count: 0usize }
        i += 1usize
    }
    nodes[root].holder = u32(root)
    ret (t, ok)
}

fn enqueue(t: *Raymond, i: usize, who: usize) {
    let n = t.nodes.len
    t.queue[i * n + (t.nodes[i].head + t.nodes[i].count) % n] = u32(who)
    t.nodes[i].count += 1usize
}

fn dequeue(t: *Raymond, i: usize) -> usize {
    let n = t.nodes.len
    let who = usize(t.queue[i * n + t.nodes[i].head])
    t.nodes[i].head = (t.nodes[i].head + 1usize) % n
    t.nodes[i].count -= 1usize
    ret who
}

// Raymond's two rules after any event at `i`; answers whether `i` entered.
fn settle(t: *Raymond, i: usize, s: *Sent) -> bool {
    var entered = false
    if usize(t.nodes[i].holder) == i && !t.nodes[i].in_cs && t.nodes[i].count > 0usize {
        let who = dequeue(t, i)
        t.nodes[i].holder = u32(who)
        t.nodes[i].asked = false
        if who == i {
            t.nodes[i].in_cs = true
            entered = true
        } else {
            push(s, .Token, i, who, 0u64)
        }
    }
    if usize(t.nodes[i].holder) != i && t.nodes[i].count > 0usize && !t.nodes[i].asked {
        push(s, .Request, i, usize(t.nodes[i].holder), 0u64)
        t.nodes[i].asked = true
    }
    ret entered
}

// Node `i` asks for the critical section; answers whether it entered at once.
fn raymond_request(t: *Raymond, i: usize, s: *Sent) -> bool {
    enqueue(t, i, i)
    ret settle(t, i, s)
}

// Deliver `m` to its `to` node; answers whether that node just entered.
fn raymond_receive(t: *Raymond, m: Message, s: *Sent) -> bool {
    let i = usize(m.to)
    if m.kind == .Request { enqueue(t, i, usize(m.from)) }
    if m.kind == .Token { t.nodes[i].holder = u32(i) }
    ret settle(t, i, s)
}

// Node `i` leaves the critical section and passes the token on if asked.
fn raymond_release(t: *Raymond, i: usize, s: *Sent) {
    t.nodes[i].in_cs = false
    let _ = settle(t, i, s)
}

// ---- planned one-call forms -----------------------------------------------

// In a `schedule`, this entry delivers every pending message before the next request.
const DELIVER: u32 = 4294967295u32

fn ra_in_cs(r: *const Ra) -> usize {
    var n = 0usize
    var i = 0usize
    while i < r.nodes.len {
        if r.nodes[i].in_cs { n += 1usize }
        i += 1usize
    }
    ret n
}

fn ray_in_cs(t: *const Raymond) -> usize {
    var n = 0usize
    var i = 0usize
    while i < t.nodes.len {
        if t.nodes[i].in_cs { n += 1usize }
        i += 1usize
    }
    ret n
}

// Record `who` entering (alone) as entry `*entered`; TooSmall when `order` is full.
fn enter(order: []u32, entered: *usize, who: usize, in_cs: usize) -> err {
    if in_cs != 1usize { ret Invalid }
    if *entered >= order.len { ret TooSmall }
    order[*entered] = u32(who)
    *entered += 1usize
    ret ok
}

// Deliver everything pending in sending order; a node that enters leaves at once.
fn ra_deliver(r: *Ra, s: *Sent, head: *usize, order: []u32, entered: *usize) -> err {
    while *head < s.count {
        if *head >= s.out.len { ret TooSmall }
        let m = s.out[*head]
        *head += 1usize
        if ra_receive(r, m, s) {
            try enter(order, entered, usize(m.to), ra_in_cs(r))
            ra_release(r, usize(m.to), s)
        }
    }
    ret ok
}

fn ray_deliver(t: *Raymond, s: *Sent, head: *usize, order: []u32, entered: *usize) -> err {
    while *head < s.count {
        if *head >= s.out.len { ret TooSmall }
        let m = s.out[*head]
        *head += 1usize
        if raymond_receive(t, m, s) {
            try enter(order, entered, usize(m.to), ray_in_cs(t))
            raymond_release(t, usize(m.to), s)
        }
    }
    ret ok
}

// Ricart-Agrawala in one call: `schedule` names the requesting nodes in
// order (`DELIVER` delivers everything pending first; a final delivery is
// implicit), every node that enters leaves at once, and `order` receives
// the entry order. Answers how many entered; `s.count` is the message
// count. TooSmall when the pool or `order` overflowed, Invalid when a
// request names no node or two nodes were ever inside at once.
fn ricart_agrawala(nodes: []RaNode, deferred: []bool, schedule: []const u32, s: *Sent, order: []u32) -> (usize, err) {
    let (r0, e0) = ra(nodes, deferred)
    if e0 != ok { ret (0usize, e0) }
    var r = r0
    var entered = 0usize
    var head = 0usize
    var i = 0usize
    while i < schedule.len {
        if schedule[i] == DELIVER {
            let e = ra_deliver(&r, s, &head, order, &entered)
            if e != ok { ret (entered, e) }
        } else {
            if usize(schedule[i]) >= nodes.len { ret (entered, Invalid) }
            ra_request(&r, usize(schedule[i]), s)
        }
        i += 1usize
    }
    let e = ra_deliver(&r, s, &head, order, &entered)
    ret (entered, e)
}

// The Raymond token tree in one call, with the same `schedule` and answers
// as `ricart_agrawala`; a requester already holding the token enters at once.
fn raymond_tree(nodes: []RayNode, queue: []u32, parent: []const u32, root: usize, schedule: []const u32, s: *Sent, order: []u32) -> (usize, err) {
    let (t0, e0) = raymond(nodes, queue, parent, root)
    if e0 != ok { ret (0usize, e0) }
    var t = t0
    var entered = 0usize
    var head = 0usize
    var i = 0usize
    while i < schedule.len {
        if schedule[i] == DELIVER {
            let e = ray_deliver(&t, s, &head, order, &entered)
            if e != ok { ret (entered, e) }
        } else {
            let who = usize(schedule[i])
            if who >= nodes.len { ret (entered, Invalid) }
            if raymond_request(&t, who, s) {
                let e = enter(order, &entered, who, ray_in_cs(&t))
                if e != ok { ret (entered, e) }
                raymond_release(&t, who, s)
            }
        }
        i += 1usize
    }
    let e = ray_deliver(&t, s, &head, order, &entered)
    ret (entered, e)
}
