// Time-series tools over `f64` in caller storage: Holt-Winters additive
// forecasting, a seasonal-trend decomposition with LOESS smoothing (STL in
// its plain form: a LOESS trend, phase means for the season, two passes),
// the CUSUM and Page-Hinkley change detectors and ADWIN drift detection as
// streaming states, GARCH(1,1) likelihood, fitting (Nelder-Mead over the
// three parameters) and variance forecasts, and the Hawkes self-exciting
// process (intensity, log likelihood, simulation by thinning).

use e.algo.rand
use e.math
use e.math.opt

type Cusum = struct { centre: f64, drift: f64, threshold: f64, high: f64, low: f64 }
type PageHinkley = struct { delta: f64, threshold: f64, count: u64, mean: f64, sum: f64, least: f64 }
type Adwin = struct { values: []f64, head: usize, count: usize, delta: f64 }
type GarchFit = struct { returns: []const f64 }
error TooSmall
error Invalid

// Additive Holt-Winters: seasonal `period`, smoothing `alpha` (level),
// `beta` (trend), `gamma` (season); the first two periods initialise the
// state. `forecast` receives `horizon` values past the series;
// `season.len >= period`. Answers the final level and trend.
fn holt_winters(series: []const f64, period: usize, alpha: f64, beta: f64, gamma: f64, horizon: usize, forecast: []f64, season: []f64) -> (f64, f64, err) {
    if period == 0usize || series.len < 2usize * period { ret (0.0f64, 0.0f64, Invalid) }
    if forecast.len < horizon || season.len < period { ret (0.0f64, 0.0f64, TooSmall) }
    var first = 0.0f64
    var second = 0.0f64
    var i = 0usize
    while i < period {
        first += series[i] / f64(period)
        second += series[period + i] / f64(period)
        i += 1usize
    }
    var level = first
    var trend = (second - first) / f64(period)
    i = 0usize
    while i < period {
        season[i] = series[i] - first
        i += 1usize
    }
    var t = period
    while t < series.len {
        let s = t % period
        let previous_level = level
        level = alpha * (series[t] - season[s]) + (1.0f64 - alpha) * (level + trend)
        trend = beta * (level - previous_level) + (1.0f64 - beta) * trend
        season[s] = gamma * (series[t] - level) + (1.0f64 - gamma) * season[s]
        t += 1usize
    }
    var h = 0usize
    while h < horizon {
        forecast[h] = level + f64(h + 1usize) * trend + season[(series.len + h) % period]
        h += 1usize
    }
    ret (level, trend, ok)
}

// LOESS: `out[i]` is the local linear fit at `i` over the `window` nearest
// points with tricube weights (window at least 3).
fn loess(series: []const f64, window: usize, out: []f64) -> err {
    let n = series.len
    if out.len < n { ret TooSmall }
    if window < 3usize || window > n { ret Invalid }
    var i = 0usize
    while i < n {
        var start = 0usize
        if i > window / 2usize { start = i - window / 2usize }
        if start + window > n { start = n - window }
        let radius = f64(window) / 2.0f64
        var sw = 0.0f64
        var sx = 0.0f64
        var sy = 0.0f64
        var sxx = 0.0f64
        var sxy = 0.0f64
        var j = start
        while j < start + window {
            var d = (f64(j) - f64(i)) / radius
            if d < 0.0f64 { d = 0.0f64 - d }
            var w = 0.0f64
            if d < 1.0f64 {
                let c = 1.0f64 - d * d * d
                w = c * c * c
            }
            let x = f64(j) - f64(i)
            sw += w
            sx += w * x
            sy += w * series[j]
            sxx += w * x * x
            sxy += w * x * series[j]
            j += 1usize
        }
        let denominator = sw * sxx - sx * sx
        if denominator != 0.0f64 {
            // The fit at x = 0 is the intercept.
            out[i] = (sxx * sy - sx * sxy) / denominator
        } else if sw > 0.0f64 {
            out[i] = sy / sw
        } else {
            out[i] = series[i]
        }
        i += 1usize
    }
    ret ok
}

// Seasonal-trend decomposition: `trend` by LOESS over `window` points,
// `seasonal` as the centred mean of the detrended series per phase of
// `period`, `remainder` the rest; two passes refine the trend on the
// deseasonalised series. `scratch.len >= n + period`.
fn stl(series: []const f64, period: usize, window: usize, trend: []f64, seasonal: []f64, remainder: []f64, scratch: []f64) -> err {
    let n = series.len
    if trend.len < n || seasonal.len < n || remainder.len < n || scratch.len < n + period { ret TooSmall }
    if period == 0usize || n < 2usize * period { ret Invalid }
    var work = scratch[..n]
    var phase = scratch[n..n + period]
    var i = 0usize
    while i < n {
        work[i] = series[i]
        seasonal[i] = 0.0f64
        i += 1usize
    }
    var pass = 0usize
    while pass < 2usize {
        let trend_error = loess(work, window, trend)
        if trend_error != ok { ret trend_error }
        var p = 0usize
        while p < period {
            phase[p] = 0.0f64
            p += 1usize
        }
        i = 0usize
        while i < n {
            phase[i % period] += (series[i] - trend[i]) / f64((n - 1usize - i % period) / period + 1usize)
            i += 1usize
        }
        var mean = 0.0f64
        p = 0usize
        while p < period {
            mean += phase[p] / f64(period)
            p += 1usize
        }
        i = 0usize
        while i < n {
            seasonal[i] = phase[i % period] - mean
            work[i] = series[i] - seasonal[i]
            i += 1usize
        }
        pass += 1usize
    }
    i = 0usize
    while i < n {
        remainder[i] = series[i] - trend[i] - seasonal[i]
        i += 1usize
    }
    ret ok
}

// Two-sided CUSUM about `centre` with allowance `drift` and alarm at `threshold`.
fn cusum(centre: f64, drift: f64, threshold: f64) -> Cusum { ret Cusum { centre: centre, drift: drift, threshold: threshold, high: 0.0f64, low: 0.0f64 } }

// Feed one value; answers whether an upward or downward shift is flagged
// (the statistics reset after an alarm).
fn cusum_step(c: *Cusum, value: f64) -> bool {
    c.high = math.max[f64](0.0f64, c.high + value - c.centre - c.drift)
    c.low = math.max[f64](0.0f64, c.low + c.centre - value - c.drift)
    if c.high > c.threshold || c.low > c.threshold {
        c.high = 0.0f64
        c.low = 0.0f64
        ret true
    }
    ret false
}

fn page_hinkley(delta: f64, threshold: f64) -> PageHinkley { ret PageHinkley { delta: delta, threshold: threshold, count: 0u64, mean: 0.0f64, sum: 0.0f64, least: 0.0f64 } }

// Feed one value; flags an upward mean change when the cumulative
// deviation rises `threshold` above its minimum (then resets).
fn page_hinkley_step(p: *PageHinkley, value: f64) -> bool {
    p.count += 1u64
    p.mean += (value - p.mean) / f64(p.count)
    p.sum += value - p.mean - p.delta
    if p.sum < p.least { p.least = p.sum }
    if p.sum - p.least > p.threshold {
        p.count = 0u64
        p.mean = 0.0f64
        p.sum = 0.0f64
        p.least = 0.0f64
        ret true
    }
    ret false
}

// ADWIN over a ring of at most `values.len` recent values with confidence `delta`.
fn adwin(values: []f64, delta: f64) -> (Adwin, err) {
    if values.len < 2usize { ret (zero, TooSmall) }
    if delta <= 0.0f64 || delta >= 1.0f64 { ret (zero, Invalid) }
    ret (Adwin { values: values, head: 0usize, count: 0usize, delta: delta }, ok)
}

fn adwin_at(a: *const Adwin, i: usize) -> f64 { ret a.values[(a.head + i) % a.values.len] }

// Feed one value; every split of the window is tested and the oldest part
// dropped when the two means differ by more than the Hoeffding bound.
// Answers whether the window shrank (drift). The ring drops its oldest
// value when full.
fn adwin_step(a: *Adwin, value: f64) -> bool {
    let cap = a.values.len
    if a.count == cap {
        a.head = (a.head + 1usize) % cap
        a.count -= 1usize
    }
    a.values[(a.head + a.count) % cap] = value
    a.count += 1usize
    var drifted = false
    var shrinking = true
    while shrinking && a.count >= 2usize {
        shrinking = false
        var total = 0.0f64
        var i = 0usize
        while i < a.count {
            total += adwin_at(a, i)
            i += 1usize
        }
        var left = 0.0f64
        var cut = 0usize
        i = 1usize
        while i < a.count && cut == 0usize {
            left += adwin_at(a, i - 1usize)
            let n0 = f64(i)
            let n1 = f64(a.count - i)
            let m = 1.0f64 / (1.0f64 / n0 + 1.0f64 / n1)
            let epsilon = math.sqrt[f64](math.log[f64](4.0f64 * f64(a.count) / a.delta) / (2.0f64 * m))
            var difference = left / n0 - (total - left) / n1
            if difference < 0.0f64 { difference = 0.0f64 - difference }
            if difference > epsilon { cut = i }
            i += 1usize
        }
        if cut > 0usize {
            a.head = (a.head + cut) % cap
            a.count -= cut
            drifted = true
            shrinking = true
        }
    }
    ret drifted
}

fn adwin_mean(a: *const Adwin) -> f64 {
    if a.count == 0usize { ret 0.0f64 }
    var total = 0.0f64
    var i = 0usize
    while i < a.count {
        total += adwin_at(a, i)
        i += 1usize
    }
    ret total / f64(a.count)
}

// The GARCH(1,1) Gaussian log likelihood of zero-mean `returns` (variance
// `omega + alpha r² + beta σ²`, starting from the sample variance).
fn garch_log_likelihood(omega: f64, alpha: f64, beta: f64, returns: []const f64) -> f64 {
    if returns.len == 0usize { ret 0.0f64 }
    var variance = 0.0f64
    var i = 0usize
    while i < returns.len {
        variance += returns[i] * returns[i] / f64(returns.len)
        i += 1usize
    }
    var total = 0.0f64
    i = 0usize
    while i < returns.len {
        if i > 0usize { variance = omega + alpha * returns[i - 1usize] * returns[i - 1usize] + beta * variance }
        total -= 0.5f64 * (math.log[f64](6.283185307179586f64 * variance) + returns[i] * returns[i] / variance)
        i += 1usize
    }
    ret total
}

fn garch_objective(fit: *GarchFit, p: []const f64) -> f64 {
    let omega = p[0usize]
    let alpha = p[1usize]
    let beta = p[2usize]
    if omega <= 0.0f64 || alpha < 0.0f64 || beta < 0.0f64 || alpha + beta >= 1.0f64 { ret 1.0e300f64 }
    ret 0.0f64 - garch_log_likelihood(omega, alpha, beta, fit.returns)
}

// Fit (omega, alpha, beta) by Nelder-Mead from the caller's start in `p`,
// maximising the likelihood under `omega > 0`, `alpha, beta >= 0`,
// `alpha + beta < 1`; `scratch.len >= 32`. Answers the log likelihood.
fn garch_fit(returns: []const f64, p: []f64, iterations: u32, scratch: []f64) -> (f64, err) {
    if p.len < 3usize || scratch.len < 32usize { ret (0.0f64, TooSmall) }
    if returns.len < 2usize { ret (0.0f64, Invalid) }
    var fit = GarchFit { returns: returns }
    let (result, run_error) = opt.nelder_mead[GarchFit](&fit, garch_objective, p[..3usize], 0.05f64, 1.0e-12f64, iterations, scratch)
    if run_error != ok { ret (0.0f64, run_error) }
    ret (0.0f64 - result.value, ok)
}

// Variance forecasts `horizon` steps ahead from the last return and
// variance: `σ²_{t+1} = ω + α r² + β σ²`, then the recursion with the
// unconditional expectation of `r²`.
fn garch_forecast(omega: f64, alpha: f64, beta: f64, last_return: f64, last_variance: f64, horizon: usize, out: []f64) -> err {
    if out.len < horizon { ret TooSmall }
    var variance = omega + alpha * last_return * last_return + beta * last_variance
    var h = 0usize
    while h < horizon {
        out[h] = variance
        variance = omega + (alpha + beta) * variance
        h += 1usize
    }
    ret ok
}

// The Hawkes intensity `mu + alpha Σ exp(-beta (t - t_i))` over the events before `t`.
fn hawkes_intensity(mu: f64, alpha: f64, beta: f64, events: []const f64, t: f64) -> f64 {
    var total = mu
    var i = 0usize
    while i < events.len && events[i] < t {
        total += alpha * math.exp[f64](0.0f64 - beta * (t - events[i]))
        i += 1usize
    }
    ret total
}

// The log likelihood of `events` (sorted) on `[0, horizon]`, with the
// recursive form of the excitation sum.
fn hawkes_log_likelihood(mu: f64, alpha: f64, beta: f64, events: []const f64, horizon: f64) -> f64 {
    var total = 0.0f64
    var excitation = 0.0f64
    var i = 0usize
    while i < events.len {
        if i > 0usize { excitation = math.exp[f64](0.0f64 - beta * (events[i] - events[i - 1usize])) * (excitation + alpha) }
        total += math.log[f64](mu + excitation)
        total -= alpha / beta * (1.0f64 - math.exp[f64](0.0f64 - beta * (horizon - events[i])))
        i += 1usize
    }
    ret total - mu * horizon
}

// Simulate on `[0, horizon)` by Ogata's thinning through the caller's PCG;
// answers the event count into `out` (stopping at its capacity with `TooSmall`).
fn hawkes_simulate(mu: f64, alpha: f64, beta: f64, horizon: f64, r: *rand.Pcg64, out: []f64) -> (usize, err) {
    if mu <= 0.0f64 || beta <= 0.0f64 || alpha < 0.0f64 || alpha >= beta { ret (0usize, Invalid) }
    var count = 0usize
    var t = 0.0f64
    while t < horizon {
        let bound = hawkes_intensity(mu, alpha, beta, out[..count], t) + alpha
        var u = rand.pcg64_f64(r)
        while u == 0.0f64 { u = rand.pcg64_f64(r) }
        t -= math.log[f64](u) / bound
        if t < horizon && rand.pcg64_f64(r) * bound <= hawkes_intensity(mu, alpha, beta, out[..count], t) {
            if count >= out.len { ret (count, TooSmall) }
            out[count] = t
            count += 1usize
        }
    }
    ret (count, ok)
}
