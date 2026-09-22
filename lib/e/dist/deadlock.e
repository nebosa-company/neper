// Deadlock detection over a wait-for graph of processes given as indices:
// an `Edge { from, to }` says `from` is blocked waiting on `to`.
// `wait_for_graph_cycle` is the centralised check, a three-colour DFS in
// node then edge order that answers whether a cycle exists and its length.
// `chandy_misra_haas` is the distributed edge-chasing algorithm for the AND
// model simulated in-process: every process has a `site`, the initiator
// sends a probe (initiator, from, to) along every wait-for edge that leaves
// its site (following same-site edges transitively first), a process that
// receives its first probe for that initiator does the same, and the
// initiator is deadlocked exactly when a probe comes back to it. The probes
// land in a caller FIFO pool in the order they were sent.

type Edge = struct { from: u32, to: u32 }
type Probe = struct { initiator: u32, from: u32, to: u32 }
error TooSmall
error Invalid

fn dfs(edges: []const Edge, n: usize, u: usize, colour: []usize, depth: []usize) -> (bool, usize) {
    colour[u] = 1usize
    var e = 0usize
    while e < edges.len {
        if usize(edges[e].from) == u {
            let v = usize(edges[e].to)
            if colour[v] == 1usize { ret (true, depth[u] - depth[v] + 1usize) }
            if colour[v] == 0usize {
                depth[v] = depth[u] + 1usize
                let (found, length) = dfs(edges, n, v, colour, depth)
                if found { ret (true, length) }
            }
        }
        e += 1usize
    }
    colour[u] = 2usize
    ret (false, 0usize)
}

// Answers (cycle found, its length); `scratch` holds at least `2 * n`
// entries. Invalid when an edge names a node past `n` or scratch is short.
fn wait_for_graph_cycle(edges: []const Edge, n: usize, scratch: []usize) -> (bool, usize, err) {
    if scratch.len < 2usize * n { ret (false, 0usize, Invalid) }
    var i = 0usize
    while i < edges.len {
        if usize(edges[i].from) >= n || usize(edges[i].to) >= n { ret (false, 0usize, Invalid) }
        i += 1usize
    }
    let colour = scratch[..n]
    let depth = scratch[n..2usize * n]
    i = 0usize
    while i < n {
        colour[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        if colour[i] == 0usize {
            depth[i] = 0usize
            let (found, length) = dfs(edges, n, i, colour, depth)
            if found { ret (true, length, ok) }
        }
        i += 1usize
    }
    ret (false, 0usize, ok)
}

type Chase = struct { edges: []const Edge, site: []const u32, initiator: u32, probes: []Probe, sent: usize, seen: []bool }

// Send a probe along every edge leaving `u`'s site that is reachable from
// `u` through same-site edges.
fn spread(c: *Chase, u: usize) {
    c.seen[u] = true
    var e = 0usize
    while e < c.edges.len {
        if usize(c.edges[e].from) == u {
            let v = usize(c.edges[e].to)
            if c.site[v] == c.site[u] {
                if !c.seen[v] { spread(c, v) }
            } else {
                if c.sent < c.probes.len { c.probes[c.sent] = Probe { initiator: c.initiator, from: u32(u), to: u32(v) } }
                c.sent += 1usize
            }
        }
        e += 1usize
    }
}

// Answers (deadlocked, probes sent, error) for `initiator`; `site` gives each
// process's site and `scratch` holds at least `2 * n` flags. TooSmall when
// the probe pool overflowed (the run stops there), Invalid on a bad graph.
fn chandy_misra_haas(edges: []const Edge, site: []const u32, initiator: usize, probes: []Probe, scratch: []bool) -> (bool, usize, err) {
    let n = site.len
    if initiator >= n || scratch.len < 2usize * n { ret (false, 0usize, Invalid) }
    var i = 0usize
    while i < edges.len {
        if usize(edges[i].from) >= n || usize(edges[i].to) >= n { ret (false, 0usize, Invalid) }
        i += 1usize
    }
    let dependent = scratch[..n]
    var c = Chase { edges: edges, site: site, initiator: u32(initiator), probes: probes, sent: 0usize, seen: scratch[n..2usize * n] }
    i = 0usize
    while i < n {
        dependent[i] = false
        c.seen[i] = false
        i += 1usize
    }
    spread(&c, initiator)
    var deadlocked = false
    var head = 0usize
    while head < c.sent {
        if head >= probes.len { ret (deadlocked, c.sent, TooSmall) }
        let k = usize(probes[head].to)
        head += 1usize
        if k == initiator {
            deadlocked = true
        } else if !dependent[k] {
            dependent[k] = true
            i = 0usize
            while i < n {
                c.seen[i] = false
                i += 1usize
            }
            spread(&c, k)
        }
    }
    ret (deadlocked, c.sent, ok)
}

const NONE: u32 = 4294967295u32

// The wait-for graph of a lock table: `holder[lock]` is the process holding
// it (NONE when free) and `waiting[process]` the lock it is blocked on (NONE
// when running); every waiter on a held lock is an edge to the holder, then
// `wait_for_graph_cycle` runs over it. Answers (edges built, cycle found,
// its length, error): TooSmall when `edges` lacks room, Invalid on a bad
// lock index or short scratch.
fn wait_for_graph(holder: []const u32, waiting: []const u32, edges: []Edge, scratch: []usize) -> (usize, bool, usize, err) {
    let n = waiting.len
    var count = 0usize
    var p = 0usize
    while p < n {
        let l = waiting[p]
        if l != NONE {
            if usize(l) >= holder.len { ret (count, false, 0usize, Invalid) }
            let h = holder[usize(l)]
            if h != NONE && usize(h) != p {
                if count >= edges.len { ret (count, false, 0usize, TooSmall) }
                edges[count] = Edge { from: u32(p), to: h }
                count += 1usize
            }
        }
        p += 1usize
    }
    let (found, length, e) = wait_for_graph_cycle(edges[..count], n, scratch)
    ret (count, found, length, e)
}
