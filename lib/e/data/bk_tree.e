// A BK-tree over a caller node pool for metric search: items of any type
// with a caller distance `d(ctx, a, b) -> u32` that is a metric (the
// triangle inequality prunes); a child hangs off its parent under the
// distance between them, children kept as a sibling list. `insert` adds
// an item, `search` visits every item within `radius` of a query, calling
// `on_hit(ctx, item, distance)` and answering the count.

type BkTree[T: type] = struct { items: []T, first_child: []u32, next_sibling: []u32, edge: []u32, used: usize }
error TooSmall

const NONE: u32 = 4294967295u32

fn bk_tree[T: type](items: []T, first_child: []u32, next_sibling: []u32, edge: []u32) -> BkTree[T] {
    ret BkTree[T] { items: items, first_child: first_child, next_sibling: next_sibling, edge: edge, used: 0usize }
}

fn insert[T: type, Ctx: type](t: *BkTree[T], item: T, ctx: *Ctx, distance: fn(*Ctx, T, T) -> u32) -> err {
    if t.used >= t.items.len || t.used >= t.first_child.len || t.used >= t.next_sibling.len || t.used >= t.edge.len { ret TooSmall }
    let id = u32(t.used)
    t.used += 1usize
    t.items[usize(id)] = item
    t.first_child[usize(id)] = NONE
    t.next_sibling[usize(id)] = NONE
    if id == 0u32 {
        t.edge[0usize] = 0u32
        ret ok
    }
    var node = 0u32
    var placing = true
    while placing {
        let d = distance(ctx, item, t.items[usize(node)])
        // A child under the same distance is descended into.
        var child = t.first_child[usize(node)]
        var found = NONE
        while child != NONE && found == NONE {
            if t.edge[usize(child)] == d { found = child }
            child = t.next_sibling[usize(child)]
        }
        if found == NONE {
            t.edge[usize(id)] = d
            t.next_sibling[usize(id)] = t.first_child[usize(node)]
            t.first_child[usize(node)] = id
            placing = false
        } else {
            node = found
        }
    }
    ret ok
}

// Every item within `radius` of `query`, in tree order; `stack.len` at
// least the node count bounds the walk. Answers the hits, or `TooSmall`
// when the stack overflows.
fn search[T: type, Ctx: type](t: *const BkTree[T], query: T, radius: u32, ctx: *Ctx, distance: fn(*Ctx, T, T) -> u32, on_hit: fn(*Ctx, T, u32), stack: []u32) -> (usize, err) {
    if t.used == 0usize { ret (0usize, ok) }
    if stack.len == 0usize { ret (0usize, TooSmall) }
    var top = 1usize
    stack[0usize] = 0u32
    var hits = 0usize
    while top > 0usize {
        top -= 1usize
        let node = stack[top]
        let d = distance(ctx, query, t.items[usize(node)])
        if d <= radius {
            on_hit(ctx, t.items[usize(node)], d)
            hits += 1usize
        }
        // Children whose edge lies within [d - radius, d + radius] may hold hits.
        var child = t.first_child[usize(node)]
        while child != NONE {
            let e = t.edge[usize(child)]
            if e + radius >= d && e <= d + radius {
                if top >= stack.len { ret (hits, TooSmall) }
                stack[top] = child
                top += 1usize
            }
            child = t.next_sibling[usize(child)]
        }
    }
    ret (hits, ok)
}
