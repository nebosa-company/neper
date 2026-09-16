// An ordered map: a treap whose priorities come from the key's own hash, so the shape
// is a function of the keys alone and the same on every run. Nodes are individual
// arena allocations with parent pointers, which is what lets an iterator be one
// pointer -- the node it is at -- and step to the in-order successor without the map.
// A removed node goes on a free list and is reused; nothing here promises identity.
//
// Keys need `cmp` and `hash`, which section 9 gives every scalar, slice, array and
// enum, and a struct by declaring them. `Set[K]` is `Map[K, bool]`.
//
// ponytail: a treap is the shortest balanced tree that is correct; an adversary who can
// choose keys that collide in the hash can make it a list, which no caller here can.

use e.mem

type Map[K: type, V: type] = struct { state: *void }
type Set[K: type] = struct { map: Map[K, bool] }
type Iter[K: type, V: type] = struct { state: *const void }
type SetIter[K: type] = struct { inner: Iter[K, bool] }

type Node[K: type, V: type] = struct { key: K, value: V, priority: u64, left: *Node[K, V], right: *Node[K, V], parent: *Node[K, V] }
type State[K: type, V: type] = struct { root: *Node[K, V], free: *Node[K, V], count: usize, arena: *mem.Arena }

// `init` cannot fail by its signature, so a map whose state could not be allocated is
// the empty map that every later `put` refuses with the arena's error.
fn init[K: type, V: type](a: *mem.Arena) -> Map[K, V] {
    var m: Map[K, V] = zero
    let (storage, storage_error) = mem.alloc[State[K, V]](a, 1usize)
    if storage_error != ok { ret m }
    storage[0usize].root = nil
    storage[0usize].free = nil
    storage[0usize].count = 0usize
    storage[0usize].arena = a
    m.state = mem.cast[*void](&storage[0usize])
    ret m
}

fn len[K: type, V: type](m: *const Map[K, V]) -> usize {
    if m.state == nil { ret 0usize }
    let s = mem.cast[*const State[K, V]](m.state)
    ret s.count
}

// The key's hash, stirred once so that keys hashing to nearby values do not sit in one
// long chain of priorities.
fn priority_of[K: type](key: K) -> u64 {
    let digest: u64 = K.hash(key)
    var x = digest ^ (digest >> 33u32)
    x = x *% 18397679294719823053u64
    x = x ^ (x >> 29u32)
    ret x
}

// The node holding `key`, or the last node on the way to where it would go.
fn locate[K: type, V: type](s: *const State[K, V], key: K) -> (*Node[K, V], i32) {
    var at = s.root
    var last: *Node[K, V] = nil
    var order = 0i32
    while at != nil {
        last = at
        order = K.cmp(key, at.key)
        if order == 0i32 { ret (at, 0i32) }
        if order < 0i32 { at = at.left } else { at = at.right }
    }
    ret (last, order)
}

// `child` takes `n`'s place under `n`'s parent.
fn replace_child[K: type, V: type](s: *State[K, V], n: *Node[K, V], child: *Node[K, V]) {
    let up = n.parent
    if up == nil {
        s.root = child
    } else {
        if up.left == n { up.left = child } else { up.right = child }
    }
    if child != nil { child.parent = up }
}

// `n`'s right child comes up over it.
fn rotate_left[K: type, V: type](s: *State[K, V], n: *Node[K, V]) {
    let r = n.right
    replace_child[K, V](s, n, r)
    n.right = r.left
    if n.right != nil { n.right.parent = n }
    r.left = n
    n.parent = r
}

fn rotate_right[K: type, V: type](s: *State[K, V], n: *Node[K, V]) {
    let l = n.left
    replace_child[K, V](s, n, l)
    n.left = l.right
    if n.left != nil { n.left.parent = n }
    l.right = n
    n.parent = l
}

// `true` when the key was new; an existing key's value is replaced.
fn put[K: type, V: type](m: *Map[K, V], key: K, value: own V) -> (bool, err) {
    if m.state == nil { ret (false, mem.Exhausted) }
    let s = mem.cast[*State[K, V]](m.state)
    let (near, order) = locate[K, V](s, key)
    if near != nil && order == 0i32 {
        near.value = value
        ret (false, ok)
    }
    var n = s.free
    if n != nil {
        s.free = n.right
    } else {
        let (storage, storage_error) = mem.alloc[Node[K, V]](s.arena, 1usize)
        if storage_error != ok { ret (false, storage_error) }
        n = &storage[0usize]
    }
    n.key = key
    n.value = value
    n.priority = priority_of[K](key)
    n.left = nil
    n.right = nil
    n.parent = near
    if near == nil {
        s.root = n
    } else {
        if order < 0i32 { near.left = n } else { near.right = n }
    }
    // Rotate up while the parent's priority is lower: the heap order over priorities.
    while n.parent != nil && n.parent.priority < n.priority {
        if n.parent.left == n { rotate_right[K, V](s, n.parent) } else { rotate_left[K, V](s, n.parent) }
    }
    s.count += 1usize
    ret (true, ok)
}

fn get[K: type, V: type](m: *const Map[K, V], key: K) -> (V, bool) {
    if m.state == nil { ret (zero, false) }
    let s = mem.cast[*const State[K, V]](m.state)
    let (near, order) = locate[K, V](s, key)
    if near == nil || order != 0i32 { ret (zero, false) }
    ret (near.value, true)
}

// The first node whose key is not less than `key` -- nil when every key is less.
fn bound_node[K: type, V: type](s: *const State[K, V], key: K, strict: bool) -> *Node[K, V] {
    var at = s.root
    var best: *Node[K, V] = nil
    while at != nil {
        let order = K.cmp(key, at.key)
        var goes_left = order < 0i32
        if !strict && order == 0i32 { ret at }
        if strict && order == 0i32 { goes_left = false }
        if goes_left {
            best = at
            at = at.left
        } else {
            at = at.right
        }
    }
    ret best
}

fn lower_bound[K: type, V: type](m: *const Map[K, V], key: K) -> (K, V, bool) {
    if m.state == nil { ret (zero, zero, false) }
    let s = mem.cast[*const State[K, V]](m.state)
    let n = bound_node[K, V](s, key, false)
    if n == nil { ret (zero, zero, false) }
    ret (n.key, n.value, true)
}

fn upper_bound[K: type, V: type](m: *const Map[K, V], key: K) -> (K, V, bool) {
    if m.state == nil { ret (zero, zero, false) }
    let s = mem.cast[*const State[K, V]](m.state)
    let n = bound_node[K, V](s, key, true)
    if n == nil { ret (zero, zero, false) }
    ret (n.key, n.value, true)
}

fn remove[K: type, V: type](m: *Map[K, V], key: K) -> (V, bool) {
    if m.state == nil { ret (zero, false) }
    let s = mem.cast[*State[K, V]](m.state)
    let (n, order) = locate[K, V](s, key)
    if n == nil || order != 0i32 { ret (zero, false) }
    let value = n.value
    // Rotate the node down, the higher-priority child coming up, until it has at most
    // one child; then that child takes its place.
    while n.left != nil && n.right != nil {
        if n.left.priority > n.right.priority { rotate_right[K, V](s, n) } else { rotate_left[K, V](s, n) }
    }
    var child = n.left
    if child == nil { child = n.right }
    replace_child[K, V](s, n, child)
    n.left = nil
    n.parent = nil
    n.right = s.free
    s.free = n
    s.count -= 1usize
    ret (value, true)
}

// Every node onto the free list, by walking the tree without the stack a recursion
// would need: from each node, go down; at a leaf, unlink it and continue from its parent.
fn clear[K: type, V: type](m: *Map[K, V]) {
    if m.state == nil { ret }
    let s = mem.cast[*State[K, V]](m.state)
    var at = s.root
    while at != nil {
        if at.left != nil {
            at = at.left
        } else {
            if at.right != nil {
                at = at.right
            } else {
                let up = at.parent
                if up != nil {
                    if up.left == at { up.left = nil } else { up.right = nil }
                }
                at.parent = nil
                at.right = s.free
                s.free = at
                at = up
            }
        }
    }
    s.root = nil
    s.count = 0usize
}

fn set_init[K: type](a: *mem.Arena) -> Set[K] {
    ret Set[K] { map: init[K, bool](a) }
}

fn set_add[K: type](s: *Set[K], key: K) -> (bool, err) {
    let (added, put_error) = put[K, bool](&s.map, key, true)
    ret (added, put_error)
}

fn set_has[K: type](s: *const Set[K], key: K) -> bool {
    let (_, has) = get[K, bool](&s.map, key)
    ret has
}

fn set_remove[K: type](s: *Set[K], key: K) -> bool {
    let (_, removed) = remove[K, bool](&s.map, key)
    ret removed
}

fn leftmost[K: type, V: type](from: *Node[K, V]) -> *Node[K, V] {
    var at = from
    while at != nil && at.left != nil { at = at.left }
    ret at
}

fn iter[K: type, V: type](m: *const Map[K, V]) -> Iter[K, V] {
    var it: Iter[K, V] = zero
    if m.state == nil { ret it }
    let s = mem.cast[*const State[K, V]](m.state)
    it.state = mem.cast[*const void](leftmost[K, V](s.root))
    ret it
}

fn iter_from[K: type, V: type](m: *const Map[K, V], key: K) -> Iter[K, V] {
    var it: Iter[K, V] = zero
    if m.state == nil { ret it }
    let s = mem.cast[*const State[K, V]](m.state)
    it.state = mem.cast[*const void](bound_node[K, V](s, key, false))
    ret it
}

// The in-order successor: the leftmost of the right subtree, else the first ancestor
// this node is to the left of.
fn iter_next[K: type, V: type](it: *Iter[K, V]) -> (K, V, bool) {
    if it.state == nil { ret (zero, zero, false) }
    // The iterator holds the node as `*const void` per the surface; the walk needs the
    // node's own pointer type, and reads only.
    let n = mem.cast[*Node[K, V]](it.state)
    var next: *Node[K, V] = nil
    if n.right != nil {
        next = leftmost[K, V](n.right)
    } else {
        var child = n
        var up = n.parent
        while up != nil && up.right == child {
            child = up
            up = up.parent
        }
        next = up
    }
    it.state = mem.cast[*const void](next)
    ret (n.key, n.value, true)
}

fn set_iter[K: type](s: *const Set[K]) -> SetIter[K] {
    ret SetIter[K] { inner: iter[K, bool](&s.map) }
}

fn set_iter_next[K: type](it: *SetIter[K]) -> (K, bool) {
    let (key, _, has) = iter_next[K, bool](&it.inner)
    ret (key, has)
}
