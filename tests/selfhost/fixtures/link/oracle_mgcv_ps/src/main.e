// e.algo.stat.mgcvpkg's P-spline smooth against mgcv. tests/oracle/mgcv_ps.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mgcv_ps`; the layout is at the top of scripts/r_oracle/groups/mgcv_ps.R.

use e.algo.stat.mgcvpkg as mg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let m1 = usize(z[2usize])
    let m2 = usize(z[3usize])
    let what = usize(z[4usize])
    let idx = usize(z[5usize])
    let x = z[6usize..6usize + n]
    let nk = k - m1 + 2usize * m1 + 2usize
    let (kn, e0) = mem.alloc[f64](a, nk)
    let (xm, e1) = mem.alloc[f64](a, n * k)
    let (s, e2) = mem.alloc[f64](a, k * k)
    if e0 != ok || e1 != ok || e2 != ok { os.exit(4) }
    mg.ps_knots(x, k, m1, kn)
    let eb = mg.ps_basis(a, x, kn, m1 + 2usize, xm)
    if eb != ok { os.exit(5) }
    let ep = mg.ps_penalty(a, k, m2, s)
    if ep != ok { os.exit(6) }
    mg.scale_penalty(xm, n, k, s)
    if what == 0usize { ret kn[idx] }
    if what == 1usize { ret xm[idx] }
    ret s[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mgcv_ps.json")
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
