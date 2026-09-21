// Segment trees over caller storage.
//
// `SegmentTree[T]` folds any associative `combine` with an identity: point
// updates and range queries in `O(log n)` over `4 * n` nodes. `Lazy` is the
// `i64` tree with range addition and range sum and minimum, its pending
// additions pushed down on demand. `Persistent` keeps every version: a point
// update makes `O(log n)` fresh nodes from a pool and answers the new root, and
// any old root still queries the array as it was.

type SegmentTree[T: type] = struct { nodes: []T, count: usize, identity: T }
type Lazy = struct { sums: []i64, mins: []i64, pending: []i64, count: usize }
type Persistent = struct { left: []u32, right: []u32, sums: []i64, used: usize, count: usize }
error TooSmall
error Invalid

// Builds the tree over `values` in `O(n)`; `nodes.len >= 4 * values.len`.
fn build[T: type, Ctx: type](nodes: []T, values: []const T, identity: T, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> (SegmentTree[T], err) {
    let n = values.len
    if nodes.len < 4usize * n { ret (zero, TooSmall) }
    var t = SegmentTree[T] { nodes: nodes, count: n, identity: identity }
    if n > 0usize { build_node[T, Ctx](&t, 1usize, 0usize, n - 1usize, values, ctx, combine) }
    ret (t, ok)
}

fn build_node[T: type, Ctx: type](t: *SegmentTree[T], node: usize, low: usize, high: usize, values: []const T, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) {
    if low == high {
        t.nodes[node] = values[low]
        ret
    }
    let middle = low + (high - low) / 2usize
    build_node[T, Ctx](t, node * 2usize, low, middle, values, ctx, combine)
    build_node[T, Ctx](t, node * 2usize + 1usize, middle + 1usize, high, values, ctx, combine)
    t.nodes[node] = combine(ctx, t.nodes[node * 2usize], t.nodes[node * 2usize + 1usize])
}

// Sets element `index` and recombines the path to the root.
fn update[T: type, Ctx: type](t: *SegmentTree[T], index: usize, value: T, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> err {
    if index >= t.count { ret Invalid }
    var node = 1usize
    var low = 0usize
    var high = t.count - 1usize
    // Descend, remembering the path through the node numbering.
    while low != high {
        let middle = low + (high - low) / 2usize
        if index <= middle {
            node = node * 2usize
            high = middle
        } else {
            node = node * 2usize + 1usize
            low = middle + 1usize
        }
    }
    t.nodes[node] = value
    while node > 1usize {
        node = node / 2usize
        t.nodes[node] = combine(ctx, t.nodes[node * 2usize], t.nodes[node * 2usize + 1usize])
    }
    ret ok
}

// The fold over `low..high`; the identity for an empty range.
fn query[T: type, Ctx: type](t: *const SegmentTree[T], low: usize, high: usize, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> (T, err) {
    if high > t.count { ret (t.identity, Invalid) }
    if low >= high { ret (t.identity, ok) }
    ret (query_node[T, Ctx](t, 1usize, 0usize, t.count - 1usize, low, high - 1usize, ctx, combine), ok)
}

fn query_node[T: type, Ctx: type](t: *const SegmentTree[T], node: usize, low: usize, high: usize, from: usize, to: usize, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> T {
    if to < low || high < from { ret t.identity }
    if from <= low && high <= to { ret t.nodes[node] }
    let middle = low + (high - low) / 2usize
    let left = query_node[T, Ctx](t, node * 2usize, low, middle, from, to, ctx, combine)
    let right = query_node[T, Ctx](t, node * 2usize + 1usize, middle + 1usize, high, from, to, ctx, combine)
    ret combine(ctx, left, right)
}

// The lazy tree over `values`; each of the three slices needs `4 * values.len`.
fn lazy_build(sums: []i64, mins: []i64, pending: []i64, values: []const i64) -> (Lazy, err) {
    let n = values.len
    if sums.len < 4usize * n || mins.len < 4usize * n || pending.len < 4usize * n { ret (zero, TooSmall) }
    var t = Lazy { sums: sums, mins: mins, pending: pending, count: n }
    var i = 0usize
    while i < 4usize * n {
        pending[i] = 0i64
        i += 1usize
    }
    if n > 0usize { lazy_build_node(&t, 1usize, 0usize, n - 1usize, values) }
    ret (t, ok)
}

fn lazy_build_node(t: *Lazy, node: usize, low: usize, high: usize, values: []const i64) {
    if low == high {
        t.sums[node] = values[low]
        t.mins[node] = values[low]
        ret
    }
    let middle = low + (high - low) / 2usize
    lazy_build_node(t, node * 2usize, low, middle, values)
    lazy_build_node(t, node * 2usize + 1usize, middle + 1usize, high, values)
    t.sums[node] = t.sums[node * 2usize] + t.sums[node * 2usize + 1usize]
    t.mins[node] = t.mins[node * 2usize]
    if t.mins[node * 2usize + 1usize] < t.mins[node] { t.mins[node] = t.mins[node * 2usize + 1usize] }
}

// Applies a pending addition to a node covering `width` elements.
fn lazy_apply(t: *Lazy, node: usize, width: usize, delta: i64) {
    t.sums[node] += delta * i64(width)
    t.mins[node] += delta
    t.pending[node] += delta
}

fn lazy_push(t: *Lazy, node: usize, low: usize, high: usize) {
    if t.pending[node] == 0i64 { ret }
    let middle = low + (high - low) / 2usize
    lazy_apply(t, node * 2usize, middle - low + 1usize, t.pending[node])
    lazy_apply(t, node * 2usize + 1usize, high - middle, t.pending[node])
    t.pending[node] = 0i64
}

// Adds `delta` to every element in `low..high`.
fn lazy_add(t: *Lazy, low: usize, high: usize, delta: i64) -> err {
    if high > t.count { ret Invalid }
    if low >= high { ret ok }
    lazy_add_node(t, 1usize, 0usize, t.count - 1usize, low, high - 1usize, delta)
    ret ok
}

fn lazy_add_node(t: *Lazy, node: usize, low: usize, high: usize, from: usize, to: usize, delta: i64) {
    if to < low || high < from { ret }
    if from <= low && high <= to {
        lazy_apply(t, node, high - low + 1usize, delta)
        ret
    }
    lazy_push(t, node, low, high)
    let middle = low + (high - low) / 2usize
    lazy_add_node(t, node * 2usize, low, middle, from, to, delta)
    lazy_add_node(t, node * 2usize + 1usize, middle + 1usize, high, from, to, delta)
    t.sums[node] = t.sums[node * 2usize] + t.sums[node * 2usize + 1usize]
    t.mins[node] = t.mins[node * 2usize]
    if t.mins[node * 2usize + 1usize] < t.mins[node] { t.mins[node] = t.mins[node * 2usize + 1usize] }
}

// The sum over `low..high`.
fn lazy_sum(t: *Lazy, low: usize, high: usize) -> (i64, err) {
    if high > t.count { ret (0i64, Invalid) }
    if low >= high { ret (0i64, ok) }
    ret (lazy_sum_node(t, 1usize, 0usize, t.count - 1usize, low, high - 1usize), ok)
}

fn lazy_sum_node(t: *Lazy, node: usize, low: usize, high: usize, from: usize, to: usize) -> i64 {
    if to < low || high < from { ret 0i64 }
    if from <= low && high <= to { ret t.sums[node] }
    lazy_push(t, node, low, high)
    let middle = low + (high - low) / 2usize
    ret lazy_sum_node(t, node * 2usize, low, middle, from, to) + lazy_sum_node(t, node * 2usize + 1usize, middle + 1usize, high, from, to)
}

// The minimum over a non-empty `low..high`.
fn lazy_min(t: *Lazy, low: usize, high: usize) -> (i64, err) {
    if high > t.count || low >= high { ret (0i64, Invalid) }
    ret (lazy_min_node(t, 1usize, 0usize, t.count - 1usize, low, high - 1usize), ok)
}

fn lazy_min_node(t: *Lazy, node: usize, low: usize, high: usize, from: usize, to: usize) -> i64 {
    if from <= low && high <= to { ret t.mins[node] }
    lazy_push(t, node, low, high)
    let middle = low + (high - low) / 2usize
    if to <= middle { ret lazy_min_node(t, node * 2usize, low, middle, from, to) }
    if from > middle { ret lazy_min_node(t, node * 2usize + 1usize, middle + 1usize, high, from, to) }
    let left = lazy_min_node(t, node * 2usize, low, middle, from, to)
    let right = lazy_min_node(t, node * 2usize + 1usize, middle + 1usize, high, from, to)
    if right < left { ret right }
    ret left
}

// A persistent sum tree over `values`: the pool needs `2 * n` nodes for the
// first version plus `ceil(log2 n) + 1` per update. Answers the tree and its
// first root.
fn persistent_build(left: []u32, right: []u32, sums: []i64, values: []const i64) -> (Persistent, u32, err) {
    let n = values.len
    if n == 0usize || n > 2147483647usize { ret (zero, 0u32, Invalid) }
    if left.len < 2usize * n || right.len < 2usize * n || sums.len < 2usize * n { ret (zero, 0u32, TooSmall) }
    if left.len != right.len || left.len != sums.len { ret (zero, 0u32, Invalid) }
    var t = Persistent { left: left, right: right, sums: sums, used: 0usize, count: n }
    let root = persistent_build_node(&t, 0usize, n - 1usize, values)
    ret (t, root, ok)
}

fn persistent_build_node(t: *Persistent, low: usize, high: usize, values: []const i64) -> u32 {
    let node = t.used
    t.used += 1usize
    if low == high {
        t.left[node] = 0u32
        t.right[node] = 0u32
        t.sums[node] = values[low]
        ret u32(node)
    }
    let middle = low + (high - low) / 2usize
    let l = persistent_build_node(t, low, middle, values)
    let r = persistent_build_node(t, middle + 1usize, high, values)
    t.left[node] = l
    t.right[node] = r
    t.sums[node] = t.sums[usize(l)] + t.sums[usize(r)]
    ret u32(node)
}

// A new version with `delta` added at `index`; `root` is unchanged.
fn persistent_add(t: *Persistent, root: u32, index: usize, delta: i64) -> (u32, err) {
    if index >= t.count { ret (root, Invalid) }
    var depth = 1usize
    var span = 1usize
    while span < t.count {
        span = span * 2usize
        depth += 1usize
    }
    if t.used + depth > t.left.len { ret (root, TooSmall) }
    ret (persistent_add_node(t, root, 0usize, t.count - 1usize, index, delta), ok)
}

fn persistent_add_node(t: *Persistent, old: u32, low: usize, high: usize, index: usize, delta: i64) -> u32 {
    let node = t.used
    t.used += 1usize
    t.left[node] = t.left[usize(old)]
    t.right[node] = t.right[usize(old)]
    t.sums[node] = t.sums[usize(old)] + delta
    if low != high {
        let middle = low + (high - low) / 2usize
        if index <= middle {
            t.left[node] = persistent_add_node(t, t.left[usize(old)], low, middle, index, delta)
        } else {
            t.right[node] = persistent_add_node(t, t.right[usize(old)], middle + 1usize, high, index, delta)
        }
    }
    ret u32(node)
}

// The sum over `low..high` in the version at `root`.
fn persistent_sum(t: *const Persistent, root: u32, low: usize, high: usize) -> (i64, err) {
    if high > t.count { ret (0i64, Invalid) }
    if low >= high { ret (0i64, ok) }
    ret (persistent_sum_node(t, root, 0usize, t.count - 1usize, low, high - 1usize), ok)
}

fn persistent_sum_node(t: *const Persistent, node: u32, low: usize, high: usize, from: usize, to: usize) -> i64 {
    if to < low || high < from { ret 0i64 }
    if from <= low && high <= to { ret t.sums[usize(node)] }
    let middle = low + (high - low) / 2usize
    ret persistent_sum_node(t, t.left[usize(node)], low, middle, from, to) + persistent_sum_node(t, t.right[usize(node)], middle + 1usize, high, from, to)
}
