// Binary diagnostic-test statistics over a 2x2 table: sensitivity,
// specificity, accuracy, predictive values, likelihood ratios and the
// diagnostic odds ratio, with exact Clopper-Pearson intervals for the
// proportions and log-method intervals for the ratios. A generic
// binary-classification read-out; report grids are out of scope.

use e.math
use e.math.special

type Table = struct { true_pos: u64, false_pos: u64, false_neg: u64, true_neg: u64 }
type Metrics = struct { sensitivity: f64, specificity: f64, accuracy: f64, positive_predictive: f64, negative_predictive: f64, lr_positive: f64, lr_negative: f64, odds_ratio: f64 }
type Interval = struct { low: f64, high: f64 }
type Intervals = struct { sensitivity: Interval, specificity: Interval, accuracy: Interval, positive_predictive: Interval, negative_predictive: Interval, lr_positive: Interval, lr_negative: Interval, odds_ratio: Interval }
error Invalid

// The Clopper-Pearson exact interval for `successes` of `trials` at
// `confidence`, by bisection on the regularised incomplete beta.
fn exact_interval(successes: u64, trials: u64, confidence: f64) -> (Interval, err) {
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

// The beta distribution quantile by bisection on the regularised incomplete
// beta.
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

// The eight metrics of the table; an empty denominator anywhere is `Invalid`.
fn metrics(t: Table) -> (Metrics, err) {
    let diseased = t.true_pos + t.false_neg
    let healthy = t.false_pos + t.true_neg
    let positive = t.true_pos + t.false_pos
    let negative = t.false_neg + t.true_neg
    let n = diseased + healthy
    if diseased == 0u64 || healthy == 0u64 || positive == 0u64 || negative == 0u64 || n == 0u64 { ret (zero, Invalid) }
    let sensitivity = f64(t.true_pos) / f64(diseased)
    let specificity = f64(t.true_neg) / f64(healthy)
    if sensitivity >= 1.0f64 || specificity <= 0.0f64 || sensitivity <= 0.0f64 || specificity >= 1.0f64 { ret (zero, Invalid) }
    if t.false_pos == 0u64 || t.false_neg == 0u64 { ret (zero, Invalid) }
    ret (Metrics {
        sensitivity: sensitivity,
        specificity: specificity,
        accuracy: f64(t.true_pos + t.true_neg) / f64(n),
        positive_predictive: f64(t.true_pos) / f64(positive),
        negative_predictive: f64(t.true_neg) / f64(negative),
        lr_positive: sensitivity / (1.0f64 - specificity),
        lr_negative: (1.0f64 - sensitivity) / specificity,
        odds_ratio: f64(t.true_pos) * f64(t.true_neg) / (f64(t.false_pos) * f64(t.false_neg))
    }, ok)
}

// The matching intervals at `confidence`: exact for the five proportions,
// log-method (1.96 standard errors) for the two likelihood ratios and the
// odds ratio.
fn metrics_ci(t: Table, confidence: f64) -> (Intervals, err) {
    if !(confidence > 0.0f64 && confidence < 1.0f64) { ret (zero, Invalid) }
    let (m, metrics_error) = metrics(t)
    if metrics_error != ok { ret (zero, metrics_error) }
    let diseased = t.true_pos + t.false_neg
    let healthy = t.false_pos + t.true_neg
    let positive = t.true_pos + t.false_pos
    let negative = t.false_neg + t.true_neg
    let n = diseased + healthy
    let (sens, sens_error) = exact_interval(t.true_pos, diseased, confidence)
    if sens_error != ok { ret (zero, sens_error) }
    let (spec, spec_error) = exact_interval(t.true_neg, healthy, confidence)
    if spec_error != ok { ret (zero, spec_error) }
    let (acc, acc_error) = exact_interval(t.true_pos + t.true_neg, n, confidence)
    if acc_error != ok { ret (zero, acc_error) }
    let (ppv, ppv_error) = exact_interval(t.true_pos, positive, confidence)
    if ppv_error != ok { ret (zero, ppv_error) }
    let (npv, npv_error) = exact_interval(t.true_neg, negative, confidence)
    if npv_error != ok { ret (zero, npv_error) }
    let se_pos = math.sqrt[f64](1.0f64 / f64(t.true_pos) - 1.0f64 / f64(diseased) + 1.0f64 / f64(t.false_pos) - 1.0f64 / f64(healthy))
    let se_neg = math.sqrt[f64](1.0f64 / f64(t.false_neg) - 1.0f64 / f64(diseased) + 1.0f64 / f64(t.true_neg) - 1.0f64 / f64(healthy))
    let se_or = math.sqrt[f64](1.0f64 / f64(t.true_pos) + 1.0f64 / f64(t.false_pos) + 1.0f64 / f64(t.false_neg) + 1.0f64 / f64(t.true_neg))
    let middle_pos = math.log[f64](m.lr_positive)
    let middle_neg = math.log[f64](m.lr_negative)
    let middle_or = math.log[f64](m.odds_ratio)
    ret (Intervals {
        sensitivity: sens,
        specificity: spec,
        accuracy: acc,
        positive_predictive: ppv,
        negative_predictive: npv,
        lr_positive: Interval { low: math.exp[f64](middle_pos - 1.96f64 * se_pos), high: math.exp[f64](middle_pos + 1.96f64 * se_pos) },
        lr_negative: Interval { low: math.exp[f64](middle_neg - 1.96f64 * se_neg), high: math.exp[f64](middle_neg + 1.96f64 * se_neg) },
        odds_ratio: Interval { low: math.exp[f64](middle_or - 1.96f64 * se_or), high: math.exp[f64](middle_or + 1.96f64 * se_or) }
    }, ok)
}
