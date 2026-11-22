// R bbmle: mle2 (the default optim BFGS with optim's numerical gradient, ndeps 1e-3, reltol sqrt(eps), maxit 100, then numDeriv::hessian and the inverse for vcov), profile (proffun of profile.R with its
// default alpha 0.01, maxsteps 100, del = zmax / 5, sequential refits from the full fit's coefficients, the extra steps past the cutoff and the smaller steps), confint (the spline method of confint.profile.mle2 and
// the quadratic one) and AICctab, BICtab and AICtab (ICtab with weights), on the five log-likelihoods of maxlikpkg.e (minus the log-likelihood is the objective).
//
// ponytail: vcov is the plain inverse where R uses MASS::ginv (they agree for a Hessian of full rank); approx collapses equal x by the mean but the spline's equal-x ties are not merged. Not here: bounds, parscale, other
// optimizers, the uniroot confint, continuation and try_harder profiling, formula and vecpar interfaces.

use e.algo.stat.maxlikpkg as ml
use e.algo.stat.rbfgs as bf
use e.algo.stat.splinepkg as spl
use e.math
use e.math.dist as dist
use e.math.nmath as nmath
use e.math.numderiv as nd
use e.mem

type FitCtx = struct { m: *ml.MCtx, p: usize, fixed: []f64, fval: []f64, full: []f64, xs: []f64, bad: bool }

fn nfree(c: *FitCtx) -> usize {
    var k = 0usize
    var j = 0usize
    while j < c.p {
        if c.fixed[j] == 0.0f64 { k += 1usize }
        j += 1usize
    }
    ret k
}

// minus the log-likelihood over the free parameters (the fixed ones come from fval)
fn fobj(c: *FitCtx, par: []const f64) -> f64 {
    var k = 0usize
    var j = 0usize
    while j < c.p {
        if c.fixed[j] != 0.0f64 {
            c.full[j] = c.fval[j]
        } else {
            c.full[j] = par[k]
            k += 1usize
        }
        j += 1usize
    }
    ret 0.0f64 - ml.ll(c.m, c.full)
}

// optim's numerical gradient: central differences with ndeps 1e-3; a non-finite value is the error R raises
fn fgr(c: *FitCtx, par: []const f64, g: []f64) {
    let nf = nfree(c)
    let eps = 0.001f64
    var i = 0usize
    while i < nf {
        c.xs[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < nf {
        c.xs[i] = par[i] + eps
        let v1 = fobj(c, c.xs[0usize..nf])
        c.xs[i] = par[i] - eps
        let v2 = fobj(c, c.xs[0usize..nf])
        g[i] = (v1 - v2) / (2.0f64 * eps)
        if g[i] != g[i] || g[i] - g[i] != 0.0f64 { c.bad = true }
        c.xs[i] = par[i]
        i += 1usize
    }
}

// optim(method = "BFGS") from par (the free start, receives the estimate); returns minus the log-likelihood there. c.bad is set when R would raise an error
fn fit(a: *mem.Arena, c: *FitCtx, par: []f64) -> f64 {
    let nf = nfree(c)
    c.bad = false
    let f0 = fobj(c, par[0usize..nf])
    if nf == 0usize { ret f0 }
    if f0 != f0 || f0 - f0 != 0.0f64 {
        c.bad = true
        ret f0
    }
    let fm = bf.vmmin[FitCtx](a, c, fobj, fgr, par[0usize..nf], 1.4901161193847656e-08f64, 100usize)
    ret fm
}

fn fvec(c: *FitCtx, x: []const f64, out: []f64) { out[0usize] = fobj(c, x) }

// the full fit of mle2: coef and se (sqrt of the diagonal of the inverse of numDeriv::hessian); returns the minimum, or NaN when R would fail
fn mle2(a: *mem.Arena, c: *FitCtx, start: []const f64, coef: []f64, se: []f64) -> f64 {
    let p = c.p
    var j = 0usize
    while j < p {
        c.fixed[j] = 0.0f64
        coef[j] = start[j]
        j += 1usize
    }
    let mn = fit(a, c, coef)
    if c.bad { ret 0.0f64 / 0.0f64 }
    var o = nd.hessian_defaults()
    let (h, he) = nd.hessian_richardson[FitCtx](a, c, fvec, coef[0usize..p], &o)
    if he != ok { ret 0.0f64 / 0.0f64 }
    let (neg, e1) = mem.alloc[f64](a, p * p)
    let (col, e2) = mem.alloc[f64](a, p)
    let (inv, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    j = 0usize
    while j < p {
        var i = 0usize
        while i < p {
            var q = 0usize
            while q < p {
                neg[i * p + q] = h[i * p + q]
                q += 1usize
            }
            col[i] = 0.0f64
            i += 1usize
        }
        col[j] = 1.0f64
        if !ml.solve(neg, p, col) { ret 0.0f64 / 0.0f64 }
        i = 0usize
        while i < p {
            inv[i * p + j] = col[i]
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        se[j] = math.sqrt[f64](inv[j * p + j])
        j += 1usize
    }
    ret mn
}

type PState = struct { i: usize, b0: []const f64, se: []const f64, min0: f64, sgn: f64, del: f64, zi: []f64, pv: []f64, n: usize, cap: usize, newpars: bool }

// one profile point (onestep of proffun): fix parameter i at b, refit the others from b0, record the row; the answer is z, NaN for an error or an unusable fit
fn onestep(a: *mem.Arena, c: *FitCtx, st: *PState, step: f64) -> f64 {
    let p = c.p
    let bi = st.b0[st.i] + st.sgn * step * st.del * st.se[st.i]
    var j = 0usize
    while j < p {
        c.fixed[j] = 0.0f64
        if j == st.i {
            c.fixed[j] = 1.0f64
            c.fval[j] = bi
        }
        j += 1usize
    }
    let nf = nfree(c)
    let (par, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    j = 0usize
    while j < p {
        if j != st.i {
            par[k] = st.b0[j]
            k += 1usize
        }
        j += 1usize
    }
    let mn = fit(a, c, par[0usize..nf])
    if c.bad { ret 0.0f64 / 0.0f64 }
    let zz = 2.0f64 * (mn - st.min0)
    var z = 0.0f64
    if zz == zz && zz < 0.0f64 {
        if zz > -0.001f64 {
            z = 0.0f64
        } else {
            st.newpars = true
            ret 0.0f64 / 0.0f64
        }
    } else {
        z = st.sgn * math.sqrt[f64](zz)
    }
    if st.n < st.cap {
        k = 0usize
        j = 0usize
        while j < p {
            if j == st.i {
                st.pv[st.n * p + j] = bi
            } else {
                st.pv[st.n * p + j] = par[k]
                k += 1usize
            }
            j += 1usize
        }
        st.zi[st.n] = z
        st.n += 1usize
    }
    ret z
}

fn same(a: f64, b: f64) -> bool {
    if a != a && b != b { ret true }
    ret a == b
}

// profile(fitted, which = i): the points sorted by parameter i, z into zout (cap values) and the full parameter rows into pvout (row-major, p columns); returns the number of points, or 0 when profiling finds a better fit (R returns that fit instead)
fn profile(a: *mem.Arena, c: *FitCtx, b0: []const f64, se: []const f64, min0: f64, i: usize, zout: []f64, pvout: []f64) -> usize {
    let p = c.p
    let cap = zout.len
    let zmax = math.sqrt[f64](nmath.qchisq(1.0f64 - 0.01f64 / 2.0f64, f64(p), true, false))
    let del = zmax / 5.0f64
    let maxsteps = 100.0f64
    var st = PState{ i: i, b0: b0, se: se, min0: min0, sgn: -1.0f64, del: del, zi: zout, pv: pvout, n: 1usize, cap: cap, newpars: false }
    st.zi[0usize] = 0.0f64
    var j = 0usize
    while j < p {
        st.pv[j] = b0[j]
        j += 1usize
    }
    var dir = 0usize
    while dir < 2usize {
        if dir == 0usize { st.sgn = -1.0f64 } else { st.sgn = 1.0f64 }
        var step = 0.0f64
        var z = 0.0f64
        var oldz = 0.0f64
        var oldcur = 0.0f64
        var stop_flat = false
        var go = true
        while go {
            step = step + 1.0f64
            if !(step < maxsteps && (z != z || math.abs[f64](z) < zmax)) {
                go = false
            } else {
                let curval = b0[i] + st.sgn * step * del * se[i]
                if curval != curval {
                    go = false
                } else {
                    z = onestep(a, c, &st, step)
                    if st.newpars { ret 0usize }
                    if step > 1.0f64 && (oldcur == curval || same(oldz, z)) {
                        stop_flat = true
                        go = false
                    } else {
                        oldcur = curval
                        oldz = z
                        if z != z { go = false }
                    }
                }
            }
        }
        let stop_cutoff = z == z && math.abs[f64](z) >= zmax
        if !stop_flat {
            if !stop_cutoff {
                var ds: [5]f64 = zero
                ds[0usize] = 0.2f64
                ds[1usize] = 0.4f64
                ds[2usize] = 0.6f64
                ds[3usize] = 0.8f64
                ds[4usize] = 0.9f64
                var d = 0usize
                var more = true
                while d < 5usize && more {
                    let curval = b0[i] + st.sgn * (step - 1.0f64 + ds[d]) * del * se[i]
                    if curval != curval {
                        more = false
                    } else {
                        z = onestep(a, c, &st, step - 1.0f64 + ds[d])
                        if st.newpars { ret 0usize }
                        if z != z || math.abs[f64](z) > zmax { more = false }
                    }
                    d += 1usize
                }
            } else if st.n < 5usize {
                let mxstep = step - 1.0f64
                step = 0.5f64
                var more = true
                while more {
                    step = step + 1.0f64
                    if !(step < mxstep) {
                        more = false
                    } else {
                        z = onestep(a, c, &st, step)
                        if st.newpars { ret 0usize }
                    }
                }
            }
        }
        dir += 1usize
    }
    // order(pvi[, i]): a stable insertion sort of the rows by column i
    var r = 1usize
    while r < st.n {
        let kz = st.zi[r]
        var row: [8]f64 = zero
        j = 0usize
        while j < p {
            row[j] = st.pv[r * p + j]
            j += 1usize
        }
        var q = r
        while q > 0usize && st.pv[(q - 1usize) * p + i] > row[i] {
            st.zi[q] = st.zi[q - 1usize]
            j = 0usize
            while j < p {
                st.pv[q * p + j] = st.pv[(q - 1usize) * p + j]
                j += 1usize
            }
            q -= 1usize
        }
        st.zi[q] = kz
        j = 0usize
        while j < p {
            st.pv[q * p + j] = row[j]
            j += 1usize
        }
        r += 1usize
    }
    ret st.n
}

// R's approx (linear, rule 1, ties = mean) of (xs, ys), xs ascending, at v
fn approx(xs: []const f64, ys: []const f64, m: usize, v: f64) -> f64 {
    if m == 0usize { ret 0.0f64 / 0.0f64 }
    var ux: [512]f64 = zero
    var uy: [512]f64 = zero
    var k = 0usize
    var i = 0usize
    while i < m && k < 512usize {
        var s = ys[i]
        var cnt = 1.0f64
        while i + 1usize < m && xs[i + 1usize] == xs[i] {
            i += 1usize
            s = s + ys[i]
            cnt = cnt + 1.0f64
        }
        ux[k] = xs[i]
        uy[k] = s / cnt
        k += 1usize
        i += 1usize
    }
    if k == 0usize || v < ux[0usize] || v > ux[k - 1usize] || v != v { ret 0.0f64 / 0.0f64 }
    var lo = 0usize
    var hi = k - 1usize
    while lo + 1usize < hi {
        let ij = (lo + hi) / 2usize
        if v < ux[ij] { hi = ij } else { lo = ij }
    }
    if v == ux[hi] { ret uy[hi] }
    if v == ux[lo] { ret uy[lo] }
    ret uy[lo] + (uy[hi] - uy[lo]) * ((v - ux[lo]) / (ux[hi] - ux[lo]))
}

// confint of a profile (the spline method): z and pv are the m sorted points of one parameter; out = (lower, upper), NaN where approx gives NA
fn confint_profile(a: *mem.Arena, z: []const f64, pv: []const f64, m: usize, level: f64, out: []f64) {
    let nan = 0.0f64 / 0.0f64
    out[0usize] = nan
    out[1usize] = nan
    let al = (1.0f64 - level) / 2.0f64
    let cut0 = dist.qnorm(al, 0.0f64, 1.0f64, true, false)
    let cut1 = dist.qnorm(1.0f64 - al, 0.0f64, 1.0f64, true, false)
    var mono = true
    var i = 0usize
    while i + 1usize < m {
        if z[i + 1usize] - z[i] < 0.0f64 { mono = false }
        i += 1usize
    }
    var t0 = nan
    var t1 = nan
    var linear = !mono
    if mono {
        let nn = 3usize * m
        let (b, e1) = mem.alloc[f64](a, m)
        let (cc, e2) = mem.alloc[f64](a, m)
        let (d, e3) = mem.alloc[f64](a, m)
        let (sx, e4) = mem.alloc[f64](a, nn)
        let (sy, e5) = mem.alloc[f64](a, nn)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret }
        spl.fmm_spline(m, pv, z, b, cc, d)
        let from = pv[0usize]
        let by = (pv[m - 1usize] - from) / f64(nn - 1usize)
        i = 0usize
        while i < nn {
            var u = from + f64(i) * by
            if i == nn - 1usize { u = pv[m - 1usize] }
            sx[i] = u
            sy[i] = spl.spline_eval(m, pv, z, b, cc, d, u)
            i += 1usize
        }
        var spmono = true
        i = 0usize
        while i + 1usize < nn {
            if sy[i + 1usize] - sy[i] < 0.0f64 { spmono = false }
            i += 1usize
        }
        if spmono {
            t0 = approx(sy, sx, nn, cut0)
            t1 = approx(sy, sx, nn, cut1)
        } else {
            linear = true
        }
    }
    if linear {
        t0 = approx(z, pv, m, cut0)
        t1 = approx(z, pv, m, cut1)
    }
    if t0 == t0 && t1 == t1 && t0 > t1 {
        let t = t0
        t0 = t1
        t1 = t
    }
    out[0usize] = t0
    out[1usize] = t1
}

// confint(fitted, method = "quad"): qnorm(a, B0, se)
fn confint_quad(b0: f64, se: f64, level: f64, out: []f64) {
    let al = (1.0f64 - level) / 2.0f64
    out[0usize] = dist.qnorm(al, b0, se, true, false)
    out[1usize] = dist.qnorm(1.0f64 - al, b0, se, true, false)
}

// ICtab(type = AIC | BIC | AICc, weights = TRUE) on m models: ll and df per model, nobs for BIC and AICc. order receives the model indices sorted by criterion, d the delta in that order, w the weights in that order
fn ictab(ll: []const f64, df: []const f64, m: usize, nobs: f64, kind: usize, order: []usize, d: []f64, w: []f64) {
    var ic: [16]f64 = zero
    var i = 0usize
    while i < m {
        if kind == 0usize {
            ic[i] = -2.0f64 * ll[i] + 2.0f64 * df[i]
        } else if kind == 1usize {
            ic[i] = -2.0f64 * ll[i] + df[i] * math.log[f64](nobs)
        } else {
            ic[i] = -2.0f64 * ll[i] + 2.0f64 * df[i] + 2.0f64 * df[i] * (df[i] + 1.0f64) / (nobs - df[i] - 1.0f64)
        }
        order[i] = i
        i += 1usize
    }
    var mn = ic[0usize]
    i = 1usize
    while i < m {
        if ic[i] < mn { mn = ic[i] }
        i += 1usize
    }
    i = 1usize
    while i < m {
        let o = order[i]
        var q = i
        while q > 0usize && ic[order[q - 1usize]] > ic[o] {
            order[q] = order[q - 1usize]
            q -= 1usize
        }
        order[q] = o
        i += 1usize
    }
    var s = 0.0f64
    i = 0usize
    while i < m {
        d[i] = ic[order[i]] - mn
        s = s + math.exp[f64](0.0f64 - d[i] / 2.0f64)
        i += 1usize
    }
    i = 0usize
    while i < m {
        w[i] = math.exp[f64](0.0f64 - d[i] / 2.0f64) / s
        i += 1usize
    }
}
