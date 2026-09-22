// Union-find over caller-supplied storage: `parent[i]` is the parent of `i` and a root
// is its own parent; `rank[i]` bounds the height of the tree under a root. `find`
// compresses the path it walks and `join` hangs the shorter tree under the taller,
// which together keep every operation near-constant amortised.

type DisjointSet = struct { parent: []u32, rank: []u8, sets: usize }
error TooLarge
error TooSmall

// `count` must fit a `u32` and both slices; every element starts as its own set.
fn init(parent: []u32, rank: []u8, count: usize) -> (DisjointSet, err) {
    if count > 4294967295usize { ret (zero, TooLarge) }
    if parent.len < count || rank.len < count { ret (zero, TooSmall) }
    var s = DisjointSet { parent: parent[..count], rank: rank[..count], sets: count }
    reset(&s)
    ret (s, ok)
}

fn len(s: *const DisjointSet) -> usize { ret s.parent.len }

fn set_count(s: *const DisjointSet) -> usize { ret s.sets }

// The root of `value`'s set, every element on the way pointed straight at it.
fn find(s: *DisjointSet, value: u32) -> u32 {
    var root = value
    while s.parent[usize(root)] != root { root = s.parent[usize(root)] }
    var at = value
    while s.parent[usize(at)] != root {
        let next = s.parent[usize(at)]
        s.parent[usize(at)] = root
        at = next
    }
    ret root
}

fn same(s: *DisjointSet, a: u32, b: u32) -> bool { ret find(s, a) == find(s, b) }

// Joins the two sets; `false` when they were one already.
fn join(s: *DisjointSet, a: u32, b: u32) -> bool {
    var root_a = find(s, a)
    var root_b = find(s, b)
    if root_a == root_b { ret false }
    if s.rank[usize(root_a)] < s.rank[usize(root_b)] {
        let swap = root_a
        root_a = root_b
        root_b = swap
    }
    s.parent[usize(root_b)] = root_a
    if s.rank[usize(root_a)] == s.rank[usize(root_b)] { s.rank[usize(root_a)] += 1u8 }
    s.sets -= 1usize
    ret true
}

fn reset(s: *DisjointSet) {
    var at = 0usize
    while at < s.parent.len {
        s.parent[at] = u32(at)
        s.rank[at] = 0u8
        at += 1usize
    }
    s.sets = s.parent.len
}

// ---- rollback ------------------------------------------------------------
// A union-find without path compression, so every union changes exactly one
// parent link and at most one rank, and a log of those changes lets `rollback`
// undo unions in reverse order: `log` holds two words per union.

type RollbackSet = struct { parent: []u32, rank: []u8, log: []u32, log_len: usize, sets: usize }

fn rollback_init(parent: []u32, rank: []u8, log: []u32, count: usize) -> (RollbackSet, err) {
    if count > 2147483647usize { ret (zero, TooLarge) }
    if parent.len < count || rank.len < count { ret (zero, TooSmall) }
    var at = 0usize
    while at < count {
        parent[at] = u32(at)
        rank[at] = 0u8
        at += 1usize
    }
    ret (RollbackSet { parent: parent[..count], rank: rank[..count], log: log, log_len: 0usize, sets: count }, ok)
}

// The root of `value`'s set, without compression.
fn rollback_find(s: *const RollbackSet, value: u32) -> u32 {
    var root = value
    while s.parent[usize(root)] != root { root = s.parent[usize(root)] }
    ret root
}

fn rollback_same(s: *const RollbackSet, a: u32, b: u32) -> bool { ret rollback_find(s, a) == rollback_find(s, b) }

// Joins the two sets, logging the change; `false` when they were one already
// (nothing is logged then), `TooSmall` when the log is full.
fn rollback_union(s: *RollbackSet, a: u32, b: u32) -> (bool, err) {
    var root_a = rollback_find(s, a)
    var root_b = rollback_find(s, b)
    if root_a == root_b { ret (false, ok) }
    if s.log_len + 2usize > s.log.len { ret (false, TooSmall) }
    if s.rank[usize(root_a)] < s.rank[usize(root_b)] {
        let swap = root_a
        root_a = root_b
        root_b = swap
    }
    var bumped = 0u32
    if s.rank[usize(root_a)] == s.rank[usize(root_b)] {
        s.rank[usize(root_a)] += 1u8
        bumped = 1u32
    }
    s.parent[usize(root_b)] = root_a
    s.log[s.log_len] = root_b
    s.log[s.log_len + 1usize] = (root_a << 1u32) | bumped
    s.log_len += 2usize
    s.sets -= 1usize
    ret (true, ok)
}

// A point to roll back to: the number of logged unions so far.
fn snapshot(s: *const RollbackSet) -> usize { ret s.log_len / 2usize }

// Undoes every union after snapshot `to`.
fn rollback(s: *RollbackSet, to: usize) {
    while s.log_len > to * 2usize {
        s.log_len -= 2usize
        let child = s.log[s.log_len]
        let word = s.log[s.log_len + 1usize]
        let root = word >> 1u32
        s.parent[usize(child)] = child
        if (word & 1u32) == 1u32 { s.rank[usize(root)] -= 1u8 }
        s.sets += 1usize
    }
}

fn rollback_set_count(s: *const RollbackSet) -> usize { ret s.sets }
