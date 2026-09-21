// A splay tree over a caller node pool holding a sequence by implicit key
// (position), with a lazy reversal flag: `build` makes a balanced tree of
// values, `splay` rotates a node to the root by zig, zig-zig and zig-zag
// steps, `at` finds the k-th element (splaying it up), `reverse_range`
// reverses positions `l..r` by splitting the range out and tagging it, and
// `collect` reads the sequence back. Node 0 is empty; parents are tracked.

type Splay[T: type] = struct { values: []T, left: []u32, right: []u32, parent: []u32, size: []u32, reversed: []bool, used: usize }
error TooSmall
error Invalid

fn splay_tree[T: type](values: []T, left: []u32, right: []u32, parent: []u32, size: []u32, reversed: []bool) -> Splay[T] {
    if size.len > 0usize { size[0usize] = 0u32 }
    ret Splay[T] { values: values, left: left, right: right, parent: parent, size: size, reversed: reversed, used: 1usize }
}

// A balanced tree over `items` (each a fresh node); answers the root.
fn build[T: type](t: *Splay[T], items: []const T) -> (u32, err) {
    if t.used + items.len > t.values.len || t.used + items.len > t.left.len || t.used + items.len > t.right.len || t.used + items.len > t.parent.len || t.used + items.len > t.size.len || t.used + items.len > t.reversed.len { ret (0u32, TooSmall) }
    ret (build_range[T](t, items, 0u32), ok)
}

fn build_range[T: type](t: *Splay[T], items: []const T, parent: u32) -> u32 {
    if items.len == 0usize { ret 0u32 }
    let middle = items.len / 2usize
    let id = t.used
    t.used += 1usize
    t.values[id] = items[middle]
    t.parent[id] = parent
    t.reversed[id] = false
    t.left[id] = build_range[T](t, items[..middle], u32(id))
    t.right[id] = build_range[T](t, items[middle + 1usize..], u32(id))
    t.size[id] = 1u32 + t.size[usize(t.left[id])] + t.size[usize(t.right[id])]
    ret u32(id)
}

fn push[T: type](t: *Splay[T], n: u32) {
    if n != 0u32 && t.reversed[usize(n)] {
        let l = t.left[usize(n)]
        t.left[usize(n)] = t.right[usize(n)]
        t.right[usize(n)] = l
        if t.left[usize(n)] != 0u32 { t.reversed[usize(t.left[usize(n)])] = !t.reversed[usize(t.left[usize(n)])] }
        if t.right[usize(n)] != 0u32 { t.reversed[usize(t.right[usize(n)])] = !t.reversed[usize(t.right[usize(n)])] }
        t.reversed[usize(n)] = false
    }
}

fn fix[T: type](t: *Splay[T], n: u32) {
    if n != 0u32 { t.size[usize(n)] = 1u32 + t.size[usize(t.left[usize(n)])] + t.size[usize(t.right[usize(n)])] }
}

// Rotate `n` above its parent.
fn rotate[T: type](t: *Splay[T], n: u32) {
    let p = t.parent[usize(n)]
    let g = t.parent[usize(p)]
    if t.left[usize(p)] == n {
        t.left[usize(p)] = t.right[usize(n)]
        if t.right[usize(n)] != 0u32 { t.parent[usize(t.right[usize(n)])] = p }
        t.right[usize(n)] = p
    } else {
        t.right[usize(p)] = t.left[usize(n)]
        if t.left[usize(n)] != 0u32 { t.parent[usize(t.left[usize(n)])] = p }
        t.left[usize(n)] = p
    }
    t.parent[usize(p)] = n
    t.parent[usize(n)] = g
    if g != 0u32 {
        if t.left[usize(g)] == p { t.left[usize(g)] = n } else { t.right[usize(g)] = n }
    }
    fix[T](t, p)
    fix[T](t, n)
}

// Splay `n` to the root (its lazy flags and its ancestors' are pushed first
// by the caller's descent); answers `n`.
fn splay[T: type](t: *Splay[T], n: u32) -> u32 {
    while t.parent[usize(n)] != 0u32 {
        let p = t.parent[usize(n)]
        let g = t.parent[usize(p)]
        if g != 0u32 {
            let zig_zig = (t.left[usize(g)] == p) == (t.left[usize(p)] == n)
            if zig_zig { rotate[T](t, p) } else { rotate[T](t, n) }
        }
        rotate[T](t, n)
    }
    ret n
}

// The node at `position` (from 0) under `root`, splayed to the root; answers
// the new root (the node itself), or 0 past the end.
fn find[T: type](t: *Splay[T], root: u32, position: usize) -> u32 {
    var n = root
    var index = position
    while n != 0u32 {
        push[T](t, n)
        let left_size = usize(t.size[usize(t.left[usize(n)])])
        if index < left_size {
            n = t.left[usize(n)]
        } else if index == left_size {
            ret splay[T](t, n)
        } else {
            index -= left_size + 1usize
            n = t.right[usize(n)]
        }
    }
    ret 0u32
}

// The value at `position`; answers it and the new root.
fn at[T: type](t: *Splay[T], root: u32, position: usize) -> (T, u32, err) {
    if position >= usize(t.size[usize(root)]) { ret (zero, root, Invalid) }
    let n = find[T](t, root, position)
    ret (t.values[usize(n)], n, ok)
}

// Reverse positions `low..=high`; answers the new root.
fn reverse_range[T: type](t: *Splay[T], root: u32, low: usize, high: usize) -> (u32, err) {
    let n = usize(t.size[usize(root)])
    if low > high || high >= n { ret (root, Invalid) }
    // Bring the element before the range to the root and the one after it to
    // the root's right child; the range is then the right child's left subtree.
    var r = root
    if low == 0usize && high == n - 1usize {
        t.reversed[usize(r)] = !t.reversed[usize(r)]
        ret (r, ok)
    }
    if low == 0usize {
        // The range is everything left of position high + 1.
        r = find[T](t, r, high + 1usize)
        let l = t.left[usize(r)]
        t.reversed[usize(l)] = !t.reversed[usize(l)]
        ret (r, ok)
    }
    r = find[T](t, r, low - 1usize)
    if high == n - 1usize {
        let right = t.right[usize(r)]
        t.reversed[usize(right)] = !t.reversed[usize(right)]
        ret (r, ok)
    }
    // Splay position high + 1 within the right subtree: detach, find, reattach.
    let right = t.right[usize(r)]
    t.parent[usize(right)] = 0u32
    let after = find[T](t, right, high - low + 1usize)
    t.right[usize(r)] = after
    t.parent[usize(after)] = r
    let range = t.left[usize(after)]
    t.reversed[usize(range)] = !t.reversed[usize(range)]
    fix[T](t, after)
    fix[T](t, r)
    ret (r, ok)
}

// The sequence in order into `out`; answers the count.
fn collect[T: type](t: *Splay[T], root: u32, out: []T) -> (usize, err) {
    if root == 0u32 { ret (0usize, ok) }
    push[T](t, root)
    let (before, left_error) = collect[T](t, t.left[usize(root)], out)
    if left_error != ok { ret (before, left_error) }
    if before >= out.len { ret (before, TooSmall) }
    out[before] = t.values[usize(root)]
    let (after, right_error) = collect[T](t, t.right[usize(root)], out[before + 1usize..])
    ret (before + 1usize + after, right_error)
}
