// e.algo.stat.kernlabcv against kernlab ksvm(cross = k). tests/oracle/kernlabcv.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabcv`; the argument layout is at the top of scripts/r_oracle/groups/kernlabcv.R.

use e.algo.rand.r as rr
use e.algo.stat.armld as ld
use e.algo.stat.kernlabclass as cl
use e.algo.stat.kernlabcv as cv
use e.algo.stat.kernlabsvm as ks
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let kc = usize(z[2usize])
    let sv = usize(z[3usize])
    let cross = usize(z[8usize])
    let scaled = z[9usize] != 0.0f64
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[10usize]))
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (cen, e2) = mem.alloc[f64](a, p)
    let (scl, e3) = mem.alloc[f64](a, p)
    let (cls, e4) = mem.alloc[usize](a, n)
    let (y, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
    var i = 0usize
    while i < n * p {
        x[i] = z[11usize + n + i]
        i += 1usize
    }
    if scaled {
        if cl.scale_cols(a, x, n, p, cen, scl) != ok { ret nan }
    }
    let par = ks.Param { ktype: 2usize, svm: sv, c: z[4usize], nu: z[5usize], p: z[6usize], gamma: z[7usize], degree: 1i64, coef0: 0.0f64, tol: 0.001f64, shrinking: true, cp: z[4usize], cn: z[4usize] }
    var lam = 1.0e-3f64 / 512.0f64 / 512.0f64
    if sv == 0usize || sv == 1usize || sv == 5usize {
        i = 0usize
        while i < n {
            cls[i] = usize(z[11usize + i]) - 1usize
            i += 1usize
        }
        let (r, e) = cv.cv_class(a, &g, x, n, p, cls, kc, &par, sv, cross, &lam)
        if e != ok { ret nan }
        ret r
    }
    var ysc = 1.0f64
    i = 0usize
    while i < n {
        y[i] = z[11usize + i]
        i += 1usize
    }
    if scaled {
        let m = ld.colmean_ld(y[0usize..n])
        let (sq, e6) = mem.alloc[f64](a, n)
        if e6 != ok { ret nan }
        i = 0usize
        while i < n {
            sq[i] = (y[i] - m) * (y[i] - m)
            i += 1usize
        }
        ysc = math.sqrt[f64](ld.sum_ld(sq[0usize..n]) / f64(n - 1usize))
        i = 0usize
        while i < n {
            y[i] = (y[i] - m) / ysc
            i += 1usize
        }
    }
    let (r, e) = cv.cv_reg(a, &g, x, n, p, y, &par, cross, ysc)
    if e != ok { ret nan }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabcv.json")
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
