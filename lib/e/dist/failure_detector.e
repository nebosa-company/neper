// The phi accrual failure detector (Hayashibara et al.): a ring of the last
// inter-arrival times between heartbeats in a caller `[]u64`, and at any
// `now` the suspicion level phi = -log10(P(next heartbeat is later than
// now)), with the wait modelled as normal over the window's mean and standard
// deviation (`e.math.special.normal_cdf`, the exact form rather than the
// exponential shortcut). phi 1 means a 10% chance the node is merely late,
// phi 8 one in 10^8; `suspect` compares against the caller's threshold.
// `min_std_dev` keeps a very regular heartbeat from making phi explode on a
// tiny delay: the calibration knob, in the caller's time unit.

use e.math
use e.math.special

type Detector = struct { intervals: []u64, count: usize, head: usize, last: u64, seen: bool, min_std_dev: f64 }

fn detector(intervals: []u64, min_std_dev: f64) -> Detector {
    ret Detector { intervals: intervals, count: 0usize, head: 0usize, last: 0u64, seen: false, min_std_dev: min_std_dev }
}

// A heartbeat arrived at `now`; the first only starts the clock.
fn heartbeat(d: *Detector, now: u64) {
    if d.seen && d.intervals.len > 0usize {
        var gap = 0u64
        if now > d.last { gap = now - d.last }
        d.intervals[d.head] = gap
        d.head = (d.head + 1usize) % d.intervals.len
        if d.count < d.intervals.len { d.count += 1usize }
    }
    d.seen = true
    d.last = now
}

// (mean, standard deviation) of the window; the deviation is floored at `min_std_dev`.
fn stats(d: *const Detector) -> (f64, f64) {
    if d.count == 0usize { ret (0.0f64, d.min_std_dev) }
    var sum = 0.0f64
    var i = 0usize
    while i < d.count {
        sum += f64(d.intervals[i])
        i += 1usize
    }
    let mean = sum / f64(d.count)
    var sq = 0.0f64
    i = 0usize
    while i < d.count {
        let dx = f64(d.intervals[i]) - mean
        sq += dx * dx
        i += 1usize
    }
    var sd = math.sqrt[f64](sq / f64(d.count))
    if sd < d.min_std_dev { sd = d.min_std_dev }
    ret (mean, sd)
}

// The suspicion level at `now`; 0 before two heartbeats have fixed an interval.
fn phi(d: *const Detector, now: u64) -> f64 {
    if d.count == 0usize || !d.seen { ret 0.0f64 }
    var t = 0.0f64
    if now > d.last { t = f64(now - d.last) }
    let (mean, sd) = stats(d)
    let z = (t - mean) / sd
    // P(wait > t) = 1 - F(t) = F(-z), via erfc so the tail keeps its digits.
    var tail = special.normal_cdf(0.0f64 - z)
    if tail < 1.0e-300f64 { tail = 1.0e-300f64 }
    ret 0.0f64 - math.log10[f64](tail)
}

fn suspect(d: *const Detector, now: u64, threshold: f64) -> bool { ret phi(d, now) >= threshold }
