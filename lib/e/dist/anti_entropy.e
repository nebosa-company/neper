// Anti-entropy between two replicas by Merkle-tree comparison. A replica's
// state is a caller `[]const Entry` sorted by key; keys fall into fixed-width
// buckets (`key / width`), each bucket's leaf hash is FNV-1a over its entries
// (key then version, little-endian) and an inner node hashes its two children.
// `merkle_build` fills a caller heap-ordered `[]u64` (root at 1, leaves from
// `len / 2`, so the leaf count is a power of two); `merkle_sync` walks two
// trees top-down and answers the bucket indices whose hashes differ and how
// many hash comparisons it spent; `merkle_diff_keys` then lists the keys that
// differ inside those buckets (missing on either side or a different version).

type Entry = struct { key: u64, version: u64 }
type Merkle = struct { hashes: []u64, width: u64 }
error TooSmall
error Invalid

fn fnv_offset() -> u64 { ret 14695981039346656037u64 }

fn fnv_word(h: u64, v: u64) -> u64 {
    var acc = h
    var i = 0u32
    while i < 8u32 {
        acc = (acc ^ ((v >> (i * 8u32)) & 255u64)) *% 1099511628211u64
        i += 1u32
    }
    ret acc
}

fn leaves(m: *const Merkle) -> usize { ret m.hashes.len / 2usize }

// Build the tree over `entries` (sorted by key) with `width` keys per bucket
// into `hashes`, whose length is twice a power of two; Invalid when a key
// falls past the last bucket or the shape is wrong.
fn merkle_build(entries: []const Entry, width: u64, hashes: []u64) -> (Merkle, err) {
    let m = Merkle { hashes: hashes, width: width }
    let n = leaves(&m)
    if n == 0usize || width == 0u64 || (n & (n - 1usize)) != 0usize || hashes.len != 2usize * n { ret (m, Invalid) }
    var i = 0usize
    while i < n {
        hashes[n + i] = fnv_offset()
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        let b = usize(entries[i].key / width)
        if b >= n { ret (m, Invalid) }
        hashes[n + b] = fnv_word(fnv_word(hashes[n + b], entries[i].key), entries[i].version)
        i += 1usize
    }
    i = n
    while i > 1usize {
        i -= 1usize
        hashes[i] = fnv_word(fnv_word(fnv_offset(), hashes[2usize * i]), hashes[2usize * i + 1usize])
    }
    ret (m, ok)
}

fn sync_node(a: *const Merkle, b: *const Merkle, node: usize, out: []usize, count: *usize, comparisons: *usize) {
    *comparisons += 1usize
    if a.hashes[node] == b.hashes[node] { ret }
    if node >= leaves(a) {
        if *count < out.len { out[*count] = node - leaves(a) }
        *count += 1usize
        ret
    }
    sync_node(a, b, 2usize * node, out, count, comparisons)
    sync_node(a, b, 2usize * node + 1usize, out, count, comparisons)
}

// Answers (differing bucket count, hash comparisons, error): Invalid when the
// trees differ in shape or width, TooSmall when `out` did not hold every
// bucket (the counts are still exact).
fn merkle_sync(a: *const Merkle, b: *const Merkle, out: []usize) -> (usize, usize, err) {
    if a.hashes.len != b.hashes.len || a.width != b.width { ret (0usize, 0usize, Invalid) }
    var count = 0usize
    var comparisons = 0usize
    sync_node(a, b, 1usize, out, &count, &comparisons)
    if count > out.len { ret (count, comparisons, TooSmall) }
    ret (count, comparisons, ok)
}

// First index whose key is at least `key`.
fn lower_bound(entries: []const Entry, key: u64) -> usize {
    var lo = 0usize
    var hi = entries.len
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if entries[mid].key < key { lo = mid + 1usize } else { hi = mid }
    }
    ret lo
}

fn emit(out: []u64, count: *usize, key: u64) {
    if *count < out.len { out[*count] = key }
    *count += 1usize
}

// The keys inside `buckets` (from `merkle_sync`) that differ between `a` and
// `b`, in bucket then key order; TooSmall when `out` is short (count exact).
fn merkle_diff_keys(a: []const Entry, b: []const Entry, width: u64, buckets: []const usize, out: []u64) -> (usize, err) {
    var count = 0usize
    var k = 0usize
    while k < buckets.len {
        let lo = u64(buckets[k]) * width
        let hi = lo + width
        var i = lower_bound(a, lo)
        var j = lower_bound(b, lo)
        while (i < a.len && a[i].key < hi) || (j < b.len && b[j].key < hi) {
            let has_a = i < a.len && a[i].key < hi
            let has_b = j < b.len && b[j].key < hi
            if has_a && (!has_b || a[i].key < b[j].key) {
                emit(out, &count, a[i].key)
                i += 1usize
            } else if has_b && (!has_a || b[j].key < a[i].key) {
                emit(out, &count, b[j].key)
                j += 1usize
            } else {
                if a[i].version != b[j].version { emit(out, &count, a[i].key) }
                i += 1usize
                j += 1usize
            }
        }
        k += 1usize
    }
    if count > out.len { ret (count, TooSmall) }
    ret (count, ok)
}
