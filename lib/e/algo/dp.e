// Classic dynamic programmes over caller storage: knapsacks, subsequences,
// coin change, matrix-chain and optimal-search-tree orderings, subarray extremes,
// the largest rectangle under a histogram, the monotonic stacks, and the convex
// hull trick with the Li Chao tree for line minima, each also as a whole-batch
// call over slopes, intercepts and queries.
//
// Each routine states the scratch it needs and answers `TooSmall` when it is
// short; values are `i64` and never checked for overflow.

type Line = struct { slope: i64, intercept: i64 }
type LiChao = struct { lines: []Line, filled: []u8, low: i64, high: i64 }
error TooSmall
error Invalid

// 0/1 knapsack: the best value within `capacity`; `table.len > capacity`.
fn knapsack(weights: []const u64, values: []const i64, capacity: usize, table: []i64) -> (i64, err) {
    if weights.len != values.len || table.len <= capacity { ret (0i64, TooSmall) }
    var c = 0usize
    while c <= capacity {
        table[c] = 0i64
        c += 1usize
    }
    var i = 0usize
    while i < weights.len {
        let w = weights[i]
        if w <= u64(capacity) {
            c = capacity
            while c >= usize(w) {
                let candidate = table[c - usize(w)] + values[i]
                if candidate > table[c] { table[c] = candidate }
                if c == 0usize { break }
                c -= 1usize
            }
        }
        i += 1usize
    }
    ret (table[capacity], ok)
}

// Unbounded knapsack: items may repeat.
fn knapsack_unbounded(weights: []const u64, values: []const i64, capacity: usize, table: []i64) -> (i64, err) {
    if weights.len != values.len || table.len <= capacity { ret (0i64, TooSmall) }
    var c = 0usize
    while c <= capacity {
        table[c] = 0i64
        var i = 0usize
        while i < weights.len {
            if weights[i] <= u64(c) && weights[i] > 0u64 {
                let candidate = table[c - usize(weights[i])] + values[i]
                if candidate > table[c] { table[c] = candidate }
            }
            i += 1usize
        }
        c += 1usize
    }
    ret (table[capacity], ok)
}

// Fractional knapsack: items taken in value-density order, the last one partly;
// `order.len >= weights.len` is scratch for the sort. Answers the value as `f64`.
fn knapsack_fractional(weights: []const f64, values: []const f64, capacity: f64, order: []usize) -> (f64, err) {
    let n = weights.len
    if values.len != n || order.len < n { ret (0.0f64, TooSmall) }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    // Insertion sort by density, descending.
    i = 1usize
    while i < n {
        var j = i
        while j > 0usize && values[order[j]] * weights[order[j - 1usize]] > values[order[j - 1usize]] * weights[order[j]] {
            let swap = order[j]
            order[j] = order[j - 1usize]
            order[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
    var room = capacity
    var total = 0.0f64
    i = 0usize
    while i < n && room > 0.0f64 {
        let k = order[i]
        if weights[k] <= room {
            total += values[k]
            room -= weights[k]
        } else if weights[k] > 0.0f64 {
            total += values[k] * room / weights[k]
            room = 0.0f64
        }
        i += 1usize
    }
    ret (total, ok)
}

// The length of the longest strictly increasing subsequence, `O(n log n)`;
// `tails.len >= values.len`.
fn lis(values: []const i64, tails: []i64) -> (usize, err) {
    if tails.len < values.len { ret (0usize, TooSmall) }
    var length = 0usize
    var i = 0usize
    while i < values.len {
        var low = 0usize
        var high = length
        while low < high {
            let middle = low + (high - low) / 2usize
            if tails[middle] < values[i] { low = middle + 1usize } else { high = middle }
        }
        tails[low] = values[i]
        if low == length { length += 1usize }
        i += 1usize
    }
    ret (length, ok)
}

// The length of the longest common subsequence; `scratch.len >= 2 * (b.len + 1)`.
fn lcs[T: type](a: []const T, b: []const T, scratch: []usize) -> (usize, err) {
    let width = b.len + 1usize
    if scratch.len < 2usize * width { ret (0usize, TooSmall) }
    var previous = scratch[..width]
    var current = scratch[width..2usize * width]
    var j = 0usize
    while j < width {
        previous[j] = 0usize
        j += 1usize
    }
    var i = 0usize
    while i < a.len {
        current[0usize] = 0usize
        j = 0usize
        while j < b.len {
            if T.eq(a[i], b[j]) {
                current[j + 1usize] = previous[j] + 1usize
            } else {
                var best = previous[j + 1usize]
                if current[j] > best { best = current[j] }
                current[j + 1usize] = best
            }
            j += 1usize
        }
        let swap = previous
        previous = current
        current = swap
        i += 1usize
    }
    ret (previous[b.len], ok)
}

// The length of the shortest supersequence of both: `a.len + b.len - lcs`.
fn shortest_common_supersequence[T: type](a: []const T, b: []const T, scratch: []usize) -> (usize, err) {
    let (common, common_error) = lcs[T](a, b, scratch)
    if common_error != ok { ret (0usize, common_error) }
    ret (a.len + b.len - common, ok)
}

// The length of the longest palindromic subsequence of `s`: the LCS of `s` and its
// reverse, over `scratch.len >= 3 * s.len + 2`.
fn longest_palindromic_subsequence(s: []const u8, scratch: []usize) -> (usize, err) {
    let n = s.len
    if scratch.len < 3usize * n + 2usize { ret (0usize, TooSmall) }
    // The reverse is built in the tail of the scratch, one byte per slot.
    var reversed = scratch[2usize * n + 2usize..3usize * n + 2usize]
    var i = 0usize
    while i < n {
        reversed[i] = usize(s[n - 1usize - i])
        i += 1usize
    }
    let width = n + 1usize
    var previous = scratch[..width]
    var current = scratch[width..2usize * width]
    var j = 0usize
    while j < width {
        previous[j] = 0usize
        j += 1usize
    }
    i = 0usize
    while i < n {
        current[0usize] = 0usize
        j = 0usize
        while j < n {
            if usize(s[i]) == reversed[j] {
                current[j + 1usize] = previous[j] + 1usize
            } else {
                var best = previous[j + 1usize]
                if current[j] > best { best = current[j] }
                current[j + 1usize] = best
            }
            j += 1usize
        }
        let swap = previous
        previous = current
        current = swap
        i += 1usize
    }
    ret (previous[n], ok)
}

// The fewest coins summing to `amount`, or `false` when no combination does;
// `table.len > amount`.
fn coin_change_min(coins: []const u64, amount: usize, table: []u64) -> (u64, bool, err) {
    if table.len <= amount { ret (0u64, false, TooSmall) }
    let none = 18446744073709551615u64
    table[0usize] = 0u64
    var a = 1usize
    while a <= amount {
        table[a] = none
        var i = 0usize
        while i < coins.len {
            if coins[i] > 0u64 && coins[i] <= u64(a) && table[a - usize(coins[i])] != none {
                let candidate = table[a - usize(coins[i])] + 1u64
                if candidate < table[a] { table[a] = candidate }
            }
            i += 1usize
        }
        a += 1usize
    }
    if table[amount] == none { ret (0u64, false, ok) }
    ret (table[amount], true, ok)
}

// The number of distinct multisets of coins summing to `amount`; `table.len > amount`.
fn coin_change_ways(coins: []const u64, amount: usize, table: []u64) -> (u64, err) {
    if table.len <= amount { ret (0u64, TooSmall) }
    var a = 0usize
    while a <= amount {
        table[a] = 0u64
        a += 1usize
    }
    table[0usize] = 1u64
    var i = 0usize
    while i < coins.len {
        if coins[i] > 0u64 {
            a = usize(coins[i])
            while a <= amount {
                table[a] = table[a] +% table[a - usize(coins[i])]
                a += 1usize
            }
        }
        i += 1usize
    }
    ret (table[amount], ok)
}

// Whether some subset of `values` sums to `wanted`; `table.len > wanted` bytes.
fn subset_sum(values: []const u64, wanted: usize, table: []u8) -> (bool, err) {
    if table.len <= wanted { ret (false, TooSmall) }
    var s = 0usize
    while s <= wanted {
        table[s] = 0u8
        s += 1usize
    }
    table[0usize] = 1u8
    var i = 0usize
    while i < values.len {
        if values[i] <= u64(wanted) {
            s = wanted
            while s >= usize(values[i]) {
                if table[s - usize(values[i])] == 1u8 { table[s] = 1u8 }
                if s == 0usize { break }
                s -= 1usize
            }
        }
        i += 1usize
    }
    ret (table[wanted] == 1u8, ok)
}

// Whether `values` splits into two subsets of equal sum.
fn partition_equal(values: []const u64, table: []u8) -> (bool, err) {
    var total = 0u64
    var i = 0usize
    while i < values.len {
        total += values[i]
        i += 1usize
    }
    if total % 2u64 != 0u64 { ret (false, ok) }
    let (found, found_error) = subset_sum(values, usize(total / 2u64), table)
    ret (found, found_error)
}

// Kadane: the largest sum of a non-empty contiguous run, and its half-open range.
fn max_subarray(values: []const i64) -> (i64, usize, usize) {
    if values.len == 0usize { ret (0i64, 0usize, 0usize) }
    var best = values[0usize]
    var best_low = 0usize
    var best_high = 1usize
    var current = values[0usize]
    var current_low = 0usize
    var i = 1usize
    while i < values.len {
        if current < 0i64 {
            current = values[i]
            current_low = i
        } else {
            current += values[i]
        }
        if current > best {
            best = current
            best_low = current_low
            best_high = i + 1usize
        }
        i += 1usize
    }
    ret (best, best_low, best_high)
}

// The largest product of a non-empty contiguous run.
fn max_product_subarray(values: []const i64) -> i64 {
    if values.len == 0usize { ret 0i64 }
    var best = values[0usize]
    var high = values[0usize]
    var low = values[0usize]
    var i = 1usize
    while i < values.len {
        let v = values[i]
        let a = high * v
        let b = low * v
        high = v
        low = v
        if a > high { high = a }
        if b > high { high = b }
        if a < low { low = a }
        if b < low { low = b }
        if high > best { best = high }
        i += 1usize
    }
    ret best
}

// Matrix chain ordering: the fewest scalar multiplications for matrices of sizes
// `dims[i] x dims[i+1]`; `table.len >= (dims.len - 1)^2`.
fn matrix_chain(dims: []const u64, table: []u64) -> (u64, err) {
    if dims.len < 2usize { ret (0u64, Invalid) }
    let n = dims.len - 1usize
    if table.len < n * n { ret (0u64, TooSmall) }
    var i = 0usize
    while i < n {
        table[i * n + i] = 0u64
        i += 1usize
    }
    var length = 2usize
    while length <= n {
        i = 0usize
        while i + length <= n {
            let j = i + length - 1usize
            var best = 18446744073709551615u64
            var k = i
            while k < j {
                let cost = table[i * n + k] + table[(k + 1usize) * n + j] + dims[i] * dims[k + 1usize] * dims[j + 1usize]
                if cost < best { best = cost }
                k += 1usize
            }
            table[i * n + j] = best
            i += 1usize
        }
        length += 1usize
    }
    ret (table[n - 1usize], ok)
}

// Optimal binary search tree: the least expected search cost for keys in order
// with the given access frequencies, root depth 1; `table.len >= 2 * n^2`.
fn optimal_bst(frequencies: []const u64, table: []u64) -> (u64, err) {
    let n = frequencies.len
    if n == 0usize { ret (0u64, ok) }
    if table.len < 2usize * n * n { ret (0u64, TooSmall) }
    var cost = table[..n * n]
    var sums = table[n * n..2usize * n * n]
    var i = 0usize
    while i < n {
        cost[i * n + i] = frequencies[i]
        sums[i * n + i] = frequencies[i]
        i += 1usize
    }
    var length = 2usize
    while length <= n {
        i = 0usize
        while i + length <= n {
            let j = i + length - 1usize
            sums[i * n + j] = sums[i * n + j - 1usize] + frequencies[j]
            var best = 18446744073709551615u64
            var r = i
            while r <= j {
                var left = 0u64
                if r > i { left = cost[i * n + r - 1usize] }
                var right = 0u64
                if r < j { right = cost[(r + 1usize) * n + j] }
                if left + right < best { best = left + right }
                r += 1usize
            }
            cost[i * n + j] = best + sums[i * n + j]
            i += 1usize
        }
        length += 1usize
    }
    ret (cost[n - 1usize], ok)
}

// The area of the largest rectangle under a histogram, and its half-open column
// range; `stack.len >= heights.len`.
fn largest_rectangle_histogram(heights: []const u64, stack: []usize) -> (u64, usize, usize, err) {
    if stack.len < heights.len { ret (0u64, 0usize, 0usize, TooSmall) }
    var best = 0u64
    var best_low = 0usize
    var best_high = 0usize
    var top = 0usize
    var i = 0usize
    while i <= heights.len {
        var h = 0u64
        if i < heights.len { h = heights[i] }
        while top > 0usize && heights[stack[top - 1usize]] >= h {
            let height = heights[stack[top - 1usize]]
            top -= 1usize
            var low = 0usize
            if top > 0usize { low = stack[top - 1usize] + 1usize }
            let area = height * u64(i - low)
            if area > best {
                best = area
                best_low = low
                best_high = i
            }
        }
        if i < heights.len {
            stack[top] = i
            top += 1usize
        }
        i += 1usize
    }
    ret (best, best_low, best_high, ok)
}

// For each element, the index of the nearest previous strictly smaller element,
// or `values.len` when none, via a monotonic stack; `out.len` and `stack.len`
// at least `values.len`.
fn previous_smaller(values: []const i64, out: []usize, stack: []usize) -> err {
    if out.len < values.len || stack.len < values.len { ret TooSmall }
    var top = 0usize
    var i = 0usize
    while i < values.len {
        while top > 0usize && values[stack[top - 1usize]] >= values[i] { top -= 1usize }
        if top > 0usize { out[i] = stack[top - 1usize] } else { out[i] = values.len }
        stack[top] = i
        top += 1usize
        i += 1usize
    }
    ret ok
}

// A Li Chao tree over the integer domain `low..=high` holding lines; queries
// answer the minimum over inserted lines at a point. `lines.len` and
// `filled.len` must be at least `4 * (high - low + 1)`.
fn li_chao_init(lines: []Line, filled: []u8, low: i64, high: i64) -> (LiChao, err) {
    if high < low { ret (zero, Invalid) }
    let span = usize(high - low + 1i64)
    if lines.len < 4usize * span || filled.len < 4usize * span { ret (zero, TooSmall) }
    var i = 0usize
    while i < 4usize * span {
        filled[i] = 0u8
        i += 1usize
    }
    ret (LiChao { lines: lines, filled: filled, low: low, high: high }, ok)
}

fn li_chao_insert(t: *LiChao, line: Line) {
    var node = 1usize
    var lo = t.low
    var hi = t.high
    var incoming = line
    while true {
        if t.filled[node] == 0u8 {
            t.lines[node] = incoming
            t.filled[node] = 1u8
            ret
        }
        let middle = lo + (hi - lo) / 2i64
        var kept = t.lines[node]
        let incoming_middle = incoming.slope * middle + incoming.intercept
        let kept_middle = kept.slope * middle + kept.intercept
        if incoming_middle < kept_middle {
            t.lines[node] = incoming
            incoming = kept
            kept = t.lines[node]
        }
        if lo == hi { ret }
        let incoming_low = incoming.slope * lo + incoming.intercept
        let kept_low = kept.slope * lo + kept.intercept
        if incoming_low < kept_low {
            node = node * 2usize
            hi = middle
        } else {
            node = node * 2usize + 1usize
            lo = middle + 1i64
        }
    }
}

// The least value at `x` over the inserted lines; `false` when none is inserted.
fn li_chao_query(t: *const LiChao, x: i64) -> (i64, bool) {
    if x < t.low || x > t.high { ret (0i64, false) }
    var node = 1usize
    var lo = t.low
    var hi = t.high
    var best = 0i64
    var any = false
    while true {
        if t.filled[node] == 0u8 { break }
        let value = t.lines[node].slope * x + t.lines[node].intercept
        if !any || value < best {
            best = value
            any = true
        }
        if lo == hi { break }
        let middle = lo + (hi - lo) / 2i64
        if x <= middle {
            node = node * 2usize
            hi = middle
        } else {
            node = node * 2usize + 1usize
            lo = middle + 1i64
        }
    }
    ret (best, any)
}

// The convex hull trick for lines added in decreasing slope order and queried at
// increasing `x`: the hull of lower envelope lines lives in `hull`, kept by
// `count`, and `pointer` walks it. Returns the new count.
fn hull_add(hull: []Line, count: usize, line: Line) -> (usize, err) {
    var n = count
    while n >= 2usize {
        let a = hull[n - 2usize]
        let b = hull[n - 1usize]
        // `b` is useless when the new line meets `a` no later than `b` does.
        // (c_b - c_a) / (m_a - m_b) >= (c_l - c_a) / (m_a - m_l), cross-multiplied.
        let left = (b.intercept - a.intercept) * (a.slope - line.slope)
        let right = (line.intercept - a.intercept) * (a.slope - b.slope)
        if left >= right { n -= 1usize } else { break }
    }
    if n >= hull.len { ret (count, TooSmall) }
    hull[n] = line
    ret (n + 1usize, ok)
}

// The minimum over the hull at `x`, with `pointer` advanced monotonically.
fn hull_query(hull: []const Line, count: usize, pointer: *usize, x: i64) -> (i64, bool) {
    if count == 0usize { ret (0i64, false) }
    if *pointer >= count { *pointer = count - 1usize }
    while *pointer + 1usize < count {
        let here = hull[*pointer].slope * x + hull[*pointer].intercept
        let next = hull[*pointer + 1usize].slope * x + hull[*pointer + 1usize].intercept
        if next <= here { *pointer += 1usize } else { break }
    }
    ret (hull[*pointer].slope * x + hull[*pointer].intercept, true)
}

// Both directions of the monotonic stack: the nearest strictly smaller element
// before and after each one, `values.len` when there is none; `stack.len` and
// both outputs at least `values.len`.
fn monotonic_stack(values: []const i64, prev_smaller: []usize, next_smaller: []usize, stack: []usize) -> err {
    let prev_error = previous_smaller(values, prev_smaller, stack)
    if prev_error != ok { ret prev_error }
    if next_smaller.len < values.len { ret TooSmall }
    var top = 0usize
    var i = values.len
    while i > 0usize {
        i -= 1usize
        while top > 0usize && values[stack[top - 1usize]] >= values[i] { top -= 1usize }
        if top > 0usize { next_smaller[i] = stack[top - 1usize] } else { next_smaller[i] = values.len }
        stack[top] = i
        top += 1usize
    }
    ret ok
}

// The index of the nearest following strictly greater element, or `values.len`.
fn next_greater(values: []const i64, out: []usize, stack: []usize) -> err {
    if out.len < values.len || stack.len < values.len { ret TooSmall }
    var top = 0usize
    var i = values.len
    while i > 0usize {
        i -= 1usize
        while top > 0usize && values[stack[top - 1usize]] <= values[i] { top -= 1usize }
        if top > 0usize { out[i] = stack[top - 1usize] } else { out[i] = values.len }
        stack[top] = i
        top += 1usize
    }
    ret ok
}

// The minimum of `slopes[i] * x + intercepts[i]` over every line at each query
// (negate both to get the maximum). The lines are sorted by decreasing slope
// into `scratch` (`scratch.len >= slopes.len`), the lower hull is built there
// in place, and each query walks it with the pointer when the queries never
// decrease, else finds its line by binary search.
fn convex_hull_trick(slopes: []const i64, intercepts: []const i64, queries: []const i64, out: []i64, scratch: []Line) -> err {
    let n = slopes.len
    if intercepts.len != n || out.len < queries.len || scratch.len < n { ret TooSmall }
    if n == 0usize { ret Invalid }
    // ponytail: insertion sort, O(n^2); a merge sort when the line count grows.
    var i = 0usize
    while i < n {
        let line = Line { slope: slopes[i], intercept: intercepts[i] }
        var j = i
        while j > 0usize && (scratch[j - 1usize].slope < line.slope || (scratch[j - 1usize].slope == line.slope && scratch[j - 1usize].intercept > line.intercept)) {
            scratch[j] = scratch[j - 1usize]
            j -= 1usize
        }
        scratch[j] = line
        i += 1usize
    }
    // The hull never holds more lines than were consumed, so it fits in front.
    var count = 0usize
    var last_slope = 0i64
    i = 0usize
    while i < n {
        let line = scratch[i]
        if i == 0usize || line.slope != last_slope {
            let (added, add_error) = hull_add(scratch, count, line)
            if add_error != ok { ret add_error }
            count = added
        }
        last_slope = line.slope
        i += 1usize
    }
    var monotone = true
    i = 1usize
    while i < queries.len {
        if queries[i] < queries[i - 1usize] { monotone = false }
        i += 1usize
    }
    var pointer = 0usize
    i = 0usize
    while i < queries.len {
        let x = queries[i]
        if monotone {
            let (value, _) = hull_query(scratch[..count], count, &pointer, x)
            out[i] = value
        } else {
            var lo = 0usize
            var hi = count - 1usize
            while lo < hi {
                let mid = lo + (hi - lo) / 2usize
                let here = scratch[mid].slope * x + scratch[mid].intercept
                let after = scratch[mid + 1usize].slope * x + scratch[mid + 1usize].intercept
                if after <= here { lo = mid + 1usize } else { hi = mid }
            }
            out[i] = scratch[lo].slope * x + scratch[lo].intercept
        }
        i += 1usize
    }
    ret ok
}

// The same minima by a Li Chao tree over the span of the queries; `lines.len`
// and `filled.len` at least `4 * (max query - min query + 1)`.
fn li_chao_tree(slopes: []const i64, intercepts: []const i64, queries: []const i64, out: []i64, lines: []Line, filled: []u8) -> err {
    let n = slopes.len
    if intercepts.len != n || out.len < queries.len { ret TooSmall }
    if queries.len == 0usize { ret ok }
    if n == 0usize { ret Invalid }
    var low = queries[0usize]
    var high = queries[0usize]
    var i = 1usize
    while i < queries.len {
        if queries[i] < low { low = queries[i] }
        if queries[i] > high { high = queries[i] }
        i += 1usize
    }
    let (built, init_error) = li_chao_init(lines, filled, low, high)
    if init_error != ok { ret init_error }
    var tree = built
    i = 0usize
    while i < n {
        li_chao_insert(&tree, Line { slope: slopes[i], intercept: intercepts[i] })
        i += 1usize
    }
    i = 0usize
    while i < queries.len {
        let (value, found) = li_chao_query(&tree, queries[i])
        if !found { ret Invalid }
        out[i] = value
        i += 1usize
    }
    ret ok
}
