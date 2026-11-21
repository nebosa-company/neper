// e.algo.stat.ordinalpkg profile likelihood for clm (profile and confint) against ordinal. tests/oracle/ordinal4.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ordinal4`; the layout is at the top of scripts/r_oracle/groups/ordinal4.R.

use e.algo.stat.ordinalpkg as od
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
    let nk = usize(z[2usize])
    let link = usize(z[3usize])
    let which = usize(z[4usize])
    let level = z[5usize]
    let ys = z[6usize..6usize + n]
    let xs = z[6usize + n..6usize + n + n * p]
    let (wts, e1) = mem.alloc[f64](a, n)
    let (lr, e2) = mem.alloc[f64](a, 101usize)
    let (bv, e3) = mem.alloc[f64](a, 101usize)
    let (ci, e4) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var i = 0usize
    while i < n {
        wts[i] = 1.0f64
        i += 1usize
    }
    if str.eq(c.name, "plo") || str.eq(c.name, "phi") {
        let alpha = (1.0f64 - level) / 4.0f64
        let m = od.clm_profile(a, xs, ys, wts, n, p, nk, link, which, alpha, lr, bv)
        if m == 0usize { ret nan }
        od.clm_confint(a, lr, bv, m, level, ci)
        if str.eq(c.name, "plo") { ret ci[0usize] }
        ret ci[1usize]
    }
    let m = od.clm_profile(a, xs, ys, wts, n, p, nk, link, which, 0.001f64, lr, bv)
    if str.eq(c.name, "pn") { ret f64(m) }
    var s = 0.0f64
    i = 0usize
    while i < m {
        s += lr[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ordinal4.json")
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
