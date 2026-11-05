// `e.algo.stat.diagnostic`: the eight metrics of a 90/20/10/80 table against
// hand arithmetic, the exact and log intervals against independent references,
// the empty-cell and bad-confidence refusals, and the u64 totals that would
// overflow. Each check exits with its own code.

use e.algo.stat.diagnostic
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: the point metrics of TP = 90, FP = 20, FN = 10, TN = 80.
    var t = diagnostic.Table { true_pos: 90u64, false_pos: 20u64, false_neg: 10u64, true_neg: 80u64 }
    let (m, m_error) = diagnostic.metrics(t)
    if m_error != ok { os.exit(1i32) }
    if !near(m.sensitivity, 0.9f64, 0.000000001f64) { os.exit(1i32) }
    if !near(m.specificity, 0.8f64, 0.000000001f64) { os.exit(1i32) }
    if !near(m.accuracy, 0.85f64, 0.000000001f64) { os.exit(1i32) }
    if !near(m.positive_predictive, 0.818181818182f64, 0.000000001f64) { os.exit(1i32) }
    if !near(m.negative_predictive, 0.888888888889f64, 0.000000001f64) { os.exit(1i32) }
    if !near(m.lr_positive, 4.5f64, 0.000000001f64) { os.exit(1i32) }
    if !near(m.lr_negative, 0.125f64, 0.000000001f64) { os.exit(1i32) }
    if !near(m.odds_ratio, 36.0f64, 0.000000001f64) { os.exit(1i32) }

    // 2: the 95% intervals -- exact for the proportions, log-method for the
    // ratios and the odds ratio.
    let (ci, ci_error) = diagnostic.metrics_ci(t, 0.95f64)
    if ci_error != ok { os.exit(2i32) }
    if !near(ci.sensitivity.low, 0.823777f64, 0.001f64) || !near(ci.sensitivity.high, 0.950995f64, 0.001f64) { os.exit(2i32) }
    if !near(ci.specificity.low, 0.708157f64, 0.001f64) || !near(ci.specificity.high, 0.873344f64, 0.001f64) { os.exit(2i32) }
    if !near(ci.accuracy.low, 0.792841f64, 0.001f64) || !near(ci.accuracy.high, 0.896450f64, 0.001f64) { os.exit(2i32) }
    if !near(ci.positive_predictive.low, 0.733260f64, 0.001f64) || !near(ci.positive_predictive.high, 0.885259f64, 0.001f64) { os.exit(2i32) }
    if !near(ci.negative_predictive.low, 0.805141f64, 0.001f64) || !near(ci.negative_predictive.high, 0.945414f64, 0.001f64) { os.exit(2i32) }
    if !near(ci.lr_positive.low, 3.0243f64, 0.01f64) || !near(ci.lr_positive.high, 6.6958f64, 0.01f64) { os.exit(2i32) }
    if !near(ci.lr_negative.low, 0.0689f64, 0.001f64) || !near(ci.lr_negative.high, 0.2269f64, 0.001f64) { os.exit(2i32) }
    if !near(ci.odds_ratio.low, 15.908f64, 0.05f64) || !near(ci.odds_ratio.high, 81.466f64, 0.2f64) { os.exit(2i32) }
    // #244: the ratio intervals use the requested confidence, not a hard-coded 1.96.
    let (ci90, ci90_error) = diagnostic.metrics_ci(t, 0.90f64)
    if ci90_error != ok { os.exit(5i32) }
    if !(ci90.lr_positive.low > ci.lr_positive.low + 0.1f64) || !(ci90.lr_positive.high < ci.lr_positive.high - 0.1f64) { os.exit(5i32) }
    if !(ci90.odds_ratio.low > ci.odds_ratio.low + 0.5f64) || !(ci90.odds_ratio.high < ci.odds_ratio.high - 1.0f64) { os.exit(5i32) }

    // 3: a perfect test keeps every metric with a defined denominator; the unbounded
    // ratios are +inf and their log-method intervals are not computed. An empty margin
    // and a bad confidence are still refused.
    var perfect = diagnostic.Table { true_pos: 90u64, false_pos: 0u64, false_neg: 10u64, true_neg: 80u64 }
    let (pm, perfect_error) = diagnostic.metrics(perfect)
    if perfect_error != ok { os.exit(3i32) }
    if !near(pm.sensitivity, 0.9f64, 0.000000001f64) || !near(pm.specificity, 1.0f64, 0.000000001f64) { os.exit(3i32) }
    if !near(pm.accuracy, 0.9444444444444444f64, 0.000000001f64) || !near(pm.positive_predictive, 1.0f64, 0.000000001f64) { os.exit(3i32) }
    if !near(pm.negative_predictive, 0.8888888888888888f64, 0.000000001f64) || !near(pm.lr_negative, 0.1f64, 0.000000001f64) { os.exit(3i32) }
    if !(pm.lr_positive > 1.0e300f64) || !(pm.odds_ratio > 1.0e300f64) { os.exit(3i32) }
    let (pci, perfect_ci_error) = diagnostic.metrics_ci(perfect, 0.95f64)
    if perfect_ci_error != ok { os.exit(3i32) }
    if !near(pci.specificity.high, 1.0f64, 0.000000001f64) || pci.specificity.low < 0.9f64 { os.exit(3i32) }
    if !(pci.lr_negative.low > 0.0f64) || !(pci.lr_negative.low < 0.1f64) || !(pci.lr_negative.high > 0.1f64) { os.exit(3i32) }
    if pci.lr_positive.low != 0.0f64 || pci.lr_positive.high != 0.0f64 || pci.odds_ratio.low != 0.0f64 || pci.odds_ratio.high != 0.0f64 { os.exit(3i32) }
    var empty = diagnostic.Table { true_pos: 0u64, false_pos: 0u64, false_neg: 0u64, true_neg: 0u64 }
    let (_, empty_error) = diagnostic.metrics(empty)
    if empty_error != diagnostic.Invalid { os.exit(3i32) }
    let (_, conf_error) = diagnostic.metrics_ci(t, 1.5f64)
    if conf_error != diagnostic.Invalid { os.exit(3i32) }

    // 4: four cells of 5e18 each keep every margin inside u64 but make the
    // total 20e18, which wraps; both entry points must refuse it.
    var huge = diagnostic.Table { true_pos: 5000000000000000000u64, false_pos: 5000000000000000000u64, false_neg: 5000000000000000000u64, true_neg: 5000000000000000000u64 }
    let (_, huge_error) = diagnostic.metrics(huge)
    if huge_error != diagnostic.Invalid { os.exit(4i32) }
    let (_, huge_ci_error) = diagnostic.metrics_ci(huge, 0.95f64)
    if huge_ci_error != diagnostic.Invalid { os.exit(4i32) }

    try io.print("algo stat diagnostic ok\n")
    ret ok
}
