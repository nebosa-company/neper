// e.algo.stat.minpacklm against minpack.lm::nls.lm (numerical Jacobian). tests/oracle/minpacklm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R minpacklm`; the layout is at the top of
// scripts/r_oracle/groups/minpacklm.R.

use e.algo.stat.minpacklm as ml
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Data = struct { id: usize, t: []const f64, y: []const f64 }

fn resid(d: *Data, p: []const f64, out: []f64) {
    var i = 0usize
    while i < d.t.len {
        var v = 0.0f64
        if d.id == 0usize { v = p[0usize] * math.exp[f64](0.0f64 - p[1usize] * d.t[i]) + p[2usize] }
        if d.id == 1usize { v = p[0usize] * d.t[i] / (p[1usize] + d.t[i]) }
        if d.id == 2usize { v = p[0usize] / (1.0f64 + math.exp[f64](0.0f64 - (d.t[i] - p[1usize]) / p[2usize])) }
        out[i] = d.y[i] - v
        i += 1usize
    }
}

fn jac(d: *Data, p: []const f64, out: []f64) {
    let m = d.t.len
    var i = 0usize
    while i < m {
        let t = d.t[i]
        if d.id == 0usize {
            let e = math.exp[f64](0.0f64 - p[1usize] * t)
            out[0usize * m + i] = 0.0f64 - e
            out[1usize * m + i] = p[0usize] * t * e
            out[2usize * m + i] = 0.0f64 - 1.0f64
        }
        if d.id == 1usize {
            out[0usize * m + i] = 0.0f64 - t / (p[1usize] + t)
            out[1usize * m + i] = p[0usize] * t / ((p[1usize] + t) * (p[1usize] + t))
        }
        if d.id == 2usize {
            let s = (t - p[1usize]) / p[2usize]
            let u = math.exp[f64](0.0f64 - s)
            let den = 1.0f64 + u
            out[0usize * m + i] = 0.0f64 - 1.0f64 / den
            out[1usize * m + i] = p[0usize] * u / (p[2usize] * den * den)
            out[2usize * m + i] = p[0usize] * u * s / (p[2usize] * den * den)
        }
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let id = usize(z[0usize])
    let n = usize(z[1usize])
    let np = usize(z[2usize])
    var d = Data { id: id, t: z[3usize..3usize + n], y: z[3usize + n..3usize + 2usize * n] }
    let (x, e1) = mem.alloc[f64](a, np)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < np {
        x[i] = z[3usize + 2usize * n + i]
        i += 1usize
    }
    let lo = z[3usize + 2usize * n + np..3usize + 2usize * n + 2usize * np]
    let hi = z[3usize + 2usize * n + 2usize * np..3usize + 2usize * n + 3usize * np]
    var q = usize(z[3usize + 2usize * n + 3usize * np])
    var fac = 100.0f64
    var dgv = z[3usize..3usize]
    if str.eq(c.name, "lmopt") {
        fac = z[3usize + 2usize * n + 3usize * np]
        dgv = z[3usize + 2usize * n + 3usize * np + 1usize..3usize + 2usize * n + 4usize * np + 1usize]
        q = usize(z[3usize + 2usize * n + 4usize * np + 1usize])
    }
    let sq = 1.4901161193847656e-8f64
    var fit: ml.Fit = zero
    var e: err = ok
    if str.eq(c.name, "lmopt") {
        let (f2, e2) = ml.nls_lm_opts[Data](a, resid, &d, n, np, x, lo, hi, sq, sq, 0.0f64, i64(100usize * (np + 1usize)), 50i64, fac, dgv)
        fit = f2
        e = e2
    } else if str.eq(c.name, "lmder") {
        let (f2, e2) = ml.nls_lm_der[Data](a, resid, jac, &d, n, np, x, lo, hi, sq, sq, 0.0f64, i64(100usize * (np + 1usize)), 50i64)
        fit = f2
        e = e2
    } else {
        let (f2, e2) = ml.nls_lm[Data](a, resid, &d, n, np, x, lo, hi, sq, sq, 0.0f64, i64(100usize * (np + 1usize)), 50i64)
        fit = f2
        e = e2
    }
    if e != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "lmsum") {
        let (jb, je) = mem.alloc[f64](a, n * np)
        if je != ok { ret 0.0f64 / 0.0f64 }
        jac(&d, x, jb)
        let (se, ee) = mem.alloc[f64](a, np)
        if ee != ok { ret 0.0f64 / 0.0f64 }
        let sg = ml.nls_summary(a, jb, n, np, fit.deviance, se)
        if q == 0usize { ret sg }
        ret se[q - 1usize]
    }
    if str.eq(c.name, "lmhess") { ret fit.hess[q] }
    if q < np { ret x[q] }
    if q == np { ret fit.deviance }
    if q == np + 1usize { ret f64(fit.info) }
    ret f64(fit.niter)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/minpacklm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
