// e.algo.stat.metrics against yardstick and ModelMetrics. tests/oracle/metrics.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R metrics`; the layout and the case names are at
// the top of scripts/r_oracle/groups/metrics.R.

use e.algo.stat.metrics as mt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "mc") || str.eq(c.name, "ova") {
        let k = usize(x[0usize])
        let m = usize(x[1usize])
        let truth = x[2usize..2usize + m]
        if str.eq(c.name, "ova") {
            let probs = x[2usize + m..2usize + m + m * k]
            ret mt.one_vs_all(a, truth, probs, k, u8(x[2usize + m + m * k]), u8(x[3usize + m + m * k]))
        }
        let est = x[2usize + m..2usize + 2usize * m]
        let (conf, ce) = mem.alloc[f64](a, k * k)
        if ce != ok { os.exit(5) }
        var q = 0usize
        while q < k * k {
            conf[q] = 0.0f64
            q += 1usize
        }
        q = 0usize
        while q < m {
            conf[usize(est[q]) * k + usize(truth[q])] += 1.0f64
            q += 1usize
        }
        ret mt.multiclass(conf, k, u8(x[2usize + 2usize * m]), u8(x[3usize + 2usize * m]), x[4usize + 2usize * m])
    }
    let n = usize(x[0usize])
    let t = x[1usize..1usize + n]
    let e = x[1usize + n..1usize + 2usize * n]
    let p1 = x[1usize + 2usize * n]
    let nm = c.name
    if str.eq(nm, "iic") { ret mt.iic(t, e) }
    if str.eq(nm, "prauc") { ret mt.pr_auc(a, t, e) }
    if str.eq(nm, "gaincap") { ret mt.gain_capture(a, t, e) }
    if str.eq(nm, "lift") {
        let (lv, le) = mt.lift_curve(a, t, e)
        if le != ok { os.exit(5) }
        let j = u8(p1)
        if j == 0u8 { ret f64(lv.len) }
        var s = 0.0f64
        var i = 0usize
        while i < lv.len {
            if j == 1u8 { s += lv[i] } else { s += f64(i + 1usize) * lv[i] }
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "rmse") { ret mt.rmse(t, e) }
    if str.eq(nm, "mae") { ret mt.mae(t, e) }
    if str.eq(nm, "mse") { ret mt.mse(t, e) }
    if str.eq(nm, "rsq") { ret mt.rsq(t, e) }
    if str.eq(nm, "rsq_trad") { ret mt.rsq_trad(t, e) }
    if str.eq(nm, "ccc") { ret mt.ccc(t, e) }
    if str.eq(nm, "huber") { ret mt.huber_loss(t, e, p1) }
    if str.eq(nm, "mape") { ret mt.mape(t, e) }
    if str.eq(nm, "smape") { ret mt.smape(t, e) }
    if str.eq(nm, "mase") { ret mt.mase(t, e) }
    if str.eq(nm, "auc") || str.eq(nm, "roc_auc") { ret mt.auc(t, e) }
    if str.eq(nm, "gini") {
        let (g, ge) = mt.gini(a, t, e)
        if ge != ok { os.exit(5) }
        ret g
    }
    if str.eq(nm, "logloss") { ret mt.logloss(t, e) }
    if str.eq(nm, "brier") { ret mt.mse(t, e) }
    if str.eq(nm, "mm_ce") {
        let (pd, pe) = mt.threshold(a, e, 0.5f64, false)
        if pe != ok { os.exit(5) }
        var wrong = 0.0f64
        var i = 0usize
        while i < n {
            if t[i] != pd[i] { wrong += 1.0f64 }
            i += 1usize
        }
        ret wrong / f64(n)
    }
    var pred = e
    if str.eq(nm, "mm_ppv") || str.eq(nm, "mm_npv") || str.eq(nm, "mm_kappa") {
        let (r, re) = mt.threshold(a, e, p1, str.eq(nm, "mm_kappa"))
        if re != ok { os.exit(5) }
        pred = r
    }
    let (tp, fp, fnn, tn) = mt.confusion(t, pred)
    var which = 0u8
    if str.eq(nm, "accuracy") { which = 0u8 }
    if str.eq(nm, "kap") || str.eq(nm, "mm_kappa") { which = 1u8 }
    if str.eq(nm, "fmeas") { which = 2u8 }
    if str.eq(nm, "mcc") { which = 3u8 }
    if str.eq(nm, "balacc") { which = 4u8 }
    if str.eq(nm, "jindex") { which = 5u8 }
    if str.eq(nm, "precision") || str.eq(nm, "mm_ppv") { which = 6u8 }
    if str.eq(nm, "recall") { which = 7u8 }
    if str.eq(nm, "spec") { which = 8u8 }
    if str.eq(nm, "mm_npv") { which = 9u8 }
    ret mt.class_metric(tp, fp, fnn, tn, which, p1)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/metrics.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
