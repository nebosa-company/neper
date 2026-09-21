// A skip list over a caller node pool: keys ordered by `K.cmp`, each node
// with a geometrically distributed height (a coin per level from the
// caller's PCG generator) and forward links per level. Node 0 is the head
// with every level; `NONE` ends a level. Removed nodes go on a free list.

use e.algo.rand

type SkipList[K: type] = struct { keys: []K, forward: []u32, height: []u8, levels: usize, used: usize, free: u32, count: usize }
error TooSmall
error Invalid

const NONE: u32 = 4294967295u32

// A list of at most `keys.len` nodes over `levels` levels;
// `forward.len >= keys.len * levels`, `height.len >= keys.len`.
fn skip_list[K: type](keys: []K, forward: []u32, height: []u8, levels: usize) -> (SkipList[K], err) {
    if levels == 0usize || levels > 64usize { ret (zero, Invalid) }
    if keys.len < 1usize || forward.len < keys.len * levels || height.len < keys.len { ret (zero, TooSmall) }
    var l = 0usize
    while l < levels {
        forward[l] = NONE
        l += 1usize
    }
    height[0usize] = u8(levels)
    ret (SkipList[K] { keys: keys, forward: forward, height: height, levels: levels, used: 1usize, free: NONE, count: 0usize }, ok)
}

fn link[K: type](s: *const SkipList[K], node: u32, level: usize) -> u32 { ret s.forward[usize(node) * s.levels + level] }

// Insert `key`; a duplicate is refused with `Invalid`.
fn insert[K: type](s: *SkipList[K], key: K, r: *rand.Pcg64) -> err {
    // Find the predecessors at every level, kept in the new node's own slots
    // until it exists; use the head's links walk with a small local array.
    var update: [64]u32 = zero
    var node = 0u32
    var level = s.levels
    while level > 0usize {
        level -= 1usize
        var after = link[K](s, node, level)
        while after != NONE && K.cmp(s.keys[usize(after)], key) < 0i32 {
            node = after
            after = link[K](s, node, level)
        }
        update[level] = node
    }
    let candidate = link[K](s, node, 0usize)
    if candidate != NONE && K.cmp(s.keys[usize(candidate)], key) == 0i32 { ret Invalid }
    // A slot: the free list first, else a fresh one.
    var id = s.free
    if id != NONE {
        s.free = s.forward[usize(id) * s.levels]
    } else {
        if s.used >= s.keys.len { ret TooSmall }
        id = u32(s.used)
        s.used += 1usize
    }
    var h = 1usize
    while h < s.levels && (rand.pcg64_next(r) & 1u64) == 1u64 { h += 1usize }
    s.keys[usize(id)] = key
    s.height[usize(id)] = u8(h)
    level = 0usize
    while level < h {
        s.forward[usize(id) * s.levels + level] = link[K](s, update[level], level)
        s.forward[usize(update[level]) * s.levels + level] = id
        level += 1usize
    }
    s.count += 1usize
    ret ok
}

// Remove `key`; answers whether it was there.
fn remove[K: type](s: *SkipList[K], key: K) -> bool {
    var update: [64]u32 = zero
    var node = 0u32
    var level = s.levels
    while level > 0usize {
        level -= 1usize
        var after = link[K](s, node, level)
        while after != NONE && K.cmp(s.keys[usize(after)], key) < 0i32 {
            node = after
            after = link[K](s, node, level)
        }
        update[level] = node
    }
    let found = link[K](s, node, 0usize)
    if found == NONE || K.cmp(s.keys[usize(found)], key) != 0i32 { ret false }
    level = 0usize
    while level < usize(s.height[usize(found)]) {
        s.forward[usize(update[level]) * s.levels + level] = link[K](s, found, level)
        level += 1usize
    }
    s.forward[usize(found) * s.levels] = s.free
    s.free = found
    s.count -= 1usize
    ret true
}

fn contains[K: type](s: *const SkipList[K], key: K) -> bool {
    var node = 0u32
    var level = s.levels
    while level > 0usize {
        level -= 1usize
        var after = link[K](s, node, level)
        while after != NONE && K.cmp(s.keys[usize(after)], key) < 0i32 {
            node = after
            after = link[K](s, node, level)
        }
    }
    let found = link[K](s, node, 0usize)
    ret found != NONE && K.cmp(s.keys[usize(found)], key) == 0i32
}

// The first node whose key is not below `key`, or `NONE`.
fn lower_bound[K: type](s: *const SkipList[K], key: K) -> u32 {
    var node = 0u32
    var level = s.levels
    while level > 0usize {
        level -= 1usize
        var after = link[K](s, node, level)
        while after != NONE && K.cmp(s.keys[usize(after)], key) < 0i32 {
            node = after
            after = link[K](s, node, level)
        }
    }
    ret link[K](s, node, 0usize)
}

// The node after `node` at the bottom level (`NONE` at the end); the first
// node is `next(0)`.
fn next[K: type](s: *const SkipList[K], node: u32) -> u32 { ret link[K](s, node, 0usize) }

// The keys in order into `out`; answers the count.
fn collect[K: type](s: *const SkipList[K], out: []K) -> (usize, err) {
    var n = 0usize
    var node = link[K](s, 0u32, 0usize)
    while node != NONE {
        if n >= out.len { ret (n, TooSmall) }
        out[n] = s.keys[usize(node)]
        n += 1usize
        node = link[K](s, node, 0usize)
    }
    ret (n, ok)
}
