// e.algo.stat.carets_vi against caret: preProcess ica and the varImp methods. tests/oracle/carets_vi.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R carets_vi`; the layout is at the top of
// scripts/r_oracle/groups/carets_vi.R.

use e.algo.stat.carets_vi as cv
use e.algo.stat.rpartfull as rf
use e.algo.stat.randomforest as rfm
use e.algo.stat.nnetpkg as nn
use e.io
use e.mem
use e.algo.rand.r as rng
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "ica") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let e = usize(z[2usize])
        let nx = usize(z[6usize])
        let id = usize(z[10usize])
        var r: rng.Rng = zero
        rng.seed(&r, i64(z[3usize]))
        let (k, e1) = mem.alloc[f64](a, p * e)
        let (w, e2) = mem.alloc[f64](a, e * e)
        let (sc, e3) = mem.alloc[f64](a, nx * e)
        if e1 != ok || e2 != ok || e3 != ok { ret nan }
        if cv.pre_process_ica(a, &r, z[11usize..11usize + n * p], n, p, e, z[7usize] > 0.5f64, z[8usize] > 0.5f64, z[9usize], usize(z[5usize]), z[4usize], z[11usize + n * p..11usize + n * p + nx * p], nx, k, w, sc) != ok { ret nan }
        var s = 0.0f64
        var q = 0usize
        if id == 0usize {
            while q < p * e {
                s += f64(q + 1usize) * k[q]
                q += 1usize
            }
            ret s
        }
        if id == 1usize {
            while q < e * e {
                s += f64(q + 1usize) * w[q]
                q += 1usize
            }
            ret s
        }
        if id == 2usize { ret k[0usize] }
        if id == 3usize {
            while q < nx * e {
                s += f64(q + 1usize) * sc[q]
                q += 1usize
            }
            ret s
        }
        while q < nx * e {
            s += sc[q] * sc[q]
            q += 1usize
        }
        ret s
    }
    if str.eq(c.name, "vig") {
        // (family, link, n, p, index, X[n p] intercept first, y[n])
        let n = usize(z[2usize])
        let p = usize(z[3usize])
        let (o, e1) = mem.alloc[f64](a, p)
        if e1 != ok { ret nan }
        if cv.var_imp_glm(a, z[5usize..5usize + n * p], n, p, z[5usize + n * p..5usize + n * p + n], usize(z[0usize]), usize(z[1usize]), o) != ok { ret nan }
        var s = 0.0f64
        var q = 0usize
        while q + 1usize < p {
            s += f64(q + 1usize) * o[q]
            q += 1usize
        }
        ret s
    }
    if str.eq(c.name, "vin") || str.eq(c.name, "vns") {
        var pp = usize(z[0usize])
        var hh = usize(z[1usize])
        var kk = usize(z[2usize])
        var skp = z[3usize] > 0.5f64
        var nw = 0usize
        var wv: []f64 = zero
        if str.eq(c.name, "vin") {
            nw = hh * (pp + 1usize) + kk * (1usize + hh)
            if skp { nw += kk * pp }
            let (w1, ew) = mem.alloc[f64](a, nw)
            if ew != ok { ret nan }
            var q = 0usize
            while q < nw {
                w1[q] = z[4usize + q]
                q += 1usize
            }
            wv = w1
        } else {
            // (n, p, h, k, mode, decay, maxit, skip, seed, rang, x, y, w)
            let nn_ = usize(z[0usize])
            pp = usize(z[1usize])
            hh = usize(z[2usize])
            kk = usize(z[3usize])
            let md = usize(z[4usize])
            skp = z[7usize] > 0.5f64
            nw = hh * (pp + 1usize) + kk * (1usize + hh)
            if skp { nw += kk * pp }
            let (w1, ew) = mem.alloc[f64](a, nw)
            let (fit, ef) = mem.alloc[f64](a, nn_ * kk)
            if ew != ok || ef != ok { ret nan }
            var g: rng.Rng = zero
            rng.seed(&g, i64(z[8usize]))
            var q = 0usize
            while q < nw {
                w1[q] = rng.runif(&g, 0.0f64 - z[9usize], z[9usize])
                q += 1usize
            }
            let xo = 10usize
            let yo = xo + nn_ * pp
            let wo = yo + nn_ * kk
            let _ = nn.nnet_fit(a, z[xo..yo], z[yo..wo], z[wo..wo + nn_], nn_, pp, hh, kk, md, skp, z[5usize], usize(z[6usize]), 1.0e-8f64, 1.0e-4f64, w1, fit)
            wv = w1
        }
        var nc = 1usize
        if kk > 1usize { nc = kk + 1usize }
        let (o, e1) = mem.alloc[f64](a, pp * nc)
        if e1 != ok { ret nan }
        if cv.var_imp_nnet(a, wv, pp, hh, kk, skp, o) != ok { ret nan }
        var s = 0.0f64
        var q2 = 0usize
        while q2 < pp * nc {
            s += f64(q2 + 1usize) * o[q2]
            q2 += 1usize
        }
        ret s
    }
    if str.eq(c.name, "vmn") {
        // (n, p, K, decay, y[n], x[n p] row-major, case weights[n])
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let nk = usize(z[2usize])
        let (coef, e1) = mem.alloc[f64](a, (nk - 1usize) * p)
        let (sev, e2) = mem.alloc[f64](a, (nk - 1usize) * p)
        let (o, e3) = mem.alloc[f64](a, p)
        if e1 != ok || e2 != ok || e3 != ok { ret nan }
        let _ = nn.multinom(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], n, p, nk, z[3usize], z[4usize + n + n * p..4usize + 2usize * n + n * p], coef, sev)
        cv.var_imp_multinom(coef, nk, p, o)
        var s = 0.0f64
        var q = 0usize
        while q + 1usize < p {
            s += f64(q + 1usize) * o[q]
            q += 1usize
        }
        ret s
    }
    if str.eq(c.name, "vrf") {
        // (kind, n, p, ntree, mtry, nodesize, sampsize, replace, nclass, seed, y[n], X[n p] row-major)
        let kind = usize(z[0usize])
        let n = usize(z[1usize])
        let p = usize(z[2usize])
        let kc = usize(z[8usize])
        var o: rfm.Opts = zero
        o.ntree = usize(z[3usize])
        o.mtry = usize(z[4usize])
        o.nodesize = usize(z[5usize])
        o.sampsize = usize(z[6usize])
        o.replace = z[7usize] != 0.0f64
        o.importance = true
        o.nperm = 1usize
        var g: rng.Rng = zero
        rng.seed(&g, i64(z[9usize]))
        let yv = z[10usize..10usize + n]
        let xd = z[10usize + n..10usize + n + n * p]
        var ts: rfm.TestSet = zero
        let (o2, e1) = mem.alloc[f64](a, p * (kc + 1usize))
        if e1 != ok { ret nan }
        var nc = p
        if kind == 0usize {
            let (cl, e3) = mem.alloc[i64](a, n)
            let (wt, e4) = mem.alloc[f64](a, kc)
            let (cut, e5) = mem.alloc[f64](a, kc)
            if e3 != ok || e4 != ok || e5 != ok { ret nan }
            var i = 0usize
            while i < n {
                cl[i] = i64(yv[i])
                i += 1usize
            }
            i = 0usize
            while i < kc {
                wt[i] = 0.0f64
                cut[i] = 1.0f64 / f64(kc)
                i += 1usize
            }
            let (f, ef) = rfm.rf_fit_class(a, &g, xd, cl, kc, n, p, wt, cut, &o, &ts)
            if ef != ok { ret nan }
            cv.var_imp_rf_class(&f, p, kc, o2)
            nc = p * kc
        } else {
            let (f, ef) = rfm.rf_fit_reg(a, &g, xd, yv, n, p, &o, &ts)
            if ef != ok { ret nan }
            cv.var_imp_rf_reg(&f, p, o2)
        }
        var s = 0.0f64
        var q3 = 0usize
        while q3 < nc {
            s += f64(q3 + 1usize) * o2[q3]
            q3 += 1usize
        }
        ret s
    }
    if str.eq(c.name, "vir") {
        // (n, p, method, k, minsplit, minbucket, cp, maxcompete, maxsurrogate, usesurrogate, surrogatestyle, maxdepth, ncat[p], y[n], X[n p])
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let (ctl, ec) = rf.rp_control(z[4usize], z[5usize], z[6usize], z[7usize], z[8usize], z[9usize], z[10usize], z[11usize], 0.0f64)
        if ec != ok { ret nan }
        let (ncat, e1) = mem.alloc[usize](a, p + 1usize)
        let (cost, e2) = mem.alloc[f64](a, p)
        let (wt, e3) = mem.alloc[f64](a, n)
        let (o, e4) = mem.alloc[f64](a, p)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
        var i = 0usize
        while i < p {
            ncat[i] = usize(z[12usize + i])
            cost[i] = 1.0f64
            i += 1usize
        }
        i = 0usize
        while i < n {
            wt[i] = 1.0f64
            i += 1usize
        }
        let y = z[12usize + p..12usize + p + n]
        let xm = z[12usize + p + n..12usize + p + n + n * p]
        var xg: []usize = zero
        let (fit, ef) = rf.rp_fit(a, xm, n, p, ncat, y, 1usize, wt, cost, usize(z[2usize]), usize(z[3usize]), z[0usize..0usize], ctl, xg)
        if ef != ok { ret nan }
        var t = fit
        let (view, ev) = rf.rp_view(a, &t)
        if ev != ok { ret nan }
        var s = 0.0f64
        var at = 0usize
        var f = 0usize
        while f < 4usize {
            cv.var_imp_rpart(&view, f >= 2usize, f % 2usize == 0usize, o)
            i = 0usize
            while i < p {
                at += 1usize
                s += f64(at) * o[i]
                i += 1usize
            }
            f += 1usize
        }
        ret s
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/carets_vi.json")
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
