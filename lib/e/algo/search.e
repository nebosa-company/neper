// Searching over slices, order-statistic selection and cycle finding.
//
// The sorted-slice entry points order by `T.cmp` and answer an index; `lower_bound`,
// `upper_bound` and `equal_range` are the half-open forms that never fail. The `_by`
// forms take a probe that compares an element against the wanted key, which is how
// a search over borrowed context or a key of another type is expressed. `kth`
// reorders its slice; it is quickselect with a median-of-three pivot, and
// `kth_deterministic` is the median-of-medians form with a linear worst case.

// The index of an element equal to `key`, or where it would be inserted.
fn binary[T: type](items: []const T, key: T) -> (usize, bool) {
    var low = 0usize
    var high = items.len
    while low < high {
        let middle = low + (high - low) / 2usize
        let order = T.cmp(items[middle], key)
        if order == 0i32 { ret (middle, true) }
        if order < 0i32 { low = middle + 1usize } else { high = middle }
    }
    ret (low, false)
}

// `probe(ctx, item)` answers `< 0` when `item` orders before the wanted key.
fn binary_by[T: type, Ctx: type](items: []const T, ctx: *Ctx, probe: fn(*Ctx, T) -> i32) -> (usize, bool) {
    var low = 0usize
    var high = items.len
    while low < high {
        let middle = low + (high - low) / 2usize
        let order = probe(ctx, items[middle])
        if order == 0i32 { ret (middle, true) }
        if order < 0i32 { low = middle + 1usize } else { high = middle }
    }
    ret (low, false)
}

// The first index whose element is not less than `key`.
fn lower_bound[T: type](items: []const T, key: T) -> usize {
    var low = 0usize
    var high = items.len
    while low < high {
        let middle = low + (high - low) / 2usize
        if T.cmp(items[middle], key) < 0i32 { low = middle + 1usize } else { high = middle }
    }
    ret low
}

// The first index whose element is greater than `key`.
fn upper_bound[T: type](items: []const T, key: T) -> usize {
    var low = 0usize
    var high = items.len
    while low < high {
        let middle = low + (high - low) / 2usize
        if T.cmp(items[middle], key) <= 0i32 { low = middle + 1usize } else { high = middle }
    }
    ret low
}

// The half-open range of elements equal to `key`.
fn equal_range[T: type](items: []const T, key: T) -> (usize, usize) {
    let first = lower_bound[T](items, key)
    let last = upper_bound[T](items[first..], key)
    ret (first, first + last)
}

// The first index holding `key` in an unordered slice.
fn linear[T: type](items: []const T, key: T) -> (usize, bool) {
    var at = 0usize
    while at < items.len {
        if T.cmp(items[at], key) == 0i32 { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// Binary search that first finds a bound by doubling, for a key expected near the
// front or a slice whose length is large compared with the answer.
fn exponential[T: type](items: []const T, key: T) -> (usize, bool) {
    if items.len == 0usize { ret (0usize, false) }
    var bound = 1usize
    while bound < items.len && T.cmp(items[bound], key) < 0i32 { bound = bound * 2usize }
    var low = bound / 2usize
    var high = bound + 1usize
    if high > items.len { high = items.len }
    let (at, found) = binary[T](items[low..high], key)
    ret (low + at, found)
}

// Probes where a uniformly distributed key would sit; expected `O(log log n)`.
fn interpolation(items: []const i64, key: i64) -> (usize, bool) {
    if items.len == 0usize { ret (0usize, false) }
    var low = 0usize
    var high = items.len - 1usize
    while low <= high && key >= items[low] && key <= items[high] {
        let span = items[high] - items[low]
        var at = low
        if span != 0i64 {
            let fraction = (key - items[low]) * i64(high - low)
            at = low + usize(fraction / span)
        }
        if items[at] == key { ret (at, true) }
        if items[at] < key { low = at + 1usize } else {
            if at == 0usize { ret (0usize, false) }
            high = at - 1usize
        }
    }
    if low < items.len && items[low] == key { ret (low, true) }
    ret (low, false)
}

// The argument maximising a unimodal `f` over the closed integer range.
fn ternary_max[Ctx: type](low: i64, high: i64, ctx: *Ctx, f: fn(*Ctx, i64) -> i64) -> i64 {
    var lo = low
    var hi = high
    while hi - lo > 2i64 {
        let third = (hi - lo) / 3i64
        let m1 = lo + third
        let m2 = hi - third
        if f(ctx, m1) < f(ctx, m2) { lo = m1 + 1i64 } else { hi = m2 - 1i64 }
    }
    var best = lo
    var at = lo + 1i64
    while at <= hi {
        if f(ctx, at) > f(ctx, best) { best = at }
        at += 1i64
    }
    ret best
}

// Saddleback search over a row-major matrix whose rows and columns both ascend:
// starts at the top-right corner and steps left or down.
fn matrix_sorted[T: type](items: []const T, columns: usize, key: T) -> (usize, usize, bool) {
    if columns == 0usize || items.len == 0usize { ret (0usize, 0usize, false) }
    let rows = items.len / columns
    var row = 0usize
    var column = columns
    while row < rows && column > 0usize {
        let order = T.cmp(items[row * columns + column - 1usize], key)
        if order == 0i32 { ret (row, column - 1usize, true) }
        if order > 0i32 { column -= 1usize } else { row += 1usize }
    }
    ret (0usize, 0usize, false)
}

// The element that would sit at `k` in sorted order; `items` is partitioned around
// it on return. `k` must be in range.
fn kth[T: type](items: []T, k: usize) -> T {
    var low = 0usize
    var high = items.len - 1usize
    while low < high {
        // Median of three chooses the pivot, which is parked at `high`.
        let middle = low + (high - low) / 2usize
        if T.cmp(items[middle], items[low]) < 0i32 {
            let s = items[middle]
            items[middle] = items[low]
            items[low] = s
        }
        if T.cmp(items[high], items[low]) < 0i32 {
            let s = items[high]
            items[high] = items[low]
            items[low] = s
        }
        if T.cmp(items[middle], items[high]) < 0i32 {
            let s = items[high]
            items[high] = items[middle]
            items[middle] = s
        }
        let pivot = items[high]
        var store = low
        var i = low
        while i < high {
            if T.cmp(items[i], pivot) < 0i32 {
                let s = items[i]
                items[i] = items[store]
                items[store] = s
                store += 1usize
            }
            i += 1usize
        }
        let s = items[store]
        items[store] = items[high]
        items[high] = s
        if k == store { ret items[k] }
        if k < store { high = store - 1usize } else { low = store + 1usize }
    }
    ret items[k]
}

// Median of medians: groups of five, the pivot is the recursive median of the
// group medians, so every step discards at least three tenths of the range.
fn kth_deterministic[T: type](items: []T, k: usize) -> T {
    var low = 0usize
    var high = items.len
    var want = k
    while high - low > 5usize {
        // Move each group's median to the front of the range.
        var group = low
        var medians = low
        while group < high {
            var end = group + 5usize
            if end > high { end = high }
            var a = group + 1usize
            while a < end {
                var b = a
                while b > group && T.cmp(items[b], items[b - 1usize]) < 0i32 {
                    let s = items[b]
                    items[b] = items[b - 1usize]
                    items[b - 1usize] = s
                    b -= 1usize
                }
                a += 1usize
            }
            let median = group + (end - group - 1usize) / 2usize
            let s = items[medians]
            items[medians] = items[median]
            items[median] = s
            medians += 1usize
            group += 5usize
        }
        let pivot = kth_deterministic[T](items[low..medians], (medians - low) / 2usize)
        // Three-way partition around the pivot value.
        var lt = low
        var i = low
        var gt = high
        while i < gt {
            let order = T.cmp(items[i], pivot)
            if order < 0i32 {
                let s = items[i]
                items[i] = items[lt]
                items[lt] = s
                lt += 1usize
                i += 1usize
            } else if order > 0i32 {
                gt -= 1usize
                let s = items[i]
                items[i] = items[gt]
                items[gt] = s
            } else {
                i += 1usize
            }
        }
        if want < lt { high = lt } else if want >= gt { low = gt } else { ret pivot }
    }
    var a = low + 1usize
    while a < high {
        var b = a
        while b > low && T.cmp(items[b], items[b - 1usize]) < 0i32 {
            let s = items[b]
            items[b] = items[b - 1usize]
            items[b - 1usize] = s
            b -= 1usize
        }
        a += 1usize
    }
    ret items[want]
}

// Floyd's tortoise and hare over the sequence `start, next(start), ...`: the index
// where the cycle begins and its length.
fn cycle_floyd[Ctx: type](start: u64, ctx: *Ctx, next: fn(*Ctx, u64) -> u64) -> (usize, usize) {
    var tortoise = next(ctx, start)
    var hare = next(ctx, next(ctx, start))
    while tortoise != hare {
        tortoise = next(ctx, tortoise)
        hare = next(ctx, next(ctx, hare))
    }
    var mu = 0usize
    tortoise = start
    while tortoise != hare {
        tortoise = next(ctx, tortoise)
        hare = next(ctx, hare)
        mu += 1usize
    }
    var lambda = 1usize
    hare = next(ctx, tortoise)
    while tortoise != hare {
        hare = next(ctx, hare)
        lambda += 1usize
    }
    ret (mu, lambda)
}

// Brent's variant: the hare teleports to the tortoise at each power of two, so
// `next` is called fewer times than Floyd's form needs.
fn cycle_brent[Ctx: type](start: u64, ctx: *Ctx, next: fn(*Ctx, u64) -> u64) -> (usize, usize) {
    var power = 1usize
    var lambda = 1usize
    var tortoise = start
    var hare = next(ctx, start)
    while tortoise != hare {
        if power == lambda {
            tortoise = hare
            power = power * 2usize
            lambda = 0usize
        }
        hare = next(ctx, hare)
        lambda += 1usize
    }
    tortoise = start
    hare = start
    var at = 0usize
    while at < lambda {
        hare = next(ctx, hare)
        at += 1usize
    }
    var mu = 0usize
    while tortoise != hare {
        tortoise = next(ctx, tortoise)
        hare = next(ctx, hare)
        mu += 1usize
    }
    ret (mu, lambda)
}
