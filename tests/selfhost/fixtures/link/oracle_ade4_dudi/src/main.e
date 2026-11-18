// e.algo.stat.ade4 against ade4 (dudi.pca, dudi.coa). tests/oracle/ade4_dudi.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ade4_dudi`; the layout is at the top of scripts/r_oracle/groups/ade4_dudi.R.

use e.algo.stat.ade4 as ad
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let nf = usize(z[3usize])
    let what = usize(z[4usize])
    let idx = usize(z[5usize])
    if kind == 7usize {
        let py = usize(z[6usize])
        let sc = z[7usize] > 0.5f64
        let xt = z[8usize..8usize + n * p]
        let yt = z[8usize + n * p..8usize + n * p + n * py]
        let (pr, pe) = ad.procuste(a, xt, yt, n, p, py, sc, nf, 0.0000001f64)
        if pe != ok { os.exit(9) }
        if what == 0usize { ret pr.d[idx] }
        if what == 1usize { ret pr.lx[idx] }
        if what == 2usize { ret pr.ly[idx] }
        if what == 3usize { ret pr.sx[idx] }
        if what == 4usize { ret pr.sy[idx] }
        ret f64(pr.rank)
    }
    if kind == 6usize {
        let py = usize(z[6usize])
        let xt = z[7usize..7usize + n * p]
        let yt = z[7usize + n * p..7usize + n * p + n * py]
        let (t1, f1) = mem.alloc[f64](a, n * p)
        let (l1, f2) = mem.alloc[f64](a, n)
        let (c1, f3) = mem.alloc[f64](a, p)
        let (t2, f4) = mem.alloc[f64](a, n * py)
        let (l2, f5) = mem.alloc[f64](a, n)
        let (c2, f6) = mem.alloc[f64](a, py)
        if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok { os.exit(7) }
        ad.pca_prep(a, xt, n, p, true, true, t1, l1, c1)
        ad.pca_prep(a, yt, n, py, true, true, t2, l2, c2)
        let (ci, ce) = ad.coinertia(a, t1, t2, n, p, py, l1, c1, c2, nf)
        if ce != ok { os.exit(8) }
        if what == 0usize { ret ci.d.eig[idx] }
        if what == 1usize { ret ci.d.c1[idx] }
        if what == 2usize { ret ci.d.l1[idx] }
        if what == 3usize { ret ci.lx[idx] }
        if what == 4usize { ret ci.ly[idx] }
        if what == 5usize { ret f64(ci.d.rank) }
        ret ci.rv
    }
    let x = z[6usize..6usize + n * p]
    var d: ad.Dudi = zero
    var e = ok
    var ratio = 0.0f64
    if kind >= 4usize {
        let fac = z[6usize + n * p..6usize + n * p + n]
        let (t, e1) = mem.alloc[f64](a, n * p)
        let (lw, e2) = mem.alloc[f64](a, n)
        let (cw, e3) = mem.alloc[f64](a, p)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(6) }
        ad.pca_prep(a, x, n, p, true, true, t, lw, cw)
        var nl = 0usize
        var i = 0usize
        while i < n {
            if usize(fac[i]) + 1usize > nl { nl = usize(fac[i]) + 1usize }
            i += 1usize
        }
        if kind == 4usize {
            let (r, rt, er) = ad.bca(a, t, n, p, lw, cw, fac, nl, nf)
            d = r
            ratio = rt
            e = er
        } else {
            let (r, rt, er) = ad.wca(a, t, n, p, lw, cw, fac, nl, nf)
            d = r
            ratio = rt
            e = er
        }
    } else if kind == 0usize {
        let (r, er) = ad.dudi_pca(a, x, n, p, true, true, nf)
        d = r
        e = er
    } else if kind == 1usize {
        let (r, er) = ad.dudi_pca(a, x, n, p, true, false, nf)
        d = r
        e = er
    } else if kind == 3usize {
        let (r, er) = ad.dudi_acm(a, x, n, p, nf)
        d = r
        e = er
    } else {
        let (r, er) = ad.dudi_coa(a, x, n, p, nf)
        d = r
        e = er
    }
    if e != ok { os.exit(5) }
    if what == 6usize { ret ratio }
    if what == 0usize { ret d.eig[idx] }
    if what == 1usize { ret d.c1[idx] }
    if what == 2usize { ret d.li[idx] }
    if what == 3usize { ret d.co[idx] }
    if what == 4usize { ret d.l1[idx] }
    ret f64(d.rank)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ade4_dudi.json")
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
