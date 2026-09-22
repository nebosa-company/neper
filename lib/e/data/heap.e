// Binary min-heap. `Heap` orders by `T.cmp`; `HeapBy` orders by a comparison
// carried with the heap, which is what an ordering over borrowed context needs.
//
// Every module-scope declaration is exported (spec section 5), so the sift loops are
// written out at each site rather than factored into helpers that would widen the
// module's public surface beyond its frozen API.

use e.data.list
use e.mem

type Heap[T: type] = struct { items: list.List[T] }
type HeapBy[T: type, Ctx: type] = struct { items: list.List[T], ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32 }
type Iter[T: type] = struct { items: []const T, index: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Heap[T], err) {
    let (items, items_error) = list.init[T](a, capacity)
    if items_error != ok { ret (zero, items_error) }
    ret (Heap[T] { items: items }, ok)
}

fn from_slice[T: type](a: *mem.Arena, source: []const T) -> (Heap[T], err) {
    let (items, items_error) = list.from_slice[T](a, source)
    if items_error != ok { ret (zero, items_error) }
    var result = Heap[T] { items: items }
    heapify_in_place[T](list.slice[T](&result.items))
    ret (result, ok)
}

fn len[T: type](h: *const Heap[T]) -> usize { ret h.items.len }

fn push[T: type](h: *Heap[T], v: own T) -> err {
    try list.push[T](&h.items, v)
    let items = list.slice[T](&h.items)
    var at = items.len - 1usize
    while at != 0usize {
        let above = at - 1usize
        let parent = above / 2usize
        if T.cmp(items[at], items[parent]) >= 0i32 { break }
        let carried = items[at]
        items[at] = items[parent]
        items[parent] = carried
        at = parent
    }
    ret ok
}

fn peek[T: type](h: *const Heap[T]) -> (T, bool) {
    if h.items.len == 0usize { ret (zero, false) }
    let items = list.slice_const[T](&h.items)
    ret (items[0usize], true)
}

fn pop[T: type](h: *Heap[T]) -> (T, bool) {
    if h.items.len == 0usize { ret (zero, false) }
    let full = list.slice[T](&h.items)
    let smallest = full[0usize]
    full[0usize] = full[full.len - 1usize]
    let (discarded, popped) = list.pop[T](&h.items)
    if !popped { ret (zero, false) }
    let items = list.slice[T](&h.items)
    var at = 0usize
    while true {
        let left = at * 2usize + 1usize
        if left >= items.len { break }
        var next = left
        let right = left + 1usize
        if right < items.len && T.cmp(items[right], items[left]) < 0i32 { next = right }
        if T.cmp(items[next], items[at]) >= 0i32 { break }
        let carried = items[at]
        items[at] = items[next]
        items[next] = carried
        at = next
    }
    ret (smallest, true)
}

fn clear[T: type](h: *Heap[T]) { list.clear[T](&h.items) }

fn init_by[T: type, Ctx: type](a: *mem.Arena, capacity: usize, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> (HeapBy[T, Ctx], err) {
    let (items, items_error) = list.init[T](a, capacity)
    if items_error != ok { ret (zero, items_error) }
    ret (HeapBy[T, Ctx] { items: items, ctx: ctx, cmp: cmp }, ok)
}

fn from_slice_by[T: type, Ctx: type](a: *mem.Arena, source: []const T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> (HeapBy[T, Ctx], err) {
    let (items, items_error) = list.from_slice[T](a, source)
    if items_error != ok { ret (zero, items_error) }
    var result = HeapBy[T, Ctx] { items: items, ctx: ctx, cmp: cmp }
    heapify_in_place_by[T, Ctx](list.slice[T](&result.items), ctx, cmp)
    ret (result, ok)
}

fn len_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> usize { ret h.items.len }

fn push_by[T: type, Ctx: type](h: *HeapBy[T, Ctx], value: own T) -> err {
    try list.push[T](&h.items, value)
    let items = list.slice[T](&h.items)
    var at = items.len - 1usize
    while at != 0usize {
        let above = at - 1usize
        let parent = above / 2usize
        if h.cmp(h.ctx, items[at], items[parent]) >= 0i32 { break }
        let carried = items[at]
        items[at] = items[parent]
        items[parent] = carried
        at = parent
    }
    ret ok
}

fn peek_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> (T, bool) {
    if h.items.len == 0usize { ret (zero, false) }
    let items = list.slice_const[T](&h.items)
    ret (items[0usize], true)
}

fn pop_by[T: type, Ctx: type](h: *HeapBy[T, Ctx]) -> (T, bool) {
    if h.items.len == 0usize { ret (zero, false) }
    let full = list.slice[T](&h.items)
    let smallest = full[0usize]
    full[0usize] = full[full.len - 1usize]
    let (discarded, popped) = list.pop[T](&h.items)
    if !popped { ret (zero, false) }
    let items = list.slice[T](&h.items)
    var at = 0usize
    while true {
        let left = at * 2usize + 1usize
        if left >= items.len { break }
        var next = left
        let right = left + 1usize
        if right < items.len && h.cmp(h.ctx, items[right], items[left]) < 0i32 { next = right }
        if h.cmp(h.ctx, items[next], items[at]) >= 0i32 { break }
        let carried = items[at]
        items[at] = items[next]
        items[next] = carried
        at = next
    }
    ret (smallest, true)
}

fn clear_by[T: type, Ctx: type](h: *HeapBy[T, Ctx]) { list.clear[T](&h.items) }

// Floyd's construction: every node above the leaves sifts down once, which is
// linear in the element count rather than n log n.
fn heapify_in_place[T: type](items: []T) {
    if items.len < 2usize { ret }
    var start = items.len / 2usize
    while start != 0usize {
        start -= 1usize
        var at = start
        while true {
            let left = at * 2usize + 1usize
            if left >= items.len { break }
            var smallest = left
            let right = left + 1usize
            if right < items.len && T.cmp(items[right], items[left]) < 0i32 { smallest = right }
            if T.cmp(items[smallest], items[at]) >= 0i32 { break }
            let carried = items[at]
            items[at] = items[smallest]
            items[smallest] = carried
            at = smallest
        }
    }
}

fn heapify_in_place_by[T: type, Ctx: type](items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) {
    if items.len < 2usize { ret }
    var start = items.len / 2usize
    while start != 0usize {
        start -= 1usize
        var at = start
        while true {
            let left = at * 2usize + 1usize
            if left >= items.len { break }
            var smallest = left
            let right = left + 1usize
            if right < items.len && cmp(ctx, items[right], items[left]) < 0i32 { smallest = right }
            if cmp(ctx, items[smallest], items[at]) >= 0i32 { break }
            let carried = items[at]
            items[at] = items[smallest]
            items[smallest] = carried
            at = smallest
        }
    }
}

// Iteration exposes internal heap order, not sorted order.
fn iter[T: type](h: *const Heap[T]) -> Iter[T] {
    ret Iter[T] { items: list.slice_const[T](&h.items), index: 0usize }
}

fn iter_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> Iter[T] {
    ret Iter[T] { items: list.slice_const[T](&h.items), index: 0usize }
}

fn iter_next[T: type](it: *Iter[T]) -> (T, bool) {
    if it.index >= it.items.len { ret (zero, false) }
    let value = it.items[it.index]
    it.index += 1usize
    ret (value, true)
}

// The named heaps below (D883) extend the module without reordering what is above:
// `heapify` is Floyd's build under its planned name; `MinMax[T]` is a min-max heap
// over caller storage; the leftist, skew, pairing, binomial and randomized meldable
// heaps all share one caller `Pool[K]` of parallel arrays (node 0 is empty, a root
// of 0 is the empty heap, and the popped node id is the caller's handle to its
// payload). Keys order by `K.cmp`; every heap is a min-heap.

error TooSmall

type MinMax[T: type] = struct { items: []T, count: usize }
type Pool[K: type] = struct { keys: []K, left: []u32, right: []u32, up: []u32, rank: []u32, used: usize }

fn heapify[T: type](items: []T) { heapify_in_place[T](items) }

fn heapify_by[T: type, Ctx: type](items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) { heapify_in_place_by[T, Ctx](items, ctx, cmp) }

// Min-max heap (Atkinson et al.): even levels hold the minimum of their subtree,
// odd levels the maximum. Level parity is the bit length of index + 1.
fn min_max[T: type](items: []T) -> MinMax[T] { ret MinMax[T] { items: items, count: 0usize } }

fn min_max_level(index: usize) -> bool {
    var v = index + 1usize
    var depth = 0usize
    while v > 1usize {
        v = v / 2usize
        depth += 1usize
    }
    ret depth % 2usize == 0usize
}

// Sift `start` down along its own level's ordering: `sign` 1 on a min level, -1 on a max level.
fn min_max_down[T: type](items: []T, count: usize, start: usize, sign: i32) {
    var at = start
    while true {
        let first = at * 2usize + 1usize
        if first >= count { break }
        var best = first
        var k = 1usize
        while k < 6usize {
            var idx = first + 1usize
            if k > 1usize { idx = at * 4usize + 1usize + k }
            if idx < count && T.cmp(items[idx], items[best]) * sign < 0i32 { best = idx }
            k += 1usize
        }
        if T.cmp(items[best], items[at]) * sign >= 0i32 { break }
        let carried = items[at]
        items[at] = items[best]
        items[best] = carried
        if best <= first + 1usize { break }
        let above = (best - 1usize) / 2usize
        if T.cmp(items[best], items[above]) * sign > 0i32 {
            let held = items[best]
            items[best] = items[above]
            items[above] = held
        }
        at = best
    }
}

fn min_max_push[T: type](h: *MinMax[T], v: T) -> err {
    if h.count >= h.items.len { ret TooSmall }
    let items = h.items
    var at = h.count
    items[at] = v
    h.count += 1usize
    if at == 0usize { ret ok }
    let parent = (at - 1usize) / 2usize
    let c = T.cmp(items[at], items[parent])
    let on_min = min_max_level(at)
    if (on_min && c > 0i32) || (!on_min && c < 0i32) {
        items[at] = items[parent]
        items[parent] = v
        at = parent
    }
    var sign = 1i32
    if !min_max_level(at) { sign = 0i32 - 1i32 }
    while at >= 3usize {
        let g = (at - 3usize) / 4usize
        if T.cmp(items[at], items[g]) * sign >= 0i32 { break }
        items[at] = items[g]
        items[g] = v
        at = g
    }
    ret ok
}

fn peek_min[T: type](h: *const MinMax[T]) -> (T, bool) {
    if h.count == 0usize { ret (zero, false) }
    ret (h.items[0usize], true)
}

fn peek_max[T: type](h: *const MinMax[T]) -> (T, bool) {
    if h.count == 0usize { ret (zero, false) }
    var best = 0usize
    if h.count > 1usize { best = 1usize }
    if h.count > 2usize && T.cmp(h.items[2usize], h.items[1usize]) > 0i32 { best = 2usize }
    ret (h.items[best], true)
}

fn pop_min[T: type](h: *MinMax[T]) -> (T, bool) {
    if h.count == 0usize { ret (zero, false) }
    let top = h.items[0usize]
    h.count -= 1usize
    h.items[0usize] = h.items[h.count]
    min_max_down[T](h.items, h.count, 0usize, 1i32)
    ret (top, true)
}

fn pop_max[T: type](h: *MinMax[T]) -> (T, bool) {
    if h.count == 0usize { ret (zero, false) }
    var best = 0usize
    if h.count > 1usize { best = 1usize }
    if h.count > 2usize && T.cmp(h.items[2usize], h.items[1usize]) > 0i32 { best = 2usize }
    let top = h.items[best]
    h.count -= 1usize
    h.items[best] = h.items[h.count]
    min_max_down[T](h.items, h.count, best, 0i32 - 1i32)
    ret (top, true)
}

// A pool over parallel arrays of one capacity (at least one slot); slot 0 stays empty.
fn pool[K: type](keys: []K, left: []u32, right: []u32, up: []u32, rank: []u32) -> Pool[K] {
    rank[0usize] = 0u32
    ret Pool[K] { keys: keys, left: left, right: right, up: up, rank: rank, used: 1usize }
}

fn pool_node[K: type](p: *Pool[K], key: K) -> (u32, err) {
    if p.used >= p.keys.len || p.used >= p.left.len || p.used >= p.right.len || p.used >= p.up.len || p.used >= p.rank.len { ret (0u32, TooSmall) }
    let id = p.used
    p.used += 1usize
    p.keys[id] = key
    p.left[id] = 0u32
    p.right[id] = 0u32
    p.up[id] = 0u32
    p.rank[id] = 0u32
    ret (u32(id), ok)
}

// Leftist heap: `rank` is the null path length (a leaf is 1, the empty tree 0) and
// the right spine is never longer than the left.
fn leftist_merge[K: type](p: *Pool[K], a: u32, b: u32) -> u32 {
    if a == 0u32 { ret b }
    if b == 0u32 { ret a }
    var x = a
    var y = b
    if K.cmp(p.keys[usize(b)], p.keys[usize(a)]) < 0i32 {
        x = b
        y = a
    }
    let n = usize(x)
    p.right[n] = leftist_merge[K](p, p.right[n], y)
    if p.rank[usize(p.left[n])] < p.rank[usize(p.right[n])] {
        let held = p.left[n]
        p.left[n] = p.right[n]
        p.right[n] = held
    }
    p.rank[n] = p.rank[usize(p.right[n])] + 1u32
    ret x
}

fn leftist_insert[K: type](p: *Pool[K], root: u32, key: K) -> (u32, err) {
    let (node, node_error) = pool_node[K](p, key)
    if node_error != ok { ret (root, node_error) }
    p.rank[usize(node)] = 1u32
    ret (leftist_merge[K](p, root, node), ok)
}

// Answers (new root, popped node); the popped node is 0 when the heap was empty.
fn leftist_pop[K: type](p: *Pool[K], root: u32) -> (u32, u32) {
    if root == 0u32 { ret (0u32, 0u32) }
    ret (leftist_merge[K](p, p.left[usize(root)], p.right[usize(root)]), root)
}

// Skew heap: the leftist merge without ranks, swapping the children unconditionally.
fn skew_merge[K: type](p: *Pool[K], a: u32, b: u32) -> u32 {
    if a == 0u32 { ret b }
    if b == 0u32 { ret a }
    var x = a
    var y = b
    if K.cmp(p.keys[usize(b)], p.keys[usize(a)]) < 0i32 {
        x = b
        y = a
    }
    let n = usize(x)
    let old_left = p.left[n]
    p.left[n] = skew_merge[K](p, p.right[n], y)
    p.right[n] = old_left
    ret x
}

fn skew_insert[K: type](p: *Pool[K], root: u32, key: K) -> (u32, err) {
    let (node, node_error) = pool_node[K](p, key)
    if node_error != ok { ret (root, node_error) }
    ret (skew_merge[K](p, root, node), ok)
}

fn skew_pop[K: type](p: *Pool[K], root: u32) -> (u32, u32) {
    if root == 0u32 { ret (0u32, 0u32) }
    ret (skew_merge[K](p, p.left[usize(root)], p.right[usize(root)]), root)
}

// Randomized meldable heap (Gambin and Malinowski): the merge descends into a child
// chosen by a coin, the top bit of an xorshift64* step over the caller's `*u64`.
// `meldable` seeds that coin (a zero seed is replaced, being the xorshift fixed point).
fn meldable(seed: u64) -> u64 {
    if seed == 0u64 { ret 11400714819323198485u64 }
    ret seed
}

fn meldable_merge[K: type](p: *Pool[K], a: u32, b: u32, coin: *u64) -> u32 {
    if a == 0u32 { ret b }
    if b == 0u32 { ret a }
    var x = a
    var y = b
    if K.cmp(p.keys[usize(b)], p.keys[usize(a)]) < 0i32 {
        x = b
        y = a
    }
    var s = *coin
    s = s ^ (s >> 12u64)
    s = s ^ (s << 25u64)
    s = s ^ (s >> 27u64)
    *coin = s
    let n = usize(x)
    if ((s *% 2685821657736338717u64) >> 63u64) == 1u64 {
        p.left[n] = meldable_merge[K](p, p.left[n], y, coin)
    } else {
        p.right[n] = meldable_merge[K](p, p.right[n], y, coin)
    }
    ret x
}

fn meldable_insert[K: type](p: *Pool[K], root: u32, key: K, coin: *u64) -> (u32, err) {
    let (node, node_error) = pool_node[K](p, key)
    if node_error != ok { ret (root, node_error) }
    ret (meldable_merge[K](p, root, node, coin), ok)
}

fn meldable_pop[K: type](p: *Pool[K], root: u32, coin: *u64) -> (u32, u32) {
    if root == 0u32 { ret (0u32, 0u32) }
    ret (meldable_merge[K](p, p.left[usize(root)], p.right[usize(root)], coin), root)
}

// Pairing heap: `left` is the first child, `right` the next sibling, and `up` the
// previous sibling or, for a first child, the parent, so a node can be cut in O(1).
fn pairing_merge[K: type](p: *Pool[K], a: u32, b: u32) -> u32 {
    if a == 0u32 { ret b }
    if b == 0u32 { ret a }
    var x = a
    var y = b
    if K.cmp(p.keys[usize(b)], p.keys[usize(a)]) < 0i32 {
        x = b
        y = a
    }
    let n = usize(x)
    let first = p.left[n]
    p.right[usize(y)] = first
    if first != 0u32 { p.up[usize(first)] = y }
    p.left[n] = y
    p.up[usize(y)] = x
    p.right[n] = 0u32
    p.up[n] = 0u32
    ret x
}

fn pairing_insert[K: type](p: *Pool[K], root: u32, key: K) -> (u32, err) {
    let (node, node_error) = pool_node[K](p, key)
    if node_error != ok { ret (root, node_error) }
    ret (pairing_merge[K](p, root, node), ok)
}

// Two-pass pairing: siblings merge in pairs left to right, then the pairs merge
// right to left. Answers (new root, popped node).
fn pairing_pop[K: type](p: *Pool[K], root: u32) -> (u32, u32) {
    if root == 0u32 { ret (0u32, 0u32) }
    var c = p.left[usize(root)]
    p.left[usize(root)] = 0u32
    var head = 0u32
    while c != 0u32 {
        let d = p.right[usize(c)]
        p.right[usize(c)] = 0u32
        p.up[usize(c)] = 0u32
        var m = c
        if d != 0u32 {
            let after = p.right[usize(d)]
            p.right[usize(d)] = 0u32
            p.up[usize(d)] = 0u32
            m = pairing_merge[K](p, c, d)
            c = after
        } else {
            c = 0u32
        }
        p.right[usize(m)] = head
        head = m
    }
    var result = head
    if result != 0u32 {
        var rest = p.right[usize(result)]
        p.right[usize(result)] = 0u32
        while rest != 0u32 {
            let following = p.right[usize(rest)]
            p.right[usize(rest)] = 0u32
            result = pairing_merge[K](p, result, rest)
            rest = following
        }
    }
    ret (result, root)
}

// Lower a node's key to `key` (never higher: the subtree below it is not re-checked),
// cutting it from its parent and merging it back at the root. Answers the new root.
fn pairing_decrease_key[K: type](p: *Pool[K], root: u32, node: u32, key: K) -> u32 {
    let n = usize(node)
    p.keys[n] = key
    if node == root { ret root }
    let u = usize(p.up[n])
    if p.left[u] == node { p.left[u] = p.right[n] } else { p.right[u] = p.right[n] }
    if p.right[n] != 0u32 { p.up[usize(p.right[n])] = p.up[n] }
    p.right[n] = 0u32
    p.up[n] = 0u32
    ret pairing_merge[K](p, root, node)
}

// Binomial heap: a root list chained by `right` in increasing degree (`rank`), each
// tree's children chained by `right` from `left` in decreasing degree.
fn binomial_link[K: type](p: *Pool[K], child: u32, parent: u32) {
    p.up[usize(child)] = parent
    p.right[usize(child)] = p.left[usize(parent)]
    p.left[usize(parent)] = child
    p.rank[usize(parent)] += 1u32
}

fn binomial_merge[K: type](p: *Pool[K], a: u32, b: u32) -> u32 {
    var ra = a
    var rb = b
    var head = 0u32
    var tail = 0u32
    while ra != 0u32 || rb != 0u32 {
        var n = rb
        if rb == 0u32 || (ra != 0u32 && p.rank[usize(ra)] <= p.rank[usize(rb)]) {
            n = ra
            ra = p.right[usize(ra)]
        } else {
            rb = p.right[usize(rb)]
        }
        if tail == 0u32 { head = n } else { p.right[usize(tail)] = n }
        tail = n
    }
    if tail != 0u32 { p.right[usize(tail)] = 0u32 }
    if head == 0u32 { ret 0u32 }
    var prev = 0u32
    var x = head
    var following = p.right[usize(x)]
    while following != 0u32 {
        let same = p.rank[usize(x)] == p.rank[usize(following)]
        let third = p.right[usize(following)]
        if !same || (third != 0u32 && p.rank[usize(third)] == p.rank[usize(x)]) {
            prev = x
            x = following
        } else if K.cmp(p.keys[usize(x)], p.keys[usize(following)]) <= 0i32 {
            p.right[usize(x)] = third
            binomial_link[K](p, following, x)
        } else {
            if prev == 0u32 { head = following } else { p.right[usize(prev)] = following }
            binomial_link[K](p, x, following)
            x = following
        }
        following = p.right[usize(x)]
    }
    ret head
}

fn binomial_insert[K: type](p: *Pool[K], root: u32, key: K) -> (u32, err) {
    let (node, node_error) = pool_node[K](p, key)
    if node_error != ok { ret (root, node_error) }
    ret (binomial_merge[K](p, root, node), ok)
}

fn binomial_peek[K: type](p: *const Pool[K], root: u32) -> u32 {
    var best = root
    var x = root
    while x != 0u32 {
        if K.cmp(p.keys[usize(x)], p.keys[usize(best)]) < 0i32 { best = x }
        x = p.right[usize(x)]
    }
    ret best
}

// Answers (new root list, popped node): the least root leaves the list and its
// children, reversed into increasing degree, merge back in.
fn binomial_pop[K: type](p: *Pool[K], root: u32) -> (u32, u32) {
    if root == 0u32 { ret (0u32, 0u32) }
    var head = root
    let best = binomial_peek[K](p, root)
    var prev = 0u32
    var x = root
    while x != best {
        prev = x
        x = p.right[usize(x)]
    }
    if prev == 0u32 { head = p.right[usize(best)] } else { p.right[usize(prev)] = p.right[usize(best)] }
    var rev = 0u32
    var c = p.left[usize(best)]
    while c != 0u32 {
        let following = p.right[usize(c)]
        p.right[usize(c)] = rev
        p.up[usize(c)] = 0u32
        rev = c
        c = following
    }
    p.left[usize(best)] = 0u32
    p.right[usize(best)] = 0u32
    ret (binomial_merge[K](p, head, rev), best)
}
