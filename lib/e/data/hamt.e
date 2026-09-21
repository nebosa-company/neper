// A persistent hash array mapped trie over `u64` keys and values in a caller
// pool: `put` and `remove` copy only the path from the root to the touched
// leaf, so every earlier root still answers its own mapping (structural
// sharing). The hash is the key through the splitmix64 finaliser, consumed
// five bits per level into 32-way bitmap nodes indexed by popcount. A node is
// a leaf when `first == NONE` (its `key`/`value` hold the entry) and a branch
// otherwise (`bitmap` names the occupied lanes, `slots[first..]` the children
// in lane order). `NONE` is the empty trie.

use e.bytes

const NONE: u32 = 4294967295u32

type Hamt = struct { bitmap: []u32, first: []u32, key: []u64, value: []u64, slots: []u32, used: usize, slots_used: usize }
error TooSmall
error Invalid

// A trie over parallel node arrays of one capacity and a child-slot pool.
fn hamt(bitmap: []u32, first: []u32, key: []u64, value: []u64, slots: []u32) -> Hamt {
    ret Hamt { bitmap: bitmap, first: first, key: key, value: value, slots: slots, used: 0usize, slots_used: 0usize }
}

fn mix(key: u64) -> u64 {
    var z = key +% 0x9e3779b97f4a7c15u64
    z = (z ^ (z >> 30u32)) *% 0xbf58476d1ce4e5b9u64
    z = (z ^ (z >> 27u32)) *% 0x94d049bb133111ebu64
    ret z ^ (z >> 31u32)
}

fn lane(hash: u64, shift: u32) -> u32 { ret u32((hash >> shift) & 31u64) }

fn is_leaf(h: *const Hamt, node: u32) -> bool { ret h.first[usize(node)] == NONE }

fn new_node(h: *Hamt) -> (u32, err) {
    if h.used >= h.bitmap.len || h.used >= h.first.len || h.used >= h.key.len || h.used >= h.value.len { ret (NONE, TooSmall) }
    let id = h.used
    h.used += 1usize
    ret (u32(id), ok)
}

fn new_leaf(h: *Hamt, key: u64, value: u64) -> (u32, err) {
    let (id, e) = new_node(h)
    if e != ok { ret (NONE, e) }
    h.first[usize(id)] = NONE
    h.key[usize(id)] = key
    h.value[usize(id)] = value
    ret (id, ok)
}

// A branch with `bitmap` and `width` fresh (unfilled) slots.
fn new_branch(h: *Hamt, bitmap: u32, width: usize) -> (u32, err) {
    if h.slots_used + width > h.slots.len { ret (NONE, TooSmall) }
    let (id, e) = new_node(h)
    if e != ok { ret (NONE, e) }
    h.bitmap[usize(id)] = bitmap
    h.first[usize(id)] = u32(h.slots_used)
    h.slots_used += width
    ret (id, ok)
}

// A branch holding two leaves whose hashes first differ at or below `shift`.
fn pair(h: *Hamt, old: u32, old_hash: u64, key: u64, value: u64, hash: u64, shift: u32) -> (u32, err) {
    // ponytail: a full 64-bit collision is refused, not chained; add a collision list if keys are ever adversarial.
    if shift > 60u32 { ret (NONE, Invalid) }
    let a = lane(old_hash, shift)
    let b = lane(hash, shift)
    if a == b {
        let (child, child_error) = pair(h, old, old_hash, key, value, hash, shift + 5u32)
        if child_error != ok { ret (NONE, child_error) }
        let (branch, branch_error) = new_branch(h, 1u32 << a, 1usize)
        if branch_error != ok { ret (NONE, branch_error) }
        h.slots[usize(h.first[usize(branch)])] = child
        ret (branch, ok)
    }
    let (leaf, leaf_error) = new_leaf(h, key, value)
    if leaf_error != ok { ret (NONE, leaf_error) }
    let (branch, branch_error) = new_branch(h, (1u32 << a) | (1u32 << b), 2usize)
    if branch_error != ok { ret (NONE, branch_error) }
    let f = usize(h.first[usize(branch)])
    if a < b {
        h.slots[f] = old
        h.slots[f + 1usize] = leaf
    } else {
        h.slots[f] = leaf
        h.slots[f + 1usize] = old
    }
    ret (branch, ok)
}

fn put_at(h: *Hamt, node: u32, hash: u64, shift: u32, key: u64, value: u64) -> (u32, err) {
    if node == NONE {
        let (leaf, e) = new_leaf(h, key, value)
        ret (leaf, e)
    }
    let n = usize(node)
    if is_leaf(h, node) {
        if h.key[n] == key {
            let (leaf, e) = new_leaf(h, key, value)
            ret (leaf, e)
        }
        let (branch, e) = pair(h, node, mix(h.key[n]), key, value, hash, shift)
        ret (branch, e)
    }
    let bit = 1u32 << lane(hash, shift)
    let bitmap = h.bitmap[n]
    let width = usize(bytes.count_ones[u32](bitmap))
    let index = usize(bytes.count_ones[u32](bitmap & (bit - 1u32)))
    let from = usize(h.first[n])
    if bitmap & bit != 0u32 {
        let (child, child_error) = put_at(h, h.slots[from + index], hash, shift + 5u32, key, value)
        if child_error != ok { ret (NONE, child_error) }
        let (branch, branch_error) = new_branch(h, bitmap, width)
        if branch_error != ok { ret (NONE, branch_error) }
        let to = usize(h.first[usize(branch)])
        var i = 0usize
        while i < width {
            h.slots[to + i] = h.slots[from + i]
            i += 1usize
        }
        h.slots[to + index] = child
        ret (branch, ok)
    }
    let (leaf, leaf_error) = new_leaf(h, key, value)
    if leaf_error != ok { ret (NONE, leaf_error) }
    let (branch, branch_error) = new_branch(h, bitmap | bit, width + 1usize)
    if branch_error != ok { ret (NONE, branch_error) }
    let to = usize(h.first[usize(branch)])
    var i = 0usize
    while i < index {
        h.slots[to + i] = h.slots[from + i]
        i += 1usize
    }
    h.slots[to + index] = leaf
    while i < width {
        h.slots[to + i + 1usize] = h.slots[from + i]
        i += 1usize
    }
    ret (branch, ok)
}

// Map `key` to `value` in a new version; `root` still describes the old one.
fn put(h: *Hamt, root: u32, key: u64, value: u64) -> (u32, err) {
    let (version, e) = put_at(h, root, mix(key), 0u32, key, value)
    ret (version, e)
}

// The value under `key` and whether it is present.
fn get(h: *const Hamt, root: u32, key: u64) -> (u64, bool) {
    let hash = mix(key)
    var node = root
    var shift = 0u32
    while node != NONE {
        let n = usize(node)
        if is_leaf(h, node) {
            if h.key[n] == key { ret (h.value[n], true) }
            ret (0u64, false)
        }
        let bit = 1u32 << lane(hash, shift)
        if h.bitmap[n] & bit == 0u32 { ret (0u64, false) }
        node = h.slots[usize(h.first[n]) + usize(bytes.count_ones[u32](h.bitmap[n] & (bit - 1u32)))]
        shift += 5u32
    }
    ret (0u64, false)
}

// Answers (new node, whether anything changed, error).
fn remove_at(h: *Hamt, node: u32, hash: u64, shift: u32, key: u64) -> (u32, bool, err) {
    if node == NONE { ret (NONE, false, ok) }
    let n = usize(node)
    if is_leaf(h, node) { ret (NONE, h.key[n] == key, ok) }
    let bit = 1u32 << lane(hash, shift)
    let bitmap = h.bitmap[n]
    if bitmap & bit == 0u32 { ret (node, false, ok) }
    let width = usize(bytes.count_ones[u32](bitmap))
    let index = usize(bytes.count_ones[u32](bitmap & (bit - 1u32)))
    let from = usize(h.first[n])
    let (child, changed, child_error) = remove_at(h, h.slots[from + index], hash, shift + 5u32, key)
    if child_error != ok { ret (NONE, false, child_error) }
    if !changed { ret (node, false, ok) }
    if child == NONE {
        if width == 1usize { ret (NONE, true, ok) }
        if width == 2usize {
            let other = h.slots[from + (1usize - index)]
            if is_leaf(h, other) { ret (other, true, ok) }
        }
        let (branch, branch_error) = new_branch(h, bitmap & ~bit, width - 1usize)
        if branch_error != ok { ret (NONE, false, branch_error) }
        let to = usize(h.first[usize(branch)])
        var i = 0usize
        while i < index {
            h.slots[to + i] = h.slots[from + i]
            i += 1usize
        }
        while i + 1usize < width {
            h.slots[to + i] = h.slots[from + i + 1usize]
            i += 1usize
        }
        ret (branch, true, ok)
    }
    if width == 1usize && is_leaf(h, child) { ret (child, true, ok) }
    let (branch, branch_error) = new_branch(h, bitmap, width)
    if branch_error != ok { ret (NONE, false, branch_error) }
    let to = usize(h.first[usize(branch)])
    var i = 0usize
    while i < width {
        h.slots[to + i] = h.slots[from + i]
        i += 1usize
    }
    h.slots[to + index] = child
    ret (branch, true, ok)
}

// Drop `key` in a new version (the same root when absent); `root` still describes the old one.
fn remove(h: *Hamt, root: u32, key: u64) -> (u32, err) {
    let (version, _, e) = remove_at(h, root, mix(key), 0u32, key)
    ret (version, e)
}

// The number of entries reachable from `root`.
fn count(h: *const Hamt, root: u32) -> usize {
    if root == NONE { ret 0usize }
    let n = usize(root)
    if is_leaf(h, root) { ret 1usize }
    let width = usize(bytes.count_ones[u32](h.bitmap[n]))
    var total = 0usize
    var i = 0usize
    while i < width {
        total += count(h, h.slots[usize(h.first[n]) + i])
        i += 1usize
    }
    ret total
}
