// Streaming statistics: Welford's running moments, merged by Chan's formula, and a
// bivariate accumulator for a least-squares line and Pearson's correlation. Every
// answer that divides by a count or a spread says `false` when there is not enough
// data for it.

use e.math

type Moments = struct { count: u64, mean: f64, m2: f64, min: f64, max: f64 }
type Regression = struct { count: u64, mean_x: f64, mean_y: f64, m2_x: f64, m2_y: f64, cov: f64 }

fn moments() -> Moments {
    var s: Moments = zero
    ret s
}

fn moments_add(s: *Moments, x: f64) {
    if s.count == 0u64 {
        s.min = x
        s.max = x
    } else {
        if x < s.min { s.min = x }
        if x > s.max { s.max = x }
    }
    s.count += 1u64
    let delta = x - s.mean
    s.mean = s.mean + delta / f64(s.count)
    s.m2 = s.m2 + delta * (x - s.mean)
}

fn moments_merge(dst: *Moments, src: *const Moments) {
    if src.count == 0u64 { ret }
    if dst.count == 0u64 {
        dst.count = src.count
        dst.mean = src.mean
        dst.m2 = src.m2
        dst.min = src.min
        dst.max = src.max
        ret
    }
    let total = dst.count + src.count
    let delta = src.mean - dst.mean
    dst.mean = dst.mean + delta * f64(src.count) / f64(total)
    dst.m2 = dst.m2 + src.m2 + delta * delta * f64(dst.count) * f64(src.count) / f64(total)
    if src.min < dst.min { dst.min = src.min }
    if src.max > dst.max { dst.max = src.max }
    dst.count = total
}

fn variance_population(s: *const Moments) -> (f64, bool) {
    if s.count == 0u64 { ret (0.0, false) }
    ret (s.m2 / f64(s.count), true)
}

fn variance_sample(s: *const Moments) -> (f64, bool) {
    if s.count < 2u64 { ret (0.0, false) }
    ret (s.m2 / f64(s.count - 1u64), true)
}

fn standard_deviation_population(s: *const Moments) -> (f64, bool) {
    let (variance, has_variance) = variance_population(s)
    if !has_variance { ret (0.0, false) }
    ret (math.sqrt[f64](variance), true)
}

fn standard_deviation_sample(s: *const Moments) -> (f64, bool) {
    let (variance, has_variance) = variance_sample(s)
    if !has_variance { ret (0.0, false) }
    ret (math.sqrt[f64](variance), true)
}

fn regression() -> Regression {
    var s: Regression = zero
    ret s
}

fn regression_add(s: *Regression, x: f64, y: f64) {
    s.count += 1u64
    let n = f64(s.count)
    let delta_x = x - s.mean_x
    let delta_y = y - s.mean_y
    s.mean_x = s.mean_x + delta_x / n
    s.mean_y = s.mean_y + delta_y / n
    s.m2_x = s.m2_x + delta_x * (x - s.mean_x)
    s.m2_y = s.m2_y + delta_y * (y - s.mean_y)
    s.cov = s.cov + delta_x * (y - s.mean_y)
}

// The least-squares line needs two points and some spread in x.
fn regression_slope(s: *const Regression) -> (f64, bool) {
    if s.count < 2u64 || s.m2_x == 0.0 { ret (0.0, false) }
    ret (s.cov / s.m2_x, true)
}

fn regression_intercept(s: *const Regression) -> (f64, bool) {
    let (slope, has_slope) = regression_slope(s)
    if !has_slope { ret (0.0, false) }
    ret (s.mean_y - slope * s.mean_x, true)
}

fn correlation(s: *const Regression) -> (f64, bool) {
    if s.count < 2u64 || s.m2_x == 0.0 || s.m2_y == 0.0 { ret (0.0, false) }
    ret (s.cov / math.sqrt[f64](s.m2_x * s.m2_y), true)
}
