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
    // Division keeps the final power-of-two doubling in range at usize::MAX.
    while span <= count / 2usize {
        span += span
        levels += 1usize
    }
    ret levels
}

// Builds a min (or, with `prefer_max`, max) table by `T.cmp`.
fn build[T: type](storage: []T, values: []const T, prefer_max: bool) -> (SparseTable[T], err) {
    let n = values.len
    let levels = levels_for(n)
    // Check the product through division before forming it, so an impossible
    // request is TooSmall rather than an overflowing multiplication.
    if n > storage.len / levels { ret (zero, TooSmall) }
    let needed = n * levels
    var i = 0usize
    while i < n {
        storage[i] = values[i]
        i += 1usize
    }
    var level = 1usize
    var span = 1usize
    while level < levels {
        // `level < levels` means two spans fit in n.  Keep the endpoint as
        // bounded subtractions instead of forming i + 2 * span.
        let last_start = n - span - span
        let previous_row = (level - 1usize) * n
        let row = level * n
        i = 0usize
        while i <= last_start {
            let left = storage[previous_row + i]
            let right = storage[previous_row + i + span]
            var pick = left
            let order = T.cmp(right, left)
            if prefer_max {
                if order > 0i32 { pick = right }
            } else {
                if order < 0i32 { pick = right }
            }
            storage[row + i] = pick
            i += 1usize
        }
        level += 1usize
        if level < levels { span += span }
    }
    ret (SparseTable[T] { table: storage[..needed], count: n, levels: levels, prefer_max: prefer_max }, ok)
}

// The extreme over `low..high`; `Invalid` for an empty, out-of-range or malformed query.
fn query[T: type](t: *const SparseTable[T], low: usize, high: usize) -> (T, err) {
    if low >= high || high > t.count { ret (zero, Invalid) }
    if t.levels == 0usize { ret (zero, Invalid) }
    if t.count > t.table.len / t.levels { ret (zero, Invalid) }
    let width = high - low
    var level = 0usize
    var span = 1usize
    while span <= width / 2usize {
        span += span
        level += 1usize
    }
    if level >= t.levels { ret (zero, Invalid) }
    let row = level * t.count
    let left = t.table[row + low]
    let right = t.table[row + high - span]
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
    if n > storage.len / levels { ret (zero, TooSmall) }
    let needed = n * levels
    var level = 0usize
    var half = 1usize
    while level < levels {
        let row = level * n
        var block = 0usize
        while block < n {
            // Cap the two half-block endpoints at n without ever forming
            // block + 2 * half; the last block is commonly partial.
            let available = n - block
            var middle = n
            if half <= available { middle = block + half }
            var end = n
            if half <= available {
                let after_middle = available - half
                if half <= after_middle { end = middle + half }
            }
            // Suffix sums leftward from the middle.
            var sum = 0i64
            var i = middle
            while i > block {
                i -= 1usize
                sum += values[i]
                storage[row + i] = sum
            }
            // Prefix sums rightward from the middle.
            sum = 0i64
            i = middle
            while i < end {
                sum += values[i]
                storage[row + i] = sum
                i += 1usize
            }
            block = end
        }
        level += 1usize
        if level < levels { half += half }
    }
    ret (DisjointTable { table: storage[..needed], count: n, levels: levels }, ok)
}

// The sum over `low..high` in `O(1)`; `Invalid` for a malformed table.
fn disjoint_query(t: *const DisjointTable, low: usize, high: usize) -> (i64, err) {
    if low >= high || high > t.count { ret (0i64, Invalid) }
    if t.levels == 0usize { ret (0i64, Invalid) }
    if t.count > t.table.len / t.levels { ret (0i64, Invalid) }
    let last = high - 1usize
    if low == last { ret (t.table[low], ok) }
    // The level is the highest bit where `low` and `last` differ.
    var level = 0usize
    var differing = low ^ last
    while differing > 1usize {
        differing = differing >> 1usize
        level += 1usize
    }
    if level >= t.levels { ret (0i64, Invalid) }
    let row = level * t.count
    ret (t.table[row + low] + t.table[row + last], ok)
}
