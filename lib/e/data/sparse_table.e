// Sparse tables over caller storage: `O(1)` range minimum or maximum after
// `O(n log n)` preprocessing, and the disjoint form that answers range sums (or
// any associative operation) in `O(1)` without idempotence.
//
// A table of `n` values has `levels = floor(log2 n) + 1` rows of `n` entries
// each, so `storage.len >= n * levels`; `levels_for` computes it. Queries are
// over half-open ranges `low..high` with `low < high <= n`.

type SparseTable[T: type] = struct { table: []T, count: usize, levels: usize, prefer_max: bool }
type DisjointTable = struct { table: []i64, count: usize, levels: usize }
error TooSmall
error Invalid

// The row count a table over `count` values needs (1 for an empty table).
fn levels_for(count: usize) -> usize {
    var levels = 1usize
    var span = 1usize
    while span * 2usize <= count {
        span = span * 2usize
        levels += 1usize
    }
    ret levels
}

// Builds a min (or, with `prefer_max`, max) table by `T.cmp`.
fn build[T: type](storage: []T, values: []const T, prefer_max: bool) -> (SparseTable[T], err) {
    let n = values.len
    let levels = levels_for(n)
    if storage.len < n * levels { ret (zero, TooSmall) }
    var i = 0usize
    while i < n {
        storage[i] = values[i]
        i += 1usize
    }
    var level = 1usize
    var span = 1usize
    while level < levels {
        i = 0usize
        while i + span * 2usize <= n {
            let left = storage[(level - 1usize) * n + i]
            let right = storage[(level - 1usize) * n + i + span]
            var pick = left
            let order = T.cmp(right, left)
            if prefer_max {
                if order > 0i32 { pick = right }
            } else {
                if order < 0i32 { pick = right }
            }
            storage[level * n + i] = pick
            i += 1usize
        }
        span = span * 2usize
        level += 1usize
    }
    ret (SparseTable[T] { table: storage[..n * levels], count: n, levels: levels, prefer_max: prefer_max }, ok)
}

// The extreme over `low..high`; `Invalid` for an empty or out-of-range query.
fn query[T: type](t: *const SparseTable[T], low: usize, high: usize) -> (T, err) {
    if low >= high || high > t.count { ret (zero, Invalid) }
    let width = high - low
    var level = 0usize
    var span = 1usize
    while span * 2usize <= width {
        span = span * 2usize
        level += 1usize
    }
    let left = t.table[level * t.count + low]
    let right = t.table[level * t.count + high - span]
    let order = T.cmp(right, left)
    if t.prefer_max {
        if order > 0i32 { ret (right, ok) }
        ret (left, ok)
    }
    if order < 0i32 { ret (right, ok) }
    ret (left, ok)
}

// Builds the disjoint sparse table of sums: level `k` holds, within each block
// of `2^(k+1)`, suffix sums up to the block's middle and prefix sums after it.
fn disjoint_build(storage: []i64, values: []const i64) -> (DisjointTable, err) {
    let n = values.len
    let levels = levels_for(n)
    if storage.len < n * levels { ret (zero, TooSmall) }
    var level = 0usize
    while level < levels {
        let half = 1usize << level
        var block = 0usize
        while block < n {
            let middle = block + half
            // Suffix sums leftward from the middle.
            var sum = 0i64
            var i = middle
            if i > n { i = n }
            while i > block {
                i -= 1usize
                sum += values[i]
                storage[level * n + i] = sum
            }
            // Prefix sums rightward from the middle.
            sum = 0i64
            i = middle
            while i < block + half * 2usize && i < n {
                sum += values[i]
                storage[level * n + i] = sum
                i += 1usize
            }
            block += half * 2usize
        }
        level += 1usize
    }
    ret (DisjointTable { table: storage[..n * levels], count: n, levels: levels }, ok)
}

// The sum over `low..high` in `O(1)`.
fn disjoint_query(t: *const DisjointTable, low: usize, high: usize) -> (i64, err) {
    if low >= high || high > t.count { ret (0i64, Invalid) }
    let last = high - 1usize
    if low == last { ret (t.table[low], ok) }
    // The level is the highest bit where `low` and `last` differ.
    var level = 0usize
    var differing = low ^ last
    while differing > 1usize {
        differing = differing >> 1usize
        level += 1usize
    }
    ret (t.table[level * t.count + low] + t.table[level * t.count + last], ok)
}
