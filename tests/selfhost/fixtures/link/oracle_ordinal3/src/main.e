// e.algo.stat.ordinalpkg clmm (one random intercept, Laplace and adaptive quadrature) against ordinal clmm. tests/oracle/ordinal3.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ordinal3`; the layout is at the top of scripts/r_oracle/groups/ordinal3.R.

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
    let ng = usize(z[3usize])
    var link = usize(z[4usize])
    if link == 2usize { link = 3usize } else if link == 3usize { link = 2usize }
    let agq = usize(z[5usize])
    let (par, e1) = mem.alloc[f64](a, nk + p)
    if e1 != ok { ret nan }
    let xs = z[6usize + 2usize * n..6usize + 2usize * n + n * p]
    let ys = z[6usize..6usize + n]
    let gs = z[6usize + n..6usize + 2usize * n]
    let ex = 6usize + 2usize * n + n * p
    if str.eq(c.name, "mfix") {
        var i = 0usize
        while i < nk + p {
            par[i] = z[ex + i]
            i += 1usize
        }
        ret od.clmm(a, xs, ys, gs, n, p, nk, ng, link, agq, false, par)
    }
    let what = usize(z[ex])
    if str.eq(c.name, "man") {
        // the reduced model keeps the first column of x
        let (x1, e4) = mem.alloc[f64](a, n)
        let (p1, e5) = mem.alloc[f64](a, nk + 1usize)
        let (an, e6) = mem.alloc[f64](a, 2usize)
        if e4 != ok || e5 != ok || e6 != ok { ret nan }
        var t = 0usize
        while t < n {
            x1[t] = xs[t * p]
            t += 1usize
        }
        let l0 = od.clmm(a, x1, ys, gs, n, 1usize, nk, ng, link, agq, true, p1)
        let l1 = od.clmm(a, xs, ys, gs, n, p, nk, ng, link, agq, true, par)
        od.clm_anova(l0, l1, 1.0f64, an)
        ret an[what]
    }
    let (re, e2) = mem.alloc[f64](a, ng)
    let (cv, e3) = mem.alloc[f64](a, ng)
    if e2 != ok || e3 != ok { ret nan }
    let ll = od.clmm_full(a, xs, ys, gs, n, p, nk, ng, link, agq, true, par, re, cv)
    if what == 0usize { ret ll }
    var s = 0.0f64
    var i = 0usize
    if what == 1usize {
        while i < nk - 1usize {
            s += par[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if what == 2usize {
        while i < p {
            s += par[nk - 1usize + i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if what == 3usize { ret par[nk - 1usize + p] }
    while i < ng {
        if what == 4usize { s += re[i] * f64(i + 1usize) } else { s += cv[i] * f64(i + 1usize) }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ordinal3.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    // this golden is minutes of compute per case, so it may be run in slices: `oracle_ordinal3 <first> <count>` (D7823)
    let (first, last) = oracle.slice(args, golden.cases.len)
    var at = first
    while at < last {
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
