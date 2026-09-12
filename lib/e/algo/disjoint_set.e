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
