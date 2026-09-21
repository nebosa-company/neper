// Treaps over a caller node pool: `Treap[K]` keys ordered by `K.cmp` with
// random priorities, `split` by key and `merge` as the primitives, `insert`,
// `remove` and `contains` on top; `Implicit[T]` is the implicit-key treap
// over a sequence, `split_at` by position and `merge`, with `insert_at`,
// `remove_at` and `at`; and `persistent_insert` keeps every version of a
// `Treap[K]` by copying the path (a version is a root). Node 0 is never used,
// so `0` is the empty tree.

use e.algo.rand

type Treap[K: type] = struct { keys: []K, priority: []u64, left: []u32, right: []u32, used: usize }
type Implicit[T: type] = struct { values: []T, priority: []u64, left: []u32, right: []u32, size: []u32, used: usize }
error TooSmall
error Invalid

// A treap over parallel arrays of one capacity; slot 0 stays empty.
fn treap[K: type](keys: []K, priority: []u64, left: []u32, right: []u32) -> Treap[K] {
    ret Treap[K] { keys: keys, priority: priority, left: left, right: right, used: 1usize }
}

fn new_node[K: type](t: *Treap[K], key: K, r: *rand.Pcg64) -> (u32, err) {
    if t.used >= t.keys.len || t.used >= t.priority.len || t.used >= t.left.len || t.used >= t.right.len { ret (0u32, TooSmall) }
    let id = t.used
    t.used += 1usize
    t.keys[id] = key
    t.priority[id] = rand.pcg64_next(r)
    t.left[id] = 0u32
    t.right[id] = 0u32
    ret (u32(id), ok)
}

// Split `root` into (keys < `key`, keys >= `key`).
fn split[K: type](t: *Treap[K], root: u32, key: K) -> (u32, u32) {
    if root == 0u32 { ret (0u32, 0u32) }
    let n = usize(root)
    if K.cmp(t.keys[n], key) < 0i32 {
        let (l, r) = split[K](t, t.right[n], key)
        t.right[n] = l
        ret (root, r)
    }
    let (l, r) = split[K](t, t.left[n], key)
    t.left[n] = r
    ret (l, root)
}

// Merge two treaps where every key of `a` is below every key of `b`.
fn merge[K: type](t: *Treap[K], a: u32, b: u32) -> u32 {
    if a == 0u32 { ret b }
    if b == 0u32 { ret a }
    if t.priority[usize(a)] > t.priority[usize(b)] {
        t.right[usize(a)] = merge[K](t, t.right[usize(a)], b)
        ret a
    }
    t.left[usize(b)] = merge[K](t, a, t.left[usize(b)])
    ret b
}

// Insert `key` (a duplicate is kept alongside); answers the new root.
fn insert[K: type](t: *Treap[K], root: u32, key: K, r: *rand.Pcg64) -> (u32, err) {
    let (node, node_error) = new_node[K](t, key, r)
    if node_error != ok { ret (root, node_error) }
    let (l, rest) = split[K](t, root, key)
    ret (merge[K](t, merge[K](t, l, node), rest), ok)
}

// Remove one node with `key`, if any; answers the new root and whether one went.
fn remove[K: type](t: *Treap[K], root: u32, key: K) -> (u32, bool) {
    if root == 0u32 { ret (0u32, false) }
    let n = usize(root)
    let c = K.cmp(key, t.keys[n])
    if c < 0i32 {
        let (l, went) = remove[K](t, t.left[n], key)
        t.left[n] = l
        ret (root, went)
    }
    if c > 0i32 {
        let (r, went) = remove[K](t, t.right[n], key)
        t.right[n] = r
        ret (root, went)
    }
    ret (merge[K](t, t.left[n], t.right[n]), true)
}

fn contains[K: type](t: *const Treap[K], root: u32, key: K) -> bool {
    var n = root
    while n != 0u32 {
        let c = K.cmp(key, t.keys[usize(n)])
        if c == 0i32 { ret true }
        if c < 0i32 { n = t.left[usize(n)] } else { n = t.right[usize(n)] }
    }
    ret false
}

// The keys of `root` in order into `out`; answers the count.
fn collect[K: type](t: *const Treap[K], root: u32, out: []K) -> (usize, err) {
    if root == 0u32 { ret (0usize, ok) }
    let n = usize(root)
    let (before, left_error) = collect[K](t, t.left[n], out)
    if left_error != ok { ret (before, left_error) }
    if before >= out.len { ret (before, TooSmall) }
    out[before] = t.keys[n]
    let (after, right_error) = collect[K](t, t.right[n], out[before + 1usize..])
    ret (before + 1usize + after, right_error)
}

// Persistent insert: the nodes on the way down are copied, so `root` still
// describes the old version; answers the new version's root.
fn persistent_insert[K: type](t: *Treap[K], root: u32, key: K, r: *rand.Pcg64) -> (u32, err) {
    let (node, node_error) = new_node[K](t, key, r)
    if node_error != ok { ret (root, node_error) }
    let (l, rest, split_error) = persistent_split[K](t, root, key)
    if split_error != ok { ret (root, split_error) }
    let (inner, inner_error) = persistent_merge[K](t, l, node)
    if inner_error != ok { ret (root, inner_error) }
    let (version, merge_error) = persistent_merge[K](t, inner, rest)
    ret (version, merge_error)
}

fn copy_node[K: type](t: *Treap[K], from: u32) -> (u32, err) {
    if t.used >= t.keys.len || t.used >= t.priority.len || t.used >= t.left.len || t.used >= t.right.len { ret (0u32, TooSmall) }
    let id = t.used
    t.used += 1usize
    let f = usize(from)
    t.keys[id] = t.keys[f]
    t.priority[id] = t.priority[f]
    t.left[id] = t.left[f]
    t.right[id] = t.right[f]
    ret (u32(id), ok)
}

fn persistent_split[K: type](t: *Treap[K], root: u32, key: K) -> (u32, u32, err) {
    if root == 0u32 { ret (0u32, 0u32, ok) }
    let (copy, copy_error) = copy_node[K](t, root)
    if copy_error != ok { ret (0u32, 0u32, copy_error) }
    let n = usize(copy)
    if K.cmp(t.keys[n], key) < 0i32 {
        let (l, r, e) = persistent_split[K](t, t.right[n], key)
        if e != ok { ret (0u32, 0u32, e) }
        t.right[n] = l
        ret (copy, r, ok)
    }
    let (l, r, e) = persistent_split[K](t, t.left[n], key)
    if e != ok { ret (0u32, 0u32, e) }
    t.left[n] = r
    ret (l, copy, ok)
}

fn persistent_merge[K: type](t: *Treap[K], a: u32, b: u32) -> (u32, err) {
    if a == 0u32 { ret (b, ok) }
    if b == 0u32 { ret (a, ok) }
    if t.priority[usize(a)] > t.priority[usize(b)] {
        let (copy, copy_error) = copy_node[K](t, a)
        if copy_error != ok { ret (0u32, copy_error) }
        let (merged, e) = persistent_merge[K](t, t.right[usize(copy)], b)
        if e != ok { ret (0u32, e) }
        t.right[usize(copy)] = merged
        ret (copy, ok)
    }
    let (copy, copy_error) = copy_node[K](t, b)
    if copy_error != ok { ret (0u32, copy_error) }
    let (merged, e) = persistent_merge[K](t, a, t.left[usize(copy)])
    if e != ok { ret (0u32, e) }
    t.left[usize(copy)] = merged
    ret (copy, ok)
}

// An implicit treap over parallel arrays; slot 0 stays empty with size 0.
fn implicit[T: type](values: []T, priority: []u64, left: []u32, right: []u32, size: []u32) -> Implicit[T] {
    if size.len > 0usize { size[0usize] = 0u32 }
    ret Implicit[T] { values: values, priority: priority, left: left, right: right, size: size, used: 1usize }
}

fn implicit_size[T: type](t: *const Implicit[T], n: u32) -> u32 { ret t.size[usize(n)] }

fn implicit_fix[T: type](t: *Implicit[T], n: u32) {
    if n != 0u32 { t.size[usize(n)] = 1u32 + t.size[usize(t.left[usize(n)])] + t.size[usize(t.right[usize(n)])] }
}

// Split `root` into (the first `count` elements, the rest).
fn split_at[T: type](t: *Implicit[T], root: u32, count: usize) -> (u32, u32) {
    if root == 0u32 { ret (0u32, 0u32) }
    let n = usize(root)
    let left_size = usize(t.size[usize(t.left[n])])
    if count <= left_size {
        let (l, r) = split_at[T](t, t.left[n], count)
        t.left[n] = r
        implicit_fix[T](t, root)
        ret (l, root)
    }
    let (l, r) = split_at[T](t, t.right[n], count - left_size - 1usize)
    t.right[n] = l
    implicit_fix[T](t, root)
    ret (root, r)
}

fn implicit_merge[T: type](t: *Implicit[T], a: u32, b: u32) -> u32 {
    if a == 0u32 { ret b }
    if b == 0u32 { ret a }
    if t.priority[usize(a)] > t.priority[usize(b)] {
        t.right[usize(a)] = implicit_merge[T](t, t.right[usize(a)], b)
        implicit_fix[T](t, a)
        ret a
    }
    t.left[usize(b)] = implicit_merge[T](t, a, t.left[usize(b)])
    implicit_fix[T](t, b)
    ret b
}

// Insert `value` before `position` (`position == size` appends).
fn insert_at[T: type](t: *Implicit[T], root: u32, position: usize, value: T, r: *rand.Pcg64) -> (u32, err) {
    if position > usize(t.size[usize(root)]) { ret (root, Invalid) }
    if t.used >= t.values.len || t.used >= t.priority.len || t.used >= t.left.len || t.used >= t.right.len || t.used >= t.size.len { ret (root, TooSmall) }
    let id = t.used
    t.used += 1usize
    t.values[id] = value
    t.priority[id] = rand.pcg64_next(r)
    t.left[id] = 0u32
    t.right[id] = 0u32
    t.size[id] = 1u32
    let (l, rest) = split_at[T](t, root, position)
    ret (implicit_merge[T](t, implicit_merge[T](t, l, u32(id)), rest), ok)
}

// Remove the element at `position`.
fn remove_at[T: type](t: *Implicit[T], root: u32, position: usize) -> (u32, err) {
    if position >= usize(t.size[usize(root)]) { ret (root, Invalid) }
    let (l, rest) = split_at[T](t, root, position)
    let (_, tail) = split_at[T](t, rest, 1usize)
    ret (implicit_merge[T](t, l, tail), ok)
}

// The element at `position`.
fn at[T: type](t: *const Implicit[T], root: u32, position: usize) -> (T, err) {
    var n = root
    var index = position
    while n != 0u32 {
        let left_size = usize(t.size[usize(t.left[usize(n)])])
        if index < left_size {
            n = t.left[usize(n)]
        } else if index == left_size {
            ret (t.values[usize(n)], ok)
        } else {
            index -= left_size + 1usize
            n = t.right[usize(n)]
        }
    }
    ret (zero, Invalid)
}
