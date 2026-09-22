// Storage-engine mechanics as in-memory simulations over caller storage,
// `u64` keys and `i64` values. A B+tree over node arrays with leaf sibling
// links (`btree_insert`, `btree_find`, `btree_range`, `btree_next_leaf`);
// dense and sparse indexes over a paged sorted key column and bitmap
// indexes over a low-cardinality column; linear and extendible hash
// indexes; an LSM tier (`memtable_flush` to a sorted run with a sparse
// index and a Bloom filter, `sstable_find`, `lsm_compact`, `lsm_find`);
// a write-ahead log with CRC32 records (`wal_append`, `checkpoint`,
// `wal_truncate`, `recover` into a `Table`); a buffer pool with LRU, CLOCK
// and LRU-2 eviction; and transaction simulations: strict 2PL with a
// wait-for graph (`txn_lock_2pl`), MVCC versions with `vacuum`, and
// optimistic validation (`occ_validate`).

use e.algo.hash
use e.dist.deadlock as dl

type BTree = struct { keys: []u64, vals: []i64, children: []u32, next_leaf: []u32, n: []u32, leaf: []bool, fanout: usize, root: u32, used: usize, height: usize }
type IndexEntry = struct { key: u64, page: u32, slot: u32 }
type LinearHash = struct { slots: []u64, vals: []i64, filled: []bool, overflow: []u32, bucket_size: usize, initial: usize, level: u32, split_ptr: usize, top: usize, n: usize, max_load: usize }
type ExtHash = struct { directory: []u32, global_depth: u32, slots: []u64, vals: []i64, filled: []bool, local_depth: []u32, bucket_size: usize, used: usize, n: usize }
type SsTable = struct { keys: []u64, vals: []i64, tomb: []bool, n: usize, index_keys: []u64, index_pos: []u32, index_n: usize, bloom: []u64, stride: usize }
type Wal = struct { log: []u8, used: usize, next_lsn: u64 }
type Table = struct { keys: []u64, vals: []i64, n: usize }
type Policy = enum u8 { Lru, Clock, LruK }
type Pool = struct { frames: []u64, valid: []bool, stamp: []u64, hist: []u64, ref_bit: []bool, policy: Policy, hand: usize, clock: u64, hits: usize, misses: usize }
type LockTable = struct { keys: []u64, owners: []u32, exclusive: []bool, n: usize, waits: []dl.Edge, wait_n: usize, scratch: []usize, txns: usize }
type Mvcc = struct { keys: []u64, vals: []i64, begin: []u64, end: []u64, writer: []u32, n: usize }
type Occ = struct { start_ts: u64, read_keys: []u64, read_n: usize, write_keys: []u64, write_vals: []i64, write_n: usize }
type CommitLog = struct { keys: []u64, ts: []u64, n: usize }
error Full
error TooSmall
error Invalid
error Corrupt

const NONE: u32 = 4294967295u32
const FOREVER: u64 = 18446744073709551615u64
const RECORD: usize = 29usize
const KIND_PUT: u8 = 0u8
const KIND_DELETE: u8 = 1u8
const KIND_CHECKPOINT: u8 = 2u8

// splitmix64 finaliser: the hash behind every hash index and Bloom filter.
fn mix(key: u64) -> u64 {
    var h = key ^ (key >> 30u32)
    h = h *% 13787848793156543929u64
    h = h ^ (h >> 27u32)
    h = h *% 10723151780598845931u64
    ret h ^ (h >> 31u32)
}

// ---- B+tree -------------------------------------------------------------

// A B+tree over node arrays: node `i` owns `fanout + 1` key/value slots (one
// spare for the split) and `fanout + 2` child slots; `n`/`leaf`/`next_leaf`
// are per node. Node 0 is the initial empty leaf root.
fn btree(keys: []u64, vals: []i64, children: []u32, next_leaf: []u32, n: []u32, leaf: []bool, fanout: usize) -> (BTree, err) {
    if fanout < 2usize { ret (zero, Invalid) }
    let nodes = n.len
    if nodes == 0usize || leaf.len < nodes || next_leaf.len < nodes || keys.len < nodes * (fanout + 1usize) || vals.len < nodes * (fanout + 1usize) || children.len < nodes * (fanout + 2usize) { ret (zero, TooSmall) }
    n[0usize] = 0u32
    leaf[0usize] = true
    next_leaf[0usize] = NONE
    ret (BTree { keys: keys, vals: vals, children: children, next_leaf: next_leaf, n: n, leaf: leaf, fanout: fanout, root: 0u32, used: 1usize, height: 1usize }, ok)
}

fn kslot(t: *const BTree, node: u32, i: usize) -> usize { ret usize(node) * (t.fanout + 1usize) + i }
fn cslot(t: *const BTree, node: u32, i: usize) -> usize { ret usize(node) * (t.fanout + 2usize) + i }

fn btree_new_node(t: *BTree, is_leaf: bool) -> (u32, err) {
    if t.used >= t.n.len { ret (0u32, Full) }
    let id = u32(t.used)
    t.used += 1usize
    t.n[usize(id)] = 0u32
    t.leaf[usize(id)] = is_leaf
    t.next_leaf[usize(id)] = NONE
    ret (id, ok)
}

// The number of keys in `node` that are <= `key` (leaf: first slot >= key).
fn btree_lower(t: *const BTree, node: u32, key: u64) -> usize {
    var i = 0usize
    let count = usize(t.n[usize(node)])
    while i < count && t.keys[kslot(t, node, i)] < key { i += 1usize }
    ret i
}

// Insert into the subtree at `node`; answers (separator, new sibling, split).
fn btree_insert_rec(t: *BTree, node: u32, key: u64, val: i64) -> (u64, u32, bool, err) {
    var count = usize(t.n[usize(node)])
    var pos = btree_lower(t, node, key)
    if t.leaf[usize(node)] {
        if pos < count && t.keys[kslot(t, node, pos)] == key {
            t.vals[kslot(t, node, pos)] = val
            ret (0u64, 0u32, false, ok)
        }
        var j = count
        while j > pos {
            t.keys[kslot(t, node, j)] = t.keys[kslot(t, node, j - 1usize)]
            t.vals[kslot(t, node, j)] = t.vals[kslot(t, node, j - 1usize)]
            j -= 1usize
        }
        t.keys[kslot(t, node, pos)] = key
        t.vals[kslot(t, node, pos)] = val
        count += 1usize
        t.n[usize(node)] = u32(count)
        if count <= t.fanout { ret (0u64, 0u32, false, ok) }
        let (sibling, e) = btree_new_node(t, true)
        if e != ok { ret (0u64, 0u32, false, e) }
        let keep = (count + 1usize) / 2usize
        var i = keep
        while i < count {
            t.keys[kslot(t, sibling, i - keep)] = t.keys[kslot(t, node, i)]
            t.vals[kslot(t, sibling, i - keep)] = t.vals[kslot(t, node, i)]
            i += 1usize
        }
        t.n[usize(sibling)] = u32(count - keep)
        t.n[usize(node)] = u32(keep)
        t.next_leaf[usize(sibling)] = t.next_leaf[usize(node)]
        t.next_leaf[usize(node)] = sibling
        ret (t.keys[kslot(t, sibling, 0usize)], sibling, true, ok)
    }
    // Internal: separators <= key send the search right.
    if pos < count && t.keys[kslot(t, node, pos)] == key { pos += 1usize }
    let (sep, sibling, split, e) = btree_insert_rec(t, t.children[cslot(t, node, pos)], key, val)
    if e != ok || !split { ret (0u64, 0u32, false, e) }
    var j = count
    while j > pos {
        t.keys[kslot(t, node, j)] = t.keys[kslot(t, node, j - 1usize)]
        t.children[cslot(t, node, j + 1usize)] = t.children[cslot(t, node, j)]
        j -= 1usize
    }
    t.keys[kslot(t, node, pos)] = sep
    t.children[cslot(t, node, pos + 1usize)] = sibling
    count += 1usize
    t.n[usize(node)] = u32(count)
    if count <= t.fanout { ret (0u64, 0u32, false, ok) }
    let (right, right_error) = btree_new_node(t, false)
    if right_error != ok { ret (0u64, 0u32, false, right_error) }
    let mid = count / 2usize
    var i = mid + 1usize
    while i < count {
        t.keys[kslot(t, right, i - mid - 1usize)] = t.keys[kslot(t, node, i)]
        t.children[cslot(t, right, i - mid - 1usize)] = t.children[cslot(t, node, i)]
        i += 1usize
    }
    t.children[cslot(t, right, count - mid - 1usize)] = t.children[cslot(t, node, count)]
    t.n[usize(right)] = u32(count - mid - 1usize)
    t.n[usize(node)] = u32(mid)
    ret (t.keys[kslot(t, node, mid)], right, true, ok)
}

// Insert or overwrite `key`; Full when the node pool is exhausted.
fn btree_insert(t: *BTree, key: u64, val: i64) -> err {
    let (sep, sibling, split, e) = btree_insert_rec(t, t.root, key, val)
    if e != ok || !split { ret e }
    let (top, top_error) = btree_new_node(t, false)
    if top_error != ok { ret top_error }
    t.keys[kslot(t, top, 0usize)] = sep
    t.children[cslot(t, top, 0usize)] = t.root
    t.children[cslot(t, top, 1usize)] = sibling
    t.n[usize(top)] = 1u32
    t.root = top
    t.height += 1usize
    ret ok
}

// The leaf whose range holds `key`.
fn btree_leaf_for(t: *const BTree, key: u64) -> u32 {
    var node = t.root
    while !t.leaf[usize(node)] {
        var pos = btree_lower(t, node, key)
        if pos < usize(t.n[usize(node)]) && t.keys[kslot(t, node, pos)] == key { pos += 1usize }
        node = t.children[cslot(t, node, pos)]
    }
    ret node
}

fn btree_find(t: *const BTree, key: u64) -> (i64, bool) {
    let leaf = btree_leaf_for(t, key)
    let pos = btree_lower(t, leaf, key)
    if pos < usize(t.n[usize(leaf)]) && t.keys[kslot(t, leaf, pos)] == key { ret (t.vals[kslot(t, leaf, pos)], true) }
    ret (0i64, false)
}

// The right sibling of `leaf` through the leaf chain.
fn btree_next_leaf(t: *const BTree, leaf: u32) -> (u32, bool) {
    let sibling = t.next_leaf[usize(leaf)]
    ret (sibling, sibling != NONE)
}

// The leftmost leaf: the head of the sibling chain.
fn btree_first_leaf(t: *const BTree) -> u32 {
    var node = t.root
    while !t.leaf[usize(node)] { node = t.children[cslot(t, node, 0usize)] }
    ret node
}

// Every entry with `lo <= key <= hi` in order into `out_keys`/`out_vals`;
// answers the count (capped by the shorter output).
fn btree_range(t: *const BTree, lo: u64, hi: u64, out_keys: []u64, out_vals: []i64) -> usize {
    var room = out_keys.len
    if out_vals.len < room { room = out_vals.len }
    var leaf = btree_leaf_for(t, lo)
    var pos = btree_lower(t, leaf, lo)
    var written = 0usize
    var more = true
    while more && written < room {
        if pos >= usize(t.n[usize(leaf)]) {
            let (sibling, has) = btree_next_leaf(t, leaf)
            more = has
            leaf = sibling
            pos = 0usize
        } else if t.keys[kslot(t, leaf, pos)] > hi {
            more = false
        } else {
            out_keys[written] = t.keys[kslot(t, leaf, pos)]
            out_vals[written] = t.vals[kslot(t, leaf, pos)]
            written += 1usize
            pos += 1usize
        }
    }
    ret written
}

fn btree_height(t: *const BTree) -> usize { ret t.height }

// ---- Dense, sparse and bitmap indexes ---------------------------------------

// One entry per key of a sorted, paged column (page = index / page_size).
fn index_dense(keys: []const u64, page_size: usize, out: []IndexEntry) -> (usize, err) {
    if page_size == 0usize { ret (0usize, Invalid) }
    if out.len < keys.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < keys.len {
        out[i] = IndexEntry { key: keys[i], page: u32(i / page_size), slot: u32(i % page_size) }
        i += 1usize
    }
    ret (keys.len, ok)
}

// One entry per page: its first key.
fn index_sparse(keys: []const u64, page_size: usize, out: []IndexEntry) -> (usize, err) {
    if page_size == 0usize { ret (0usize, Invalid) }
    let pages = (keys.len + page_size - 1usize) / page_size
    if out.len < pages { ret (0usize, TooSmall) }
    var p = 0usize
    while p < pages {
        out[p] = IndexEntry { key: keys[p * page_size], page: u32(p), slot: 0u32 }
        p += 1usize
    }
    ret (pages, ok)
}

// The number of index entries with key <= `key` (binary search).
fn index_upper(index: []const IndexEntry, key: u64) -> usize {
    var lo = 0usize
    var hi = index.len
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if index[mid].key <= key { lo = mid + 1usize } else { hi = mid }
    }
    ret lo
}

// Answers (page, slot, found) from a dense index.
fn index_lookup_dense(index: []const IndexEntry, key: u64) -> (u32, u32, bool) {
    let upper = index_upper(index, key)
    if upper == 0usize || index[upper - 1usize].key != key { ret (0u32, 0u32, false) }
    ret (index[upper - 1usize].page, index[upper - 1usize].slot, true)
}

// Answers (page, slot, found) from a sparse index: the page is found by
// binary search, then scanned in the column.
fn index_lookup_sparse(index: []const IndexEntry, keys: []const u64, page_size: usize, key: u64) -> (u32, u32, bool) {
    let upper = index_upper(index, key)
    if upper == 0usize || page_size == 0usize { ret (0u32, 0u32, false) }
    let page = usize(index[upper - 1usize].page)
    var i = page * page_size
    var stop = i + page_size
    if stop > keys.len { stop = keys.len }
    while i < stop {
        if keys[i] == key { ret (u32(page), u32(i - page * page_size), true) }
        i += 1usize
    }
    ret (0u32, 0u32, false)
}

// One bitmap per distinct value of a column with values `< cardinality`,
// laid out back to back in `out`; answers the words per bitmap.
fn index_bitmap(values: []const u8, cardinality: usize, out: []u64) -> (usize, err) {
    let words = (values.len + 63usize) / 64usize
    if out.len < words * cardinality { ret (0usize, TooSmall) }
    var w = 0usize
    while w < words * cardinality {
        out[w] = 0u64
        w += 1usize
    }
    var i = 0usize
    while i < values.len {
        let v = usize(values[i])
        if v >= cardinality { ret (0usize, Invalid) }
        out[v * words + i / 64usize] = out[v * words + i / 64usize] | (1u64 << u32(i % 64usize))
        i += 1usize
    }
    ret (words, ok)
}

fn bitmap_and(a: []const u64, b: []const u64, out: []u64) -> err {
    if a.len != b.len || out.len < a.len { ret TooSmall }
    var i = 0usize
    while i < a.len {
        out[i] = a[i] & b[i]
        i += 1usize
    }
    ret ok
}

fn bitmap_or(a: []const u64, b: []const u64, out: []u64) -> err {
    if a.len != b.len || out.len < a.len { ret TooSmall }
    var i = 0usize
    while i < a.len {
        out[i] = a[i] | b[i]
        i += 1usize
    }
    ret ok
}

fn bitmap_count(a: []const u64) -> usize {
    var total = 0usize
    var i = 0usize
    while i < a.len {
        var w = a[i]
        while w != 0u64 {
            w = w & (w - 1u64)
            total += 1usize
        }
        i += 1usize
    }
    ret total
}

// ---- Linear hashing -------------------------------------------------------------

// Buckets of `bucket_size` slots in one pool: primary buckets grow from the
// bottom, overflow buckets are taken from the top. `max_load` is a percent.
fn hash_index_linear(slots: []u64, vals: []i64, filled: []bool, overflow: []u32, bucket_size: usize, initial: usize, max_load: usize) -> (LinearHash, err) {
    if bucket_size == 0usize || initial == 0usize || max_load == 0usize { ret (zero, Invalid) }
    let buckets = overflow.len
    if buckets < initial || filled.len < buckets * bucket_size || slots.len < buckets * bucket_size || vals.len < buckets * bucket_size { ret (zero, TooSmall) }
    var b = 0usize
    while b < buckets {
        overflow[b] = NONE
        b += 1usize
    }
    var i = 0usize
    while i < buckets * bucket_size {
        filled[i] = false
        i += 1usize
    }
    ret (LinearHash { slots: slots, vals: vals, filled: filled, overflow: overflow, bucket_size: bucket_size, initial: initial, level: 0u32, split_ptr: 0usize, top: buckets, n: 0usize, max_load: max_load }, ok)
}

fn lh_primary(h: *const LinearHash) -> usize { ret (h.initial << h.level) + h.split_ptr }

fn lh_address(h: *const LinearHash, key: u64) -> usize {
    let m = mix(key)
    var addr = usize(m % u64(h.initial << h.level))
    if addr < h.split_ptr { addr = usize(m % u64(h.initial << (h.level + 1u32))) }
    ret addr
}

// The slot holding `key` along the chain of `bucket`, if any.
fn lh_locate(h: *const LinearHash, bucket: usize, key: u64) -> (usize, bool) {
    var b = bucket
    while b != usize(NONE) {
        var i = 0usize
        while i < h.bucket_size {
            let s = b * h.bucket_size + i
            if h.filled[s] && h.slots[s] == key { ret (s, true) }
            i += 1usize
        }
        b = usize(h.overflow[b])
    }
    ret (0usize, false)
}

// Place `key` in the chain of `bucket` (it is known absent).
fn lh_place(h: *LinearHash, bucket: usize, key: u64, val: i64) -> err {
    var b = bucket
    while true {
        var i = 0usize
        while i < h.bucket_size {
            let s = b * h.bucket_size + i
            if !h.filled[s] {
                h.filled[s] = true
                h.slots[s] = key
                h.vals[s] = val
                ret ok
            }
            i += 1usize
        }
        if h.overflow[b] == NONE {
            if h.top <= lh_primary(h) + 1usize { ret Full }
            h.top -= 1usize
            h.overflow[b] = u32(h.top)
        }
        b = usize(h.overflow[b])
    }
    ret Full
}

// Split the bucket under the split pointer into itself and a new primary bucket.
fn lh_split(h: *LinearHash) -> err {
    let from = h.split_ptr
    let to = lh_primary(h)
    if to + 1usize > h.top { ret Full }
    h.split_ptr += 1usize
    if h.split_ptr == (h.initial << h.level) {
        h.split_ptr = 0usize
        h.level += 1u32
    }
    // Rehash every entry of the chain in place: an entry that now maps to
    // `to` is cleared here and placed there.
    var b = from
    while b != usize(NONE) {
        var i = 0usize
        while i < h.bucket_size {
            let s = b * h.bucket_size + i
            if h.filled[s] && lh_address(h, h.slots[s]) == to {
                h.filled[s] = false
                let e = lh_place(h, to, h.slots[s], h.vals[s])
                if e != ok { ret e }
            }
            i += 1usize
        }
        b = usize(h.overflow[b])
    }
    ret ok
}

// Insert or overwrite; a split follows when the load exceeds `max_load` percent.
fn lh_insert(h: *LinearHash, key: u64, val: i64) -> err {
    let bucket = lh_address(h, key)
    let (s, found) = lh_locate(h, bucket, key)
    if found {
        h.vals[s] = val
        ret ok
    }
    let e = lh_place(h, bucket, key, val)
    if e != ok { ret e }
    h.n += 1usize
    if h.n * 100usize > h.max_load * lh_primary(h) * h.bucket_size { ret lh_split(h) }
    ret ok
}

fn lh_find(h: *const LinearHash, key: u64) -> (i64, bool) {
    let (s, found) = lh_locate(h, lh_address(h, key), key)
    if !found { ret (0i64, false) }
    ret (h.vals[s], true)
}

fn lh_remove(h: *LinearHash, key: u64) -> bool {
    let (s, found) = lh_locate(h, lh_address(h, key), key)
    if !found { ret false }
    h.filled[s] = false
    h.n -= 1usize
    ret true
}

// ---- Extendible hashing ------------------------------------------------------

// A directory of `2^global_depth` bucket ids over a bucket pool; the
// directory may grow up to `directory.len` (a power of two).
fn hash_index_extendible(directory: []u32, slots: []u64, vals: []i64, filled: []bool, local_depth: []u32, bucket_size: usize) -> (ExtHash, err) {
    if bucket_size == 0usize || directory.len == 0usize { ret (zero, Invalid) }
    let buckets = local_depth.len
    if buckets == 0usize || filled.len < buckets * bucket_size || slots.len < buckets * bucket_size || vals.len < buckets * bucket_size { ret (zero, TooSmall) }
    var i = 0usize
    while i < bucket_size {
        filled[i] = false
        i += 1usize
    }
    directory[0usize] = 0u32
    local_depth[0usize] = 0u32
    ret (ExtHash { directory: directory, global_depth: 0u32, slots: slots, vals: vals, filled: filled, local_depth: local_depth, bucket_size: bucket_size, used: 1usize, n: 0usize }, ok)
}

fn eh_bucket(h: *const ExtHash, key: u64) -> usize {
    let mask = (1u64 << h.global_depth) - 1u64
    ret usize(h.directory[usize(mix(key) & mask)])
}

fn eh_locate(h: *const ExtHash, bucket: usize, key: u64) -> (usize, bool) {
    var i = 0usize
    while i < h.bucket_size {
        let s = bucket * h.bucket_size + i
        if h.filled[s] && h.slots[s] == key { ret (s, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// Split `bucket`, doubling the directory first when its local depth is global.
fn eh_split(h: *ExtHash, bucket: usize) -> err {
    if usize(h.local_depth[bucket]) == usize(h.global_depth) {
        let size = 1usize << h.global_depth
        if size * 2usize > h.directory.len { ret Full }
        var i = 0usize
        while i < size {
            h.directory[size + i] = h.directory[i]
            i += 1usize
        }
        h.global_depth += 1u32
    }
    if h.used >= h.local_depth.len { ret Full }
    let fresh = h.used
    h.used += 1usize
    let depth = h.local_depth[bucket] + 1u32
    h.local_depth[bucket] = depth
    h.local_depth[fresh] = depth
    var i = 0usize
    while i < h.bucket_size {
        h.filled[fresh * h.bucket_size + i] = false
        i += 1usize
    }
    // Directory slots of `bucket` whose bit `depth - 1` is set move to `fresh`.
    let bit = 1usize << (depth - 1u32)
    var d = 0usize
    while d < (1usize << h.global_depth) {
        if usize(h.directory[d]) == bucket && (d & bit) != 0usize { h.directory[d] = u32(fresh) }
        d += 1usize
    }
    i = 0usize
    var moved = 0usize
    while i < h.bucket_size {
        let s = bucket * h.bucket_size + i
        if h.filled[s] && (usize(mix(h.slots[s])) & bit) != 0usize {
            h.filled[s] = false
            h.slots[fresh * h.bucket_size + moved] = h.slots[s]
            h.vals[fresh * h.bucket_size + moved] = h.vals[s]
            h.filled[fresh * h.bucket_size + moved] = true
            moved += 1usize
        }
        i += 1usize
    }
    ret ok
}

// Insert or overwrite; splits until the key's bucket has room.
fn eh_insert(h: *ExtHash, key: u64, val: i64) -> err {
    while true {
        let bucket = eh_bucket(h, key)
        let (s, found) = eh_locate(h, bucket, key)
        if found {
            h.vals[s] = val
            ret ok
        }
        var i = 0usize
        while i < h.bucket_size {
            let slot = bucket * h.bucket_size + i
            if !h.filled[slot] {
                h.filled[slot] = true
                h.slots[slot] = key
                h.vals[slot] = val
                h.n += 1usize
                ret ok
            }
            i += 1usize
        }
        let e = eh_split(h, bucket)
        if e != ok { ret e }
    }
    ret Full
}

fn eh_find(h: *const ExtHash, key: u64) -> (i64, bool) {
    let (s, found) = eh_locate(h, eh_bucket(h, key), key)
    if !found { ret (0i64, false) }
    ret (h.vals[s], true)
}

fn eh_remove(h: *ExtHash, key: u64) -> bool {
    let (s, found) = eh_locate(h, eh_bucket(h, key), key)
    if !found { ret false }
    h.filled[s] = false
    h.n -= 1usize
    ret true
}

// ---- LSM: memtable flush, SSTables, compaction -----------------------------------

// An empty SSTable over caller storage: a sparse index entry every `stride`
// keys and a Bloom filter of `bloom.len * 64` bits with three hashes.
fn sstable(keys: []u64, vals: []i64, tomb: []bool, index_keys: []u64, index_pos: []u32, bloom: []u64, stride: usize) -> (SsTable, err) {
    if stride == 0usize || bloom.len == 0usize { ret (zero, Invalid) }
    if vals.len < keys.len || tomb.len < keys.len || index_pos.len < index_keys.len || index_keys.len < (keys.len + stride - 1usize) / stride { ret (zero, TooSmall) }
    ret (SsTable { keys: keys, vals: vals, tomb: tomb, n: 0usize, index_keys: index_keys, index_pos: index_pos, index_n: 0usize, bloom: bloom, stride: stride }, ok)
}

fn bloom_bit(s: *const SsTable, key: u64, k: u64) -> (usize, u64) {
    let m = mix(key)
    let bit = ((m & 4294967295u64) +% (k *% (m >> 32u32))) % (u64(s.bloom.len) * 64u64)
    ret (usize(bit / 64u64), 1u64 << u32(bit % 64u64))
}

// Rebuild the sparse index and Bloom filter over the first `s.n` entries.
fn sstable_build(s: *SsTable) {
    var w = 0usize
    while w < s.bloom.len {
        s.bloom[w] = 0u64
        w += 1usize
    }
    s.index_n = 0usize
    var i = 0usize
    while i < s.n {
        if i % s.stride == 0usize {
            s.index_keys[s.index_n] = s.keys[i]
            s.index_pos[s.index_n] = u32(i)
            s.index_n += 1usize
        }
        var k = 0u64
        while k < 3u64 {
            let (word, bit) = bloom_bit(s, s.keys[i], k)
            s.bloom[word] = s.bloom[word] | bit
            k += 1u64
        }
        i += 1usize
    }
}

// Write a sorted memtable (strictly ascending keys, `tomb` marks deletes)
// into `s` as one run with its index and filter.
fn memtable_flush(mem_keys: []const u64, mem_vals: []const i64, mem_tomb: []const bool, s: *SsTable) -> err {
    if mem_keys.len > s.keys.len { ret TooSmall }
    if mem_vals.len < mem_keys.len || mem_tomb.len < mem_keys.len { ret Invalid }
    var i = 0usize
    while i < mem_keys.len {
        if i > 0usize && mem_keys[i - 1usize] >= mem_keys[i] { ret Invalid }
        s.keys[i] = mem_keys[i]
        s.vals[i] = mem_vals[i]
        s.tomb[i] = mem_tomb[i]
        i += 1usize
    }
    s.n = mem_keys.len
    sstable_build(s)
    ret ok
}

// The position of `key` in `s`: Bloom filter, then the sparse index, then a
// scan of one stride.
fn sstable_locate(s: *const SsTable, key: u64) -> (usize, bool) {
    var k = 0u64
    while k < 3u64 {
        let (word, bit) = bloom_bit(s, key, k)
        if (s.bloom[word] & bit) == 0u64 { ret (0usize, false) }
        k += 1u64
    }
    var lo = 0usize
    var hi = s.index_n
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if s.index_keys[mid] <= key { lo = mid + 1usize } else { hi = mid }
    }
    if lo == 0usize { ret (0usize, false) }
    var i = usize(s.index_pos[lo - 1usize])
    var stop = i + s.stride
    if stop > s.n { stop = s.n }
    while i < stop && s.keys[i] < key { i += 1usize }
    if i < stop && s.keys[i] == key { ret (i, true) }
    ret (0usize, false)
}

// The live value of `key` in `s` (a tombstone answers not found).
fn sstable_find(s: *const SsTable, key: u64) -> (i64, bool) {
    let (i, found) = sstable_locate(s, key)
    if !found || s.tomb[i] { ret (0i64, false) }
    ret (s.vals[i], true)
}

// Merge `runs` (newest first) into `out`, keeping the newest version of each
// key; tombstones are dropped when `bottom` (no older level remains).
fn lsm_compact(runs: []const SsTable, heads: []usize, out: *SsTable, bottom: bool) -> (usize, err) {
    if heads.len < runs.len { ret (0usize, TooSmall) }
    var r = 0usize
    while r < runs.len {
        heads[r] = 0usize
        r += 1usize
    }
    out.n = 0usize
    var more = true
    while more {
        var best = 0usize
        var have = false
        var low = 0u64
        r = 0usize
        while r < runs.len {
            if heads[r] < runs[r].n && (!have || runs[r].keys[heads[r]] < low) {
                have = true
                low = runs[r].keys[heads[r]]
                best = r
            }
            r += 1usize
        }
        more = have
        if have {
            let i = heads[best]
            if !(bottom && runs[best].tomb[i]) {
                if out.n >= out.keys.len { ret (out.n, TooSmall) }
                out.keys[out.n] = low
                out.vals[out.n] = runs[best].vals[i]
                out.tomb[out.n] = runs[best].tomb[i]
                out.n += 1usize
            }
            r = 0usize
            while r < runs.len {
                if heads[r] < runs[r].n && runs[r].keys[heads[r]] == low { heads[r] += 1usize }
                r += 1usize
            }
        }
    }
    sstable_build(out)
    ret (out.n, ok)
}

// Look `key` up through `levels` newest first; the first run that knows the
// key decides (a tombstone hides older versions).
fn lsm_find(levels: []const SsTable, key: u64) -> (i64, bool) {
    var l = 0usize
    while l < levels.len {
        let (i, found) = sstable_locate(&levels[l], key)
        if found {
            if levels[l].tomb[i] { ret (0i64, false) }
            ret (levels[l].vals[i], true)
        }
        l += 1usize
    }
    ret (0i64, false)
}

// ---- Key/value table (recovery target, OCC store) ---------------------------------

fn table(keys: []u64, vals: []i64) -> Table { ret Table { keys: keys, vals: vals, n: 0usize } }

// ponytail: linear scan; the table is a recovery/transaction stand-in, not an index.
fn table_slot(t: *const Table, key: u64) -> (usize, bool) {
    var i = 0usize
    while i < t.n {
        if t.keys[i] == key { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn table_get(t: *const Table, key: u64) -> (i64, bool) {
    let (i, found) = table_slot(t, key)
    if !found { ret (0i64, false) }
    ret (t.vals[i], true)
}

fn table_put(t: *Table, key: u64, val: i64) -> err {
    let (i, found) = table_slot(t, key)
    if found {
        t.vals[i] = val
        ret ok
    }
    if t.n >= t.keys.len || t.n >= t.vals.len { ret Full }
    t.keys[t.n] = key
    t.vals[t.n] = val
    t.n += 1usize
    ret ok
}

fn table_delete(t: *Table, key: u64) -> bool {
    let (i, found) = table_slot(t, key)
    if !found { ret false }
    t.n -= 1usize
    t.keys[i] = t.keys[t.n]
    t.vals[i] = t.vals[t.n]
    ret true
}

// ---- Write-ahead log --------------------------------------------------------------

fn put64(dst: []u8, off: usize, v: u64) {
    var i = 0usize
    while i < 8usize {
        dst[off + i] = u8((v >> u32(i * 8usize)) & 255u64)
        i += 1usize
    }
}

fn get64(src: []const u8, off: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v = v | (u64(src[off + i]) << u32(i * 8usize))
        i += 1usize
    }
    ret v
}

fn wal(log: []u8) -> Wal { ret Wal { log: log, used: 0usize, next_lsn: 1u64 } }

// Append a 29-byte record `lsn | kind | key | val | crc32`; answers its LSN.
fn wal_append(w: *Wal, kind: u8, key: u64, val: i64) -> (u64, err) {
    if kind > KIND_CHECKPOINT { ret (0u64, Invalid) }
    if w.used + RECORD > w.log.len { ret (0u64, Full) }
    let lsn = w.next_lsn
    let base = w.used
    put64(w.log, base, lsn)
    w.log[base + 8usize] = kind
    put64(w.log, base + 9usize, key)
    put64(w.log, base + 17usize, u64.trunc(val))
    let crc = hash.crc32(w.log[base..base + 25usize])
    var i = 0usize
    while i < 4usize {
        w.log[base + 25usize + i] = u8((crc >> u32(i * 8usize)) & 255u32)
        i += 1usize
    }
    w.used += RECORD
    w.next_lsn += 1u64
    ret (lsn, ok)
}

// Append a checkpoint record; answers its LSN, the point recovery can start from.
fn checkpoint(w: *Wal) -> (u64, err) {
    let (lsn, e) = wal_append(w, KIND_CHECKPOINT, 0u64, 0i64)
    ret (lsn, e)
}

// Drop every record with an LSN below `checkpoint_lsn`; answers how many went.
fn wal_truncate(w: *Wal, checkpoint_lsn: u64) -> usize {
    var from = 0usize
    var dropped = 0usize
    while from + RECORD <= w.used && get64(w.log, from) < checkpoint_lsn {
        from += RECORD
        dropped += 1usize
    }
    var i = 0usize
    while from + i < w.used {
        w.log[i] = w.log[from + i]
        i += 1usize
    }
    w.used -= from
    ret dropped
}

// Parse the record at `off`; answers (lsn, kind, key, val, ok | Corrupt).
fn wal_record(log: []const u8, off: usize) -> (u64, u8, u64, i64, err) {
    let crc = hash.crc32(log[off..off + 25usize])
    var stored = 0u32
    var i = 0usize
    while i < 4usize {
        stored = stored | (u32(log[off + 25usize + i]) << u32(i * 8usize))
        i += 1usize
    }
    if stored != crc || log[off + 8usize] > KIND_CHECKPOINT { ret (0u64, 0u8, 0u64, 0i64, Corrupt) }
    ret (get64(log, off), log[off + 8usize], get64(log, off + 9usize), i64.trunc(get64(log, off + 17usize)), ok)
}

// Redo every put/delete with LSN above `applied_upto` into `t`; a torn tail
// (fewer than a record's bytes) ends the replay, a CRC mismatch answers
// Corrupt with the count applied so far.
fn recover(log: []const u8, used: usize, t: *Table, applied_upto: u64) -> (usize, err) {
    var off = 0usize
    var applied = 0usize
    while off + RECORD <= used && off + RECORD <= log.len {
        let (lsn, kind, key, val, e) = wal_record(log, off)
        if e != ok { ret (applied, e) }
        if lsn > applied_upto {
            if kind == KIND_PUT {
                let put_error = table_put(t, key, val)
                if put_error != ok { ret (applied, put_error) }
                applied += 1usize
            } else if kind == KIND_DELETE {
                let _ = table_delete(t, key)
                applied += 1usize
            }
        }
        off += RECORD
    }
    ret (applied, ok)
}

// ---- Buffer pool -----------------------------------------------------------------

fn buffer_pool(frames: []u64, valid: []bool, stamp: []u64, hist: []u64, ref_bit: []bool, policy: Policy) -> (Pool, err) {
    let f = frames.len
    if f == 0usize { ret (zero, Invalid) }
    if valid.len < f || stamp.len < f || hist.len < f || ref_bit.len < f { ret (zero, TooSmall) }
    var i = 0usize
    while i < f {
        valid[i] = false
        stamp[i] = 0u64
        hist[i] = 0u64
        ref_bit[i] = false
        i += 1usize
    }
    ret (Pool { frames: frames, valid: valid, stamp: stamp, hist: hist, ref_bit: ref_bit, policy: policy, hand: 0usize, clock: 1u64, hits: 0usize, misses: 0usize }, ok)
}

// The frame to reclaim under the pool's policy (every frame is valid here).
// LRU: the oldest access; CLOCK: sweep the hand clearing reference bits;
// LRU-2: a frame with fewer than two accesses first (oldest), else the
// oldest second-to-last access.
fn buffer_pool_evict(p: *Pool) -> usize {
    let f = p.frames.len
    if p.policy == .Clock {
        while p.ref_bit[p.hand] {
            p.ref_bit[p.hand] = false
            p.hand = (p.hand + 1usize) % f
        }
        let victim = p.hand
        p.hand = (p.hand + 1usize) % f
        ret victim
    }
    var victim = 0usize
    var i = 1usize
    while i < f {
        if p.policy == .Lru {
            if p.stamp[i] < p.stamp[victim] { victim = i }
        } else {
            let young_i = p.hist[i] == 0u64
            let young_v = p.hist[victim] == 0u64
            if young_i && !young_v {
                victim = i
            } else if young_i == young_v {
                if young_i {
                    if p.stamp[i] < p.stamp[victim] { victim = i }
                } else if p.hist[i] < p.hist[victim] {
                    victim = i
                }
            }
        }
        i += 1usize
    }
    ret victim
}

// Touch `page`: answers (frame, hit); a miss fills a free frame or evicts.
fn pool_access(p: *Pool, page: u64) -> (usize, bool) {
    let f = p.frames.len
    var frame = f
    var free = f
    var i = 0usize
    while i < f {
        if p.valid[i] && p.frames[i] == page { frame = i }
        if !p.valid[i] && free == f { free = i }
        i += 1usize
    }
    var hit = false
    if frame < f {
        hit = true
        p.hits += 1usize
        p.hist[frame] = p.stamp[frame]
    } else {
        p.misses += 1usize
        frame = free
        if frame == f { frame = buffer_pool_evict(p) }
        p.frames[frame] = page
        p.valid[frame] = true
        p.hist[frame] = 0u64
    }
    p.stamp[frame] = p.clock
    p.ref_bit[frame] = true
    p.clock += 1u64
    ret (frame, hit)
}

// ---- Strict two-phase locking ---------------------------------------------------

// Lock rows of (key, owner, exclusive) plus a wait-for edge list over `txns`
// transaction ids; `scratch` holds at least `2 * txns` entries.
fn lock_table(keys: []u64, owners: []u32, exclusive: []bool, waits: []dl.Edge, scratch: []usize, txns: usize) -> (LockTable, err) {
    if owners.len < keys.len || exclusive.len < keys.len || scratch.len < 2usize * txns { ret (zero, TooSmall) }
    ret (LockTable { keys: keys, owners: owners, exclusive: exclusive, n: 0usize, waits: waits, wait_n: 0usize, scratch: scratch, txns: txns }, ok)
}

fn drop_waits_from(lt: *LockTable, txn: u32) {
    var i = 0usize
    while i < lt.wait_n {
        if lt.waits[i].from == txn {
            lt.wait_n -= 1usize
            lt.waits[i] = lt.waits[lt.wait_n]
        } else {
            i += 1usize
        }
    }
}

// Request `key` in shared or exclusive mode for `txn`. Answers (granted,
// deadlock): a conflict records wait-for edges to every blocking owner and
// checks the graph for a cycle; on a cycle the edges are withdrawn and the
// caller should abort `txn`. Full when the lock rows or edge list are
// exhausted; Invalid for a transaction id past `txns`.
fn txn_lock_2pl(lt: *LockTable, txn: u32, key: u64, exclusive: bool) -> (bool, bool, err) {
    if usize(txn) >= lt.txns { ret (false, false, Invalid) }
    var own = lt.n
    var blocked = false
    var i = 0usize
    while i < lt.n {
        if lt.keys[i] == key {
            if lt.owners[i] == txn {
                own = i
            } else if exclusive || lt.exclusive[i] {
                blocked = true
            }
        }
        i += 1usize
    }
    if blocked {
        let before = lt.wait_n
        i = 0usize
        while i < lt.n {
            if lt.keys[i] == key && lt.owners[i] != txn && (exclusive || lt.exclusive[i]) {
                if lt.wait_n >= lt.waits.len { ret (false, false, Full) }
                lt.waits[lt.wait_n] = dl.Edge { from: txn, to: lt.owners[i] }
                lt.wait_n += 1usize
            }
            i += 1usize
        }
        let (cycle, _, e) = dl.wait_for_graph_cycle(lt.waits[..lt.wait_n], lt.txns, lt.scratch)
        if e != ok { ret (false, false, e) }
        if cycle {
            lt.wait_n = before
            ret (false, true, ok)
        }
        ret (false, false, ok)
    }
    drop_waits_from(lt, txn)
    if own < lt.n {
        if exclusive { lt.exclusive[own] = true }
        ret (true, false, ok)
    }
    if lt.n >= lt.keys.len { ret (false, false, Full) }
    lt.keys[lt.n] = key
    lt.owners[lt.n] = txn
    lt.exclusive[lt.n] = exclusive
    lt.n += 1usize
    ret (true, false, ok)
}

// Release every lock of `txn` (commit or abort) and its wait-for edges.
fn txn_unlock_all(lt: *LockTable, txn: u32) -> usize {
    var released = 0usize
    var i = 0usize
    while i < lt.n {
        if lt.owners[i] == txn {
            lt.n -= 1usize
            lt.keys[i] = lt.keys[lt.n]
            lt.owners[i] = lt.owners[lt.n]
            lt.exclusive[i] = lt.exclusive[lt.n]
            released += 1usize
        } else {
            i += 1usize
        }
    }
    drop_waits_from(lt, txn)
    i = 0usize
    while i < lt.wait_n {
        if lt.waits[i].to == txn {
            lt.wait_n -= 1usize
            lt.waits[i] = lt.waits[lt.wait_n]
        } else {
            i += 1usize
        }
    }
    ret released
}

// ---- Multi-version concurrency control ---------------------------------------

// Versions of (key, val, begin, end, writer): `begin` is the writer's commit
// timestamp (0 while pending), `end` the superseding commit or FOREVER.
fn txn_mvcc(keys: []u64, vals: []i64, begin: []u64, end: []u64, writer: []u32) -> (Mvcc, err) {
    if vals.len < keys.len || begin.len < keys.len || end.len < keys.len || writer.len < keys.len { ret (zero, TooSmall) }
    ret (Mvcc { keys: keys, vals: vals, begin: begin, end: end, writer: writer, n: 0usize }, ok)
}

// Add a pending version of `key` written by `txn`.
fn mvcc_write(m: *Mvcc, txn: u32, key: u64, val: i64) -> err {
    var i = 0usize
    while i < m.n {
        if m.keys[i] == key && m.begin[i] == 0u64 && m.writer[i] == txn {
            m.vals[i] = val
            ret ok
        }
        i += 1usize
    }
    if m.n >= m.keys.len { ret Full }
    m.keys[m.n] = key
    m.vals[m.n] = val
    m.begin[m.n] = 0u64
    m.end[m.n] = FOREVER
    m.writer[m.n] = txn
    m.n += 1usize
    ret ok
}

// The version of `key` visible to a snapshot at `snapshot_ts`.
fn mvcc_read(m: *const Mvcc, snapshot_ts: u64, key: u64) -> (i64, bool) {
    var i = 0usize
    while i < m.n {
        if m.keys[i] == key && m.begin[i] != 0u64 && m.begin[i] <= snapshot_ts && snapshot_ts < m.end[i] { ret (m.vals[i], true) }
        i += 1usize
    }
    ret (0i64, false)
}

// Commit `txn` at `commit_ts`: its pending versions begin there and the
// versions they supersede end there. Answers how many versions committed.
fn mvcc_commit(m: *Mvcc, txn: u32, commit_ts: u64) -> usize {
    var committed = 0usize
    var i = 0usize
    while i < m.n {
        if m.begin[i] == 0u64 && m.writer[i] == txn {
            var j = 0usize
            while j < m.n {
                if j != i && m.keys[j] == m.keys[i] && m.begin[j] != 0u64 && m.end[j] == FOREVER { m.end[j] = commit_ts }
                j += 1usize
            }
            m.begin[i] = commit_ts
            committed += 1usize
        }
        i += 1usize
    }
    ret committed
}

// Drop the pending versions of `txn`.
fn mvcc_abort(m: *Mvcc, txn: u32) -> usize {
    var removed = 0usize
    var i = 0usize
    while i < m.n {
        if m.begin[i] == 0u64 && m.writer[i] == txn {
            mvcc_remove_at(m, i)
            removed += 1usize
        } else {
            i += 1usize
        }
    }
    ret removed
}

fn mvcc_remove_at(m: *Mvcc, i: usize) {
    m.n -= 1usize
    m.keys[i] = m.keys[m.n]
    m.vals[i] = m.vals[m.n]
    m.begin[i] = m.begin[m.n]
    m.end[i] = m.end[m.n]
    m.writer[i] = m.writer[m.n]
}

// Remove every version no snapshot at or after `oldest_active_ts` can see.
fn vacuum(m: *Mvcc, oldest_active_ts: u64) -> usize {
    var removed = 0usize
    var i = 0usize
    while i < m.n {
        if m.end[i] != FOREVER && m.end[i] <= oldest_active_ts {
            mvcc_remove_at(m, i)
            removed += 1usize
        } else {
            i += 1usize
        }
    }
    ret removed
}

// ---- Optimistic concurrency control -----------------------------------------------

fn commit_log(keys: []u64, ts: []u64) -> CommitLog { ret CommitLog { keys: keys, ts: ts, n: 0usize } }

// A transaction started at `start_ts` with caller read-set and write-buffer storage.
fn txn_occ(start_ts: u64, read_keys: []u64, write_keys: []u64, write_vals: []i64) -> Occ {
    ret Occ { start_ts: start_ts, read_keys: read_keys, read_n: 0usize, write_keys: write_keys, write_vals: write_vals, write_n: 0usize }
}

fn occ_begin(start_ts: u64, read_keys: []u64, write_keys: []u64, write_vals: []i64) -> Occ {
    ret txn_occ(start_ts, read_keys, write_keys, write_vals)
}

// Read `key`: the transaction's own buffered write first, else the table;
// the key joins the read set.
fn occ_read(t: *Occ, store: *const Table, key: u64) -> (i64, bool, err) {
    var seen = false
    var i = 0usize
    while i < t.read_n {
        if t.read_keys[i] == key { seen = true }
        i += 1usize
    }
    if !seen {
        if t.read_n >= t.read_keys.len { ret (0i64, false, Full) }
        t.read_keys[t.read_n] = key
        t.read_n += 1usize
    }
    i = 0usize
    while i < t.write_n {
        if t.write_keys[i] == key { ret (t.write_vals[i], true, ok) }
        i += 1usize
    }
    let (val, found) = table_get(store, key)
    ret (val, found, ok)
}

// Buffer a write of `key`.
fn occ_write(t: *Occ, key: u64, val: i64) -> err {
    var i = 0usize
    while i < t.write_n {
        if t.write_keys[i] == key {
            t.write_vals[i] = val
            ret ok
        }
        i += 1usize
    }
    if t.write_n >= t.write_keys.len || t.write_n >= t.write_vals.len { ret Full }
    t.write_keys[t.write_n] = key
    t.write_vals[t.write_n] = val
    t.write_n += 1usize
    ret ok
}

// Backward validation: no commit after `start_ts` wrote a key this
// transaction read.
fn occ_validate(t: *const Occ, log: *const CommitLog) -> bool {
    var i = 0usize
    while i < log.n {
        if log.ts[i] > t.start_ts {
            var r = 0usize
            while r < t.read_n {
                if t.read_keys[r] == log.keys[i] { ret false }
                r += 1usize
            }
        }
        i += 1usize
    }
    ret true
}

// Validate, then apply the write buffer to `store` and log every written key
// at `commit_ts`. Answers whether the transaction committed.
fn occ_commit(t: *const Occ, store: *Table, log: *CommitLog, commit_ts: u64) -> (bool, err) {
    if !occ_validate(t, log) { ret (false, ok) }
    if log.n + t.write_n > log.keys.len || log.n + t.write_n > log.ts.len { ret (false, Full) }
    var i = 0usize
    while i < t.write_n {
        let e = table_put(store, t.write_keys[i], t.write_vals[i])
        if e != ok { ret (false, e) }
        log.keys[log.n] = t.write_keys[i]
        log.ts[log.n] = commit_ts
        log.n += 1usize
        i += 1usize
    }
    ret (true, ok)
}
