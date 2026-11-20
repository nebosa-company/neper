// R earth: glm responses (glm = list(family = ...) fits a glm of each response on the selected basis functions) and cross-validation (nfold, ncross,
// stratify, pmethod = "cv"), as earth_glm, earth_cv and the nterms selection of earth.default do them. The fold groups are drawn with R's sample() from
// the caller's generator, in earth's order.
//
// Not here: binomial pairs, factor responses and their class rates, varmod, weights.

use e.algo.rand.r as rr
use e.algo.stat.armglm as ag
use e.algo.stat.earth as ea
use e.algo.stat.earthfit as ef
use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

// ---- glm

// family: 0 gaussian (identity), 1 binomial (logit), 2 poisson (log). stats[r * 8 ..]: nulldev, df.null, dev, df.residual, devratio, AIC, iter, converged
type GlmFit = struct { fam: usize, link: usize, nr: usize, nsel: usize, coef: []f64, stats: []f64 }

fn link_of(fam: usize) -> usize {
    if fam == 1usize { ret 3usize }
    if fam == 2usize { ret 1usize }
    ret 0usize
}

fn glm_aic(fam: usize, y: []const f64, mu: []const f64, dev: f64, n: usize, rank: usize, tmp: []f64) -> f64 {
    var aic = 0.0f64
    if fam == 0usize {
        let nobs = f64(n)
        aic = nobs * (math.log[f64](2.0f64 * 3.141592653589793f64 * dev / nobs) + 1.0f64) + 2.0f64
    }
    if fam == 1usize {
        var i = 0usize
        while i < n {
            tmp[i] = nb.dbinom(math.floor[f64](y[i] + 0.5f64), 1.0f64, mu[i], true)
            i += 1usize
        }
        aic = 0.0f64 - 2.0f64 * ef.ld_sum(tmp[0usize..n])
    }
    if fam == 2usize {
        var i = 0usize
        while i < n {
            tmp[i] = nm.dpois(y[i], mu[i], true)
            i += 1usize
        }
        aic = 0.0f64 - 2.0f64 * ef.ld_sum(tmp[0usize..n])
    }
    ret aic + 2.0f64 * f64(rank)
}

fn devratio(nulldev: f64, dev: f64) -> f64 {
    let r = (nulldev - dev) / nulldev
    if nulldev < 0.0f64 || r != r { ret 0.0f64 / 0.0f64 }
    if r < 1.0e-4f64 { ret 0.0f64 }
    ret r
}

// glm(y ~ ., family) of every response column of y on the selected basis functions of f (the intercept column included)
fn glm_fit_resps(a: *mem.Arena, f: *const ef.EFit, y: []const f64, fam: usize) -> (GlmFit, err) {
    var g: GlmFit = zero
    let n = f.n
    let k = f.nsel
    let nr = f.nr
    let link = link_of(fam)
    let (coef, e1) = mem.alloc[f64](a, k * nr + 1usize)
    let (stats, e2) = mem.alloc[f64](a, nr * 8usize + 1usize)
    let (cv, e3) = mem.alloc[f64](a, k * k + 1usize)
    let (info, e4) = mem.alloc[f64](a, 8usize)
    let (mu, e5) = mem.alloc[f64](a, n + 1usize)
    let (tmp, e6) = mem.alloc[f64](a, n + 1usize)
    let (cf, e7) = mem.alloc[f64](a, k + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (g, mem.Exhausted) }
    let none = f.fitted[0usize..0usize]
    let (xrow, e8) = mem.alloc[f64](a, n * k + 1usize)
    if e8 != ok { ret (g, mem.Exhausted) }
    var ti = 0usize
    while ti < n {
        var tc = 0usize
        while tc < k {
            xrow[ti * k + tc] = f.bx[tc * n + ti]
            tc += 1usize
        }
        ti += 1usize
    }
    var r = 0usize
    while r < nr {
        let yr = y[r * n..r * n + n]
        let it = ag.glm_fit_gen(a, xrow, yr, n, k, fam, link, none, none, true, cf, cv, info)
        if it == 0usize { ret (g, ea.EarthFailed) }
        var i = 0usize
        while i < k {
            coef[i + r * k] = cf[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            var eta = 0.0f64
            var c = 0usize
            while c < k {
                eta += f.bx[c * n + i] * cf[c]
                c += 1usize
            }
            mu[i] = ag.linkinv(link, eta)
            i += 1usize
        }
        let dev = info[1usize]
        let nulldev = info[2usize]
        var iters = f64(it)
        var conv = 1.0f64
        if it == 26usize {
            iters = 25.0f64
            conv = 0.0f64
        }
        stats[r * 8usize] = nulldev
        stats[r * 8usize + 1usize] = f64(n) - 1.0f64
        stats[r * 8usize + 2usize] = dev
        stats[r * 8usize + 3usize] = info[4usize]
        stats[r * 8usize + 4usize] = devratio(nulldev, dev)
        stats[r * 8usize + 5usize] = glm_aic(fam, yr, mu, dev, n, k, tmp)
        stats[r * 8usize + 6usize] = iters
        stats[r * 8usize + 7usize] = conv
        r += 1usize
    }
    g.fam = fam
    g.link = link
    g.nr = nr
    g.nsel = k
    g.coef = coef
    g.stats = stats
    ret (g, ok)
}

// predict.glm on the earth basis functions of the m rows of x: type 0 link, 1 response
fn glm_predict(a: *mem.Arena, f: *const ef.EFit, g: *const GlmFit, x: []const f64, m: usize, kind: usize, out: []f64) -> err {
    let (bx, e) = ef.get_bx(a, x, m, f.p, f.dirs, f.cuts, f.nt, f.sel, f.nsel)
    if e != ok { ret e }
    var r = 0usize
    while r < f.nr {
        var i = 0usize
        while i < m {
            var eta = 0.0f64
            var c = 0usize
            while c < f.nsel {
                eta += bx[c * m + i] * g.coef[c + r * f.nsel]
                c += 1usize
            }
            if kind == 1usize { eta = ag.linkinv(g.link, eta) }
            out[i + r * m] = eta
            i += 1usize
        }
        r += 1usize
    }
    ret ok
}

// ---- cross-validation helpers

fn nused_preds(f: *const ef.EFit) -> usize {
    var c = 0usize
    var j = 0usize
    while j < f.p {
        var any = false
        var k = 0usize
        while k < f.nsel {
            if f.dirs[f.sel[k] + j * f.nt] != 0i64 { any = true }
            k += 1usize
        }
        if any { c += 1usize }
        j += 1usize
    }
    ret c
}

// get.weighted.rsq with unit weights
fn rsq_of(a: *mem.Arena, y: []const f64, yhat: []const f64, n: usize) -> f64 {
    let mark = mem.mark(a)
    let (t, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        t[i] = (y[i] - yhat[i]) * (y[i] - yhat[i])
        i += 1usize
    }
    let rss = ef.ld_sum(t[0usize..n])
    let mu = ef.ld_sum(y[0usize..n]) / f64(n)
    i = 0usize
    while i < n {
        t[i] = (y[i] - mu) * (y[i] - mu)
        i += 1usize
    }
    let tss = ef.ld_sum(t[0usize..n])
    mem.reset(a, mark)
    ret ea.get_rsq(rss, tss)
}

// the element of largest absolute value (the first on ties), with its sign
fn max_err(x: []const f64, n: usize) -> f64 {
    var best = 0usize
    var bv = math.abs[f64](x[0usize])
    var i = 1usize
    while i < n {
        let v = math.abs[f64](x[i])
        if v > bv {
            bv = v
            best = i
        }
        i += 1usize
    }
    ret x[best]
}

// the average rank of every value
fn avg_ranks(v: []const f64, n: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var less = 0usize
        var eq = 0usize
        var j = 0usize
        while j < n {
            if v[j] < v[i] { less += 1usize }
            if v[j] == v[i] { eq += 1usize }
            j += 1usize
        }
        out[i] = f64(less) + (f64(eq) + 1.0f64) / 2.0f64
        i += 1usize
    }
}

fn auc_of(a: *mem.Arena, yhat: []const f64, y: []const f64, n: usize) -> f64 {
    let (xy, e1) = mem.alloc[f64](a, n + 1usize)
    let (rk, e2) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var nx = 0usize
    var i = 0usize
    while i < n {
        if !(y[i] > 0.5f64) {
            xy[nx] = yhat[i]
            nx += 1usize
        }
        i += 1usize
    }
    var ny = 0usize
    i = 0usize
    while i < n {
        if y[i] > 0.5f64 {
            xy[nx + ny] = yhat[i]
            ny += 1usize
        }
        i += 1usize
    }
    avg_ranks(xy, n, rk)
    var s = 0.0f64
    i = 0usize
    while i < nx {
        s += rk[i]
        i += 1usize
    }
    let fx = f64(nx)
    let fy = f64(ny)
    let wilc = fx * fy + (fx * (fx + 1.0f64)) / 2.0f64 - s
    ret wilc / (fx * fy)
}

// glm(y ~ v, family): (intercept, slope)
fn calib_fit(a: *mem.Arena, v: []const f64, y: []const f64, n: usize, fam: usize) -> (f64, f64) {
    let (xd, e1) = mem.alloc[f64](a, 2usize * n)
    let (cf, e2) = mem.alloc[f64](a, 2usize)
    let (cv, e3) = mem.alloc[f64](a, 4usize)
    let (info, e4) = mem.alloc[f64](a, 8usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    var i = 0usize
    while i < n {
        xd[2usize * i] = 1.0f64
        xd[2usize * i + 1usize] = v[i]
        i += 1usize
    }
    let none = v[0usize..0usize]
    let it = ag.glm_fit_gen(a, xd, y, n, 2usize, fam, link_of(fam), none, none, true, cf, cv, info)
    if it == 0usize { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    ret (cf[0usize], cf[1usize])
}

// cor(x, y) as R's two-pass algorithm computes it
fn cor_of(x: []const f64, y: []const f64, n: usize) -> f64 {
    let mx = ef.ld_sum(x[0usize..n]) / f64(n)
    let my = ef.ld_sum(y[0usize..n]) / f64(n)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < n {
        let dx = x[i] - mx
        let dy = y[i] - my
        sxy += dx * dy
        sxx += dx * dx
        syy += dy * dy
        i += 1usize
    }
    ret sxy / (math.sqrt[f64](sxx) * math.sqrt[f64](syy))
}

// ---- earth_cv

type Cv = struct {
    ntab: usize,
    nr: usize,
    maxn: usize,
    rsq: []f64,
    maxerr: []f64,
    nterms: []f64,
    nvars: []f64,
    groups: []usize,
    oof: []f64,
    infold: []f64,
    has_oof: bool,
    has_glm: bool,
    dev: []f64,
    cint: []f64,
    cslope: []f64,
    test: []f64,
    ncross: usize,
    nfold: usize,
    n: usize,
}

// get.groups: sample(rep(1:nfold, length.out = n)), then for every response the cases with y != 0 are redrawn
fn get_groups(a: *mem.Arena, rng: *rr.Rng, y: []const f64, n: usize, nr: usize, nfold: usize, stratify: bool, out: []usize) -> err {
    let (perm, e1) = rr.sample_int(a, rng, i64(n), i64(n), false)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        out[i] = (usize(perm[i]) - 1usize) % nfold + 1usize
        i += 1usize
    }
    if stratify {
        var r = 0usize
        while r < nr {
            var m = 0usize
            i = 0usize
            while i < n {
                if y[r * n + i] != 0.0f64 { m += 1usize }
                i += 1usize
            }
            let (pm, e2) = rr.sample_int(a, rng, i64(m), i64(m), false)
            if e2 != ok { ret e2 }
            var q = 0usize
            i = 0usize
            while i < n {
                if y[r * n + i] != 0.0f64 {
                    out[i] = (usize(pm[q]) - 1usize) % nfold + 1usize
                    q += 1usize
                }
                i += 1usize
            }
            r += 1usize
        }
    }
    ret ok
}

fn rows_of(x: []const f64, n: usize, p: usize, rows: []const usize, m: usize, out: []f64) {
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < m {
            out[i + j * m] = x[rows[i] + j * n]
            i += 1usize
        }
        j += 1usize
    }
}

// earth_cv: `full` is the model fitted to all the data (backward pruning when pmethod is cv), nterms_full its number of terms before pruning. o carries the earth
// arguments of the full model; glm_fam is 0 gaussian, 1 binomial, 2 poisson for a glm model and 3 for none. keep_oof asks for the out-of-fold RSq per subset size
fn earth_cv(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, nr: usize, o: *const ef.Opts, nterms_full: usize, scaled: bool, glm_fam: usize, nfold_in: usize, ncross: usize, stratify: bool, keep_oof: bool, rng: *rr.Rng) -> (Cv, err) {
    var cv: Cv = zero
    var nfold = nfold_in
    if nfold > n { nfold = n }
    let ntab = ncross * nfold + 1usize
    let maxn = nterms_full
    cv.ntab = ntab
    cv.nr = nr
    cv.maxn = maxn
    cv.ncross = ncross
    cv.nfold = nfold
    cv.n = n
    cv.has_oof = keep_oof
    cv.has_glm = glm_fam == 1usize || glm_fam == 2usize
    let (rsq, e1) = mem.alloc[f64](a, ntab * (nr + 1usize))
    let (maxerr, e2) = mem.alloc[f64](a, ntab * (nr + 1usize))
    let (nterms, e3) = mem.alloc[f64](a, ntab)
    let (nvars, e4) = mem.alloc[f64](a, ntab)
    let (groups, e5) = mem.alloc[usize](a, ncross * n)
    let (oof, e6) = mem.alloc[f64](a, ntab * maxn)
    let (infold, e7) = mem.alloc[f64](a, ntab * maxn)
    let (dev, e8) = mem.alloc[f64](a, ntab * (nr + 1usize))
    let (cint, e9) = mem.alloc[f64](a, ntab * (nr + 1usize))
    let (cslope, e10) = mem.alloc[f64](a, ntab * (nr + 1usize))
    let (test, e11) = mem.alloc[f64](a, ntab * (nr + 1usize))
    let (fitall, e12) = mem.alloc[f64](a, n * nr)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (cv, mem.Exhausted) }
    var z = 0usize
    while z < ntab * (nr + 1usize) {
        rsq[z] = 0.0f64
        maxerr[z] = 0.0f64
        dev[z] = 0.0f64
        cint[z] = 0.0f64
        cslope[z] = 0.0f64
        test[z] = 0.0f64
        z += 1usize
    }
    z = 0usize
    while z < ntab * maxn {
        oof[z] = 0.0f64
        infold[z] = 0.0f64
        z += 1usize
    }
    // the groups of every cross
    var ic = 0usize
    while ic < ncross {
        let e = get_groups(a, rng, y, n, nr, nfold, stratify, groups[ic * n..ic * n + n])
        if e != ok { ret (cv, e) }
        ic += 1usize
    }
    let (oofrows, e13) = mem.alloc[usize](a, n)
    let (inrows, e14) = mem.alloc[usize](a, n)
    if e13 != ok || e14 != ok { ret (cv, mem.Exhausted) }
    var fo = o.scale_y
    if scaled { fo = 1i64 } else { fo = 0i64 }
    ic = 0usize
    while ic < ncross {
        var ifold = 1usize
        while ifold <= nfold {
            let row = ic * nfold + ifold - 1usize
            var no = 0usize
            var ni = 0usize
            var i = 0usize
            while i < n {
                if groups[ic * n + i] == ifold {
                    oofrows[no] = i
                    no += 1usize
                } else {
                    inrows[ni] = i
                    ni += 1usize
                }
                i += 1usize
            }
            let mark = mem.mark(a)
            let (xi, e15) = mem.alloc[f64](a, ni * p)
            let (yi, e16) = mem.alloc[f64](a, ni * nr)
            let (xo, e17) = mem.alloc[f64](a, no * p)
            let (yo, e18) = mem.alloc[f64](a, no * nr)
            if e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret (cv, mem.Exhausted) }
            rows_of(x, n, p, inrows, ni, xi)
            rows_of(x, n, p, oofrows, no, xo)
            var r = 0usize
            while r < nr {
                var q = 0usize
                while q < ni {
                    yi[q + r * ni] = y[inrows[q] + r * n]
                    q += 1usize
                }
                q = 0usize
                while q < no {
                    yo[q + r * no] = y[oofrows[q] + r * n]
                    q += 1usize
                }
                r += 1usize
            }
            var o2 = *o
            o2.scale_y = fo
            o2.nprune = 0usize
            if o2.pmethod == 5usize { o2.pmethod = 0usize }
            let (fm, fwd, e19) = ef.earth_fit_fwd(a, xi, yi, ni, p, nr, &o2)
            if e19 != ok { ret (cv, e19) }
            let (pf, e20) = mem.alloc[f64](a, no * nr)
            let (pr2, e21) = mem.alloc[f64](a, no * nr)
            if e20 != ok || e21 != ok { ret (cv, mem.Exhausted) }
            let ep = ef.predict_rows(a, &fm, xo, no, pf)
            if ep != ok { ret (cv, ep) }
            var gf: GlmFit = zero
            if cv.has_glm {
                let (g2, e22) = glm_fit_resps(a, &fm, yi, glm_fam)
                if e22 != ok { ret (cv, e22) }
                gf = g2
                let e23 = glm_predict(a, &fm, &gf, xo, no, 1usize, pr2)
                if e23 != ok { ret (cv, e23) }
            }
            r = 0usize
            while r < nr {
                let yoc = yo[r * no..r * no + no]
                rsq[row + r * ntab] = rsq_of(a, yoc, pf[r * no..r * no + no], no)
                // the residuals against the earth fit, or against the glm response
                let (er, e24) = mem.alloc[f64](a, no + 1usize)
                if e24 != ok { ret (cv, mem.Exhausted) }
                var q = 0usize
                if cv.has_glm {
                    let ph = pr2[r * no..r * no + no]
                    while q < no {
                        er[q] = yoc[q] - ph[q]
                        q += 1usize
                    }
                    maxerr[row + r * ntab] = max_err(er, no)
                    if glm_fam == 1usize {
                        var sdv = 0.0f64
                        let (tmp, e25) = mem.alloc[f64](a, no + 1usize)
                        let (lg, e26) = mem.alloc[f64](a, no + 1usize)
                        if e25 != ok || e26 != ok { ret (cv, mem.Exhausted) }
                        q = 0usize
                        while q < no {
                            tmp[q] = yoc[q] * math.log[f64](ph[q]) + (1.0f64 - yoc[q]) * math.log[f64](1.0f64 - ph[q])
                            q += 1usize
                        }
                        sdv = 0.0f64 - 2.0f64 * ef.ld_sum(tmp[0usize..no])
                        dev[row + r * ntab] = sdv / f64(no)
                        q = 0usize
                        while q < no {
                            var yh = ph[q] + 1.0e-5f64
                            if yh >= 1.0f64 { yh = 0.99999f64 }
                            lg[q] = math.log[f64](yh / (1.0f64 - yh))
                            q += 1usize
                        }
                        let (c0, c1) = calib_fit(a, lg, yoc, no, 1usize)
                        cint[row + r * ntab] = c0
                        cslope[row + r * ntab] = c1
                        test[row + r * ntab] = auc_of(a, ph, yoc, no)
                    } else {
                        let (tmp, e25) = mem.alloc[f64](a, no + 1usize)
                        let (lg, e26) = mem.alloc[f64](a, no + 1usize)
                        if e25 != ok || e26 != ok { ret (cv, mem.Exhausted) }
                        q = 0usize
                        while q < no {
                            var c = 0.0f64
                            if yoc[q] != 0.0f64 { c = yoc[q] * math.log[f64](yoc[q] / ph[q]) }
                            tmp[q] = c - (yoc[q] - ph[q])
                            lg[q] = math.log[f64](ph[q])
                            q += 1usize
                        }
                        dev[row + r * ntab] = 2.0f64 * ef.ld_sum(tmp[0usize..no]) / f64(no)
                        let (c0, c1) = calib_fit(a, lg, yoc, no, 2usize)
                        cint[row + r * ntab] = c0
                        cslope[row + r * ntab] = c1
                        test[row + r * ntab] = cor_of(ph, yoc, no)
                    }
                } else {
                    let ph = pf[r * no..r * no + no]
                    while q < no {
                        er[q] = yoc[q] - ph[q]
                        q += 1usize
                    }
                    maxerr[row + r * ntab] = max_err(er, no)
                }
                r += 1usize
            }
            nvars[row] = f64(nused_preds(&fm))
            nterms[row] = f64(fm.nsel)
            if keep_oof {
                // out-of-fold and in-fold RSq of the model pruned to each size with penalty -1
                let (allfit, e27) = mem.alloc[f64](a, n * nr)
                if e27 != ok { ret (cv, mem.Exhausted) }
                let nlim = maxn
                var k = 1usize
                while k <= nlim {
                    if k <= fm.nt {
                        let mark2 = mem.mark(a)
                        let (pf2, e28) = ef.prune_and_fit(a, yi, ni, p, nr, &fwd, o2.nk, o2.thresh, 0.0f64 - 1.0f64, fm.pmethod, k)
                        if e28 != ok { ret (cv, e28) }
                        let e29 = ef.predict_rows(a, &pf2, x, n, allfit)
                        if e29 != ok { ret (cv, e29) }
                        var so = 0.0f64
                        var si = 0.0f64
                        let (ov, e30) = mem.alloc[f64](a, no + 1usize)
                        let (oy, e31) = mem.alloc[f64](a, no + 1usize)
                        let (iv, e32) = mem.alloc[f64](a, ni + 1usize)
                        let (iy, e33) = mem.alloc[f64](a, ni + 1usize)
                        if e30 != ok || e31 != ok || e32 != ok || e33 != ok { ret (cv, mem.Exhausted) }
                        r = 0usize
                        while r < nr {
                            var q2 = 0usize
                            while q2 < no {
                                ov[q2] = allfit[oofrows[q2] + r * n]
                                oy[q2] = y[oofrows[q2] + r * n]
                                q2 += 1usize
                            }
                            q2 = 0usize
                            while q2 < ni {
                                iv[q2] = allfit[inrows[q2] + r * n]
                                iy[q2] = y[inrows[q2] + r * n]
                                q2 += 1usize
                            }
                            let w = 1.0f64 / f64(nr)
                            so = so + w * rsq_of(a, oy, ov, no)
                            si = si + w * rsq_of(a, iy, iv, ni)
                            r += 1usize
                        }
                        oof[row + (k - 1usize) * ntab] = so
                        infold[row + (k - 1usize) * ntab] = si
                        mem.reset(a, mark2)
                    } else {
                        oof[row + (k - 1usize) * ntab] = 0.0f64 / 0.0f64
                        infold[row + (k - 1usize) * ntab] = 0.0f64 / 0.0f64
                    }
                    k += 1usize
                }
            }
            // the summary column: the mean over the responses
            var srsq = 0.0f64
            r = 0usize
            while r < nr {
                srsq += rsq[row + r * ntab]
                r += 1usize
            }
            rsq[row + nr * ntab] = srsq / f64(nr)
            let (me, e34) = mem.alloc[f64](a, nr + 1usize)
            if e34 != ok { ret (cv, mem.Exhausted) }
            r = 0usize
            while r < nr {
                me[r] = maxerr[row + r * ntab]
                r += 1usize
            }
            maxerr[row + nr * ntab] = max_err(me, nr)
            if cv.has_glm {
                var sd = 0.0f64
                var sc = 0.0f64
                var ss = 0.0f64
                var st = 0.0f64
                r = 0usize
                while r < nr {
                    sd += dev[row + r * ntab]
                    sc += cint[row + r * ntab]
                    ss += cslope[row + r * ntab]
                    st += test[row + r * ntab]
                    r += 1usize
                }
                dev[row + nr * ntab] = sd / f64(nr)
                cint[row + nr * ntab] = sc / f64(nr)
                cslope[row + nr * ntab] = ss / f64(nr)
                test[row + nr * ntab] = st / f64(nr)
            }
            let keep_rows = mark
            let _kr = keep_rows
            // the data of this fold are not needed again, but the tables above are outside the mark
            mem.reset(a, mark)
            ifold += 1usize
        }
        ic += 1usize
    }
    // the last row of every table: the mean over the folds (the signed maximum for the maximum errors)
    let last = ntab - 1usize
    var c = 0usize
    while c <= nr {
        var s1 = 0.0f64
        var s2 = 0.0f64
        var s3 = 0.0f64
        var s4 = 0.0f64
        var s5 = 0.0f64
        var q = 0usize
        let (col, e35) = mem.alloc[f64](a, ntab)
        if e35 != ok { ret (cv, mem.Exhausted) }
        while q < last {
            s1 += rsq[q + c * ntab]
            s2 += dev[q + c * ntab]
            s3 += cint[q + c * ntab]
            s4 += cslope[q + c * ntab]
            s5 += test[q + c * ntab]
            col[q] = maxerr[q + c * ntab]
            q += 1usize
        }
        rsq[last + c * ntab] = s1 / f64(last)
        maxerr[last + c * ntab] = max_err(col, last)
        if cv.has_glm {
            dev[last + c * ntab] = s2 / f64(last)
            cint[last + c * ntab] = s3 / f64(last)
            cslope[last + c * ntab] = s4 / f64(last)
            test[last + c * ntab] = s5 / f64(last)
        }
        c += 1usize
    }
    var s6 = 0.0f64
    var s7 = 0.0f64
    var q2 = 0usize
    while q2 < last {
        s6 += nterms[q2]
        s7 += nvars[q2]
        q2 += 1usize
    }
    nterms[last] = s6 / f64(last)
    nvars[last] = s7 / f64(last)
    if keep_oof {
        var k = 0usize
        while k < maxn {
            var sa = 0.0f64
            var sb = 0.0f64
            var na = 0usize
            var q3 = 0usize
            while q3 < last {
                let va = oof[q3 + k * ntab]
                let vb = infold[q3 + k * ntab]
                if va == va {
                    sa += va
                    sb += vb
                    na += 1usize
                }
                q3 += 1usize
            }
            if na * 2usize > last || na == last {
                oof[last + k * ntab] = sa / f64(na)
                infold[last + k * ntab] = sb / f64(na)
            } else {
                oof[last + k * ntab] = 0.0f64 / 0.0f64
                infold[last + k * ntab] = 0.0f64 / 0.0f64
            }
            k += 1usize
        }
    }
    cv.rsq = rsq
    cv.maxerr = maxerr
    cv.nterms = nterms
    cv.nvars = nvars
    cv.groups = groups
    cv.oof = oof
    cv.infold = infold
    cv.dev = dev
    cv.cint = cint
    cv.cslope = cslope
    cv.test = test
    let _fa = fitall
    ret (cv, ok)
}

// the size of the model pmethod = "cv" selects: the first size with the largest mean out-of-fold RSq among the first limit sizes
fn cv_size(cv: *const Cv, limit: usize) -> usize {
    var lim = limit
    if lim == 0usize || lim > cv.maxn { lim = cv.maxn }
    var best = 0usize
    var bv = 0.0f64 - 1.0e300f64
    var found = false
    var k = 0usize
    while k < lim {
        let v = cv.oof[(cv.ntab - 1usize) + k * cv.ntab]
        if v == v && (!found || v > bv) {
            bv = v
            best = k
            found = true
        }
        k += 1usize
    }
    ret best + 1usize
}

type Model = struct { f: ef.EFit, g: GlmFit, has_glm: bool, cv: Cv, has_cv: bool }

// earth() on a numeric matrix with the glm and cross-validation arguments: glm_fam 3 for none, nfold 0 for no cross-validation. pmethod 5 is "cv": the model
// is pruned to the size the cross-validation chose (o.nprune, when set, limits the sizes considered)
fn earth_model(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, nr: usize, o: *const ef.Opts, glm_fam: usize, nfold: usize, ncross: usize, stratify: bool, keep_oof: bool, rng: *rr.Rng) -> (Model, err) {
    var m: Model = zero
    var o1 = *o
    var cvm = o.pmethod == 5usize
    if cvm {
        o1.pmethod = 0usize
        o1.nprune = 0usize
    }
    let (f0, fwd, e1) = ef.earth_fit_fwd(a, x, y, n, p, nr, &o1)
    if e1 != ok { ret (m, e1) }
    var scaled = o.scale_y == 1i64
    if o.scale_y < 0i64 && nr == 1usize { scaled = true }
    var fin = f0
    if nfold > 1usize && ncross >= 1usize {
        let (cv, e2) = earth_cv(a, x, y, n, p, nr, &o1, f0.nt, scaled, glm_fam, nfold, ncross, stratify, keep_oof || cvm, rng)
        if e2 != ok { ret (m, e2) }
        m.cv = cv
        m.has_cv = true
        if cvm {
            let sz = cv_size(&m.cv, o.nprune)
            let (f2, e3) = ef.prune_and_fit(a, y, n, p, nr, &fwd, o.nk, o.thresh, o.penalty, 5usize, sz)
            if e3 != ok { ret (m, e3) }
            fin = f2
        }
    }
    m.f = fin
    if glm_fam < 3usize {
        let (g, e4) = glm_fit_resps(a, &m.f, y, glm_fam)
        if e4 != ok { ret (m, e4) }
        m.g = g
        m.has_glm = true
    }
    ret (m, ok)
}
