// e.algo.stat.logspline against polspline: dlogspline, plogspline and qlogspline of fitted models.
// tests/oracle/polspline.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R polspline`.

use e.algo.stat.logspline as ls
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nk = usize(z[0usize])
    var m: ls.LogSpline = zero
    m.c0 = z[1usize]
    m.c1 = z[2usize]
    m.kc = z[3usize..3usize + nk]
    m.knots = z[3usize + nk..3usize + 2usize * nk]
    let o = 3usize + 2usize * nk
    m.lower = z[o] > 0.5f64
    m.lo = z[o + 1usize]
    m.upper = z[o + 2usize] > 0.5f64
    m.hi = z[o + 3usize]
    let fn_ = usize(z[o + 4usize])
    let x = z[o + 5usize]
    if fn_ == 0usize { ret ls.dlogspline(&m, x, false) }
    if fn_ == 1usize { ret ls.dlogspline(&m, x, true) }
    let nan = 0.0f64 / 0.0f64
    if fn_ == 2usize {
        let (v, e) = ls.plogspline(a, &m, x)
        if e != ok { ret nan }
        ret v
    }
    let (v, e) = ls.qlogspline(a, &m, x)
    if e != ok { ret nan }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/polspline.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 8usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
