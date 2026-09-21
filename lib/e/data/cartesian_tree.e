// Cartesian trees over caller storage: `build` makes the min-heap-ordered
// tree whose in-order walk is the array order in O(n) (ties: the leftmost
// equal key is the ancestor), `lca` answers the lowest common ancestor of
// two positions by walking parents, `range_min` answers the index of the
// leftmost minimum of `[lo, hi)` as the LCA of its ends, and `is_valid`
// checks heap order, tie order and the in-order walk. Nodes are array
// positions; `NONE` marks a missing child or the root's parent.

type Tree = struct { left: []u32, right: []u32, parent: []u32, n: usize, root: u32 }
error TooSmall
error Invalid

const NONE: u32 = 4294967295u32

// The Cartesian tree of `keys` into `left`, `right` and `parent`.
fn build[T: type](keys: []const T, left: []u32, right: []u32, parent: []u32) -> (Tree, err) {
    let n = keys.len
    if left.len < n || right.len < n || parent.len < n { ret (zero, TooSmall) }
    // The stack is the right spine, so `top` and the parent links stand in for it.
    var top = NONE
    var i = 0usize
    while i < n {
        var last = NONE
        while top != NONE && T.cmp(keys[usize(top)], keys[i]) > 0i32 {
            last = top
            top = parent[usize(top)]
        }
        left[i] = last
        right[i] = NONE
        if last != NONE { parent[usize(last)] = u32(i) }
        parent[i] = top
        if top != NONE { right[usize(top)] = u32(i) }
        top = u32(i)
        i += 1usize
    }
    var root = NONE
    while top != NONE {
        root = top
        top = parent[usize(top)]
    }
    ret (Tree { left: left, right: right, parent: parent, n: n, root: root }, ok)
}

fn depth(t: *const Tree, i: usize) -> usize {
    var d = 0usize
    var node = t.parent[i]
    while node != NONE {
        d += 1usize
        node = t.parent[usize(node)]
    }
    ret d
}

// The lowest common ancestor of positions `i` and `j`.
// ponytail: O(depth) per query; an Euler tour plus sparse table if queries dominate.
fn lca(t: *const Tree, i: usize, j: usize) -> (usize, err) {
    if i >= t.n || j >= t.n { ret (0usize, Invalid) }
    var a = u32(i)
    var b = u32(j)
    var da = depth(t, i)
    var db = depth(t, j)
    while da > db {
        a = t.parent[usize(a)]
        da -= 1usize
    }
    while db > da {
        b = t.parent[usize(b)]
        db -= 1usize
    }
    while a != b {
        a = t.parent[usize(a)]
        b = t.parent[usize(b)]
    }
    ret (usize(a), ok)
}

// The index of the leftmost minimum of `[lo, hi)`.
fn range_min(t: *const Tree, lo: usize, hi: usize) -> (usize, err) {
    if lo >= hi || hi > t.n { ret (0usize, Invalid) }
    let (m, e) = lca(t, lo, hi - 1usize)
    ret (m, e)
}

// Whether `t` is the Cartesian tree of `keys`: links agree, every child is
// no smaller than its parent (strictly larger on the left), and the in-order
// walk from `root` visits 0..n-1 in order.
fn is_valid[T: type](keys: []const T, t: *const Tree) -> bool {
    let n = keys.len
    if t.n != n { ret false }
    if n == 0usize { ret t.root == NONE }
    if t.root == NONE || usize(t.root) >= n || t.parent[usize(t.root)] != NONE { ret false }
    var i = 0usize
    while i < n {
        let l = t.left[i]
        let r = t.right[i]
        if l != NONE {
            if usize(l) >= i || t.parent[usize(l)] != u32(i) || T.cmp(keys[usize(l)], keys[i]) <= 0i32 { ret false }
        }
        if r != NONE {
            if usize(r) <= i || usize(r) >= n || t.parent[usize(r)] != u32(i) || T.cmp(keys[usize(r)], keys[i]) < 0i32 { ret false }
        }
        i += 1usize
    }
    // In-order by successor steps; a stray link breaks the sequence or the count.
    var node = t.root
    while t.left[usize(node)] != NONE { node = t.left[usize(node)] }
    var expected = 0usize
    while node != NONE {
        if usize(node) != expected { ret false }
        expected += 1usize
        if t.right[usize(node)] != NONE {
            node = t.right[usize(node)]
            while t.left[usize(node)] != NONE { node = t.left[usize(node)] }
        } else {
            var child = node
            node = t.parent[usize(node)]
            while node != NONE && t.right[usize(node)] == child {
                child = node
                node = t.parent[usize(node)]
            }
        }
    }
    ret expected == n
}
