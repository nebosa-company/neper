// e.algo.stat.mgcvpkg's thin-plate regression spline with GCV selection against mgcv::gam. tests/oracle/mgcv_tp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mgcv_tp`; the layout is at the top of scripts/r_oracle/groups/mgcv_tp.R.

use e.algo.stat.mgcvpkg as mg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let what = usize(z[2usize])
    let idx = usize(z[3usize])
    let x = z[4usize..4usize + n]
    let y = z[4usize + n..4usize + 2usize * n]
    let (dm, e0) = mem.alloc[f64](a, n * k)
    let e1 = ok
    let (pen0, e2) = mem.alloc[f64](a, k * k)
    let (coef, e3) = mem.alloc[f64](a, k)
    let (fit, e4) = mem.alloc[f64](a, n)
    let (pen, e5) = mem.alloc[f64](a, k * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(4) }
    let eb = mg.tp_build(a, x, k, dm, pen0)
    if eb != ok { os.exit(5) }
    var i = 0usize
    let sp = mg.gcv_gen_select(a, dm, n, k, pen0, y, coef, fit)
    i = 0usize
    while i < k * k {
        pen[i] = sp * pen0[i]
        i += 1usize
    }
    let (edf, rss, e) = mg.pls_fit(a, dm, n, k, pen, y, coef, fit)
    if e != ok { os.exit(6) }
    let nf = f64(n)
    if what == 0usize { ret nf * rss / ((nf - edf) * (nf - edf)) }
    if what == 1usize { ret edf }
    ret fit[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mgcv_tp.json")
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
