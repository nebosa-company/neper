// A criterion-style benchmark harness over `e.time`: warm the body up, calibrate how many
// iterations make a sample long enough to read, collect `samples` timings (nanoseconds per
// iteration), reject Tukey outliers, and report robust and parametric statistics with a
// confidence interval for the mean. Reports compare: Welch's t over the two kept sample
// sets against a caller-chosen noise threshold, so what counts as a regression is the
// caller's policy (CI thresholds are not decided here).
//
// `run` measures; everything after it is pure and works on any `[]f64` of per-iteration
// times, which is how the fixtures pin the numbers and the report schema without timing.
// A sample set is sorted in place. Sorting is a shell sort: sample counts are in the
// hundreds, not millions.

use e.math
use e.str
use e.time

type Config = struct { warmup_ns: i64, target_sample_ns: i64, max_iters: u64, fence_x10: u32 }
type Stats = struct { count: usize, kept: usize, mean: f64, median: f64, stddev: f64, min: f64, max: f64, q1: f64, q3: f64, mad: f64, std_err: f64, ci_low: f64, ci_high: f64, low_mild: usize, low_severe: usize, high_mild: usize, high_severe: usize }
type Report = struct { name: str, iters: u64, stats: Stats }
type Verdict = enum u8 { Improved, Regressed, NoChange }
type Comparison = struct { change_pct: f64, t: f64, significant: bool, verdict: Verdict }
error TooFew
error TooSmall

// 100 ms of warm-up, samples of about 1 ms, at most 2**32 iterations per sample, and
// the usual 1.5 interquartile-range fence for rejection.
fn config_default() -> Config {
    ret Config { warmup_ns: 100000000i64, target_sample_ns: 1000000i64, max_iters: 4294967296u64, fence_x10: 15u32 }
}

// Ascending shell sort in place.
fn sort(values: []f64) {
    var gap = values.len / 2usize
    while gap > 0usize {
        var i = gap
        while i < values.len {
            let v = values[i]
            var j = i
            while j >= gap && values[j - gap] > v {
                values[j] = values[j - gap]
                j -= gap
            }
            values[j] = v
            i += 1usize
        }
        gap = gap / 2usize
    }
}

// The p-quantile of ascending values by linear interpolation between order statistics
// (the "R-7" definition: position p * (n - 1)); 0 for an empty slice.
fn quantile(sorted: []const f64, p: f64) -> f64 {
    if sorted.len == 0usize { ret 0.0f64 }
    if sorted.len == 1usize { ret sorted[0] }
    let position = p * f64(sorted.len - 1usize)
    let lower = usize(position)
    if lower >= sorted.len - 1usize { ret sorted[sorted.len - 1usize] }
    let fraction = position - f64(lower)
    ret sorted[lower] + fraction * (sorted[lower + 1usize] - sorted[lower])
}

// The two-sided 95% Student t critical values for 1 to 30 degrees of freedom.
fn t_table() -> str {
    ret "12.706,4.303,3.182,2.776,2.571,2.447,2.365,2.306,2.262,2.228,2.201,2.179,2.160,2.145,2.131,2.120,2.110,2.101,2.093,2.086,2.080,2.074,2.069,2.064,2.060,2.056,2.052,2.048,2.045,2.042"
}

// Two-sided 95% Student t critical value for `df` degrees of freedom: the table to 30,
// then the normal 1.96, which it is within 4% of (t at 31 is 2.040).
fn t_critical(df: usize) -> f64 {
    if df == 0usize { ret 0.0f64 }
    if df > 30usize { ret 1.96f64 }
    let table = t_table()
    var start = 0usize
    var index = 1usize
    var i = 0usize
    while i < table.len {
        if table[i] == 44u8 {
            if index == df {
                let (v, e) = str.parse_f64(table[start..i])
                ret v
            }
            index += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    let (last, le) = str.parse_f64(table[start..])
    ret last
}
// Statistics of `samples` (sorted in place): quartiles over all of them, the outlier
// classification (mild beyond `fence` times the IQR, severe beyond twice that), then
// mean, deviation and the interval over the values inside the fence. `median`, `mad`
// and `min`/`max` are of the kept values as well. `TooFew` under two samples.
fn summarize(samples: []f64, fence_x10: u32) -> (Stats, err) {
    var s: Stats = zero
    if samples.len < 2usize { ret (s, TooFew) }
    sort(samples)
    s.count = samples.len
    s.q1 = quantile(samples, 0.25f64)
    s.q3 = quantile(samples, 0.75f64)
    let iqr = s.q3 - s.q1
    let fence = f64(fence_x10) / 10.0f64
    let mild_low = s.q1 - fence * iqr
    let mild_high = s.q3 + fence * iqr
    let severe_low = s.q1 - 2.0f64 * fence * iqr
    let severe_high = s.q3 + 2.0f64 * fence * iqr
    var first = 0usize
    var last = samples.len
    var i = 0usize
    while i < samples.len {
        let v = samples[i]
        if v < severe_low {
            s.low_severe += 1usize
        } else if v < mild_low {
            s.low_mild += 1usize
        } else if v > severe_high {
            s.high_severe += 1usize
        } else if v > mild_high {
            s.high_mild += 1usize
        }
        i += 1usize
    }
    // Kept values are the contiguous run inside the mild fences (the slice is sorted).
    while first < last && samples[first] < mild_low { first += 1usize }
    while last > first && samples[last - 1usize] > mild_high { last -= 1usize }
    let kept = samples[first..last]
    s.kept = kept.len
    if kept.len == 0usize { ret (s, TooFew) }
    var sum = 0.0f64
    i = 0usize
    while i < kept.len {
        sum += kept[i]
        i += 1usize
    }
    s.mean = sum / f64(kept.len)
    s.min = kept[0]
    s.max = kept[kept.len - 1usize]
    s.median = quantile(kept, 0.5f64)
    var squares = 0.0f64
    i = 0usize
    while i < kept.len {
        let d = kept[i] - s.mean
        squares += d * d
        i += 1usize
    }
    if kept.len > 1usize {
        s.stddev = math.sqrt[f64](squares / f64(kept.len - 1usize))
    }
    s.std_err = s.stddev / math.sqrt[f64](f64(kept.len))
    let half = t_critical(kept.len - 1usize) * s.std_err
    s.ci_low = s.mean - half
    s.ci_high = s.mean + half
    // Median absolute deviation of the kept values with no scratch: the deviations of a sorted
    // slice from its median are two monotone runs, merged until the middle one is reached.
    var mid = 0usize
    while mid < kept.len && kept[mid] < s.median { mid += 1usize }
    var left = mid
    var right = mid
    var seen = 0usize
    let rank_wanted = kept.len / 2usize + 1usize
    var current = 0.0f64
    var previous = 0.0f64
    while seen < rank_wanted {
        var take_left = false
        if left > 0usize && right < kept.len {
            take_left = s.median - kept[left - 1usize] <= kept[right] - s.median
        } else if left > 0usize {
            take_left = true
        }
        var d = 0.0f64
        if take_left {
            d = s.median - kept[left - 1usize]
            left -= 1usize
        } else {
            d = kept[right] - s.median
            right += 1usize
        }
        previous = current
        current = d
        seen += 1usize
    }
    if kept.len % 2usize == 0usize {
        s.mad = (previous + current) / 2.0f64
    } else {
        s.mad = current
    }
    ret (s, ok)
}

// Welch's t of the change from `base` to `current` over their kept samples, the change
// in the mean as a percentage of the base mean, and a verdict: `Improved` or `Regressed`
// when the t statistic exceeds the critical value and the change is larger than
// `threshold_pct` in magnitude, `NoChange` otherwise.
fn compare(base: Stats, current: Stats, threshold_pct: f64) -> Comparison {
    var c: Comparison = zero
    c.verdict = .NoChange
    if base.mean == 0.0f64 { ret c }
    c.change_pct = (current.mean - base.mean) / base.mean * 100.0f64
    let variance = base.std_err * base.std_err + current.std_err * current.std_err
    if variance > 0.0f64 {
        c.t = (current.mean - base.mean) / math.sqrt[f64](variance)
    }
    var magnitude = c.t
    if magnitude < 0.0f64 { magnitude = 0.0f64 - magnitude }
    var change = c.change_pct
    if change < 0.0f64 { change = 0.0f64 - change }
    c.significant = magnitude > t_critical(base.kept + current.kept - 2usize)
    if c.significant && change > threshold_pct {
        if c.change_pct < 0.0f64 { c.verdict = .Improved } else { c.verdict = .Regressed }
    }
    ret c
}

fn verdict_name(v: Verdict) -> str {
    if v == .Improved { ret "improved" }
    if v == .Regressed { ret "regressed" }
    ret "no change"
}

fn push_number(b: *str.Builder, v: f64) -> err {
    ret str.push_f64_fixed(b, v, 3u8)
}

// The report as one JSON object; the schema is: name, iters, samples, kept, mean, median,
// stddev, min, max, q1, q3, mad, ci_low, ci_high (nanoseconds per iteration, three
// decimals) and `outliers` {low_severe, low_mild, high_mild, high_severe}.
fn render_json(b: *str.Builder, r: Report) -> err {
    try str.push(b, "{\"name\": \"")
    try str.push(b, r.name)
    try str.push(b, "\", \"iters\": ")
    try str.push_u64(b, r.iters)
    try str.push(b, ", \"samples\": ")
    try str.push_usize(b, r.stats.count)
    try str.push(b, ", \"kept\": ")
    try str.push_usize(b, r.stats.kept)
    try str.push(b, ", \"mean\": ")
    try push_number(b, r.stats.mean)
    try str.push(b, ", \"median\": ")
    try push_number(b, r.stats.median)
    try str.push(b, ", \"stddev\": ")
    try push_number(b, r.stats.stddev)
    try str.push(b, ", \"min\": ")
    try push_number(b, r.stats.min)
    try str.push(b, ", \"max\": ")
    try push_number(b, r.stats.max)
    try str.push(b, ", \"q1\": ")
    try push_number(b, r.stats.q1)
    try str.push(b, ", \"q3\": ")
    try push_number(b, r.stats.q3)
    try str.push(b, ", \"mad\": ")
    try push_number(b, r.stats.mad)
    try str.push(b, ", \"ci_low\": ")
    try push_number(b, r.stats.ci_low)
    try str.push(b, ", \"ci_high\": ")
    try push_number(b, r.stats.ci_high)
    try str.push(b, ", \"outliers\": {\"low_severe\": ")
    try str.push_usize(b, r.stats.low_severe)
    try str.push(b, ", \"low_mild\": ")
    try str.push_usize(b, r.stats.low_mild)
    try str.push(b, ", \"high_mild\": ")
    try str.push_usize(b, r.stats.high_mild)
    try str.push(b, ", \"high_severe\": ")
    try str.push_usize(b, r.stats.high_severe)
    try str.push(b, "}}")
    ret ok
}

// A criterion-like text block: name, time interval, spread and outlier counts.
fn render_text(b: *str.Builder, r: Report) -> err {
    try str.push(b, r.name)
    try str.push(b, "\n  time:   [")
    try push_number(b, r.stats.ci_low)
    try str.push(b, " ns ")
    try push_number(b, r.stats.mean)
    try str.push(b, " ns ")
    try push_number(b, r.stats.ci_high)
    try str.push(b, " ns]\n  median: ")
    try push_number(b, r.stats.median)
    try str.push(b, " ns (mad ")
    try push_number(b, r.stats.mad)
    try str.push(b, ")\n  stddev: ")
    try push_number(b, r.stats.stddev)
    try str.push(b, " ns over ")
    try str.push_usize(b, r.stats.kept)
    try str.push(b, " of ")
    try str.push_usize(b, r.stats.count)
    try str.push(b, " samples, ")
    try str.push_u64(b, r.iters)
    try str.push(b, " iterations each\n  outliers: ")
    try str.push_usize(b, r.stats.low_severe + r.stats.low_mild + r.stats.high_mild + r.stats.high_severe)
    try str.push(b, " (")
    try str.push_usize(b, r.stats.low_severe)
    try str.push(b, " low severe, ")
    try str.push_usize(b, r.stats.low_mild)
    try str.push(b, " low mild, ")
    try str.push_usize(b, r.stats.high_mild)
    try str.push(b, " high mild, ")
    try str.push_usize(b, r.stats.high_severe)
    try str.push(b, " high severe)\n")
    ret ok
}

fn render_comparison(b: *str.Builder, name: str, c: Comparison) -> err {
    try str.push(b, name)
    try str.push(b, ": ")
    try str.push(b, verdict_name(c.verdict))
    try str.push(b, " (")
    try str.push_f64_fixed(b, c.change_pct, 2u8)
    try str.push(b, "%, t = ")
    try str.push_f64_fixed(b, c.t, 2u8)
    try str.push(b, ")\n")
    ret ok
}

// Time `iters` calls of `body`, in nanoseconds.
fn time_batch[Ctx: type](ctx: *Ctx, body: fn(*Ctx), iters: u64) -> (f64, err) {
    let (start, se) = time.monotonic()
    if se != ok { ret (0.0f64, se) }
    var i = 0u64
    while i < iters {
        body(ctx)
        i += 1u64
    }
    let (end, ee) = time.monotonic()
    if ee != ok { ret (0.0f64, ee) }
    ret (f64(time.instant_diff(end, start).nanos), ok)
}

// Warm `body` up for the configured time while doubling the batch, then pick the
// iteration count whose batch lasts about `target_sample_ns`.
fn calibrate[Ctx: type](ctx: *Ctx, body: fn(*Ctx), cfg: Config) -> (u64, err) {
    var iters = 1u64
    var spent = 0.0f64
    var per_iter = 1.0f64
    while spent < f64(cfg.warmup_ns) {
        let (elapsed, te) = time_batch[Ctx](ctx, body, iters)
        if te != ok { ret (1u64, te) }
        spent += elapsed
        if elapsed > 0.0f64 { per_iter = elapsed / f64(iters) }
        if iters < cfg.max_iters { iters = iters * 2u64 }
    }
    var wanted = f64(cfg.target_sample_ns) / per_iter
    if wanted < 1.0f64 { wanted = 1.0f64 }
    var n = u64(wanted)
    if n > cfg.max_iters { n = cfg.max_iters }
    ret (n, ok)
}

// Measure `body` into `samples` (one per-iteration time in nanoseconds each) and
// summarize it. `samples` must hold at least two values.
fn run[Ctx: type](name: str, cfg: Config, ctx: *Ctx, body: fn(*Ctx), samples: []f64) -> (Report, err) {
    var r: Report = zero
    r.name = name
    if samples.len < 2usize { ret (r, TooFew) }
    let (iters, ce) = calibrate[Ctx](ctx, body, cfg)
    if ce != ok { ret (r, ce) }
    r.iters = iters
    var i = 0usize
    while i < samples.len {
        let (elapsed, te) = time_batch[Ctx](ctx, body, iters)
        if te != ok { ret (r, te) }
        samples[i] = elapsed / f64(iters)
        i += 1usize
    }
    let (stats, se) = summarize(samples, cfg.fence_x10)
    r.stats = stats
    ret (r, se)
}
