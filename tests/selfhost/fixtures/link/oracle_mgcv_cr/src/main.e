// e.algo.stat.mgcvpkg's cubic regression spline against mgcv. tests/oracle/mgcv_cr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mgcv_cr`; the layout is at the top of scripts/r_oracle/groups/mgcv_cr.R.

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
    let (xk, e0) = mem.alloc[f64](a, k)
    let (f, e1) = mem.alloc[f64](a, k * k)
    let (s, e2) = mem.alloc[f64](a, k * k)
    let (xm, e3) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    let e = mg.place_knots(a, x, k, xk)
    if e != ok { os.exit(5) }
    let ep = mg.cr_penalty(a, xk, k, f, s)
    if ep != ok { os.exit(6) }
    mg.cr_basis(x, xk, k, f, xm)
    mg.scale_penalty(xm, n, k, s)
    if what == 0usize { ret xk[idx] }
    if what == 1usize { ret xm[idx] }
    ret s[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mgcv_cr.json")
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
