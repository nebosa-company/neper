// Dynamic forests over caller storage. `LinkCut` is a link-cut tree: every
// preferred path is a splay tree ordered by depth with a lazy reversal flag,
// `access` makes the root-to-`v` path preferred, `make_root` everts by
// reversing that path, `link` and `cut` keep a forest, `connected` compares
// roots and `path_sum` aggregates `value` along a path in O(log n) amortised.
// `Euler` is an Euler tour tree: each tree's tour (one node per vertex, two
// per edge, one for each direction) is a splay sequence, so `ett_link`
// concatenates two tours, `ett_cut` splits one out and `ett_connected`
// compares sequence roots. Node 0 is the null node; vertices are `1..=n`.

type LinkCut = struct { n: usize, left: []u32, right: []u32, parent: []u32, rev: []bool, value: []i64, sum: []i64 }
type Euler = struct { n: usize, left: []u32, right: []u32, parent: []u32, edge_u: []u32, edge_v: []u32 }
error TooSmall
error Invalid

// A link-cut tree over vertices `1..=n` with the caller's `value` per vertex;
// every array needs `n + 1` slots.
fn link_cut(n: usize, left: []u32, right: []u32, parent: []u32, rev: []bool, value: []i64, sum: []i64) -> (LinkCut, err) {
    if left.len <= n || right.len <= n || parent.len <= n || rev.len <= n || value.len <= n || sum.len <= n { ret (zero, TooSmall) }
    var i = 0usize
    while i <= n {
        left[i] = 0u32
        right[i] = 0u32
        parent[i] = 0u32
        rev[i] = false
        sum[i] = value[i]
        i += 1usize
    }
    sum[0usize] = 0i64
    ret (LinkCut { n: n, left: left, right: right, parent: parent, rev: rev, value: value, sum: sum }, ok)
}

fn valid(t: *const LinkCut, v: u32) -> bool { ret v != 0u32 && usize(v) <= t.n }

fn is_root(t: *const LinkCut, x: u32) -> bool {
    let p = t.parent[usize(x)]
    ret p == 0u32 || (t.left[usize(p)] != x && t.right[usize(p)] != x)
}

fn push(t: *LinkCut, x: u32) {
    if !t.rev[usize(x)] { ret }
    let l = t.left[usize(x)]
    t.left[usize(x)] = t.right[usize(x)]
    t.right[usize(x)] = l
    if t.left[usize(x)] != 0u32 { t.rev[usize(t.left[usize(x)])] = !t.rev[usize(t.left[usize(x)])] }
    if t.right[usize(x)] != 0u32 { t.rev[usize(t.right[usize(x)])] = !t.rev[usize(t.right[usize(x)])] }
    t.rev[usize(x)] = false
}

fn update(t: *LinkCut, x: u32) {
    t.sum[usize(x)] = t.sum[usize(t.left[usize(x)])] + t.value[usize(x)] + t.sum[usize(t.right[usize(x)])]
}

fn push_path(t: *LinkCut, x: u32) {
    if !is_root(t, x) { push_path(t, t.parent[usize(x)]) }
    push(t, x)
}

// Rotate `x` above its parent; a grandparent that does not own the parent
// (a path-parent pointer) is left alone.
fn rotate(left: []u32, right: []u32, parent: []u32, x: u32) {
    let p = parent[usize(x)]
    let g = parent[usize(p)]
    if left[usize(p)] == x {
        left[usize(p)] = right[usize(x)]
        if right[usize(x)] != 0u32 { parent[usize(right[usize(x)])] = p }
        right[usize(x)] = p
    } else {
        right[usize(p)] = left[usize(x)]
        if left[usize(x)] != 0u32 { parent[usize(left[usize(x)])] = p }
        left[usize(x)] = p
    }
    parent[usize(p)] = x
    parent[usize(x)] = g
    if g != 0u32 {
        if left[usize(g)] == p { left[usize(g)] = x } else if right[usize(g)] == p { right[usize(g)] = x }
    }
}

fn rotate_up(t: *LinkCut, x: u32) {
    let p = t.parent[usize(x)]
    rotate(t.left, t.right, t.parent, x)
    update(t, p)
    update(t, x)
}

fn splay(t: *LinkCut, x: u32) {
    push_path(t, x)
    while !is_root(t, x) {
        let p = t.parent[usize(x)]
        if !is_root(t, p) {
            let g = t.parent[usize(p)]
            if (t.left[usize(g)] == p) == (t.left[usize(p)] == x) { rotate_up(t, p) } else { rotate_up(t, x) }
        }
        rotate_up(t, x)
    }
}

// Make the root-to-`v` path preferred with `v` at the root of its splay tree.
fn access(t: *LinkCut, v: u32) -> err {
    if !valid(t, v) { ret Invalid }
    var last = 0u32
    var y = v
    while y != 0u32 {
        splay(t, y)
        t.right[usize(y)] = last
        update(t, y)
        last = y
        y = t.parent[usize(y)]
    }
    splay(t, v)
    ret ok
}

// Evert: make `v` the root of its tree.
fn make_root(t: *LinkCut, v: u32) -> err {
    try access(t, v)
    t.rev[usize(v)] = !t.rev[usize(v)]
    ret ok
}

fn find_root(t: *LinkCut, v: u32) -> (u32, err) {
    let access_error = access(t, v)
    if access_error != ok { ret (0u32, access_error) }
    var y = v
    push(t, y)
    while t.left[usize(y)] != 0u32 {
        y = t.left[usize(y)]
        push(t, y)
    }
    splay(t, y)
    ret (y, ok)
}

fn connected(t: *LinkCut, u: u32, v: u32) -> bool {
    let (ru, ue) = find_root(t, u)
    let (rv, ve) = find_root(t, v)
    ret ue == ok && ve == ok && ru == rv
}

// Add the edge `u`-`v`; `Invalid` if they are already in one tree.
fn link(t: *LinkCut, u: u32, v: u32) -> err {
    if !valid(t, u) || !valid(t, v) || connected(t, u, v) { ret Invalid }
    try make_root(t, u)
    t.parent[usize(u)] = v
    ret ok
}

// Remove the edge `u`-`v`; `Invalid` if it is not an edge.
fn cut(t: *LinkCut, u: u32, v: u32) -> err {
    if !valid(t, u) || !valid(t, v) || u == v || !connected(t, u, v) { ret Invalid }
    try make_root(t, u)
    try access(t, v)
    if t.left[usize(v)] != u { ret Invalid }
    push(t, u)
    if t.left[usize(u)] != 0u32 || t.right[usize(u)] != 0u32 { ret Invalid }
    t.left[usize(v)] = 0u32
    t.parent[usize(u)] = 0u32
    update(t, v)
    ret ok
}

// The sum of `value` over the vertices of the `u`..`v` path.
fn path_sum(t: *LinkCut, u: u32, v: u32) -> (i64, err) {
    if !valid(t, u) || !valid(t, v) || !connected(t, u, v) { ret (0i64, Invalid) }
    let root_error = make_root(t, u)
    if root_error != ok { ret (0i64, root_error) }
    let access_error = access(t, v)
    if access_error != ok { ret (0i64, access_error) }
    ret (t.sum[usize(v)], ok)
}

fn set_value(t: *LinkCut, v: u32, x: i64) -> err {
    try access(t, v)
    t.value[usize(v)] = x
    update(t, v)
    ret ok
}

// An Euler tour tree over vertices `1..=n` with room for `edge_u.len` edges;
// `left`, `right` and `parent` need `n + 1 + 2 * edge_u.len` slots.
fn euler_tour_tree(n: usize, left: []u32, right: []u32, parent: []u32, edge_u: []u32, edge_v: []u32) -> (Euler, err) {
    let slots = n + 1usize + 2usize * edge_u.len
    if left.len < slots || right.len < slots || parent.len < slots || edge_v.len < edge_u.len { ret (zero, TooSmall) }
    var i = 0usize
    while i < slots {
        left[i] = 0u32
        right[i] = 0u32
        parent[i] = 0u32
        i += 1usize
    }
    i = 0usize
    while i < edge_u.len {
        edge_u[i] = 0u32
        i += 1usize
    }
    ret (Euler { n: n, left: left, right: right, parent: parent, edge_u: edge_u, edge_v: edge_v }, ok)
}

fn ett_splay(t: *Euler, x: u32) {
    while t.parent[usize(x)] != 0u32 {
        let p = t.parent[usize(x)]
        let g = t.parent[usize(p)]
        if g != 0u32 {
            if (t.left[usize(g)] == p) == (t.left[usize(p)] == x) { rotate(t.left, t.right, t.parent, p) } else { rotate(t.left, t.right, t.parent, x) }
        }
        rotate(t.left, t.right, t.parent, x)
    }
}

// The sequence `a` followed by `b` (either may be 0); answers the root.
fn concat(t: *Euler, a: u32, b: u32) -> u32 {
    if a == 0u32 { ret b }
    if b == 0u32 { ret a }
    var r = a
    while t.right[usize(r)] != 0u32 { r = t.right[usize(r)] }
    ett_splay(t, r)
    t.right[usize(r)] = b
    t.parent[usize(b)] = r
    ret r
}

// Rotate the tour of `v` cyclically so that it starts at `v`.
fn reroot(t: *Euler, v: u32) {
    ett_splay(t, v)
    let before = t.left[usize(v)]
    if before == 0u32 { ret }
    t.left[usize(v)] = 0u32
    t.parent[usize(before)] = 0u32
    let _ = concat(t, v, before)
}

fn ett_connected(t: *Euler, u: u32, v: u32) -> bool {
    if u == 0u32 || v == 0u32 || usize(u) > t.n || usize(v) > t.n { ret false }
    if u == v { ret true }
    ett_splay(t, u)
    ett_splay(t, v)
    ret t.parent[usize(u)] != 0u32
}

fn ett_link(t: *Euler, u: u32, v: u32) -> err {
    if u == 0u32 || v == 0u32 || usize(u) > t.n || usize(v) > t.n || ett_connected(t, u, v) { ret Invalid }
    // ponytail: linear scan for a free edge slot and for an edge on cut (O(m)); a map from (u, v) if m grows large.
    var k = 0usize
    while k < t.edge_u.len && t.edge_u[k] != 0u32 { k += 1usize }
    if k >= t.edge_u.len { ret TooSmall }
    t.edge_u[k] = u
    t.edge_v[k] = v
    let a = u32(t.n + 1usize + 2usize * k)
    let b = a + 1u32
    t.left[usize(a)] = 0u32
    t.right[usize(a)] = 0u32
    t.parent[usize(a)] = 0u32
    t.left[usize(b)] = 0u32
    t.right[usize(b)] = 0u32
    t.parent[usize(b)] = 0u32
    reroot(t, u)
    reroot(t, v)
    ett_splay(t, u)
    ett_splay(t, v)
    let _ = concat(t, concat(t, concat(t, u, a), v), b)
    ret ok
}

fn ett_cut(t: *Euler, u: u32, v: u32) -> err {
    var k = 0usize
    while k < t.edge_u.len && !((t.edge_u[k] == u && t.edge_v[k] == v) || (t.edge_u[k] == v && t.edge_v[k] == u)) { k += 1usize }
    if k >= t.edge_u.len { ret Invalid }
    t.edge_u[k] = 0u32
    let a = u32(t.n + 1usize + 2usize * k)
    let b = a + 1u32
    // Rotate the tour to start at `a`: [a, tour of v's side, b, tour of u's side].
    reroot(t, a)
    ett_splay(t, b)
    let before = t.left[usize(b)]
    let after = t.right[usize(b)]
    t.left[usize(b)] = 0u32
    t.right[usize(b)] = 0u32
    if before != 0u32 { t.parent[usize(before)] = 0u32 }
    if after != 0u32 { t.parent[usize(after)] = 0u32 }
    ett_splay(t, a)
    let rest = t.right[usize(a)]
    t.right[usize(a)] = 0u32
    if rest != 0u32 { t.parent[usize(rest)] = 0u32 }
    ret ok
}
