// e.algo.stat.drc against drc. tests/oracle/drc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R drc`; the layout is at the top of scripts/r_oracle/groups/drc.R.

use e.algo.stat.drc as dr
use e.io
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// mselect: (n, dose, resp, nmodels, (kind, alpha, five fixed) per model, j) -- model j's column, or its place in the AIC order
fn mselect_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let dose = x[1usize..1usize + n]
    let resp = x[1usize + n..1usize + 2usize * n]
    let nm = usize(x[1usize + 2usize * n])
    let base = 2usize + 2usize * n
    let j = usize(x[base + 7usize * nm])
    let (grp, e0) = mem.alloc[usize](a, n)
    let (ics, e2) = mem.alloc[f64](a, nm)
    let (ranks, e3) = mem.alloc[f64](a, nm)
    if e0 != ok || e2 != ok || e3 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        grp[i] = 0usize
        i += 1usize
    }
    var answer_v = 0.0f64
    var m = 0usize
    while m < nm {
        let at = base + 7usize * m
        let (f, e1) = dr.fit(a, i64(x[at]), x[at + 1usize], x[at + 2usize..at + 7usize], dose, resp, grp, 1usize, 0i64, 0.0f64, dose[0usize..0usize])
        if e1 != ok { os.exit(6) }
        ics[m] = dr.aic(&f)
        if m == j {
            let k = c.name
            if str.eq(k, "mselll") { answer_v = f.loglik }
            if str.eq(k, "mselic") { answer_v = ics[m] }
            if str.eq(k, "mselrv") { answer_v = f.rv }
            if str.eq(k, "mselof") {
                let (fv, pv, d1, d2) = dr.lack_of_fit(&f, dose, resp, grp, a)
                answer_v = pv
            }
        }
        m += 1usize
    }
    dr.rank_order(ics, ranks)
    if str.eq(c.name, "mselrank") { ret ranks[j] }
    ret answer_v
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.starts_with(c.name, "msel") { ret mselect_answer(a, c) }
    let x = c.args
    let kind = i64(x[0usize])
    let alpha = x[1usize]
    let mode = i64(x[2usize])
    let kk = usize(x[3usize])
    let fixedv = x[4usize..9usize]
    let n = usize(x[9usize])
    let dose = x[10usize..10usize + n]
    let resp = x[10usize + n..10usize + 2usize * n]
    let (grp, e0) = mem.alloc[usize](a, n)
    if e0 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        grp[i] = usize(x[10usize + 2usize * n + i])
        i += 1usize
    }
    let s1 = x[10usize + 3usize * n]
    let s2 = x[11usize + 3usize * n]
    let k = c.name
    // robust cases: s1 is the scale, s2 the selector, and the coefficients to evaluate at follow
    var scale = 0.0f64
    var fixpar = dose[0usize..0usize]
    if str.starts_with(k, "r") && !str.eq(k, "rv") {
        scale = s1
        fixpar = x[12usize + 3usize * n..x.len]
    }
    let (f, e1) = dr.fit(a, kind, alpha, fixedv, dose, resp, grp, kk, mode, scale, fixpar)
    if e1 != ok { os.exit(6) }
    if str.eq(k, "rcrit") { ret f.crit }
    if str.eq(k, "rvalue") { ret f.value }
    if str.eq(k, "rrv") { ret f.rv }
    if str.eq(k, "rse") { ret math.sqrt[f64](f.vcov[usize(s2) * f.np + usize(s2)]) }
    if str.eq(k, "rll") { ret f.loglik }
    if str.eq(k, "par") { ret f.par[usize(s1)] }
    if str.eq(k, "se") { ret math.sqrt[f64](f.vcov[usize(s1) * f.np + usize(s1)]) }
    if str.eq(k, "covar") { ret f.vcov[usize(s1) * f.np + usize(s2)] }
    if str.eq(k, "rv") { ret f.rv }
    if str.eq(k, "value") { ret f.value }
    if str.eq(k, "loglik") { ret f.loglik }
    if str.eq(k, "aic") { ret dr.aic(&f) }
    if str.eq(k, "fit") { ret f.fitted[usize(s1)] }
    if str.eq(k, "lofF") || str.eq(k, "lofp") {
        let (fv, pv, d1, d2) = dr.lack_of_fit(&f, dose, resp, grp, a)
        if str.eq(k, "lofF") { ret fv }
        ret pv
    }
    if str.starts_with(k, "cp") {
        let (est, se, t, p) = dr.comp_parm(&f, usize(s1), 0usize, 1usize, s2 == 1.0f64)
        if str.eq(k, "cpest") { ret est }
        if str.eq(k, "cpse") { ret se }
        if str.eq(k, "cpt") { ret t }
        ret p
    }
    if str.starts_with(k, "sel") {
        let (est, se, t, p) = dr.ed_comp(&f, kind, alpha, fixedv, 0usize, 1usize, s1, s2, a)
        if str.eq(k, "selest") { ret est }
        if str.eq(k, "selse") { ret se }
        if str.eq(k, "selt") { ret t }
        ret p
    }
    let (est, se) = dr.ed(&f, kind, alpha, fixedv, usize(s1), s2, a)
    if str.eq(k, "ed") { ret est }
    if str.eq(k, "edse") { ret se }
    var q = nb.qt(0.975f64, f.dfres, true, false)
    if mode == 2 { q = dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false) }
    if str.eq(k, "edlo") { ret est - q * se }
    ret est + q * se
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/drc.json")
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
            if failures < 6usize {
                let (initial, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, c.name)
                    let _ = str.push(&b, " mode,kind,K ")
                    let _ = str.push_f64(&b, c.args[2usize])
                    let _ = str.push(&b, ",")
                    let _ = str.push_f64(&b, c.args[0usize])
                    let _ = str.push(&b, ",")
                    let _ = str.push_f64(&b, c.args[3usize])
                    let _ = str.push(&b, " n ")
                    let _ = str.push_f64(&b, c.args[9usize])
                    let _ = str.push(&b, " sel ")
                    let _ = str.push_f64(&b, c.args[c.args.len - 2usize])
                    let _ = str.push(&b, ",")
                    let _ = str.push_f64(&b, c.args[c.args.len - 1usize])
                    let _ = str.push(&b, " got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, " want ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
