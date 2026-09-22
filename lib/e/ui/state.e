// Fine-grained reactivity over caller storage: a `signal` is a value cell,
// a `memo` a derived value recomputed only when an input changed, an
// `effect` a computation run for its side effects. Reading through `get`
// inside a running computation records a dependency edge; `set` marks the
// dependents dirty and `schedule_effects` runs every dirty node once in
// increasing height order (a node's height is one above its highest input),
// so a node never observes a mixed state. A memo whose value did not change
// does not wake its dependents; a computation re-records its inputs on
// every run, so dependencies are dynamic. Values are `i64`: the caller maps
// richer state through the node index. `Graph[Ctx]` is generic over the one
// context type its computations receive.

type Graph[Ctx: type] = struct { ctx: *Ctx, value: []i64, kind: []u8, height: []u32, dirty: []u8, runs: []u32, compute: []fn(*Ctx, *Graph[Ctx]) -> i64, run: []fn(*Ctx, *Graph[Ctx]), from: []u32, to: []u32, edge_count: usize, used: usize, running: u32, batch: u32, lost: usize }
error TooSmall
error Invalid

fn kind_signal() -> u8 { ret 0u8 }
fn kind_memo() -> u8 { ret 1u8 }
fn kind_effect() -> u8 { ret 2u8 }
fn kind_disposed() -> u8 { ret 3u8 }

// A graph over parallel node arrays (the shortest bounds the node count) and
// the edge arrays `from`/`to` (the shorter bounds the edge count).
fn graph[Ctx: type](ctx: *Ctx, value: []i64, kind: []u8, height: []u32, dirty: []u8, runs: []u32, compute: []fn(*Ctx, *Graph[Ctx]) -> i64, run: []fn(*Ctx, *Graph[Ctx]), from: []u32, to: []u32) -> (Graph[Ctx], err) {
    if value.len == 0usize || kind.len == 0usize || height.len == 0usize || dirty.len == 0usize || runs.len == 0usize || compute.len == 0usize || run.len == 0usize || from.len == 0usize || to.len == 0usize { ret (zero, TooSmall) }
    ret (Graph[Ctx] { ctx: ctx, value: value, kind: kind, height: height, dirty: dirty, runs: runs, compute: compute, run: run, from: from, to: to, edge_count: 0usize, used: 0usize, running: 0u32, batch: 0u32, lost: 0usize }, ok)
}

fn new_node[Ctx: type](g: *Graph[Ctx], kind: u8) -> (u32, err) {
    let id = g.used
    if id >= g.value.len || id >= g.kind.len || id >= g.height.len || id >= g.dirty.len || id >= g.runs.len || id >= g.compute.len || id >= g.run.len { ret (0u32, TooSmall) }
    g.used += 1usize
    g.value[id] = 0i64
    g.kind[id] = kind
    g.height[id] = 0u32
    g.dirty[id] = 0u8
    g.runs[id] = 0u32
    ret (u32(id), ok)
}

// A new signal holding `initial`.
fn signal[Ctx: type](g: *Graph[Ctx], initial: i64) -> (u32, err) {
    let (id, e) = new_node[Ctx](g, kind_signal())
    if e != ok { ret (0u32, e) }
    g.value[usize(id)] = initial
    ret (id, ok)
}

// The value of node `id`; inside a running computation the read is recorded
// as a dependency. An invalid `id` answers 0 (the next fallible entry point
// reports `TooSmall` when an edge could not be recorded).
fn get[Ctx: type](g: *Graph[Ctx], id: u32) -> i64 {
    if usize(id) >= g.used { ret 0i64 }
    if g.running != 0u32 { record_edge[Ctx](g, id, g.running - 1u32) }
    ret g.value[usize(id)]
}

fn record_edge[Ctx: type](g: *Graph[Ctx], from: u32, to: u32) {
    var i = 0usize
    while i < g.edge_count {
        if g.from[i] == from && g.to[i] == to { ret }
        i += 1usize
    }
    if g.edge_count >= g.from.len || g.edge_count >= g.to.len {
        g.lost += 1usize
        ret
    }
    g.from[g.edge_count] = from
    g.to[g.edge_count] = to
    g.edge_count += 1usize
}

// Drop every edge into `to` (when `into`) or touching `id` (otherwise).
fn drop_edges[Ctx: type](g: *Graph[Ctx], id: u32, into: bool) {
    var kept = 0usize
    var i = 0usize
    while i < g.edge_count {
        let goes = g.to[i] == id || (!into && g.from[i] == id)
        if !goes {
            g.from[kept] = g.from[i]
            g.to[kept] = g.to[i]
            kept += 1usize
        }
        i += 1usize
    }
    g.edge_count = kept
}

fn mark_dependents[Ctx: type](g: *Graph[Ctx], id: u32) {
    var i = 0usize
    while i < g.edge_count {
        if g.from[i] == id && g.kind[usize(g.to[i])] != kind_disposed() { g.dirty[usize(g.to[i])] = 1u8 }
        i += 1usize
    }
}

// Set signal `id` to `value`: dependents go dirty and, outside a batch, run
// at once. `Invalid` inside a computation or for a node that is no signal.
fn set[Ctx: type](g: *Graph[Ctx], id: u32, value: i64) -> err {
    if g.running != 0u32 || usize(id) >= g.used || g.kind[usize(id)] != kind_signal() { ret Invalid }
    if g.value[usize(id)] == value { ret ok }
    g.value[usize(id)] = value
    mark_dependents[Ctx](g, id)
    if g.batch == 0u32 { ret schedule_effects[Ctx](g) }
    ret ok
}

// Lift the dependents of `id` above it after its height rose.
fn raise_dependents[Ctx: type](g: *Graph[Ctx], id: u32) {
    var i = 0usize
    while i < g.edge_count {
        if g.from[i] == id && g.height[usize(g.to[i])] <= g.height[usize(id)] {
            g.height[usize(g.to[i])] = g.height[usize(id)] + 1u32
            raise_dependents[Ctx](g, g.to[i])
        }
        i += 1usize
    }
}

// Run node `id` once: its inputs are re-recorded, its height settled;
// answers whether a memo's value changed.
fn run_node[Ctx: type](g: *Graph[Ctx], id: u32) -> bool {
    let n = usize(id)
    drop_edges[Ctx](g, id, true)
    let previous = g.running
    g.running = id + 1u32
    g.runs[n] += 1u32
    var changed = false
    if g.kind[n] == kind_memo() {
        let compute = g.compute[n]
        let value = compute(g.ctx, g)
        changed = value != g.value[n]
        g.value[n] = value
    } else {
        let run = g.run[n]
        run(g.ctx, g)
    }
    g.running = previous
    var height = 0u32
    var i = 0usize
    while i < g.edge_count {
        if g.to[i] == id && g.height[usize(g.from[i])] + 1u32 > height { height = g.height[usize(g.from[i])] + 1u32 }
        i += 1usize
    }
    g.height[n] = height
    raise_dependents[Ctx](g, id)
    ret changed
}

// A derived value: `compute` runs once now to record its inputs and again
// whenever one of them changed.
fn memo[Ctx: type](g: *Graph[Ctx], compute: fn(*Ctx, *Graph[Ctx]) -> i64) -> (u32, err) {
    if g.running != 0u32 { ret (0u32, Invalid) }
    let (id, e) = new_node[Ctx](g, kind_memo())
    if e != ok { ret (0u32, e) }
    g.compute[usize(id)] = compute
    let _ = run_node[Ctx](g, id)
    if g.lost != 0usize { ret (id, TooSmall) }
    ret (id, ok)
}

// A side-effecting computation: `run` runs once now and again whenever one
// of the nodes it read changed.
fn effect[Ctx: type](g: *Graph[Ctx], run: fn(*Ctx, *Graph[Ctx])) -> (u32, err) {
    if g.running != 0u32 { ret (0u32, Invalid) }
    let (id, e) = new_node[Ctx](g, kind_effect())
    if e != ok { ret (0u32, e) }
    g.run[usize(id)] = run
    let _ = run_node[Ctx](g, id)
    if g.lost != 0usize { ret (id, TooSmall) }
    ret (id, ok)
}

// Defer scheduling until the matching `batch_end`; batches nest.
fn batch_begin[Ctx: type](g: *Graph[Ctx]) {
    g.batch += 1u32
}

// Close a batch; the outermost close runs the dirty nodes.
fn batch_end[Ctx: type](g: *Graph[Ctx]) -> err {
    if g.batch > 0u32 { g.batch -= 1u32 }
    if g.batch == 0u32 { ret schedule_effects[Ctx](g) }
    ret ok
}

// Run every dirty node once, lowest height first; a memo that kept its value
// leaves its dependents asleep. `TooSmall` when an edge could not be recorded.
fn schedule_effects[Ctx: type](g: *Graph[Ctx]) -> err {
    if g.running != 0u32 { ret Invalid }
    // ponytail: a linear scan per step, O(nodes * dirty); a height-bucketed queue if graphs grow past a few hundred nodes
    var found = true
    while found {
        found = false
        var best = 0usize
        var i = 0usize
        while i < g.used {
            if g.dirty[i] != 0u8 && (!found || g.height[i] < g.height[best]) {
                best = i
                found = true
            }
            i += 1usize
        }
        if found {
            g.dirty[best] = 0u8
            let changed = run_node[Ctx](g, u32(best))
            if changed && g.kind[best] == kind_memo() { mark_dependents[Ctx](g, u32(best)) }
        }
    }
    if g.lost != 0usize { ret TooSmall }
    ret ok
}

// Retire node `id`: it never runs again and no edge touches it.
fn dispose[Ctx: type](g: *Graph[Ctx], id: u32) -> err {
    if g.running != 0u32 || usize(id) >= g.used { ret Invalid }
    g.kind[usize(id)] = kind_disposed()
    g.dirty[usize(id)] = 0u8
    drop_edges[Ctx](g, id, false)
    ret ok
}

// How many times node `id` has run (0 for a signal or an unknown id).
fn run_count[Ctx: type](g: *const Graph[Ctx], id: u32) -> u32 {
    if usize(id) >= g.used { ret 0u32 }
    ret g.runs[usize(id)]
}

// The node's current height (0 for a signal).
fn height_of[Ctx: type](g: *const Graph[Ctx], id: u32) -> u32 {
    if usize(id) >= g.used { ret 0u32 }
    ret g.height[usize(id)]
}

// The number of recorded dependency edges.
fn edge_count[Ctx: type](g: *const Graph[Ctx]) -> usize { ret g.edge_count }
