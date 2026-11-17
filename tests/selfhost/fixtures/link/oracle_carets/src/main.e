// e.algo.stat.carets against caret: confusionMatrix of a two-class table and postResample. tests/oracle/carets.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R carets`; the layout is at the top of
// scripts/r_oracle/groups/carets.R.

use e.algo.stat.carets as ct
use e.io
use e.mem
use e.math
use e.algo.rand.r as rng
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "rs") || str.eq(c.name, "cf") || str.eq(c.name, "gk") {
        var r: rng.Rng = zero
        rng.seed(&r, i64(z[0usize]))
        var n = 0usize
        if str.eq(c.name, "rs") { n = usize(z[1usize]) } else if str.eq(c.name, "cf") { n = usize(z[2usize]) } else { n = usize(z[3usize]) }
        let (v, e) = mem.alloc[i64](a, n)
        if e != ok { ret nan }
        if str.eq(c.name, "rs") {
            if ct.create_resample(a, &r, n, v) != ok { ret nan }
        } else {
            let (cl, e2) = mem.alloc[i64](a, n)
            if e2 != ok { ret nan }
            var q = 0usize
            if str.eq(c.name, "cf") {
                while q < n {
                    cl[q] = i64(z[3usize + q]) - 1i64
                    q += 1usize
                }
                if ct.create_folds(a, &r, cl, usize(z[1usize]), v) != ok { ret nan }
            } else {
                while q < n {
                    cl[q] = i64(z[4usize + q]) - 1i64
                    q += 1usize
                }
                if ct.group_kfold(a, &r, cl, usize(z[2usize]), usize(z[1usize]), v) != ok { ret nan }
            }
        }
        var s = 0.0f64
        var q2 = 0usize
        while q2 < n {
            s += f64(q2 + 1usize) * f64(v[q2])
            q2 += 1usize
        }
        ret s
    }
    if str.eq(c.name, "cmv") {
        // (which 0 ppv 1 npv 2 prevalence 3 f1 4 detection rate, TP, FP, FN, TN, prevalence)
        let tp = z[1usize]
        let fp = z[2usize]
        let fnn = z[3usize]
        let tn = z[4usize]
        let (po, pe) = mem.alloc[f64](a, 3usize)
        if pe != ok { ret nan }
        ct.with_prevalence(tp / (tp + fnn), tn / (fp + tn), z[5usize], po)
        let w = usize(z[0usize])
        if w < 3usize { ret po[w] }
        let cc = ct.confusion2(tp, fp, fnn, tn, 0.95f64)
        if w == 3usize { ret cc.f1 }
        ret cc.detection_rate
    }
    if str.eq(c.name, "knn") {
        // (n, p, k, index, X[n p] with -999999 for a missing value)
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let (xs, e1) = mem.alloc[f64](a, n * p)
        let (o, e2) = mem.alloc[f64](a, n * p)
        if e1 != ok || e2 != ok { ret nan }
        var q = 0usize
        while q < n * p {
            xs[q] = z[4usize + q]
            if xs[q] < -999998.0f64 { xs[q] = nan }
            q += 1usize
        }
        if ct.knn_impute(a, xs, n, p, usize(z[2usize]), o) != ok { ret nan }
        ret o[usize(z[3usize])]
    }
    if str.eq(c.name, "mf") {
        // createMultiFolds(factor(y), k, times): (seed, k, n, times, class codes 1..), the fold assignments of the repetitions drawn one after another, answered as sum over reps of rep * sum(position * fold)
        var r: rng.Rng = zero
        rng.seed(&r, i64(z[0usize]))
        let n = usize(z[2usize])
        let times = usize(z[3usize])
        let (v, e) = mem.alloc[i64](a, n)
        let (cl, e2) = mem.alloc[i64](a, n)
        if e != ok || e2 != ok { ret nan }
        var q = 0usize
        while q < n {
            cl[q] = i64(z[4usize + q]) - 1i64
            q += 1usize
        }
        var s = 0.0f64
        var t = 0usize
        while t < times {
            if ct.create_folds(a, &r, cl, usize(z[1usize]), v) != ok { ret nan }
            var q2 = 0usize
            while q2 < n {
                s += f64(t + 1usize) * f64(q2 + 1usize) * f64(v[q2])
                q2 += 1usize
            }
            t += 1usize
        }
        ret s
    }
    if str.eq(c.name, "dp") {
        var r: rng.Rng = zero
        rng.seed(&r, i64(z[0usize]))
        let n = usize(z[4usize])
        let (mk, e) = mem.alloc[f64](a, n)
        let (mi, e2) = mem.alloc[i64](a, n)
        if e != ok || e2 != ok { ret nan }
        var yy = z[5usize..5usize + n]
        if z[3usize] == 0.0f64 {
            var q = 0usize
            while q < n {
                mk[q] = yy[q] - 1.0f64
                q += 1usize
            }
            yy = mk[0usize..n]
        }
        if ct.create_data_partition(a, &r, yy, z[3usize] != 0.0f64, z[1usize], usize(z[2usize]), mi) != ok { ret nan }
        var s = 0.0f64
        var q2 = 0usize
        while q2 < n {
            s += f64(q2 + 1usize) * f64(mi[q2])
            q2 += 1usize
        }
        ret s
    }
    if str.eq(c.name, "pp") {
        let n = usize(z[3usize])
        let p = usize(z[4usize])
        let (o, e) = mem.alloc[f64](a, n * p)
        if e != ok { ret nan }
        let mode = usize(z[0usize])
        let xs = z[5usize..5usize + n * p]
        if mode == 3usize { ct.pre_process_range(xs, n, p, z[1usize], z[2usize], o) } else { ct.pre_process_cs(xs, n, p, mode != 1usize, mode >= 1usize, o) }
        var s = 0.0f64
        var q = 0usize
        while q < n * p {
            s += f64(q % n + 1usize) * f64(q / n + 1usize) * o[q]
            q += 1usize
        }
        ret s
    }
    if str.eq(c.name, "cmk") {
        let k = usize(z[1usize])
        let (o, e) = mem.alloc[f64](a, 7usize + 11usize * k)
        if e != ok { ret nan }
        ct.confusion_multi(z[2usize..2usize + k * k], k, o)
        ret o[usize(z[0usize])]
    }
    if str.eq(c.name, "bc") {
        let n = usize(z[1usize])
        let ys = z[2usize..2usize + n]
        let lam = ct.box_cox_lambda(a, ys)
        if z[0usize] == 0.0f64 {
            if lam != lam { ret 0.0f64 - 99.0f64 }
            ret lam
        }
        var s = 0.0f64
        var q = 0usize
        while q < n {
            s += f64(q + 1usize) * ct.box_cox_apply(ys[q], lam)
            q += 1usize
        }
        ret s
    }
    if str.eq(c.name, "yj") {
        let n = usize(z[1usize])
        let ys = z[2usize..2usize + n]
        let lam = ct.yeo_johnson_lambda(a, ys)
        if z[0usize] == 0.0f64 {
            if lam != lam { ret 0.0f64 - 99.0f64 }
            ret lam
        }
        var s = 0.0f64
        var q = 0usize
        while q < n {
            var v = ys[q]
            if lam == lam { v = ct.yj_value(ys[q], lam) }
            s += f64(q + 1usize) * v
            q += 1usize
        }
        ret s
    }
    if str.eq(c.name, "vig") {
        // (n, p, index, X[n p] intercept first, y[n]): varImp of a logistic glm
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let (o, e) = mem.alloc[f64](a, p)
        if e != ok { ret nan }
        if ct.var_imp_logit(a, z[3usize..3usize + n * p], n, p, z[3usize + n * p..3usize + n * p + n], o) != ok { ret nan }
        ret o[usize(z[2usize])]
    }
    if str.eq(c.name, "vi") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let (o, e) = mem.alloc[f64](a, p)
        if e != ok { ret nan }
        if ct.var_imp_lm(a, z[3usize..3usize + n * p], n, p, z[3usize + n * p..3usize + n * p + n], o) != ok { ret nan }
        ret o[usize(z[2usize])]
    }
    if str.eq(c.name, "pca") {
        let n = usize(z[2usize])
        let p = usize(z[3usize])
        let (sd, e1) = mem.alloc[f64](a, p)
        let (sc, e2) = mem.alloc[f64](a, n * p)
        if e1 != ok || e2 != ok { ret nan }
        let k = ct.pre_process_pca(a, z[4usize..4usize + n * p], n, p, z[0usize], sd, sc)
        let id = usize(z[1usize])
        if id == 0usize { ret f64(k) }
        if id <= p { ret sd[id - 1usize] }
        let j = id - p - 1usize
        var s = 0.0f64
        var q = 0usize
        while q < n {
            s += math.abs[f64](sc[j * n + q])
            q += 1usize
        }
        ret s
    }
    if str.eq(c.name, "ts") {
        let (o, e) = mem.alloc[i64](a, 400usize)
        if e != ok { ret nan }
        let cnt = ct.create_time_slices(usize(z[0usize]), usize(z[1usize]), usize(z[2usize]), z[3usize] != 0.0f64, usize(z[4usize]), o)
        let id = usize(z[5usize])
        if id == 0usize { ret f64(cnt) }
        var s = 0.0f64
        var q = 0usize
        while q < cnt {
            s += f64(o[4usize * q + id - 1usize])
            q += 1usize
        }
        ret s
    }
    let id = usize(z[0usize])
    if str.eq(c.name, "pr") {
        let n = usize(z[1usize])
        let (rmse, r2, mae) = ct.post_resample(z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n])
        if id == 0usize { ret rmse }
        if id == 1usize { ret r2 }
        ret mae
    }
    let m = ct.confusion2(z[1usize], z[2usize], z[3usize], z[4usize], 0.95f64)
    if id == 0usize { ret m.accuracy }
    if id == 1usize { ret m.kappa }
    if id == 2usize { ret m.lower }
    if id == 3usize { ret m.upper }
    if id == 4usize { ret m.nir }
    if id == 5usize { ret m.pvalue }
    if id == 6usize { ret m.mcnemar }
    if id == 7usize { ret m.sens }
    if id == 8usize { ret m.spec }
    if id == 9usize { ret m.ppv }
    if id == 10usize { ret m.npv }
    if id == 11usize { ret m.f1 }
    if id == 12usize { ret m.prevalence }
    if id == 13usize { ret m.detection_rate }
    if id == 14usize { ret m.detection_prevalence }
    ret m.balanced
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/carets.json")
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
