// e.algo.stat.pls against pls: the four plsr fits compared by sums of the coefficients, the fitted values, the scores and the loadings.
// tests/oracle/pls.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pls`; the layout is at the top of
// scripts/r_oracle/groups/pls.R.

use e.algo.stat.pls as pl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn sums(v: []const f64, what: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if what == 0usize { s += v[i] }
        if what == 1usize { s += f64(i + 1usize) * v[i] }
        if what == 2usize { s += v[i] * v[i] }
        i += 1usize
    }
    ret s
}

fn a_seg(a: *mem.Arena, v: []const f64) -> []usize {
    let (o, e) = mem.alloc[usize](a, v.len)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < v.len {
        o[i] = usize(v[i])
        i += 1usize
    }
    ret o
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let m = u8(x[0usize])
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let q = usize(x[3usize])
    let ncomp = usize(x[4usize])
    let centre = x[5usize] == 1.0f64
    let xs = x[6usize..6usize + n * p]
    let ys = x[6usize + n * p..6usize + n * p + n * q]
    let tail = 6usize + n * p + n * q
    let nm0 = c.name
    if str.eq(nm0, "jsd") || str.eq(nm0, "jt") {
        let jn = usize(x[tail])
        let jseg = a_seg(a, x[tail + 1usize..tail + 1usize + n])
        let jk = usize(x[tail + 1usize + n])
        let jw = usize(x[tail + 2usize + n])
        let (cf, e1) = mem.alloc[f64](a, p * q)
        let (sdv, e2) = mem.alloc[f64](a, p * q)
        if e1 != ok || e2 != ok { os.exit(9) }
        if pl.jack_test(a, m, xs, ys, n, p, q, jk, centre, jseg, jn, cf, sdv) != ok { os.exit(10) }
        if str.eq(nm0, "jt") {
            var ti = 0usize
            while ti < p * q {
                cf[ti] = cf[ti] / sdv[ti]
                ti += 1usize
            }
            ret sums(cf, jw)
        }
        ret sums(sdv, jw)
    }
    if str.eq(nm0, "press") || str.eq(nm0, "adj") || str.eq(nm0, "press0") || str.eq(nm0, "msep") || str.eq(nm0, "r2") {
        let nseg = usize(x[tail])
        let seg = a_seg(a, x[tail + 1usize..tail + 1usize + n])
        let (cv, ce) = pl.cross_validate(a, m, xs, ys, n, p, q, ncomp, centre, seg, nseg)
        if ce != ok { os.exit(7) }
        let base = tail + 1usize + n
        if str.eq(nm0, "press0") { ret cv.press0[usize(x[base])] }
        if str.eq(nm0, "press") { ret cv.press[usize(x[base]) * cv.ncomp + usize(x[base + 1usize])] }
        if str.eq(nm0, "adj") { ret cv.adj[usize(x[base]) * cv.ncomp + usize(x[base + 1usize])] }
        let est = usize(x[base])
        let j = usize(x[base + 1usize])
        let k = usize(x[base + 2usize])
        let (fit2, fe2) = pl.fit_method(a, m, xs, ys, n, p, q, ncomp, centre)
        if fe2 != ok { os.exit(8) }
        // total sum of squares of the response and the training and CV errors; k = 0 is the intercept-only model
        var sm = 0.0f64
        var i = 0usize
        while i < n {
            sm += ys[i * q + j]
            i += 1usize
        }
        let mean = sm / f64(n)
        var sst = 0.0f64
        i = 0usize
        while i < n {
            sst += (ys[i * q + j] - mean) * (ys[i * q + j] - mean)
            i += 1usize
        }
        var sse = 0.0f64
        if est == 0usize {
            if k == 0usize { sse = sst } else { sse = pl.train_sse(fit2, ys, n, q, j, k - 1usize) }
        } else {
            if k == 0usize { sse = cv.press0[j] } else { sse = cv.press[j * cv.ncomp + k - 1usize] }
        }
        if str.eq(nm0, "r2") { ret 1.0f64 - sse / sst }
        var ms = sse / f64(n)
        if est == 2usize && k > 0usize {
            let tr = pl.train_sse(fit2, ys, n, q, j, k - 1usize) / f64(n)
            ms = cv.press[j * cv.ncomp + k - 1usize] / f64(n) + tr - cv.adj[j * cv.ncomp + k - 1usize]
        }
        ret ms
    }
    let (fit, e) = pl.fit_method(a, m, xs, ys, n, p, q, ncomp, centre)
    if e != ok { os.exit(6) }
    let nm = c.name
    if str.eq(nm, "coef") || str.eq(nm, "fit") {
        let k = usize(x[tail]) - 1usize
        let what = usize(x[tail + 1usize])
        if str.eq(nm, "coef") { ret sums(fit.coef[k * p * q..(k + 1usize) * p * q], what) }
        ret sums(fit.fitted[k * n * q..(k + 1usize) * n * q], what)
    }
    let k = usize(x[tail]) - 1usize
    if str.eq(nm, "xvar") { ret fit.xvar[k] }
    if str.eq(nm, "tt") || str.eq(nm, "ttsum") {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            let v = fit.scores[i * ncomp + k]
            if str.eq(nm, "tt") { s += v * v } else { s += v * f64(i + 1usize) }
            i += 1usize
        }
        ret s
    }
    var s = 0.0f64
    var i = 0usize
    while i < p {
        let v = fit.loadings[i * ncomp + k]
        if str.eq(nm, "pp") { s += v * v } else { s += v * f64(i + 1usize) }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pls.json")
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
