// Sorting over slices.
//
// `in_place` and `stable_in_place` order by `T.cmp`; the `_by` forms take the
// comparison as a value, which is how an ordering over borrowed context is
// expressed. The radix entry points are for unsigned integers only.
//
// Every module-scope declaration is exported (spec section 5), so the sift, merge
// and counting loops are written out at each site rather than factored into helpers
// that would widen the module's public surface beyond its frozen API.

use e.mem

// Heapsort: an in-place max-heap, then repeated extraction from the back. Chosen
// over quicksort for its guaranteed bound and because it needs no recursion.
fn in_place[T: type](items: []T) {
    if items.len < 2usize { ret }
    var start = items.len / 2usize
    while start != 0usize {
        start -= 1usize
        var at = start
        while true {
            let left = at * 2usize + 1usize
            if left >= items.len { break }
            var largest = left
            let right = left + 1usize
            if right < items.len && T.cmp(items[right], items[left]) > 0i32 { largest = right }
            if T.cmp(items[largest], items[at]) <= 0i32 { break }
            let carried = items[at]
            items[at] = items[largest]
            items[largest] = carried
            at = largest
        }
    }
    var end = items.len
    while end > 1usize {
        end -= 1usize
        let carried = items[0usize]
        items[0usize] = items[end]
        items[end] = carried
        var at = 0usize
        while true {
            let left = at * 2usize + 1usize
            if left >= end { break }
            var largest = left
            let right = left + 1usize
            if right < end && T.cmp(items[right], items[left]) > 0i32 { largest = right }
            if T.cmp(items[largest], items[at]) <= 0i32 { break }
            let moved = items[at]
            items[at] = items[largest]
            items[largest] = moved
            at = largest
        }
    }
}

fn in_place_by[T: type, Ctx: type](items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) {
    if items.len < 2usize { ret }
    var start = items.len / 2usize
    while start != 0usize {
        start -= 1usize
        var at = start
        while true {
            let left = at * 2usize + 1usize
            if left >= items.len { break }
            var largest = left
            let right = left + 1usize
            if right < items.len && cmp(ctx, items[right], items[left]) > 0i32 { largest = right }
            if cmp(ctx, items[largest], items[at]) <= 0i32 { break }
            let carried = items[at]
            items[at] = items[largest]
            items[largest] = carried
            at = largest
        }
    }
    var end = items.len
    while end > 1usize {
        end -= 1usize
        let carried = items[0usize]
        items[0usize] = items[end]
        items[end] = carried
        var at = 0usize
        while true {
            let left = at * 2usize + 1usize
            if left >= end { break }
            var largest = left
            let right = left + 1usize
            if right < end && cmp(ctx, items[right], items[left]) > 0i32 { largest = right }
            if cmp(ctx, items[largest], items[at]) <= 0i32 { break }
            let moved = items[at]
            items[at] = items[largest]
            items[largest] = moved
            at = largest
        }
    }
}

// Bottom-up merge sort. Equal elements keep their input order because the left run
// wins every tie. The arena holds one scratch buffer, released before returning.
fn stable_in_place[T: type](a: *mem.Arena, items: []T) -> err {
    if items.len < 2usize { ret ok }
    let marker = mem.mark(a)
    let (scratch, scratch_error) = mem.alloc[T](a, items.len)
    if scratch_error != ok { ret scratch_error }
    var width = 1usize
    while width < items.len {
        var low = 0usize
        while low < items.len {
            var middle = low + width
            if middle > items.len { middle = items.len }
            var high = low + width * 2usize
            if high > items.len { high = items.len }
            var left = low
            var right = middle
            var out = low
            while out < high {
                var take_left = left < middle
                if take_left && right < high {
                    if T.cmp(items[right], items[left]) < 0i32 { take_left = false }
                }
                if take_left {
                    scratch[out] = items[left]
                    left += 1usize
                } else {
                    scratch[out] = items[right]
                    right += 1usize
                }
                out += 1usize
            }
            out = low
            while out < high {
                items[out] = scratch[out]
                out += 1usize
            }
            low += width * 2usize
        }
        width = width * 2usize
    }
    mem.reset(a, marker)
    ret ok
}

fn stable_in_place_by[T: type, Ctx: type](a: *mem.Arena, items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> err {
    if items.len < 2usize { ret ok }
    let marker = mem.mark(a)
    let (scratch, scratch_error) = mem.alloc[T](a, items.len)
    if scratch_error != ok { ret scratch_error }
    var width = 1usize
    while width < items.len {
        var low = 0usize
        while low < items.len {
            var middle = low + width
            if middle > items.len { middle = items.len }
            var high = low + width * 2usize
            if high > items.len { high = items.len }
            var left = low
            var right = middle
            var out = low
            while out < high {
                var take_left = left < middle
                if take_left && right < high {
                    if cmp(ctx, items[right], items[left]) < 0i32 { take_left = false }
                }
                if take_left {
                    scratch[out] = items[left]
                    left += 1usize
                } else {
                    scratch[out] = items[right]
                    right += 1usize
                }
                out += 1usize
            }
            out = low
            while out < high {
                items[out] = scratch[out]
                out += 1usize
            }
            low += width * 2usize
        }
        width = width * 2usize
    }
    mem.reset(a, marker)
    ret ok
}

// Least-significant-digit radix over one byte at a time: four passes for u32,
// eight for u64. Each pass is a counting sort, so the whole thing is stable.
fn radix_u32_in_place(a: *mem.Arena, items: []u32) -> err {
    if items.len < 2usize { ret ok }
    let marker = mem.mark(a)
    let (scratch, scratch_error) = mem.alloc[u32](a, items.len)
    if scratch_error != ok { ret scratch_error }
    var counts: [256]usize = zero
    var shift = 0usize
    while shift < 32usize {
        var bucket = 0usize
        while bucket < 256usize {
            counts[bucket] = 0usize
            bucket += 1usize
        }
        var at = 0usize
        while at < items.len {
            let digit = (items[at] >> shift) & 255u32
            counts[usize(digit)] += 1usize
            at += 1usize
        }
        var running = 0usize
        bucket = 0usize
        while bucket < 256usize {
            let held = counts[bucket]
            counts[bucket] = running
            running += held
            bucket += 1usize
        }
        at = 0usize
        while at < items.len {
            let digit = (items[at] >> shift) & 255u32
            scratch[counts[usize(digit)]] = items[at]
            counts[usize(digit)] += 1usize
            at += 1usize
        }
        at = 0usize
        while at < items.len {
            items[at] = scratch[at]
            at += 1usize
        }
        shift += 8usize
    }
    mem.reset(a, marker)
    ret ok
}

fn radix_u64_in_place(a: *mem.Arena, items: []u64) -> err {
    if items.len < 2usize { ret ok }
    let marker = mem.mark(a)
    let (scratch, scratch_error) = mem.alloc[u64](a, items.len)
    if scratch_error != ok { ret scratch_error }
    var counts: [256]usize = zero
    var shift = 0usize
    while shift < 64usize {
        var bucket = 0usize
        while bucket < 256usize {
            counts[bucket] = 0usize
            bucket += 1usize
        }
        var at = 0usize
        while at < items.len {
            let digit = (items[at] >> shift) & 255u64
            counts[usize(digit)] += 1usize
            at += 1usize
        }
        var running = 0usize
        bucket = 0usize
        while bucket < 256usize {
            let held = counts[bucket]
            counts[bucket] = running
            running += held
            bucket += 1usize
        }
        at = 0usize
        while at < items.len {
            let digit = (items[at] >> shift) & 255u64
            scratch[counts[usize(digit)]] = items[at]
            counts[usize(digit)] += 1usize
            at += 1usize
        }
        at = 0usize
        while at < items.len {
            items[at] = scratch[at]
            at += 1usize
        }
        shift += 8usize
    }
    mem.reset(a, marker)
    ret ok
}

fn is_sorted[T: type](items: []const T) -> bool {
    if items.len < 2usize { ret true }
    var at = 1usize
    while at < items.len {
        if T.cmp(items[at], items[at - 1usize]) < 0i32 { ret false }
        at += 1usize
    }
    ret true
}
