// `e.algo.stat.diagnostic`: the eight metrics of a 90/20/10/80 table against
// hand arithmetic, the exact and log intervals against independent references,
// and the empty-cell and bad-confidence refusals. Each check exits with its
// own code.

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

    // 3: the refusals -- a zero cell, an empty margin and a bad confidence.
    var perfect = diagnostic.Table { true_pos: 90u64, false_pos: 0u64, false_neg: 10u64, true_neg: 80u64 }
    let (_, perfect_error) = diagnostic.metrics(perfect)
    if perfect_error != diagnostic.Invalid { os.exit(3i32) }
    var empty = diagnostic.Table { true_pos: 0u64, false_pos: 0u64, false_neg: 0u64, true_neg: 0u64 }
    let (_, empty_error) = diagnostic.metrics(empty)
    if empty_error != diagnostic.Invalid { os.exit(3i32) }
    let (_, conf_error) = diagnostic.metrics_ci(t, 1.5f64)
    if conf_error != diagnostic.Invalid { os.exit(3i32) }
    let (_, conf_propagates) = diagnostic.metrics_ci(perfect, 0.95f64)
    if conf_propagates != diagnostic.Invalid { os.exit(3i32) }

    try io.print("algo stat diagnostic ok\n")
    ret ok
}
