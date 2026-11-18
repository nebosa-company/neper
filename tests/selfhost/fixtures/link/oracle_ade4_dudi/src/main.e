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
    if kind == 8usize {
        let nb = usize(z[6usize])
        let rw = z[7usize..7usize + n]
        let xt = z[7usize + n..7usize + n + n * p]
        let (fd, fe) = ad.dudi_fca(a, xt, n, p, rw, nb, nf)
        if fe != ok { os.exit(10) }
        if what == 0usize { ret fd.eig[idx] }
        if what == 1usize { ret fd.c1[idx] }
        if what == 2usize { ret fd.li[idx] }
        if what == 3usize { ret fd.co[idx] }
        if what == 4usize { ret fd.l1[idx] }
        ret f64(fd.rank)
    }
    if kind == 9usize {
        let nl = usize(z[6usize])
        let pq = usize(z[7usize])
        let rdat = z[8usize..8usize + n * p]
        let ldat = z[8usize + n * p..8usize + n * p + n * nl]
        let qdat = z[8usize + n * p + n * nl..8usize + n * p + n * nl + nl * pq]
        let (rt, g1) = mem.alloc[f64](a, n * p)
        let (rlw, g2) = mem.alloc[f64](a, n)
        let (rcw, g3) = mem.alloc[f64](a, p)
        let (lt, g4) = mem.alloc[f64](a, n * nl)
        let (llw, g5) = mem.alloc[f64](a, n)
        let (lcw, g6) = mem.alloc[f64](a, nl)
        let (qt, g7) = mem.alloc[f64](a, nl * pq)
        let (qcw, g8) = mem.alloc[f64](a, pq)
        if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok || g8 != ok { os.exit(11) }
        ad.pca_prep(a, rdat, n, p, true, true, rt, rlw, rcw)
        let ce = ad.coa_prep(a, ldat, n, nl, lt, llw, lcw)
        if ce != ok { os.exit(12) }
        ad.pca_prep_w(a, qdat, nl, pq, true, true, qt, lcw, qcw)
        let (rq, re) = ad.rlq(a, rt, rcw, n, p, lt, llw, lcw, nl, qt, qcw, pq, nf)
        if re != ok { os.exit(13) }
        if what == 0usize { ret rq.d.eig[idx] }
        if what == 1usize { ret rq.d.c1[idx] }
        if what == 2usize { ret rq.d.l1[idx] }
        if what == 3usize { ret rq.lr[idx] }
        if what == 4usize { ret rq.lq[idx] }
        ret f64(rq.d.rank)
    }
    if kind == 10usize {
        let kinds = z[6usize..6usize + p]
        let xt = z[6usize + p..6usize + p + n * p]
        let (md, me) = ad.dudi_mix(a, xt, kinds, n, p, nf)
        if me != ok { os.exit(14) }
        if what == 0usize { ret md.eig[idx] }
        if what == 1usize { ret md.c1[idx] }
        if what == 2usize { ret md.li[idx] }
        if what == 3usize { ret md.co[idx] }
        if what == 4usize { ret md.l1[idx] }
        ret f64(md.rank)
    }
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
        if what == 6usize { ret pr.rx[idx] }
        if what == 7usize { ret pr.ry[idx] }
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
        if what == 6usize {
            let (lw, g1) = mem.alloc[f64](a, n)
            let (cr, g2) = mem.alloc[f64](a, p * r.nf)
            if g1 != ok || g2 != ok { os.exit(15) }
            var q = 0usize
            while q < n {
                lw[q] = 1.0f64 / f64(n)
                q += 1usize
            }
            let ge = ad.acm_cr(a, x, n, p, lw, r.l1, r.nf, cr)
            if ge != ok { os.exit(16) }
            ret cr[idx]
        }
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
