// Streaming statistics: Welford's running moments, merged by Chan's formula, and a
// bivariate accumulator for a least-squares line and Pearson's correlation. Every
// answer that divides by a count or a spread says `false` when there is not enough
// data for it.
//
// Below the accumulators, batch statistics over `[]const f64` samples: a compensated
// mean, the Hyndman-Fan quantiles, sample skewness and kurtosis, Shannon entropy,
// covariance matrices with Ledoit-Wolf shrinkage, Pearson, Spearman and Kendall
// correlations, Gaussian kernel density, bootstrap and jackknife resampling, binomial
// proportion intervals, empirical value at risk and expected shortfall, and
// moment and maximum-likelihood fits of the normal, exponential, gamma and beta
// distributions. Scratch slices are the caller's; a sample said to be `sorted` is
// ascending.

use e.algo.rand
use e.algo.sort
use e.math
use e.math.special

error TooSmall
error Invalid

type Moments = struct { count: u64, mean: f64, m2: f64, min: f64, max: f64 }
type Regression = struct { count: u64, mean_x: f64, mean_y: f64, m2_x: f64, m2_y: f64, cov: f64 }
type RegressionDiagnostic = struct { fitted: f64, residual: f64, leverage: f64, standardized: f64, cook: f64 }
type SurvivalPoint = struct { time: f64, survival: f64, cumulative_hazard: f64, at_risk: usize, events: usize, censored: usize }
type ControlLimits = struct { center: f64, lower: f64, upper: f64 }
type NormalCapability = struct {
    mean: f64, within_sigma: f64, overall_sigma: f64,
    cp: f64, cpk: f64, pp: f64, ppk: f64,
    individuals: ControlLimits, moving_range: ControlLimits,
}
type CapabilityPerformance = struct {
    observed_below_ppm: f64, observed_above_ppm: f64,
    within_below_ppm: f64, within_above_ppm: f64,
    overall_below_ppm: f64, overall_above_ppm: f64,
}
type LognormalCapability = struct {
    log_mean: f64, log_sigma: f64, median: f64,
    pp: f64, ppl: f64, ppu: f64, ppk: f64,
    observed_below_ppm: f64, observed_above_ppm: f64,
    expected_below_ppm: f64, expected_above_ppm: f64,
}
type BinomialCapability = struct {
    defective: u64, inspected: u64, fraction: f64, ppm: f64,
    confidence: Interval, target_fraction: f64, meets_target: bool,
    upper_bound_meets_target: bool, beyond_limits: usize,
}
type BatchCapability = struct {
    batches: usize, batch_size: usize, mean: f64,
    within_sigma: f64, between_sigma: f64, between_within_sigma: f64, overall_sigma: f64,
    cp: f64, cpk: f64, pp: f64, ppk: f64,
    observed_ppm: f64, expected_bw_ppm: f64, expected_overall_ppm: f64,
}
type GageLinearity = struct {
    reference_count: usize, repeats: usize, average_bias: f64,
    intercept: f64, slope: f64, linearity: f64,
    residual_sigma: f64, slope_standard_error: f64, slope_p: f64,
}
type AttributeAgreementRate = struct {
    matched: usize, total: usize, fraction: f64, confidence: Interval,
}
type AttributeAgreement = struct {
    items: usize, appraisers: usize, trials: usize,
    between_matched: usize, all_vs_standard_matched: usize,
    pooled_rating_fraction: f64, pooled_rating_kappa: f64, kappa_defined: bool,
}
type GageRunSummary = struct {
    parts: usize, operators: usize, repeats: usize,
    grand_mean: f64, minimum: f64, maximum: f64, max_repeat_range: f64,
}
type CrossTabSummary = struct { rows: usize, columns: usize, total: u64 }
type ReportAggregate = struct { sum: f64, count: usize }
type SubgroupSpreadKind = enum u8 { Range, StdDev }
type AttributeControlKind = enum u8 { P, Np, C, U }
type AttributeControlPoint = struct { value: f64, center: f64, lower: f64, upper: f64 }
type CusumPoint = struct { high: f64, low: f64, high_signal: bool, low_signal: bool }
type ControlSignal = struct {
    beyond3: bool, same_side9: bool, trend6: bool, alternating14: bool,
    two_of_three2: bool, four_of_five1: bool, within1_15: bool, outside1_8: bool,
}
type AgreementLimits = struct { bias: f64, lower: f64, upper: f64 }
type BinaryPoint = struct { tp: usize, fp: usize }
type BinaryCurve = struct { points: []BinaryPoint, positives: usize, negatives: usize }
type CalibrationBin = struct { count: usize, positives: usize, score_sum: f64 }
type BinaryConfusion = struct { true_negative: usize, false_positive: usize, false_negative: usize, true_positive: usize }

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

// Paired method differences use sample SD; critical is caller-selected.
fn agreement_limits(left: []const f64, right: []const f64, critical: f64) -> (AgreementLimits, bool) {
    if left.len < 2usize || right.len != left.len || critical != critical || critical - critical != 0.0f64 || critical <= 0.0f64 { ret (zero, false) }
    var s = moments()
    var i = 0usize
    while i < left.len {
        let difference = left[i] - right[i]
        if left[i] != left[i] || right[i] != right[i] || difference != difference || difference - difference != 0.0f64 { ret (zero, false) }
        moments_add(&s, difference)
        i += 1usize
    }
    let (sd, defined) = standard_deviation_sample(&s)
    if !defined { ret (zero, false) }
    let lower = s.mean - critical * sd
    let upper = s.mean + critical * sd
    if lower - lower != 0.0f64 || upper - upper != 0.0f64 { ret (zero, false) }
    ret (AgreementLimits { bias: s.mean, lower: lower, upper: upper }, true)
}

// Sort once and advance all equal-score observations at the same threshold.
fn binary_curve(scores: []const f64, positive: []const bool, order: []usize, out: []BinaryPoint) -> (BinaryCurve, err) {
    if scores.len == 0usize || positive.len != scores.len { ret (zero, Invalid) }
    if order.len < scores.len || out.len <= scores.len { ret (zero, TooSmall) }
    var positives = 0usize
    var i = 0usize
    while i < scores.len {
        if scores[i] != scores[i] || scores[i] - scores[i] != 0.0f64 { ret (zero, Invalid) }
        if positive[i] { positives += 1usize }
        order[i] = i
        i += 1usize
    }
    let negatives = scores.len - positives
    if positives == 0usize || negatives == 0usize { ret (zero, Invalid) }
    var key = RankKey { values: scores }
    sort.in_place_by[usize, RankKey](order[..scores.len], &key, compare_by_value)
    out[0usize] = BinaryPoint { tp: 0usize, fp: 0usize }
    var used = 1usize
    var remaining = scores.len
    var tp = 0usize
    var fp = 0usize
    while remaining > 0usize {
        let threshold = scores[order[remaining - 1usize]]
        while remaining > 0usize && scores[order[remaining - 1usize]] == threshold {
            remaining -= 1usize
            if positive[order[remaining]] { tp += 1usize } else { fp += 1usize }
        }
        out[used] = BinaryPoint { tp: tp, fp: fp }
        used += 1usize
    }
    ret (BinaryCurve { points: out[..used], positives: positives, negatives: negatives }, ok)
}

fn roc_auc(c: *const BinaryCurve) -> (f64, bool) {
    if c.positives == 0usize || c.negatives == 0usize || c.points.len < 2usize { ret (0.0f64, false) }
    var area = 0.0f64
    var i = 1usize
    while i < c.points.len {
        let before = c.points[i - 1usize]
        let after = c.points[i]
        if after.tp < before.tp || after.fp < before.fp || after.tp > c.positives || after.fp > c.negatives { ret (0.0f64, false) }
        let dx = f64(after.fp - before.fp) / f64(c.negatives)
        area += dx * ((f64(before.tp) + f64(after.tp)) / (2.0f64 * f64(c.positives)))
        i += 1usize
    }
    if c.points[0usize].tp != 0usize || c.points[0usize].fp != 0usize || c.points[c.points.len - 1usize].tp != c.positives || c.points[c.points.len - 1usize].fp != c.negatives { ret (0.0f64, false) }
    ret (area, true)
}

// Raw ROC area from false-positive rate 0 to the caller's cutoff.
fn roc_partial_auc(c: *const BinaryCurve, max_fpr: f64) -> (f64, bool) {
    let (_, valid) = roc_auc(c)
    if !valid || max_fpr != max_fpr || max_fpr <= 0.0f64 || max_fpr > 1.0f64 { ret (0.0f64, false) }
    var area = 0.0f64
    var i = 1usize
    while i < c.points.len {
        let before = c.points[i - 1usize]
        let after = c.points[i]
        let x0 = f64(before.fp) / f64(c.negatives)
        let x1 = f64(after.fp) / f64(c.negatives)
        if x0 >= max_fpr { break }
        if x1 > x0 {
            var stop = x1
            if stop > max_fpr { stop = max_fpr }
            let y0 = f64(before.tp) / f64(c.positives)
            let y1 = f64(after.tp) / f64(c.positives)
            let y_stop = y0 + (y1 - y0) * (stop - x0) / (x1 - x0)
            area += (stop - x0) * (y0 + y_stop) * 0.5f64
            if stop == max_fpr { break }
        }
        i += 1usize
    }
    ret (area, true)
}

// The returned point index selects the highest-score threshold on a J tie.
fn youden_index(c: *const BinaryCurve) -> (usize, f64, bool) {
    let (_, valid) = roc_auc(c)
    if !valid { ret (0usize, 0.0f64, false) }
    var best_index = 0usize
    var best = 0.0f64
    var i = 1usize
    while i < c.points.len {
        let p = c.points[i]
        let value = f64(p.tp) / f64(c.positives) - f64(p.fp) / f64(c.negatives)
        if value > best {
            best = value
            best_index = i
        }
        i += 1usize
    }
    ret (best_index, best, true)
}

fn average_precision(c: *const BinaryCurve) -> (f64, bool) {
    if c.positives == 0usize || c.negatives == 0usize || c.points.len < 2usize { ret (0.0f64, false) }
    var area = 0.0f64
    var i = 1usize
    while i < c.points.len {
        let before = c.points[i - 1usize]
        let after = c.points[i]
        if after.tp < before.tp || after.fp < before.fp || after.tp > c.positives || after.fp > c.negatives { ret (0.0f64, false) }
        if after.tp > before.tp {
            let selected = after.tp + after.fp
            area += (f64(after.tp - before.tp) / f64(c.positives)) * (f64(after.tp) / f64(selected))
        }
        i += 1usize
    }
    if c.points[0usize].tp != 0usize || c.points[0usize].fp != 0usize || c.points[c.points.len - 1usize].tp != c.positives || c.points[c.points.len - 1usize].fp != c.negatives { ret (0.0f64, false) }
    ret (area, true)
}

// Equal-width probability bins; callers choose resolution through storage length.
fn binary_calibration(scores: []const f64, positive: []const bool, bins: []CalibrationBin) -> err {
    if scores.len == 0usize || positive.len != scores.len { ret Invalid }
    if bins.len == 0usize { ret TooSmall }
    var i = 0usize
    while i < scores.len {
        let score = scores[i]
        if score != score || score - score != 0.0f64 || score < 0.0f64 || score > 1.0f64 { ret Invalid }
        i += 1usize
    }
    i = 0usize
    while i < bins.len {
        bins[i] = CalibrationBin { count: 0usize, positives: 0usize, score_sum: 0.0f64 }
        i += 1usize
    }
    i = 0usize
    while i < scores.len {
        var bucket = usize(scores[i] * f64(bins.len))
        if bucket == bins.len { bucket -= 1usize }
        bins[bucket].count += 1usize
        if positive[i] { bins[bucket].positives += 1usize }
        bins[bucket].score_sum += scores[i]
        i += 1usize
    }
    ret ok
}

// Rows are actual negative/positive; columns are predicted negative/positive.
fn binary_confusion(scores: []const f64, positive: []const bool, threshold: f64) -> (BinaryConfusion, err) {
    if scores.len == 0usize || positive.len != scores.len || threshold != threshold || threshold - threshold != 0.0f64 { ret (zero, Invalid) }
    var counts: BinaryConfusion = zero
    var i = 0usize
    while i < scores.len {
        let score = scores[i]
        if score != score || score - score != 0.0f64 { ret (zero, Invalid) }
        if positive[i] {
            if score >= threshold { counts.true_positive += 1usize } else { counts.false_negative += 1usize }
        } else {
            if score >= threshold { counts.false_positive += 1usize } else { counts.true_negative += 1usize }
        }
        i += 1usize
    }
    ret (counts, ok)
}

// ponytail: O(samples * thresholds); reuse the sorted sweep if large grids need it.
fn decision_curve(scores: []const f64, positive: []const bool, thresholds: []const f64, model: []f64, treat_all: []f64) -> err {
    if scores.len == 0usize || positive.len != scores.len || thresholds.len == 0usize { ret Invalid }
    if model.len < thresholds.len || treat_all.len < thresholds.len { ret TooSmall }
    var positives = 0usize
    var i = 0usize
    while i < scores.len {
        let score = scores[i]
        if score != score || score - score != 0.0f64 || score < 0.0f64 || score > 1.0f64 { ret Invalid }
        if positive[i] { positives += 1usize }
        i += 1usize
    }
    i = 0usize
    while i < thresholds.len {
        let threshold = thresholds[i]
        if threshold != threshold || threshold <= 0.0f64 || threshold >= 1.0f64 || (i > 0usize && threshold <= thresholds[i - 1usize]) { ret Invalid }
        i += 1usize
    }
    i = 0usize
    while i < thresholds.len {
        let ratio = thresholds[i] / (1.0f64 - thresholds[i])
        let (counts, counts_error) = binary_confusion(scores, positive, thresholds[i])
        if counts_error != ok { ret counts_error }
        model[i] = (f64(counts.true_positive) - f64(counts.false_positive) * ratio) / f64(scores.len)
        treat_all[i] = (f64(positives) - f64(scores.len - positives) * ratio) / f64(scores.len)
        i += 1usize
    }
    ret ok
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

// Internally standardized residuals and Cook's distance for an intercept/slope OLS fit.
// An exact fit has zero residual variance, so these diagnostics are undefined.
fn regression_diagnostics(x: []const f64, y: []const f64, out: []RegressionDiagnostic) -> err {
    if x.len < 4usize || y.len != x.len { ret Invalid }
    if out.len < x.len { ret TooSmall }
    var s = regression()
    var i = 0usize
    while i < x.len {
        if x[i] - x[i] != 0.0f64 || y[i] - y[i] != 0.0f64 { ret Invalid }
        regression_add(&s, x[i], y[i])
        i += 1usize
    }
    let (slope, defined) = regression_slope(&s)
    if !defined { ret Invalid }
    let intercept = s.mean_y - slope * s.mean_x
    let mse = (s.m2_y - slope * s.cov) / f64(x.len - 2usize)
    if mse <= 0.0f64 || mse - mse != 0.0f64 || intercept - intercept != 0.0f64 { ret Invalid }
    i = 0usize
    while i < x.len {
        let dx = x[i] - s.mean_x
        let leverage = 1.0f64 / f64(x.len) + dx * dx / s.m2_x
        let fitted = intercept + slope * x[i]
        let residual = y[i] - fitted
        let remaining = 1.0f64 - leverage
        if remaining <= 0.0f64 { ret Invalid }
        let standardized = residual / math.sqrt[f64](mse * remaining)
        let cook = residual * residual / (2.0f64 * mse) * leverage / (remaining * remaining)
        if standardized - standardized != 0.0f64 || cook - cook != 0.0f64 { ret Invalid }
        out[i] = RegressionDiagnostic { fitted: fitted, residual: residual, leverage: leverage, standardized: standardized, cook: cook }
        i += 1usize
    }
    ret ok
}

// Sorted nonnegative follow-up times; tied events precede censoring within a
// time group. Output includes a time-zero baseline and each distinct time.
fn survival_curve(times: []const f64, event: []const bool, out: []SurvivalPoint) -> ([]SurvivalPoint, err) {
    if times.len == 0usize || event.len != times.len { ret (zero, Invalid) }
    if out.len <= times.len { ret (zero, TooSmall) }
    var i = 0usize
    while i < times.len {
        if times[i] < 0.0f64 || times[i] - times[i] != 0.0f64 || (i > 0usize && times[i] < times[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    out[0usize] = SurvivalPoint { time: 0.0f64, survival: 1.0f64, cumulative_hazard: 0.0f64, at_risk: times.len, events: 0usize, censored: 0usize }
    var used = 1usize
    var risk = times.len
    var survival = 1.0f64
    var hazard = 0.0f64
    i = 0usize
    while i < times.len {
        let time = times[i]
        var events = 0usize
        var censored = 0usize
        while i < times.len && times[i] == time {
            if event[i] { events += 1usize } else { censored += 1usize }
            i += 1usize
        }
        let fraction = f64(events) / f64(risk)
        survival *= 1.0f64 - fraction
        hazard += fraction
        out[used] = SurvivalPoint { time: time, survival: survival, cumulative_hazard: hazard, at_risk: risk, events: events, censored: censored }
        used += 1usize
        risk -= events + censored
    }
    ret (out[..used], ok)
}

// Four-parameter log-logistic mean (drc LL.4 parameterisation). This evaluates
// caller-supplied parameters; it does not infer or fit them from observations.
fn log_logistic4(dose: f64, lower: f64, upper: f64, ec50: f64, slope: f64) -> (f64, err) {
    if dose <= 0.0f64 || ec50 <= 0.0f64 || lower >= upper || slope == 0.0f64 { ret (0.0f64, Invalid) }
    if dose - dose != 0.0f64 || lower - lower != 0.0f64 || upper - upper != 0.0f64 || ec50 - ec50 != 0.0f64 || slope - slope != 0.0f64 { ret (0.0f64, Invalid) }
    let exponent = slope * (math.log[f64](dose) - math.log[f64](ec50))
    var fraction = 0.0f64
    if exponent < -40.0f64 {
        fraction = 1.0f64
    } else if exponent < 40.0f64 {
        fraction = 1.0f64 / (1.0f64 + math.exp[f64](exponent))
    }
    let response = lower + (upper - lower) * fraction
    if response - response != 0.0f64 { ret (0.0f64, Invalid) }
    ret (response, ok)
}

// Piecewise event/person-time rates for intervals (edges[i], edges[i+1]].
// Every subject enters at time zero and contributes exposure until its event
// or right-censoring time; zero-exposure bins have no estimable rate.
fn interval_hazard(times: []const f64, event: []const bool, edges: []const f64, counts: []u64, exposure: []f64, rates: []f64) -> err {
    if times.len == 0usize || event.len != times.len || edges.len < 2usize { ret Invalid }
    let bins = edges.len - 1usize
    if counts.len < bins || exposure.len < bins || rates.len < bins { ret TooSmall }
    if edges[0usize] != 0.0f64 { ret Invalid }
    var j = 0usize
    while j < bins {
        if edges[j] - edges[j] != 0.0f64 || edges[j + 1usize] - edges[j + 1usize] != 0.0f64 || edges[j + 1usize] <= edges[j] { ret Invalid }
        counts[j] = 0u64
        exposure[j] = 0.0f64
        rates[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < times.len {
        let time = times[i]
        if time <= 0.0f64 || time > edges[bins] || time - time != 0.0f64 { ret Invalid }
        j = 0usize
        while j < bins {
            let lower = edges[j]
            let upper = edges[j + 1usize]
            var observed_end = time
            if observed_end > upper { observed_end = upper }
            if observed_end > lower { exposure[j] += observed_end - lower }
            if event[i] && time > lower && time <= upper { counts[j] += 1u64 }
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < bins {
        if exposure[j] <= 0.0f64 || exposure[j] - exposure[j] != 0.0f64 { ret Invalid }
        rates[j] = f64(counts[j]) / exposure[j]
        if rates[j] - rates[j] != 0.0f64 { ret Invalid }
        j += 1usize
    }
    ret ok
}

// Three-sigma Individuals and moving-range limits for consecutive pairs.
fn imr_limits(values: []const f64, moving: []f64) -> (ControlLimits, ControlLimits, err) {
    if values.len < 2usize { ret (zero, zero, Invalid) }
    if moving.len < values.len - 1usize { ret (zero, zero, TooSmall) }
    var i = 0usize
    while i < values.len {
        if values[i] - values[i] != 0.0f64 { ret (zero, zero, Invalid) }
        i += 1usize
    }
    var observations = moments()
    var ranges = moments()
    i = 0usize
    while i < values.len {
        moments_add(&observations, values[i])
        if i > 0usize {
            var span = values[i] - values[i - 1usize]
            if span < 0.0f64 { span = 0.0f64 - span }
            if span - span != 0.0f64 { ret (zero, zero, Invalid) }
            moving[i - 1usize] = span
            moments_add(&ranges, span)
        }
        i += 1usize
    }
    let spread = 3.0f64 * ranges.mean / 1.128f64
    let individuals = ControlLimits { center: observations.mean, lower: observations.mean - spread, upper: observations.mean + spread }
    let mr = ControlLimits { center: ranges.mean, lower: 0.0f64, upper: 3.267f64 * ranges.mean }
    if individuals.lower - individuals.lower != 0.0f64 || individuals.upper - individuals.upper != 0.0f64 || mr.upper - mr.upper != 0.0f64 { ret (zero, zero, Invalid) }
    ret (individuals, mr, ok)
}

// Individuals-only normal capability. Within sigma is MR-bar/d2 for pairs;
// overall sigma is the sample standard deviation. Both specifications are required.
fn normal_capability_individuals(values: []const f64, lsl: f64, usl: f64, moving: []f64) -> (NormalCapability, err) {
    if lsl - lsl != 0.0f64 || usl - usl != 0.0f64 || !(usl > lsl) { ret (zero, Invalid) }
    let (individuals, ranges, limit_error) = imr_limits(values, moving)
    if limit_error != ok { ret (zero, limit_error) }
    var observations = moments()
    var i = 0usize
    while i < values.len {
        moments_add(&observations, values[i])
        i += 1usize
    }
    let (overall, has_overall) = standard_deviation_sample(&observations)
    let within = ranges.center / 1.128f64
    if !has_overall || !(overall > 0.0f64) || !(within > 0.0f64) || overall - overall != 0.0f64 || within - within != 0.0f64 { ret (zero, Invalid) }
    let width = usl - lsl
    let lower = observations.mean - lsl
    let upper = usl - observations.mean
    if width - width != 0.0f64 || lower - lower != 0.0f64 || upper - upper != 0.0f64 { ret (zero, Invalid) }
    var closest = lower
    if upper < closest { closest = upper }
    let cp = width / (6.0f64 * within)
    let cpk = closest / (3.0f64 * within)
    let pp = width / (6.0f64 * overall)
    let ppk = closest / (3.0f64 * overall)
    if cp - cp != 0.0f64 || cpk - cpk != 0.0f64 || pp - pp != 0.0f64 || ppk - ppk != 0.0f64 { ret (zero, Invalid) }
    ret (NormalCapability { mean: observations.mean, within_sigma: within, overall_sigma: overall, cp: cp, cpk: cpk, pp: pp, ppk: ppk, individuals: individuals, moving_range: ranges }, ok)
}

// Observed tails count actual measurements; expected tails assume a normal
// distribution with the within or overall sigma of the capability summary.
fn normal_capability_performance(values: []const f64, lsl: f64, usl: f64, summary: NormalCapability) -> (CapabilityPerformance, err) {
    if values.len == 0usize || lsl - lsl != 0.0f64 || usl - usl != 0.0f64 || !(usl > lsl) || summary.mean - summary.mean != 0.0f64 || summary.within_sigma - summary.within_sigma != 0.0f64 || summary.overall_sigma - summary.overall_sigma != 0.0f64 || !(summary.within_sigma > 0.0f64) || !(summary.overall_sigma > 0.0f64) { ret (zero, Invalid) }
    var below = 0usize
    var above = 0usize
    var i = 0usize
    while i < values.len {
        if values[i] - values[i] != 0.0f64 { ret (zero, Invalid) }
        if values[i] < lsl { below += 1usize }
        if values[i] > usl { above += 1usize }
        i += 1usize
    }
    let million = 1000000.0f64
    let result = CapabilityPerformance {
        observed_below_ppm: million * f64(below) / f64(values.len), observed_above_ppm: million * f64(above) / f64(values.len),
        within_below_ppm: million * special.normal_cdf((lsl - summary.mean) / summary.within_sigma),
        within_above_ppm: million * special.normal_cdf((summary.mean - usl) / summary.within_sigma),
        overall_below_ppm: million * special.normal_cdf((lsl - summary.mean) / summary.overall_sigma),
        overall_above_ppm: million * special.normal_cdf((summary.mean - usl) / summary.overall_sigma),
    }
    ret (result, ok)
}

// Balanced one-way random-effects batch capability. The between component is
// max((MS_between - MS_within) / batch_size, 0); no c4 correction is applied.
fn batch_capability(values: []const f64, batch_size: usize, lsl: f64, usl: f64, batch_means: []f64, batch_spreads: []f64) -> (BatchCapability, err) {
    if batch_size < 2usize || values.len / batch_size < 3usize || values.len % batch_size != 0usize || !(usl > lsl) || lsl - lsl != 0.0f64 || usl - usl != 0.0f64 { ret (zero, Invalid) }
    let batches = values.len / batch_size
    if batch_means.len < batches || batch_spreads.len < batches { ret (zero, TooSmall) }
    var total = moments()
    var within_ss = 0.0f64
    var outside = 0usize
    var i = 0usize
    while i < batches {
        var subgroup = moments()
        var j = 0usize
        while j < batch_size {
            let x = values[i * batch_size + j]
            if x - x != 0.0f64 { ret (zero, Invalid) }
            moments_add(&subgroup, x)
            moments_add(&total, x)
            if x < lsl || x > usl { outside += 1usize }
            j += 1usize
        }
        batch_means[i] = subgroup.mean
        batch_spreads[i] = math.sqrt[f64](subgroup.m2 / f64(batch_size - 1usize))
        within_ss += subgroup.m2
        i += 1usize
    }
    let ms_within = within_ss / f64(batches * (batch_size - 1usize))
    var between_ss = 0.0f64
    i = 0usize
    while i < batches {
        let offset = batch_means[i] - total.mean
        between_ss += f64(batch_size) * offset * offset
        i += 1usize
    }
    let ms_between = between_ss / f64(batches - 1usize)
    var between_var = (ms_between - ms_within) / f64(batch_size)
    if between_var < 0.0f64 { between_var = 0.0f64 }
    let within = math.sqrt[f64](ms_within)
    let between = math.sqrt[f64](between_var)
    let combined = math.sqrt[f64](ms_within + between_var)
    let overall = math.sqrt[f64](total.m2 / f64(values.len - 1usize))
    if !(within > 0.0f64) || !(combined > 0.0f64) || !(overall > 0.0f64) || combined - combined != 0.0f64 || overall - overall != 0.0f64 { ret (zero, Invalid) }
    let width = usl - lsl
    let closest = math.min[f64](total.mean - lsl, usl - total.mean)
    let cp = width / (6.0f64 * combined)
    let cpk = closest / (3.0f64 * combined)
    let pp = width / (6.0f64 * overall)
    let ppk = closest / (3.0f64 * overall)
    if cp - cp != 0.0f64 || cpk - cpk != 0.0f64 || pp - pp != 0.0f64 || ppk - ppk != 0.0f64 { ret (zero, Invalid) }
    let million = 1000000.0f64
    ret (BatchCapability {
        batches: batches, batch_size: batch_size, mean: total.mean,
        within_sigma: within, between_sigma: between, between_within_sigma: combined, overall_sigma: overall,
        cp: cp, cpk: cpk, pp: pp, ppk: ppk,
        observed_ppm: million * f64(outside) / f64(values.len),
        expected_bw_ppm: million * (special.normal_cdf((lsl - total.mean) / combined) + special.normal_cdf((total.mean - usl) / combined)),
        expected_overall_ppm: million * (special.normal_cdf((lsl - total.mean) / overall) + special.normal_cdf((total.mean - usl) / overall)),
    }, ok)
}

// Bias = measurement - reference. OLS fits every replicate, while the means
// and caller-critical confidence limits are reported at each reference value.
fn gage_linearity(references: []const f64, measurements: []const f64, repeats: usize, critical: f64, biases: []f64, means: []f64, fitted: []f64, lower: []f64, upper: []f64) -> (GageLinearity, err) {
    if references.len < 5usize || repeats < 2usize || measurements.len % repeats != 0usize || measurements.len / repeats != references.len || !(critical > 0.0f64) || critical - critical != 0.0f64 { ret (zero, Invalid) }
    if biases.len < measurements.len || means.len < references.len || fitted.len < references.len || lower.len < references.len || upper.len < references.len { ret (zero, TooSmall) }
    var regression_state = regression()
    var i = 0usize
    while i < references.len {
        let reference = references[i]
        if reference - reference != 0.0f64 || (i > 0usize && !(reference > references[i - 1usize])) { ret (zero, Invalid) }
        var total_bias = 0.0f64
        var j = 0usize
        while j < repeats {
            let index = i * repeats + j
            let measurement = measurements[index]
            if measurement - measurement != 0.0f64 { ret (zero, Invalid) }
            let observed_bias = measurement - reference
            if observed_bias - observed_bias != 0.0f64 { ret (zero, Invalid) }
            biases[index] = observed_bias
            total_bias += observed_bias
            regression_add(&regression_state, reference, observed_bias)
            j += 1usize
        }
        means[i] = total_bias / f64(repeats)
        i += 1usize
    }
    let (slope, defined) = regression_slope(&regression_state)
    if !defined || !(regression_state.m2_x > 0.0f64) { ret (zero, Invalid) }
    let intercept = regression_state.mean_y - slope * regression_state.mean_x
    var residual_ss = 0.0f64
    i = 0usize
    while i < references.len {
        var j = 0usize
        while j < repeats {
            let residual = biases[i * repeats + j] - (intercept + slope * references[i])
            residual_ss += residual * residual
            j += 1usize
        }
        i += 1usize
    }
    let mse = residual_ss / f64(measurements.len - 2usize)
    let residual_sigma = math.sqrt[f64](mse)
    let slope_se = math.sqrt[f64](mse / regression_state.m2_x)
    if mse - mse != 0.0f64 || residual_sigma - residual_sigma != 0.0f64 || intercept - intercept != 0.0f64 || slope - slope != 0.0f64 { ret (zero, Invalid) }
    var slope_p = 1.0f64
    if slope_se == 0.0f64 {
        if slope != 0.0f64 { slope_p = 0.0f64 }
    } else {
        let t = math.abs[f64](slope / slope_se)
        slope_p = 2.0f64 * (1.0f64 - special.t_cdf(t, f64(measurements.len - 2usize)))
    }
    i = 0usize
    while i < references.len {
        let x = references[i]
        fitted[i] = intercept + slope * x
        let dx = x - regression_state.mean_x
        let se = math.sqrt[f64](mse * (1.0f64 / f64(measurements.len) + dx * dx / regression_state.m2_x))
        lower[i] = fitted[i] - critical * se
        upper[i] = fitted[i] + critical * se
        if lower[i] - lower[i] != 0.0f64 || upper[i] - upper[i] != 0.0f64 { ret (zero, Invalid) }
        i += 1usize
    }
    ret (GageLinearity {
        reference_count: references.len, repeats: repeats,
        average_bias: regression_state.mean_y, intercept: intercept, slope: slope,
        linearity: slope * (references[references.len - 1usize] - references[0usize]),
        residual_sigma: residual_sigma, slope_standard_error: slope_se, slope_p: slope_p,
    }, ok)
}

// Nominal agreement with a known standard. A part counts for an appraiser only
// if all trials agree; versus-standard additionally requires the reference.
// Kappa is separately defined over individual ratings versus repeated standard.
fn attribute_agreement(standard: []const usize, ratings: []const usize, appraisers: usize, trials: usize, categories: usize, confidence: f64, within: []AttributeAgreementRate, versus_standard: []AttributeAgreementRate) -> (AttributeAgreement, err) {
    if standard.len < 2usize || appraisers < 2usize || trials < 2usize || categories < 2usize || categories > 256usize || !(confidence > 0.0f64 && confidence < 1.0f64) { ret (zero, Invalid) }
    if ratings.len % trials != 0usize || ratings.len / trials % appraisers != 0usize || ratings.len / trials / appraisers != standard.len { ret (zero, Invalid) }
    if within.len < appraisers || versus_standard.len < appraisers { ret (zero, TooSmall) }
    var item = 0usize
    while item < standard.len {
        if standard[item] >= categories { ret (zero, Invalid) }
        item += 1usize
    }
    var pooled_matches = 0usize
    var between_matches = 0usize
    var all_standard_matches = 0usize
    var appraiser = 0usize
    while appraiser < appraisers {
        var consistent = 0usize
        var consistent_standard = 0usize
        item = 0usize
        while item < standard.len {
            let start = (appraiser * standard.len + item) * trials
            let first = ratings[start]
            var same = true
            var trial = 0usize
            while trial < trials {
                let response = ratings[start + trial]
                if response >= categories { ret (zero, Invalid) }
                if response != first { same = false }
                if response == standard[item] { pooled_matches += 1usize }
                trial += 1usize
            }
            if same {
                consistent += 1usize
                if first == standard[item] { consistent_standard += 1usize }
            }
            item += 1usize
        }
        let (within_ci, within_error) = interval_clopper_pearson(u64(consistent), u64(standard.len), confidence)
        let (standard_ci, standard_error) = interval_clopper_pearson(u64(consistent_standard), u64(standard.len), confidence)
        if within_error != ok || standard_error != ok { ret (zero, Invalid) }
        within[appraiser] = AttributeAgreementRate { matched: consistent, total: standard.len, fraction: f64(consistent) / f64(standard.len), confidence: within_ci }
        versus_standard[appraiser] = AttributeAgreementRate { matched: consistent_standard, total: standard.len, fraction: f64(consistent_standard) / f64(standard.len), confidence: standard_ci }
        appraiser += 1usize
    }
    item = 0usize
    while item < standard.len {
        let first = ratings[item * trials]
        var all_same = true
        appraiser = 0usize
        while appraiser < appraisers {
            var trial = 0usize
            while trial < trials {
                if ratings[(appraiser * standard.len + item) * trials + trial] != first { all_same = false }
                trial += 1usize
            }
            appraiser += 1usize
        }
        if all_same {
            between_matches += 1usize
            if first == standard[item] { all_standard_matches += 1usize }
        }
        item += 1usize
    }
    var chance = 0.0f64
    var category = 0usize
    while category < categories {
        var standard_count = 0usize
        var rating_count = 0usize
        item = 0usize
        while item < standard.len {
            if standard[item] == category { standard_count += 1usize }
            item += 1usize
        }
        var i = 0usize
        while i < ratings.len {
            if ratings[i] == category { rating_count += 1usize }
            i += 1usize
        }
        chance += (f64(standard_count) / f64(standard.len)) * (f64(rating_count) / f64(ratings.len))
        category += 1usize
    }
    let pooled_fraction = f64(pooled_matches) / f64(ratings.len)
    var kappa = 0.0f64
    let defined = chance < 1.0f64
    if defined { kappa = (pooled_fraction - chance) / (1.0f64 - chance) }
    ret (AttributeAgreement {
        items: standard.len, appraisers: appraisers, trials: trials,
        between_matched: between_matches, all_vs_standard_matched: all_standard_matches,
        pooled_rating_fraction: pooled_fraction, pooled_rating_kappa: kappa, kappa_defined: defined,
    }, ok)
}

// Two-parameter lognormal MLE on the log scale (overall variation only).
// Pp/Ppk use the Z-score convention, not ISO percentile-spread indices.
fn lognormal_capability(values: []const f64, lsl: f64, usl: f64) -> (LognormalCapability, err) {
    if values.len < 5usize || lsl - lsl != 0.0f64 || usl - usl != 0.0f64 || !(lsl > 0.0f64) || !(usl > lsl) { ret (zero, Invalid) }
    var logs = moments()
    var below = 0usize
    var above = 0usize
    var i = 0usize
    while i < values.len {
        let x = values[i]
        if x - x != 0.0f64 || !(x > 0.0f64) { ret (zero, Invalid) }
        moments_add(&logs, math.log[f64](x))
        if x < lsl { below += 1usize }
        if x > usl { above += 1usize }
        i += 1usize
    }
    let sigma = math.sqrt[f64](logs.m2 / f64(values.len))
    if !(sigma > 0.0f64) || sigma - sigma != 0.0f64 { ret (zero, Invalid) }
    let median = math.exp[f64](logs.mean)
    let z_lower = (math.log[f64](lsl) - logs.mean) / sigma
    let z_upper = (math.log[f64](usl) - logs.mean) / sigma
    let ppl = (0.0f64 - z_lower) / 3.0f64
    let ppu = z_upper / 3.0f64
    let pp = (z_upper - z_lower) / 6.0f64
    let ppk = math.min[f64](ppl, ppu)
    if median - median != 0.0f64 || z_lower - z_lower != 0.0f64 || z_upper - z_upper != 0.0f64 || pp - pp != 0.0f64 || ppk - ppk != 0.0f64 { ret (zero, Invalid) }
    let million = 1000000.0f64
    ret (LognormalCapability {
        log_mean: logs.mean, log_sigma: sigma, median: median,
        pp: pp, ppl: ppl, ppu: ppu, ppk: ppk,
        observed_below_ppm: million * f64(below) / f64(values.len),
        observed_above_ppm: million * f64(above) / f64(values.len),
        expected_below_ppm: million * special.normal_cdf(z_lower),
        expected_above_ppm: million * special.normal_cdf(0.0f64 - z_upper),
    }, ok)
}

// Each true entry starts a phase; moving ranges never span a phase boundary.
fn imr_phase_control(values: []const f64, starts: []const bool, moving: []f64, out: []AttributeControlPoint) -> err {
    if values.len < 2usize || starts.len != values.len || !starts[0usize] { ret Invalid }
    if moving.len < values.len - 1usize || out.len < values.len { ret TooSmall }
    var begin = 0usize
    var i = 0usize
    while i < values.len {
        if values[i] - values[i] != 0.0f64 { ret Invalid }
        if i > 0usize && starts[i] {
            if i - begin < 2usize { ret Invalid }
            begin = i
        }
        i += 1usize
    }
    if values.len - begin < 2usize { ret Invalid }
    begin = 0usize
    while begin < values.len {
        var end = begin + 1usize
        while end < values.len && !starts[end] { end += 1usize }
        let (limits, _, limit_error) = imr_limits(values[begin..end], moving[begin..end - 1usize])
        if limit_error != ok { ret limit_error }
        i = begin
        while i < end {
            out[i] = AttributeControlPoint { value: values[i], center: limits.center, lower: limits.lower, upper: limits.upper }
            i += 1usize
        }
        if end < values.len { moving[end - 1usize] = 0.0f64 }
        begin = end
    }
    ret ok
}

// Subgroup-major values. Standard A2/D3/D4 factors cover sizes 2..10.
fn xbar_r_limits(values: []const f64, subgroup: usize, means: []f64, ranges: []f64) -> (ControlLimits, ControlLimits, err) {
    if subgroup < 2usize || subgroup > 10usize || values.len < subgroup * 2usize || values.len % subgroup != 0usize { ret (zero, zero, Invalid) }
    let groups = values.len / subgroup
    if means.len < groups || ranges.len < groups { ret (zero, zero, TooSmall) }
    var i = 0usize
    while i < values.len {
        if values[i] - values[i] != 0.0f64 { ret (zero, zero, Invalid) }
        i += 1usize
    }
    var grand = moments()
    var range_stats = moments()
    var group = 0usize
    while group < groups {
        let start = group * subgroup
        var sample = moments()
        var low = values[start]
        var high = low
        i = 0usize
        while i < subgroup {
            let value = values[start + i]
            moments_add(&sample, value)
            if value < low { low = value }
            if value > high { high = value }
            i += 1usize
        }
        let span = high - low
        if sample.mean - sample.mean != 0.0f64 || span - span != 0.0f64 { ret (zero, zero, Invalid) }
        means[group] = sample.mean
        ranges[group] = span
        moments_add(&grand, sample.mean)
        moments_add(&range_stats, span)
        group += 1usize
    }
    let a2 = [9]f64{ 1.880f64, 1.023f64, 0.729f64, 0.577f64, 0.483f64, 0.419f64, 0.373f64, 0.337f64, 0.308f64 }
    let d3 = [9]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.076f64, 0.136f64, 0.184f64, 0.223f64 }
    let d4 = [9]f64{ 3.267f64, 2.575f64, 2.282f64, 2.115f64, 2.004f64, 1.924f64, 1.864f64, 1.816f64, 1.777f64 }
    let factor = subgroup - 2usize
    let mean_limits = ControlLimits { center: grand.mean, lower: grand.mean - a2[factor] * range_stats.mean, upper: grand.mean + a2[factor] * range_stats.mean }
    let range_limits = ControlLimits { center: range_stats.mean, lower: d3[factor] * range_stats.mean, upper: d4[factor] * range_stats.mean }
    if mean_limits.lower - mean_limits.lower != 0.0f64 || mean_limits.upper - mean_limits.upper != 0.0f64 || range_limits.upper - range_limits.upper != 0.0f64 { ret (zero, zero, Invalid) }
    ret (mean_limits, range_limits, ok)
}

// Three-sigma binomial (P/Np) or Poisson (C/U) limits. Sizes are inspected
// units/opportunities; Np requires equal sizes and C requires unit size one.
fn attribute_control(kind: AttributeControlKind, counts: []const usize, sizes: []const usize, out: []AttributeControlPoint) -> err {
    if counts.len < 2usize || sizes.len != counts.len { ret Invalid }
    if out.len < counts.len { ret TooSmall }
    var total_count = 0.0f64
    var total_size = 0.0f64
    var i = 0usize
    while i < counts.len {
        if sizes[i] == 0usize || (kind == .C && sizes[i] != 1usize) || (kind == .Np && sizes[i] != sizes[0usize]) || ((kind == .P || kind == .Np) && counts[i] > sizes[i]) { ret Invalid }
        total_count += f64(counts[i])
        total_size += f64(sizes[i])
        i += 1usize
    }
    let rate = total_count / total_size
    if rate - rate != 0.0f64 { ret Invalid }
    i = 0usize
    while i < counts.len {
        let n = f64(sizes[i])
        var value = f64(counts[i])
        var center = rate
        var sigma = 0.0f64
        var ceiling = 0.0f64
        if kind == .P {
            value /= n
            sigma = math.sqrt[f64](rate * (1.0f64 - rate) / n)
            ceiling = 1.0f64
        } else if kind == .Np {
            center *= n
            sigma = math.sqrt[f64](center * (1.0f64 - rate))
            ceiling = n
        } else if kind == .C {
            sigma = math.sqrt[f64](rate)
        } else {
            value /= n
            sigma = math.sqrt[f64](rate / n)
        }
        var lower = center - 3.0f64 * sigma
        var upper = center + 3.0f64 * sigma
        if lower < 0.0f64 { lower = 0.0f64 }
        if ceiling > 0.0f64 && upper > ceiling { upper = ceiling }
        if value - value != 0.0f64 || upper - upper != 0.0f64 { ret Invalid }
        out[i] = AttributeControlPoint { value: value, center: center, lower: lower, upper: upper }
        i += 1usize
    }
    ret ok
}

// Binomial defective-unit capability over time-ordered subgroups. The pooled
// rate weights each subgroup by inspected units; the 95% interval method is
// explicitly Wilson rather than the Clopper-Pearson interval.
fn binomial_capability(counts: []const usize, sizes: []const usize, target_fraction: f64, confidence: f64, controls: []AttributeControlPoint, cumulative: []f64) -> (BinomialCapability, err) {
    if counts.len < 2usize || sizes.len != counts.len || !(target_fraction >= 0.0f64 && target_fraction <= 1.0f64) || !(confidence > 0.0f64 && confidence < 1.0f64) { ret (zero, Invalid) }
    if controls.len < counts.len || cumulative.len < counts.len { ret (zero, TooSmall) }
    let control_error = attribute_control(.P, counts, sizes, controls)
    if control_error != ok { ret (zero, control_error) }
    var defective = 0u64
    var inspected = 0u64
    var beyond = 0usize
    var i = 0usize
    while i < counts.len {
        if u64(counts[i]) > 18446744073709551615u64 - defective || u64(sizes[i]) > 18446744073709551615u64 - inspected { ret (zero, Invalid) }
        defective += u64(counts[i])
        inspected += u64(sizes[i])
        cumulative[i] = f64(defective) / f64(inspected)
        if controls[i].value < controls[i].lower || controls[i].value > controls[i].upper { beyond += 1usize }
        i += 1usize
    }
    let fraction = f64(defective) / f64(inspected)
    let (interval, interval_error) = interval_wilson(defective, inspected, confidence)
    if interval_error != ok || fraction - fraction != 0.0f64 { ret (zero, Invalid) }
    ret (BinomialCapability {
        defective: defective, inspected: inspected, fraction: fraction,
        ppm: fraction * 1000000.0f64, confidence: interval, target_fraction: target_fraction,
        meets_target: fraction <= target_fraction,
        upper_bound_meets_target: interval.high <= target_fraction,
        beyond_limits: beyond,
    }, ok)
}

// Re-estimate each P/Np/C/U baseline within its own phase.
fn attribute_control_phased(kind: AttributeControlKind, counts: []const usize, sizes: []const usize, starts: []const bool, out: []AttributeControlPoint) -> err {
    if counts.len < 2usize || sizes.len != counts.len || starts.len != counts.len || !starts[0usize] { ret Invalid }
    if out.len < counts.len { ret TooSmall }
    var begin = 0usize
    var i = 0usize
    while i < counts.len {
        if i > 0usize && starts[i] {
            if i - begin < 2usize { ret Invalid }
            begin = i
        }
        if sizes[i] == 0usize || (kind == .C && sizes[i] != 1usize) || (kind == .Np && sizes[i] != sizes[begin]) || ((kind == .P || kind == .Np) && counts[i] > sizes[i]) { ret Invalid }
        i += 1usize
    }
    if counts.len - begin < 2usize { ret Invalid }
    begin = 0usize
    while begin < counts.len {
        var end = begin + 1usize
        while end < counts.len && !starts[end] { end += 1usize }
        let phase_error = attribute_control(kind, counts[begin..end], sizes[begin..end], out[begin..end])
        if phase_error != ok { ret phase_error }
        begin = end
    }
    ret ok
}

// Laney P'/U' widen or narrow ordinary attribute limits by the z-score MR estimate.
fn laney_control(kind: AttributeControlKind, counts: []const usize, sizes: []const usize, out: []AttributeControlPoint) -> (f64, err) {
    if kind != .P && kind != .U { ret (0.0f64, Invalid) }
    let base_error = attribute_control(kind, counts, sizes, out)
    if base_error != ok { ret (0.0f64, base_error) }
    let center = out[0usize].center
    if center <= 0.0f64 || (kind == .P && center >= 1.0f64) { ret (0.0f64, Invalid) }
    var ranges = 0.0f64
    var previous = 0.0f64
    var i = 0usize
    while i < counts.len {
        let n = f64(sizes[i])
        var variance = center / n
        if kind == .P { variance *= 1.0f64 - center }
        let z = (out[i].value - center) / math.sqrt[f64](variance)
        if z - z != 0.0f64 { ret (0.0f64, Invalid) }
        if i > 0usize {
            var difference = z - previous
            if difference < 0.0f64 { difference = -difference }
            ranges += difference
        }
        previous = z
        i += 1usize
    }
    let sigma_z = ranges / f64(counts.len - 1usize) / 1.128f64
    if sigma_z - sigma_z != 0.0f64 { ret (0.0f64, Invalid) }
    i = 0usize
    while i < counts.len {
        let n = f64(sizes[i])
        var variance = center / n
        if kind == .P { variance *= 1.0f64 - center }
        let spread = 3.0f64 * math.sqrt[f64](variance) * sigma_z
        var lower = center - spread
        var upper = center + spread
        if lower < 0.0f64 { lower = 0.0f64 }
        if kind == .P && upper > 1.0f64 { upper = 1.0f64 }
        if upper - upper != 0.0f64 { ret (0.0f64, Invalid) }
        out[i].lower = lower
        out[i].upper = upper
        i += 1usize
    }
    ret (sigma_z, ok)
}

// Each phase gets its own pooled baseline and adjacent-z dispersion estimate.
fn laney_control_phased(kind: AttributeControlKind, counts: []const usize, sizes: []const usize, starts: []const bool, out: []AttributeControlPoint, sigma_z: []f64) -> err {
    if kind != .P && kind != .U { ret Invalid }
    if sigma_z.len < counts.len { ret TooSmall }
    let phase_error = attribute_control_phased(kind, counts, sizes, starts, out)
    if phase_error != ok { ret phase_error }
    var begin = 0usize
    while begin < counts.len {
        var end = begin + 1usize
        while end < counts.len && !starts[end] { end += 1usize }
        let (sigma, control_error) = laney_control(kind, counts[begin..end], sizes[begin..end], out[begin..end])
        if control_error != ok { ret control_error }
        var i = begin
        while i < end {
            sigma_z[i] = sigma
            i += 1usize
        }
        begin = end
    }
    ret ok
}

// Interpolate adjacent geometric CDF steps, then convert trials-until to gaps-between.
fn geometric_gap_percentile(probability: f64, fraction: f64) -> (f64, bool) {
    if !(probability > 0.0f64) || probability > 1.0f64 || fraction < 0.0f64 || !(fraction < 1.0f64) { ret (0.0f64, false) }
    if probability == 1.0f64 { ret (0.0f64, true) }
    var log_survival = math.log[f64](1.0f64 - probability)
    if probability < 0.00000001f64 { log_survival = -probability - probability * probability / 2.0f64 }
    let trials = math.log[f64](1.0f64 - fraction) / log_survival
    let before = math.floor[f64](trials)
    let lower_cdf = 1.0f64 - math.exp[f64](before * log_survival)
    let upper_cdf = 1.0f64 - math.exp[f64]((before + 1.0f64) * log_survival)
    var gap = trials - 1.0f64
    if upper_cdf > lower_cdf { gap = before - 1.0f64 + (fraction - lower_cdf) / (upper_cdf - lower_cdf) }
    if gap < 0.0f64 { gap = 0.0f64 }
    if gap - gap != 0.0f64 { ret (0.0f64, false) }
    ret (gap, true)
}

// G chart: whole opportunities between events, with a fitted geometric model.
fn g_control_limits(gaps: []const usize) -> (ControlLimits, err) {
    if gaps.len < 2usize { ret (zero, Invalid) }
    var sample = moments()
    var i = 0usize
    while i < gaps.len {
        moments_add(&sample, f64(gaps[i]))
        i += 1usize
    }
    let probability = 1.0f64 / (sample.mean + 1.0f64)
    if !(probability > 0.0f64) || probability > 1.0f64 { ret (zero, Invalid) }
    let (center, center_ok) = geometric_gap_percentile(probability, 0.5f64)
    let (lower, lower_ok) = geometric_gap_percentile(probability, 0.00135f64)
    let (upper, upper_ok) = geometric_gap_percentile(probability, 0.99865f64)
    if !center_ok || !lower_ok || !upper_ok { ret (zero, Invalid) }
    let limits = ControlLimits { center: center, lower: lower, upper: upper }
    if limits.upper - limits.upper != 0.0f64 { ret (zero, Invalid) }
    ret (limits, ok)
}

// T chart: positive continuous elapsed time with exponential MLE scale.
fn t_exponential_control_limits(intervals: []const f64) -> (ControlLimits, err) {
    if intervals.len < 2usize { ret (zero, Invalid) }
    var sample = moments()
    var i = 0usize
    while i < intervals.len {
        if !(intervals[i] > 0.0f64) || intervals[i] - intervals[i] != 0.0f64 { ret (zero, Invalid) }
        moments_add(&sample, intervals[i])
        i += 1usize
    }
    let limits = ControlLimits {
        center: sample.mean * (0.0f64 - math.log[f64](0.5f64)),
        lower: sample.mean * (0.0f64 - math.log[f64](1.0f64 - 0.00135f64)),
        upper: sample.mean * (0.0f64 - math.log[f64](1.0f64 - 0.99865f64)),
    }
    if limits.upper - limits.upper != 0.0f64 { ret (zero, Invalid) }
    ret (limits, ok)
}

// Tests 1–8 mark the point that completes a special-cause pattern.
fn control_run_rules_phased(values: []const f64, centers: []const f64, sigmas: []const f64, starts: []const bool, out: []ControlSignal) -> err {
    if values.len == 0usize || centers.len != values.len || sigmas.len != values.len { ret Invalid }
    if starts.len != 0usize && (starts.len != values.len || !starts[0usize]) { ret Invalid }
    if out.len < values.len { ret TooSmall }
    var i = 0usize
    while i < values.len {
        if values[i] - values[i] != 0.0f64 || centers[i] - centers[i] != 0.0f64 || !(sigmas[i] > 0.0f64) || sigmas[i] - sigmas[i] != 0.0f64 { ret Invalid }
        let z = (values[i] - centers[i]) / sigmas[i]
        if z - z != 0.0f64 { ret Invalid }
        i += 1usize
    }
    var above = 0usize
    var below = 0usize
    var rising = 1usize
    var falling = 1usize
    var alternating = 1usize
    var phase_begin = 0usize
    i = 0usize
    while i < values.len {
        if i > 0usize && starts.len > 0usize && starts[i] {
            phase_begin = i
            above = 0usize
            below = 0usize
            rising = 1usize
            falling = 1usize
            alternating = 1usize
        }
        let z = (values[i] - centers[i]) / sigmas[i]
        if z > 0.0f64 { above += 1usize } else { above = 0usize }
        if z < 0.0f64 { below += 1usize } else { below = 0usize }
        if i > phase_begin {
            if values[i] > values[i - 1usize] { rising += 1usize } else { rising = 1usize }
            if values[i] < values[i - 1usize] { falling += 1usize } else { falling = 1usize }
            if values[i] == values[i - 1usize] { alternating = 1usize } else if i == phase_begin + 1usize { alternating = 2usize } else if (values[i] > values[i - 1usize] && values[i - 1usize] < values[i - 2usize]) || (values[i] < values[i - 1usize] && values[i - 1usize] > values[i - 2usize]) {
                alternating += 1usize
            } else {
                alternating = 2usize
            }
        }
        var signal: ControlSignal = zero
        signal.beyond3 = z > 3.0f64 || z < -3.0f64
        signal.same_side9 = above >= 9usize || below >= 9usize
        signal.trend6 = rising >= 6usize || falling >= 6usize
        signal.alternating14 = alternating >= 14usize
        if i - phase_begin >= 2usize {
            var high2 = 0usize
            var low2 = 0usize
            var j = i - 2usize
            while j <= i {
                let zone = (values[j] - centers[j]) / sigmas[j]
                if zone > 2.0f64 { high2 += 1usize }
                if zone < -2.0f64 { low2 += 1usize }
                j += 1usize
            }
            signal.two_of_three2 = high2 >= 2usize || low2 >= 2usize
        }
        if i - phase_begin >= 4usize {
            var high1 = 0usize
            var low1 = 0usize
            var j = i - 4usize
            while j <= i {
                let zone = (values[j] - centers[j]) / sigmas[j]
                if zone > 1.0f64 { high1 += 1usize }
                if zone < -1.0f64 { low1 += 1usize }
                j += 1usize
            }
            signal.four_of_five1 = high1 >= 4usize || low1 >= 4usize
        }
        if i - phase_begin >= 14usize {
            signal.within1_15 = true
            var j = i - 14usize
            while j <= i {
                let zone = (values[j] - centers[j]) / sigmas[j]
                if zone < -1.0f64 || zone > 1.0f64 { signal.within1_15 = false }
                j += 1usize
            }
        }
        if i - phase_begin >= 7usize {
            signal.outside1_8 = true
            var j = i - 7usize
            while j <= i {
                let zone = (values[j] - centers[j]) / sigmas[j]
                if zone >= -1.0f64 && zone <= 1.0f64 { signal.outside1_8 = false }
                j += 1usize
            }
        }
        out[i] = signal
        i += 1usize
    }
    ret ok
}

fn control_run_rules(values: []const f64, centers: []const f64, sigmas: []const f64, out: []ControlSignal) -> err {
    ret control_run_rules_phased(values, centers, sigmas, zero, out)
}

// Subgroup-major X-bar/S limits use sample SD and the gamma-derived c4 factor.
fn xbar_s_limits(values: []const f64, subgroup: usize, means: []f64, deviations: []f64) -> (ControlLimits, ControlLimits, err) {
    if subgroup < 2usize || subgroup > values.len / 2usize || values.len % subgroup != 0usize { ret (zero, zero, Invalid) }
    let groups = values.len / subgroup
    if means.len < groups || deviations.len < groups { ret (zero, zero, TooSmall) }
    var i = 0usize
    while i < values.len {
        if values[i] - values[i] != 0.0f64 { ret (zero, zero, Invalid) }
        i += 1usize
    }
    var grand = moments()
    var spread = moments()
    var group = 0usize
    while group < groups {
        var sample = moments()
        i = 0usize
        while i < subgroup {
            moments_add(&sample, values[group * subgroup + i])
            i += 1usize
        }
        let (sd, defined) = standard_deviation_sample(&sample)
        if !defined || sd - sd != 0.0f64 || sample.mean - sample.mean != 0.0f64 { ret (zero, zero, Invalid) }
        means[group] = sample.mean
        deviations[group] = sd
        moments_add(&grand, sample.mean)
        moments_add(&spread, sd)
        group += 1usize
    }
    let n = f64(subgroup)
    let c4 = math.sqrt[f64](2.0f64 / (n - 1.0f64)) * math.exp[f64](special.lgamma(n / 2.0f64) - special.lgamma((n - 1.0f64) / 2.0f64))
    if !(c4 > 0.0f64) || c4 > 1.0f64 { ret (zero, zero, Invalid) }
    let s_factor = 3.0f64 * math.sqrt[f64](1.0f64 - c4 * c4) / c4
    let x_factor = 3.0f64 * spread.mean / (c4 * math.sqrt[f64](n))
    var s_lower = spread.mean * (1.0f64 - s_factor)
    if s_lower < 0.0f64 { s_lower = 0.0f64 }
    let xbar = ControlLimits { center: grand.mean, lower: grand.mean - x_factor, upper: grand.mean + x_factor }
    let s = ControlLimits { center: spread.mean, lower: s_lower, upper: spread.mean * (1.0f64 + s_factor) }
    if xbar.lower - xbar.lower != 0.0f64 || xbar.upper - xbar.upper != 0.0f64 || s.upper - s.upper != 0.0f64 { ret (zero, zero, Invalid) }
    ret (xbar, s, ok)
}

// Phase starts are subgroup indices; both charts re-estimate from each phase.
fn subgroup_control_phased(kind: SubgroupSpreadKind, values: []const f64, subgroup: usize, starts: []const bool, means: []f64, spreads: []f64, mean_points: []AttributeControlPoint, spread_points: []AttributeControlPoint) -> err {
    if subgroup < 2usize || (kind == .Range && subgroup > 10usize) || values.len % subgroup != 0usize { ret Invalid }
    let groups = values.len / subgroup
    if groups < 2usize || starts.len != groups || !starts[0usize] { ret Invalid }
    if means.len < groups || spreads.len < groups || mean_points.len < groups || spread_points.len < groups { ret TooSmall }
    var begin = 0usize
    var group = 0usize
    while group < groups {
        if group > 0usize && starts[group] {
            if group - begin < 2usize { ret Invalid }
            begin = group
        }
        group += 1usize
    }
    if groups - begin < 2usize { ret Invalid }
    var i = 0usize
    while i < values.len {
        if values[i] - values[i] != 0.0f64 { ret Invalid }
        i += 1usize
    }
    begin = 0usize
    while begin < groups {
        var end = begin + 1usize
        while end < groups && !starts[end] { end += 1usize }
        var mean_limits: ControlLimits = zero
        var spread_limits: ControlLimits = zero
        var calc_error: err = ok
        if kind == .Range {
            let (mean_result, spread_result, result_error) = xbar_r_limits(values[begin * subgroup..end * subgroup], subgroup, means[begin..end], spreads[begin..end])
            mean_limits = mean_result
            spread_limits = spread_result
            calc_error = result_error
        } else {
            let (mean_result, spread_result, result_error) = xbar_s_limits(values[begin * subgroup..end * subgroup], subgroup, means[begin..end], spreads[begin..end])
            mean_limits = mean_result
            spread_limits = spread_result
            calc_error = result_error
        }
        if calc_error != ok { ret calc_error }
        group = begin
        while group < end {
            mean_points[group] = AttributeControlPoint { value: means[group], center: mean_limits.center, lower: mean_limits.lower, upper: mean_limits.upper }
            spread_points[group] = AttributeControlPoint { value: spreads[group], center: spread_limits.center, lower: spread_limits.lower, upper: spread_limits.upper }
            group += 1usize
        }
        begin = end
    }
    ret ok
}

// One-sided tabular sums share the target, reference allowance and decision h.
fn cusum_control(values: []const f64, center: f64, reference: f64, decision: f64, out: []CusumPoint) -> err {
    if values.len == 0usize || center - center != 0.0f64 || reference - reference != 0.0f64 || decision - decision != 0.0f64 || reference < 0.0f64 || decision <= 0.0f64 { ret Invalid }
    if out.len < values.len { ret TooSmall }
    var i = 0usize
    while i < values.len {
        if values[i] - values[i] != 0.0f64 { ret Invalid }
        i += 1usize
    }
    var high = 0.0f64
    var low = 0.0f64
    i = 0usize
    while i < values.len {
        high += values[i] - center - reference
        low += center - reference - values[i]
        if high < 0.0f64 { high = 0.0f64 }
        if low < 0.0f64 { low = 0.0f64 }
        if high - high != 0.0f64 || low - low != 0.0f64 { ret Invalid }
        out[i] = CusumPoint { high: high, low: low, high_signal: high > decision, low_signal: low > decision }
        i += 1usize
    }
    ret ok
}

// Startup limits use the exact geometric variance for independent observations.
fn ewma_control(values: []const f64, center: f64, sigma: f64, lambda: f64, width: f64, out: []AttributeControlPoint) -> err {
    if values.len == 0usize || center - center != 0.0f64 || sigma - sigma != 0.0f64 || lambda - lambda != 0.0f64 || width - width != 0.0f64 || sigma <= 0.0f64 || lambda <= 0.0f64 || width <= 0.0f64 { ret Invalid }
    if out.len < values.len { ret TooSmall }
    var i = 0usize
    while i < values.len {
        if values[i] - values[i] != 0.0f64 { ret Invalid }
        i += 1usize
    }
    let remain = 1.0f64 - lambda
    let decay = remain * remain
    var power = 1.0f64
    var average = center
    i = 0usize
    while i < values.len {
        average = lambda * values[i] + remain * average
        power *= decay
        let limit = width * sigma * math.sqrt[f64](lambda / (2.0f64 - lambda) * (1.0f64 - power))
        if average - average != 0.0f64 || limit - limit != 0.0f64 { ret Invalid }
        out[i] = AttributeControlPoint { value: average, center: center, lower: center - limit, upper: center + limit }
        i += 1usize
    }
    ret ok
}

fn correlation(s: *const Regression) -> (f64, bool) {
    if s.count < 2u64 || s.m2_x == 0.0 || s.m2_y == 0.0 { ret (0.0, false) }
    ret (s.cov / math.sqrt[f64](s.m2_x * s.m2_y), true)
}

// ---- Batch statistics over samples ----

// Hyndman-Fan quantile definitions R-1..R-9 (numpy's `inverted_cdf` ..
// `normal_unbiased`; R7 is numpy's default `linear`) and numpy's `nearest`.
type QuantileMethod = enum u8 { R1, R2, R3, R4, R5, R6, R7, R8, R9, Nearest }
// Kernel bandwidth rules of thumb, as `scipy.stats.gaussian_kde` scales them.
type Bandwidth = enum u8 { Silverman, Scott }
type Distribution = enum u8 { Normal, Exponential, Gamma, Beta }
// The two parameters of a fit: Normal (mean, standard deviation), Exponential
// (rate, 0), Gamma (shape, scale), Beta (alpha, beta).
type Fit = struct { a: f64, b: f64 }
type Interval = struct { low: f64, high: f64 }

// Probability that a large-lot, single-sample attributes plan accepts:
// P[Binomial(sample_size, defective_fraction) <= acceptance_number].
// Finite-lot sampling without replacement needs a hypergeometric model.
fn binomial_acceptance_probability(sample_size: usize, acceptance_number: usize, defective_fraction: f64) -> (f64, err) {
    if sample_size == 0usize || acceptance_number > sample_size || !(defective_fraction >= 0.0f64 && defective_fraction <= 1.0f64) { ret (0.0f64, Invalid) }
    if acceptance_number == sample_size || defective_fraction == 0.0f64 { ret (1.0f64, ok) }
    if defective_fraction == 1.0f64 { ret (0.0f64, ok) }
    let probability = special.beta_i(f64(sample_size - acceptance_number), f64(acceptance_number + 1usize), 1.0f64 - defective_fraction)
    if !(probability >= 0.0f64 && probability <= 1.0f64) { ret (0.0f64, Invalid) }
    ret (probability, ok)
}

// The log binomial coefficient by `lgamma`, stable past `u64` range where
// the multiplicative form overflows.
fn log_binomial(n: u64, k: u64) -> f64 {
    ret special.lgamma(f64(n) + 1.0f64) - special.lgamma(f64(k) + 1.0f64) - special.lgamma(f64(n - k) + 1.0f64)
}

// P[X = observed] drawing `draws` without replacement from `population`
// holding `successes`: `C(successes, observed) C(population - successes,
// draws - observed) / C(population, draws)` in log space. An inconsistent
// population (`successes` or `draws` past `population`) is `Invalid`; an
// `observed` outside the support answers `0`.
fn hypergeometric_pmf(population: u64, successes: u64, draws: u64, observed: u64) -> (f64, err) {
    if successes > population || draws > population { ret (0.0f64, Invalid) }
    var low = 0u64
    if draws > population - successes { low = draws - (population - successes) }
    var high = draws
    if successes < high { high = successes }
    if observed < low || observed > high { ret (0.0f64, ok) }
    ret (math.exp[f64](log_binomial(successes, observed) + log_binomial(population - successes, draws - observed) - log_binomial(population, draws)), ok)
}

// P[X <= observed] over the same model; past the support edge this is
// exactly `1` (below it, `0`).
fn hypergeometric_cdf(population: u64, successes: u64, draws: u64, observed: u64) -> (f64, err) {
    if successes > population || draws > population { ret (0.0f64, Invalid) }
    var low = 0u64
    if draws > population - successes { low = draws - (population - successes) }
    var high = draws
    if successes < high { high = successes }
    if observed >= high { ret (1.0f64, ok) }
    var total = 0.0f64
    var k = low
    while k <= observed {
        let (point, point_error) = hypergeometric_pmf(population, successes, draws, k)
        if point_error != ok { ret (0.0f64, point_error) }
        total += point
        if k == 18446744073709551615u64 { ret (total, ok) }
        k += 1u64
    }
    ret (total, ok)
}

// P[X >= observed] over the same model, summed upward from `observed` so the
// tail of interest keeps its digits; below the support edge this is exactly
// `1` (past it, `0`).
fn hypergeometric_sf(population: u64, successes: u64, draws: u64, observed: u64) -> (f64, err) {
    if successes > population || draws > population { ret (0.0f64, Invalid) }
    var low = 0u64
    if draws > population - successes { low = draws - (population - successes) }
    var high = draws
    if successes < high { high = successes }
    if observed <= low { ret (1.0f64, ok) }
    var total = 0.0f64
    var k = observed
    while k <= high {
        let (point, point_error) = hypergeometric_pmf(population, successes, draws, k)
        if point_error != ok { ret (0.0f64, point_error) }
        total += point
        if k == 18446744073709551615u64 { ret (total, ok) }
        k += 1u64
    }
    ret (total, ok)
}
// `estimate` is the statistic of the full sample; the bias-corrected value is
// `estimate - bias`.
type Jackknife = struct { estimate: f64, bias: f64, standard_error: f64 }
type RankKey = struct { values: []const f64 }

fn sum_plain(values: []const f64) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < values.len {
        total += values[i]
        i += 1usize
    }
    ret total
}

// The mean by Neumaier's compensated sum: the rounding error of every addition
// is carried separately and folded in at the end.
fn mean_compensated(values: []const f64) -> (f64, bool) {
    if values.len == 0usize { ret (0.0f64, false) }
    var total = 0.0f64
    var compensation = 0.0f64
    var i = 0usize
    while i < values.len {
        let x = values[i]
        let t = total + x
        if math.abs[f64](total) >= math.abs[f64](x) {
            compensation += (total - t) + x
        } else {
            compensation += (x - t) + total
        }
        total = t
        i += 1usize
    }
    ret ((total + compensation) / f64(values.len), true)
}

// numpy's `_lerp`: the form that is exact at both ends.
fn lerp(a: f64, b: f64, t: f64) -> f64 {
    if t >= 0.5f64 { ret b - (b - a) * (1.0f64 - t) }
    ret a + (b - a) * t
}

// The `p`-quantile (0 <= p <= 1) of an ascending sample; `false` when the sample
// is empty or `p` is out of range. Bit-for-bit numpy's `quantile(method=...)`.
fn quantile(sorted: []const f64, p: f64, method: QuantileMethod) -> (f64, bool) {
    let n = sorted.len
    if n == 0usize || !(p >= 0.0f64 && p <= 1.0f64) { ret (0.0f64, false) }
    let nf = f64(n)
    let last = n - 1usize
    if method == .Nearest {
        let k = math.round[f64]((nf - 1.0f64) * p)
        ret (sorted[usize(k)], true)
    }
    if method == .R1 || method == .R3 {
        var index = nf * p - 1.0f64
        if method == .R3 { index -= 0.5f64 }
        let previous = math.floor[f64](index)
        var chosen = previous + 1.0f64
        if index == previous {
            if method == .R1 { chosen = previous }
            // R3 keeps the previous only when it is odd (zero-based), which is
            // the even order statistic of the paper.
            if method == .R3 && previous >= 0.0f64 && i64(previous) % 2i64 == 1i64 { chosen = previous }
        }
        if chosen < 0.0f64 { chosen = 0.0f64 }
        if chosen > f64(last) { chosen = f64(last) }
        ret (sorted[usize(chosen)], true)
    }
    var virtual = 0.0f64
    var alpha = 1.0f64
    var beta = 1.0f64
    if method == .R4 { alpha = 0.0f64 }
    if method == .R5 {
        alpha = 0.5f64
        beta = 0.5f64
    }
    if method == .R6 {
        alpha = 0.0f64
        beta = 0.0f64
    }
    if method == .R8 {
        alpha = 1.0f64 / 3.0f64
        beta = alpha
    }
    if method == .R9 {
        alpha = 0.375f64
        beta = 0.375f64
    }
    if method == .R7 {
        virtual = (nf - 1.0f64) * p
    } else if method == .R2 {
        virtual = nf * p - 1.0f64
    } else {
        virtual = nf * p + (alpha + p * (1.0f64 - alpha - beta)) - 1.0f64
    }
    let previous = math.floor[f64](virtual)
    var gamma = virtual - previous
    if method == .R2 {
        gamma = 1.0f64
        if virtual == previous { gamma = 0.5f64 }
    }
    var lo = 0usize
    var hi = 0usize
    if virtual >= nf - 1.0f64 {
        lo = last
        hi = last
    } else if virtual >= 0.0f64 {
        lo = usize(previous)
        hi = lo + 1usize
    }
    ret (lerp(sorted[lo], sorted[hi], gamma), true)
}

// Central moments about the mean with divisor n: (mean, m2, m3, m4).
fn central_moments(values: []const f64) -> (f64, f64, f64, f64) {
    let n = f64(values.len)
    let mu = sum_plain(values) / n
    var m2 = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    var i = 0usize
    while i < values.len {
        let d = values[i] - mu
        let d2 = d * d
        m2 += d2
        m3 += d2 * d
        m4 += d2 * d2
        i += 1usize
    }
    ret (mu, m2 / n, m3 / n, m4 / n)
}

// The sample-adjusted skewness G1 (`scipy.stats.skew(bias=False)`); needs three
// values and some spread.
fn skewness(values: []const f64) -> (f64, bool) {
    if values.len < 3usize { ret (0.0f64, false) }
    let (_, m2, m3, _) = central_moments(values)
    if m2 == 0.0f64 { ret (0.0f64, false) }
    let n = f64(values.len)
    let g1 = m3 / math.pow[f64](m2, 1.5f64)
    ret (g1 * math.sqrt[f64](n * (n - 1.0f64)) / (n - 2.0f64), true)
}

// The sample-adjusted excess kurtosis G2 (`scipy.stats.kurtosis(bias=False)`);
// needs four values and some spread.
fn kurtosis(values: []const f64) -> (f64, bool) {
    if values.len < 4usize { ret (0.0f64, false) }
    let (_, m2, _, m4) = central_moments(values)
    if m2 == 0.0f64 { ret (0.0f64, false) }
    let n = f64(values.len)
    let g2 = m4 / (m2 * m2) - 3.0f64
    ret (((n + 1.0f64) * g2 + 6.0f64) * (n - 1.0f64) / ((n - 2.0f64) * (n - 3.0f64)), true)
}

// Shannon entropy in nats of a weight vector that is normalised first, so counts
// and probabilities both serve; zero weights contribute nothing. `false` for an
// empty, negative or all-zero vector.
fn entropy(weights: []const f64) -> (f64, bool) {
    var total = 0.0f64
    var i = 0usize
    while i < weights.len {
        if weights[i] < 0.0f64 { ret (0.0f64, false) }
        total += weights[i]
        i += 1usize
    }
    if total <= 0.0f64 { ret (0.0f64, false) }
    var h = 0.0f64
    i = 0usize
    while i < weights.len {
        if weights[i] > 0.0f64 {
            let p = weights[i] / total
            h -= p * math.log[f64](p)
        }
        i += 1usize
    }
    ret (h, true)
}

// Shannon entropy in bits of a histogram of counts (a 256-bin byte histogram
// answers between 0 and 8).
fn entropy_counts(counts: []const u64) -> (f64, bool) {
    var total = 0u64
    var i = 0usize
    while i < counts.len {
        total += counts[i]
        i += 1usize
    }
    if total == 0u64 { ret (0.0f64, false) }
    var h = 0.0f64
    i = 0usize
    while i < counts.len {
        if counts[i] != 0u64 {
            let p = f64(counts[i]) / f64(total)
            h -= p * math.log2[f64](p)
        }
        i += 1usize
    }
    ret (h, true)
}

// Column means and the centred cross products of a row-major `n x columns` matrix
// into `out` (`columns x columns`), divided by `divisor`.
fn cross_products(rows: []const f64, columns: usize, out: []f64, divisor: f64) -> err {
    if columns == 0usize || rows.len % columns != 0usize { ret Invalid }
    if out.len < columns * columns { ret TooSmall }
    let n = rows.len / columns
    var j = 0usize
    while j < columns {
        var k = 0usize
        while k < columns {
            out[j * columns + k] = 0.0f64
            k += 1usize
        }
        // The diagonal holds the column mean while it is being formed.
        var total = 0.0f64
        var i = 0usize
        while i < n {
            total += rows[i * columns + j]
            i += 1usize
        }
        out[j * columns + j] = total / f64(n)
        j += 1usize
    }
    var i = 0usize
    while i < n {
        j = 0usize
        while j < columns {
            let dj = rows[i * columns + j] - out[j * columns + j]
            var k = j + 1usize
            while k < columns {
                let dk = rows[i * columns + k] - out[k * columns + k]
                out[j * columns + k] += dj * dk
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < columns {
        let mu = out[j * columns + j]
        var total = 0.0f64
        i = 0usize
        while i < n {
            let d = rows[i * columns + j] - mu
            total += d * d
            i += 1usize
        }
        out[j * columns + j] = total / divisor
        var k = j + 1usize
        while k < columns {
            out[j * columns + k] = out[j * columns + k] / divisor
            out[k * columns + j] = out[j * columns + k]
            k += 1usize
        }
        j += 1usize
    }
    ret ok
}

// The sample covariance (divisor n - 1) of the columns of a row-major matrix
// with `columns` columns; `out` receives `columns x columns`. `numpy.cov(rowvar=False)`.
fn covariance_matrix(rows: []const f64, columns: usize, out: []f64) -> err {
    if columns == 0usize || rows.len < 2usize * columns { ret Invalid }
    ret cross_products(rows, columns, out, f64(rows.len / columns) - 1.0f64)
}

// Ledoit-Wolf (2004) shrinkage of the biased covariance (divisor n) toward the
// scaled identity, as `sklearn.covariance.ledoit_wolf`; answers the shrinkage
// weight and leaves the shrunk matrix in `out`.
fn covariance_shrink(rows: []const f64, columns: usize, out: []f64) -> (f64, err) {
    if columns == 0usize || rows.len < columns || rows.len % columns != 0usize { ret (0.0f64, Invalid) }
    if out.len < columns * columns { ret (0.0f64, TooSmall) }
    let n = rows.len / columns
    let p = f64(columns)
    // The column means sit in the first row of `out` until the covariance
    // overwrites them, so the centred row norms need no scratch.
    var j = 0usize
    while j < columns {
        var total = 0.0f64
        var i = 0usize
        while i < n {
            total += rows[i * columns + j]
            i += 1usize
        }
        out[j] = total / f64(n)
        j += 1usize
    }
    // Sum over samples of the squared norm of the centred row, squared: the
    // <X2.T, X2> total of the reference.
    var beta_sum = 0.0f64
    var i = 0usize
    while i < n {
        var norm2 = 0.0f64
        j = 0usize
        while j < columns {
            let d = rows[i * columns + j] - out[j]
            norm2 += d * d
            j += 1usize
        }
        beta_sum += norm2 * norm2
        i += 1usize
    }
    let e = cross_products(rows, columns, out, f64(n))
    if e != ok { ret (0.0f64, e) }
    if columns == 1usize { ret (0.0f64, ok) }
    var trace = 0.0f64
    var delta_sum = 0.0f64
    j = 0usize
    while j < columns {
        trace += out[j * columns + j]
        var k = 0usize
        while k < columns {
            let c = out[j * columns + k]
            delta_sum += c * c
            k += 1usize
        }
        j += 1usize
    }
    let mu = trace / p
    var beta = (beta_sum / f64(n) - delta_sum) / (p * f64(n))
    let delta = (delta_sum - 2.0f64 * mu * trace + p * mu * mu) / p
    if delta < beta { beta = delta }
    var shrinkage = 0.0f64
    if beta != 0.0f64 { shrinkage = beta / delta }
    j = 0usize
    while j < columns * columns {
        out[j] = (1.0f64 - shrinkage) * out[j]
        j += 1usize
    }
    j = 0usize
    while j < columns {
        out[j * columns + j] += shrinkage * mu
        j += 1usize
    }
    ret (shrinkage, ok)
}

// Pearson's r of two equal-length samples; `false` below two points or without
// spread in either.
fn correlation_pearson(x: []const f64, y: []const f64) -> (f64, bool) {
    let n = x.len
    if n < 2usize || y.len != n { ret (0.0f64, false) }
    let mean_x = sum_plain(x) / f64(n)
    let mean_y = sum_plain(y) / f64(n)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < n {
        let dx = x[i] - mean_x
        let dy = y[i] - mean_y
        sxy += dx * dy
        sxx += dx * dx
        syy += dy * dy
        i += 1usize
    }
    if sxx == 0.0f64 || syy == 0.0f64 { ret (0.0f64, false) }
    ret (sxy / math.sqrt[f64](sxx * syy), true)
}

fn compare_by_value(k: *RankKey, a: usize, b: usize) -> i32 {
    if k.values[a] < k.values[b] { ret 0i32 - 1i32 }
    if k.values[a] > k.values[b] { ret 1i32 }
    ret 0i32
}

fn compare_floats(k: *RankKey, a: f64, b: f64) -> i32 {
    if a < b { ret 0i32 - 1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

// One-based ranks with ties averaged (`scipy.stats.rankdata`); `order` is
// scratch for the sort.
fn rank(values: []const f64, out: []f64, order: []usize) -> err {
    let n = values.len
    if out.len < n || order.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    var k = RankKey { values: values }
    sort.in_place_by[usize, RankKey](order[..n], &k, compare_by_value)
    i = 0usize
    while i < n {
        var j = i
        while j + 1usize < n && values[order[j + 1usize]] == values[order[i]] { j += 1usize }
        let average = (f64(i) + f64(j)) / 2.0f64 + 1.0f64
        var m = i
        while m <= j {
            out[order[m]] = average
            m += 1usize
        }
        i = j + 1usize
    }
    ret ok
}

// Spearman's rho: Pearson's r over average ranks. `scratch` holds `2 * x.len`
// floats and `order` `x.len` indices.
fn correlation_spearman(x: []const f64, y: []const f64, scratch: []f64, order: []usize) -> (f64, err) {
    let n = x.len
    if n < 2usize || y.len != n { ret (0.0f64, Invalid) }
    if scratch.len < 2usize * n { ret (0.0f64, TooSmall) }
    let e1 = rank(x, scratch[..n], order)
    if e1 != ok { ret (0.0f64, e1) }
    let e2 = rank(y, scratch[n..2usize * n], order)
    if e2 != ok { ret (0.0f64, e2) }
    let (rho, has_rho) = correlation_pearson(scratch[..n], scratch[n..2usize * n])
    if !has_rho { ret (0.0f64, Invalid) }
    ret (rho, ok)
}

// Kendall's tau-b with tie corrections (`scipy.stats.kendalltau`); `false` when
// either sample is constant.
// ponytail: O(n^2) pair walk; Knight's merge-sort inversion count is O(n log n).
fn correlation_kendall(x: []const f64, y: []const f64) -> (f64, bool) {
    let n = x.len
    if n < 2usize || y.len != n { ret (0.0f64, false) }
    var concordant = 0.0f64
    var discordant = 0.0f64
    var tied_x = 0.0f64
    var tied_y = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let dx = x[i] - x[j]
            let dy = y[i] - y[j]
            if dx == 0.0f64 { tied_x += 1.0f64 }
            if dy == 0.0f64 { tied_y += 1.0f64 }
            if dx != 0.0f64 && dy != 0.0f64 {
                if (dx > 0.0f64) == (dy > 0.0f64) { concordant += 1.0f64 } else { discordant += 1.0f64 }
            }
            j += 1usize
        }
        i += 1usize
    }
    let pairs = f64(n) * f64(n - 1usize) / 2.0f64
    let denominator = (pairs - tied_x) * (pairs - tied_y)
    if denominator <= 0.0f64 { ret (0.0f64, false) }
    ret ((concordant - discordant) / math.sqrt[f64](denominator), true)
}

// A rule-of-thumb Gaussian bandwidth scaled by the sample standard deviation:
// Scott's n^(-1/5) or Silverman's (3n/4)^(-1/5), the one-dimensional factors of
// `scipy.stats.gaussian_kde`. `false` below two values or without spread.
fn kde_bandwidth(values: []const f64, rule: Bandwidth) -> (f64, bool) {
    let n = values.len
    if n < 2usize { ret (0.0f64, false) }
    let (_, m2, _, _) = central_moments(values)
    if m2 == 0.0f64 { ret (0.0f64, false) }
    let sd = math.sqrt[f64](m2 * f64(n) / (f64(n) - 1.0f64))
    var base = f64(n)
    if rule == .Silverman { base = f64(n) * 0.75f64 }
    ret (sd * math.pow[f64](base, 0.0f64 - 0.2f64), true)
}

// The Gaussian kernel density estimate of `values` at each of `points`.
fn kde(values: []const f64, bandwidth: f64, points: []const f64, out: []f64) -> err {
    if values.len == 0usize || !(bandwidth > 0.0f64) { ret Invalid }
    if out.len < points.len { ret TooSmall }
    let scale = 1.0f64 / (f64(values.len) * bandwidth * 2.5066282746310002f64)
    var q = 0usize
    while q < points.len {
        var total = 0.0f64
        var i = 0usize
        while i < values.len {
            let u = (points[q] - values[i]) / bandwidth
            total += math.exp[f64](0.0f64 - 0.5f64 * u * u)
            i += 1usize
        }
        out[q] = total * scale
        q += 1usize
    }
    ret ok
}

// Product-Gaussian density on a caller-owned row-major (y, x) grid.
// The two bandwidths are explicit; callers choose domain and grid spacing.
fn kde2d(x: []const f64, y: []const f64, bandwidth_x: f64, bandwidth_y: f64, grid_x: []const f64, grid_y: []const f64, out: []f64) -> err {
    if x.len == 0usize || x.len != y.len || grid_x.len == 0usize || grid_y.len == 0usize || !(bandwidth_x > 0.0f64) || !(bandwidth_y > 0.0f64) { ret Invalid }
    if grid_x.len > out.len / grid_y.len { ret TooSmall }
    let scale = 1.0f64 / (f64(x.len) * 6.283185307179586f64 * bandwidth_x * bandwidth_y)
    if !(scale > 0.0f64) || scale != scale || scale - scale != 0.0f64 { ret Invalid }
    var i = 0usize
    while i < x.len {
        if x[i] != x[i] || x[i] - x[i] != 0.0f64 || y[i] != y[i] || y[i] - y[i] != 0.0f64 { ret Invalid }
        i += 1usize
    }
    var row = 0usize
    while row < grid_y.len {
        if grid_y[row] != grid_y[row] || grid_y[row] - grid_y[row] != 0.0f64 { ret Invalid }
        var column = 0usize
        while column < grid_x.len {
            if grid_x[column] != grid_x[column] || grid_x[column] - grid_x[column] != 0.0f64 { ret Invalid }
            var sum = 0.0f64
            i = 0usize
            while i < x.len {
                let dx = (grid_x[column] - x[i]) / bandwidth_x
                let dy = (grid_y[row] - y[i]) / bandwidth_y
                sum += math.exp[f64](0.0f64 - 0.5f64 * (dx * dx + dy * dy))
                i += 1usize
            }
            out[row * grid_x.len + column] = sum * scale
            column += 1usize
        }
        row += 1usize
    }
    ret ok
}

// The bootstrap percentile interval of `statistic` at `confidence` (0 < c < 1)
// over `rounds` resamples drawn with `r`. `sample` holds `values.len` floats and
// `stats` `rounds` floats; `stats` is left sorted.
fn bootstrap[Ctx: type](r: *rand.Pcg64, values: []const f64, ctx: *Ctx, statistic: fn(*Ctx, []const f64) -> f64, rounds: usize, confidence: f64, sample: []f64, stats: []f64) -> (Interval, err) {
    let n = values.len
    var interval: Interval = zero
    if n == 0usize || rounds < 2usize || !(confidence > 0.0f64 && confidence < 1.0f64) { ret (interval, Invalid) }
    if sample.len < n || stats.len < rounds { ret (interval, TooSmall) }
    var k = 0usize
    while k < rounds {
        var i = 0usize
        while i < n {
            sample[i] = values[usize(rand.pcg64_bounded(r, u64(n)))]
            i += 1usize
        }
        stats[k] = statistic(ctx, sample[..n])
        k += 1usize
    }
    var key = RankKey { values: values }
    sort.in_place_by[f64, RankKey](stats[..rounds], &key, compare_floats)
    let (low, _) = quantile(stats[..rounds], (1.0f64 - confidence) / 2.0f64, .R7)
    let (high, _) = quantile(stats[..rounds], (1.0f64 + confidence) / 2.0f64, .R7)
    interval.low = low
    interval.high = high
    ret (interval, ok)
}

// The leave-one-out jackknife of `statistic`: its bias and standard error.
// `scratch` holds `values.len - 1` floats.
fn jackknife[Ctx: type](values: []const f64, ctx: *Ctx, statistic: fn(*Ctx, []const f64) -> f64, scratch: []f64) -> (Jackknife, err) {
    let n = values.len
    var result: Jackknife = zero
    if n < 2usize { ret (result, Invalid) }
    if scratch.len + 1usize < n { ret (result, TooSmall) }
    result.estimate = statistic(ctx, values)
    var total = 0.0f64
    var total_squares = 0.0f64
    var leave = 0usize
    while leave < n {
        var i = 0usize
        var j = 0usize
        while i < n {
            if i != leave {
                scratch[j] = values[i]
                j += 1usize
            }
            i += 1usize
        }
        let theta = statistic(ctx, scratch[..n - 1usize])
        total += theta
        total_squares += theta * theta
        leave += 1usize
    }
    let nf = f64(n)
    let mean_theta = total / nf
    result.bias = (nf - 1.0f64) * (mean_theta - result.estimate)
    var spread = total_squares / nf - mean_theta * mean_theta
    if spread < 0.0f64 { spread = 0.0f64 }
    result.standard_error = math.sqrt[f64]((nf - 1.0f64) * spread)
    ret (result, ok)
}

// The Wilson score interval for `successes` of `trials` at `confidence`.
fn interval_wilson(successes: u64, trials: u64, confidence: f64) -> (Interval, err) {
    var interval: Interval = zero
    if trials == 0u64 || successes > trials || !(confidence > 0.0f64 && confidence < 1.0f64) { ret (interval, Invalid) }
    let z = special.normal_quantile((1.0f64 + confidence) / 2.0f64)
    let n = f64(trials)
    let p = f64(successes) / n
    let z2 = z * z
    let centre = (p + z2 / (2.0f64 * n)) / (1.0f64 + z2 / n)
    let half = z * math.sqrt[f64](p * (1.0f64 - p) / n + z2 / (4.0f64 * n * n)) / (1.0f64 + z2 / n)
    interval.low = centre - half
    interval.high = centre + half
    ret (interval, ok)
}

// The beta distribution quantile by bisection on the regularised incomplete beta.
fn beta_quantile(p: f64, a: f64, b: f64) -> f64 {
    if p <= 0.0f64 { ret 0.0f64 }
    if p >= 1.0f64 { ret 1.0f64 }
    var lo = 0.0f64
    var hi = 1.0f64
    var i = 0usize
    while i < 200usize && hi - lo > 1.0e-16f64 {
        let mid = (lo + hi) / 2.0f64
        if special.beta_i(a, b, mid) < p { lo = mid } else { hi = mid }
        i += 1usize
    }
    ret (lo + hi) / 2.0f64
}

// The Clopper-Pearson exact interval for `successes` of `trials` at `confidence`.
fn interval_clopper_pearson(successes: u64, trials: u64, confidence: f64) -> (Interval, err) {
    var interval: Interval = zero
    if trials == 0u64 || successes > trials || !(confidence > 0.0f64 && confidence < 1.0f64) { ret (interval, Invalid) }
    let tail = (1.0f64 - confidence) / 2.0f64
    let k = f64(successes)
    let n = f64(trials)
    if successes > 0u64 { interval.low = beta_quantile(tail, k, n - k + 1.0f64) }
    interval.high = 1.0f64
    if successes < trials { interval.high = beta_quantile(1.0f64 - tail, k + 1.0f64, n - k) }
    ret (interval, ok)
}

// Historical value at risk: the `level`-quantile (R-7) of ascending losses.
fn value_at_risk(sorted: []const f64, level: f64) -> (f64, bool) {
    let (v, has_v) = quantile(sorted, level, .R7)
    ret (v, has_v)
}

// Expected shortfall (CVaR): the mean of the largest `n - floor(level * n)`
// ascending losses; `false` when that tail is empty.
fn expected_shortfall(sorted: []const f64, level: f64) -> (f64, bool) {
    let n = sorted.len
    if n == 0usize || !(level >= 0.0f64 && level < 1.0f64) { ret (0.0f64, false) }
    let first = usize(math.floor[f64](level * f64(n)))
    if first >= n { ret (0.0f64, false) }
    ret (sum_plain(sorted[first..]) / f64(n - first), true)
}

// Method of moments: mean and population variance matched to the distribution's.
fn fit_moments(values: []const f64, distribution: Distribution) -> (Fit, err) {
    var fit: Fit = zero
    if values.len < 2usize { ret (fit, Invalid) }
    let (mu, m2, _, _) = central_moments(values)
    if distribution == .Normal {
        fit.a = mu
        fit.b = math.sqrt[f64](m2)
        ret (fit, ok)
    }
    if distribution == .Exponential {
        if mu <= 0.0f64 { ret (fit, Invalid) }
        fit.a = 1.0f64 / mu
        ret (fit, ok)
    }
    if m2 == 0.0f64 { ret (fit, Invalid) }
    if distribution == .Gamma {
        if mu <= 0.0f64 { ret (fit, Invalid) }
        fit.a = mu * mu / m2
        fit.b = m2 / mu
        ret (fit, ok)
    }
    if mu <= 0.0f64 || mu >= 1.0f64 { ret (fit, Invalid) }
    let common = mu * (1.0f64 - mu) / m2 - 1.0f64
    if common <= 0.0f64 { ret (fit, Invalid) }
    fit.a = mu * common
    fit.b = (1.0f64 - mu) * common
    ret (fit, ok)
}

// psi(x) for x > 0: the recurrence up to 10, then the asymptotic series.
fn digamma(x: f64) -> f64 {
    if !(x > 0.0f64) { ret special.nan() }
    var result = 0.0f64
    var t = x
    while t < 10.0f64 {
        result -= 1.0f64 / t
        t += 1.0f64
    }
    let r = 1.0f64 / (t * t)
    result += math.log[f64](t) - 0.5f64 / t
    result -= r * (1.0f64 / 12.0f64 - r * (1.0f64 / 120.0f64 - r * (1.0f64 / 252.0f64 - r * (1.0f64 / 240.0f64 - r * (1.0f64 / 132.0f64 - r * 691.0f64 / 32760.0f64)))))
    ret result
}

// psi'(x) for x > 0, by the same recurrence and series.
fn trigamma(x: f64) -> f64 {
    if !(x > 0.0f64) { ret special.nan() }
    var result = 0.0f64
    var t = x
    while t < 10.0f64 {
        result += 1.0f64 / (t * t)
        t += 1.0f64
    }
    let r = 1.0f64 / (t * t)
    result += 1.0f64 / t + 0.5f64 * r
    result += r / t * (1.0f64 / 6.0f64 - r * (1.0f64 / 30.0f64 - r * (1.0f64 / 42.0f64 - r * (1.0f64 / 30.0f64 - r * (5.0f64 / 66.0f64 - r * 691.0f64 / 2730.0f64)))))
    ret result
}

// Maximum likelihood: closed forms for the normal and exponential, Newton on
// the digamma equation for the gamma shape, and a two-dimensional Newton from
// the moment estimate for the beta shapes.
fn fit_mle(values: []const f64, distribution: Distribution) -> (Fit, err) {
    let (start, e) = fit_moments(values, distribution)
    if e != ok || distribution == .Normal || distribution == .Exponential { ret (start, e) }
    var fit = start
    let n = f64(values.len)
    var log_sum = 0.0f64
    var log_complement = 0.0f64
    var i = 0usize
    while i < values.len {
        let x = values[i]
        if x <= 0.0f64 || (distribution == .Beta && x >= 1.0f64) { ret (start, Invalid) }
        log_sum += math.log[f64](x)
        if distribution == .Beta { log_complement += math.log[f64](1.0f64 - x) }
        i += 1usize
    }
    if distribution == .Gamma {
        let mu = sum_plain(values) / n
        let s = math.log[f64](mu) - log_sum / n
        if !(s > 0.0f64) { ret (start, Invalid) }
        var k = (3.0f64 - s + math.sqrt[f64]((s - 3.0f64) * (s - 3.0f64) + 24.0f64 * s)) / (12.0f64 * s)
        var round = 0usize
        while round < 100usize {
            let step = (math.log[f64](k) - digamma(k) - s) / (1.0f64 / k - trigamma(k))
            k -= step
            if k <= 0.0f64 { k = 1.0e-8f64 }
            round += 1usize
            if math.abs[f64](step) < 1.0e-13f64 * k { round = 100usize }
        }
        fit.a = k
        fit.b = mu / k
        ret (fit, ok)
    }
    let l1 = log_sum / n
    let l2 = log_complement / n
    var round = 0usize
    while round < 100usize {
        let both = digamma(fit.a + fit.b)
        let g1 = both - digamma(fit.a) + l1
        let g2 = both - digamma(fit.b) + l2
        let h12 = trigamma(fit.a + fit.b)
        let h11 = h12 - trigamma(fit.a)
        let h22 = h12 - trigamma(fit.b)
        let determinant = h11 * h22 - h12 * h12
        if determinant == 0.0f64 { ret (start, Invalid) }
        var step_a = (h22 * g1 - h12 * g2) / determinant
        var step_b = (h11 * g2 - h12 * g1) / determinant
        while fit.a - step_a <= 0.0f64 || fit.b - step_b <= 0.0f64 {
            step_a = step_a / 2.0f64
            step_b = step_b / 2.0f64
        }
        fit.a -= step_a
        fit.b -= step_b
        round += 1usize
        if math.abs[f64](step_a) < 1.0e-13f64 * fit.a && math.abs[f64](step_b) < 1.0e-13f64 * fit.b { round = 100usize }
    }
    ret (fit, ok)
}

// Balanced crossed random-effects Gage R&R: every operator measures every
// part the same number of times. Variance components are nonnegative method-
// of-moments estimates; a nonsignificant interaction is pooled into error.
type GageRrMeanSquares = struct { part: f64, operator: f64, interaction: f64, repeatability: f64 }
type GageRrComponents = struct { repeatability: f64, operator: f64, interaction: f64, part: f64, gage: f64, total: f64 }
type GageRrWork = struct { part_means: []f64, operator_means: []f64, cell_means: []f64 }
type GageRrSummary = struct { mean_squares: GageRrMeanSquares, components: GageRrComponents, interaction_p: f64, interaction_included: bool }

fn gage_finite(value: f64) -> bool {
    ret value == value && value - value == 0.0f64
}

// Measurements are part-major, operator-major, then replicate-major.
// Centering the sum on the first observation avoids overflow for large offsets.
fn gage_run_summary(values: []const f64, parts: usize, operators: usize, repeats: usize) -> (GageRunSummary, err) {
    if parts < 2usize || operators < 2usize || repeats < 2usize || values.len == 0usize { ret (zero, Invalid) }
    if parts > values.len / operators { ret (zero, Invalid) }
    let cells = parts * operators
    if repeats > values.len / cells || cells * repeats != values.len { ret (zero, Invalid) }
    let baseline = values[0usize]
    if !gage_finite(baseline) { ret (zero, Invalid) }
    var minimum = baseline
    var maximum = baseline
    var max_range = 0.0f64
    var centered_sum = 0.0f64
    var cell = 0usize
    while cell < cells {
        var cell_min = values[cell * repeats]
        var cell_max = cell_min
        var trial = 0usize
        while trial < repeats {
            let value = values[cell * repeats + trial]
            if !gage_finite(value) { ret (zero, Invalid) }
            if value < minimum { minimum = value }
            if value > maximum { maximum = value }
            if value < cell_min { cell_min = value }
            if value > cell_max { cell_max = value }
            centered_sum += value - baseline
            trial += 1usize
        }
        let cell_range = cell_max - cell_min
        if !gage_finite(cell_range) || !gage_finite(centered_sum) { ret (zero, Invalid) }
        if cell_range > max_range { max_range = cell_range }
        cell += 1usize
    }
    let grand_mean = baseline + centered_sum / f64(values.len)
    if !gage_finite(grand_mean) || !gage_finite(maximum - minimum) { ret (zero, Invalid) }
    ret (GageRunSummary {
        parts: parts, operators: operators, repeats: repeats,
        grand_mean: grand_mean, minimum: minimum, maximum: maximum,
        max_repeat_range: max_range,
    }, ok)
}

// Exact categorical counts, row-major cells, and both marginal totals.
fn cross_tabulate(row_ids: []const usize, column_ids: []const usize, rows: usize, columns: usize, cells: []u64, row_totals: []u64, column_totals: []u64) -> (CrossTabSummary, err) {
    if rows == 0usize || columns == 0usize || row_ids.len == 0usize || row_ids.len != column_ids.len { ret (zero, Invalid) }
    if rows > cells.len / columns || row_totals.len < rows || column_totals.len < columns { ret (zero, TooSmall) }
    var i = 0usize
    while i < row_ids.len {
        if row_ids[i] >= rows || column_ids[i] >= columns { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < rows * columns {
        cells[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < rows {
        row_totals[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < columns {
        column_totals[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < row_ids.len {
        let row = row_ids[i]
        let column = column_ids[i]
        cells[row * columns + column] += 1u64
        row_totals[row] += 1u64
        column_totals[column] += 1u64
        i += 1usize
    }
    ret (CrossTabSummary { rows: rows, columns: columns, total: u64(row_ids.len) }, ok)
}

// Numeric matrix aggregation distinguishes an absent cell from an observed zero.
fn matrix_aggregate(row_ids: []const usize, column_ids: []const usize, values: []const f64, present: []const bool, rows: usize, columns: usize, cells: []ReportAggregate, row_totals: []ReportAggregate, column_totals: []ReportAggregate) -> (ReportAggregate, err) {
    if rows == 0usize || columns == 0usize || row_ids.len == 0usize || row_ids.len != column_ids.len || row_ids.len != values.len || row_ids.len != present.len { ret (zero, Invalid) }
    if rows > cells.len / columns || row_totals.len < rows || column_totals.len < columns { ret (zero, TooSmall) }
    var i = 0usize
    while i < row_ids.len {
        if row_ids[i] >= rows || column_ids[i] >= columns || (present[i] && !gage_finite(values[i])) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < rows * columns {
        cells[i] = ReportAggregate { sum: 0.0f64, count: 0usize }
        i += 1usize
    }
    i = 0usize
    while i < rows {
        row_totals[i] = ReportAggregate { sum: 0.0f64, count: 0usize }
        i += 1usize
    }
    i = 0usize
    while i < columns {
        column_totals[i] = ReportAggregate { sum: 0.0f64, count: 0usize }
        i += 1usize
    }
    var grand: ReportAggregate = zero
    i = 0usize
    while i < row_ids.len {
        if present[i] {
            let row = row_ids[i]
            let column = column_ids[i]
            let index = row * columns + column
            cells[index].sum += values[i]
            cells[index].count += 1usize
            row_totals[row].sum += values[i]
            row_totals[row].count += 1usize
            column_totals[column].sum += values[i]
            column_totals[column].count += 1usize
            grand.sum += values[i]
            grand.count += 1usize
            if !gage_finite(cells[index].sum) || !gage_finite(row_totals[row].sum) || !gage_finite(column_totals[column].sum) || !gage_finite(grand.sum) { ret (zero, Invalid) }
        }
        i += 1usize
    }
    ret (grand, ok)
}

fn gage_rr_variance_components(parts: usize, operators: usize, repeats: usize, means: *const GageRrMeanSquares, include_interaction: bool) -> (GageRrComponents, err) {
    if parts < 2usize || operators < 2usize || repeats < 2usize || !gage_finite(means.part) || !gage_finite(means.operator) || !gage_finite(means.interaction) || !gage_finite(means.repeatability) || means.part < 0.0f64 || means.operator < 0.0f64 || means.interaction < 0.0f64 || means.repeatability < 0.0f64 { ret (zero, Invalid) }
    var components = GageRrComponents { repeatability: means.repeatability, operator: 0.0f64, interaction: 0.0f64, part: 0.0f64, gage: 0.0f64, total: 0.0f64 }
    if include_interaction {
        components.operator = math.max[f64]((means.operator - means.interaction) / (f64(parts) * f64(repeats)), 0.0f64)
        components.interaction = math.max[f64]((means.interaction - means.repeatability) / f64(repeats), 0.0f64)
        components.part = math.max[f64]((means.part - means.interaction) / (f64(operators) * f64(repeats)), 0.0f64)
    } else {
        components.operator = math.max[f64]((means.operator - means.repeatability) / (f64(parts) * f64(repeats)), 0.0f64)
        components.part = math.max[f64]((means.part - means.repeatability) / (f64(operators) * f64(repeats)), 0.0f64)
    }
    components.gage = components.repeatability + components.operator + components.interaction
    components.total = components.gage + components.part
    if !gage_finite(components.gage) || !gage_finite(components.total) { ret (zero, Invalid) }
    ret (components, ok)
}

// `values` are part-major, then operator-major, then replicate-major.
// Work slices hold centered cell, part and operator sums, then their means.
fn gage_rr_crossed(values: []const f64, parts: usize, operators: usize, repeats: usize, alpha: f64, work: *GageRrWork) -> (GageRrSummary, err) {
    if parts < 2usize || operators < 2usize || repeats < 2usize || values.len == 0usize || !(alpha > 0.0f64 && alpha < 1.0f64) { ret (zero, Invalid) }
    if parts > values.len / operators { ret (zero, Invalid) }
    let cells = parts * operators
    if repeats > values.len / cells || cells * repeats != values.len { ret (zero, Invalid) }
    if work.part_means.len < parts || work.operator_means.len < operators || work.cell_means.len < cells { ret (zero, TooSmall) }
    let baseline = values[0usize]
    if !gage_finite(baseline) { ret (zero, Invalid) }
    var p = 0usize
    while p < parts {
        work.part_means[p] = 0.0f64
        p += 1usize
    }
    var o = 0usize
    while o < operators {
        work.operator_means[o] = 0.0f64
        o += 1usize
    }
    var grand_sum = 0.0f64
    p = 0usize
    while p < parts {
        o = 0usize
        while o < operators {
            let cell = p * operators + o
            var cell_sum = 0.0f64
            var r = 0usize
            while r < repeats {
                let value = values[cell * repeats + r] - baseline
                if !gage_finite(value) { ret (zero, Invalid) }
                cell_sum += value
                r += 1usize
            }
            if !gage_finite(cell_sum) { ret (zero, Invalid) }
            work.cell_means[cell] = cell_sum / f64(repeats)
            work.part_means[p] += cell_sum
            work.operator_means[o] += cell_sum
            grand_sum += cell_sum
            o += 1usize
        }
        p += 1usize
    }
    let grand = grand_sum / f64(values.len)
    if !gage_finite(grand) { ret (zero, Invalid) }
    p = 0usize
    while p < parts {
        work.part_means[p] = work.part_means[p] / (f64(operators) * f64(repeats))
        p += 1usize
    }
    o = 0usize
    while o < operators {
        work.operator_means[o] = work.operator_means[o] / (f64(parts) * f64(repeats))
        o += 1usize
    }
    var ss_part = 0.0f64
    var ss_operator = 0.0f64
    var ss_interaction = 0.0f64
    var ss_repeatability = 0.0f64
    p = 0usize
    while p < parts {
        let part_delta = work.part_means[p] - grand
        ss_part += part_delta * part_delta
        o = 0usize
        while o < operators {
            let cell = p * operators + o
            let interaction_delta = work.cell_means[cell] - work.part_means[p] - work.operator_means[o] + grand
            ss_interaction += interaction_delta * interaction_delta
            var r = 0usize
            while r < repeats {
                let residual = values[cell * repeats + r] - baseline - work.cell_means[cell]
                ss_repeatability += residual * residual
                r += 1usize
            }
            o += 1usize
        }
        p += 1usize
    }
    o = 0usize
    while o < operators {
        let operator_delta = work.operator_means[o] - grand
        ss_operator += operator_delta * operator_delta
        o += 1usize
    }
    ss_part *= f64(operators) * f64(repeats)
    ss_operator *= f64(parts) * f64(repeats)
    ss_interaction *= f64(repeats)
    let df_interaction = f64(parts - 1usize) * f64(operators - 1usize)
    let df_repeatability = f64(cells) * f64(repeats - 1usize)
    let ms_interaction = ss_interaction / df_interaction
    let ms_repeatability = ss_repeatability / df_repeatability
    if !gage_finite(ss_part) || !gage_finite(ss_operator) || !gage_finite(ms_interaction) || !gage_finite(ms_repeatability) { ret (zero, Invalid) }
    var interaction_p = 1.0f64
    if ms_repeatability == 0.0f64 {
        if ms_interaction > 0.0f64 { interaction_p = 0.0f64 }
    } else {
        interaction_p = 1.0f64 - special.f_cdf(ms_interaction / ms_repeatability, df_interaction, df_repeatability)
    }
    if !(interaction_p >= 0.0f64 && interaction_p <= 1.0f64) { ret (zero, Invalid) }
    let include_interaction = interaction_p < alpha
    var means = GageRrMeanSquares { part: ss_part / f64(parts - 1usize), operator: ss_operator / f64(operators - 1usize), interaction: ms_interaction, repeatability: ms_repeatability }
    if !include_interaction { means.repeatability = (ss_interaction + ss_repeatability) / (df_interaction + df_repeatability) }
    let (components, components_error) = gage_rr_variance_components(parts, operators, repeats, &means, include_interaction)
    if components_error != ok { ret (zero, components_error) }
    ret (GageRrSummary { mean_squares: means, components: components, interaction_p: interaction_p, interaction_included: include_interaction }, ok)
}
