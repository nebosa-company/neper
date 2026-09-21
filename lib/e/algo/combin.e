// Combinatorial enumeration: binomials, permutations, combinations, subsets as
// bit masks, and the zeta transforms over subsets.
//
// Enumerators either step a caller-held state in place (`next_*`, answering
// `false` when the sequence is exhausted) or call a visitor per element and stop
// when it answers `false`. Masks are `u64`, so a ground set has at most 64
// elements; the transforms work on a table of `1 << bits` entries in place.

error Invalid
error TooSmall

// `n choose k`, and whether it fit in a `u64`.
fn binomial(n: u64, k: u64) -> (u64, bool) {
    if k > n { ret (0u64, true) }
    var kk = k
    if kk > n - kk { kk = n - kk }
    var result = 1u64
    var i = 1u64
    while i <= kk {
        // result * (n - kk + i) / i, with the product checked for overflow.
        let factor = n - kk + i
        let g = gcd(result, i)
        let reduced = result / g
        let divisor = i / g
        let scaled = factor / divisor
        if reduced != 0u64 && scaled > 18446744073709551615u64 / reduced { ret (0u64, false) }
        result = reduced * scaled
        i += 1u64
    }
    ret (result, true)
}

fn gcd(a: u64, b: u64) -> u64 {
    var x = a
    var y = b
    while y != 0u64 {
        let r = x % y
        x = y
        y = r
    }
    ret x
}

// `n!`, and whether it fit; `20!` is the largest.
fn factorial(n: u64) -> (u64, bool) {
    if n > 20u64 { ret (0u64, false) }
    var result = 1u64
    var i = 2u64
    while i <= n {
        result = result * i
        i += 1u64
    }
    ret (result, true)
}

// Rearranges `items` into the next permutation in `T.cmp` order; `false` (and
// the first permutation) after the last.
fn next_permutation[T: type](items: []T) -> bool {
    if items.len < 2usize { ret false }
    var i = items.len - 1usize
    while i > 0usize && T.cmp(items[i - 1usize], items[i]) >= 0i32 { i -= 1usize }
    if i == 0usize {
        reverse[T](items)
        ret false
    }
    var j = items.len - 1usize
    while T.cmp(items[j], items[i - 1usize]) <= 0i32 { j -= 1usize }
    let swap = items[i - 1usize]
    items[i - 1usize] = items[j]
    items[j] = swap
    reverse[T](items[i..])
    ret true
}

fn reverse[T: type](items: []T) {
    var lo = 0usize
    var hi = items.len
    while lo + 1usize < hi {
        hi -= 1usize
        let swap = items[lo]
        items[lo] = items[hi]
        items[hi] = swap
        lo += 1usize
    }
}

// Heap's algorithm: visits every permutation of `items` once, each by one swap;
// `scratch.len >= items.len`. Answers `false` when the visitor stopped it.
fn permutations[T: type, Ctx: type](items: []T, scratch: []usize, ctx: *Ctx, visit: fn(*Ctx, []const T) -> bool) -> (bool, err) {
    let n = items.len
    if scratch.len < n { ret (true, TooSmall) }
    var k = 0usize
    while k < n {
        scratch[k] = 0usize
        k += 1usize
    }
    if !visit(ctx, items) { ret (false, ok) }
    var i = 1usize
    while i < n {
        if scratch[i] < i {
            var a = 0usize
            if i % 2usize == 1usize { a = scratch[i] }
            let swap = items[a]
            items[a] = items[i]
            items[i] = swap
            if !visit(ctx, items) { ret (false, ok) }
            scratch[i] += 1usize
            i = 1usize
        } else {
            scratch[i] = 0usize
            i += 1usize
        }
    }
    ret (true, ok)
}

// Steps `indices`, an ascending `k`-combination of `0..n`, to the next in
// lexicographic order; `false` (and the first combination) after the last.
fn next_combination(indices: []usize, n: usize) -> bool {
    let k = indices.len
    if k == 0usize || k > n { ret false }
    var i = k
    while i > 0usize {
        i -= 1usize
        if indices[i] < n - k + i {
            indices[i] += 1usize
            var j = i + 1usize
            while j < k {
                indices[j] = indices[j - 1usize] + 1usize
                j += 1usize
            }
            ret true
        }
    }
    i = 0usize
    while i < k {
        indices[i] = i
        i += 1usize
    }
    ret false
}

// Visits every subset of a `count`-element set as a mask, from empty to full.
fn subsets[Ctx: type](count: u32, ctx: *Ctx, visit: fn(*Ctx, u64) -> bool) -> (bool, err) {
    if count > 64u32 { ret (true, Invalid) }
    var mask = 0u64
    while true {
        if !visit(ctx, mask) { ret (false, ok) }
        if count == 64u32 {
            if mask == 18446744073709551615u64 { break }
        } else if mask + 1u64 == 1u64 << u64(count) { break }
        mask += 1u64
    }
    ret (true, ok)
}

// Gosper's hack: the next larger mask with the same number of set bits, or 0
// when `mask` is the largest such value below `2^64`.
fn next_subset_same_popcount(mask: u64) -> u64 {
    if mask == 0u64 { ret 0u64 }
    let lowest = mask & (0u64 -% mask)
    let ripple = mask +% lowest
    if ripple == 0u64 { ret 0u64 }
    let ones = ((mask ^ ripple) >> 2u64) / lowest
    ret ripple | ones
}

// The submask after `sub` when walking the submasks of `mask` downward from
// `mask` itself; `false` once the empty set has been visited.
fn next_submask(sub: u64, mask: u64) -> (u64, bool) {
    if sub == 0u64 { ret (0u64, false) }
    ret ((sub -% 1u64) & mask, true)
}

// Visits every submask of `mask`, from `mask` down to the empty set.
fn subsets_of_mask[Ctx: type](mask: u64, ctx: *Ctx, visit: fn(*Ctx, u64) -> bool) -> bool {
    var sub = mask
    while true {
        if !visit(ctx, sub) { ret false }
        if sub == 0u64 { break }
        sub = (sub -% 1u64) & mask
    }
    ret true
}

// The zeta transform over subsets in place: on return `values[mask]` is the sum of
// the input over every submask of `mask`. `values.len == 1 << bits`.
fn subset_sums(values: []i64, bits: u32) -> err {
    if bits > 63u32 || values.len != 1usize << usize(bits) { ret Invalid }
    var bit = 0usize
    while bit < usize(bits) {
        var mask = 0usize
        while mask < values.len {
            if ((mask >> bit) & 1usize) == 1usize { values[mask] += values[mask ^ (1usize << bit)] }
            mask += 1usize
        }
        bit += 1usize
    }
    ret ok
}

// The inverse of `subset_sums` (the Möbius transform).
fn subset_sums_inverse(values: []i64, bits: u32) -> err {
    if bits > 63u32 || values.len != 1usize << usize(bits) { ret Invalid }
    var bit = 0usize
    while bit < usize(bits) {
        var mask = 0usize
        while mask < values.len {
            if ((mask >> bit) & 1usize) == 1usize { values[mask] -= values[mask ^ (1usize << bit)] }
            mask += 1usize
        }
        bit += 1usize
    }
    ret ok
}

// The sum over every superset of each mask, in place.
fn superset_sums(values: []i64, bits: u32) -> err {
    if bits > 63u32 || values.len != 1usize << usize(bits) { ret Invalid }
    var bit = 0usize
    while bit < usize(bits) {
        var mask = 0usize
        while mask < values.len {
            if ((mask >> bit) & 1usize) == 0usize { values[mask] += values[mask | (1usize << bit)] }
            mask += 1usize
        }
        bit += 1usize
    }
    ret ok
}
