// R coxme 2.2-22 `coxme()` (default coxmeFull variance functions): the mixed-effects Cox model of Ripatti and Palmgren, fitted
// by the same route as coxme.fit. Per theta (the log variance parameters) a Newton iteration on the penalised partial
// likelihood runs a fixed number of steps from the same start (coxfit6b); optim's BFGS (vmmin, central-difference gradient,
// step 1e-3, reltol 1e-5) minimises the negative integrated log likelihood over a grid-chosen start, then one more Newton fit
// to convergence gives the coefficients, the variance and the degrees of freedom. The starting coefficients come from
// survival's coxph.fit (coxfit6), whose iteration count sets the inner step count, max(4, iter + 1).
//
// The information matrix is dense. R's sparse path (a single factor with at least 50 levels, some holding at most 2% of the
// rows) is reproduced by what it drops: the off-diagonal entries between sparse levels in the information, and in the
// inverse that becomes the variance. The accumulation order follows coxfit6b so the BFGS path matches.
//
// Supported: right-censored (time, status) data, strata, case weights, an offset, Efron or Breslow ties, any number of random
// terms (1|g), nested (1|g1/g2/...) with the expanded level codes outermost first, one random slope (z|g), (0+z|g) as one group.
// Not here: (start, stop] data, shrinkage terms (x|1), vfixed/vinit, kinship varlist matrices, refine.n, slopes with a sparse
// group. Several slopes in one term and slopes over nested groups are not fitted either: coxmeFull itself stops on them
// (R 4.6 / coxme 2.2-22 errors in gchol and in xmap), so there is nothing to equal.

use e.math
use e.mem
use e.algo.stat.rbfgs as bf

error CoxmeUnsupported

type CoxmeTerm = struct { icpt: bool, ng: usize, codes: []const usize, nvar: usize, xs: []const f64 }

type CoxmeFit = struct {
    nfixed: usize, nfrail: usize, ntheta: usize, nvc: usize,
    fixef: []f64, frail: []f64, theta: []f64, vcoef: []f64, vmat: []f64,
    ll_null: f64, ll_int: f64, ll_pen: f64, penalty: f64, df_int: f64, df_pen: f64,
    it_outer: usize, it_inner: usize
}

type CoxCtx = struct {
    n: usize, nv: usize, efron: bool,
    rp: []usize, ci: []usize, cv: []f64,
    off: []f64, w: []f64, st: []f64, mark: []usize, wtave: []f64, sfirst: []usize,
    a: []f64, a2: []f64, tt: []f64, cm: []f64, cm2: []f64, u: []f64, im: []f64
}

type MeCtx = struct {
    cx: CoxCtx,
    nf: usize, nfac: usize, ns: usize, nfx: usize, nterm: usize, ntheta: usize,
    flo: []usize, fhi: []usize, psum: []f64, pen: []f64, obeta: []f64, pb: []f64,
    kmat: []f64, gk: []f64, thv: []f64, gx: []f64, start: []f64, bw: []f64, fb: []f64,
    t_ng: []usize, t_icpt: []usize, t_nvar: []usize, t_th0: []usize, t_nth: []usize,
    t_i0: []usize, t_m: []usize, t_s0: []usize, t_c0: []usize, clo: []usize, chi: []usize,
    ll0: f64, eps: f64, tolch: f64, inner: usize, count: usize, hdet: f64, sumlogd: f64, lastll: f64
}

fn cxm_af(a: *mem.Arena, n: usize) -> ([]f64, err) {
    var m = n
    if m == 0usize { m = 1usize }
    let (v, e) = mem.alloc[f64](a, m)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < m {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v[0usize..n], ok)
}

fn cxm_au(a: *mem.Arena, n: usize) -> ([]usize, err) {
    var m = n
    if m == 0usize { m = 1usize }
    let (v, e) = mem.alloc[usize](a, m)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < m {
        v[i] = 0usize
        i += 1usize
    }
    ret (v[0usize..n], ok)
}

fn cxm_fin(v: f64) -> bool { ret v - v == 0.0f64 }

// the partial log likelihood at beta (start: the value the sum begins from), with the score in c.u and the lower triangle of
// the information in c.im; the loop is coxfit6b's, Breslow or Efron
fn cxm_eval(c: *CoxCtx, beta: []const f64, start: f64) -> f64 {
    let nv = c.nv
    var ll = start
    var i = 0usize
    while i < nv {
        c.u[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nv * nv {
        c.im[i] = 0.0f64
        i += 1usize
    }
    var denom = 0.0f64
    var efw = 0.0f64
    var p = 0usize
    while p < c.n {
        if c.sfirst[p] == 1usize {
            denom = 0.0f64
            efw = 0.0f64
            i = 0usize
            while i < nv {
                c.a[i] = 0.0f64
                c.a2[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < nv * nv {
                c.cm[i] = 0.0f64
                c.cm2[i] = 0.0f64
                i += 1usize
            }
        }
        let lo = c.rp[p]
        let hi = c.rp[p + 1usize]
        var z = c.off[p]
        var k = lo
        while k < hi {
            z += beta[c.ci[k]] * c.cv[k]
            k += 1usize
        }
        let risk = math.exp[f64](z) * c.w[p]
        denom += risk
        k = lo
        while k < hi {
            let ik = c.ci[k]
            let vk = c.cv[k]
            c.a[ik] += risk * vk
            var l = lo
            while l < hi {
                let il = c.ci[l]
                if il <= ik { c.cm[ik * nv + il] += risk * vk * c.cv[l] }
                l += 1usize
            }
            k += 1usize
        }
        if c.st[p] == 1.0f64 {
            ll += c.w[p] * z
            efw += risk
            k = lo
            while k < hi {
                let ik = c.ci[k]
                let vk = c.cv[k]
                c.u[ik] += c.w[p] * vk
                c.a2[ik] += risk * vk
                var l = lo
                while l < hi {
                    let il = c.ci[l]
                    if il <= ik { c.cm2[ik * nv + il] += risk * vk * c.cv[l] }
                    l += 1usize
                }
                k += 1usize
            }
        }
        if c.mark[p] > 0usize {
            let nd = c.mark[p]
            if !c.efron || nd == 1usize {
                let temp = c.wtave[p] * f64(nd)
                ll -= temp * math.log[f64](denom)
                var r = 0usize
                while r < nv {
                    c.tt[r] = c.a[r] / denom
                    c.u[r] -= temp * c.tt[r]
                    r += 1usize
                }
                r = 0usize
                while r < nv {
                    var s = 0usize
                    while s <= r {
                        c.im[r * nv + s] += temp * (c.cm[r * nv + s] / denom - c.tt[r] * c.tt[s])
                        s += 1usize
                    }
                    r += 1usize
                }
            } else {
                var kk = 0usize
                while kk < nd {
                    let fr = f64(kk) / f64(nd)
                    let d2 = denom - fr * efw
                    ll -= c.wtave[p] * math.log[f64](d2)
                    var r = 0usize
                    while r < nv {
                        c.tt[r] = (c.a[r] - fr * c.a2[r]) / d2
                        c.u[r] -= c.wtave[p] * c.tt[r]
                        r += 1usize
                    }
                    r = 0usize
                    while r < nv {
                        var s = 0usize
                        while s <= r {
                            c.im[r * nv + s] += c.wtave[p] * ((c.cm[r * nv + s] - fr * c.cm2[r * nv + s]) / d2 - c.tt[r] * c.tt[s])
                            s += 1usize
                        }
                        r += 1usize
                    }
                    kk += 1usize
                }
            }
            efw = 0.0f64
            i = 0usize
            while i < nv {
                c.a2[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < nv * nv {
                c.cm2[i] = 0.0f64
                i += 1usize
            }
        }
        p += 1usize
    }
    ret ll
}

// cholesky4 on a dense matrix: C = LDL' in the lower triangle, D on the diagonal; a pivot under eps = max|diag| * toler zeroes
// its column. Returns the rank.
fn cxm_gchol4(m: []f64, n: usize, toler: f64) -> usize {
    var eps = 0.0f64
    var i = 0usize
    while i < n {
        if math.abs[f64](m[i * n + i]) > eps { eps = math.abs[f64](m[i * n + i]) }
        i += 1usize
    }
    if eps > 0.0f64 {
        eps = eps * toler
    } else {
        eps = toler
    }
    var rank = 0usize
    i = 0usize
    while i < n {
        let pivot = m[i * n + i]
        if math.abs[f64](pivot) < eps {
            var j = i
            while j < n {
                m[j * n + i] = 0.0f64
                j += 1usize
            }
        } else {
            rank += 1usize
            var j = i + 1usize
            while j < n {
                let temp = m[j * n + i] / pivot
                m[j * n + i] = temp
                m[j * n + j] -= temp * temp * pivot
                var k = j + 1usize
                while k < n {
                    m[k * n + j] -= temp * m[k * n + i]
                    k += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    ret rank
}

// survival's cholesky2: the same factorisation with a one-sided pivot test, non-finite pivots zeroed
fn cxm_gchol2(m: []f64, n: usize, toler: f64) {
    var eps = 0.0f64
    var i = 0usize
    while i < n {
        if m[i * n + i] > eps { eps = m[i * n + i] }
        i += 1usize
    }
    if eps == 0.0f64 {
        eps = toler
    } else {
        eps = eps * toler
    }
    i = 0usize
    while i < n {
        let pivot = m[i * n + i]
        if !cxm_fin(pivot) || pivot < eps {
            m[i * n + i] = 0.0f64
        } else {
            var j = i + 1usize
            while j < n {
                let temp = m[j * n + i] / pivot
                m[j * n + i] = temp
                m[j * n + j] -= temp * temp * pivot
                var k = j + 1usize
                while k < n {
                    m[k * n + j] -= temp * m[k * n + i]
                    k += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
}

// chsolve4 (flag 0) on a dense factor: y := A^-1 y
fn cxm_chsolve(m: []const f64, n: usize, y: []f64) {
    var j = 0usize
    while j < n {
        let temp = y[j]
        var k = j + 1usize
        while k < n {
            y[k] -= temp * m[k * n + j]
            k += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < n {
        let d = m[j * n + j]
        if d > 0.0f64 {
            y[j] = y[j] / d
        } else {
            y[j] = 0.0f64
        }
        j += 1usize
    }
    j = n
    while j > 0usize {
        j -= 1usize
        if m[j * n + j] == 0.0f64 {
            y[j] = 0.0f64
        } else {
            var temp = y[j]
            var k = j + 1usize
            while k < n {
                temp -= y[k] * m[k * n + j]
                k += 1usize
            }
            y[j] = temp
        }
    }
}

// chinv4 (flag 1) on a dense factor: the full symmetric inverse replaces it
fn cxm_chinv(m: []f64, n: usize) {
    var i = 0usize
    while i < n {
        if m[i * n + i] > 0.0f64 {
            m[i * n + i] = 1.0f64 / m[i * n + i]
            var k = i + 1usize
            while k < n {
                m[k * n + i] *= -1.0f64
                k += 1usize
            }
            var j = i + 1usize
            while j < n {
                let temp = m[j * n + i]
                k = j + 1usize
                while k < n {
                    m[k * n + i] -= temp * m[k * n + j]
                    k += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        if m[i * n + i] == 0.0f64 {
            var k = i
            while k < n {
                m[k * n + i] = 0.0f64
                m[i * n + k] = 0.0f64
                k += 1usize
            }
        } else {
            var temp = m[i * n + i]
            var k = i + 1usize
            while k < n {
                temp += m[k * n + i] * m[k * n + i] * m[k * n + k]
                m[k * n + i] *= m[k * n + k]
                k += 1usize
            }
            m[i * n + i] = temp
            var j = i + 1usize
            while j < n {
                temp = m[j * n + i]
                k = j + 1usize
                while k < n {
                    temp += m[k * n + i] * m[k * n + j]
                    k += 1usize
                }
                m[j * n + i] = temp
                m[i * n + j] = temp
                j += 1usize
            }
        }
        i += 1usize
    }
}

// order(strata, -time, status) for kind 0 (coxme), order(strata, time) for kind 1 (survival); ties by position
fn cxm_order(a: *mem.Arena, n: usize, strata: []const usize, time: []const f64, status: []const f64, kind: usize) -> ([]usize, err) {
    let (ord, e) = cxm_au(a, n)
    if e != ok { ret (ord, e) }
    var i = 0usize
    while i < n {
        var j = i
        while j > 0usize {
            let p = ord[j - 1usize]
            var swap = false
            if strata[p] != strata[i] {
                swap = strata[p] > strata[i]
            } else if time[p] != time[i] {
                if kind == 0usize {
                    swap = time[p] < time[i]
                } else {
                    swap = time[p] > time[i]
                }
            } else if kind == 0usize {
                swap = status[p] > status[i]
            }
            if !swap { break }
            ord[j] = p
            j -= 1usize
        }
        ord[j] = i
        i += 1usize
    }
    ret (ord, ok)
}

// the ragged storage of a CoxCtx for n rows of at most nzmax entries and nv coefficients
fn cxm_ctx(a: *mem.Arena, n: usize, nv: usize, nzmax: usize, efron: bool) -> (CoxCtx, err) {
    var c: CoxCtx = zero
    let (rp, e1) = cxm_au(a, n + 1usize)
    let (ci, e2) = cxm_au(a, n * nzmax)
    let (cv, e3) = cxm_af(a, n * nzmax)
    let (off, e4) = cxm_af(a, n)
    let (w, e5) = cxm_af(a, n)
    let (st, e6) = cxm_af(a, n)
    let (mark, e7) = cxm_au(a, n)
    let (wtave, e8) = cxm_af(a, n)
    let (sfirst, e9) = cxm_au(a, n)
    let (aa, e10) = cxm_af(a, nv)
    let (a2, e11) = cxm_af(a, nv)
    let (tt, e12) = cxm_af(a, nv)
    let (cm, e13) = cxm_af(a, nv * nv)
    let (cm2, e14) = cxm_af(a, nv * nv)
    let (u, e15) = cxm_af(a, nv)
    let (im, e16) = cxm_af(a, nv * nv)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (c, mem.Exhausted) }
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret (c, mem.Exhausted) }
    c.n = n
    c.nv = nv
    c.efron = efron
    c.rp = rp
    c.ci = ci
    c.cv = cv
    c.off = off
    c.w = w
    c.st = st
    c.mark = mark
    c.wtave = wtave
    c.sfirst = sfirst
    c.a = aa
    c.a2 = a2
    c.tt = tt
    c.cm = cm
    c.cm2 = cm2
    c.u = u
    c.im = im
    ret (c, ok)
}

// survival coxfit6 (coxph.fit with centred and scaled covariates, zero start): the coefficients on the scale of the scaled covariates,
// the log likelihood at 0 and at the fit, and the iteration count
fn cxm_cox0(c: *CoxCtx, p: usize, maxiter: usize, eps: f64, toler: f64, coef: []f64, nbeta: []f64, work: []f64) -> (f64, f64, usize) {
    var i = 0usize
    while i < p {
        coef[i] = 0.0f64
        i += 1usize
    }
    var beta = work[0usize..p]
    var newb = nbeta
    i = 0usize
    while i < p {
        beta[i] = 0.0f64
        i += 1usize
    }
    var iter = 0usize
    var ll0 = cxm_eval(c, beta, 0.0f64)
    var ll1 = ll0
    if p == 0usize { ret (ll0, ll0, 0usize) }
    var a1 = work[p..2usize * p]
    i = 0usize
    while i < p {
        a1[i] = c.u[i]
        i += 1usize
    }
    cxm_gchol2(c.im, p, toler)
    cxm_chsolve(c.im, p, a1)
    if maxiter == 0usize || !cxm_fin(ll0) { ret (ll0, ll1, 0usize) }
    i = 0usize
    while i < p {
        newb[i] = beta[i] + a1[i]
        i += 1usize
    }
    var halving = 0.0f64
    var done = false
    iter = 1usize
    while iter <= maxiter && !done {
        let newlk = cxm_eval(c, newb, 0.0f64)
        cxm_gchol2(c.im, p, toler)
        var nonfin = false
        i = 0usize
        while i < p {
            if !cxm_fin(c.u[i]) { nonfin = true }
            var j = 0usize
            while j < p {
                if !cxm_fin(c.im[i * p + j]) { nonfin = true }
                j += 1usize
            }
            i += 1usize
        }
        if !cxm_fin(newlk) { nonfin = true }
        if !nonfin && math.abs[f64](1.0f64 - ll1 / newlk) <= eps {
            ll1 = newlk
            i = 0usize
            while i < p {
                beta[i] = newb[i]
                i += 1usize
            }
            done = true
        } else if nonfin || newlk < ll1 {
            halving += 1.0f64
            i = 0usize
            while i < p {
                newb[i] = (newb[i] + halving * beta[i]) / (halving + 1.0f64)
                i += 1usize
            }
            iter += 1usize
        } else {
            halving = 0.0f64
            ll1 = newlk
            cxm_chsolve(c.im, p, c.u)
            i = 0usize
            while i < p {
                beta[i] = newb[i]
                newb[i] = newb[i] + c.u[i]
                i += 1usize
            }
            iter += 1usize
        }
    }
    if !done && maxiter > 1usize { ll1 = cxm_eval(c, beta, 0.0f64) }
    i = 0usize
    while i < p {
        coef[i] = beta[i]
        i += 1usize
    }
    ret (ll0, ll1, iter)
}

// the penalty is c.pen (nf by nf); coxfit6b: Newton steps with step halving between min_it and max_it, recentring each factor.
// Returns (penalised log likelihood, log det of the penalised block, iterations).
fn cxm_newton(c: *MeCtx, beta: []f64, min_it: usize, max_it: usize) -> (f64, f64, usize) {
    let nv = c.cx.nv
    let nf = c.nf
    var i = 0usize
    while i < nv {
        c.obeta[i] = beta[i]
        i += 1usize
    }
    var f = 0usize
    while f < c.nfx {
        var s = 0.0f64
        var j = 0usize
        while j < nf {
            var t = 0.0f64
            var l = c.flo[f]
            while l < c.fhi[f] {
                t += c.pen[j * nf + l]
                l += 1usize
            }
            s += t
            j += 1usize
        }
        c.psum[f] = s
        f += 1usize
    }
    var ll1 = 0.0f64
    var newlik = 0.0f64
    var iter = 0usize
    var done = false
    while !done && iter <= max_it {
        var q = 0.0f64
        var j = 0usize
        while j < nf {
            var t = 0.0f64
            var l = 0usize
            while l < nf {
                t += c.pen[j * nf + l] * beta[l]
                l += 1usize
            }
            c.pb[j] = t
            q += t * beta[j]
            j += 1usize
        }
        let pl = 0.0f64 - q / 2.0f64
        newlik = cxm_eval(&c.cx, beta, pl)
        j = 0usize
        while j < nf {
            c.cx.u[j] -= c.pb[j]
            var l = 0usize
            while l <= j {
                if j < c.ns && l < j {
                    c.cx.im[j * nv + l] = 0.0f64
                } else {
                    c.cx.im[j * nv + l] += c.pen[j * nf + l]
                }
                l += 1usize
            }
            j += 1usize
        }
        var cont = false
        if iter > 0usize && newlik < ll1 && math.abs[f64](1.0f64 - ll1 / newlik) > c.eps {
            i = 0usize
            while i < nv {
                beta[i] = (c.obeta[i] + beta[i]) / 2.0f64
                i += 1usize
            }
            cont = true
        }
        if !cont {
            let _rk = cxm_gchol4(c.cx.im, nv, c.tolch)
            if iter >= min_it && math.abs[f64](1.0f64 - ll1 / newlik) <= c.eps {
                done = true
            } else {
                ll1 = newlik
                if iter < max_it {
                    cxm_chsolve(c.cx.im, nv, c.cx.u)
                    i = 0usize
                    while i < nv {
                        c.obeta[i] = beta[i]
                        beta[i] += c.cx.u[i]
                        i += 1usize
                    }
                    f = 0usize
                    while f < c.nfx {
                        j = 0usize
                        while j < nf {
                            c.bw[j] = 0.0f64
                            if j >= c.flo[f] && j < c.fhi[f] { c.bw[j] = beta[j] }
                            j += 1usize
                        }
                        var s = 0.0f64
                        j = 0usize
                        while j < nf {
                            var t = 0.0f64
                            var l = 0usize
                            while l < nf {
                                t += c.pen[j * nf + l] * c.bw[l]
                                l += 1usize
                            }
                            s += t
                            j += 1usize
                        }
                        s = s / c.psum[f]
                        j = c.flo[f]
                        while j < c.fhi[f] {
                            beta[j] -= s
                            j += 1usize
                        }
                        f += 1usize
                    }
                }
            }
        }
        if !done { iter += 1usize }
    }
    var hd = 0.0f64
    i = 0usize
    while i < nf {
        hd += math.log[f64](c.cx.im[i * nv + i])
        i += 1usize
    }
    ret (newlik, hd, iter)
}

// the variance matrix of every random term, assembled from exp(theta); kmat is nf by nf, symmetric
fn cxm_kbuild(c: *MeCtx, th: []const f64) {
    let nf = c.nf
    var i = 0usize
    while i < nf * nf {
        c.kmat[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < c.ntheta {
        var v = th[i]
        if v > 36.0f64 { v = 36.0f64 }
        if v < -36.0f64 { v = -36.0f64 }
        c.thv[i] = math.exp[f64](v)
        i += 1usize
    }
    var t = 0usize
    while t < c.nterm {
        let m = c.t_m[t]
        let th0 = c.t_th0[t]
        if c.t_nvar[t] == 0usize {
            var g = 0usize
            while g < c.t_ng[t] {
                var u = c.clo[c.t_c0[t] + g]
                while u < c.chi[c.t_c0[t] + g] {
                    c.kmat[(c.t_i0[t] + u) * nf + c.t_i0[t] + u] = c.thv[th0 + g]
                    u += 1usize
                }
                g += 1usize
            }
        } else if c.t_icpt[t] == 1usize {
            let iv = c.thv[th0]
            let cr = c.thv[th0 + 1usize]
            let xv = c.thv[th0 + 2usize]
            let rho = (cr - 1.0f64) / (cr + 1.0f64)
            let cov = rho * math.sqrt[f64](xv * iv)
            var u = 0usize
            while u < m {
                let ri = c.t_i0[t] + u
                let rs = c.t_s0[t] + u
                c.kmat[ri * nf + ri] = iv
                c.kmat[rs * nf + rs] = xv
                c.kmat[ri * nf + rs] = cov
                c.kmat[rs * nf + ri] = cov
                u += 1usize
            }
        } else {
            var u = 0usize
            while u < m {
                let rs = c.t_s0[t] + u
                c.kmat[rs * nf + rs] = c.thv[th0]
                u += 1usize
            }
        }
        t += 1usize
    }
}

// -(1 + integrated log likelihood - loglik0) at theta, optim's objective (coxme.fit's logfun)
fn cxm_logfun(c: *MeCtx, th: []const f64) -> f64 {
    let nf = c.nf
    let nv = c.cx.nv
    cxm_kbuild(c, th)
    var i = 0usize
    while i < nf * nf {
        c.gk[i] = c.kmat[i]
        i += 1usize
    }
    let _r = cxm_gchol4(c.gk, nf, 1.0e-9f64)
    var sl = 0.0f64
    i = 0usize
    while i < nf {
        sl += math.log[f64](c.gk[i * nf + i])
        i += 1usize
    }
    cxm_chinv(c.gk, nf)
    i = 0usize
    while i < nf {
        if c.gk[i * nf + i] <= 0.0f64 { ret 0.0f64 }
        i += 1usize
    }
    i = 0usize
    while i < nf * nf {
        c.pen[i] = c.gk[i]
        i += 1usize
    }
    i = 0usize
    while i < nv {
        c.fb[i] = c.start[i]
        i += 1usize
    }
    let (pl, hd, _it) = cxm_newton(c, c.fb, c.inner, c.inner)
    let ilik = pl - 0.5f64 * (sl + hd)
    ret 0.0f64 - (1.0f64 + ilik - c.ll0)
}

fn cxm_f(c: *MeCtx, th: []const f64) -> f64 {
    c.count += 1usize
    ret cxm_logfun(c, th)
}

// optim's numerical gradient: central differences, ndeps 1e-3
fn cxm_g(c: *MeCtx, th: []const f64, out: []f64) {
    let n = th.len
    var i = 0usize
    while i < n {
        c.gx[i] = th[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        let v0 = th[i]
        c.gx[i] = v0 + 0.001f64
        let v1 = cxm_logfun(c, c.gx)
        c.gx[i] = v0 - 0.001f64
        let v2 = cxm_logfun(c, c.gx)
        out[i] = (v1 - v2) / (2.0f64 * 0.001f64)
        c.gx[i] = v0
        i += 1usize
    }
}

// The fit. codes of a term: column k holds the level codes (0-based, every level used) of the k-th expanded nesting factor,
// outermost first (g1, then g1/g2, ...); a slope term has one column. status is 0 or 1; strata are 0-based codes.
fn coxme_fit(a: *mem.Arena, time: []const f64, status: []const f64, strata: []const usize, weights: []const f64, offset: []const f64, x: []const f64, n: usize, p: usize, efron: bool, terms: []const CoxmeTerm) -> (CoxmeFit, err) {
    var fit: CoxmeFit = zero
    let nterm = terms.len
    // ---- layout of the random terms
    var tcols = 0usize
    var t = 0usize
    while t < nterm {
        tcols += terms[t].ng
        t += 1usize
    }
    let (t_ng, q1) = cxm_au(a, nterm)
    let (t_icpt, q2) = cxm_au(a, nterm)
    let (t_nvar, q3) = cxm_au(a, nterm)
    let (t_th0, q4) = cxm_au(a, nterm)
    let (t_nth, q5) = cxm_au(a, nterm)
    let (t_i0, q6) = cxm_au(a, nterm)
    let (t_m, q7) = cxm_au(a, nterm)
    let (t_s0, q8) = cxm_au(a, nterm)
    let (t_c0, q9) = cxm_au(a, nterm)
    let (clo, q10) = cxm_au(a, tcols)
    let (chi, q11) = cxm_au(a, tcols)
    let (nlev, q12) = cxm_au(a, tcols)
    let (pbase, q13) = cxm_au(a, tcols)
    let (flo, q14) = cxm_au(a, tcols)
    let (fhi, q15) = cxm_au(a, tcols)
    if q1 != ok || q2 != ok || q3 != ok || q4 != ok || q5 != ok || q6 != ok || q7 != ok || q8 != ok { ret (fit, CoxmeUnsupported) }
    if q9 != ok || q10 != ok || q11 != ok || q12 != ok || q13 != ok || q14 != ok || q15 != ok { ret (fit, CoxmeUnsupported) }
    var plen = 0usize
    t = 0usize
    var cc = 0usize
    while t < nterm {
        let ng = terms[t].ng
        t_ng[t] = ng
        t_nvar[t] = terms[t].nvar
        t_icpt[t] = 0usize
        if terms[t].icpt { t_icpt[t] = 1usize }
        t_c0[t] = cc
        var g = 0usize
        var cofs = 0usize
        while g < ng {
            // the column of expanded codes for nesting level g, innermost first
            let col = ng - 1usize - g
            var mx = 0usize
            var i = 0usize
            while i < n {
                if terms[t].codes[col * n + i] + 1usize > mx { mx = terms[t].codes[col * n + i] + 1usize }
                i += 1usize
            }
            nlev[cc + g] = mx
            clo[cc + g] = cofs
            chi[cc + g] = cofs + mx
            pbase[cc + g] = plen
            plen += mx
            cofs += mx
            g += 1usize
        }
        t_m[t] = cofs
        cc += ng
        t += 1usize
    }
    let (perm, q16) = cxm_au(a, plen)
    let (cnt, q17) = cxm_au(a, plen)
    if q16 != ok || q17 != ok { ret (fit, CoxmeUnsupported) }
    // sparse reordering (coxmeFull$initialize): levels holding at most 2% of the rows go first, in their order
    var ns = 0usize
    t = 0usize
    while t < nterm {
        let ng = terms[t].ng
        let c0 = t_c0[t]
        let col0 = ng - 1usize
        var i = 0usize
        while i < n {
            cnt[pbase[c0] + terms[t].codes[col0 * n + i]] += 1usize
            i += 1usize
        }
        let nl = nlev[c0]
        var big = nl >= 50usize
        if ng > 1usize { big = nl > 50usize }
        var anysp = false
        var l = 0usize
        while l < nl {
            if f64(cnt[pbase[c0] + l]) / f64(n) <= 0.02f64 { anysp = true }
            l += 1usize
        }
        var nsp = 0usize
        if big && anysp {
            l = 0usize
            while l < nl {
                if f64(cnt[pbase[c0] + l]) / f64(n) <= 0.02f64 {
                    perm[pbase[c0] + l] = nsp
                    nsp += 1usize
                }
                l += 1usize
            }
            var nx = nsp
            l = 0usize
            while l < nl {
                if !(f64(cnt[pbase[c0] + l]) / f64(n) <= 0.02f64) {
                    perm[pbase[c0] + l] = nx
                    nx += 1usize
                }
                l += 1usize
            }
        } else {
            l = 0usize
            while l < nl {
                perm[pbase[c0] + l] = l
                l += 1usize
            }
        }
        var g = 1usize
        while g < ng {
            l = 0usize
            while l < nlev[c0 + g] {
                perm[pbase[c0 + g] + l] = l
                l += 1usize
            }
            g += 1usize
        }
        if t == 0usize && terms[t].icpt { ns = nsp }
        if nsp > 0usize && terms[t].nvar > 0usize { ret (fit, CoxmeUnsupported) }
        t += 1usize
    }
    // coefficient bases: every intercept block, then every slope block
    var nfac = 0usize
    var nfx = 0usize
    t = 0usize
    while t < nterm {
        t_i0[t] = nfac
        if terms[t].icpt {
            nfac += t_m[t]
            nfx += terms[t].ng
        }
        t += 1usize
    }
    var nf = nfac
    var nzmax = p
    t = 0usize
    while t < nterm {
        t_s0[t] = nf
        nf += terms[t].nvar * t_m[t]
        nzmax += terms[t].nvar
        t += 1usize
    }
    nzmax += nfx
    // fx columns (intercept maps) for the recentring
    var fc = 0usize
    t = 0usize
    while t < nterm {
        if terms[t].icpt {
            var g = 0usize
            while g < terms[t].ng {
                flo[fc] = t_i0[t] + clo[t_c0[t] + g]
                fhi[fc] = t_i0[t] + chi[t_c0[t] + g]
                fc += 1usize
                g += 1usize
            }
        }
        t += 1usize
    }
    let nv = nf + p
    // ---- data in coxme's order
    let (ord, qo) = cxm_order(a, n, strata, time, status, 0usize)
    if qo != ok { ret (fit, qo) }
    let (cx, qc) = cxm_ctx(a, n, nv, nzmax, efron)
    if qc != ok { ret (fit, qc) }
    var cxm = cx
    let (xs, qx) = cxm_af(a, n * p)
    let (means, qm) = cxm_af(a, p)
    let (scale, qs) = cxm_af(a, p)
    if qx != ok || qm != ok || qs != ok { ret (fit, CoxmeUnsupported) }
    var k = 0usize
    while k < p {
        var sm = 0.0f64
        var i = 0usize
        while i < n {
            sm += x[k * n + ord[i]]
            i += 1usize
        }
        sm = sm / f64(n)
        means[k] = sm
        var sa = 0.0f64
        i = 0usize
        while i < n {
            let v = x[k * n + ord[i]] - sm
            xs[k * n + i] = v
            sa += math.abs[f64](v)
            i += 1usize
        }
        sa = sa / f64(n)
        scale[k] = sa
        if !(sa > 0.0f64) { ret (fit, CoxmeUnsupported) }
        i = 0usize
        while i < n {
            xs[k * n + i] = xs[k * n + i] / sa
            i += 1usize
        }
        k += 1usize
    }
    var i = 0usize
    while i < n {
        let o = ord[i]
        cxm.off[i] = offset[o]
        cxm.w[i] = weights[o]
        cxm.st[i] = status[o]
        cxm.sfirst[i] = 0usize
        if i == 0usize || strata[o] != strata[ord[i - 1usize]] { cxm.sfirst[i] = 1usize }
        var kk = cxm.rp[i]
        t = 0usize
        while t < nterm {
            if terms[t].icpt {
                var g = 0usize
                while g < terms[t].ng {
                    let col = terms[t].ng - 1usize - g
                    let code = terms[t].codes[col * n + o]
                    cxm.ci[kk] = t_i0[t] + clo[t_c0[t] + g] + perm[pbase[t_c0[t] + g] + code]
                    cxm.cv[kk] = 1.0f64
                    kk += 1usize
                    g += 1usize
                }
            }
            t += 1usize
        }
        t = 0usize
        while t < nterm {
            var j = 0usize
            while j < terms[t].nvar {
                let code = terms[t].codes[o]
                cxm.ci[kk] = t_s0[t] + j * t_m[t] + perm[pbase[t_c0[t]] + code]
                cxm.cv[kk] = terms[t].xs[j * n + o]
                kk += 1usize
                j += 1usize
            }
            t += 1usize
        }
        k = 0usize
        while k < p {
            cxm.ci[kk] = nf + k
            cxm.cv[kk] = xs[k * n + i]
            kk += 1usize
            k += 1usize
        }
        cxm.rp[i + 1usize] = kk
        i += 1usize
    }
    // ties: mark the last row of each time group, with the average death weight
    var ndead = 0usize
    var tw = 0.0f64
    i = 0usize
    while i < n {
        cxm.mark[i] = 0usize
        cxm.wtave[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let o = ord[i]
        if status[o] == 1.0f64 {
            ndead += 1usize
            tw += weights[o]
        }
        var endgrp = i + 1usize == n
        if !endgrp {
            let o2 = ord[i + 1usize]
            endgrp = strata[o2] != strata[o] || time[o2] != time[o]
        }
        if endgrp {
            cxm.mark[i] = ndead
            if ndead > 0usize { cxm.wtave[i] = tw / f64(ndead) }
            ndead = 0usize
            tw = 0.0f64
        }
        i += 1usize
    }
    // ---- the starting fit: survival's coxph.fit
    let (c0r, q0) = cxm_ctx(a, n, p, p, efron)
    if q0 != ok { ret (fit, q0) }
    var c0 = c0r
    let (ord2, qo2) = cxm_order(a, n, strata, time, status, 1usize)
    if qo2 != ok { ret (fit, qo2) }
    let (sc0, qa1) = cxm_af(a, p)
    let (cf0, qa2) = cxm_af(a, p)
    let (nb0, qa3) = cxm_af(a, p)
    let (wk0, qa4) = cxm_af(a, 2usize * p)
    let (x0, qa5) = cxm_af(a, n * p)
    if qa1 != ok || qa2 != ok || qa3 != ok || qa4 != ok || qa5 != ok { ret (fit, CoxmeUnsupported) }
    var sw = 0.0f64
    i = 0usize
    while i < n {
        sw += weights[ord2[i]]
        i += 1usize
    }
    k = 0usize
    while k < p {
        var sm = 0.0f64
        i = 0usize
        while i < n {
            sm += weights[ord2[i]] * x[k * n + ord2[i]]
            i += 1usize
        }
        sm = sm / sw
        var sa = 0.0f64
        i = 0usize
        while i < n {
            let v = x[k * n + ord2[i]] - sm
            sa += weights[ord2[i]] * math.abs[f64](v)
            i += 1usize
        }
        var sf = 1.0f64
        if sa > 0.0f64 { sf = sw / sa }
        sc0[k] = sf
        i = 0usize
        while i < n {
            x0[k * n + ord2[i]] = (x[k * n + ord2[i]] - sm) * sf
            i += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < n {
        let o = ord[i]
        c0.off[i] = cxm.off[i]
        c0.w[i] = cxm.w[i]
        c0.st[i] = cxm.st[i]
        c0.sfirst[i] = cxm.sfirst[i]
        c0.mark[i] = cxm.mark[i]
        c0.wtave[i] = cxm.wtave[i]
        c0.rp[i] = i * p
        k = 0usize
        while k < p {
            c0.ci[i * p + k] = k
            c0.cv[i * p + k] = x0[k * n + o]
            k += 1usize
        }
        c0.rp[i + 1usize] = (i + 1usize) * p
        i += 1usize
    }
    let toler0 = math.pow[f64](2.220446049250313e-16f64, 0.75f64)
    let (ll_init, ll_fit0, it0) = cxm_cox0(&c0, p, 20usize, 1.0e-9f64, toler0, cf0, nb0, wk0)
    var inner = 4usize
    if p > 0usize && it0 + 1usize > 4usize { inner = it0 + 1usize }
    k = 0usize
    while k < p {
        cf0[k] = cf0[k] * sc0[k]
        k += 1usize
    }
    // ---- theta: the candidate starts, per parameter
    var ntheta = 0usize
    t = 0usize
    while t < nterm {
        t_th0[t] = ntheta
        if terms[t].nvar == 0usize {
            t_nth[t] = terms[t].ng
        } else if terms[t].icpt {
            t_nth[t] = 3usize
        } else {
            t_nth[t] = 1usize
        }
        ntheta += t_nth[t]
        t += 1usize
    }
    let (cand, qd1) = cxm_af(a, ntheta * 4usize)
    let (clen, qd2) = cxm_au(a, ntheta)
    if qd1 != ok || qd2 != ok { ret (fit, CoxmeUnsupported) }
    t = 0usize
    while t < nterm {
        let th0 = t_th0[t]
        if terms[t].nvar == 0usize {
            var g = 0usize
            while g < terms[t].ng {
                cxm_varinit(cand[(th0 + g) * 4usize..(th0 + g) * 4usize + 4usize], 1.0f64)
                clen[th0 + g] = 4usize
                g += 1usize
            }
        } else {
            // the slope variable's variance
            var mu = 0.0f64
            i = 0usize
            while i < n {
                mu += terms[t].xs[i]
                i += 1usize
            }
            mu = mu / f64(n)
            var vs = 0.0f64
            i = 0usize
            while i < n {
                vs += (terms[t].xs[i] - mu) * (terms[t].xs[i] - mu)
                i += 1usize
            }
            vs = vs / f64(n - 1usize)
            var at = th0
            if terms[t].icpt {
                cxm_varinit(cand[at * 4usize..at * 4usize + 4usize], 1.0f64)
                clen[at] = 4usize
                at += 1usize
                cand[at * 4usize] = math.log[f64]((1.0f64 + 0.0f64) / (1.0f64 - 0.0f64))
                cand[at * 4usize + 1usize] = math.log[f64]((1.0f64 + 0.3f64) / (1.0f64 - 0.3f64))
                clen[at] = 2usize
                at += 1usize
            }
            cxm_varinit(cand[at * 4usize..at * 4usize + 4usize], vs)
            clen[at] = 4usize
        }
        t += 1usize
    }
    // ---- the model context
    var me: MeCtx = zero
    me.cx = cxm
    me.nf = nf
    me.nfac = nfac
    me.ns = ns
    me.nfx = nfx
    me.nterm = nterm
    me.ntheta = ntheta
    me.flo = flo
    me.fhi = fhi
    me.t_ng = t_ng
    me.t_icpt = t_icpt
    me.t_nvar = t_nvar
    me.t_th0 = t_th0
    me.t_nth = t_nth
    me.t_i0 = t_i0
    me.t_m = t_m
    me.t_s0 = t_s0
    me.t_c0 = t_c0
    me.clo = clo
    me.chi = chi
    let (psum, w1) = cxm_af(a, nfx)
    let (pen, w2) = cxm_af(a, nf * nf)
    let (obeta, w3) = cxm_af(a, nv)
    let (pb, w4) = cxm_af(a, nf)
    let (kmat, w5) = cxm_af(a, nf * nf)
    let (gk, w6) = cxm_af(a, nf * nf)
    let (thv, w7) = cxm_af(a, ntheta)
    let (gx, w8) = cxm_af(a, ntheta)
    let (start, w9) = cxm_af(a, nv)
    let (bw, w10) = cxm_af(a, nf)
    let (fb, w11) = cxm_af(a, nv)
    let (thb, w12) = cxm_af(a, ntheta)
    if w1 != ok || w2 != ok || w3 != ok || w4 != ok || w5 != ok || w6 != ok { ret (fit, CoxmeUnsupported) }
    if w7 != ok || w8 != ok || w9 != ok || w10 != ok || w11 != ok || w12 != ok { ret (fit, CoxmeUnsupported) }
    me.psum = psum
    me.pen = pen
    me.obeta = obeta
    me.pb = pb
    me.kmat = kmat
    me.gk = gk
    me.thv = thv
    me.gx = gx
    me.start = start
    me.bw = bw
    me.fb = fb
    me.ll0 = ll_fit0
    me.eps = 1.0e-8f64
    me.tolch = math.pow[f64](2.220446049250313e-16f64, 0.75f64)
    me.inner = inner
    k = 0usize
    while k < p {
        start[nf + k] = scale[k] * cf0[k] * 0.7f64
        k += 1usize
    }
    // best start over the grid of candidates (expand.grid order: the first parameter varies fastest)
    var total = 1usize
    k = 0usize
    while k < ntheta {
        total *= clen[k]
        k += 1usize
    }
    var best = 0.0f64
    var have = false
    var gi = 0usize
    while gi < total {
        var rem = gi
        k = 0usize
        while k < ntheta {
            thb[k] = cand[k * 4usize + rem % clen[k]]
            rem = rem / clen[k]
            k += 1usize
        }
        let lv = cxm_logfun(&me, thb)
        if cxm_fin(lv) && (!have || lv < best) {
            best = lv
            have = true
            k = 0usize
            while k < ntheta {
                gx[k] = thb[k]
                k += 1usize
            }
        }
        gi += 1usize
    }
    if !have { ret (fit, CoxmeUnsupported) }
    k = 0usize
    while k < ntheta {
        thb[k] = gx[k]
        k += 1usize
    }
    me.count = 0usize
    let _fmin = bf.vmmin[MeCtx](a, &me, cxm_f, cxm_g, thb, 1.0e-5f64, 100usize)
    let it_out = me.count
    // ---- the final fit at the estimated theta
    cxm_kbuild(&me, thb)
    k = 0usize
    while k < nf * nf {
        gk[k] = kmat[k]
        k += 1usize
    }
    let _rk = cxm_gchol4(gk, nf, 1.0e-9f64)
    var sl = 0.0f64
    k = 0usize
    while k < nf {
        sl += math.log[f64](gk[k * nf + k])
        k += 1usize
    }
    cxm_chinv(gk, nf)
    k = 0usize
    while k < nf * nf {
        pen[k] = gk[k]
        k += 1usize
    }
    k = 0usize
    while k < nv {
        fb[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < p {
        fb[nf + k] = cf0[k] * scale[k]
        k += 1usize
    }
    let (pl, hd, itf) = cxm_newton(&me, fb, 0usize, 20usize)
    let ilik = pl - 0.5f64 * (sl + hd)
    // the inverse of the factored information, sparse-by-sparse entries dropped as bdsmatrix keeps only blocks
    let (hv, qh) = cxm_af(a, nv * nv)
    if qh != ok { ret (fit, CoxmeUnsupported) }
    k = 0usize
    while k < nv * nv {
        hv[k] = me.cx.im[k]
        k += 1usize
    }
    cxm_chinv(hv, nv)
    var r = 0usize
    while r < nv {
        var s = 0usize
        while s < r {
            if r < ns { hv[r * nv + s] = 0.0f64 }
            hv[s * nv + r] = hv[r * nv + s]
            s += 1usize
        }
        r += 1usize
    }
    var tr = 0.0f64
    r = 0usize
    while r < nf {
        var s = 0usize
        while s < nf {
            tr += hv[r * nv + s] * pen[r * nf + s]
            s += 1usize
        }
        r += 1usize
    }
    var qpen = 0.0f64
    r = 0usize
    while r < nf {
        var s = 0usize
        var pr = 0.0f64
        while s < nf {
            pr += pen[r * nf + s] * fb[s]
            s += 1usize
        }
        qpen += fb[r] * pr
        r += 1usize
    }
    // ---- results
    let (fixef, r1) = cxm_af(a, p)
    let (frail, r2) = cxm_af(a, nf)
    let (thout, r3) = cxm_af(a, ntheta)
    let (vmat, r4) = cxm_af(a, nv * nv)
    var nvc = 0usize
    t = 0usize
    while t < nterm {
        nvc += t_nth[t]
        t += 1usize
    }
    let (vcoef, r5) = cxm_af(a, nvc)
    if r1 != ok || r2 != ok || r3 != ok || r4 != ok || r5 != ok { ret (fit, CoxmeUnsupported) }
    k = 0usize
    while k < p {
        fixef[k] = fb[nf + k] / scale[k]
        k += 1usize
    }
    k = 0usize
    while k < nf {
        frail[k] = fb[k]
        k += 1usize
    }
    k = 0usize
    while k < ntheta {
        thout[k] = thb[k]
        k += 1usize
    }
    r = 0usize
    while r < nv {
        var s = 0usize
        while s < nv {
            var d = 1.0f64
            if r >= nf { d = d * scale[r - nf] }
            if s >= nf { d = d * scale[s - nf] }
            vmat[r * nv + s] = hv[r * nv + s] / d
            s += 1usize
        }
        r += 1usize
    }
    var vi = 0usize
    t = 0usize
    while t < nterm {
        let th0 = t_th0[t]
        if terms[t].nvar == 0usize || !terms[t].icpt {
            var g = 0usize
            while g < t_nth[t] {
                vcoef[vi] = math.exp[f64](thb[th0 + g])
                vi += 1usize
                g += 1usize
            }
        } else {
            let cr = math.exp[f64](thb[th0 + 1usize])
            vcoef[vi] = math.exp[f64](thb[th0])
            vcoef[vi + 1usize] = (cr - 1.0f64) / (cr + 1.0f64)
            vcoef[vi + 2usize] = math.exp[f64](thb[th0 + 2usize])
            vi += 3usize
        }
        t += 1usize
    }
    fit.nfixed = p
    fit.nfrail = nf
    fit.ntheta = ntheta
    fit.nvc = nvc
    fit.fixef = fixef
    fit.frail = frail
    fit.theta = thout
    fit.vcoef = vcoef
    fit.vmat = vmat
    fit.ll_null = ll_init
    fit.ll_int = ilik
    fit.ll_pen = pl
    fit.penalty = qpen / 2.0f64
    fit.df_int = f64(p + ntheta)
    fit.df_pen = f64(p) + (f64(nf) - tr)
    fit.it_outer = it_out
    fit.it_inner = it_out * inner + itf
    ret (fit, ok)
}

// varinit = c(.02, .1, .4, .8)^2 over `den`
fn cxm_varinit(out: []f64, den: f64) {
    out[0usize] = math.log[f64](0.02f64 * 0.02f64 / den)
    out[1usize] = math.log[f64](0.1f64 * 0.1f64 / den)
    out[2usize] = math.log[f64](0.4f64 * 0.4f64 / den)
    out[3usize] = math.log[f64](0.8f64 * 0.8f64 / den)
}
