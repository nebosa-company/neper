// A B+ tree over a caller node pool: `u64` keys and values, leaves holding
// up to `order` entries and inner nodes up to `order` children, the leaves
// chained for range scans. `insert` splits a full node and promotes its
// separator (`split_node`), `remove` borrows from a sibling or merges an
// underfull node (`merge_node`), `get` and `scan` read. Node 0 is unused.

type Btree = struct { keys: []u64, values: []u32, count: []u32, leaf: []bool, next: []u32, order: usize, root: u32, used: usize, height: usize, free: u32 }
error TooSmall
error Invalid

const NONE: u32 = 4294967295u32

// A tree of `order` (at least 3) over pools sized `nodes * order`
// (`keys`, `values`) and `nodes` (`count`, `leaf`, `next`).
fn btree(keys: []u64, values: []u32, count: []u32, leaf: []bool, next: []u32, order: usize) -> (Btree, err) {
    if order < 3usize { ret (zero, Invalid) }
    let nodes = count.len
    if nodes < 2usize || keys.len < nodes * order || values.len < nodes * order || leaf.len < nodes || next.len < nodes { ret (zero, TooSmall) }
    count[1usize] = 0u32
    leaf[1usize] = true
    next[1usize] = NONE
    ret (Btree { keys: keys, values: values, count: count, leaf: leaf, next: next, order: order, root: 1u32, used: 2usize, height: 1usize, free: NONE }, ok)
}

fn key_at(t: *const Btree, node: u32, i: usize) -> u64 { ret t.keys[usize(node) * t.order + i] }
fn set_key(t: *Btree, node: u32, i: usize, k: u64) { t.keys[usize(node) * t.order + i] = k }
// In a leaf a slot holds the value; in an inner node the child.
fn value_at(t: *const Btree, node: u32, i: usize) -> u32 { ret t.values[usize(node) * t.order + i] }
fn set_value(t: *Btree, node: u32, i: usize, v: u32) { t.values[usize(node) * t.order + i] = v }

// The first slot whose key is not below `key`.
fn lower_bound(t: *const Btree, node: u32, key: u64) -> usize {
    var i = 0usize
    while i < usize(t.count[usize(node)]) && key_at(t, node, i) < key { i += 1usize }
    ret i
}

// The child of an inner node to follow for `key`: keys[i] is the smallest
// key under child i, except child 0 which takes everything below keys[1].
fn child_for(t: *const Btree, node: u32, key: u64) -> usize {
    var i = usize(t.count[usize(node)]) - 1usize
    while i > 0usize && key_at(t, node, i) > key { i -= 1usize }
    ret i
}

fn get(t: *const Btree, key: u64) -> (u32, bool) {
    var node = t.root
    while !t.leaf[usize(node)] { node = value_at(t, node, child_for(t, node, key)) }
    let i = lower_bound(t, node, key)
    if i < usize(t.count[usize(node)]) && key_at(t, node, i) == key { ret (value_at(t, node, i), true) }
    ret (0u32, false)
}

fn new_node(t: *Btree, is_leaf: bool) -> (u32, err) {
    var id = t.free
    if id != NONE {
        t.free = t.next[usize(id)]
    } else {
        if t.used >= t.count.len { ret (NONE, TooSmall) }
        id = u32(t.used)
        t.used += 1usize
    }
    t.count[usize(id)] = 0u32
    t.leaf[usize(id)] = is_leaf
    t.next[usize(id)] = NONE
    ret (id, ok)
}

// Split the full `node` in two; answers the new right node and its first key.
fn split_node(t: *Btree, node: u32) -> (u32, u64, err) {
    let (right, right_error) = new_node(t, t.leaf[usize(node)])
    if right_error != ok { ret (NONE, 0u64, right_error) }
    let total = usize(t.count[usize(node)])
    let half = total / 2usize
    var i = half
    while i < total {
        set_key(t, right, i - half, key_at(t, node, i))
        set_value(t, right, i - half, value_at(t, node, i))
        i += 1usize
    }
    t.count[usize(right)] = u32(total - half)
    t.count[usize(node)] = u32(half)
    if t.leaf[usize(node)] {
        t.next[usize(right)] = t.next[usize(node)]
        t.next[usize(node)] = right
    }
    ret (right, key_at(t, right, 0usize), ok)
}

// Insert into the subtree at `node`; when it overflows the split's right
// node and separator come back for the parent to add.
fn insert_into(t: *Btree, node: u32, key: u64, value: u32) -> (u32, u64, bool, err) {
    if t.leaf[usize(node)] {
        let i = lower_bound(t, node, key)
        let n = usize(t.count[usize(node)])
        if i < n && key_at(t, node, i) == key {
            set_value(t, node, i, value)
            ret (NONE, 0u64, false, ok)
        }
        var j = n
        while j > i {
            set_key(t, node, j, key_at(t, node, j - 1usize))
            set_value(t, node, j, value_at(t, node, j - 1usize))
            j -= 1usize
        }
        set_key(t, node, i, key)
        set_value(t, node, i, value)
        t.count[usize(node)] = u32(n + 1usize)
    } else {
        let c = child_for(t, node, key)
        let child = value_at(t, node, c)
        let (right, separator, split, child_error) = insert_into(t, child, key, value)
        if child_error != ok { ret (NONE, 0u64, false, child_error) }
        if c == 0usize && key < key_at(t, node, 0usize) { set_key(t, node, 0usize, key) }
        if split {
            let n = usize(t.count[usize(node)])
            var j = n
            while j > c + 1usize {
                set_key(t, node, j, key_at(t, node, j - 1usize))
                set_value(t, node, j, value_at(t, node, j - 1usize))
                j -= 1usize
            }
            set_key(t, node, c + 1usize, separator)
            set_value(t, node, c + 1usize, right)
            t.count[usize(node)] = u32(n + 1usize)
        }
    }
    if usize(t.count[usize(node)]) >= t.order {
        let (right, separator, split_error) = split_node(t, node)
        if split_error != ok { ret (NONE, 0u64, false, split_error) }
        ret (right, separator, true, ok)
    }
    ret (NONE, 0u64, false, ok)
}

fn insert(t: *Btree, key: u64, value: u32) -> err {
    let (right, separator, split, insert_error) = insert_into(t, t.root, key, value)
    if insert_error != ok { ret insert_error }
    if split {
        let (top, top_error) = new_node(t, false)
        if top_error != ok { ret top_error }
        set_key(t, top, 0usize, key_at(t, t.root, 0usize))
        set_value(t, top, 0usize, t.root)
        set_key(t, top, 1usize, separator)
        set_value(t, top, 1usize, right)
        t.count[usize(top)] = 2u32
        t.root = top
        t.height += 1usize
    }
    ret ok
}

fn release(t: *Btree, node: u32) {
    t.next[usize(node)] = t.free
    t.free = node
}

// Merge child `c + 1` of `node` into child `c` (both underfull); the right
// node returns to the pool.
fn merge_node(t: *Btree, node: u32, c: usize) {
    let left = value_at(t, node, c)
    let right = value_at(t, node, c + 1usize)
    let ln = usize(t.count[usize(left)])
    let rn = usize(t.count[usize(right)])
    var i = 0usize
    while i < rn {
        set_key(t, left, ln + i, key_at(t, right, i))
        set_value(t, left, ln + i, value_at(t, right, i))
        i += 1usize
    }
    t.count[usize(left)] = u32(ln + rn)
    if t.leaf[usize(left)] { t.next[usize(left)] = t.next[usize(right)] }
    release(t, right)
    let n = usize(t.count[usize(node)])
    i = c + 1usize
    while i + 1usize < n {
        set_key(t, node, i, key_at(t, node, i + 1usize))
        set_value(t, node, i, value_at(t, node, i + 1usize))
        i += 1usize
    }
    t.count[usize(node)] = u32(n - 1usize)
}

fn minimum_fill(t: *const Btree) -> usize { ret (t.order - 1usize) / 2usize }

// Remove `key` from the subtree at `node`; answers whether it was there.
fn remove_from(t: *Btree, node: u32, key: u64) -> bool {
    if t.leaf[usize(node)] {
        let i = lower_bound(t, node, key)
        let n = usize(t.count[usize(node)])
        if i >= n || key_at(t, node, i) != key { ret false }
        var j = i
        while j + 1usize < n {
            set_key(t, node, j, key_at(t, node, j + 1usize))
            set_value(t, node, j, value_at(t, node, j + 1usize))
            j += 1usize
        }
        t.count[usize(node)] = u32(n - 1usize)
        ret true
    }
    let c = child_for(t, node, key)
    let child = value_at(t, node, c)
    let went = remove_from(t, child, key)
    if !went { ret false }
    if usize(t.count[usize(child)]) > minimum_fill(t) {
        if usize(t.count[usize(child)]) > 0usize { set_key(t, node, c, key_at(t, child, 0usize)) }
        ret true
    }
    // Underfull: merge with a neighbour when both fit in one node, else
    // borrow one entry from it.
    let n = usize(t.count[usize(node)])
    if c + 1usize < n {
        let right = value_at(t, node, c + 1usize)
        if usize(t.count[usize(child)]) + usize(t.count[usize(right)]) < t.order {
            merge_node(t, node, c)
        } else {
            let cn = usize(t.count[usize(child)])
            set_key(t, child, cn, key_at(t, right, 0usize))
            set_value(t, child, cn, value_at(t, right, 0usize))
            t.count[usize(child)] = u32(cn + 1usize)
            let rn = usize(t.count[usize(right)])
            var j = 0usize
            while j + 1usize < rn {
                set_key(t, right, j, key_at(t, right, j + 1usize))
                set_value(t, right, j, value_at(t, right, j + 1usize))
                j += 1usize
            }
            t.count[usize(right)] = u32(rn - 1usize)
            set_key(t, node, c + 1usize, key_at(t, right, 0usize))
        }
        set_key(t, node, c, key_at(t, child, 0usize))
    } else if c > 0usize {
        let left = value_at(t, node, c - 1usize)
        if usize(t.count[usize(child)]) + usize(t.count[usize(left)]) < t.order {
            merge_node(t, node, c - 1usize)
        } else {
            let ln = usize(t.count[usize(left)])
            let cn = usize(t.count[usize(child)])
            var j = cn
            while j > 0usize {
                set_key(t, child, j, key_at(t, child, j - 1usize))
                set_value(t, child, j, value_at(t, child, j - 1usize))
                j -= 1usize
            }
            set_key(t, child, 0usize, key_at(t, left, ln - 1usize))
            set_value(t, child, 0usize, value_at(t, left, ln - 1usize))
            t.count[usize(child)] = u32(cn + 1usize)
            t.count[usize(left)] = u32(ln - 1usize)
            set_key(t, node, c, key_at(t, child, 0usize))
        }
    } else if usize(t.count[usize(child)]) > 0usize {
        set_key(t, node, c, key_at(t, child, 0usize))
    }
    ret true
}

fn remove(t: *Btree, key: u64) -> bool {
    let went = remove_from(t, t.root, key)
    // A root with a single child is replaced by it.
    while !t.leaf[usize(t.root)] && t.count[usize(t.root)] == 1u32 {
        let old = t.root
        t.root = value_at(t, t.root, 0usize)
        release(t, old)
        t.height -= 1usize
    }
    ret went
}

// The (key, value) pairs with `low <= key < high` in order into `keys`/`values`;
// answers the count.
fn scan(t: *const Btree, low: u64, high: u64, keys: []u64, values: []u32) -> (usize, err) {
    var node = t.root
    while !t.leaf[usize(node)] { node = value_at(t, node, child_for(t, node, low)) }
    var i = lower_bound(t, node, low)
    var n = 0usize
    while node != NONE {
        while i < usize(t.count[usize(node)]) {
            let k = key_at(t, node, i)
            if k >= high { ret (n, ok) }
            if n >= keys.len || n >= values.len { ret (n, TooSmall) }
            keys[n] = k
            values[n] = value_at(t, node, i)
            n += 1usize
            i += 1usize
        }
        node = t.next[usize(node)]
        i = 0usize
    }
    ret (n, ok)
}
