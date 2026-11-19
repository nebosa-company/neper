// e.algo.stat.mgcvpkg's two-smooth REML selection against mgcv::gam. tests/oracle/mgcv_reml2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mgcv_reml2`; the layout is at the top of scripts/r_oracle/groups/mgcv_reml2.R.

use e.algo.stat.mgcvpkg as mg
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

// the absorbed, scaled basis xz (n by k - 1) and penalty sz of one smooth: kind 0 cr, 1 ps
fn smooth(a: *mem.Arena, x: []const f64, n: usize, k: usize, kind: usize, xz: []f64, sz: []f64) -> err {
    var nkn = k + 2usize
    if kind == 1usize { nkn = k - 2usize + 2usize * 2usize + 2usize }
    let (kn, e0) = mem.alloc[f64](a, nkn)
    let (f, e1) = mem.alloc[f64](a, k * k)
    let (s, e2) = mem.alloc[f64](a, k * k)
    let (xm, e3) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    if kind == 0usize {
        let e = mg.place_knots(a, x, k, kn)
        if e != ok { ret e }
        let ep = mg.cr_penalty(a, kn, k, f, s)
        if ep != ok { ret ep }
        mg.cr_basis(x, kn, k, f, xm)
    } else {
        mg.ps_knots(x, k, 2usize, kn)
        let eb = mg.ps_basis(a, x, kn, 4usize, xm)
        if eb != ok { ret eb }
        let ep = mg.ps_penalty(a, k, 2usize, s)
        if ep != ok { ret ep }
    }
    mg.scale_penalty(xm, n, k, s)
    ret mg.absorb_sum_zero(a, xm, n, k, s, xz, sz)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k1 = usize(z[1usize])
    let k2 = usize(z[2usize])
    let what = usize(z[3usize])
    let idx = usize(z[4usize])
    let x1 = z[5usize..5usize + n]
    let x2 = z[5usize + n..5usize + 2usize * n]
    let y = z[5usize + 2usize * n..5usize + 3usize * n]
    let q1 = k1 - 1usize
    let q2 = k2 - 1usize
    let p = 1usize + q1 + q2
    let (xz1, a0) = mem.alloc[f64](a, n * q1)
    let (sz1, a1) = mem.alloc[f64](a, q1 * q1)
    let (xz2, a2) = mem.alloc[f64](a, n * q2)
    let (sz2, a3) = mem.alloc[f64](a, q2 * q2)
    let (dm, a4) = mem.alloc[f64](a, n * p)
    let (pen, a5) = mem.alloc[f64](a, p * p)
    let (coef, a6) = mem.alloc[f64](a, p)
    let (fit, a7) = mem.alloc[f64](a, n)
    if a0 != ok || a1 != ok || a2 != ok || a3 != ok || a4 != ok || a5 != ok || a6 != ok || a7 != ok { os.exit(4) }
    let s1 = smooth(a, x1, n, k1, 0usize, xz1, sz1)
    if s1 != ok { os.exit(5) }
    let s2 = smooth(a, x2, n, k2, 1usize, xz2, sz2)
    if s2 != ok { os.exit(6) }
    var i = 0usize
    while i < n {
        dm[i * p] = 1.0f64
        var j = 0usize
        while j < q1 {
            dm[i * p + 1usize + j] = xz1[i * q1 + j]
            j += 1usize
        }
        j = 0usize
        while j < q2 {
            dm[i * p + 1usize + q1 + j] = xz2[i * q2 + j]
            j += 1usize
        }
        i += 1usize
    }
    var rho: [2]f64 = zero
    let es = mg.gam_gcv_select2(a, dm, n, q1, sz1, q2, sz2, y, coef, fit, rho[0usize..2usize], true)
    if es != ok { os.exit(7) }
    i = 0usize
    while i < p * p {
        pen[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < q1 {
        var j = 0usize
        while j < q1 {
            pen[(1usize + i) * p + 1usize + j] = math.exp[f64](rho[0usize]) * sz1[i * q1 + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < q2 {
        var j = 0usize
        while j < q2 {
            pen[(1usize + q1 + i) * p + 1usize + q1 + j] = math.exp[f64](rho[1usize]) * sz2[i * q2 + j]
            j += 1usize
        }
        i += 1usize
    }
    let (edf, rss, e) = mg.pls_fit(a, dm, n, p, pen, y, coef, fit)
    if e != ok { os.exit(8) }
    let nf = f64(n)
    if what == 0usize { ret edf }
    if what == 1usize { ret edf }
    ret fit[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mgcv_reml2.json")
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
