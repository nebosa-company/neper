// Merkle trees by RFC 6962 over `e.crypto.hash`'s SHA-256: a leaf is
// SHA-256(0x00 || data), an inner node is SHA-256(0x01 || left || right), an
// n-leaf tree splits at k = the largest power of two below n (no duplication),
// and the empty tree is SHA-256(""). `build` lays every node into caller
// storage (`nodes_required(n)` bytes: 2n-1 hashes of 32 bytes) as one block per
// subtree -- the subtree's root first, then the left block, then the right --
// so `audit_path` (inclusion, section 2.1.1) and `consistency_proof` (section
// 2.1.2) walk O(log n) blocks and read sibling roots in O(1). `verify` and
// `verify_consistency` are the verification algorithms of sections 2.1.3.2 and
// 2.1.4.2 over the root hashes alone.

use e.crypto.hash as hash

type Tree = struct { nodes: []u8, n: usize }
error TooSmall
error Invalid

// Bytes `build` needs for `n` leaves.
fn nodes_required(n: usize) -> usize {
    if n == 0usize { ret 0usize }
    ret (2usize * n - 1usize) * 32usize
}

fn leaf_hash(data: []const u8) -> [32]u8 {
    var s = hash.sha256_init()
    var prefix: [1]u8 = zero
    hash.sha256_update(&s, prefix[0..])
    hash.sha256_update(&s, data)
    ret hash.sha256_done(&s)
}

fn inner_hash(left: []const u8, right: []const u8) -> [32]u8 {
    var s = hash.sha256_init()
    var prefix: [1]u8 = [1]u8{ 1 }
    hash.sha256_update(&s, prefix[0..])
    hash.sha256_update(&s, left)
    hash.sha256_update(&s, right)
    ret hash.sha256_done(&s)
}

// The largest power of two strictly below `n` (n >= 2).
fn split_point(n: usize) -> usize {
    var k = 1usize
    while k * 2usize < n { k *= 2usize }
    ret k
}

fn copy_hash(out: []u8, at: usize, h: [32]u8) {
    var i = 0usize
    while i < 32usize {
        out[at + i] = h[i]
        i += 1usize
    }
}

// Hash leaves[lo..hi) into the block at slot `base`.
fn build_range(leaves: []const []const u8, nodes: []u8, lo: usize, hi: usize, base: usize) {
    let size = hi - lo
    if size == 1usize {
        copy_hash(nodes, base * 32usize, leaf_hash(leaves[lo]))
        ret
    }
    let k = split_point(size)
    let left = base + 1usize
    let right = base + 2usize * k
    build_range(leaves, nodes, lo, lo + k, left)
    build_range(leaves, nodes, lo + k, hi, right)
    let h = inner_hash(nodes[left * 32usize..left * 32usize + 32usize], nodes[right * 32usize..right * 32usize + 32usize])
    copy_hash(nodes, base * 32usize, h)
}

// Build the tree over `leaves` into `nodes` (at least `nodes_required(leaves.len)` bytes).
fn build(leaves: []const []const u8, nodes: []u8) -> (Tree, err) {
    let need = nodes_required(leaves.len)
    if nodes.len < need { ret (Tree { nodes: nodes, n: 0usize }, TooSmall) }
    if leaves.len > 0usize { build_range(leaves, nodes, 0usize, leaves.len, 0usize) }
    ret (Tree { nodes: nodes[..need], n: leaves.len }, ok)
}

fn root(t: *const Tree) -> [32]u8 {
    if t.n == 0usize {
        let none: [0]u8 = zero
        ret hash.sha256(none[0..])
    }
    ret root_at(t, 0usize)
}

// Inclusion proof for leaf `index`: sibling hashes from the leaf up, 32 bytes
// each, into `out`; answers the bytes written.
fn audit_path(t: *const Tree, index: usize, out: []u8) -> (usize, err) {
    if index >= t.n { ret (0usize, Invalid) }
    var lo = 0usize
    var hi = t.n
    var base = 0usize
    var depth = 0usize
    // Descend, remembering the sibling block at each level (top-down).
    var siblings: [64]usize = zero
    while hi - lo > 1usize {
        let k = split_point(hi - lo)
        let left = base + 1usize
        let right = base + 2usize * k
        if index < lo + k {
            siblings[depth] = right
            hi = lo + k
            base = left
        } else {
            siblings[depth] = left
            lo = lo + k
            base = right
        }
        depth += 1usize
    }
    if out.len < depth * 32usize { ret (0usize, TooSmall) }
    // Emit bottom-up.
    var written = 0usize
    while depth > 0usize {
        depth -= 1usize
        copy_hash(out, written, root_at(t, siblings[depth]))
        written += 32usize
    }
    ret (written, ok)
}

fn same(a: [32]u8, b: [32]u8) -> bool {
    var i = 0usize
    while i < 32usize {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// Verify an inclusion proof (RFC 6962 section 2.1.3.2): `leaf_data` sits at
// `index` in an `n`-leaf tree whose root is `root_hash`.
fn verify(root_hash: [32]u8, leaf_data: []const u8, index: usize, n: usize, path: []const u8) -> bool {
    if n == 0usize || index >= n || path.len % 32usize != 0usize { ret false }
    var fn_ = index
    var sn = n - 1usize
    var r = leaf_hash(leaf_data)
    var at = 0usize
    while at < path.len {
        if sn == 0usize { ret false }
        let c = path[at..at + 32usize]
        if (fn_ & 1usize) == 1usize || fn_ == sn {
            r = inner_hash(c, r[0..])
            while fn_ != 0usize && (fn_ & 1usize) == 0usize {
                fn_ = fn_ >> 1u32
                sn = sn >> 1u32
            }
        } else {
            r = inner_hash(r[0..], c)
        }
        fn_ = fn_ >> 1u32
        sn = sn >> 1u32
        at += 32usize
    }
    ret sn == 0usize && same(r, root_hash)
}

// Consistency proof (RFC 6962 section 2.1.2) from the first `m` leaves to the
// whole tree, 32 bytes per node into `out`; answers the bytes written.
fn consistency_proof(t: *const Tree, m: usize, out: []u8) -> (usize, err) {
    if m == 0usize || m > t.n { ret (0usize, Invalid) }
    // SUBPROOF walks down toward D[0:m]; the hashes it appends come out in
    // bottom-up order, so collect the slots top-down and emit reversed.
    var slots: [64]usize = zero
    var depth = 0usize
    var lo = 0usize
    var hi = t.n
    var base = 0usize
    var want = m
    var whole = true
    while want < hi - lo {
        let k = split_point(hi - lo)
        let left = base + 1usize
        let right = base + 2usize * k
        if want <= k {
            slots[depth] = right
            hi = lo + k
            base = left
        } else {
            slots[depth] = left
            want = want - k
            lo = lo + k
            base = right
            whole = false
        }
        depth += 1usize
    }
    var need = depth * 32usize
    if !whole { need += 32usize }
    if out.len < need { ret (0usize, TooSmall) }
    var written = 0usize
    if !whole {
        // SUBPROOF(m, D[m], false) = {MTH(D[m])}: the block we stopped in.
        copy_hash(out, 0usize, root_at(t, base))
        written = 32usize
    }
    while depth > 0usize {
        depth -= 1usize
        copy_hash(out, written, root_at(t, slots[depth]))
        written += 32usize
    }
    ret (written, ok)
}

fn root_at(t: *const Tree, index: usize) -> [32]u8 {
    var out: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        out[i] = t.nodes[index * 32usize + i]
        i += 1usize
    }
    ret out
}

// Verify a consistency proof (RFC 6962 section 2.1.4.2) between the `m`-leaf
// tree with root `old_root` and the `n`-leaf tree with root `new_root`.
fn verify_consistency(old_root: [32]u8, new_root: [32]u8, m: usize, n: usize, proof: []const u8) -> bool {
    if m == 0usize || m > n || proof.len % 32usize != 0usize { ret false }
    if m == n { ret proof.len == 0usize && same(old_root, new_root) }
    if proof.len == 0usize { ret false }
    var fn_ = m - 1usize
    var sn = n - 1usize
    while (fn_ & 1usize) == 1usize {
        fn_ = fn_ >> 1u32
        sn = sn >> 1u32
    }
    var fr: [32]u8 = zero
    var at = 0usize
    if (m & (m - 1usize)) == 0usize {
        fr = old_root
    } else {
        fr = root_at_slice(proof, 0usize)
        at = 32usize
    }
    var sr = fr
    while at < proof.len {
        if sn == 0usize { ret false }
        let c = proof[at..at + 32usize]
        if (fn_ & 1usize) == 1usize || fn_ == sn {
            fr = inner_hash(c, fr[0..])
            sr = inner_hash(c, sr[0..])
            while fn_ != 0usize && (fn_ & 1usize) == 0usize {
                fn_ = fn_ >> 1u32
                sn = sn >> 1u32
            }
        } else {
            sr = inner_hash(sr[0..], c)
        }
        fn_ = fn_ >> 1u32
        sn = sn >> 1u32
        at += 32usize
    }
    ret sn == 0usize && same(fr, old_root) && same(sr, new_root)
}

fn root_at_slice(bytes: []const u8, at: usize) -> [32]u8 {
    var out: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        out[i] = bytes[at + i]
        i += 1usize
    }
    ret out
}
