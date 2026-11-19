// e.algo.stat.mgcvpkg's predictions and standard errors against predict.gam. tests/oracle/mgcv_predict.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mgcv_predict`; the layout is at the top of scripts/r_oracle/groups/mgcv_predict.R.

use e.algo.stat.mgcvpkg as mg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let m = usize(z[2usize])
    let sp = z[3usize]
    let what = usize(z[4usize])
    let idx = usize(z[5usize])
    let x = z[6usize..6usize + n]
    let y = z[6usize + n..6usize + 2usize * n]
    let xnew = z[6usize + 2usize * n..6usize + 2usize * n + m]
    let (kn, e0) = mem.alloc[f64](a, k)
    let (f, e1) = mem.alloc[f64](a, k * k)
    let (s, e2) = mem.alloc[f64](a, k * k)
    let (xm, e3) = mem.alloc[f64](a, n * k)
    let (xn, e4) = mem.alloc[f64](a, m * k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(4) }
    let ek = mg.place_knots(a, x, k, kn)
    if ek != ok { os.exit(5) }
    let ep = mg.cr_penalty(a, kn, k, f, s)
    if ep != ok { os.exit(6) }
    mg.cr_basis(x, kn, k, f, xm)
    mg.cr_basis(xnew, kn, k, f, xn)
    mg.scale_penalty(xm, n, k, s)
    let q = k - 1usize
    let p = k
    let (xz, g0) = mem.alloc[f64](a, n * q)
    let (sz, g1) = mem.alloc[f64](a, q * q)
    let (zm, g2) = mem.alloc[f64](a, k * q)
    let (dm, g3) = mem.alloc[f64](a, n * p)
    let (pen, g4) = mem.alloc[f64](a, p * p)
    let (rows, g5) = mem.alloc[f64](a, m * p)
    let (pred, g6) = mem.alloc[f64](a, m)
    let (se, g7) = mem.alloc[f64](a, m)
    if g0 != ok || g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok { os.exit(7) }
    let ea = mg.absorb_sum_zero(a, xm, n, k, s, xz, sz)
    if ea != ok { os.exit(8) }
    let ez = mg.sum_zero_z(a, xm, n, k, zm)
    if ez != ok { os.exit(9) }
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
    // the new rows: [1 | xn Z]
    i = 0usize
    while i < m {
        rows[i * p] = 1.0f64
        var cc = 0usize
        while cc < q {
            var v = 0.0f64
            var t = 0usize
            while t < k {
                v += xn[i * k + t] * zm[t * q + cc]
                t += 1usize
            }
            rows[i * p + 1usize + cc] = v
            cc += 1usize
        }
        i += 1usize
    }
    let eg = mg.gam_predict(a, dm, n, p, pen, y, rows, m, pred, se)
    if eg != ok { os.exit(10) }
    if what == 0usize { ret pred[idx] }
    ret se[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mgcv_predict.json")
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
