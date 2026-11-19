// e.algo.stat.mgcvpkg's summary.gam table and fit statistics against summary.gam. tests/oracle/mgcv_summary.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mgcv_summary`; the layout is at the top of scripts/r_oracle/groups/mgcv_summary.R.

use e.algo.stat.mgcvpkg as mg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let sp = z[2usize]
    let what = usize(z[3usize])
    let x = z[4usize..4usize + n]
    let y = z[4usize + n..4usize + 2usize * n]
    let (kn, e0) = mem.alloc[f64](a, k)
    let (f, e1) = mem.alloc[f64](a, k * k)
    let (s, e2) = mem.alloc[f64](a, k * k)
    let (xm, e3) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    let ek = mg.place_knots(a, x, k, kn)
    if ek != ok { os.exit(5) }
    let ep = mg.cr_penalty(a, kn, k, f, s)
    if ep != ok { os.exit(6) }
    mg.cr_basis(x, kn, k, f, xm)
    mg.scale_penalty(xm, n, k, s)
    let q = k - 1usize
    let p = k
    let (xz, g0) = mem.alloc[f64](a, n * q)
    let (sz, g1) = mem.alloc[f64](a, q * q)
    let (dm, g3) = mem.alloc[f64](a, n * p)
    let (pen, g4) = mem.alloc[f64](a, p * p)
    if g0 != ok || g1 != ok || g3 != ok || g4 != ok { os.exit(7) }
    let ea = mg.absorb_sum_zero(a, xm, n, k, s, xz, sz)
    if ea != ok { os.exit(8) }
    var i = 0usize
    while i < n {
        dm[i * p] = 1.0f64
        var j = 0usize
        while j < q {
            dm[i * p + 1usize + j] = xz[i * q + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p * p {
        pen[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            pen[(1usize + i) * p + 1usize + j] = sp * sz[i * q + j]
            j += 1usize
        }
        i += 1usize
    }
    let (sm, es) = mg.gam_summary(a, dm, n, p, pen, y)
    if es != ok { os.exit(10) }
    if what == 0usize { ret sm.est }
    if what == 1usize { ret sm.se }
    if what == 2usize { ret sm.tval }
    if what == 3usize { ret sm.pval }
    if what == 4usize { ret sm.sig2 }
    if what == 5usize { ret sm.rsq }
    if what == 6usize { ret sm.devexpl }
    ret sm.edf
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mgcv_summary.json")
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
