// Counters, gauges and histograms that any thread may touch: every field is an
// `Atomic` and every update one atomic instruction, relaxed, since a metric is read
// as a whole by a snapshot and never used to order other memory. A histogram's sum is
// an `f64` kept as its bits in an `Atomic[u64]`, added under a compare-and-swap loop.

use e.atomic
use e.mem
use e.math

type Counter = struct { value: Atomic[u64] }
type Gauge = struct { value: Atomic[i64] }
type Histogram = struct { bounds: []const f64, counts: []Atomic[u64], sum_bits: Atomic[u64] }
type Snapshot = struct { count: u64, sum: f64, buckets: []const u64 }
error Invalid

fn counter() -> Counter {
    var c: Counter = zero
    c.value = atomic.init(0u64)
    ret c
}

fn counter_add(c: *Counter, value: u64) {
    let previous = atomic.add(&c.value, value, .Relaxed)
    if previous > previous { ret }
}

fn counter_get(c: *Counter) -> u64 { ret atomic.load(&c.value, .Relaxed) }

fn gauge() -> Gauge {
    var g: Gauge = zero
    g.value = atomic.init(0i64)
    ret g
}

fn gauge_set(g: *Gauge, value: i64) { atomic.store(&g.value, value, .Relaxed) }

fn gauge_add(g: *Gauge, value: i64) {
    let previous = atomic.add(&g.value, value, .Relaxed)
    if previous > previous { ret }
}

fn gauge_get(g: *Gauge) -> i64 { ret atomic.load(&g.value, .Relaxed) }

// `bounds` are the upper edges of the buckets, finite and strictly increasing; the
// last bucket, for everything above the last bound, is implicit.
fn histogram(a: *mem.Arena, bounds: []const f64) -> (Histogram, err) {
    var at = 0usize
    while at < bounds.len {
        let b = bounds[at]
        if !(b == b) || math.abs[f64](b) == mem.bitcast[f64](9218868437227405312u64) { ret (zero, Invalid) }
        if at > 0usize && !(bounds[at - 1usize] < b) { ret (zero, Invalid) }
        at += 1usize
    }
    let (counts, counts_error) = mem.alloc[Atomic[u64]](a, bounds.len + 1usize)
    if counts_error != ok { ret (zero, counts_error) }
    at = 0usize
    while at < counts.len {
        counts[at] = atomic.init(0u64)
        at += 1usize
    }
    var h: Histogram = zero
    h.bounds = bounds
    h.counts = counts
    h.sum_bits = atomic.init(0u64)
    ret (h, ok)
}

fn histogram_observe(h: *Histogram, value: f64) {
    // The first bucket whose bound is not below the value, by binary search.
    var low = 0usize
    var high = h.bounds.len
    while low < high {
        let mid = (low + high) / 2usize
        if h.bounds[mid] < value { low = mid + 1usize } else { high = mid }
    }
    let previous = atomic.add(&h.counts[low], 1u64, .Relaxed)
    if previous > previous { ret }
    while true {
        let current = atomic.load(&h.sum_bits, .Relaxed)
        let next = mem.bitcast[u64](mem.bitcast[f64](current) + value)
        let (swapped, _) = atomic.cas(&h.sum_bits, current, next, .Relaxed, .Relaxed)
        if swapped { break }
    }
}

// Cumulative bucket counts, the way a histogram is reported: bucket `i` holds every
// observation at or below `bounds[i]`, and the last holds them all.
fn histogram_snapshot(a: *mem.Arena, h: *const Histogram) -> (Snapshot, err) {
    // An atomic load takes the mutable pointer; a snapshot writes nothing through it.
    let live = mem.cast[*Histogram](h)
    let (buckets, buckets_error) = mem.alloc[u64](a, live.counts.len)
    if buckets_error != ok { ret (zero, buckets_error) }
    var total = 0u64
    var at = 0usize
    while at < live.counts.len {
        total += atomic.load(&live.counts[at], .Relaxed)
        buckets[at] = total
        at += 1usize
    }
    var s: Snapshot = zero
    s.count = total
    s.sum = mem.bitcast[f64](atomic.load(&live.sum_bits, .Relaxed))
    s.buckets = buckets[0..]
    ret (s, ok)
}
