// e.algo.stat.gstatvgm against gstat. tests/oracle/gstatvgm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gstatvgm`; the layout is at the top of scripts/r_oracle/groups/gstatvgm.R.

use e.algo.stat.gstatvgm as gv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "gam") {
        let nst = usize(x[0usize])
        ret gv.model_gamma(x[1usize..1usize + 6usize * nst], nst, x[1usize + 6usize * nst], x[2usize + 6usize * nst])
    }
    if str.eq(k, "cutoff") {
        let n = usize(x[0usize])
        let (xy, e1) = mem.alloc[f64](a, 2usize * n)
        if e1 != ok { os.exit(5) }
        var i = 0usize
        while i < n {
            xy[2usize * i] = x[1usize + 3usize * i]
            xy[2usize * i + 1usize] = x[2usize + 3usize * i]
            i += 1usize
        }
        ret gv.default_cutoff(xy, n)
    }
    let kind = usize(x[0usize])
    let cloud = x[1usize] > 0.5f64
    let na = usize(x[2usize])
    let nb = usize(x[3usize])
    var base = 11usize
    let nd = usize(x[10usize])
    let (xa, e1) = mem.alloc[f64](a, 2usize * na)
    if e1 != ok { os.exit(5) }
    let (za, e2) = mem.alloc[f64](a, na)
    if e2 != ok { os.exit(6) }
    var i = 0usize
    while i < na {
        xa[2usize * i] = x[base + 3usize * i]
        xa[2usize * i + 1usize] = x[base + 3usize * i + 1usize]
        za[i] = x[base + 3usize * i + 2usize]
        i += 1usize
    }
    base += 3usize * na
    let (xb, e3) = mem.alloc[f64](a, 2usize * nb + 2usize)
    if e3 != ok { os.exit(7) }
    let (zb, e4) = mem.alloc[f64](a, nb + 1usize)
    if e4 != ok { os.exit(8) }
    if kind == 1usize {
        i = 0usize
        while i < nb {
            zb[i] = x[base + 3usize * i + 2usize]
            i += 1usize
        }
    }
    if kind == 2usize {
        i = 0usize
        while i < nb {
            xb[2usize * i] = x[base + 3usize * i]
            xb[2usize * i + 1usize] = x[base + 3usize * i + 1usize]
            zb[i] = x[base + 3usize * i + 2usize]
            i += 1usize
        }
    }
    let (ra, e8) = mem.alloc[f64](a, na)
    if e8 != ok { os.exit(12) }
    let (rb, e9) = mem.alloc[f64](a, nb + 1usize)
    if e9 != ok { os.exit(13) }
    if gv.trend_residuals(a, xa, za, na, nd, ra) != ok { os.exit(14) }
    if kind == 4usize {
        i = 0usize
        while i < na {
            ra[i] = za[i]
            i += 1usize
        }
    }
    if kind == 1usize { if gv.trend_residuals(a, xa, zb, nb, nd, rb) != ok { os.exit(15) } }
    if kind == 2usize { if gv.trend_residuals(a, xb, zb, nb, nd, rb) != ok { os.exit(16) } }
    let cap = gv.ev_capacity(na, nb, x[4usize], x[5usize], cloud)
    let (onp, e5) = mem.alloc[f64](a, cap)
    if e5 != ok { os.exit(9) }
    let (od, e6) = mem.alloc[f64](a, cap)
    if e6 != ok { os.exit(10) }
    let (og, e7) = mem.alloc[f64](a, cap)
    if e7 != ok { os.exit(11) }
    var n_est = 0usize
    if kind == 1usize { n_est = gv.emp_variogram(kind, xa, ra, na, xa, rb, nb, x[4usize], x[5usize], x[6usize], x[7usize], cloud, onp, od, og) }
    if kind != 1usize { n_est = gv.emp_variogram(kind, xa, ra, na, xb, rb, nb, x[4usize], x[5usize], x[6usize], x[7usize], cloud, onp, od, og) }
    let part = usize(x[8usize])
    if part == 3usize { ret f64(n_est) }
    let idx = usize(x[9usize])
    if idx >= n_est { ret 0.0f64 - 1.0f64 }
    if part == 0usize { ret onp[idx] }
    if part == 1usize { ret od[idx] }
    ret og[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gstatvgm.json")
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
