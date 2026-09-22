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

error TooSmall
error Invalid

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
        var slot = 0usize
        while slot < 256usize {
            counts[slot] = 0usize
            slot += 1usize
        }
        var at = 0usize
        while at < items.len {
            let digit = (items[at] >> shift) & 255u32
            counts[usize(digit)] += 1usize
            at += 1usize
        }
        var running = 0usize
        slot = 0usize
        while slot < 256usize {
            let held = counts[slot]
            counts[slot] = running
            running += held
            slot += 1usize
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
        var slot = 0usize
        while slot < 256usize {
            counts[slot] = 0usize
            slot += 1usize
        }
        var at = 0usize
        while at < items.len {
            let digit = (items[at] >> shift) & 255u64
            counts[usize(digit)] += 1usize
            at += 1usize
        }
        var running = 0usize
        slot = 0usize
        while slot < 256usize {
            let held = counts[slot]
            counts[slot] = running
            running += held
            slot += 1usize
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

// The named sorters below (D882) order by `T.cmp` like `in_place`, or by a caller
// key function where the key type is intrinsic to the algorithm. Stable: insertion,
// merge, patience, counting, bucket, radix_bytes, external_merge.

// Insertion sort: stable, and what `quick` and `bucket` fall back to on short runs.
fn insertion[T: type](items: []T) {
    var i = 1usize
    while i < items.len {
        let held = items[i]
        var j = i
        while j > 0usize && T.cmp(items[j - 1usize], held) > 0i32 {
            items[j] = items[j - 1usize]
            j -= 1usize
        }
        items[j] = held
        i += 1usize
    }
}

// Shell sort over the Ciura gap sequence (701 down to 1). Not stable.
// ponytail: the sequence is not extended by 2.25 past 701, so very long inputs
// only lose speed, never correctness.
fn shell[T: type](items: []T) {
    var gaps: [8]usize = zero
    gaps[0usize] = 701usize
    gaps[1usize] = 301usize
    gaps[2usize] = 132usize
    gaps[3usize] = 57usize
    gaps[4usize] = 23usize
    gaps[5usize] = 10usize
    gaps[6usize] = 4usize
    gaps[7usize] = 1usize
    var g = 0usize
    while g < 8usize {
        let gap = gaps[g]
        var i = gap
        while i < items.len {
            let held = items[i]
            var j = i
            while j >= gap && T.cmp(items[j - gap], held) > 0i32 {
                items[j] = items[j - gap]
                j -= gap
            }
            items[j] = held
            i += 1usize
        }
        g += 1usize
    }
}

// Heapsort under its own name: `in_place` is the heapsort.
fn heap[T: type](items: []T) { in_place[T](items) }

// Top-down merge sort through a caller `scratch` of at least `items.len`. Stable:
// the left half wins every tie.
fn merge[T: type](items: []T, scratch: []T) -> err {
    if scratch.len < items.len { ret TooSmall }
    if items.len < 2usize { ret ok }
    let middle = items.len / 2usize
    let _ = merge[T](items[..middle], scratch[..middle])
    let _ = merge[T](items[middle..items.len], scratch[middle..items.len])
    var left = 0usize
    var right = middle
    var out = 0usize
    while out < items.len {
        var take_left = left < middle
        if take_left && right < items.len {
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
    out = 0usize
    while out < items.len {
        items[out] = scratch[out]
        out += 1usize
    }
    ret ok
}

// Quicksort: median of three for the pivot, Hoare partition, insertion sort below
// sixteen elements. Not stable.
fn quick[T: type](items: []T) {
    if items.len < 16usize {
        insertion[T](items)
        ret
    }
    let n = items.len
    let mid = n / 2usize
    let last = n - 1usize
    if T.cmp(items[mid], items[0usize]) < 0i32 {
        let carried = items[mid]
        items[mid] = items[0usize]
        items[0usize] = carried
    }
    if T.cmp(items[last], items[0usize]) < 0i32 {
        let carried = items[last]
        items[last] = items[0usize]
        items[0usize] = carried
    }
    if T.cmp(items[last], items[mid]) < 0i32 {
        let carried = items[last]
        items[last] = items[mid]
        items[mid] = carried
    }
    let pivot = items[mid]
    var i = 0usize
    var j = n
    while true {
        while T.cmp(items[i], pivot) < 0i32 { i += 1usize }
        j -= 1usize
        while T.cmp(items[j], pivot) > 0i32 { j -= 1usize }
        if i >= j { break }
        let carried = items[i]
        items[i] = items[j]
        items[j] = carried
        i += 1usize
    }
    quick[T](items[..j + 1usize])
    quick[T](items[j + 1usize..n])
}

// Cycle sort: every element is written at most once, into its final slot; the
// answer is how many writes that took. Not stable.
fn cycle[T: type](items: []T) -> usize {
    var writes = 0usize
    let n = items.len
    var start = 0usize
    while start + 1usize < n {
        var item = items[start]
        var pos = start
        var i = start + 1usize
        while i < n {
            if T.cmp(items[i], item) < 0i32 { pos += 1usize }
            i += 1usize
        }
        if pos == start {
            start += 1usize
            continue
        }
        while T.cmp(items[pos], item) == 0i32 { pos += 1usize }
        var carried = items[pos]
        items[pos] = item
        item = carried
        writes += 1usize
        while pos != start {
            pos = start
            i = start + 1usize
            while i < n {
                if T.cmp(items[i], item) < 0i32 { pos += 1usize }
                i += 1usize
            }
            while T.cmp(items[pos], item) == 0i32 { pos += 1usize }
            carried = items[pos]
            items[pos] = item
            item = carried
            writes += 1usize
        }
        start += 1usize
    }
    ret writes
}

// Patience sorting: deal each element onto the leftmost pile whose top is greater
// (binary search over the pile tops, which stay in increasing order), then merge the
// piles through a min-heap of their tops. Stable, because equal elements land on
// piles left to right and ties in the heap go to the earlier index. The answer is
// the pile count, which is the length of the longest non-decreasing subsequence.
// `scratch`, `below` and `tops` each need `items.len` slots.
fn patience[T: type](items: []T, scratch: []T, below: []usize, tops: []usize) -> (usize, err) {
    let n = items.len
    if scratch.len < n || below.len < n || tops.len < n { ret (0usize, TooSmall) }
    var piles = 0usize
    var i = 0usize
    while i < n {
        var low = 0usize
        var high = piles
        while low < high {
            let mid = (low + high) / 2usize
            if T.cmp(items[tops[mid]], items[i]) > 0i32 { high = mid } else { low = mid + 1usize }
        }
        if low == piles {
            below[i] = n
            piles += 1usize
        } else {
            below[i] = tops[low]
        }
        tops[low] = i
        i += 1usize
    }
    // The tops are sorted by (key, index), which already satisfies the heap order.
    var size = piles
    var out = 0usize
    while size > 0usize {
        let taken = tops[0usize]
        scratch[out] = items[taken]
        out += 1usize
        if below[taken] < n {
            tops[0usize] = below[taken]
        } else {
            size -= 1usize
            tops[0usize] = tops[size]
        }
        var node = 0usize
        while true {
            let left = node * 2usize + 1usize
            if left >= size { break }
            var smallest = left
            let right = left + 1usize
            if right < size {
                let order = T.cmp(items[tops[right]], items[tops[left]])
                if order < 0i32 || (order == 0i32 && tops[right] < tops[left]) { smallest = right }
            }
            let order = T.cmp(items[tops[smallest]], items[tops[node]])
            if order > 0i32 || (order == 0i32 && tops[smallest] > tops[node]) { break }
            let carried = tops[node]
            tops[node] = tops[smallest]
            tops[smallest] = carried
            node = smallest
        }
    }
    i = 0usize
    while i < n {
        items[i] = scratch[i]
        i += 1usize
    }
    ret (piles, ok)
}

// Counting sort by a `u32` key below `bound`; `counts` needs `bound` slots and
// `scratch` needs `items.len`. Stable. A key at or past `bound` is `Invalid`.
fn counting[T: type, Ctx: type](items: []T, scratch: []T, ctx: *Ctx, key: fn(*Ctx, T) -> u32, bound: u32, counts: []usize) -> err {
    let n = items.len
    if scratch.len < n || counts.len < usize(bound) { ret TooSmall }
    var b = 0usize
    while b < usize(bound) {
        counts[b] = 0usize
        b += 1usize
    }
    var i = 0usize
    while i < n {
        let k = key(ctx, items[i])
        if k >= bound { ret Invalid }
        counts[usize(k)] += 1usize
        i += 1usize
    }
    var running = 0usize
    b = 0usize
    while b < usize(bound) {
        let held = counts[b]
        counts[b] = running
        running += held
        b += 1usize
    }
    i = 0usize
    while i < n {
        let k = usize(key(ctx, items[i]))
        scratch[counts[k]] = items[i]
        counts[k] += 1usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        items[i] = scratch[i]
        i += 1usize
    }
    ret ok
}

// Bucket sort by an `f64` key in [0, 1): `starts.len - 1` equal-width buckets, a
// stable scatter into `scratch`, then an insertion sort of each bucket. `starts`
// is left holding the bucket boundaries. A key outside [0, 1) is `Invalid`.
fn bucket[T: type, Ctx: type](items: []T, scratch: []T, ctx: *Ctx, key: fn(*Ctx, T) -> f64, starts: []usize) -> err {
    let n = items.len
    if scratch.len < n || starts.len < 2usize { ret TooSmall }
    let buckets = starts.len - 1usize
    var b = 0usize
    while b <= buckets {
        starts[b] = 0usize
        b += 1usize
    }
    var i = 0usize
    while i < n {
        let k = key(ctx, items[i])
        if !(k >= 0.0f64 && k < 1.0f64) { ret Invalid }
        starts[usize(k * f64(buckets)) + 1usize] += 1usize
        i += 1usize
    }
    b = 1usize
    while b <= buckets {
        starts[b] += starts[b - 1usize]
        b += 1usize
    }
    i = 0usize
    while i < n {
        let k = usize(key(ctx, items[i]) * f64(buckets))
        scratch[starts[k]] = items[i]
        starts[k] += 1usize
        i += 1usize
    }
    // `starts[b]` is now the end of bucket b, which is where bucket b + 1 starts.
    b = buckets
    while b > 0usize {
        starts[b] = starts[b - 1usize]
        b -= 1usize
    }
    starts[0usize] = 0usize
    b = 0usize
    while b < buckets {
        i = starts[b] + 1usize
        while i < starts[b + 1usize] {
            let held = scratch[i]
            let held_key = key(ctx, held)
            var j = i
            while j > starts[b] && key(ctx, scratch[j - 1usize]) > held_key {
                scratch[j] = scratch[j - 1usize]
                j -= 1usize
            }
            scratch[j] = held
            i += 1usize
        }
        b += 1usize
    }
    i = 0usize
    while i < n {
        items[i] = scratch[i]
        i += 1usize
    }
    ret ok
}

// LSD radix sort of fixed-width byte rows: `rows` holds `rows.len / width` rows of
// `width` bytes, ordered lexicographically by their first `key_width` bytes; one
// counting pass per key byte from the last to the first. Stable, so the bytes past
// the key keep their input order among equal keys. `scratch` needs `rows.len`.
fn radix_bytes(rows: []u8, width: usize, key_width: usize, scratch: []u8) -> err {
    if width == 0usize || key_width > width || rows.len % width != 0usize { ret Invalid }
    if scratch.len < rows.len { ret TooSmall }
    let n = rows.len / width
    var counts: [256]usize = zero
    var column = key_width
    while column > 0usize {
        column -= 1usize
        var b = 0usize
        while b < 256usize {
            counts[b] = 0usize
            b += 1usize
        }
        var r = 0usize
        while r < n {
            counts[usize(rows[r * width + column])] += 1usize
            r += 1usize
        }
        var running = 0usize
        b = 0usize
        while b < 256usize {
            let held = counts[b]
            counts[b] = running
            running += held
            b += 1usize
        }
        r = 0usize
        while r < n {
            let slot = counts[usize(rows[r * width + column])]
            counts[usize(rows[r * width + column])] += 1usize
            var c = 0usize
            while c < width {
                scratch[slot * width + c] = rows[r * width + c]
                c += 1usize
            }
            r += 1usize
        }
        r = 0usize
        while r < rows.len {
            rows[r] = scratch[r]
            r += 1usize
        }
    }
    ret ok
}

// The k-way merge of `bounds.len - 1` sorted runs held back to back in `runs`, run
// `i` being `runs[bounds[i]..bounds[i + 1]]`, through a min-heap of run indices
// (`run_heap` and `cursor`, one slot per run) into `out` (`runs.len` slots). Ties go
// to the earlier run, so the result is the stable sort of what the runs held. This
// is the in-memory model of external merge sort.
// ponytail: the I/O layer (run formation into files, one buffered reader per run,
// a writer for `out`) is the caller's; nothing here touches e.io.
fn external_merge[T: type](runs: []const T, bounds: []const usize, cursor: []usize, run_heap: []usize, out: []T) -> err {
    if bounds.len < 1usize { ret Invalid }
    let k = bounds.len - 1usize
    if cursor.len < k || run_heap.len < k || out.len < runs.len { ret TooSmall }
    if bounds[k] > runs.len { ret Invalid }
    var size = 0usize
    var r = 0usize
    while r < k {
        if bounds[r] > bounds[r + 1usize] { ret Invalid }
        cursor[r] = bounds[r]
        if bounds[r] < bounds[r + 1usize] {
            // Sift up under (key, run) order.
            var node = size
            run_heap[node] = r
            size += 1usize
            while node > 0usize {
                let parent = (node - 1usize) / 2usize
                let order = T.cmp(runs[cursor[run_heap[node]]], runs[cursor[run_heap[parent]]])
                if order > 0i32 || (order == 0i32 && run_heap[node] > run_heap[parent]) { break }
                let carried = run_heap[parent]
                run_heap[parent] = run_heap[node]
                run_heap[node] = carried
                node = parent
            }
        }
        r += 1usize
    }
    var written = 0usize
    while size > 0usize {
        let top = run_heap[0usize]
        out[written] = runs[cursor[top]]
        written += 1usize
        cursor[top] += 1usize
        if cursor[top] == bounds[top + 1usize] {
            size -= 1usize
            run_heap[0usize] = run_heap[size]
        }
        var node = 0usize
        while true {
            let left = node * 2usize + 1usize
            if left >= size { break }
            var smallest = left
            let right = left + 1usize
            if right < size {
                let order = T.cmp(runs[cursor[run_heap[right]]], runs[cursor[run_heap[left]]])
                if order < 0i32 || (order == 0i32 && run_heap[right] < run_heap[left]) { smallest = right }
            }
            let order = T.cmp(runs[cursor[run_heap[smallest]]], runs[cursor[run_heap[node]]])
            if order > 0i32 || (order == 0i32 && run_heap[smallest] > run_heap[node]) { break }
            let carried = run_heap[node]
            run_heap[node] = run_heap[smallest]
            run_heap[smallest] = carried
            node = smallest
        }
    }
    ret ok
}

// Three-way string quicksort (Bentley-Sedgewick MSD radix): partition on the byte
// at `depth`, a string that ends before `depth` sorting first, and recurse into the
// equal band one byte deeper. Byte order, so ASCII and UTF-8 code point order.
fn strings(items: []str) { strings_from(items, 0usize) }

fn strings_from(items: []str, depth: usize) {
    if items.len < 2usize { ret }
    let middle = items[items.len / 2usize]
    var pivot = 0i32 - 1i32
    if middle.len > depth { pivot = i32(middle[depth]) }
    var lt = 0usize
    var gt = items.len
    var i = 0usize
    while i < gt {
        var c = 0i32 - 1i32
        let current = items[i]
        if current.len > depth { c = i32(current[depth]) }
        if c < pivot {
            let carried = items[lt]
            items[lt] = items[i]
            items[i] = carried
            lt += 1usize
            i += 1usize
        } else {
            if c > pivot {
                gt -= 1usize
                let carried = items[gt]
                items[gt] = items[i]
                items[i] = carried
            } else {
                i += 1usize
            }
        }
    }
    strings_from(items[..lt], depth)
    if pivot >= 0i32 { strings_from(items[lt..gt], depth + 1usize) }
    strings_from(items[gt..items.len], depth)
}
