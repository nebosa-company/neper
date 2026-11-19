// e.algo.stat.mgcvpkg's REML smoothing-parameter selection against mgcv::gam. tests/oracle/mgcv_reml.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mgcv_reml`; the layout is at the top of scripts/r_oracle/groups/mgcv_reml.R.

use e.algo.stat.mgcvpkg as mg
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let bs = usize(z[2usize])
    let what = usize(z[3usize])
    let idx = usize(z[4usize])
    let x = z[5usize..5usize + n]
    let y = z[5usize + n..5usize + 2usize * n]
    var nkn = k + 2usize
    if bs == 1usize { nkn = k - 2usize + 2usize * 2usize + 2usize }
    let (kn, e0) = mem.alloc[f64](a, nkn)
    let (f, e1) = mem.alloc[f64](a, k * k)
    let (s, e2) = mem.alloc[f64](a, k * k)
    let (xm, e3) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    if bs == 0usize {
        let e = mg.place_knots(a, x, k, kn)
        if e != ok { os.exit(5) }
        let ep = mg.cr_penalty(a, kn, k, f, s)
        if ep != ok { os.exit(6) }
        mg.cr_basis(x, kn, k, f, xm)
    } else {
        mg.ps_knots(x, k, 2usize, kn)
        let eb = mg.ps_basis(a, x, kn, 4usize, xm)
        if eb != ok { os.exit(5) }
        let ep = mg.ps_penalty(a, k, 2usize, s)
        if ep != ok { os.exit(6) }
    }
    mg.scale_penalty(xm, n, k, s)
    let (xz, g0) = mem.alloc[f64](a, n * (k - 1usize))
    let (sz, g1) = mem.alloc[f64](a, (k - 1usize) * (k - 1usize))
    let (coef, g2) = mem.alloc[f64](a, k)
    let (fit, g3) = mem.alloc[f64](a, n)
    if g0 != ok || g1 != ok || g2 != ok || g3 != ok { os.exit(7) }
    let ea = mg.absorb_sum_zero(a, xm, n, k, s, xz, sz)
    if ea != ok { os.exit(8) }
    let sp = mg.gam_reml_select(a, xz, n, k - 1usize, sz, y, coef, fit)
    let (edf, rss, ee) = mg.gam_gaussian(a, xz, n, k - 1usize, sz, sp, y, coef, fit)
    if ee != ok { os.exit(9) }
    let nf = f64(n)
    if what == 0usize { ret mg.gam_reml_score(a, xz, n, k - 1usize, sz, y, sp, coef, fit) }
    if what == 1usize { ret edf }
    if what == 2usize { ret fit[idx] }
    ret math.log10[f64](sp)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mgcv_reml.json")
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
