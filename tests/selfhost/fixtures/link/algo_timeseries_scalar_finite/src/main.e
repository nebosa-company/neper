// Scalar inventory models must reject NaN and infinity rather than allowing
// ordered comparisons to silently pass and returning a non-finite answer.
use e.algo.timeseries
use e.mem
use e.os

fn nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }
fn infinity() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

fn main() {
    let bad = nan()
    let inf = infinity()
    let (_, e1) = timeseries.eoq(bad, 1.0f64, 1.0f64)
    let (_, e2) = timeseries.eoq(1.0f64, inf, 1.0f64)
    let (_, e3) = timeseries.eoq_total(1.0f64, 1.0f64, 1.0f64, bad)
    let (_, e4) = timeseries.newsvendor_ratio(inf, 1.0f64)
    let (_, e5) = timeseries.newsvendor_ratio(1.0e308f64, 1.0e308f64)
    if e1 != timeseries.Invalid || e2 != timeseries.Invalid || e3 != timeseries.Invalid || e4 != timeseries.Invalid || e5 != timeseries.Invalid { os.exit(1) }

    var demands: [2]f64 = [2]f64{ 10.0f64, 20.0f64 }
    var probs: [2]f64 = [2]f64{ 0.5f64, 0.5f64 }
    let (_, e6) = timeseries.newsvendor_discrete(demands[..], probs[..], bad)
    probs[0usize] = bad
    let (_, e7) = timeseries.newsvendor_discrete(demands[..], probs[..], 0.5f64)
    probs[0usize] = 0.5f64
    demands[1usize] = inf
    let (_, e8) = timeseries.newsvendor_discrete(demands[..], probs[..], 1.0f64)
    if e6 != timeseries.Invalid || e7 != timeseries.Invalid || e8 != timeseries.Invalid { os.exit(2) }
    os.exit(0)
}
