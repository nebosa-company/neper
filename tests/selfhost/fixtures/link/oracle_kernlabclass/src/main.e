// e.algo.stat.kernlabclass against kernlab ksvm (multi-class voting, scaling, class weights, probability models). tests/oracle/kernlabclass.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabclass`; the argument layouts are at the top of scripts/r_oracle/groups/kernlabclass.R.

use e.algo.rand.r as rr
use e.algo.stat.kernlabclass as kc
use e.algo.stat.kernlabsvm as ks
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn class_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let k = usize(z[2usize])
    let sv = usize(z[4usize])
    let nt = usize(z[14usize])
    let npair = k * (k - 1usize) / 2usize
    let w = z[15usize..15usize + k]
    let clsv = z[15usize + k..15usize + k + n]
    let (cls, e0) = mem.alloc[usize](a, n)
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (xt, e2) = mem.alloc[f64](a, nt * p)
    let (cen, e3) = mem.alloc[f64](a, p)
    let (scl, e4) = mem.alloc[f64](a, p)
    let (coef, e5) = mem.alloc[f64](a, npair * n)
    let (bb, e6) = mem.alloc[f64](a, npair)
    let (ob, e7) = mem.alloc[f64](a, npair)
    let (ab, e8) = mem.alloc[f64](a, 2usize * npair)
    let (dec, e9) = mem.alloc[f64](a, nt * npair)
    let (dv, e10) = mem.alloc[f64](a, nt)
    let (vt, e11) = mem.alloc[f64](a, k * nt)
    let (vr, e12) = mem.alloc[f64](a, k)
    let (pr, e13) = mem.alloc[f64](a, nt * k)
    let (pb, e14) = mem.alloc[f64](a, npair)
    let (rs, e15) = mem.alloc[f64](a, nt)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok { ret nan }
    var i = 0usize
    while i < n {
        cls[i] = usize(clsv[i]) - 1usize
        i += 1usize
    }
    i = 0usize
    while i < n * p {
        x[i] = z[15usize + k + n + i]
        i += 1usize
    }
    i = 0usize
    while i < nt * p {
        xt[i] = z[15usize + k + n + n * p + i]
        i += 1usize
    }
    if z[10usize] > 0.5f64 {
        if kc.scale_cols(a, x, n, p, cen, scl) != ok { ret nan }
        kc.apply_scale(xt, nt, p, cen, scl)
    }
    let par = ks.Param { ktype: usize(z[3usize]), svm: sv, c: z[5usize], nu: z[6usize], p: 0.1f64, gamma: z[7usize], degree: i64(z[8usize]), coef0: z[9usize], tol: 0.001f64, shrinking: true, cp: z[5usize], cn: z[5usize] }
    var wts: []const f64 = zero
    if z[12usize] > 0.5f64 { wts = w }
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[13usize]))
    if kc.fit_class(a, x, n, p, cls, k, &par, wts, coef, bb, ob) != ok { ret nan }
    if str.eq(c.name, "coef") { ret wsum(coef, npair * n) }
    if str.eq(c.name, "b") { ret wsum(bb, npair) }
    if str.eq(c.name, "obj") { ret wsum(ob, npair) }
    var q = 0usize
    while q < npair {
        if kc.decide(a, &par, x, n, p, coef[q * n..(q + 1usize) * n], bb[q], xt, nt, dv) != ok { ret nan }
        var t = 0usize
        while t < nt {
            dec[t * npair + q] = dv[t]
            t += 1usize
        }
        q += 1usize
    }
    if str.eq(c.name, "dec") { ret wsum(dec, nt * npair) }
    var t = 0usize
    while t < nt {
        let best = kc.vote_row(dec[t * npair..(t + 1usize) * npair], k, vr)
        rs[t] = f64(best + 1usize)
        var j = 0usize
        while j < k {
            vt[j * nt + t] = vr[j]
            j += 1usize
        }
        t += 1usize
    }
    if str.eq(c.name, "votes") { ret wsum(vt, k * nt) }
    if str.eq(c.name, "resp") { ret wsum(rs, nt) }
    if kc.prob_class(a, &g, x, n, p, cls, k, &par, ab) != ok { ret nan }
    if str.eq(c.name, "ab") { ret wsum(ab, 2usize * npair) }
    var which = 0usize
    if str.eq(c.name, "prob_pkpd") { which = 1usize }
    if str.eq(c.name, "prob_vote") { which = 2usize }
    t = 0usize
    while t < nt {
        q = 0usize
        while q < npair {
            pb[q] = 1.0f64 - kc.sigmoid(dec[t * npair + q], ab[2usize * q], ab[2usize * q + 1usize])
            q += 1usize
        }
        if kc.couple(a, pb, k, which, pr[t * k..(t + 1usize) * k]) != ok { ret nan }
        t += 1usize
    }
    ret wsum(pr, nt * k)
}

fn reg_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let nt = usize(z[13usize])
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (xt, e2) = mem.alloc[f64](a, nt * p)
    let (y, e3) = mem.alloc[f64](a, n)
    let (cen, e4) = mem.alloc[f64](a, p)
    let (scl, e5) = mem.alloc[f64](a, p)
    let (coef, e6) = mem.alloc[f64](a, n)
    let (dv, e7) = mem.alloc[f64](a, nt)
    var yc: [1]f64 = zero
    var ys: [1]f64 = zero
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    var i = 0usize
    while i < n {
        y[i] = z[14usize + i]
        i += 1usize
    }
    i = 0usize
    while i < n * p {
        x[i] = z[14usize + n + i]
        i += 1usize
    }
    i = 0usize
    while i < nt * p {
        xt[i] = z[14usize + n + n * p + i]
        i += 1usize
    }
    let scaled = z[10usize] > 0.5f64
    if scaled {
        if kc.scale_cols(a, x, n, p, cen, scl) != ok { ret nan }
        kc.apply_scale(xt, nt, p, cen, scl)
        if kc.scale_cols(a, y, n, 1usize, yc[0usize..1usize], ys[0usize..1usize]) != ok { ret nan }
    }
    let par = ks.Param { ktype: usize(z[2usize]), svm: usize(z[3usize]), c: z[4usize], nu: z[5usize], p: z[6usize], gamma: z[7usize], degree: i64(z[8usize]), coef0: z[9usize], tol: 0.001f64, shrinking: true, cp: z[4usize], cn: z[4usize] }
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[12usize]))
    let (rho, ob, se) = ks.smo_optim(a, x, n, p, y, &par, coef)
    if se != ok { ret nan }
    if str.eq(c.name, "r_coef") { ret wsum(coef, n) }
    if str.eq(c.name, "r_b") { ret rho }
    if str.eq(c.name, "r_pred") {
        if kc.decide(a, &par, x, n, p, coef, rho, xt, nt, dv) != ok { ret nan }
        var t = 0usize
        while t < nt {
            if scaled { dv[t] = dv[t] * ys[0usize] + yc[0usize] }
            t += 1usize
        }
        ret wsum(dv, nt)
    }
    let (pm, pe) = kc.prob_reg(a, &g, x, n, p, y, &par, scaled, ys[0usize], yc[0usize])
    if pe != ok { ret nan }
    ret pm
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.starts_with(c.name, "r_") { ret reg_case(a, c) }
    ret class_case(a, c)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabclass.json")
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
