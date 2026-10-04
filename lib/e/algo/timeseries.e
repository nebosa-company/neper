// Time-series tools over `f64` in caller storage: Holt-Winters additive
// forecasting, a seasonal-trend decomposition with LOESS smoothing (STL in
// its plain form: a LOESS trend, phase means for the season, two passes),
// the CUSUM and Page-Hinkley change detectors and ADWIN drift detection as
// streaming states, GARCH(1,1) likelihood, fitting (Nelder-Mead over the
// three parameters) and variance forecasts, and the Hawkes self-exciting
// process (intensity, log likelihood, simulation by thinning).
//
// Multivariate and structural coverage: VAR(p) estimation by equation-wise
// ordinary least squares with multi-step forecasts, the VAR(p) companion
// state-space form for `e.math.filter`'s Kalman, and the local-level and
// local-linear-trend structural models run through that same Kalman.

use e.algo.rand
use e.math
use e.math.filter
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

// The two below are D885: the planned names for the recursions the likelihoods
// run, answered as paths the caller can inspect.

// The GARCH(1,1) conditional variance path: `out[i]` is the variance of
// `returns[i]`, `omega + alpha r^2_{i-1} + beta out[i-1]` from the sample
// variance, which is what `garch_log_likelihood` sums over; `garch_fit`
// estimates the parameters and `garch_forecast` continues the path.
fn garch(omega: f64, alpha: f64, beta: f64, returns: []const f64, out: []f64) -> err {
    let n = returns.len
    if out.len < n { ret TooSmall }
    if n == 0usize { ret Invalid }
    var variance = 0.0f64
    var i = 0usize
    while i < n {
        variance += returns[i] * returns[i] / f64(n)
        i += 1usize
    }
    i = 0usize
    while i < n {
        if i > 0usize { variance = omega + alpha * returns[i - 1usize] * returns[i - 1usize] + beta * variance }
        out[i] = variance
        i += 1usize
    }
    ret ok
}

// The exponential Hawkes intensity just before each event of the sorted
// `events`: `out[i] = mu + A_i` with `A_i = exp(-beta (t_i - t_{i-1})) (A_{i-1} + alpha)`,
// the recursion `hawkes_log_likelihood` takes the log of; `hawkes_simulate`
// draws a path by thinning.
fn hawkes(mu: f64, alpha: f64, beta: f64, events: []const f64, out: []f64) -> err {
    if out.len < events.len { ret TooSmall }
    var excitation = 0.0f64
    var i = 0usize
    while i < events.len {
        if i > 0usize { excitation = math.exp[f64](0.0f64 - beta * (events[i] - events[i - 1usize])) * (excitation + alpha) }
        out[i] = mu + excitation
        i += 1usize
    }
    ret ok
}

// Solve the normal equations `a x = b` for symmetric `a` (`n x n`) by
// Gauss-Jordan elimination with partial pivoting over `work`
// (`work.len >= n * (n + 1)`); a pivot under `n` ulps of the largest diagonal
// (never below `1e-300`) is `Invalid`.
fn solve_normal(a: []const f64, b: []const f64, x: []f64, n: usize, work: []f64) -> err {
    if n == 0usize { ret Invalid }
    if a.len < n * n || b.len < n || x.len < n || work.len < n * (n + 1usize) { ret TooSmall }
    var cap = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            work[i * (n + 1usize) + j] = a[i * n + j]
            j += 1usize
        }
        work[i * (n + 1usize) + n] = b[i]
        var diag = a[i * n + i]
        if diag < 0.0f64 { diag = 0.0f64 - diag }
        if diag > cap { cap = diag }
        i += 1usize
    }
    var floor = f64(n) * 2.5e-16f64 * cap
    if floor < 1.0e-300f64 { floor = 1.0e-300f64 }
    var col = 0usize
    while col < n {
        var pivot = col
        var best = work[col * (n + 1usize) + col]
        if best < 0.0f64 { best = 0.0f64 - best }
        var r = col + 1usize
        while r < n {
            var contender = work[r * (n + 1usize) + col]
            if contender < 0.0f64 { contender = 0.0f64 - contender }
            if contender > best {
                pivot = r
                best = contender
            }
            r += 1usize
        }
        if best < floor { ret Invalid }
        if pivot != col {
            var j = col
            while j < n + 1usize {
                let held = work[col * (n + 1usize) + j]
                work[col * (n + 1usize) + j] = work[pivot * (n + 1usize) + j]
                work[pivot * (n + 1usize) + j] = held
                j += 1usize
            }
        }
        let scale = 1.0f64 / work[col * (n + 1usize) + col]
        var j = col
        while j < n + 1usize {
            work[col * (n + 1usize) + j] = work[col * (n + 1usize) + j] * scale
            j += 1usize
        }
        r = 0usize
        while r < n {
            if r != col {
                let factor = work[r * (n + 1usize) + col]
                if factor != 0.0f64 {
                    j = col
                    while j < n + 1usize {
                        work[r * (n + 1usize) + j] -= factor * work[col * (n + 1usize) + j]
                        j += 1usize
                    }
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    i = 0usize
    while i < n {
        x[i] = work[i * (n + 1usize) + n]
        i += 1usize
    }
    ret ok
}

// Fit a VAR(p) over `n` rows of `k` variables (`series` row-major, `n * k`):
// `y(t) = intercept + A1 y(t-1) + ... + Ap y(t-p)`, equation by equation by
// ordinary least squares. `coefs` receives the `p` stacked `k x k` lag blocks
// (`coefs[(lag * k + i) * k + j]` drives variable `i` from variable `j`) and
// `intercept` the `k` constants; `scratch.len >= 2 * m * (m + 1)` with
// `m = 1 + p * k`. Needs at least `m` identified observations past the lags.
fn var_fit(series: []const f64, n: usize, k: usize, p: usize, coefs: []f64, intercept: []f64, scratch: []f64) -> err {
    if k == 0usize || p == 0usize || n == 0usize { ret Invalid }
    if series.len < n * k { ret Invalid }
    if n <= p { ret Invalid }
    let obs = n - p
    let m = 1usize + p * k
    if obs < m { ret Invalid }
    if coefs.len < p * k * k || intercept.len < k { ret TooSmall }
    if scratch.len < 2usize * m * (m + 1usize) { ret TooSmall }
    var xtx = scratch[..m * m]
    var xty = scratch[m * m..m * m + m]
    var work = scratch[m * m + m..2usize * m * (m + 1usize)]
    var eq = 0usize
    while eq < k {
        var a = 0usize
        while a < m * m {
            xtx[a] = 0.0f64
            a += 1usize
        }
        a = 0usize
        while a < m {
            xty[a] = 0.0f64
            a += 1usize
        }
        var t = p
        while t < n {
            var u = 0usize
            while u < m {
                var ru = 1.0f64
                if u > 0usize {
                    let uu = u - 1usize
                    ru = series[(t - 1usize - uu / k) * k + uu % k]
                }
                var v = 0usize
                while v < m {
                    var rv = 1.0f64
                    if v > 0usize {
                        let vv = v - 1usize
                        rv = series[(t - 1usize - vv / k) * k + vv % k]
                    }
                    xtx[u * m + v] += ru * rv
                    v += 1usize
                }
                xty[u] += ru * series[t * k + eq]
                u += 1usize
            }
            t += 1usize
        }
        let fit_error = solve_normal(xtx, xty, xty, m, work)
        if fit_error != ok { ret fit_error }
        intercept[eq] = xty[0usize]
        var lag = 0usize
        while lag < p {
            var j = 0usize
            while j < k {
                coefs[(lag * k + eq) * k + j] = xty[1usize + lag * k + j]
                j += 1usize
            }
            lag += 1usize
        }
        eq += 1usize
    }
    ret ok
}

// Forecast `horizon` rows from the last `p` rows in `history` (oldest first,
// `history.len >= p * k`) under fitted `coefs`/`intercept`, feeding each step
// back in; `out` receives the `horizon` rows (`out.len >= horizon * k`).
fn var_forecast(coefs: []const f64, intercept: []const f64, k: usize, p: usize, history: []const f64, horizon: usize, out: []f64) -> err {
    if k == 0usize || p == 0usize { ret Invalid }
    if coefs.len < p * k * k || intercept.len < k { ret TooSmall }
    if history.len < p * k { ret Invalid }
    if out.len < horizon * k { ret TooSmall }
    var s = 0usize
    while s < horizon {
        var i = 0usize
        while i < k {
            var total = intercept[i]
            var lag = 0usize
            while lag < p {
                var j = 0usize
                while j < k {
                    var prior = 0.0f64
                    if s > lag {
                        prior = out[(s - 1usize - lag) * k + j]
                    } else {
                        prior = history[(p - 1usize - lag + s) * k + j]
                    }
                    total += coefs[(lag * k + i) * k + j] * prior
                    j += 1usize
                }
                lag += 1usize
            }
            out[s * k + i] = total
            i += 1usize
        }
        s += 1usize
    }
    ret ok
}

// The VAR(p) companion state-space form for `e.math.filter`'s Kalman: `f` is
// the `(k * p) x (k * p)` transition (top rows the lag blocks, an identity
// shifting the rest down) and `h` the `k x (k * p)` observation picking the
// first block; `f.len >= (k * p)^2`, `h.len >= k^2 * p`.
fn var_companion(coefs: []const f64, k: usize, p: usize, f: []f64, h: []f64) -> err {
    if k == 0usize || p == 0usize { ret Invalid }
    if coefs.len < p * k * k { ret TooSmall }
    let dim = k * p
    if f.len < dim * dim || h.len < k * dim { ret TooSmall }
    var i = 0usize
    while i < dim * dim {
        f[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k * dim {
        h[i] = 0.0f64
        i += 1usize
    }
    var r = 0usize
    while r < k {
        var c = 0usize
        while c < dim {
            f[r * dim + c] = coefs[((c / k) * k + r) * k + c % k]
            c += 1usize
        }
        r += 1usize
    }
    r = k
    while r < dim {
        f[r * dim + r - k] = 1.0f64
        r += 1usize
    }
    var q = 0usize
    while q < k {
        h[q * dim + q] = 1.0f64
        q += 1usize
    }
    ret ok
}

// The local-level structural model (`level(t) = level(t - 1) + eta`,
// `y(t) = level(t) + eps`) run through `e.math.filter`'s Kalman:
// `filtered[t]` is the posterior level after `observations[t]`;
// `scratch.len >= 18`. A singular update step is `Invalid`.
fn level_filter(observations: []const f64, level_var: f64, obs_var: f64, initial: f64, initial_var: f64, filtered: []f64, scratch: []f64) -> err {
    let n = observations.len
    if n == 0usize { ret Invalid }
    if level_var < 0.0f64 || obs_var <= 0.0f64 || initial_var < 0.0f64 { ret Invalid }
    if filtered.len < n || scratch.len < 18usize { ret TooSmall }
    scratch[0usize] = 1.0f64
    scratch[1usize] = level_var
    scratch[2usize] = 1.0f64
    scratch[3usize] = obs_var
    scratch[4usize] = initial
    scratch[5usize] = initial_var
    var t = 0usize
    while t < n {
        scratch[6usize] = observations[t]
        let predict_error = filter.kalman_predict(scratch[4usize..5usize], scratch[5usize..6usize], scratch[..1usize], scratch[1usize..2usize], 1usize, scratch[7usize..10usize])
        if predict_error != ok { ret predict_error }
        let update_error = filter.kalman_update(scratch[4usize..5usize], scratch[5usize..6usize], scratch[2usize..3usize], scratch[3usize..4usize], scratch[6usize..7usize], 1usize, 1usize, scratch[7usize..18usize])
        if update_error == filter.Singular { ret Invalid }
        if update_error != ok { ret update_error }
        filtered[t] = scratch[4usize]
        t += 1usize
    }
    ret ok
}

// The local-linear-trend structural model (`level` plus `slope`, observed
// with noise) run through `e.math.filter`'s Kalman: `level_out[t]` and
// `trend_out[t]` are the posteriors after `observations[t]`;
// `scratch.len >= 41`. A singular update step is `Invalid`.
fn trend_filter(observations: []const f64, level_var: f64, slope_var: f64, obs_var: f64, initial_level: f64, initial_slope: f64, initial_var: f64, level_out: []f64, trend_out: []f64, scratch: []f64) -> err {
    let n = observations.len
    if n == 0usize { ret Invalid }
    if level_var < 0.0f64 || slope_var < 0.0f64 || obs_var <= 0.0f64 || initial_var < 0.0f64 { ret Invalid }
    if level_out.len < n || trend_out.len < n || scratch.len < 41usize { ret TooSmall }
    scratch[0usize] = 1.0f64
    scratch[1usize] = 1.0f64
    scratch[2usize] = 0.0f64
    scratch[3usize] = 1.0f64
    scratch[4usize] = level_var
    scratch[5usize] = 0.0f64
    scratch[6usize] = 0.0f64
    scratch[7usize] = slope_var
    scratch[8usize] = 1.0f64
    scratch[9usize] = 0.0f64
    scratch[10usize] = obs_var
    scratch[11usize] = initial_level
    scratch[12usize] = initial_slope
    scratch[13usize] = initial_var
    scratch[14usize] = 0.0f64
    scratch[15usize] = 0.0f64
    scratch[16usize] = initial_var
    var t = 0usize
    while t < n {
        scratch[17usize] = observations[t]
        let predict_error = filter.kalman_predict(scratch[11usize..13usize], scratch[13usize..17usize], scratch[..4usize], scratch[4usize..8usize], 2usize, scratch[18usize..28usize])
        if predict_error != ok { ret predict_error }
        let update_error = filter.kalman_update(scratch[11usize..13usize], scratch[13usize..17usize], scratch[8usize..10usize], scratch[10usize..11usize], scratch[17usize..18usize], 2usize, 1usize, scratch[18usize..41usize])
        if update_error == filter.Singular { ret Invalid }
        if update_error != ok { ret update_error }
        level_out[t] = scratch[11usize]
        trend_out[t] = scratch[12usize]
        t += 1usize
    }
    ret ok
}

// The ARMA residual context: `series` observed, `resid` caller workspace
// (`resid.len >= series.len`), `p`/`q` the orders.
type ArmaFit = struct { series: []const f64, resid: []f64, p: usize, q: usize }

// Difference `series` `d` times into `out[..n - d]` (`out.len >= n`,
// `d == 0` copies); answers the effective length `n - d`.
fn arima_difference(series: []const f64, d: usize, out: []f64) -> (usize, err) {
    let n = series.len
    if n == 0usize { ret (0usize, Invalid) }
    if out.len < n { ret (0usize, TooSmall) }
    if d > n { ret (0usize, Invalid) }
    var i = 0usize
    while i < n {
        out[i] = series[i]
        i += 1usize
    }
    var pass = 0usize
    while pass < d {
        i = 0usize
        while i < n - 1usize - pass {
            out[i] = out[i + 1usize] - out[i]
            i += 1usize
        }
        pass += 1usize
    }
    ret (n - d, ok)
}

// Fit an AR(p) with intercept by ordinary least squares over `solve_normal`:
// `coefs` receives the `p` lags, `intercept` its constant;
// `scratch.len >= 2 * m * (m + 1)` with `m = p + 1`. Needs at least `m`
// observations past the lags.
fn ar_fit(series: []const f64, p: usize, coefs: []f64, intercept: []f64, scratch: []f64) -> err {
    let n = series.len
    if p == 0usize || n == 0usize { ret Invalid }
    if n <= p { ret Invalid }
    let obs = n - p
    let m = p + 1usize
    if obs < m { ret Invalid }
    if coefs.len < p || intercept.len < 1usize { ret TooSmall }
    if scratch.len < 2usize * m * (m + 1usize) { ret TooSmall }
    var xtx = scratch[..m * m]
    var xty = scratch[m * m..m * m + m]
    var work = scratch[m * m + m..2usize * m * (m + 1usize)]
    var a = 0usize
    while a < m * m {
        xtx[a] = 0.0f64
        a += 1usize
    }
    a = 0usize
    while a < m {
        xty[a] = 0.0f64
        a += 1usize
    }
    var t = p
    while t < n {
        var u = 0usize
        while u < m {
            var ru = 1.0f64
            if u > 0usize { ru = series[t - u] }
            var v = 0usize
            while v < m {
                var rv = 1.0f64
                if v > 0usize { rv = series[t - v] }
                xtx[u * m + v] += ru * rv
                v += 1usize
            }
            xty[u] += ru * series[t]
            u += 1usize
        }
        t += 1usize
    }
    let fit_error = solve_normal(xtx, xty, xty, m, work)
    if fit_error != ok { ret fit_error }
    intercept[0usize] = xty[0usize]
    var lag = 0usize
    while lag < p {
        coefs[lag] = xty[1usize + lag]
        lag += 1usize
    }
    ret ok
}

// The conditional sum of squared residuals of the ARMA(p, q) with `intercept`
// (pre-sample values and shocks are zero); `resid` is workspace
// (`resid.len >= series.len`).
fn arma_css(series: []const f64, ar: []const f64, ma: []const f64, intercept: f64, resid: []f64) -> (f64, err) {
    let n = series.len
    let p = ar.len
    let q = ma.len
    if n == 0usize { ret (0.0f64, Invalid) }
    if resid.len < n { ret (0.0f64, TooSmall) }
    var total = 0.0f64
    var t = 0usize
    while t < n {
        var fitted = intercept
        var i = 0usize
        while i < p {
            if t > i { fitted += ar[i] * series[t - 1usize - i] }
            i += 1usize
        }
        var j = 0usize
        while j < q {
            if t > j { fitted += ma[j] * resid[t - 1usize - j] }
            j += 1usize
        }
        resid[t] = series[t] - fitted
        total += resid[t] * resid[t]
        t += 1usize
    }
    ret (total, ok)
}

// The `arma_fit` objective over `params = [intercept, ar..., ma...]`; answers
// a large penalty when the residual workspace misbehaves so a derivative-free
// search turns back.
fn arma_objective(fit: *ArmaFit, params: []const f64) -> f64 {
    let (value, css_error) = arma_css(fit.series, params[1usize..1usize + fit.p], params[1usize + fit.p..1usize + fit.p + fit.q], params[0usize], fit.resid)
    if css_error != ok { ret 1.0e300f64 }
    ret value
}

// Fit ARMA(p, q) by Nelder-Mead over the conditional sum of squares:
// `params` holds `p + q + 1` entries, an initial guess in place
// (`[intercept, ar..., ma...]`), and receives the fit;
// `scratch.len >= n + (r + 1)^2 + 4 * r` with `r = p + q + 1` (the first `n`
// cells are the residual workspace). Answers the residual sum.
fn arma_fit(series: []const f64, p: usize, q: usize, params: []f64, scale: f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (f64, err) {
    let n = series.len
    let r = p + q + 1usize
    if n == 0usize { ret (0.0f64, Invalid) }
    if params.len != r { ret (0.0f64, Invalid) }
    if scratch.len < n + (r + 1usize) * (r + 1usize) + 4usize * r { ret (0.0f64, TooSmall) }
    var fit = ArmaFit { series: series, resid: scratch[..n], p: p, q: q }
    let (result, fit_error) = opt.nelder_mead[ArmaFit](&fit, arma_objective, params, scale, tolerance, max_iterations, scratch[n..])
    if fit_error != ok { ret (0.0f64, fit_error) }
    ret (result.value, ok)
}

// Forecast `horizon` steps under AR coefficients `ar`, MA coefficients `ma`
// and `intercept` from the last `past` observations (`past.len >= ar.len`)
// and the last `past_resid` shocks (`past_resid.len >= ma.len`, zero where
// unknown); future shocks are zero. `out.len >= horizon`.
fn arma_forecast(ar: []const f64, ma: []const f64, intercept: f64, past: []const f64, past_resid: []const f64, horizon: usize, out: []f64) -> err {
    let p = ar.len
    let q = ma.len
    if past.len < p || past_resid.len < q { ret Invalid }
    if out.len < horizon { ret TooSmall }
    let base = past.len
    let rbase = past_resid.len
    var s = 0usize
    while s < horizon {
        var total = intercept
        var i = 0usize
        while i < p {
            if s > i {
                total += ar[i] * out[s - 1usize - i]
            } else {
                total += ar[i] * past[base - 1usize - i + s]
            }
            i += 1usize
        }
        var j = 0usize
        while j < q {
            if s <= j { total += ma[j] * past_resid[rbase - 1usize - j + s] }
            j += 1usize
        }
        out[s] = total
        s += 1usize
    }
    ret ok
}

// The economic order quantity `sqrt(2 * demand * order_cost / holding_cost)`.
fn eoq(demand: f64, order_cost: f64, holding_cost: f64) -> (f64, err) {
    if demand <= 0.0f64 || order_cost <= 0.0f64 || holding_cost <= 0.0f64 { ret (0.0f64, Invalid) }
    ret (math.sqrt[f64](2.0f64 * demand * order_cost / holding_cost), ok)
}

// The total cost at `quantity`: `demand / quantity * order_cost` ordering
// plus `quantity / 2 * holding_cost` holding.
fn eoq_total(demand: f64, order_cost: f64, holding_cost: f64, quantity: f64) -> (f64, err) {
    if demand <= 0.0f64 || order_cost <= 0.0f64 || holding_cost <= 0.0f64 || quantity <= 0.0f64 { ret (0.0f64, Invalid) }
    ret (demand / quantity * order_cost + quantity / 2.0f64 * holding_cost, ok)
}

// The newsvendor critical ratio `underage / (underage + overage)`.
fn newsvendor_ratio(underage: f64, overage: f64) -> (f64, err) {
    if underage < 0.0f64 || overage < 0.0f64 || underage + overage <= 0.0f64 { ret (0.0f64, Invalid) }
    ret (underage / (underage + overage), ok)
}

// The smallest of the ascending candidate `demands` whose cumulative `probs`
// reach `ratio` (the last when rounding never reaches it); the two slices
// share their length and `ratio` sits in `[0, 1]`.
fn newsvendor_discrete(demands: []const f64, probs: []const f64, ratio: f64) -> (f64, err) {
    let n = demands.len
    if n == 0usize || probs.len != n { ret (0.0f64, Invalid) }
    if ratio < 0.0f64 || ratio > 1.0f64 { ret (0.0f64, Invalid) }
    var cumulative = 0.0f64
    var i = 0usize
    while i < n {
        if probs[i] < 0.0f64 { ret (0.0f64, Invalid) }
        if i > 0usize && demands[i] < demands[i - 1usize] { ret (0.0f64, Invalid) }
        cumulative += probs[i]
        if cumulative >= ratio { ret (demands[i], ok) }
        i += 1usize
    }
    ret (demands[n - 1usize], ok)
}
