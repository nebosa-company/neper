// E-graphs with equality saturation (egg-style) over caller storage. An e-node
// is `(op, child_a, child_b)` with `none()` for an absent child; its index is
// also its e-class id, and classes merge through a union-find, so `find(g, x)`
// is the canonical class of any node or class id. A hashcons (open addressing
// over `table`) keeps `add` from duplicating a node; `merge` may leave it stale
// and `rebuild` restores congruence: children are canonicalised, duplicates
// merged and retired (`dead()` op) until nothing changes. Patterns are small
// trees over caller arrays whose op `variable(k)` (k < 4) binds a class;
// `ematch` enumerates every binding, `apply_rule` instantiates a right-hand side
// and merges, `saturate` repeats until a fixpoint or a cap, `extract` picks the
// cheapest term of a class bottom-up.

use e.algo.disjoint_set as dsu

error TooSmall
error Invalid

type EGraph = struct { node_op: []u32, node_a: []u32, node_b: []u32, sets: dsu.DisjointSet, table: []u32, nodes: usize, dead: usize }
type Pattern = struct { op: []const u32, a: []const u32, b: []const u32, root: u32 }
type Rule = struct { lhs: Pattern, rhs: Pattern }

// An absent child, and an unbound variable in a match record.
fn none() -> u32 { ret 4294967295u32 }
// The op of a retired duplicate; `node_count` excludes them.
fn dead() -> u32 { ret 4294967294u32 }
// The pattern op that binds variable `k` (k < 4); ops at or above `variable(0)` are reserved.
fn variable(k: u32) -> u32 { ret 4294967280u32 + k }
// Words per match record written by `ematch`: the class then four bindings.
fn match_words() -> usize { ret 5usize }
fn table_required(max_nodes: usize) -> usize { ret max_nodes * 2usize + 1usize }

// The node capacity is the shortest of the node and union-find arrays; the
// table needs `table_required` of that.
fn egraph(node_op: []u32, node_a: []u32, node_b: []u32, parent: []u32, rank: []u8, table: []u32) -> (EGraph, err) {
    var cap = node_op.len
    if node_a.len < cap { cap = node_a.len }
    if node_b.len < cap { cap = node_b.len }
    if parent.len < cap { cap = parent.len }
    if rank.len < cap { cap = rank.len }
    if table.len < table_required(cap) { ret (zero, TooSmall) }
    let (sets, set_error) = dsu.init(parent, rank, cap)
    if set_error != ok { ret (zero, set_error) }
    var i = 0usize
    while i < table.len {
        table[i] = 0u32
        i += 1usize
    }
    ret (EGraph { node_op: node_op[..cap], node_a: node_a[..cap], node_b: node_b[..cap], sets: sets, table: table, nodes: 0usize, dead: 0usize }, ok)
}

fn find(g: *EGraph, x: u32) -> u32 { ret dsu.find(&g.sets, x) }

fn canon(g: *EGraph, x: u32) -> u32 {
    if x == none() { ret x }
    ret dsu.find(&g.sets, x)
}

fn class_count(g: *EGraph) -> usize { ret dsu.set_count(&g.sets) - (g.node_op.len - g.nodes) }

fn node_count(g: *EGraph) -> usize { ret g.nodes - g.dead }

// The table slot for `(op, a, b)`: `true` when it holds a matching node.
fn probe(g: *EGraph, op: u32, a: u32, b: u32) -> (usize, bool) {
    let h = (op *% 2654435761u32) ^ (a *% 2246822519u32) ^ (b *% 3266489917u32)
    var slot = usize(h) % g.table.len
    while g.table[slot] != 0u32 {
        let n = usize(g.table[slot] - 1u32)
        if g.node_op[n] == op && g.node_a[n] == a && g.node_b[n] == b { ret (slot, true) }
        slot += 1usize
        if slot == g.table.len { slot = 0usize }
    }
    ret (slot, false)
}

// The class of `(op, a, b)`, added when no equal node exists.
fn add(g: *EGraph, op: u32, a: u32, b: u32) -> (u32, err) {
    if op >= variable(0u32) { ret (0u32, Invalid) }
    if a != none() && usize(a) >= g.nodes { ret (0u32, Invalid) }
    if b != none() && usize(b) >= g.nodes { ret (0u32, Invalid) }
    let ca = canon(g, a)
    let cb = canon(g, b)
    let (slot, hit) = probe(g, op, ca, cb)
    if hit { ret (find(g, g.table[slot] - 1u32), ok) }
    if g.nodes >= g.node_op.len { ret (0u32, TooSmall) }
    let i = g.nodes
    g.nodes += 1usize
    g.node_op[i] = op
    g.node_a[i] = ca
    g.node_b[i] = cb
    g.table[slot] = u32(i) + 1u32
    ret (u32(i), ok)
}

fn add_leaf(g: *EGraph, op: u32) -> (u32, err) {
    let (c, e) = add(g, op, none(), none())
    ret (c, e)
}

// Unites the classes; answers the surviving class id. Call `rebuild` afterwards.
fn merge(g: *EGraph, x: u32, y: u32) -> u32 {
    let _ = dsu.join(&g.sets, x, y)
    ret find(g, x)
}

// Restores congruence: re-hashconses every live node over canonical children,
// merging and retiring duplicates, until a pass changes nothing.
fn rebuild(g: *EGraph) {
    // ponytail: every pass rescans all nodes; egg walks a dirty-class worklist.
    var merged = true
    while merged {
        merged = false
        var t = 0usize
        while t < g.table.len {
            g.table[t] = 0u32
            t += 1usize
        }
        var i = 0usize
        while i < g.nodes {
            if g.node_op[i] != dead() {
                g.node_a[i] = canon(g, g.node_a[i])
                g.node_b[i] = canon(g, g.node_b[i])
                let (slot, hit) = probe(g, g.node_op[i], g.node_a[i], g.node_b[i])
                if hit {
                    let _ = dsu.join(&g.sets, u32(i), g.table[slot] - 1u32)
                    g.node_op[i] = dead()
                    g.dead += 1usize
                    merged = true
                } else {
                    g.table[slot] = u32(i) + 1u32
                }
            }
            i += 1usize
        }
    }
}

// Every match of `pat` in the graph, `match_words()` words each: the matched
// class then the classes bound to variables 0..3 (`none()` when unused).
fn ematch(g: *EGraph, pat: Pattern, matches: []u32) -> (usize, err) {
    var gp: [32]u32 = zero
    var gc: [32]u32 = zero
    var bind: [4]u32 = zero
    var found = 0usize
    var r = 0usize
    while r < g.nodes {
        if find(g, u32(r)) == u32(r) {
            bind[0usize] = none()
            bind[1usize] = none()
            bind[2usize] = none()
            bind[3usize] = none()
            gp[0usize] = pat.root
            gc[0usize] = u32(r)
            let e = match_goals(g, pat, gp[..], gc[..], 1usize, bind[..], u32(r), matches, &found)
            if e != ok { ret (found, e) }
        }
        r += 1usize
    }
    ret (found, ok)
}

// Solves the goal stack `(gp, gc)[..count]` of (pattern node, class) pairs by
// backtracking; each solution appends a record to `matches`.
fn match_goals(g: *EGraph, pat: Pattern, gp: []u32, gc: []u32, count: usize, bind: []u32, root: u32, matches: []u32, found: *usize) -> err {
    // ponytail: naive e-matching, a full node scan per goal; upgrade is relational e-matching.
    if count == 0usize {
        let base = *found * match_words()
        if base + match_words() > matches.len { ret TooSmall }
        matches[base] = root
        var k = 0usize
        while k < 4usize {
            matches[base + 1usize + k] = bind[k]
            k += 1usize
        }
        *found += 1usize
        ret ok
    }
    let p = usize(gp[count - 1usize])
    let c = find(g, gc[count - 1usize])
    let op = pat.op[p]
    if op >= variable(0u32) {
        let k = usize(op - variable(0u32))
        if k >= 4usize { ret Invalid }
        if bind[k] != none() {
            if find(g, bind[k]) != c { ret ok }
            ret match_goals(g, pat, gp, gc, count - 1usize, bind, root, matches, found)
        }
        bind[k] = c
        let e = match_goals(g, pat, gp, gc, count - 1usize, bind, root, matches, found)
        bind[k] = none()
        ret e
    }
    var i = 0usize
    while i < g.nodes {
        if g.node_op[i] == op && find(g, u32(i)) == c {
            let has_a = pat.a[p] != none()
            let has_b = pat.b[p] != none()
            if has_a == (g.node_a[i] != none()) && has_b == (g.node_b[i] != none()) {
                var n = count - 1usize
                if has_a {
                    if n >= gp.len { ret TooSmall }
                    gp[n] = pat.a[p]
                    gc[n] = g.node_a[i]
                    n += 1usize
                }
                if has_b {
                    if n >= gp.len { ret TooSmall }
                    gp[n] = pat.b[p]
                    gc[n] = g.node_b[i]
                    n += 1usize
                }
                let e = match_goals(g, pat, gp, gc, n, bind, root, matches, found)
                if e != ok { ret e }
                gp[count - 1usize] = u32(p)
                gc[count - 1usize] = c
            }
        }
        i += 1usize
    }
    ret ok
}

// The class of pattern node `p` built under `bind` (four words).
fn instantiate(g: *EGraph, pat: Pattern, p: u32, bind: []const u32) -> (u32, err) {
    let op = pat.op[usize(p)]
    if op >= variable(0u32) {
        let k = usize(op - variable(0u32))
        if k >= 4usize || bind[k] == none() { ret (0u32, Invalid) }
        ret (bind[k], ok)
    }
    var a = none()
    var b = none()
    if pat.a[usize(p)] != none() {
        let (ca, ea) = instantiate(g, pat, pat.a[usize(p)], bind)
        if ea != ok { ret (0u32, ea) }
        a = ca
    }
    if pat.b[usize(p)] != none() {
        let (cb, eb) = instantiate(g, pat, pat.b[usize(p)], bind)
        if eb != ok { ret (0u32, eb) }
        b = cb
    }
    let (c, e) = add(g, op, a, b)
    ret (c, e)
}

// Instantiates `rule.rhs` under each of the `count` records in `matches` (from
// `ematch` of `rule.lhs`) and merges it with the matched class.
fn apply_rule(g: *EGraph, rule: Rule, matches: []const u32, count: usize) -> err {
    var m = 0usize
    while m < count {
        let base = m * match_words()
        let (c, e) = instantiate(g, rule.rhs, rule.rhs.root, matches[base + 1usize..base + match_words()])
        if e != ok { ret e }
        let _ = merge(g, matches[base], c)
        m += 1usize
    }
    ret ok
}

// Repeats {match every rule, apply every match, rebuild} until an iteration adds
// no node and merges no class, or `max_iterations` ran; answers the iterations
// run. `matches` holds one iteration's records for all rules (up to 16 rules).
// A full graph stops after its rebuild with `TooSmall` and the merges so far.
fn saturate(g: *EGraph, rules: []const Rule, max_iterations: usize, matches: []u32) -> (usize, err) {
    if rules.len > 16usize { ret (0usize, Invalid) }
    var counts: [16]usize = zero
    var it = 0usize
    while it < max_iterations {
        let nodes0 = g.nodes
        let classes0 = class_count(g)
        var used = 0usize
        var r = 0usize
        while r < rules.len {
            let rule = rules[r]
            let (n, e) = ematch(g, rule.lhs, matches[used..])
            if e != ok { ret (it, e) }
            counts[r] = n
            used += n * match_words()
            r += 1usize
        }
        used = 0usize
        r = 0usize
        var stop = ok
        while r < rules.len && stop == ok {
            let rule = rules[r]
            stop = apply_rule(g, rule, matches[used..], counts[r])
            used += counts[r] * match_words()
            r += 1usize
        }
        rebuild(g)
        it += 1usize
        if stop != ok { ret (it, stop) }
        if g.nodes == nodes0 && class_count(g) == classes0 { ret (it, ok) }
    }
    ret (it, ok)
}

// The cheapest term cost of `root`'s class: a node costs `cost_of_op[op]` (1
// when `op` is past the slice, so an empty slice is egg's AstSize) plus its
// children's best. `best_cost`/`best_node` (`node_count` long, indexed by class)
// hold the fixpoint for `extract_write`.
fn extract(g: *EGraph, root: u32, cost_of_op: []const u32, best_cost: []u32, best_node: []u32) -> (u32, err) {
    if best_cost.len < g.nodes || best_node.len < g.nodes { ret (0u32, TooSmall) }
    if usize(root) >= g.nodes { ret (0u32, Invalid) }
    var i = 0usize
    while i < g.nodes {
        best_cost[i] = none()
        best_node[i] = none()
        i += 1usize
    }
    var changed = true
    while changed {
        changed = false
        i = 0usize
        while i < g.nodes {
            let op = g.node_op[i]
            if op != dead() {
                var cost = 1u32
                if usize(op) < cost_of_op.len { cost = cost_of_op[usize(op)] }
                var reachable = true
                if g.node_a[i] != none() {
                    let ca = best_cost[usize(find(g, g.node_a[i]))]
                    if ca == none() { reachable = false } else { cost += ca }
                }
                if reachable && g.node_b[i] != none() {
                    let cb = best_cost[usize(find(g, g.node_b[i]))]
                    if cb == none() { reachable = false } else { cost += cb }
                }
                let c = usize(find(g, u32(i)))
                if reachable && cost < best_cost[c] {
                    best_cost[c] = cost
                    best_node[c] = u32(i)
                    changed = true
                }
            }
            i += 1usize
        }
    }
    let best = best_cost[usize(find(g, root))]
    if best == none() { ret (0u32, Invalid) }
    ret (best, ok)
}

// Writes the extracted term of `class` in preorder: `out_a`/`out_b` index the
// output arrays (`none()` when absent). Answers the node count.
fn extract_write(g: *EGraph, class: u32, best_node: []const u32, out_op: []u32, out_a: []u32, out_b: []u32) -> (usize, err) {
    var count = 0usize
    let (_, e) = write_tree(g, class, best_node, out_op, out_a, out_b, &count)
    ret (count, e)
}

fn write_tree(g: *EGraph, class: u32, best_node: []const u32, out_op: []u32, out_a: []u32, out_b: []u32, count: *usize) -> (u32, err) {
    let idx = *count
    if idx >= out_op.len || idx >= out_a.len || idx >= out_b.len { ret (0u32, TooSmall) }
    let n = best_node[usize(find(g, class))]
    if n == none() { ret (0u32, Invalid) }
    *count += 1usize
    out_op[idx] = g.node_op[usize(n)]
    out_a[idx] = none()
    out_b[idx] = none()
    if g.node_a[usize(n)] != none() {
        let (ia, ea) = write_tree(g, g.node_a[usize(n)], best_node, out_op, out_a, out_b, count)
        if ea != ok { ret (0u32, ea) }
        out_a[idx] = ia
    }
    if g.node_b[usize(n)] != none() {
        let (ib, eb) = write_tree(g, g.node_b[usize(n)], best_node, out_op, out_a, out_b, count)
        if eb != ok { ret (0u32, eb) }
        out_b[idx] = ib
    }
    ret (u32(idx), ok)
}
