// `e.metrics`: a counter, a gauge, and a histogram's cumulative buckets and sum,
// with bounds refused unless finite and increasing and the implicit last bucket.
// Every check has its own exit code.
use e.os
use e.mem
use e.metrics as metrics

fn main(a: *mem.Arena, args: []str) -> err {
    var c = metrics.counter()
    metrics.counter_add(&c, 5u64)
    metrics.counter_add(&c, 7u64)
    if metrics.counter_get(&c) != 12u64 { os.exit(1) }
    var g = metrics.gauge()
    metrics.gauge_set(&g, -3i64)
    metrics.gauge_add(&g, 10i64)
    if metrics.gauge_get(&g) != 7i64 { os.exit(2) }
    let bounds: [3]f64 = [3]f64{ 1.0, 5.0, 10.0 }
    let (h0, e1) = metrics.histogram(a, bounds[0..])
    if e1 != ok { os.exit(3) }
    var h = h0
    metrics.histogram_observe(&h, 0.5)
    metrics.histogram_observe(&h, 1.0)
    metrics.histogram_observe(&h, 3.0)
    metrics.histogram_observe(&h, 10.0)
    metrics.histogram_observe(&h, 11.0)
    let (s, e2) = metrics.histogram_snapshot(a, &h)
    if e2 != ok || s.count != 5u64 || s.sum != 25.5 || s.buckets.len != 4usize { os.exit(4) }
    if s.buckets[0] != 2u64 || s.buckets[1] != 3u64 || s.buckets[2] != 4u64 || s.buckets[3] != 5u64 { os.exit(5) }
    let bad: [2]f64 = [2]f64{ 5.0, 1.0 }
    let (_, e3) = metrics.histogram(a, bad[0..])
    let inf: [1]f64 = [1]f64{ mem.bitcast[f64](9218868437227405312u64) }
    let (_, e4) = metrics.histogram(a, inf[0..])
    if e3 != metrics.Invalid || e4 != metrics.Invalid { os.exit(6) }
    let none: [0]f64 = zero
    let (h1, e5) = metrics.histogram(a, none[0..])
    var only = h1
    metrics.histogram_observe(&only, 42.0)
    let (s1, _) = metrics.histogram_snapshot(a, &only)
    if e5 != ok || s1.buckets.len != 1usize || s1.buckets[0] != 1u64 || s1.sum != 42.0 { os.exit(7) }
    os.exit(0)
    ret ok
}
