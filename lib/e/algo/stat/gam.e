// R package gam (Hastie): the backfitting generalized additive model gam(y ~ s(x1) + s(x2) + z, family) with smoothing-spline terms s().
//
// A port of the package Fortran: splsm (the smoothing spline of one term on the unique signif(x, 6) values, with df matching by the
// package sbart Brent search over spar in [-1.5, 2] or a fixed spar), bakfit/backf1 (backfitting against the weighted QR of the parametric part,
// LINPACK dqrdc2 pivoting at tol 1e-7) and gam.fit (the IRLS loop over the Gaussian, binomial/logit and Poisson/log families).
// The package sgram constant .3330 is a REAL*4 literal, so the penalty uses its double widening, not 0.333.
// The spline returned for a df-matched term is the one from the LAST Brent evaluation (as the package returns it), not the refit at the minimiser.
//
// lo() terms of one variable (degree 1 or 2) follow the package loess (kd-tree vertices, Hermite interpolation, exact leverages); a model mixing s() and lo() runs the package general.wam order.
//
// predict at newdata (gam_predict, values only: R gives no standard errors there) covers s() terms and lo() terms of degree 1 or 2 inside the data box.
// Not here: lo() of two or more variables, the random() smoother, NA handling, knot thinning above 3199 unique x.

use e.math
use e.mem
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.algo.stat.smspline as sm
use e.algo.linalg.decomp as dc
use e.algo.stat.loessfit as lf
use e.algo.stat.gbmfit as gb


type GamFit = struct {
    coef: []f64, eta: []f64, mu: []f64, smooth: []f64, nldf: []f64, levs: []f64, spar: []f64, weights: []f64, resid: []f64,
    nl_chisq: []f64, bf_iter: []usize, deviance: f64, null_dev: f64, aic: f64, df_resid: f64, df_null: f64, iter: usize, rank: usize, q: usize, n: usize, p: usize,
    par_df: []f64, par_ss: []f64, par_f: []f64, par_p: []f64, ssr: f64, disp: f64, np_df: []f64, np_stat: []f64, np_p: []f64, se_link: []f64, se_resp: []f64
}

fn empty_f() -> []f64 {
    var e: []f64 = zero
    ret e
}

fn zal(a: *mem.Arena, n: usize) -> []f64 {
    let (v, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret empty_f() }
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0.0f64
        i += 1usize
    }
    ret v[0usize..n]
}

fn ab(r: usize, c: usize) -> usize { ret (r - 1usize) + 4usize * (c - 1usize) }

fn nearbyint(v: f64) -> f64 {
    let r = math.floor[f64](v)
    let d = v - r
    if d > 0.5f64 { ret r + 1.0f64 }
    if d < 0.5f64 { ret r }
    let h = math.floor[f64](r / 2.0f64) * 2.0f64
    if h == r { ret r }
    ret r + 1.0f64
}

fn pow10i(e: i64) -> f64 {
    var v = 1.0f64
    var i = 0i64
    while i < e {
        v *= 10.0f64
        i += 1i64
    }
    ret v
}

// R signif(x, 6)
fn signif6(x: f64) -> f64 {
    if x == 0.0f64 { ret x }
    var sg = 1.0f64
    var ax = x
    if x < 0.0f64 {
        sg = 0.0f64 - 1.0f64
        ax = 0.0f64 - x
    }
    let l10 = math.log10[f64](ax)
    let e10 = i64(5.0f64 - math.floor[f64](l10))
    if e10 > 0i64 {
        let p = pow10i(e10)
        ret sg * (nearbyint(ax * p) / p)
    }
    let p2 = pow10i(0i64 - e10)
    ret sg * (nearbyint(ax / p2) * p2)
}

fn sknotl_ndk(n: usize) -> usize {
    if n < 50usize { ret n }
    let a1 = math.log[f64](50.0f64) / math.log[f64](2.0f64)
    let a2 = math.log[f64](100.0f64) / math.log[f64](2.0f64)
    let a3 = math.log[f64](140.0f64) / math.log[f64](2.0f64)
    let a4 = math.log[f64](200.0f64) / math.log[f64](2.0f64)
    let fn_ = f64(n)
    if n < 200usize { ret usize(math.pow[f64](2.0f64, a1 + (a2 - a1) * (fn_ - 50.0f64) / 150.0f64)) }
    if n < 800usize { ret usize(math.pow[f64](2.0f64, a2 + (a3 - a2) * (fn_ - 200.0f64) / 600.0f64)) }
    if n < 3200usize { ret usize(math.pow[f64](2.0f64, a3 + (a4 - a3) * (fn_ - 800.0f64) / 2400.0f64)) }
    ret usize(200.0f64 + math.pow[f64](f64(n - 3200usize), 0.2f64))
}

// the 0-based span l (3 <= l <= nk - 1) with knot[l] <= x < knot[l + 1], the last span for x at or beyond the right end
fn span0(knot: []const f64, nk: usize, x: f64) -> usize {
    var l = 3usize
    while l < nk - 1usize {
        if x >= knot[l + 1usize] { l += 1usize } else { ret l }
    }
    ret l
}

type Spl = struct {
    nk: usize, nef: usize, knot: []f64, xin: []f64, yin: []f64, win: []f64, xwy: []f64,
    hs0: []f64, hs1: []f64, hs2: []f64, hs3: []f64, sg0: []f64, sg1: []f64, sg2: []f64, sg3: []f64,
    abd: []f64, p1ip: []f64, coef: []f64, sz: []f64, lev: []f64, crit: f64, ratio: f64
}

fn dpbfa(abd: []f64, n: usize) -> usize {
    var j = 1usize
    while j <= n {
        var s = 0.0f64
        var ik = 4usize
        var jk = 1usize
        if j > 3usize { jk = j - 3usize }
        var mu = 1usize
        if j < 5usize { mu = 5usize - j }
        var k = mu
        while k <= 3usize {
            var dot = 0.0f64
            var q = 0usize
            while q < k - mu {
                dot += abd[ab(ik + q, jk)] * abd[ab(mu + q, j)]
                q += 1usize
            }
            var t = abd[ab(k, j)] - dot
            t = t / abd[ab(4usize, jk)]
            abd[ab(k, j)] = t
            s += t * t
            ik -= 1usize
            jk += 1usize
            k += 1usize
        }
        s = abd[ab(4usize, j)] - s
        if s <= 0.0f64 { ret j }
        abd[ab(4usize, j)] = math.sqrt[f64](s)
        j += 1usize
    }
    ret 0usize
}

fn dpbsl(abd: []const f64, n: usize, b: []f64) {
    var k = 1usize
    while k <= n {
        var lm = k - 1usize
        if lm > 3usize { lm = 3usize }
        let la = 4usize - lm
        let lb = k - lm
        var t = 0.0f64
        var q = 0usize
        while q < lm {
            t += abd[ab(la + q, k)] * b[lb + q - 1usize]
            q += 1usize
        }
        b[k - 1usize] = (b[k - 1usize] - t) / abd[ab(4usize, k)]
        k += 1usize
    }
    var kb = 1usize
    while kb <= n {
        let k2 = n + 1usize - kb
        var lm = k2 - 1usize
        if lm > 3usize { lm = 3usize }
        let la = 4usize - lm
        let lb = k2 - lm
        b[k2 - 1usize] = b[k2 - 1usize] / abd[ab(4usize, k2)]
        let t = 0.0f64 - b[k2 - 1usize]
        var q = 0usize
        while q < lm {
            b[lb + q - 1usize] += t * abd[ab(la + q, k2)]
            q += 1usize
        }
        kb += 1usize
    }
}

fn sinerp(abd: []const f64, nk: usize, p1ip: []f64) {
    var wjm3: [3]f64 = zero
    var wjm2: [2]f64 = zero
    var wjm1: [1]f64 = zero
    var c1 = 0.0f64
    var c2 = 0.0f64
    var c3 = 0.0f64
    var i = 1usize
    while i <= nk {
        let j = nk - i + 1usize
        let c0 = 1.0f64 / abd[ab(4usize, j)]
        if j + 3usize <= nk {
            c1 = abd[ab(1usize, j + 3usize)] * c0
            c2 = abd[ab(2usize, j + 2usize)] * c0
            c3 = abd[ab(3usize, j + 1usize)] * c0
        } else {
            if j + 2usize == nk {
                c1 = 0.0f64
                c2 = abd[ab(2usize, j + 2usize)] * c0
                c3 = abd[ab(3usize, j + 1usize)] * c0
            } else {
                if j + 1usize == nk {
                    c1 = 0.0f64
                    c2 = 0.0f64
                    c3 = abd[ab(3usize, j + 1usize)] * c0
                } else {
                    c1 = 0.0f64
                    c2 = 0.0f64
                    c3 = 0.0f64
                }
            }
        }
        p1ip[ab(1usize, j)] = 0.0f64 - (c1 * wjm3[0usize] + c2 * wjm3[1usize] + c3 * wjm3[2usize])
        p1ip[ab(2usize, j)] = 0.0f64 - (c1 * wjm3[1usize] + c2 * wjm2[0usize] + c3 * wjm2[1usize])
        p1ip[ab(3usize, j)] = 0.0f64 - (c1 * wjm3[2usize] + c2 * wjm2[1usize] + c3 * wjm1[0usize])
        p1ip[ab(4usize, j)] = c0 * c0 + c1 * c1 * wjm3[0usize] + 2.0f64 * c1 * c2 * wjm3[1usize] + 2.0f64 * c1 * c3 * wjm3[2usize] + c2 * c2 * wjm2[0usize] + 2.0f64 * c2 * c3 * wjm2[1usize] + c3 * c3 * wjm1[0usize]
        wjm3[0usize] = wjm2[0usize]
        wjm3[1usize] = wjm2[1usize]
        wjm3[2usize] = p1ip[ab(2usize, j)]
        wjm2[0usize] = wjm1[0usize]
        wjm2[1usize] = p1ip[ab(3usize, j)]
        wjm1[0usize] = p1ip[ab(4usize, j)]
        i += 1usize
    }
}

// the package sslvrg for icrit 3: the fit at lambda, its leverages and the df-matching criterion 3 + (dofoff - tr)^2; returns the dpbfa info
fn sslvrg(a: *mem.Arena, s: *Spl, lambda: f64, dofoff: f64) -> usize {
    let nk = s.nk
    var i = 1usize
    while i <= nk {
        s.coef[i - 1usize] = s.xwy[i - 1usize]
        s.abd[ab(4usize, i)] = s.hs0[i - 1usize] + lambda * s.sg0[i - 1usize]
        i += 1usize
    }
    i = 1usize
    while i + 1usize <= nk {
        s.abd[ab(3usize, i + 1usize)] = s.hs1[i - 1usize] + lambda * s.sg1[i - 1usize]
        i += 1usize
    }
    i = 1usize
    while i + 2usize <= nk {
        s.abd[ab(2usize, i + 2usize)] = s.hs2[i - 1usize] + lambda * s.sg2[i - 1usize]
        i += 1usize
    }
    i = 1usize
    while i + 3usize <= nk {
        s.abd[ab(1usize, i + 3usize)] = s.hs3[i - 1usize] + lambda * s.sg3[i - 1usize]
        i += 1usize
    }
    let info = dpbfa(s.abd, nk)
    if info != 0usize { ret info }
    dpbsl(s.abd, nk, s.coef)
    var nv: [4]f64 = zero
    i = 0usize
    while i < s.nef {
        let xv = s.xin[i]
        let l = span0(s.knot, nk, xv)
        sm.basis_funs(s.knot, l, xv, 3usize, nv[0usize..4usize])
        var v = 0.0f64
        var p = 0usize
        while p < 4usize {
            v += s.coef[l - 3usize + p] * nv[p]
            p += 1usize
        }
        s.sz[i] = v
        i += 1usize
    }
    sinerp(s.abd, nk, s.p1ip)
    var tr = 0.0f64
    i = 0usize
    while i < s.nef {
        var xv = s.xin[i]
        var l = span0(s.knot, nk, xv)
        if xv >= s.knot[nk] {
            l = nk - 1usize
            xv = s.knot[nk] - 1.0e-11f64
        }
        sm.basis_funs(s.knot, l, xv, 3usize, nv[0usize..4usize])
        let j = l - 2usize
        let b0 = nv[0usize]
        let b1 = nv[1usize]
        let b2 = nv[2usize]
        let b3 = nv[3usize]
        let pp = s.p1ip
        let q = (pp[ab(4usize, j)] * (b0 * b0) + 2.0f64 * pp[ab(3usize, j)] * b0 * b1 + 2.0f64 * pp[ab(2usize, j)] * b0 * b2 + 2.0f64 * pp[ab(1usize, j)] * b0 * b3 + pp[ab(4usize, j + 1usize)] * (b1 * b1) + 2.0f64 * pp[ab(3usize, j + 1usize)] * b1 * b2 + 2.0f64 * pp[ab(2usize, j + 1usize)] * b1 * b3 + pp[ab(4usize, j + 2usize)] * (b2 * b2) + 2.0f64 * pp[ab(3usize, j + 2usize)] * b2 * b3 + pp[ab(4usize, j + 3usize)] * (b3 * b3))
        s.lev[i] = q * (s.win[i] * s.win[i])
        tr += s.lev[i]
        i += 1usize
    }
    s.crit = 3.0f64 + (dofoff - tr) * (dofoff - tr)
    let _ = a
    ret 0usize
}

fn wmean(n: usize, y: []const f64, w: []const f64) -> f64 {
    var wtot = 0.0f64
    var wsum = 0.0f64
    var i = 0usize
    while i < n {
        wsum += y[i] * w[i]
        wtot += w[i]
        i += 1usize
    }
    if wtot > 0.0f64 { ret wsum / wtot }
    ret 0.0f64
}

fn cpen(yw1: []const f64, yw2: []const f64, ii: usize, jj: usize, wpt: f64) -> f64 {
    ret wpt * (yw1[ii] * yw1[jj] + (yw2[ii] * yw1[jj] + yw2[jj] * yw1[ii]) * 0.5f64 + yw2[ii] * yw2[jj] * 0.33300000429153442f64)
}

// the package smoothing spline of one term. x, y, w are the n observations, mt the 0-based unique-x group of each (nef groups, sorted),
// spar (in and out), dof (target df, <= 0 for a fixed spar; out: the df of the smooth less one), smo the smooth at the observations, s0 the weighted mean of y, lev the nef leverages
fn splsm(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, mt: []const usize, nef: usize, spar: *f64, dof: *f64, smo: []f64, s0: *f64, lev: []f64, ev: []const f64, evo: []f64) -> err {
    let mk = mem.mark(a)
    let xin = zal(a, nef + 1usize)
    let yin = zal(a, nef + 1usize)
    let win = zal(a, nef + 1usize)
    let work = zal(a, n + 1usize)
    var i = 0usize
    while i < n {
        win[mt[i]] += w[i]
        xin[mt[i]] = x[i]
        work[i] = y[i] * w[i]
        i += 1usize
    }
    let tmp = zal(a, nef + 1usize)
    i = 0usize
    while i < n {
        tmp[mt[i]] += work[i]
        i += 1usize
    }
    i = 0usize
    while i < nef {
        if win[i] > 0.0f64 { yin[i] = tmp[i] / win[i] } else { yin[i] = 0.0f64 }
        i += 1usize
    }
    let xmin = xin[0usize]
    let xrange = xin[nef - 1usize] - xin[0usize]
    i = 0usize
    while i < nef {
        xin[i] = (xin[i] - xmin) / xrange
        i += 1usize
    }
    let ndk = sknotl_ndk(nef)
    let nk = ndk + 2usize
    let knot = zal(a, nk + 4usize)
    var j = 0usize
    while j < 3usize {
        knot[j] = xin[0usize]
        knot[ndk + 3usize + j] = xin[nef - 1usize]
        j += 1usize
    }
    j = 1usize
    while j <= ndk {
        var ix = 0usize
        if ndk > 1usize { ix = (j - 1usize) * (nef - 1usize) / (ndk - 1usize) }
        knot[j + 2usize] = xin[ix]
        j += 1usize
    }
    var sp = Spl {
        nk: nk, nef: nef, knot: knot, xin: xin, yin: yin, win: win, xwy: zal(a, nk), hs0: zal(a, nk), hs1: zal(a, nk), hs2: zal(a, nk), hs3: zal(a, nk),
        sg0: zal(a, nk), sg1: zal(a, nk), sg2: zal(a, nk), sg3: zal(a, nk), abd: zal(a, 4usize * nk), p1ip: zal(a, 4usize * nk),
        coef: zal(a, nk), sz: zal(a, nef + 1usize), lev: zal(a, nef + 1usize), crit: 0.0f64, ratio: 1.0f64
    }
    var ispar = false
    var dofoff = 0.0f64
    if *dof <= 0.0f64 {
        ispar = true
    } else {
        if *dof < 1.0f64 { *dof = 1.0f64 }
        dofoff = *dof + 1.0f64
    }
    let sumwin = nsum(nef, win)
    *s0 = wmean(n, y, w)
    // sbart: the weights enter squared, so take their roots
    i = 0usize
    while i < nef {
        if win[i] > 0.0f64 { win[i] = math.sqrt[f64](win[i]) }
        i += 1usize
    }
    // sgram
    var yw1: [4]f64 = zero
    var yw2: [4]f64 = zero
    var l = 3usize
    while l < nk {
        let wpt = knot[l + 1usize] - knot[l]
        if wpt > 0.0f64 {
            var fe = sm.basis_deriv(a, knot, nk, l, knot[l], 2usize, yw1[0usize..4usize])
            if fe != ok { ret fe }
            fe = sm.basis_deriv(a, knot, nk, l, knot[l + 1usize], 2usize, yw2[0usize..4usize])
            if fe != ok { ret fe }
            var p = 0usize
            while p < 4usize {
                yw2[p] = yw2[p] - yw1[p]
                p += 1usize
            }
            p = 0usize
            while p < 4usize {
                let g = l - 3usize + p
                sp.sg0[g] += cpen(yw1[0usize..4usize], yw2[0usize..4usize], p, p, wpt)
                if p + 1usize < 4usize { sp.sg1[g] += cpen(yw1[0usize..4usize], yw2[0usize..4usize], p, p + 1usize, wpt) }
                if p + 2usize < 4usize { sp.sg2[g] += cpen(yw1[0usize..4usize], yw2[0usize..4usize], p, p + 2usize, wpt) }
                if p + 3usize < 4usize { sp.sg3[g] += cpen(yw1[0usize..4usize], yw2[0usize..4usize], p, p + 3usize, wpt) }
                p += 1usize
            }
        }
        l += 1usize
    }
    // stxwx
    var nv: [4]f64 = zero
    i = 0usize
    while i < nef {
        let xv = xin[i]
        let ls = span0(knot, nk, xv)
        sm.basis_funs(knot, ls, xv, 3usize, nv[0usize..4usize])
        let jj = ls - 3usize
        let w2 = win[i] * win[i]
        let zz = yin[i]
        sp.xwy[jj] += w2 * zz * nv[0usize]
        sp.hs0[jj] += w2 * (nv[0usize] * nv[0usize])
        sp.hs1[jj] += w2 * nv[0usize] * nv[1usize]
        sp.hs2[jj] += w2 * nv[0usize] * nv[2usize]
        sp.hs3[jj] += w2 * nv[0usize] * nv[3usize]
        sp.xwy[jj + 1usize] += w2 * zz * nv[1usize]
        sp.hs0[jj + 1usize] += w2 * (nv[1usize] * nv[1usize])
        sp.hs1[jj + 1usize] += w2 * nv[1usize] * nv[2usize]
        sp.hs2[jj + 1usize] += w2 * nv[1usize] * nv[3usize]
        sp.xwy[jj + 2usize] += w2 * zz * nv[2usize]
        sp.hs0[jj + 2usize] += w2 * (nv[2usize] * nv[2usize])
        sp.hs1[jj + 2usize] += w2 * nv[2usize] * nv[3usize]
        sp.xwy[jj + 3usize] += w2 * zz * nv[3usize]
        sp.hs0[jj + 3usize] += w2 * (nv[3usize] * nv[3usize])
        i += 1usize
    }
    var t1 = 0.0f64
    var t2 = 0.0f64
    i = 2usize
    while i < nk - 3usize {
        t1 += sp.hs0[i]
        t2 += sp.sg0[i]
        i += 1usize
    }
    let ratio = t1 / t2
    sp.ratio = ratio
    var ier = 0usize
    if ispar {
        ier = sslvrg(a, &sp, ratio * math.pow[f64](16.0f64, *spar * 6.0f64 - 2.0f64), dofoff)
    } else {
        // Brent (Forsythe, Malcolm and Moler fmin) as in sbart.c
        let cgold = 0.381966011250105151795413165634f64
        let tol = 1.0e-4f64
        let eps = 2.0e-8f64
        let big = 1.0e100f64
        var aa = 0.0f64 - 1.5f64
        var bb = 2.0f64
        var vv = aa + cgold * (bb - aa)
        var ww = vv
        var xx = vv
        var ee = 0.0f64
        var dd = 0.0f64
        var fu = 0.0f64
        var uu = 0.0f64
        *spar = xx
        ier = sslvrg(a, &sp, ratio * math.pow[f64](16.0f64, *spar * 6.0f64 - 2.0f64), dofoff)
        var fx = sp.crit
        var fv = fx
        var fw = fx
        var iter = 0usize
        while ier == 0usize {
            let xm = (aa + bb) * 0.5f64
            let tol1 = eps * math.abs[f64](xx) + tol / 3.0f64
            let tol2 = tol1 * 2.0f64
            iter += 1usize
            if math.abs[f64](xx - xm) <= tol2 - (bb - aa) * 0.5f64 || iter > 200usize { break }
            var golden = true
            if !(math.abs[f64](ee) <= tol1 || fx >= big || fv >= big || fw >= big) {
                var r = (xx - ww) * (fx - fv)
                var q = (xx - vv) * (fx - fw)
                var p = (xx - vv) * q - (xx - ww) * r
                q = (q - r) * 2.0f64
                if q > 0.0f64 { p = 0.0f64 - p }
                q = math.abs[f64](q)
                r = ee
                ee = dd
                if !(math.abs[f64](p) >= math.abs[f64](0.5f64 * q * r) || q == 0.0f64) {
                    if !(p <= q * (aa - xx) || p >= q * (bb - xx)) {
                        golden = false
                        dd = p / q
                        uu = xx + dd
                        if uu - aa < tol2 || bb - uu < tol2 { dd = math.copysign[f64](tol1, xm - xx) }
                    }
                }
            }
            if golden {
                if xx >= xm { ee = aa - xx } else { ee = bb - xx }
                dd = cgold * ee
            }
            if math.abs[f64](dd) >= tol1 { uu = xx + dd } else { uu = xx + math.copysign[f64](tol1, dd) }
            *spar = uu
            ier = sslvrg(a, &sp, ratio * math.pow[f64](16.0f64, *spar * 6.0f64 - 2.0f64), dofoff)
            fu = sp.crit
            if !(fu == fu) || fu > 1.0e300f64 { fu = 2.0f64 * big }
            if fu <= fx {
                if uu >= xx { aa = xx } else { bb = xx }
                vv = ww
                fv = fw
                ww = xx
                fw = fx
                xx = uu
                fx = fu
            } else {
                if uu < xx { aa = uu } else { bb = uu }
                if fu <= fw || ww == xx {
                    vv = ww
                    fv = fw
                    ww = uu
                    fw = fu
                } else {
                    if fu <= fv || vv == xx || vv == ww { vv = uu
                        fv = fu }
                }
            }
        }
        *spar = xx
    }
    // back to the weights
    i = 0usize
    while i < nef {
        win[i] = win[i] * win[i]
        i += 1usize
    }
    let sbar = wmean(nef, sp.sz, win)
    let xbar = wmean(nef, xin, win)
    let lv = zal(a, nef + 1usize)
    i = 0usize
    while i < nef {
        lv[i] = (xin[i] - xbar) * sp.sz[i]
        i += 1usize
    }
    let xsbar = wmean(nef, lv, win)
    i = 0usize
    while i < nef {
        lv[i] = (xin[i] - xbar) * (xin[i] - xbar)
        i += 1usize
    }
    let dsum = wmean(nef, lv, win)
    i = 0usize
    while i < nef {
        if win[i] > 0.0f64 {
            lv[i] = sp.lev[i] / win[i] - 1.0f64 / sumwin - lv[i] / (sumwin * dsum)
        } else {
            lv[i] = 0.0f64
        }
        i += 1usize
    }
    var d = 0.0f64
    i = 0usize
    while i < nef {
        d += lv[i] * win[i]
        i += 1usize
    }
    *dof = d + 1.0f64
    i = 0usize
    while i < nef {
        sp.sz[i] = sp.sz[i] - sbar - (xin[i] - xbar) * xsbar / dsum
        lev[i] = lv[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        smo[i] = sp.sz[mt[i]]
        i += 1usize
    }
    // gam.sp: the raw spline of the last evaluation at ev, linear beyond the scaled range [0, 1] from the end value and slope
    var ei = 0usize
    while ei < ev.len {
        let xs = (ev[ei] - xmin) / xrange
        var xe = xs
        if xs < 0.0f64 { xe = 0.0f64 }
        if xs > 1.0f64 { xe = 1.0f64 }
        let ls = span0(sp.knot, nk, xe)
        sm.basis_funs(sp.knot, ls, xe, 3usize, nv[0usize..4usize])
        var vq = 0.0f64
        var pq = 0usize
        while pq < 4usize {
            vq += sp.coef[ls - 3usize + pq] * nv[pq]
            pq += 1usize
        }
        if xs < 0.0f64 || xs > 1.0f64 {
            var dv: [4]f64 = zero
            let de = sm.basis_deriv(a, sp.knot, nk, ls, xe, 1usize, dv[0usize..4usize])
            if de != ok { ret de }
            var dq = 0.0f64
            pq = 0usize
            while pq < 4usize {
                dq += sp.coef[ls - 3usize + pq] * dv[pq]
                pq += 1usize
            }
            vq += (xs - xe) * dq
        }
        evo[ei] = vq
        ei += 1usize
    }
    mem.reset(a, mk)
    ret ok
}

fn nsum(n: usize, v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i]
        i += 1usize
    }
    ret s
}

fn dwrss(n: usize, y: []const f64, eta: []const f64, w: []const f64) -> f64 {
    var wsum = 0.0f64
    var wtot = 0.0f64
    var i = 0usize
    while i < n {
        let wk = y[i] - eta[i]
        wsum += w[i] * wk * wk
        wtot += w[i]
        i += 1usize
    }
    if wtot > 0.0f64 { ret wsum / wtot }
    ret 0.0f64
}

// the unique sorted signif(x, 6) values of a column: mt gets the 0-based group of each observation, returns the count
fn gam_match(a: *mem.Arena, x: []const f64, n: usize, mt: []usize) -> usize {
    let mk = mem.mark(a)
    let sx = zal(a, n)
    var i = 0usize
    while i < n {
        sx[i] = signif6(x[i])
        i += 1usize
    }
    // insertion sort
    i = 1usize
    while i < n {
        let v = sx[i]
        var j = i
        while j > 0usize && sx[j - 1usize] > v {
            sx[j] = sx[j - 1usize]
            j -= 1usize
        }
        sx[j] = v
        i += 1usize
    }
    var nu = 0usize
    i = 0usize
    while i < n {
        if i == 0usize || sx[i] != sx[nu - 1usize] {
            sx[nu] = sx[i]
            nu += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        let v = signif6(x[i])
        var g = 0usize
        while sx[g] != v { g += 1usize }
        mt[i] = g
        i += 1usize
    }
    mem.reset(a, mk)
    ret nu
}

// family 0 Gaussian/identity, 1 binomial/logit, 2 Poisson/log
fn linkfun(fam: usize, mu: f64) -> f64 {
    if fam == 1usize { ret math.log[f64](mu / (1.0f64 - mu)) }
    if fam == 2usize { ret math.log[f64](mu) }
    ret mu
}

fn linkinv(fam: usize, eta: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    if fam == 1usize {
        var t = math.exp[f64](eta)
        if eta < 0.0f64 - 30.0f64 { t = eps }
        if eta > 30.0f64 { t = 1.0f64 / eps }
        ret t / (1.0f64 + t)
    }
    if fam == 2usize {
        let e = math.exp[f64](eta)
        if e > eps { ret e }
        ret eps
    }
    ret eta
}

fn mu_eta(fam: usize, eta: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    if fam == 1usize {
        let op = 1.0f64 + math.exp[f64](eta)
        if eta > 30.0f64 || eta < 0.0f64 - 30.0f64 { ret eps }
        ret math.exp[f64](eta) / (op * op)
    }
    if fam == 2usize {
        let e = math.exp[f64](eta)
        if e > eps { ret e }
        ret eps
    }
    ret 1.0f64
}

fn variance(fam: usize, mu: f64) -> f64 {
    if fam == 1usize { ret mu * (1.0f64 - mu) }
    if fam == 2usize { ret mu }
    ret 1.0f64
}

fn ylogy(y: f64, mu: f64) -> f64 {
    if y != 0.0f64 { ret y * math.log[f64](y / mu) }
    ret 0.0f64
}

fn dev_resid(fam: usize, y: f64, mu: f64, wt: f64) -> f64 {
    if fam == 1usize { ret 2.0f64 * wt * (ylogy(y, mu) + ylogy(1.0f64 - y, 1.0f64 - mu)) }
    if fam == 2usize {
        if y > 0.0f64 { ret 2.0f64 * (wt * (y * math.log[f64](y / mu) - (y - mu))) }
        ret 2.0f64 * (mu * wt)
    }
    ret wt * ((y - mu) * (y - mu))
}

fn deviance(fam: usize, n: usize, y: []const f64, mu: []const f64, w: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += dev_resid(fam, y[i], mu[i], w[i])
        i += 1usize
    }
    ret s
}

fn aic_of(fam: usize, n: usize, y: []const f64, mu: []const f64, w: []const f64, dev: f64) -> f64 {
    let nobs = f64(n)
    var s = 0.0f64
    var i = 0usize
    if fam == 1usize {
        // the package passes nobs, not the binomial counts: m is the scalar nobs, and ifelse(m > 0, wt/m, 0) is then the scalar w[1]/nobs
        while i < n {
            if nobs > 0.0f64 {
                s += w[0usize] / nobs * nb.dbinom(nearbyint(nobs * y[i]), nearbyint(nobs), mu[i], true)
            }
            i += 1usize
        }
        ret 0.0f64 - 2.0f64 * s
    }
    if fam == 2usize {
        while i < n {
            s += nm.dpois(y[i], mu[i], true) * w[i]
            i += 1usize
        }
        ret 0.0f64 - 2.0f64 * s
    }
    while i < n {
        s += math.log[f64](w[i])
        i += 1usize
    }
    ret nobs * (math.log[f64](2.0f64 * 3.141592653589793f64 * dev / nobs) + 1.0f64) + 2.0f64 - s
}

type Bf = struct { qr: dc.Qr, qrank: usize, nit: usize, effect: []f64, res: []f64 }

// lo() of one variable (the package loess lo1/lo2): the smoother over the unique x (nef of them, weights win) as a matrix sop, the weighted parametric basis qb (r columns), the nonlinear df and leverages
type LoCache = struct { nv: usize, vv: []f64, op0: []f64, op1: []f64, xu: []f64, nef: usize, r: usize, dof: f64, win: []f64, sqw: []f64, sqwi: []f64, sop: []f64, qb: []f64, lev: []f64 }

fn zal_lc(a: *mem.Arena, n: usize) -> []LoCache {
    let (v, e) = mem.alloc[LoCache](a, n + 1usize)
    if e != ok {
        var em: []LoCache = zero
        ret em
    }
    var i = 0usize
    while i < n + 1usize {
        var z: LoCache = zero
        v[i] = z
        i += 1usize
    }
    ret v[0usize..n]
}

// lo2 with nit <= 1: x is the model matrix (n by p, column-major), cj the first column of the term and pj its columns (the first is the smoothed variable, the rest the polynomial); degree = pj
fn lo_build(a: *mem.Arena, x: []const f64, n: usize, cj: usize, pj: usize, w: []const f64, mt: []const usize, nef: usize, span: f64, c: *LoCache) -> err {
    var bad = 0usize
    let win = zal(a, nef)
    let sqw = zal(a, nef)
    let sqwi = zal(a, nef)
    let xt = zal(a, nef * pj)
    var i = 0usize
    while i < n {
        let k = mt[i]
        win[k] += w[i]
        var j = 0usize
        while j < pj {
            xt[j * nef + k] = x[(cj + j) * n + i]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nef {
        if win[i] > 0.0f64 {
            sqw[i] = math.sqrt[f64](win[i])
            sqwi[i] = 1.0f64 / sqw[i]
        } else {
            sqw[i] = 1.0e-5f64
            sqwi[i] = 1.0e5f64
        }
        i += 1usize
    }
    let xin = xt[0usize..nef]
    var nf = usize(math.floor[f64](f64(nef) * span))
    if nf > nef { nf = nef }
    if nf == 0usize { ret gb.NoMemory }
    let fc = usize(math.floor[f64](f64(nef) * (span / 5.0f64)))
    let cuts = gb.af(a, nef + 2usize, &bad)
    let stl = gb.au(a, 2usize * nef + 8usize, &bad)
    let stu = gb.au(a, 2usize * nef + 8usize, &bad)
    let stlo = gb.af(a, 2usize * nef + 8usize, &bad)
    let sthi = gb.af(a, 2usize * nef + 8usize, &bad)
    let vv = gb.af(a, nef + 4usize, &bad)
    let idx = gb.au(a, nef + 2usize, &bad)
    let tmp = gb.au(a, nef + 2usize, &bad)
    if bad != 0usize { ret gb.NoMemory }
    var alpha = xin[0usize]
    var beta = xin[nef - 1usize]
    var mx = math.abs[f64](alpha)
    if math.abs[f64](beta) > mx { mx = math.abs[f64](beta) }
    var spread = beta - alpha
    let floor_w = 1.0e-10f64 * mx + 1.0e-30f64
    if floor_w > spread { spread = floor_w }
    let mu = 0.005f64 * spread
    alpha = alpha - mu
    beta = beta + mu
    let nc = lf.kd_cuts(xin, nef, fc, alpha, beta, cuts, stl, stu, stlo, sthi)
    var cc = 0usize
    while cc < nc {
        idx[cc] = cc
        cc += 1usize
    }
    gb.msort(cuts, idx, tmp, nc)
    vv[0usize] = alpha
    cc = 0usize
    while cc < nc {
        vv[cc + 1usize] = cuts[idx[cc]]
        cc += 1usize
    }
    vv[nc + 1usize] = beta
    let nv = nc + 2usize
    let op0 = zal(a, nv * nef)
    let op1 = zal(a, nv * nef)
    let u = zal(a, nef)
    let o2 = zal(a, 2usize)
    var v = 0usize
    while v < nv {
        var j = 0usize
        while j < nef {
            let mk = mem.mark(a)
            u[j] = 1.0f64
            let e = lf.local_fit(a, xin, u, win, nef, nf, span, pj, vv[v], o2)
            u[j] = 0.0f64
            mem.reset(a, mk)
            if e != ok { ret e }
            op0[v * nef + j] = o2[0usize]
            op1[v * nef + j] = o2[1usize]
            j += 1usize
        }
        v += 1usize
    }
    let sop = zal(a, nef * nef)
    i = 0usize
    while i < nef {
        var cell = 0usize
        while cell + 1usize < nv - 1usize && xin[i] > vv[cell + 1usize] { cell += 1usize }
        let wd = vv[cell + 1usize] - vv[cell]
        let h = (xin[i] - vv[cell]) / wd
        let phi0 = (1.0f64 - h) * (1.0f64 - h) * (1.0f64 + 2.0f64 * h)
        let phi1 = h * h * (3.0f64 - 2.0f64 * h)
        let psi0 = h * (1.0f64 - h) * (1.0f64 - h)
        let psi1 = h * h * (h - 1.0f64)
        var j = 0usize
        while j < nef {
            sop[i * nef + j] = phi0 * op0[cell * nef + j] + phi1 * op0[(cell + 1usize) * nef + j] + (psi0 * op1[cell * nef + j] + psi1 * op1[(cell + 1usize) * nef + j]) * wd
            j += 1usize
        }
        i += 1usize
    }
    // orthonormal basis of the weighted parametric columns (1, x, ...), dropping a column once it is within 1e-7 of the span of the earlier ones
    let qb = zal(a, nef * (pj + 1usize))
    var r = 0usize
    var col = 0usize
    while col <= pj {
        let vcol = qb[r * nef..r * nef + nef]
        i = 0usize
        while i < nef {
            if col == 0usize { vcol[i] = sqw[i] } else { vcol[i] = xt[(col - 1usize) * nef + i] * sqw[i] }
            i += 1usize
        }
        var n0 = 0.0f64
        i = 0usize
        while i < nef {
            n0 += vcol[i] * vcol[i]
            i += 1usize
        }
        n0 = math.sqrt[f64](n0)
        var pass = 0usize
        while pass < 2usize {
            var l = 0usize
            while l < r {
                var d = 0.0f64
                i = 0usize
                while i < nef {
                    d += qb[l * nef + i] * vcol[i]
                    i += 1usize
                }
                i = 0usize
                while i < nef {
                    vcol[i] -= d * qb[l * nef + i]
                    i += 1usize
                }
                l += 1usize
            }
            pass += 1usize
        }
        var n1 = 0.0f64
        i = 0usize
        while i < nef {
            n1 += vcol[i] * vcol[i]
            i += 1usize
        }
        n1 = math.sqrt[f64](n1)
        if n1 > 1.0e-7f64 * n0 {
            i = 0usize
            while i < nef {
                vcol[i] = vcol[i] / n1
                i += 1usize
            }
            r += 1usize
        }
        col += 1usize
    }
    let lev = zal(a, nef)
    var dof = 0.0f64
    i = 0usize
    while i < nef {
        var t = sop[i * nef + i]
        var l = 0usize
        while l < r {
            t -= qb[l * nef + i] * qb[l * nef + i]
            l += 1usize
        }
        if win[i] > 0.0f64 {
            lev[i] = t / win[i]
            dof += lev[i] * win[i]
        }
        i += 1usize
    }
    c.nef = nef
    c.nv = nv
    c.vv = vv
    c.op0 = op0
    c.op1 = op1
    c.xu = xin
    c.r = r
    c.dof = dof
    c.win = win
    c.sqw = sqw
    c.sqwi = sqwi
    c.sop = sop
    c.qb = qb
    c.lev = lev
    ret ok
}

// the nonlinear part of the loess smooth of z (weights w), per observation
fn lo_apply(a: *mem.Arena, c: *const LoCache, z: []const f64, w: []const f64, n: usize, mt: []const usize, smo: []f64) {
    let nef = c.nef
    let yin = zal(a, nef)
    var i = 0usize
    while i < n {
        yin[mt[i]] += z[i] * w[i]
        i += 1usize
    }
    i = 0usize
    while i < nef {
        yin[i] = yin[i] * c.sqwi[i] * c.sqwi[i]
        i += 1usize
    }
    let so = zal(a, nef)
    i = 0usize
    while i < nef {
        var t = 0.0f64
        var j = 0usize
        while j < nef {
            t += c.sop[i * nef + j] * yin[j]
            j += 1usize
        }
        so[i] = t * c.sqw[i]
        i += 1usize
    }
    let pr = zal(a, nef)
    var l = 0usize
    while l < c.r {
        var d = 0.0f64
        i = 0usize
        while i < nef {
            d += c.qb[l * nef + i] * so[i]
            i += 1usize
        }
        let dd = d
        i = 0usize
        while i < nef {
            pr[i] += dd * c.qb[l * nef + i]
            i += 1usize
        }
        l += 1usize
    }
    i = 0usize
    while i < n {
        smo[i] = (so[mt[i]] - pr[mt[i]]) * c.sqwi[mt[i]]
        i += 1usize
    }
}

// bakfit/backf1: x is n by p (column-major), which the 0-based columns smoothed (q of them), mts the q match arrays (n each), nefs their counts
fn backfit(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, w: []const f64, q: usize, which: []const usize, spar: []f64, dof: []f64, mts: []const usize, nefs: []const usize, etal: []f64, s: []f64, eta: []f64, beta: []f64, vr: []f64, tol: f64, maxit: usize, bf: *Bf) -> err {
    let sqwt = zal(a, n)
    let sqwti = zal(a, n)
    var anyzwt = false
    var i = 0usize
    while i < n {
        if w[i] > 0.0f64 {
            sqwt[i] = math.sqrt[f64](w[i])
            sqwti[i] = 1.0f64 / sqwt[i]
        } else {
            anyzwt = true
        }
        i += 1usize
    }
    let xw = zal(a, n * p)
    var j = 0usize
    while j < p {
        i = 0usize
        while i < n {
            xw[j * n + i] = x[j * n + i] * sqwt[i]
            i += 1usize
        }
        j += 1usize
    }
    let (f, qe) = dc.qr(a, xw, n, p, 1.0e-7f64)
    if qe != ok { ret qe }
    let qrank = f.rank
    i = 0usize
    while i < n {
        var t = 0.0f64
        j = 0usize
        while j < q {
            t += s[j * n + i]
            j += 1usize
        }
        eta[i] = t
        i += 1usize
    }
    let z = zal(a, n)
    let old = zal(a, n)
    let col = zal(a, n)
    let smo = zal(a, n)
    let effect = zal(a, n)
    let bw = zal(a, n)
    let lev = zal(a, n)
    let bq = zal(a, p)
    // a negative dof marks a lo() term: span = -dof, degree = spar (its columns in the model matrix)
    let lcs = zal_lc(a, q + 1usize)
    let lspan = zal(a, q + 1usize)
    var ratio = 1.0f64
    var nit = 0usize
    var s0 = 0.0f64
    while ratio > tol && nit < maxit {
        var deltaf = 0.0f64
        nit += 1usize
        i = 0usize
        while i < n {
            z[i] = (y[i] - eta[i]) * sqwt[i]
            i += 1usize
        }
        // dqrsl job 1101: effects Q'z, coefficients, and X b
        i = 0usize
        while i < n {
            effect[i] = z[i]
            i += 1usize
        }
        dc.qr_qty(&f, effect)
        j = 0usize
        while j < p {
            bq[j] = 0.0f64
            j += 1usize
        }
        var jj = qrank
        while jj > 0usize {
            jj -= 1usize
            var sm_ = effect[jj]
            var c = jj + 1usize
            while c < qrank {
                sm_ = sm_ - f.qr[c * n + jj] * bq[c]
                c += 1usize
            }
            bq[jj] = sm_ / f.qr[jj * n + jj]
        }
        i = 0usize
        while i < n {
            if i < qrank { bw[i] = effect[i] } else { bw[i] = 0.0f64 }
            i += 1usize
        }
        dc.qr_qy(&f, bw)
        i = 0usize
        while i < n {
            etal[i] = bw[i] * sqwti[i]
            i += 1usize
        }
        var k = 0usize
        while k < q {
            let cj = which[k]
            i = 0usize
            while i < n {
                old[i] = s[k * n + i]
                z[i] = y[i] - etal[i] - eta[i] + old[i]
                col[i] = x[cj * n + i]
                i += 1usize
            }
            let nef = nefs[k]
            if nit == 1usize && dof[k] < 0.0f64 { lspan[k] = 0.0f64 - dof[k] }
            if lspan[k] > 0.0f64 {
                if nit == 1usize {
                    let le = lo_build(a, x, n, cj, usize(spar[k]), w, mts[k * n..k * n + n], nef, lspan[k], &lcs[k])
                    if le != ok { ret le }
                    dof[k] = lcs[k].dof
                }
                lo_apply(a, &lcs[k], z, w, n, mts[k * n..k * n + n], smo)
                i = 0usize
                while i < n {
                    s[k * n + i] = smo[i]
                    eta[i] = eta[i] + smo[i] - old[i]
                    i += 1usize
                }
                i = 0usize
                while i < nef {
                    vr[k * n + i] = lcs[k].lev[i]
                    i += 1usize
                }
                deltaf += dwrss(n, old, smo, w)
                k += 1usize
                continue
            }
            if nit > 1usize { dof[k] = 0.0f64 }
            let se = splsm(a, col, z, w, n, mts[k * n..k * n + n], nef, &spar[k], &dof[k], smo, &s0, lev, empty_f(), empty_f())
            if se != ok { ret se }
            i = 0usize
            while i < n {
                s[k * n + i] = smo[i]
                eta[i] = eta[i] + smo[i] - old[i]
                etal[i] = etal[i] + s0
                i += 1usize
            }
            i = 0usize
            while i < nef {
                vr[k * n + i] = lev[i]
                i += 1usize
            }
            deltaf += dwrss(n, old, smo, w)
            k += 1usize
        }
        var normf = 0.0f64
        i = 0usize
        while i < n {
            normf += w[i] * eta[i] * eta[i]
            i += 1usize
        }
        if normf > 0.0f64 { ratio = math.sqrt[f64](deltaf / normf) } else { ratio = 0.0f64 }
    }
    // un-pivot the coefficients
    j = 0usize
    while j < p {
        beta[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < p {
        beta[f.pivot[j]] = bq[j]
        j += 1usize
    }
    if anyzwt {
        i = 0usize
        while i < n {
            if w[i] <= 0.0f64 {
                var t = 0.0f64
                j = 0usize
                while j < p {
                    t += beta[j] * x[j * n + i]
                    j += 1usize
                }
                etal[i] = t
            }
            i += 1usize
        }
    }
    i = 0usize
    while i < n {
        eta[i] = eta[i] + etal[i]
        i += 1usize
    }
    // the per-term leverages spread to the observations
    var k = 0usize
    while k < q {
        let nef = nefs[k]
        i = 0usize
        while i < n {
            old[i] = vr[k * n + mts[k * n + i]]
            i += 1usize
        }
        i = 0usize
        while i < n {
            vr[k * n + i] = old[i]
            i += 1usize
        }
        let _ = nef
        k += 1usize
    }
    bf.qr = f
    bf.qrank = qrank
    bf.nit = nit
    bf.effect = effect
    ret ok
}

// general.wam (a model mixing s() and lo() terms): lm.wfit of the parametric part, then each smoother in the order of `which` (the package puts every s() before the lo() terms) on its partial residual.
// A dof >= 0 marks an s() term (matched again from spar each call, as gam.s does), < 0 a lo() term (span = -dof, degree = spar).
fn general_wam(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, w: []const f64, q: usize, which: []const usize, spar: []f64, dof: []f64, mts: []const usize, nefs: []const usize, s: []f64, eta: []f64, beta: []f64, vr: []f64, tol: f64, maxit: usize, bf: *Bf) -> err {
    let sqwt = zal(a, n)
    var i = 0usize
    while i < n {
        if w[i] > 0.0f64 { sqwt[i] = math.sqrt[f64](w[i]) }
        i += 1usize
    }
    let xw = zal(a, n * p)
    var j = 0usize
    while j < p {
        i = 0usize
        while i < n {
            xw[j * n + i] = x[j * n + i] * sqwt[i]
            i += 1usize
        }
        j += 1usize
    }
    let (f, qe) = dc.qr(a, xw, n, p, 1.0e-7f64)
    if qe != ok { ret qe }
    let qrank = f.rank
    let spar0 = zal(a, q + 1usize)
    let dof0 = zal(a, q + 1usize)
    var k = 0usize
    while k < q {
        spar0[k] = spar[k]
        dof0[k] = dof[k]
        k += 1usize
    }
    let r = zal(a, n)
    i = 0usize
    while i < n {
        var t = 0.0f64
        k = 0usize
        while k < q {
            t += s[k * n + i]
            k += 1usize
        }
        r[i] = y[i] - t
        i += 1usize
    }
    let fl = zal(a, n)
    let lres = zal(a, n)
    let zz = zal(a, n)
    let zj = zal(a, n)
    let old = zal(a, n)
    let col = zal(a, n)
    let smo = zal(a, n)
    let effect = zal(a, n)
    let bw = zal(a, n)
    let lev = zal(a, n)
    let bq = zal(a, p)
    let lcs = zal_lc(a, q + 1usize)
    var ratio = tol + 1.0f64
    var nit = 0usize
    var s0 = 0.0f64
    while ratio > tol && nit < maxit {
        nit += 1usize
        i = 0usize
        while i < n {
            zz[i] = r[i] + fl[i]
            effect[i] = zz[i] * sqwt[i]
            i += 1usize
        }
        dc.qr_qty(&f, effect)
        j = 0usize
        while j < p {
            bq[j] = 0.0f64
            j += 1usize
        }
        var jj = qrank
        while jj > 0usize {
            jj -= 1usize
            var sm_ = effect[jj]
            var c = jj + 1usize
            while c < qrank {
                sm_ = sm_ - f.qr[c * n + jj] * bq[c]
                c += 1usize
            }
            bq[jj] = sm_ / f.qr[jj * n + jj]
        }
        // the fitted values of the parametric part, from the coefficients
        j = 0usize
        while j < p {
            beta[j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < p {
            beta[f.pivot[j]] = bq[j]
            j += 1usize
        }
        i = 0usize
        while i < n {
            var t = 0.0f64
            j = 0usize
            while j < p {
                t += beta[j] * x[j * n + i]
                j += 1usize
            }
            fl[i] = t
            r[i] = zz[i] - t
            lres[i] = r[i]
            i += 1usize
        }
        var deltaf = 0.0f64
        k = 0usize
        while k < q {
            let cj = which[k]
            let nef = nefs[k]
            i = 0usize
            while i < n {
                old[i] = s[k * n + i]
                zj[i] = r[i] + old[i]
                i += 1usize
            }
            if dof0[k] < 0.0f64 {
                if nit == 1usize {
                    let le = lo_build(a, x, n, cj, usize(spar0[k]), w, mts[k * n..k * n + n], nef, 0.0f64 - dof0[k], &lcs[k])
                    if le != ok { ret le }
                    dof[k] = lcs[k].dof
                }
                lo_apply(a, &lcs[k], zj, w, n, mts[k * n..k * n + n], smo)
                i = 0usize
                while i < nef {
                    vr[k * n + i] = lcs[k].lev[i]
                    i += 1usize
                }
            } else {
                i = 0usize
                while i < n {
                    col[i] = signif6(x[cj * n + i])
                    i += 1usize
                }
                spar[k] = spar0[k]
                dof[k] = dof0[k]
                let se = splsm(a, col, zj, w, n, mts[k * n..k * n + n], nef, &spar[k], &dof[k], smo, &s0, lev, empty_f(), empty_f())
                if se != ok { ret se }
                i = 0usize
                while i < nef {
                    vr[k * n + i] = lev[i]
                    i += 1usize
                }
            }
            i = 0usize
            while i < n {
                r[i] = zj[i] - smo[i]
                s[k * n + i] = zj[i] - r[i]
                i += 1usize
            }
            deltaf += dwrss(n, old, s[k * n..k * n + n], w)
            k += 1usize
        }
        var normf = 0.0f64
        i = 0usize
        while i < n {
            var t = 0.0f64
            k = 0usize
            while k < q {
                t += s[k * n + i]
                k += 1usize
            }
            normf += w[i] * (t * t)
            i += 1usize
        }
        if normf > 0.0f64 { ratio = math.sqrt[f64](deltaf / normf) } else { ratio = 0.0f64 }
    }
    i = 0usize
    while i < n {
        eta[i] = y[i] - r[i]
        i += 1usize
    }
    // the per-term leverages spread to the observations
    k = 0usize
    while k < q {
        i = 0usize
        while i < n {
            old[i] = vr[k * n + mts[k * n + i]]
            i += 1usize
        }
        i = 0usize
        while i < n {
            vr[k * n + i] = old[i]
            i += 1usize
        }
        k += 1usize
    }
    bf.qr = f
    bf.qrank = qrank
    bf.nit = nit
    bf.effect = effect
    bf.res = lres
    ret ok
}

// gam.fit for y ~ x (columns of the model matrix, the first the intercept) with the columns `which` smoothed by s(., df) (df > 0) or s(., spar) (df = 0).
// y is the response (0/1 for binomial), w the prior weights. out arrays are allocated in a.
fn gam_fit(a: *mem.Arena, xin_: []const f64, n: usize, p: usize, y0: []const f64, w: []const f64, fam: usize, q: usize, which: []const usize, df: []const f64, spar0: []const f64, eps: f64, maxit: usize, bf_eps: f64, bf_maxit: usize, out: *GamFit) -> err {
    let off = zal(a, n)
    ret gam_fit_off(a, xin_, n, p, y0, w, off, fam, q, which, df, spar0, eps, maxit, bf_eps, bf_maxit, out)
}

// gam with offset(): the working response is z = eta - offset + (y - mu) / mu.eta, the backfit fits z, and eta is that fit plus the offset.
// As in the package, the starting eta ignores the offset and null.deviance is the weighted-mean one.
fn gam_fit_off(a: *mem.Arena, xin_: []const f64, n: usize, p: usize, y0: []const f64, w: []const f64, off: []const f64, fam: usize, q: usize, which: []const usize, df: []const f64, spar0: []const f64, eps: f64, maxit: usize, bf_eps: f64, bf_maxit: usize, out: *GamFit) -> err {
    let x = zal(a, n * p)
    var i = 0usize
    while i < n * p {
        x[i] = xin_[i]
        i += 1usize
    }
    let y = zal(a, n)
    i = 0usize
    while i < n {
        y[i] = y0[i]
        if fam == 1usize && w[i] == 0.0f64 { y[i] = 0.0f64 }
        i += 1usize
    }
    let mts = zal_u(a, n * q + 1usize)
    let nefs = zal_u(a, q + 1usize)
    var nlo = 0usize
    var ns_ = 0usize
    var k = 0usize
    while k < q {
        if df[k] < 0.0f64 { nlo += 1usize } else { ns_ += 1usize }
        k += 1usize
    }
    let gen = nlo > 0usize && ns_ > 0usize
    k = 0usize
    while k < q {
        let cj = which[k]
        i = 0usize
        while i < n {
            if df[k] >= 0.0f64 && !gen { x[cj * n + i] = signif6(x[cj * n + i]) }
            i += 1usize
        }
        nefs[k] = gam_match(a, x[cj * n..cj * n + n], n, mts[k * n..k * n + n])
        k += 1usize
    }
    let mu = zal(a, n)
    let eta = zal(a, n)
    let z = zal(a, n)
    let wz = zal(a, n)
    var i2 = 0usize
    while i2 < n {
        var ms = y[i2]
        if fam == 1usize { ms = (w[i2] * y[i2] + 0.5f64) / (w[i2] + 1.0f64) }
        if fam == 2usize { ms = y[i2] + 0.1f64 }
        eta[i2] = linkfun(fam, ms)
        mu[i2] = linkinv(fam, eta[i2])
        i2 += 1usize
    }
    let s = zal(a, n * q + 1usize)
    let vr = zal(a, n * q + 1usize)
    let spar = zal(a, q + 1usize)
    let dof = zal(a, q + 1usize)
    let beta = zal(a, p)
    let etal = zal(a, n)
    let bfeta = zal(a, n)
    let bfit = zal(a, n)
    var newdev = deviance(fam, n, y, mu, w)
    var olddev = 10.0f64 * newdev + 10.0f64
    var bfi = zal_u(a, maxit + 1usize)
    var bf: Bf = zero
    var iter = 0usize
    var good = zal(a, n)
    while iter < maxit {
        iter += 1usize
        i = 0usize
        while i < n {
            var g = 0.0f64
            let me = mu_eta(fam, eta[i])
            if w[i] > 0.0f64 && me != 0.0f64 { g = 1.0f64 }
            good[i] = g
            z[i] = eta[i] - off[i]
            wz[i] = 0.0f64
            if g > 0.0f64 {
                z[i] = z[i] + (y[i] - mu[i]) / me
                wz[i] = w[i] * (me * me) / variance(fam, mu[i])
            }
            i += 1usize
        }
        k = 0usize
        while k < q {
            spar[k] = spar0[k]
            dof[k] = df[k]
            k += 1usize
        }
        i = 0usize
        while i < n {
            etal[i] = 0.0f64
            i += 1usize
        }
        var be = ok
        if gen {
            be = general_wam(a, x, n, p, z, wz, q, which, spar, dof, mts, nefs, s, bfeta, beta, vr, bf_eps, bf_maxit, &bf)
        } else {
            be = backfit(a, x, n, p, z, wz, q, which, spar, dof, mts, nefs, etal, s, bfeta, beta, vr, bf_eps, bf_maxit, &bf)
        }
        if be != ok { ret be }
        bfi[iter - 1usize] = bf.nit
        i = 0usize
        while i < n {
            eta[i] = bfeta[i] + off[i]
            mu[i] = linkinv(fam, eta[i])
            i += 1usize
        }
        olddev = newdev
        newdev = deviance(fam, n, y, mu, w)
        if !(newdev == newdev) { break }
        if !(math.abs[f64](olddev - newdev) / (olddev + 0.1f64) > eps) { break }
    }
    let _ = bfit
    let nl_df = zal(a, q + 1usize)
    var sumnl = 0.0f64
    k = 0usize
    while k < q {
        nl_df[k] = dof[k] - 1.0f64
        if df[k] < 0.0f64 { nl_df[k] = dof[k] }
        sumnl += nl_df[k]
        k += 1usize
    }
    var nzero = 0.0f64
    var sw = 0.0f64
    var swy = 0.0f64
    i = 0usize
    while i < n {
        if w[i] == 0.0f64 { nzero += 1.0f64 }
        sw += w[i]
        swy += w[i] * y[i]
        i += 1usize
    }
    let dfres = f64(n) - f64(bf.qrank) - sumnl - nzero
    let wtdmu = swy / sw
    var nulldev = 0.0f64
    i = 0usize
    while i < n {
        nulldev += dev_resid(fam, y[i], wtdmu, w[i])
        i += 1usize
    }
    let nok = f64(n) - nzero
    let rankm = nok - dfres
    let aicm = aic_of(fam, n, y, mu, w, newdev) + 2.0f64 * rankm
    // nl.chisq: gam.nlchisq(qr, residuals, wz, smooth)
    let chi = zal(a, q + 1usize)
    let resid = zal(a, n)
    i = 0usize
    while i < n {
        resid[i] = z[i] - (eta[i] - off[i])
        if gen { resid[i] = bf.res[i] }
        i += 1usize
    }
    let col = zal(a, n)
    k = 0usize
    while k < q {
        i = 0usize
        while i < n {
            col[i] = s[k * n + i] * math.sqrt[f64](wz[i])
            i += 1usize
        }
        let sc = zal(a, n)
        i = 0usize
        while i < n {
            sc[i] = col[i]
            i += 1usize
        }
        dc.qr_qty(&bf.qr, sc)
        i = 0usize
        while i < bf.qrank {
            sc[i] = 0.0f64
            i += 1usize
        }
        dc.qr_qy(&bf.qr, sc)
        var tot = 0.0f64
        i = 0usize
        while i < n {
            tot += sc[i] * sc[i] + 2.0f64 * col[i] * (math.sqrt[f64](wz[i]) * resid[i])
            i += 1usize
        }
        chi[k] = tot
        k += 1usize
    }
    out.coef = beta
    out.eta = eta
    out.mu = mu
    out.smooth = s
    out.nldf = nl_df
    out.levs = vr
    out.spar = spar
    out.weights = wz
    out.resid = resid
    out.nl_chisq = chi
    out.bf_iter = bfi[0usize..iter]
    out.deviance = newdev
    out.null_dev = nulldev
    out.aic = aicm
    out.df_resid = dfres
    out.df_null = nok - 1.0f64
    out.iter = iter
    out.rank = bf.qrank
    out.q = q
    out.n = n
    out.p = p
    // anova.lm of the weighted QR (the parametric effects, one term per model-matrix column) and summary.Gam (the nonparametric effects)
    let pdf = zal(a, p + 1usize)
    let pss = zal(a, p + 1usize)
    let pfv = zal(a, p + 1usize)
    let ppv = zal(a, p + 1usize)
    // the columns of a lo() term of degree 2 are one anova term
    let grp = zal_u(a, p + 1usize)
    var gi = 0usize
    while gi < p {
        grp[gi] = gi
        gi += 1usize
    }
    k = 0usize
    while k < q {
        if df[k] < 0.0f64 {
            var gj = 1usize
            while gj < usize(spar0[k]) {
                grp[which[k] + gj] = which[k]
                gj += 1usize
            }
        }
        k += 1usize
    }
    var cc = 0usize
    while cc < bf.qrank {
        let cl = grp[bf.qr.pivot[cc]]
        pdf[cl] += 1.0f64
        pss[cl] += bf.effect[cc] * bf.effect[cc]
        cc += 1usize
    }
    var ssr = 0.0f64
    var ssq = 0.0f64
    i = 0usize
    while i < n {
        ssr += wz[i] * (resid[i] * resid[i])
        let rw = resid[i] * math.sqrt[f64](wz[i])
        ssq += rw * rw
        i += 1usize
    }
    cc = 1usize
    while cc < p {
        if pdf[cc] > 0.0f64 {
            pfv[cc] = pss[cc] / pdf[cc] / (ssr / dfres)
            ppv[cc] = nb.pf(pfv[cc], pdf[cc], dfres, false, false)
        }
        cc += 1usize
    }
    var phihat = 1.0e300f64
    if dfres > 0.0f64 { phihat = ssq / dfres }
    let chiorf = fam != 0usize
    var disp = phihat
    if chiorf { disp = 1.0f64 }
    let npdf = zal(a, q + 1usize)
    let npst = zal(a, q + 1usize)
    let npp = zal(a, q + 1usize)
    k = 0usize
    while k < q {
        let nlc = chi[k] / disp
        npdf[k] = math.floor[f64](nl_df[k] * 10.0f64 + 0.5f64) / 10.0f64
        if chiorf {
            npst[k] = nlc
            npp[k] = 1.0f64 - nm.pchisq(nlc, nl_df[k], true, false)
        } else {
            npst[k] = nlc / nl_df[k]
            npp[k] = 1.0f64 - nb.pf(npst[k], nl_df[k], dfres, true, false)
        }
        k += 1usize
    }
    // predict.Gam(se.fit = TRUE) without newdata: the lm standard error of X b from R, then plus disp times the smoother leverages (the response scale by |mu.eta|)
    let sel = zal(a, n)
    let ses = zal(a, n)
    let vv = zal(a, p + 1usize)
    i = 0usize
    while i < n {
        var ip = 0.0f64
        cc = 0usize
        while cc < bf.qrank {
            var t = x[bf.qr.pivot[cc] * n + i]
            var r = 0usize
            while r < cc {
                t = t - bf.qr.qr[cc * n + r] * vv[r]
                r += 1usize
            }
            vv[cc] = t / bf.qr.qr[cc * n + cc]
            ip += vv[cc] * vv[cc] * disp
            cc += 1usize
        }
        var lv = 0.0f64
        k = 0usize
        while k < q {
            lv += vr[k * n + i]
            k += 1usize
        }
        sel[i] = math.sqrt[f64](ip + disp * lv)
        ses[i] = sel[i] * math.abs[f64](mu_eta(fam, eta[i]))
        i += 1usize
    }
    out.se_link = sel
    out.se_resp = ses
    out.par_df = pdf
    out.par_ss = pss
    out.par_f = pfv
    out.par_p = ppv
    out.ssr = ssr
    out.disp = disp
    out.np_df = npdf
    out.np_stat = npst
    out.np_p = npp
    ret ok
}

// anova(m1, m2, test = "Chisq" / "F") of two Gam fits, the second row: Df, Deviance, Pr(>Chi), F, Pr(>F). The dispersion is that of the fit with the smaller residual df; F is NaN when it is 1 (binomial, Poisson)
// the nonlinear part of the loess smooth (degree 1 or 2) of z at the new points xe (the package gam.lo with xeval: lowese minus the weighted polynomial fit of the smooth at the data on the term columns)
fn lo_eval(a: *mem.Arena, c: *const LoCache, deg: usize, z: []const f64, w: []const f64, n: usize, mt: []const usize, xe: []const f64, out: []f64) {
    let nef = c.nef
    let yb = zal(a, nef)
    var i = 0usize
    while i < n {
        yb[mt[i]] += z[i] * w[i]
        i += 1usize
    }
    i = 0usize
    while i < nef {
        yb[i] = yb[i] * c.sqwi[i] * c.sqwi[i]
        i += 1usize
    }
    let sf = zal(a, nef)
    var sw = 0.0f64
    var sx = 0.0f64
    i = 0usize
    while i < nef {
        var t = 0.0f64
        var j = 0usize
        while j < nef {
            t += c.sop[i * nef + j] * yb[j]
            j += 1usize
        }
        sf[i] = t
        sw += c.win[i]
        sx += c.win[i] * c.xu[i]
        i += 1usize
    }
    let xb = sx / sw
    // the parametric fit of the smooth on 1, u, u^2 (u = x - xb) for degree 2, on 1, u for degree 1: gam.lo subtracts cbind(1, xeval) %*% beta over all the term's columns
    var g: [9]f64 = zero
    var rhs: [3]f64 = zero
    i = 0usize
    while i < nef {
        let u = c.xu[i] - xb
        var bs: [3]f64 = zero
        bs[0usize] = 1.0f64
        bs[1usize] = u
        bs[2usize] = u * u
        var r1 = 0usize
        while r1 <= deg {
            rhs[r1] += c.win[i] * bs[r1] * sf[i]
            var r2 = 0usize
            while r2 <= deg {
                g[r1 * 3usize + r2] += c.win[i] * bs[r1] * bs[r2]
                r2 += 1usize
            }
            r1 += 1usize
        }
        i += 1usize
    }
    // Gaussian elimination with partial pivoting on the (deg + 1) square system
    var r1 = 0usize
    while r1 <= deg {
        var piv = r1
        var r2 = r1 + 1usize
        while r2 <= deg {
            if math.abs[f64](g[r2 * 3usize + r1]) > math.abs[f64](g[piv * 3usize + r1]) { piv = r2 }
            r2 += 1usize
        }
        if piv != r1 {
            var cc = 0usize
            while cc <= deg {
                let tg = g[r1 * 3usize + cc]
                g[r1 * 3usize + cc] = g[piv * 3usize + cc]
                g[piv * 3usize + cc] = tg
                cc += 1usize
            }
            let tr = rhs[r1]
            rhs[r1] = rhs[piv]
            rhs[piv] = tr
        }
        r2 = r1 + 1usize
        while r2 <= deg {
            let fct = g[r2 * 3usize + r1] / g[r1 * 3usize + r1]
            var cc = r1
            while cc <= deg {
                g[r2 * 3usize + cc] -= fct * g[r1 * 3usize + cc]
                cc += 1usize
            }
            rhs[r2] -= fct * rhs[r1]
            r2 += 1usize
        }
        r1 += 1usize
    }
    var beta: [3]f64 = zero
    var r3 = deg + 1usize
    while r3 > 0usize {
        r3 -= 1usize
        var t = rhs[r3]
        var cc = r3 + 1usize
        while cc <= deg {
            t -= g[r3 * 3usize + cc] * beta[cc]
            cc += 1usize
        }
        beta[r3] = t / g[r3 * 3usize + r3]
    }
    let v0 = zal(a, c.nv)
    let v1 = zal(a, c.nv)
    var v = 0usize
    while v < c.nv {
        var t0 = 0.0f64
        var t1 = 0.0f64
        var j = 0usize
        while j < nef {
            t0 += c.op0[v * nef + j] * yb[j]
            t1 += c.op1[v * nef + j] * yb[j]
            j += 1usize
        }
        v0[v] = t0
        v1[v] = t1
        v += 1usize
    }
    i = 0usize
    while i < xe.len {
        var cell = 0usize
        while cell + 1usize < c.nv - 1usize && xe[i] > c.vv[cell + 1usize] { cell += 1usize }
        let wd = c.vv[cell + 1usize] - c.vv[cell]
        let h = (xe[i] - c.vv[cell]) / wd
        let phi0 = (1.0f64 - h) * (1.0f64 - h) * (1.0f64 + 2.0f64 * h)
        let phi1 = h * h * (3.0f64 - 2.0f64 * h)
        let psi0 = h * (1.0f64 - h) * (1.0f64 - h)
        let psi1 = h * h * (h - 1.0f64)
        out[i] = phi0 * v0[cell] + phi1 * v0[cell + 1usize] + (psi0 * v1[cell] + psi1 * v1[cell + 1usize]) * wd - (beta[0usize] + beta[1usize] * (xe[i] - xb) + beta[2usize] * (xe[i] - xb) * (xe[i] - xb))
        i += 1usize
    }
}

// predict.Gam(fit, newdata, type = "link" or "response") for the terms of gam_fit: xnew is the m by p model matrix of the new rows (column-major, the columns of x); each smooth term is refitted to
// the working residual plus its smooth under the final weights and evaluated at the new rows, as the package does. R gives no standard errors here. lo() new x must lie inside the data box.
fn gam_predict(a: *mem.Arena, xin_: []const f64, n: usize, p: usize, fam: usize, q: usize, which: []const usize, df: []const f64, spar0: []const f64, f: *const GamFit, xnew: []const f64, m: usize, response: bool, out: []f64) -> err {
    var i = 0usize
    while i < m {
        var t = 0.0f64
        var j = 0usize
        while j < p {
            if f.coef[j] == f.coef[j] { t += f.coef[j] * xnew[j * m + i] }
            j += 1usize
        }
        out[i] = t
        i += 1usize
    }
    let mt = zal_u(a, n)
    let z = zal(a, n)
    let smo = zal(a, n)
    let lev = zal(a, n + 1usize)
    let col = zal(a, n)
    let ev = zal(a, m)
    let evo = zal(a, m)
    var k = 0usize
    while k < q {
        let cj = which[k]
        i = 0usize
        while i < n {
            z[i] = f.resid[i] + f.smooth[k * n + i]
            col[i] = xin_[cj * n + i]
            i += 1usize
        }
        i = 0usize
        while i < m {
            ev[i] = xnew[cj * m + i]
            i += 1usize
        }
        if df[k] < 0.0f64 {
            let nef = gam_match(a, col, n, mt)
            var c: LoCache = zero
            let le = lo_build(a, xin_, n, cj, usize(spar0[k]), f.weights, mt, nef, 0.0f64 - df[k], &c)
            if le != ok { ret le }
            lo_eval(a, &c, usize(spar0[k]), z, f.weights, n, mt, ev, evo)
        } else {
            i = 0usize
            while i < n {
                col[i] = signif6(col[i])
                i += 1usize
            }
            let nef = gam_match(a, col, n, mt)
            var spar = spar0[k]
            var dof = df[k]
            var s0 = 0.0f64
            let se = splsm(a, col, z, f.weights, n, mt, nef, &spar, &dof, smo, &s0, lev, ev, evo)
            if se != ok { ret se }
        }
        i = 0usize
        while i < m {
            out[i] += evo[i]
            i += 1usize
        }
        k += 1usize
    }
    if response {
        i = 0usize
        while i < m {
            out[i] = linkinv(fam, out[i])
            i += 1usize
        }
    }
    ret ok
}

fn anova_two(f1: *const GamFit, f2: *const GamFit) -> [5]f64 {
    var disp = f1.disp
    var dfscale = f1.df_resid
    if f2.df_resid < f1.df_resid {
        disp = f2.disp
        dfscale = f2.df_resid
    }
    let dfs = f1.df_resid - f2.df_resid
    let dv = f1.deviance - f2.deviance
    var out: [5]f64 = zero
    out[0usize] = dfs
    out[1usize] = dv
    var vals = dv / disp
    if dfs < 0.0f64 { vals = 0.0f64 - vals }
    out[2usize] = nm.pchisq(vals, math.abs[f64](dfs), false, false)
    out[3usize] = 0.0f64 / 0.0f64
    out[4usize] = 0.0f64 / 0.0f64
    if disp != 1.0f64 {
        let fv = dv / dfs / disp
        out[3usize] = fv
        out[4usize] = nb.pf(fv, math.abs[f64](dfs), dfscale, false, false)
    }
    ret out
}

type StepPath = struct { nm: usize, items: []usize, aic: []f64, dev: []f64, dfres: []f64, final_fit: GamFit }

// the fit of a stepping state: variable v takes option items[v] (1-based) of its scope; kind 0 leaves it out (the "1" regimen), 1 enters it linearly, 2 through s(x, df = dfv), 3 through lo(x, span = dfv); the s() terms come first as the package orders them
fn fit_items(a: *mem.Arena, xv: []const f64, n: usize, nv: usize, y: []const f64, w: []const f64, fam: usize, maxopt: usize, kind: []const usize, dfv: []const f64, items: []const usize, out: *GamFit) -> err {
    var p = 1usize
    var q = 0usize
    var qs = 0usize
    var v = 0usize
    while v < nv {
        let kd = kind[v * maxopt + items[v] - 1usize]
        if kd > 0usize { p += 1usize }
        if kd > 1usize { q += 1usize }
        if kd == 2usize { qs += 1usize }
        v += 1usize
    }
    let x = zal(a, n * p)
    let wh = zal_u(a, q + 1usize)
    let df = zal(a, q + 1usize)
    let sp = zal(a, q + 1usize)
    var i = 0usize
    while i < n {
        x[i] = 1.0f64
        i += 1usize
    }
    var col = 1usize
    var k = 0usize
    var kl = qs
    v = 0usize
    while v < nv {
        let kd = kind[v * maxopt + items[v] - 1usize]
        if kd > 0usize {
            i = 0usize
            while i < n {
                x[col * n + i] = xv[v * n + i]
                i += 1usize
            }
            if kd == 2usize {
                wh[k] = col
                df[k] = dfv[v * maxopt + items[v] - 1usize]
                sp[k] = 1.0f64
                k += 1usize
            }
            if kd == 3usize {
                wh[kl] = col
                df[kl] = 0.0f64 - dfv[v * maxopt + items[v] - 1usize]
                sp[kl] = 1.0f64
                kl += 1usize
            }
            col += 1usize
        }
        v += 1usize
    }
    ret gam_fit(a, x, n, p, y, w, fam, q, wh[0usize..q], df[0usize..q], sp[0usize..q], 1.0e-7f64, 30usize, 1.0e-7f64, 30usize, out)
}

// step.Gam: direction 0 both, 1 backward, 2 forward; start the 1-based option of each variable; the path of accepted models (the first is the start)
fn step_gam(a: *mem.Arena, xv: []const f64, n: usize, nv: usize, y: []const f64, w: []const f64, fam: usize, maxopt: usize, nopt: []const usize, kind: []const usize, dfv: []const f64, start: []const usize, direction: usize, max_steps: usize, path: *StepPath) -> err {
    let cap = 2usize * nv * (max_steps + 2usize) + 2usize
    let visited = zal_u(a, cap * nv)
    let pitems = zal_u(a, (max_steps + 2usize) * nv)
    let paic = zal(a, max_steps + 2usize)
    let pdev = zal(a, max_steps + 2usize)
    let pdf = zal(a, max_steps + 2usize)
    let items = zal_u(a, nv)
    var nvis = 1usize
    var v = 0usize
    while v < nv {
        items[v] = start[v]
        visited[v] = start[v]
        pitems[v] = start[v]
        v += 1usize
    }
    var fit: GamFit = zero
    var e = fit_items(a, xv, n, nv, y, w, fam, maxopt, kind, dfv, items, &fit)
    if e != ok { ret e }
    var best_aic = fit.aic
    paic[0usize] = best_aic
    pdev[0usize] = fit.deviance
    pdf[0usize] = fit.df_resid
    var nm_ = 1usize
    var aicv = best_aic + 1.0f64
    var steps = max_steps
    let trials = zal_u(a, 2usize * nv * nv)
    let taic = zal(a, 2usize * nv)
    var stepped = false
    while best_aic < aicv && steps > 0usize {
        steps -= 1usize
        aicv = best_aic
        var nt = 0usize
        v = 0usize
        while v < nv {
            var dir = 0usize
            while dir < 2usize {
                var ok_ = false
                var tv = items[v]
                if dir == 0usize && (direction == 0usize || direction == 1usize) && items[v] > 1usize {
                    tv = items[v] - 1usize
                    ok_ = true
                }
                if dir == 1usize && (direction == 0usize || direction == 2usize) && items[v] + 1usize <= nopt[v] {
                    tv = items[v] + 1usize
                    ok_ = true
                }
                if ok_ {
                    var seen = false
                    var s = 0usize
                    while s < nvis {
                        var same = true
                        var u = 0usize
                        while u < nv {
                            var cmp = items[u]
                            if u == v { cmp = tv }
                            if visited[s * nv + u] != cmp { same = false }
                            u += 1usize
                        }
                        if same { seen = true }
                        s += 1usize
                    }
                    if !seen {
                        var u = 0usize
                        while u < nv {
                            var cmp = items[u]
                            if u == v { cmp = tv }
                            visited[nvis * nv + u] = cmp
                            trials[nt * nv + u] = cmp
                            u += 1usize
                        }
                        nvis += 1usize
                        nt += 1usize
                    }
                }
                dir += 1usize
            }
            v += 1usize
        }
        if nt == 0usize { break }
        let fits = zal_gf(a, nt)
        var t = 0usize
        var best = 0usize
        while t < nt {
            let tm = zal_u(a, nv)
            var u = 0usize
            while u < nv {
                tm[u] = trials[t * nv + u]
                u += 1usize
            }
            e = fit_items(a, xv, n, nv, y, w, fam, maxopt, kind, dfv, tm[0usize..nv], &fits[t])
            if e != ok { ret e }
            taic[t] = fits[t].aic
            if taic[t] < taic[best] { best = t }
            t += 1usize
        }
        best_aic = taic[best]
        if best_aic >= aicv || steps == 0usize { break }
        fit = fits[best]
        var u = 0usize
        while u < nv {
            items[u] = trials[best * nv + u]
            pitems[nm_ * nv + u] = items[u]
            u += 1usize
        }
        paic[nm_] = best_aic
        pdev[nm_] = fit.deviance
        pdf[nm_] = fit.df_resid
        nm_ += 1usize
        stepped = true
    }
    let _ = stepped
    path.nm = nm_
    path.items = pitems
    path.aic = paic
    path.dev = pdev
    path.dfres = pdf
    path.final_fit = fit
    ret ok
}

fn zal_gf(a: *mem.Arena, n: usize) -> []GamFit {
    let (v, e) = mem.alloc[GamFit](a, n + 1usize)
    if e != ok {
        var em: []GamFit = zero
        ret em
    }
    var i = 0usize
    while i < n + 1usize {
        var z: GamFit = zero
        v[i] = z
        i += 1usize
    }
    ret v[0usize..n]
}

fn zal_u(a: *mem.Arena, n: usize) -> []usize {
    let (v, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok {
        var em: []usize = zero
        ret em
    }
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0usize
        i += 1usize
    }
    ret v[0usize..n]
}
