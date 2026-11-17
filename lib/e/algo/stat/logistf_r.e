// R logistf (Heinze, Ploner, Jiricka, Steiner), port of the package's C code and R code: Firth's penalized logistic regression with the
// package's own iteration (logistffit_revised and logistffit_IRLS), the profile penalized likelihood limits (logistplfit), the penalized
// likelihood ratio tests (logistftest, anova, add1, drop1, forward, backward), FLIC, FLAC, predict, profile, logistf.pdf and PVR.confint.
//
// A design matrix x is n by k, column-major (as R holds it), the intercept column included when the model has one. y is 0/1. weight and
// offset are n long, or empty for the defaults (ones, zeros). A term is a column here; the selection functions work on subsets of the
// columns of one full design matrix, indexed from 0. logistf.control(collapse) is replayed (fit_fit): a design of at most 10 distinct values is fitted as
// its distinct rows with their counts as weights, which changes the iterate the 1e-5 stopping rule lands on.
//
// Not here: the legacy fitters logistf.fit.old and logistpl.old (the legacy = TRUE paths of logistf.pdf, CLIP.confint and CLIP.profile) and plot.logistf.profile.

use e.math
use e.math.nmath as nm
use e.math.dist as dist
use e.mem

error Singular

// scratch: one block of f64 and one of usize taken in strict stack order; a function resets at to what it found
type Bump = struct { buf: []f64, at: usize, ibuf: []usize, iat: usize }

fn bump_new(a: *mem.Arena, cap: usize, icap: usize) -> (Bump, err) {
    let (f, e1) = mem.alloc[f64](a, cap)
    if e1 != ok { ret (zero, e1) }
    let (g, e2) = mem.alloc[usize](a, icap)
    if e2 != ok { ret (zero, e2) }
    ret (Bump { buf: f, at: 0usize, ibuf: g, iat: 0usize }, ok)
}

fn take(b: *Bump, n: usize) -> []f64 {
    let s = b.buf[b.at..b.at + n]
    var i = 0usize
    while i < n {
        s[i] = 0.0f64
        i += 1usize
    }
    b.at += n
    ret s
}

fn take_u(b: *Bump, n: usize) -> []usize {
    let s = b.ibuf[b.iat..b.iat + n]
    var i = 0usize
    while i < n {
        s[i] = 0usize
        i += 1usize
    }
    b.iat += n
    ret s
}

fn finite(v: f64) -> bool { ret v == v && v - v == 0.0f64 }

fn nan() -> f64 {
    let z = 0.0f64
    ret z / z
}

fn infinity() -> f64 {
    let z = 0.0f64
    ret 1.0f64 / z
}

fn sqrt_f(v: f64) -> f64 { ret math.sqrt[f64](v) }

// the controls of logistf.control, logistpl.control and logistf.mod.control (tau)
type Ctl = struct {
    maxit: usize, maxstep: f64, maxhs: usize, lconv: f64, gconv: f64, xconv: f64, irls: bool, collapse: bool, tau: f64,
    plmaxit: usize, plmaxstep: f64, plmaxhs: usize, pllconv: f64, plxconv: f64
}

fn ctl_default() -> Ctl {
    ret Ctl {
        maxit: 25usize, maxstep: 5.0f64, maxhs: 0usize, lconv: 1.0e-5f64, gconv: 1.0e-5f64, xconv: 1.0e-5f64, irls: false, collapse: true, tau: 0.5f64,
        plmaxit: 100usize, plmaxstep: 5.0f64, plmaxhs: 0usize, pllconv: 1.0e-5f64, plxconv: 1.0e-5f64
    }
}

fn maxabs(v: []const f64, n: usize) -> f64 {
    var r = math.abs[f64](v[0usize])
    var i = 1usize
    while i < n {
        let t = math.abs[f64](v[i])
        // fmax: a NaN loses
        if t > r || r != r { r = t }
        i += 1usize
    }
    ret r
}

fn maxabs_ind(v: []const f64, ind: []const usize, n: usize) -> f64 {
    var r = math.abs[f64](v[ind[0usize]])
    var i = 1usize
    while i < n {
        let t = math.abs[f64](v[ind[i]])
        if t > r || r != r { r = t }
        i += 1usize
    }
    ret r
}

// log determinant of the symmetric positive definite m by m a (column-major) from its Cholesky factor; the upper factor goes to u
fn chol_upper(a: []const f64, m: usize, u: []f64) -> err {
    var j = 0usize
    while j < m {
        var i = 0usize
        while i < m {
            u[i + j * m] = a[i + j * m]
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < m {
        var d = 0.0f64
        var l = 0usize
        while l < j {
            d += u[l + j * m] * u[l + j * m]
            l += 1usize
        }
        let ajj = u[j + j * m] - d
        if !(ajj > 0.0f64) { ret Singular }
        let r = sqrt_f(ajj)
        u[j + j * m] = r
        var i = j + 1usize
        while i < m {
            var s = 0.0f64
            l = 0usize
            while l < j {
                s += u[l + j * m] * u[l + i * m]
                l += 1usize
            }
            u[j + i * m] = (u[j + i * m] - s) / r
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// lapack_det: 2 * sum(log(diag(chol(a))))
fn pd_logdet(b: *Bump, a: []const f64, m: usize) -> (f64, err) {
    let mark = b.at
    let u = take(b, m * m)
    let e = chol_upper(a, m, u)
    if e != ok {
        b.at = mark
        ret (0.0f64, e)
    }
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += math.log[f64](u[i + i * m])
        i += 1usize
    }
    b.at = mark
    ret (2.0f64 * s, ok)
}

// lapack_inv: the inverse of the symmetric positive definite a, in place, both triangles filled
fn pd_inv(b: *Bump, a: []f64, m: usize) -> err {
    let mark = b.at
    let u = take(b, m * m)
    let w = take(b, m * m)
    let e = chol_upper(a, m, u)
    if e != ok {
        b.at = mark
        ret e
    }
    var c = 0usize
    while c < m {
        w[c + c * m] = 1.0f64 / u[c + c * m]
        var r = c
        while r > 0usize {
            r -= 1usize
            var s = 0.0f64
            var l = r + 1usize
            while l <= c {
                s += u[r + l * m] * w[l + c * m]
                l += 1usize
            }
            w[r + c * m] = (0.0f64 - s) / u[r + r * m]
        }
        c += 1usize
    }
    var i = 0usize
    while i < m {
        var j = i
        while j < m {
            var s = 0.0f64
            var l = j
            while l < m {
                s += w[i + l * m] * w[j + l * m]
                l += 1usize
            }
            a[i + j * m] = s
            a[j + i * m] = s
            j += 1usize
        }
        i += 1usize
    }
    b.at = mark
    ret ok
}

fn lf_pi(x: []const f64, n: usize, k: usize, beta: []const f64, offset: []const f64, pi: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += x[i + j * n] * beta[j]
            j += 1usize
        }
        pi[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - s - offset[i]))
        i += 1usize
    }
}

// X' W X for the weights w (the row weights, not their roots), the roots multiplied in first as the package does; m columns taken from x by
// col (or all k when col is empty)
fn lf_xwx(b: *Bump, x: []const f64, n: usize, k: usize, w: []const f64, col: []const usize, m: usize, out: []f64) {
    let mark = b.at
    let xs = take(b, n * m)
    var j = 0usize
    while j < m {
        var cj = j
        if col.len > 0usize { cj = col[j] }
        var i = 0usize
        while i < n {
            xs[i + j * n] = x[i + cj * n] * sqrt_f(w[i])
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < m {
        var l = j
        while l < m {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += xs[i + j * n] * xs[i + l * n]
                i += 1usize
            }
            out[j + l * m] = s
            out[l + j * m] = s
            l += 1usize
        }
        j += 1usize
    }
    b.at = mark
}

type St = struct { logdet: f64, loglik: f64, warn: bool }

// the state at beta: pi, the inverse information at the unaugmented weights (into fisher), the hat diagonal and the penalized log-likelihood;
// check turns a log determinant under -200 into an error. old is the value a non-finite probability falls back to
fn lf_state(b: *Bump, x: []const f64, y: []const f64, n: usize, k: usize, weight: []const f64, offset: []const f64, beta: []const f64, firth: bool, tau: f64, pi: []f64, fisher: []f64, hdiag: []f64, check: bool, old: f64) -> (St, err) {
    let mark = b.at
    lf_pi(x, n, k, beta, offset, pi)
    let wv = take(b, n)
    var i = 0usize
    while i < n {
        wv[i] = weight[i] * pi[i] * (1.0f64 - pi[i])
        i += 1usize
    }
    let none = take_u(b, 0usize)
    lf_xwx(b, x, n, k, wv, none, k, fisher)
    let (logdet, e1) = pd_logdet(b, fisher, k)
    if e1 != ok {
        b.at = mark
        ret (zero, e1)
    }
    if check && logdet < 0.0f64 - 200.0f64 {
        b.at = mark
        ret (zero, Singular)
    }
    let e2 = pd_inv(b, fisher, k)
    if e2 != ok {
        b.at = mark
        ret (zero, e2)
    }
    let xs = take(b, n * k)
    var j = 0usize
    while j < k {
        i = 0usize
        while i < n {
            xs[i + j * n] = x[i + j * n] * sqrt_f(wv[i])
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        var h = 0.0f64
        j = 0usize
        while j < k {
            var t = 0.0f64
            var l = 0usize
            while l < k {
                t += xs[i + l * n] * fisher[l + j * k]
                l += 1usize
            }
            h += t * xs[i + j * n]
            j += 1usize
        }
        hdiag[i] = h
        i += 1usize
    }
    var ll = 0.0f64
    var warn = false
    i = 0usize
    while i < n {
        if finite(math.log[f64](1.0f64 - pi[i])) && finite(math.log[f64](pi[i])) {
            ll += y[i] * weight[i] * math.log[f64](pi[i]) + (1.0f64 - y[i]) * weight[i] * math.log[f64](1.0f64 - pi[i])
        } else {
            warn = true
            ll = old
            break
        }
        i += 1usize
    }
    if firth { ll += tau * logdet }
    b.at = mark
    ret (St { logdet: logdet, loglik: ll, warn: warn }, ok)
}

// U* = X' w with w the penalized (or plain) residual; exact selects the correct weighted form, the package's first evaluation drops the weight on pi
fn lf_ustar(x: []const f64, y: []const f64, n: usize, k: usize, weight: []const f64, pi: []const f64, hdiag: []const f64, firth: bool, tau: f64, first: bool, w: []f64, ustar: []f64) {
    var i = 0usize
    while i < n {
        if firth {
            if first {
                w[i] = (weight[i] * y[i] - pi[i]) + 2.0f64 * tau * hdiag[i] * (0.5f64 - pi[i])
            } else {
                w[i] = (weight[i] * (y[i] - pi[i]) + 2.0f64 * tau * hdiag[i] * (0.5f64 - pi[i]))
            }
        } else {
            w[i] = weight[i] * (y[i] - pi[i])
        }
        i += 1usize
    }
    var j = 0usize
    while j < k {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += x[i + j * n] * w[i]
            i += 1usize
        }
        ustar[j] = s
        j += 1usize
    }
}

type Core = struct { iter: usize, evals: usize, loglik: f64, warn: bool, c0: f64, c1: f64, c2: f64 }

// logistffit_revised: colfit is 1-based as in R, a lone 0 meaning "evaluate only". beta is the start and the answer; var (k*k), ustar (k),
// pi and hdiag (n) are written
fn fit_nr(b: *Bump, x: []const f64, y: []const f64, n: usize, k: usize, weight: []const f64, offset: []const f64, beta: []f64, colfit: []const usize, firth: bool, c: Ctl, var_out: []f64, ustar: []f64, pi: []f64, hdiag: []f64) -> (Core, err) {
    let mark = b.at
    let imark = b.iat
    let nc = colfit.len
    let selcol = take_u(b, nc)
    var maxit = c.maxit
    var q = 0usize
    while q < nc {
        if colfit[q] > 0usize { selcol[q] = colfit[q] - 1usize }
        q += 1usize
    }
    var evaluate_only = false
    if colfit[0usize] == 0usize { evaluate_only = true }
    if evaluate_only { maxit = 0usize }
    let delta = take(b, k)
    let beta_old = take(b, k)
    let w = take(b, n)
    let cov_aug = take(b, k * k)
    let (s0, e0) = lf_state(b, x, y, n, k, weight, offset, beta, firth, c.tau, pi, var_out, hdiag, true, 0.0f64)
    if e0 != ok {
        b.at = mark
        b.iat = imark
        ret (zero, e0)
    }
    var core = Core { iter: 0usize, evals: 1usize, loglik: s0.loglik, warn: s0.warn, c0: 0.0f64, c1: 0.0f64, c2: 0.0f64 }
    var stop = s0.warn
    lf_ustar(x, y, n, k, weight, pi, hdiag, firth, c.tau, true, w, ustar)
    var loglik_change = 5.0f64
    if maxit > 0usize {
        while true {
            let loglik_old = core.loglik
            var i = 0usize
            while i < k {
                beta_old[i] = beta[i]
                i += 1usize
            }
            // the reduced information on the augmented weights
            let wa = take(b, n)
            i = 0usize
            while i < n {
                if firth {
                    wa[i] = (weight[i] + 2.0f64 * hdiag[i] * c.tau) * pi[i] * (1.0f64 - pi[i])
                } else {
                    wa[i] = weight[i] * pi[i] * (1.0f64 - pi[i])
                }
                i += 1usize
            }
            let fred = take(b, nc * nc)
            lf_xwx(b, x, n, k, wa, selcol, nc, fred)
            let e1 = pd_inv(b, fred, nc)
            if e1 != ok {
                b.at = mark
                b.iat = imark
                ret (zero, e1)
            }
            i = 0usize
            while i < k * k {
                cov_aug[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < nc {
                var j = 0usize
                while j < nc {
                    cov_aug[selcol[i] + k * selcol[j]] = fred[i + nc * j]
                    j += 1usize
                }
                i += 1usize
            }
            var j = 0usize
            while j < k {
                var s = 0.0f64
                var l = 0usize
                while l < k {
                    s += cov_aug[l + j * k] * ustar[l]
                    l += 1usize
                }
                delta[j] = s
                j += 1usize
            }
            if c.maxstep >= 0.0f64 {
                let mx = maxabs(delta, k) / c.maxstep
                if mx > 1.0f64 {
                    i = 0usize
                    while i < k {
                        delta[i] = delta[i] / mx
                        i += 1usize
                    }
                }
            }
            i = 0usize
            while i < k {
                beta[i] += delta[i]
                i += 1usize
            }
            var halfs = 1usize
            while halfs <= c.maxhs {
                let (st, e2) = lf_state(b, x, y, n, k, weight, offset, beta, firth, c.tau, pi, var_out, hdiag, false, loglik_old)
                if e2 != ok {
                    b.at = mark
                    b.iat = imark
                    ret (zero, e2)
                }
                core.loglik = st.loglik
                if st.warn {
                    core.warn = true
                    stop = true
                }
                core.evals += 1usize
                if core.loglik >= loglik_old - c.lconv { break }
                lf_ustar(x, y, n, k, weight, pi, hdiag, firth, c.tau, false, w, ustar)
                i = 0usize
                while i < k {
                    delta[i] = delta[i] / 2.0f64
                    beta[i] -= delta[i]
                    i += 1usize
                }
                halfs += 1usize
            }
            if c.maxhs == 0usize {
                let (st, e3) = lf_state(b, x, y, n, k, weight, offset, beta, firth, c.tau, pi, var_out, hdiag, true, loglik_old)
                if e3 != ok {
                    b.at = mark
                    b.iat = imark
                    ret (zero, e3)
                }
                core.loglik = st.loglik
                if st.warn {
                    core.warn = true
                    stop = true
                }
                core.evals += 1usize
                lf_ustar(x, y, n, k, weight, pi, hdiag, firth, c.tau, false, w, ustar)
            }
            loglik_change = core.loglik - loglik_old
            if core.iter >= maxit || (maxabs_ind(delta, selcol, nc) <= c.xconv && maxabs_ind(ustar, selcol, nc) < c.gconv && loglik_change < c.lconv) {
                stop = true
            }
            b.at = b.at - nc * nc - n
            if stop { break }
            core.iter += 1usize
        }
        i_copy(cov_aug, var_out, k * k)
        core.c0 = loglik_change
        core.c1 = maxabs_ind(ustar, selcol, nc)
        core.c2 = maxabs_ind(delta, selcol, nc)
    }
    b.at = mark
    b.iat = imark
    ret (core, ok)
}

fn i_copy(src: []const f64, dst: []f64, n: usize) {
    var i = 0usize
    while i < n {
        dst[i] = src[i]
        i += 1usize
    }
}

// logistffit_IRLS
fn fit_irls(b: *Bump, x: []const f64, y: []const f64, n: usize, k: usize, weight: []const f64, offset: []const f64, beta: []f64, colfit: []const usize, firth: bool, c: Ctl, var_out: []f64, pi: []f64, hdiag: []f64) -> (Core, err) {
    let mark = b.at
    let imark = b.iat
    let nc = colfit.len
    let selcol = take_u(b, nc)
    var q = 0usize
    while q < nc {
        if colfit[q] > 0usize { selcol[q] = colfit[q] - 1usize }
        q += 1usize
    }
    var maxit = c.maxit
    if colfit[0usize] == 0usize { maxit = 0usize }
    let beta_old = take(b, k)
    let delta = take(b, k)
    let nr = take(b, n)
    let (s0, e0) = lf_state(b, x, y, n, k, weight, offset, beta, firth, c.tau, pi, var_out, hdiag, true, 0.0f64)
    if e0 != ok {
        b.at = mark
        b.iat = imark
        ret (zero, e0)
    }
    var core = Core { iter: 0usize, evals: 1usize, loglik: s0.loglik, warn: s0.warn, c0: 0.0f64, c1: 0.0f64, c2: 0.0f64 }
    var stop = s0.warn
    var loglik_change = 5.0f64
    let fred = take(b, nc * nc)
    if maxit > 0usize && !stop {
        while true {
            let loglik_old = core.loglik
            var i = 0usize
            while i < k {
                beta_old[i] = beta[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                var s = 0.0f64
                var j = 0usize
                while j < k {
                    s += x[i + j * n] * beta_old[j]
                    j += 1usize
                }
                nr[i] = s
                i += 1usize
            }
            let wa = take(b, n)
            i = 0usize
            while i < n {
                let wi = pi[i] * (1.0f64 - pi[i]) * (weight[i] + 2.0f64 * c.tau * hdiag[i])
                if firth {
                    nr[i] += 1.0f64 / wi * (weight[i] * (y[i] - pi[i]) + 2.0f64 * c.tau * hdiag[i] * (0.5f64 - pi[i]))
                    wa[i] = wi
                } else {
                    nr[i] += 1.0f64 / wi * weight[i] * (y[i] - pi[i])
                    wa[i] = pi[i] * (1.0f64 - pi[i])
                }
                i += 1usize
            }
            lf_xwx(b, x, n, k, wa, selcol, nc, fred)
            let (ld, e1) = pd_logdet(b, fred, nc)
            if e1 != ok {
                b.at = mark
                b.iat = imark
                ret (zero, e1)
            }
            if ld < 0.0f64 - 200.0f64 {
                b.at = mark
                b.iat = imark
                ret (zero, Singular)
            }
            let e2 = pd_inv(b, fred, nc)
            if e2 != ok {
                b.at = mark
                b.iat = imark
                ret (zero, e2)
            }
            // beta = (X'WX)^-1 X'W z with W the row weights multiplied into X
            let xr = take(b, n * nc)
            i = 0usize
            while i < n {
                var j = 0usize
                while j < nc {
                    xr[j + i * nc] = x[i + selcol[j] * n] * wa[i]
                    j += 1usize
                }
                i += 1usize
            }
            let t1 = take(b, nc * n)
            var j = 0usize
            while j < nc {
                i = 0usize
                while i < n {
                    var s = 0.0f64
                    var l = 0usize
                    while l < nc {
                        s += fred[j + l * nc] * xr[l + i * nc]
                        l += 1usize
                    }
                    t1[j + i * nc] = s
                    i += 1usize
                }
                j += 1usize
            }
            j = 0usize
            while j < nc {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += t1[j + i * nc] * nr[i]
                    i += 1usize
                }
                beta[selcol[j]] = s
                j += 1usize
            }
            let (st, e3) = lf_state(b, x, y, n, k, weight, offset, beta, firth, c.tau, pi, var_out, hdiag, true, loglik_old)
            if e3 != ok {
                b.at = mark
                b.iat = imark
                ret (zero, e3)
            }
            core.loglik = st.loglik
            if st.warn {
                core.warn = true
                stop = true
            }
            core.evals += 1usize
            loglik_change = core.loglik - loglik_old
            i = 0usize
            while i < k {
                delta[i] = beta[i] - beta_old[i]
                i += 1usize
            }
            core.iter += 1usize
            if core.iter >= maxit || (maxabs_ind(delta, selcol, nc) <= c.xconv && loglik_change < c.lconv) { stop = true }
            b.at = b.at - n - n * nc - nc * n
            if stop { break }
        }
    }
    var cv = take(b, k * k)
    if maxit > 0usize {
        var i = 0usize
        while i < nc {
            var j = 0usize
            while j < nc {
                cv[selcol[i] + k * selcol[j]] = fred[i + nc * j]
                j += 1usize
            }
            i += 1usize
        }
        i_copy(cv, var_out, k * k)
        core.c0 = loglik_change
        core.c2 = maxabs_ind(delta, selcol, nc)
    }
    b.at = mark
    b.iat = imark
    ret (core, ok)
}

// logistf.fit: dispatches on the control's fit; the result lands in the arrays given
fn fit_dispatch(b: *Bump, x: []const f64, y: []const f64, n: usize, k: usize, weight: []const f64, offset: []const f64, beta: []f64, colfit: []const usize, firth: bool, c: Ctl, var_out: []f64, ustar: []f64, pi: []f64, hdiag: []f64) -> (Core, err) {
    if c.irls {
        let (r1, e1) = fit_irls(b, x, y, n, k, weight, offset, beta, colfit, firth, c, var_out, pi, hdiag)
        ret (r1, e1)
    }
    let (r2, e2) = fit_nr(b, x, y, n, k, weight, offset, beta, colfit, firth, c, var_out, ustar, pi, hdiag)
    ret (r2, e2)
}

// logistf.fit: with collapse on and unit weights, a design whose x columns and y hold at most 10 distinct values is fitted as its distinct rows
// (x, y, offset) weighted by their counts, and pi and the hat diagonal are put back per row. The weighted path is not the unweighted one (the
// package's first score drops the weight on pi), so the 1e-5 convergence stops at a different iterate
fn fit_fit(b: *Bump, x: []const f64, y: []const f64, n: usize, k: usize, weight: []const f64, offset: []const f64, beta: []f64, colfit: []const usize, firth: bool, c: Ctl, var_out: []f64, ustar: []f64, pi: []f64, hdiag: []f64) -> (Core, err) {
    var collapse = c.collapse
    var i = 0usize
    while i < n && collapse {
        if weight[i] != 1.0f64 { collapse = false }
        i += 1usize
    }
    if collapse {
        // the distinct values of x and y together
        let mark0 = b.at
        let vals = take(b, 12usize)
        var nv = 0usize
        var j = 0usize
        while j <= k && collapse {
            i = 0usize
            while i < n && collapse {
                var v = y[i]
                if j < k { v = x[i + j * n] }
                var seen = false
                var q = 0usize
                while q < nv {
                    if vals[q] == v { seen = true }
                    q += 1usize
                }
                if !seen {
                    if nv >= 10usize {
                        collapse = false
                    } else {
                        vals[nv] = v
                        nv += 1usize
                    }
                }
                i += 1usize
            }
            j += 1usize
        }
        b.at = mark0
    }
    if !collapse {
        let (r0, e0) = fit_dispatch(b, x, y, n, k, weight, offset, beta, colfit, firth, c, var_out, ustar, pi, hdiag)
        ret (r0, e0)
    }
    let mark = b.at
    let imark = b.iat
    let grp = take_u(b, n)
    var ng = 0usize
    i = 0usize
    while i < n {
        var found = false
        var g = 0usize
        while g < ng && !found {
            var same = y[i] == y[grp[g]] && offset[i] == offset[grp[g]]
            var j = 0usize
            while j < k && same {
                if x[i + j * n] != x[grp[g] + j * n] { same = false }
                j += 1usize
            }
            if same { found = true } else { g += 1usize }
        }
        if !found {
            grp[ng] = i
            g = ng
            ng += 1usize
        }
        i += 1usize
    }
    // grp[g] is the first row of group g; idx[i] the group of row i
    let idx = take_u(b, n)
    i = 0usize
    while i < n {
        var g = 0usize
        var found = false
        while g < ng && !found {
            var same = y[i] == y[grp[g]] && offset[i] == offset[grp[g]]
            var j = 0usize
            while j < k && same {
                if x[i + j * n] != x[grp[g] + j * n] { same = false }
                j += 1usize
            }
            if same { found = true } else { g += 1usize }
        }
        idx[i] = g
        i += 1usize
    }
    let xc = take(b, ng * k)
    let yc = take(b, ng)
    let oc = take(b, ng)
    let wc = take(b, ng)
    let pic = take(b, ng)
    let hc = take(b, ng)
    var g2 = 0usize
    while g2 < ng {
        yc[g2] = y[grp[g2]]
        oc[g2] = offset[grp[g2]]
        var j = 0usize
        while j < k {
            xc[g2 + j * ng] = x[grp[g2] + j * n]
            j += 1usize
        }
        g2 += 1usize
    }
    i = 0usize
    while i < n {
        wc[idx[i]] += 1.0f64
        i += 1usize
    }
    let (r1, e1) = fit_dispatch(b, xc, yc, ng, k, wc, oc, beta, colfit, firth, c, var_out, ustar, pic, hc)
    if e1 != ok {
        b.at = mark
        b.iat = imark
        ret (zero, e1)
    }
    i = 0usize
    while i < n {
        pi[i] = pic[idx[i]]
        hdiag[i] = hc[idx[i]] / wc[idx[i]]
        i += 1usize
    }
    b.at = mark
    b.iat = imark
    ret (r1, ok)
}

type Pl = struct { beta: f64, loglik: f64, iter: usize, warn: bool, c0: f64, c1: f64 }

// logistplfit: the profile penalized likelihood limit of coefficient i (0-based) on the side which (-1 lower, 1 upper), from init; the iterate
// of each step goes to hist (plmaxit by k, column-major, filled for iter steps)
fn logistpl(b: *Bump, x: []const f64, y: []const f64, n: usize, k: usize, weight: []const f64, offset: []const f64, init: []const f64, isel: usize, ll0: f64, firth: bool, side: f64, c: Ctl, hist: []f64) -> (Pl, err) {
    let mark = b.at
    let beta = take(b, k)
    i_copy(init, beta, k)
    let pi = take(b, n)
    let hdiag = take(b, n)
    let fisher = take(b, k * k)
    let fa = take(b, k * k)
    let ustar = take(b, k)
    let delta = take(b, k)
    let w = take(b, n)
    let wa = take(b, n)
    let tau = c.tau
    var warn = false
    let (s0, e0) = lf_state(b, x, y, n, k, weight, offset, beta, firth, tau, pi, fisher, hdiag, true, 0.0f64)
    if e0 != ok {
        b.at = mark
        ret (zero, e0)
    }
    var loglik = s0.loglik
    if s0.warn { warn = true }
    var i = 0usize
    while i < n {
        if firth {
            wa[i] = pi[i] * (1.0f64 - pi[i]) * (weight[i] + 2.0f64 * tau * hdiag[i])
        } else {
            wa[i] = weight[i] * pi[i] * (1.0f64 - pi[i])
        }
        i += 1usize
    }
    let none = take_u(b, 0usize)
    lf_xwx(b, x, n, k, wa, none, k, fa)
    let (ld0, e1) = pd_logdet(b, fa, k)
    if e1 != ok {
        b.at = mark
        ret (zero, e1)
    }
    if ld0 < 0.0f64 - 200.0f64 {
        b.at = mark
        ret (zero, Singular)
    }
    let e2 = pd_inv(b, fa, k)
    if e2 != ok {
        b.at = mark
        ret (zero, e2)
    }
    var iter = 0usize
    var stop = false
    var delta_max = 0.0f64
    while true {
        lf_ustar(x, y, n, k, weight, pi, hdiag, firth, tau, false, w, ustar)
        // U*' V U*, V the inverse augmented information
        var quad = 0.0f64
        var j = 0usize
        while j < k {
            var s = 0.0f64
            i = 0usize
            while i < k {
                s += ustar[i] * (0.0f64 - fa[i + j * k])
                i += 1usize
            }
            quad += s * ustar[j]
            j += 1usize
        }
        let under = (0.0f64 - 2.0f64) * ((ll0 - loglik) + 0.5f64 * quad) / fa[k * isel + isel]
        var lambda = 0.0f64
        if !(under < 0.0f64) { lambda = side * sqrt_f(under) }
        ustar[isel] += lambda
        j = 0usize
        while j < k {
            var s = 0.0f64
            i = 0usize
            while i < k {
                s += fa[i + j * k] * ustar[i]
                i += 1usize
            }
            delta[j] = s
            j += 1usize
        }
        if c.plmaxstep >= 0.0f64 {
            let mx = maxabs(delta, k) / c.plmaxstep
            if mx > 1.0f64 {
                i = 0usize
                while i < k {
                    delta[i] = delta[i] / mx
                    i += 1usize
                }
            }
        }
        i = 0usize
        while i < k {
            beta[i] += delta[i]
            i += 1usize
        }
        let loglik_old = loglik
        var halfs = 0usize
        while true {
            let (st, e3) = lf_state(b, x, y, n, k, weight, offset, beta, firth, tau, pi, fisher, hdiag, true, loglik_old)
            if e3 != ok {
                b.at = mark
                ret (zero, e3)
            }
            loglik = st.loglik
            if st.warn {
                warn = true
                stop = true
            }
            if stop { break }
            i = 0usize
            while i < n {
                if firth {
                    wa[i] = pi[i] * (1.0f64 - pi[i]) * (weight[i] + 2.0f64 * tau * hdiag[i])
                } else {
                    wa[i] = weight[i] * pi[i] * (1.0f64 - pi[i])
                }
                i += 1usize
            }
            lf_xwx(b, x, n, k, wa, none, k, fa)
            let (ld1, e4) = pd_logdet(b, fa, k)
            if e4 != ok {
                b.at = mark
                ret (zero, e4)
            }
            if ld1 < 0.0f64 - 200.0f64 {
                b.at = mark
                ret (zero, Singular)
            }
            let e5 = pd_inv(b, fa, k)
            if e5 != ok {
                b.at = mark
                ret (zero, e5)
            }
            halfs += 1usize
            if halfs >= c.plmaxhs || (math.abs[f64](loglik - ll0) < math.abs[f64](loglik_old - ll0) && loglik > ll0) { break }
            i = 0usize
            while i < k {
                delta[i] = delta[i] / 2.0f64
                beta[i] -= delta[i]
                i += 1usize
            }
        }
        iter += 1usize
        i = 0usize
        while i < k {
            hist[i * c.plmaxit + iter - 1usize] = beta[i]
            i += 1usize
        }
        delta_max = maxabs(delta, k)
        if iter >= c.plmaxit || (math.abs[f64](loglik - ll0) <= c.pllconv && delta_max < c.plxconv) { break }
    }
    let res = Pl { beta: beta[isel], loglik: loglik, iter: iter, warn: warn, c0: math.abs[f64](loglik - ll0), c1: delta_max }
    b.at = mark
    ret (res, ok)
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// the logistf call

type Opt = struct {
    firth: bool, pl: bool, alpha: f64, c: Ctl, has_int: bool,
    plconf: []const usize, has_plconf: bool, terms_fit: []const usize, has_terms: bool,
    init: []const f64, has_init: bool, flic: bool, facs: []const f64, nv: usize
}

fn opt_default() -> Opt {
    ret Opt {
        firth: true, pl: true, alpha: 0.05f64, c: ctl_default(), has_int: true,
        plconf: zero, has_plconf: false, terms_fit: zero, has_terms: false,
        init: zero, has_init: false, flic: false, facs: zero, nv: 0usize
    }
}

// method of a confidence interval: 0 Wald, 1 profile likelihood, 2 none ("-")
type Lf = struct {
    n: usize, k: usize, coef: []f64, var_m: []f64, df: usize, ll_full: f64, ll_null: f64, iter_full: usize, iter_null: usize,
    sumw: f64, c0: f64, c1: f64, c2: f64, lp: []f64, pred: []f64, hat: []f64, prob: []f64, ci_lo: []f64, ci_up: []f64,
    method_ci: []usize, pl_iter: []usize, pl_conv: []f64, np: usize, firth: bool, flic: bool, alpha: f64, warn: bool, int: usize
}

fn pchisq_up(x: f64, df: f64) -> f64 { ret 1.0f64 - nm.pchisq(x, df, true, false) }

fn fill_f(s: []f64, v: f64) {
    var i = 0usize
    while i < s.len {
        s[i] = v
        i += 1usize
    }
}

fn weights_or_ones(a: *mem.Arena, w: []const f64, n: usize) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, n)
    if e != ok { ret (r, e) }
    var i = 0usize
    while i < n {
        if w.len == 0usize {
            r[i] = 1.0f64
        } else {
            r[i] = w[i]
        }
        i += 1usize
    }
    ret (r, ok)
}

fn offset_or_zeros(a: *mem.Arena, w: []const f64, n: usize) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, n)
    if e != ok { ret (r, e) }
    var i = 0usize
    while i < n {
        if w.len == 0usize {
            r[i] = 0.0f64
        } else {
            r[i] = w[i]
        }
        i += 1usize
    }
    ret (r, ok)
}

fn bump_for(a: *mem.Arena, n: usize, k: usize) -> (Bump, err) {
    let (b, e) = bump_new(a, 80usize * (n * k + n + k * k + 64usize) + 8192usize, 2usize * n + 8usize * k + 256usize)
    ret (b, e)
}

fn in_list(l: []const usize, v: usize, m: usize) -> bool {
    var i = 0usize
    while i < m {
        if l[i] == v { ret true }
        i += 1usize
    }
    ret false
}

// logistf: weight and offset may be empty. The model is x (n by k); has_int says the first column is the intercept
fn logistf(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, weight_in: []const f64, offset_in: []const f64, o: Opt) -> (Lf, err) {
    let (b, eb) = bump_for(a, n, k)
    if eb != ok { ret (zero, eb) }
    var bm = b
    let bp = &bm
    let (weight, e1) = weights_or_ones(a, weight_in, n)
    if e1 != ok { ret (zero, e1) }
    let (offset, e2) = offset_or_zeros(a, offset_in, n)
    if e2 != ok { ret (zero, e2) }
    var ncf = k
    if o.has_terms { ncf = o.terms_fit.len }
    let (colfit, e3) = mem.alloc[usize](a, ncf)
    if e3 != ok { ret (zero, e3) }
    var i = 0usize
    while i < ncf {
        if o.has_terms {
            colfit[i] = o.terms_fit[i]
        } else {
            colfit[i] = i + 1usize
        }
        i += 1usize
    }
    let (beta, e4) = mem.alloc[f64](a, k)
    let (var_m, e5) = mem.alloc[f64](a, k * k)
    let (ustar, e6) = mem.alloc[f64](a, k)
    let (pi, e7) = mem.alloc[f64](a, n)
    let (hat, e8) = mem.alloc[f64](a, n)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (zero, mem.Exhausted) }
    i = 0usize
    while i < k {
        beta[i] = 0.0f64
        if o.has_init { beta[i] = o.init[i] }
        i += 1usize
    }
    let (core, ef) = fit_fit(bp, x, y, n, k, weight, offset, beta, colfit, o.firth, o.c, var_m, ustar, pi, hat)
    if ef != ok { ret (zero, ef) }
    // the null model: the first column only
    let (beta0, f1) = mem.alloc[f64](a, k)
    let (var0, f2) = mem.alloc[f64](a, k * k)
    let (ustar0, f3) = mem.alloc[f64](a, k)
    let (pi0, f4) = mem.alloc[f64](a, n)
    let (hat0, f5) = mem.alloc[f64](a, n)
    let (cf1, f6) = mem.alloc[usize](a, 1usize)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok { ret (zero, mem.Exhausted) }
    fill_f(beta0, 0.0f64)
    cf1[0usize] = 1usize
    let (core0, e0) = fit_fit(bp, x, y, n, k, weight, offset, beta0, cf1, o.firth, o.c, var0, ustar0, pi0, hat0)
    if e0 != ok { ret (zero, e0) }
    let (prob, g1) = mem.alloc[f64](a, k)
    let (ci_lo, g2) = mem.alloc[f64](a, k)
    let (ci_up, g3) = mem.alloc[f64](a, k)
    let (method_ci, g4) = mem.alloc[usize](a, k)
    let (pl_iter, g5) = mem.alloc[usize](a, 3usize * k)
    let (pl_conv, g6) = mem.alloc[f64](a, 4usize * k)
    let (lp, g7) = mem.alloc[f64](a, n)
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok { ret (zero, mem.Exhausted) }
    var sumw = 0.0f64
    i = 0usize
    while i < n {
        sumw += weight[i]
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += x[i + j * n] * beta[j]
            j += 1usize
        }
        lp[i] = s + offset[i]
        i += 1usize
    }
    i = 0usize
    while i < 3usize * k {
        pl_iter[i] = 0usize
        i += 1usize
    }
    fill_f(pl_conv, 0.0f64)
    fill_f(prob, 0.0f64)
    fill_f(ci_lo, 0.0f64)
    fill_f(ci_up, 0.0f64)
    var int = 0usize
    if o.has_int { int = 1usize }
    var nterms = k
    if o.has_terms { nterms = ncf }
    var r = Lf {
        n: n, k: k, coef: beta, var_m: var_m, df: nterms - int, ll_full: core.loglik, ll_null: core0.loglik, iter_full: core.iter, iter_null: core0.iter,
        sumw: sumw, c0: core.c0, c1: core.c1, c2: core.c2, lp: lp, pred: pi, hat: hat, prob: prob, ci_lo: ci_lo, ci_up: ci_up,
        method_ci: method_ci, pl_iter: pl_iter, pl_conv: pl_conv, np: 0usize, firth: o.firth, flic: false, alpha: o.alpha, warn: core.warn, int: int
    }
    if !o.pl {
        let zq = dist.qnorm(o.alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
        let zu = dist.qnorm(1.0f64 - o.alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
        i = 0usize
        while i < k {
            method_ci[i] = 0usize
            var inside = true
            if o.has_terms { inside = in_list(colfit, i + 1usize, ncf) }
            if inside {
                let vv = var_m[i + i * k]
                prob[i] = pchisq_up(beta[i] * beta[i] / vv, 1.0f64)
                ci_lo[i] = beta[i] + zq * sqrt_f(vv)
                ci_up[i] = beta[i] + zu * sqrt_f(vv)
            }
            i += 1usize
        }
    } else {
        // the coefficients to profile (1-based as in R) and those left out
        let (plist, h1) = mem.alloc[usize](a, k)
        if h1 != ok { ret (zero, h1) }
        var np = 0usize
        var single_intercept = false
        if k == 1usize && o.has_int { single_intercept = true }
        i = 0usize
        while i < k {
            var want = false
            if o.has_plconf {
                want = in_list(o.plconf, i + 1usize, o.plconf.len)
            } else {
                want = !single_intercept
            }
            if o.has_terms && want { want = in_list(colfit, i + 1usize, ncf) }
            if want {
                plist[np] = i
                np += 1usize
            }
            i += 1usize
        }
        // a given plconf is visited in its own order
        if o.has_plconf {
            np = 0usize
            var q = 0usize
            while q < o.plconf.len {
                let c = o.plconf[q] - 1usize
                var take_it = true
                if o.has_terms { take_it = in_list(colfit, c + 1usize, ncf) }
                if take_it {
                    plist[np] = c
                    np += 1usize
                }
                q += 1usize
            }
        }
        r.np = np
        let ll0 = core.loglik - nm.qchisq(1.0f64 - o.alpha, 1.0f64, true, false) / 2.0f64
        let (hist, hh) = mem.alloc[f64](a, o.c.plmaxit * k)
        if hh != ok { ret (zero, hh) }
        let tofit_n = ncf
        let (tofit, h2) = mem.alloc[usize](a, tofit_n + 1usize)
        let (beta_i, h3) = mem.alloc[f64](a, k)
        let (var_i, h4) = mem.alloc[f64](a, k * k)
        let (us_i, h5) = mem.alloc[f64](a, k)
        let (pi_i, h6) = mem.alloc[f64](a, n)
        let (hat_i, h7) = mem.alloc[f64](a, n)
        if h2 != ok || h3 != ok || h4 != ok || h5 != ok || h6 != ok || h7 != ok { ret (zero, mem.Exhausted) }
        // entries neither profiled nor left out are NA
        i = 0usize
        while i < k {
            var is_pl = false
            var is_rest = false
            is_pl = in_list(plist, i, np)
            if o.has_terms {
                is_rest = !in_list(colfit, i + 1usize, ncf)
            } else {
                if o.has_plconf {
                    is_rest = !in_list(o.plconf, i + 1usize, o.plconf.len)
                } else {
                    is_rest = single_intercept
                }
            }
            if is_pl {
                method_ci[i] = 1usize
            } else {
                if is_rest {
                    method_ci[i] = 2usize
                    prob[i] = 0.0f64
                    ci_lo[i] = 0.0f64
                    ci_up[i] = 0.0f64
                } else {
                    method_ci[i] = 3usize
                    prob[i] = nan()
                    ci_lo[i] = nan()
                    ci_up[i] = nan()
                }
            }
            i += 1usize
        }
        var q = 0usize
        while q < np {
            let ci = plist[q]
            let (lo, e10) = logistpl(bp, x, y, n, k, weight, offset, beta, ci, ll0, o.firth, 0.0f64 - 1.0f64, o.c, hist)
            if e10 != ok { ret (zero, e10) }
            ci_lo[ci] = lo.beta
            pl_iter[ci * 3usize] = lo.iter
            let (up, e11) = logistpl(bp, x, y, n, k, weight, offset, beta, ci, ll0, o.firth, 1.0f64, o.c, hist)
            if e11 != ok { ret (zero, e11) }
            ci_up[ci] = up.beta
            pl_iter[ci * 3usize + 1usize] = up.iter
            pl_conv[q * 4usize] = lo.c0
            pl_conv[q * 4usize + 1usize] = lo.c1
            pl_conv[q * 4usize + 2usize] = up.c0
            pl_conv[q * 4usize + 3usize] = up.c1
            var nt = 0usize
            var t = 0usize
            while t < ncf {
                if colfit[t] != ci + 1usize {
                    tofit[nt] = colfit[t]
                    nt += 1usize
                }
                t += 1usize
            }
            if nt == 0usize {
                tofit[0usize] = 0usize
                nt = 1usize
            }
            fill_f(beta_i, 0.0f64)
            let (ci_core, e12) = fit_fit(bp, x, y, n, k, weight, offset, beta_i, tofit[0usize..nt], o.firth, o.c, var_i, us_i, pi_i, hat_i)
            if e12 != ok { ret (zero, e12) }
            pl_iter[ci * 3usize + 2usize] = ci_core.iter
            prob[ci] = pchisq_up(2.0f64 * (core.loglik - ci_core.loglik), 1.0f64)
            q += 1usize
        }
    }
    if o.flic {
        let (fl, e13) = flic_in_logistf(a, x, n, k, y, r)
        if e13 != ok { ret (zero, e13) }
        ret (fl, ok)
    }
    ret (r, ok)
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// glm(y ~ 1, family = binomial, offset): the iteratively reweighted fit with glm.fit's stopping rule

type Glm = struct { coef: f64, w2sum: f64, iter: usize, eta: []f64, mu: []f64, conv: bool }

fn eps_dbl() -> f64 { ret 2.220446049250313e-16f64 }

fn logit_inv(eta: f64) -> f64 {
    var t = 0.0f64
    if eta < 0.0f64 - 30.0f64 {
        t = eps_dbl()
    } else {
        if eta > 30.0f64 {
            t = 1.0f64 / eps_dbl()
        } else {
            t = math.exp[f64](eta)
        }
    }
    ret t / (1.0f64 + t)
}

fn logit_mu_eta(eta: f64) -> f64 {
    if eta > 30.0f64 || eta < 0.0f64 - 30.0f64 { ret eps_dbl() }
    let op = 1.0f64 + math.exp[f64](eta)
    ret math.exp[f64](eta) / (op * op)
}

fn y_log_y(y: f64, mu: f64) -> f64 {
    if y != 0.0f64 { ret y * math.log[f64](y / mu) }
    ret 0.0f64
}

fn glm_dev(y: []const f64, mu: []const f64, wt: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += 2.0f64 * wt[i] * (y_log_y(y[i], mu[i]) + y_log_y(1.0f64 - y[i], 1.0f64 - mu[i]))
        i += 1usize
    }
    ret s
}

fn glm_intercept(a: *mem.Arena, y: []const f64, n: usize, off: []const f64, wt: []const f64) -> (Glm, err) {
    let (eta, e1) = mem.alloc[f64](a, n)
    let (mu, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (zero, mem.Exhausted) }
    var i = 0usize
    while i < n {
        let ms = (wt[i] * y[i] + 0.5f64) / (wt[i] + 1.0f64)
        eta[i] = math.log[f64](ms / (1.0f64 - ms))
        mu[i] = logit_inv(eta[i])
        i += 1usize
    }
    var devold = glm_dev(y, mu, wt, n)
    var coef = 0.0f64
    var w2 = 0.0f64
    var it = 1usize
    var conv = false
    while it <= 25usize {
        var sw = 0.0f64
        var swz = 0.0f64
        i = 0usize
        while i < n {
            let me = logit_mu_eta(eta[i])
            let z = (eta[i] - off[i]) + (y[i] - mu[i]) / me
            let w = sqrt_f((wt[i] * me * me) / (mu[i] * (1.0f64 - mu[i])))
            sw += w * w
            swz += w * (z * w)
            i += 1usize
        }
        w2 = sw
        coef = swz / sw
        i = 0usize
        while i < n {
            eta[i] = coef + off[i]
            mu[i] = logit_inv(eta[i])
            i += 1usize
        }
        let dev = glm_dev(y, mu, wt, n)
        if !finite(dev) { ret (zero, Singular) }
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 {
            conv = true
            break
        }
        devold = dev
        it += 1usize
    }
    ret (Glm { coef: coef, w2sum: w2, iter: it, eta: eta, mu: mu, conv: conv }, ok)
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// FLIC

fn copy_lf(a: *mem.Arena, src: Lf) -> (Lf, err) {
    var r = src
    let (c, e1) = mem.alloc[f64](a, src.k)
    let (v, e2) = mem.alloc[f64](a, src.k * src.k)
    let (l, e3) = mem.alloc[f64](a, src.n)
    let (p, e4) = mem.alloc[f64](a, src.n)
    let (lo, e5) = mem.alloc[f64](a, src.k)
    let (up, e6) = mem.alloc[f64](a, src.k)
    let (pr, e7) = mem.alloc[f64](a, src.k)
    let (m, e8) = mem.alloc[usize](a, src.k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (zero, mem.Exhausted) }
    i_copy(src.coef, c, src.k)
    i_copy(src.var_m, v, src.k * src.k)
    i_copy(src.lp, l, src.n)
    i_copy(src.pred, p, src.n)
    i_copy(src.ci_lo, lo, src.k)
    i_copy(src.ci_up, up, src.k)
    i_copy(src.prob, pr, src.k)
    var i = 0usize
    while i < src.k {
        m[i] = src.method_ci[i]
        i += 1usize
    }
    r.coef = c
    r.var_m = v
    r.lp = l
    r.pred = p
    r.ci_lo = lo
    r.ci_up = up
    r.prob = pr
    r.method_ci = m
    ret (r, ok)
}

// logistf(flic = TRUE): the intercept refitted by ML given the other linear predictor, its Wald interval, the covariance (X'WX)^-1 at the
// refitted probabilities. The observation weights are not used by the refit
fn flic_in_logistf(a: *mem.Arena, x: []const f64, n: usize, k: usize, y: []const f64, lf: Lf) -> (Lf, err) {
    let (b, eb) = bump_for(a, n, k)
    if eb != ok { ret (zero, eb) }
    var bm = b
    let bp = &bm
    var (r, ec) = copy_lf(a, lf)
    if ec != ok { ret (zero, ec) }
    let (lpf, e1) = mem.alloc[f64](a, n)
    let (ones, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (zero, mem.Exhausted) }
    var i = 0usize
    while i < n {
        lpf[i] = lf.lp[i] - lf.coef[0usize]
        ones[i] = 1.0f64
        i += 1usize
    }
    let (g, eg) = glm_intercept(a, y, n, lpf, ones)
    if eg != ok { ret (zero, eg) }
    let (wv, e_wv) = mem.alloc[f64](a, n)
    if e_wv != ok { ret (zero, e_wv) }
    fill_f(wv, 0.0f64)
    i = 0usize
    while i < n {
        wv[i] = g.mu[i] * (1.0f64 - g.mu[i])
        i += 1usize
    }
    let (none, e_none) = mem.alloc[usize](a, 0usize)
    if e_none != ok { ret (zero, e_none) }
    let (xwx, e_xwx) = mem.alloc[f64](a, k * k)
    if e_xwx != ok { ret (zero, e_xwx) }
    fill_f(xwx, 0.0f64)
    lf_xwx(bp, x, n, k, wv, none, k, xwx)
    let ei = pd_inv(bp, xwx, k)
    if ei != ok { ret (zero, ei) }
    let se0 = sqrt_f(xwx[0usize])
    r.coef[0usize] = g.coef
    r.ci_lo[0usize] = g.coef - se0 * 1.96f64
    r.ci_up[0usize] = g.coef + se0 * 1.96f64
    i = 0usize
    while i < n {
        r.lp[i] = g.eta[i]
        r.pred[i] = g.mu[i]
        i += 1usize
    }
    i_copy(xwx, r.var_m, k * k)
    r.method_ci[0usize] = 0usize
    r.flic = true
    ret (r, ok)
}

// flic(formula, data) and flic(lfobject): lf is the logistf fit (flic = FALSE) of the same model. terms_fit (1-based, may be empty) as in
// modcontrol. The covariance weights the cross products by the fitted probabilities and the offset enters the refit twice, as the package does
fn flic_fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, weight_in: []const f64, offset_in: []const f64, terms_fit: []const usize, lf: Lf) -> (Lf, err) {
    let (b, eb) = bump_for(a, n, k)
    if eb != ok { ret (zero, eb) }
    var bm = b
    let bp = &bm
    var (r, ec) = copy_lf(a, lf)
    if ec != ok { ret (zero, ec) }
    let (weight, ew) = weights_or_ones(a, weight_in, n)
    if ew != ok { ret (zero, ew) }
    let (offset, eo) = offset_or_zeros(a, offset_in, n)
    if eo != ok { ret (zero, eo) }
    let (lpo, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (zero, e1) }
    var i = 0usize
    while i < n {
        lpo[i] = (lf.lp[i] - lf.coef[0usize]) + offset[i]
        i += 1usize
    }
    let (g, eg) = glm_intercept(a, y, n, lpo, weight)
    if eg != ok { ret (zero, eg) }
    let (wv, e_wv) = mem.alloc[f64](a, n)
    if e_wv != ok { ret (zero, e_wv) }
    fill_f(wv, 0.0f64)
    i = 0usize
    while i < n {
        wv[i] = g.mu[i] * (1.0f64 - g.mu[i])
        i += 1usize
    }
    let (none, e_none) = mem.alloc[usize](a, 0usize)
    if e_none != ok { ret (zero, e_none) }
    let (xwx, e_xwx) = mem.alloc[f64](a, k * k)
    if e_xwx != ok { ret (zero, e_xwx) }
    fill_f(xwx, 0.0f64)
    lf_xwx(bp, x, n, k, wv, none, k, xwx)
    let (ld, el) = pd_logdet(bp, xwx, k)
    if el != ok { ret (zero, el) }
    let ei = pd_inv(bp, xwx, k)
    if ei != ok { ret (zero, ei) }
    let se0 = sqrt_f(xwx[0usize])
    var ll = 0.0f64
    i = 0usize
    while i < n {
        if y[i] != 0.0f64 {
            ll += math.log[f64](g.mu[i])
        } else {
            ll += math.log[f64](1.0f64 - g.mu[i])
        }
        i += 1usize
    }
    let full_ll = ll + 0.5f64 * ld
    r.coef[0usize] = g.coef
    // the probabilities at the new coefficients, without the offset
    let (pp, e_pp) = mem.alloc[f64](a, n)
    if e_pp != ok { ret (zero, e_pp) }
    fill_f(pp, 0.0f64)
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += x[i + j * n] * r.coef[j]
            j += 1usize
        }
        pp[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - s))
        r.pred[i] = pp[i]
        r.lp[i] = g.eta[i]
        i += 1usize
    }
    var nt = k
    if terms_fit.len > 0usize { nt = terms_fit.len }
    let (sel, e_sel) = mem.alloc[usize](a, nt)
    if e_sel != ok { ret (zero, e_sel) }
    i = 0usize
    while i < nt {
        if terms_fit.len > 0usize {
            sel[i] = terms_fit[i] - 1usize
        } else {
            sel[i] = i
        }
        i += 1usize
    }
    let (vr, e_vr) = mem.alloc[f64](a, nt * nt)
    if e_vr != ok { ret (zero, e_vr) }
    fill_f(vr, 0.0f64)
    lf_xwx(bp, x, n, k, pp, sel, nt, vr)
    let ev = pd_inv(bp, vr, nt)
    if ev != ok { ret (zero, ev) }
    fill_f(r.var_m, 0.0f64)
    i = 0usize
    while i < nt {
        var j = 0usize
        while j < nt {
            r.var_m[sel[i] + k * sel[j]] = vr[i + nt * j]
            j += 1usize
        }
        i += 1usize
    }
    let se_glm = sqrt_f(1.0f64 / g.w2sum)
    let z = g.coef / se_glm
    r.prob[0usize] = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false)
    r.ci_lo[0usize] = g.coef - se0 * 1.96f64
    r.ci_up[0usize] = g.coef + se0 * 1.96f64
    r.method_ci[0usize] = 0usize
    r.ll_full = full_ll
    r.flic = true
    ret (r, ok)
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// FLAC: ML on the data stacked three times, the second and third copies weighted by tau times the hat diagonal, the third with the response
// reversed, and an indicator of the copies as an extra covariate (the last column). x has the intercept first. The final fit takes no offset
// and the default alpha, as flac.default's call leaves them

fn flac(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, weight_in: []const f64, offset_in: []const f64, o: Opt) -> (Lf, err) {
    var o1 = o
    o1.pl = false
    o1.firth = true
    o1.flic = false
    let (f1, e1) = logistf(a, x, y, n, k, weight_in, offset_in, o1)
    if e1 != ok { ret (zero, e1) }
    let (weight, ew) = weights_or_ones(a, weight_in, n)
    if ew != ok { ret (zero, ew) }
    let ka = k + 1usize
    let na = 3usize * n
    let (xa, e2) = mem.alloc[f64](a, na * ka)
    let (ya, e3) = mem.alloc[f64](a, na)
    let (wa, e4) = mem.alloc[f64](a, na)
    if e2 != ok || e3 != ok || e4 != ok { ret (zero, mem.Exhausted) }
    var rep = 0usize
    while rep < 3usize {
        var i = 0usize
        while i < n {
            let row = rep * n + i
            var j = 0usize
            while j < k {
                xa[row + j * na] = x[i + j * n]
                j += 1usize
            }
            var ps = 1.0f64
            if rep == 0usize { ps = 0.0f64 }
            xa[row + k * na] = ps
            if rep == 2usize {
                ya[row] = 1.0f64 - y[i]
            } else {
                ya[row] = y[i]
            }
            if rep == 0usize {
                wa[row] = weight[i] * 1.0f64
            } else {
                wa[row] = f1.hat[i] * o.c.tau
            }
            i += 1usize
        }
        rep += 1usize
    }
    var o2 = o
    o2.firth = false
    o2.flic = false
    o2.alpha = 0.05f64
    o2.has_plconf = false
    let (f2, e5) = logistf(a, xa, ya, na, ka, wa, zero, o2)
    if e5 != ok { ret (zero, e5) }
    // the intercept-and-indicator model for the null log-likelihood
    let (x3, e6) = mem.alloc[f64](a, na * 2usize)
    if e6 != ok { ret (zero, e6) }
    var r3 = 0usize
    while r3 < na {
        x3[r3] = 1.0f64
        x3[r3 + na] = xa[r3 + k * na]
        r3 += 1usize
    }
    var o3 = opt_default()
    o3.firth = false
    o3.pl = false
    let (f3, e7) = logistf(a, x3, ya, na, 2usize, wa, zero, o3)
    if e7 != ok { ret (zero, e7) }
    // the answer: everything of the augmented fit but the indicator
    var res = f1
    let (c, g1) = mem.alloc[f64](a, k)
    let (v, g2) = mem.alloc[f64](a, k * k)
    let (lpv, g3) = mem.alloc[f64](a, n)
    let (pv, g4) = mem.alloc[f64](a, n)
    let (lo, g5) = mem.alloc[f64](a, k)
    let (up, g6) = mem.alloc[f64](a, k)
    let (pr, g7) = mem.alloc[f64](a, k)
    let (mc, g8) = mem.alloc[usize](a, k)
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok || g8 != ok { ret (zero, mem.Exhausted) }
    var j = 0usize
    while j < k {
        c[j] = f2.coef[j]
        lo[j] = f2.ci_lo[j]
        up[j] = f2.ci_up[j]
        pr[j] = f2.prob[j]
        mc[j] = f2.method_ci[j]
        var l = 0usize
        while l < k {
            v[l + j * k] = f2.var_m[l + j * ka]
            l += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < n {
        lpv[i] = f2.lp[i]
        pv[i] = f2.pred[i]
        i += 1usize
    }
    res.coef = c
    res.var_m = v
    res.lp = lpv
    res.pred = pv
    res.ci_lo = lo
    res.ci_up = up
    res.prob = pr
    res.method_ci = mc
    res.ll_full = f2.ll_full
    res.ll_null = f3.ll_full
    res.pl_iter = f2.pl_iter
    res.np = f2.np
    ret (res, ok)
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// penalized likelihood ratio tests: logistftest, anova, add1, drop1

error NotNested

// the columns cols (0-based, of the n-row matrix x) as a matrix of their own
fn cols_of(a: *mem.Arena, x: []const f64, n: usize, cols: []const usize) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, n * cols.len + 1usize)
    if e != ok { ret (r, e) }
    var j = 0usize
    while j < cols.len {
        var i = 0usize
        while i < n {
            r[i + j * n] = x[i + cols[j] * n]
            i += 1usize
        }
        j += 1usize
    }
    ret (r[0usize..n * cols.len], ok)
}

// the model with the columns cols of the full design x: logistf with every column fitted, no plconf
fn fit_model(a: *mem.Arena, x: []const f64, n: usize, y: []const f64, weight: []const f64, offset: []const f64, cols: []const usize, o: Opt, pl: bool) -> (Lf, err) {
    let (xs, e) = cols_of(a, x, n, cols)
    if e != ok { ret (zero, e) }
    var oo = o
    oo.pl = pl
    oo.has_plconf = false
    oo.has_terms = false
    oo.has_init = false
    oo.flic = false
    oo.has_int = o.has_int && cols[0usize] == 0usize
    let (r, e2) = logistf(a, xs, y, n, cols.len, weight, offset, oo)
    ret (r, e2)
}

type Test = struct { ll_full: f64, ll_null: f64, chisq: f64, df: usize, prob: f64 }

// logistftest: x is the model's design (n by k). pos are the tested columns (0-based); vals (same length) or beta0 (length k) set the
// null values (empty: zero)
fn lf_test(a: *mem.Arena, x: []const f64, n: usize, k: usize, y: []const f64, weight_in: []const f64, offset_in: []const f64, pos: []const usize, vals: []const f64, beta0: []const f64, firth: bool, c: Ctl) -> (Test, err) {
    let (b, eb) = bump_for(a, n, k)
    if eb != ok { ret (zero, eb) }
    var bm = b
    let bp = &bm
    let (weight, ew) = weights_or_ones(a, weight_in, n)
    if ew != ok { ret (zero, ew) }
    let (offset, eo) = offset_or_zeros(a, offset_in, n)
    if eo != ok { ret (zero, eo) }
    let (beta, e1) = mem.alloc[f64](a, k)
    let (vv, e2) = mem.alloc[f64](a, k * k)
    let (us, e3) = mem.alloc[f64](a, k)
    let (pi, e4) = mem.alloc[f64](a, n)
    let (hd, e5) = mem.alloc[f64](a, n)
    let (cf, e6) = mem.alloc[usize](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (zero, mem.Exhausted) }
    var i = 0usize
    while i < k {
        beta[i] = 0.0f64
        cf[i] = i + 1usize
        i += 1usize
    }
    let (full, ef) = fit_fit(bp, x, y, n, k, weight, offset, beta, cf, firth, c, vv, us, pi, hd)
    if ef != ok { ret (zero, ef) }
    let (b0, f1) = mem.alloc[f64](a, k)
    let (v0, f2) = mem.alloc[f64](a, k * k)
    let (u0, f3) = mem.alloc[f64](a, k)
    let (p0, f4) = mem.alloc[f64](a, n)
    let (h0, f5) = mem.alloc[f64](a, n)
    let (c0, f6) = mem.alloc[usize](a, k)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok { ret (zero, mem.Exhausted) }
    i = 0usize
    while i < k {
        b0[i] = 0.0f64
        if beta0.len > 0usize { b0[i] = beta0[i] }
        i += 1usize
    }
    i = 0usize
    while i < pos.len {
        if vals.len > 0usize { b0[pos[i]] = vals[i] }
        i += 1usize
    }
    // all columns tested in their natural order: nothing is fitted
    var all = pos.len == k
    i = 0usize
    while i < pos.len && all {
        if pos[i] != i { all = false }
        i += 1usize
    }
    var nc = 0usize
    if all {
        c0[0usize] = 0usize
        nc = 1usize
    } else {
        i = 0usize
        while i < k {
            if !in_list(pos, i, pos.len) {
                c0[nc] = i + 1usize
                nc += 1usize
            }
            i += 1usize
        }
    }
    let (nul, en) = fit_fit(bp, x, y, n, k, weight, offset, b0, c0[0usize..nc], firth, c, v0, u0, p0, h0)
    if en != ok { ret (zero, en) }
    let chisq = 0.0f64 - 2.0f64 * (nul.loglik - full.loglik)
    ret (Test { ll_full: full.loglik, ll_null: nul.loglik, chisq: chisq, df: pos.len, prob: pchisq_up(chisq, f64(pos.len)) }, ok)
}

// logistftest finds the tested columns by the names model.matrix gives the test formula ~ t1 + t2 + ... - 1: a term of several variables is
// named by the variables in order of first appearance in that formula, so x1:x2 written after x2 is "x2:x1" and matches no column. The terms
// of test (full-design columns; facs is nv by K, the variables of each) whose name survives, in order
fn survive(facs: []const f64, nv: usize, test: []const usize, out: []usize) -> usize {
    let none = usize(1000000usize)
    var m = 0usize
    var t = 0usize
    while t < test.len {
        var ok_term = true
        var prev_rank = 0usize
        var have_prev = false
        var r = 0usize
        while r < nv {
            if facs[r + test[t] * nv] > 0.0f64 {
                // rank of r: the count of distinct variables seen before it in the formula text
                var rank_r = none
                var cnt = 0usize
                var tt = 0usize
                var found = false
                while tt <= t && !found {
                    var rr = 0usize
                    while rr < nv && !found {
                        if facs[rr + test[tt] * nv] > 0.0f64 {
                            // first appearance of rr among terms 0..tt: counts if no earlier term has it
                            var earlier = false
                            var t2 = 0usize
                            while t2 < tt {
                                if facs[rr + test[t2] * nv] > 0.0f64 { earlier = true }
                                t2 += 1usize
                            }
                            if rr == r {
                                found = true
                                rank_r = cnt
                            }
                            if !earlier { cnt += 1usize }
                        }
                        rr += 1usize
                    }
                    tt += 1usize
                }
                if have_prev && !(rank_r > prev_rank) { ok_term = false }
                prev_rank = rank_r
                have_prev = true
            }
            r += 1usize
        }
        if ok_term {
            out[m] = test[t]
            m += 1usize
        }
        t += 1usize
    }
    ret m
}

type Anova = struct { chisq: f64, df: usize, pval: f64, plr1: f64, plr2: f64 }

fn pos_in(cols: []const usize, test: []const usize, out: []usize) -> usize {
    var m = 0usize
    var t = 0usize
    while t < test.len {
        var j = 0usize
        var found = false
        while j < cols.len && !found {
            if cols[j] == test[t] {
                out[m] = j
                m += 1usize
                found = true
            }
            j += 1usize
        }
        t += 1usize
    }
    ret m
}

// anova(object, formula = ~terms, method = "nested"): the test of the terms test (full-design column indices) in the model with the columns cols
fn anova_formula(a: *mem.Arena, x: []const f64, n: usize, y: []const f64, weight: []const f64, offset: []const f64, cols: []const usize, test: []const usize, o: Opt) -> (Anova, err) {
    let (xs, e) = cols_of(a, x, n, cols)
    if e != ok { ret (zero, e) }
    var oo = o
    oo.pl = false
    oo.has_plconf = false
    oo.has_terms = false
    oo.has_init = false
    oo.flic = false
    oo.has_int = o.has_int && cols[0usize] == 0usize
    let (fit1, e1) = logistf(a, xs, y, n, cols.len, weight, offset, oo)
    if e1 != ok { ret (zero, e1) }
    let (pos, e2) = mem.alloc[usize](a, test.len + 1usize)
    let (kept, e2b) = mem.alloc[usize](a, test.len + 1usize)
    if e2 != ok || e2b != ok { ret (zero, mem.Exhausted) }
    var tk = test
    if o.nv > 0usize {
        let nk = survive(o.facs, o.nv, test, kept)
        tk = kept[0usize..nk]
    }
    let m = pos_in(cols, tk, pos)
    let (t, e3) = lf_test(a, xs, n, cols.len, y, weight, offset, pos[0usize..m], zero, zero, o.firth, o.c)
    if e3 != ok { ret (zero, e3) }
    let plr1 = 0.0f64 - 2.0f64 * (fit1.ll_null - fit1.ll_full)
    ret (Anova { chisq: t.chisq, df: t.df, pval: t.prob, plr1: plr1, plr2: plr1 - t.chisq }, ok)
}

// anova(fit1, fit2, method = "PLR")
fn anova_plr(f1: Lf, f2: Lf) -> (Anova, err) {
    if f1.df == f2.df { ret (zero, NotNested) }
    var df = f1.df - f2.df
    if f2.df > f1.df { df = f2.df - f1.df }
    let plr1 = 0.0f64 - 2.0f64 * (f1.ll_null - f1.ll_full)
    let plr2 = 0.0f64 - 2.0f64 * (f2.ll_null - f2.ll_full)
    var chisq = plr1 - plr2
    if chisq < 0.0f64 { chisq = 0.0f64 }
    ret (Anova { chisq: chisq, df: df, pval: pchisq_up(chisq, f64(df)), plr1: plr1, plr2: plr2 }, ok)
}

// anova(fit1, fit2) with method "nested" for the models with the columns cols1 and cols2
fn anova_nested(a: *mem.Arena, x: []const f64, n: usize, y: []const f64, weight: []const f64, offset: []const f64, cols1: []const usize, cols2: []const usize, o: Opt) -> (Anova, err) {
    let (f1, e1) = fit_model(a, x, n, y, weight, offset, cols1, o, false)
    if e1 != ok { ret (zero, e1) }
    let (f2, e2) = fit_model(a, x, n, y, weight, offset, cols2, o, false)
    if e2 != ok { ret (zero, e2) }
    var big = cols1
    var small = cols2
    if f1.df < f2.df {
        big = cols2
        small = cols1
    }
    // object is the model with the larger df; a is its terms, b the other's
    var ta = big
    var tb = small
    var all_in = true
    var i = 0usize
    while i < ta.len {
        if !in_list(tb, ta[i], tb.len) { all_in = false }
        i += 1usize
    }
    if all_in {
        ta = small
        tb = big
    } else {
        i = 0usize
        while i < tb.len {
            if !in_list(ta, tb[i], ta.len) { ret (zero, NotNested) }
            i += 1usize
        }
    }
    let (aug, e3) = mem.alloc[usize](a, ta.len + 1usize)
    if e3 != ok { ret (zero, e3) }
    var na = 0usize
    i = 0usize
    while i < ta.len {
        if !in_list(tb, ta[i], tb.len) {
            aug[na] = ta[i]
            na += 1usize
        }
        i += 1usize
    }
    let (r, e4) = anova_formula(a, x, n, y, weight, offset, big, aug[0usize..na], o)
    ret (r, e4)
}

// add1: one row (chisq, df, p) per candidate of scope, written to out (3 per candidate)
fn add1(a: *mem.Arena, x: []const f64, n: usize, y: []const f64, weight: []const f64, offset: []const f64, cols: []const usize, scope: []const usize, o: Opt, out: []f64) -> err {
    var s = 0usize
    while s < scope.len {
        let (nc, e1) = mem.alloc[usize](a, cols.len + 1usize)
        if e1 != ok { ret e1 }
        var i = 0usize
        while i < cols.len {
            nc[i] = cols[i]
            i += 1usize
        }
        nc[cols.len] = scope[s]
        let one = nc[cols.len..cols.len + 1usize]
        let (r, e2) = anova_formula(a, x, n, y, weight, offset, nc, one, o)
        if e2 != ok { ret e2 }
        out[s * 3usize] = r.chisq
        out[s * 3usize + 1usize] = f64(r.df)
        out[s * 3usize + 2usize] = r.pval
        s += 1usize
    }
    ret ok
}

// drop1: the same for each term of scope removed from the model cols; rem (may be empty) are the terms already removed under full.penalty
fn drop1(a: *mem.Arena, x: []const f64, n: usize, y: []const f64, weight: []const f64, offset: []const f64, cols: []const usize, scope: []const usize, rem: []const usize, o: Opt, out: []f64) -> err {
    var s = 0usize
    while s < scope.len {
        var r: Anova = zero
        if rem.len > 0usize && scope.len != rem.len {
            let (tt, e1) = mem.alloc[usize](a, rem.len + 1usize)
            if e1 != ok { ret e1 }
            tt[0usize] = scope[s]
            var q = 0usize
            while q < rem.len {
                tt[q + 1usize] = rem[q]
                q += 1usize
            }
            let (r1, e2) = anova_formula(a, x, n, y, weight, offset, cols, tt[0usize..rem.len + 1usize], o)
            if e2 != ok { ret e2 }
            r = r1
        } else {
            let (tt2, e3) = mem.alloc[usize](a, 1usize)
            if e3 != ok { ret e3 }
            tt2[0usize] = scope[s]
            let (r2, e4) = anova_formula(a, x, n, y, weight, offset, cols, tt2, o)
            if e4 != ok { ret e4 }
            r = r2
        }
        out[s * 3usize] = r.chisq
        out[s * 3usize + 1usize] = f64(r.df)
        out[s * 3usize + 2usize] = r.pval
        s += 1usize
    }
    ret ok
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// selection

type Sel = struct { fit: Lf, cols: []usize, nc: usize, steps: usize, order: []usize, pl: bool }

// extractAIC: (df, deviance + k df)
fn extract_aic(f: Lf, kpen: f64) -> (f64, f64) {
    let dev = 0.0f64 - 2.0f64 * (f.ll_null - f.ll_full)
    ret (f64(f.df), dev + kpen * f64(f.df))
}

// forward: start is the model's columns (full-design indices, the intercept 0 first); scope the candidates. order receives the columns added
fn forward(a: *mem.Arena, x: []const f64, n: usize, y: []const f64, weight: []const f64, offset: []const f64, start: []const usize, scope_in: []const usize, o: Opt, steps: usize, slentry: f64, pl: bool) -> (Sel, err) {
    let (cols, e1) = mem.alloc[usize](a, start.len + scope_in.len + 1usize)
    let (scope, e2) = mem.alloc[usize](a, scope_in.len + 1usize)
    let (order, e3) = mem.alloc[usize](a, scope_in.len + 1usize)
    let (mat, e4) = mem.alloc[f64](a, 3usize * scope_in.len + 3usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (zero, mem.Exhausted) }
    var nc = start.len
    var i = 0usize
    while i < nc {
        cols[i] = start[i]
        i += 1usize
    }
    var ns = 0usize
    i = 0usize
    while i < scope_in.len {
        if !in_list(start, scope_in[i], start.len) {
            scope[ns] = scope_in[i]
            ns += 1usize
        }
        i += 1usize
    }
    var istep = 0usize
    var norder = 0usize
    var working_pl = o.pl
    while istep < steps && ns >= 1usize {
        istep += 1usize
        let e5 = add1(a, x, n, y, weight, offset, cols[0usize..nc], scope[0usize..ns], o, mat)
        if e5 != ok { ret (zero, e5) }
        var all_big = true
        i = 0usize
        while i < ns {
            if !(mat[i * 3usize + 2usize] > slentry) { all_big = false }
            i += 1usize
        }
        if all_big { break }
        var pmin = mat[2usize]
        i = 1usize
        while i < ns {
            if mat[i * 3usize + 2usize] < pmin { pmin = mat[i * 3usize + 2usize] }
            i += 1usize
        }
        var best = ns
        var bchi = 0.0f64 - infinity()
        i = 0usize
        while i < ns {
            if mat[i * 3usize + 2usize] == pmin {
                // ties go to the largest chi-square; the first of equals
                if best == ns || mat[i * 3usize] > bchi {
                    best = i
                    bchi = mat[i * 3usize]
                }
            }
            i += 1usize
        }
        let addvar = scope[best]
        cols[nc] = addvar
        nc += 1usize
        order[norder] = addvar
        norder += 1usize
        working_pl = false
        var q = best
        while q + 1usize < ns {
            scope[q] = scope[q + 1usize]
            q += 1usize
        }
        ns -= 1usize
    }
    if pl { working_pl = true }
    let (f, e6) = fit_model(a, x, n, y, weight, offset, cols[0usize..nc], o, working_pl)
    if e6 != ok { ret (zero, e6) }
    ret (Sel { fit: f, cols: cols, nc: nc, steps: istep, order: order[0usize..norder], pl: working_pl }, ok)
}

// factor.scope(drop): which of the model's terms (columns of facs, nv variables by K columns, column-major) can be dropped: those no other
// term contains
fn droppable(facs: []const f64, nv: usize, terms: []const usize, nt: usize, keep: []bool) {
    var i = 0usize
    while i < nt {
        keep[i] = true
        i += 1usize
    }
    if nt <= 1usize { ret }
    i = 0usize
    while i < nt {
        var fmax = 0.0f64
        var j = 0usize
        while j < nt {
            if j != i {
                var s = 0.0f64
                var r = 0usize
                while r < nv {
                    if facs[r + terms[i] * nv] > 0.0f64 && facs[r + terms[j] * nv] > 0.0f64 { s += 1.0f64 }
                    r += 1usize
                }
                if s > fmax { fmax = s }
            }
            j += 1usize
        }
        var fii = 0.0f64
        var r2 = 0usize
        while r2 < nv {
            if facs[r2 + terms[i] * nv] > 0.0f64 { fii += 1.0f64 }
            r2 += 1usize
        }
        if !(fmax != fii) { keep[i] = false }
        i += 1usize
    }
}

// backward: drops the term with the largest p value while some p is not below slstay. facs (nv by K) marks which variables make up each column
// (the intercept column is all zero). full_penalty keeps the removed terms in the penalty and refits at the end with them unfitted
fn backward(a: *mem.Arena, x: []const f64, n: usize, K: usize, y: []const f64, weight: []const f64, offset: []const f64, start: []const usize, facs: []const f64, nv: usize, o: Opt, steps: usize, slstay: f64, full_penalty: bool) -> (Sel, err) {
    let (cols, e1) = mem.alloc[usize](a, start.len + 1usize)
    let (order, e2) = mem.alloc[usize](a, start.len + 1usize)
    let (scope, e3) = mem.alloc[usize](a, start.len + 1usize)
    let (keep, e4) = mem.alloc[bool](a, start.len + 1usize)
    let (mat, e5) = mem.alloc[f64](a, 3usize * start.len + 3usize)
    let (terms_cur, e6) = mem.alloc[usize](a, start.len + 1usize)
    let (removal, e7) = mem.alloc[usize](a, start.len + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (zero, mem.Exhausted) }
    var nc = start.len
    var i = 0usize
    while i < nc {
        cols[i] = start[i]
        i += 1usize
    }
    var nrem = 0usize
    var norder = 0usize
    var istep = 0usize
    var df = nc - 1usize
    if !o.has_int { df = nc }
    var working_pl = o.pl
    var intercept = 0usize
    if o.has_int { intercept = 1usize }
    let (obj, e8) = fit_model(a, x, n, y, weight, offset, start, o, o.pl)
    if e8 != ok { ret (zero, e8) }
    var working = obj
    while istep < steps && df > 1usize {
        // the terms still in the formula
        var nt = 0usize
        i = intercept
        while i < nc {
            terms_cur[nt] = cols[i]
            nt += 1usize
            i += 1usize
        }
        if full_penalty {
            // terms(newform.fp): the start model less the removed ones, tested in the start model
            nt = 0usize
            i = intercept
            while i < start.len {
                if !in_list(removal, start[i], nrem) {
                    terms_cur[nt] = start[i]
                    nt += 1usize
                }
                i += 1usize
            }
        }
        droppable(facs, nv, terms_cur, nt, keep)
        var ns = 0usize
        i = 0usize
        while i < nt {
            if keep[i] {
                scope[ns] = terms_cur[i]
                ns += 1usize
            }
            i += 1usize
        }
        if full_penalty && istep != 0usize {
            let e9 = drop1(a, x, n, y, weight, offset, start, scope[0usize..ns], removal[0usize..nrem], o, mat)
            if e9 != ok { ret (zero, e9) }
        } else {
            let none = removal[0usize..0usize]
            var base: []const usize = cols[0usize..nc]
            if full_penalty { base = start }
            let e10 = drop1(a, x, n, y, weight, offset, base, scope[0usize..ns], none, o, mat)
            if e10 != ok { ret (zero, e10) }
        }
        istep += 1usize
        var all_small = true
        i = 0usize
        while i < ns {
            if !(mat[i * 3usize + 2usize] < slstay) { all_small = false }
            i += 1usize
        }
        if all_small { break }
        var pmax = mat[2usize]
        var at = 0usize
        i = 1usize
        while i < ns {
            if mat[i * 3usize + 2usize] > pmax {
                pmax = mat[i * 3usize + 2usize]
                at = i
            }
            i += 1usize
        }
        let gone = scope[at]
        order[norder] = gone
        norder += 1usize
        if full_penalty {
            removal[nrem] = gone
            nrem += 1usize
            df -= 1usize
        } else {
            // drop the column from the model
            var q = 0usize
            var w = 0usize
            while q < nc {
                if cols[q] != gone {
                    cols[w] = cols[q]
                    w += 1usize
                }
                q += 1usize
            }
            nc = w
            if df == 2usize {
                working_pl = false
            }
            let (nw, e11) = fit_model(a, x, n, y, weight, offset, cols[0usize..nc], o, working_pl)
            if e11 != ok { ret (zero, e11) }
            working = nw
            df = working.df
        }
    }
    if full_penalty && nrem > 0usize {
        // all terms stay in the penalty, the removed ones are not fitted
        var oo = o
        let (tofit, e12) = mem.alloc[usize](a, start.len + 1usize)
        if e12 != ok { ret (zero, e12) }
        var nf = 0usize
        i = 0usize
        while i < start.len {
            if !in_list(removal, start[i], nrem) {
                tofit[nf] = i + 1usize
                nf += 1usize
            }
            i += 1usize
        }
        let (xs, e13) = cols_of(a, x, n, start)
        if e13 != ok { ret (zero, e13) }
        oo.has_terms = true
        oo.terms_fit = tofit[0usize..nf]
        oo.has_plconf = false
        oo.has_init = false
        oo.flic = false
        let (fw, e14) = logistf(a, xs, y, n, start.len, weight, offset, oo)
        if e14 != ok { ret (zero, e14) }
        working = fw
        nc = start.len
        i = 0usize
        while i < nc {
            cols[i] = start[i]
            i += 1usize
        }
    }
    ret (Sel { fit: working, cols: cols, nc: nc, steps: istep, order: order[0usize..norder], pl: working_pl }, ok)
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// predict

// the linear predictor of the rows of xn (m by k) under coef
fn predict_link(coef: []const f64, xn: []const f64, m: usize, k: usize, out: []f64) {
    var i = 0usize
    while i < m {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += coef[j] * xn[i + j * m]
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
}

fn predict_response(coef: []const f64, xn: []const f64, m: usize, k: usize, out: []f64) {
    predict_link(coef, xn, m, k, out)
    var i = 0usize
    while i < m {
        out[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - out[i]))
        i += 1usize
    }
}

// sqrt(x' V x) for each row of xn
fn predict_se(vm: []const f64, xn: []const f64, m: usize, k: usize, out: []f64) {
    var i = 0usize
    while i < m {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            var t = 0.0f64
            var l = 0usize
            while l < k {
                t += xn[i + l * m] * vm[l + j * k]
                l += 1usize
            }
            s += t * xn[i + j * m]
            j += 1usize
        }
        out[i] = sqrt_f(s)
        i += 1usize
    }
}

// predict(type = "terms"): assign gives the term of each column (0 the intercept); xt is the training design (nt rows) whose column means
// are subtracted. pred is m by nterms (column-major); the second answer is the constant sum(avx * beta). With se, se_out (m by nterms) gets
// sqrt(d' V d) for d the term's columns of xn less the reference row ref (k long)
fn predict_terms(coef: []const f64, vm: []const f64, xt: []const f64, nt: usize, xn: []const f64, m: usize, k: usize, assign: []const usize, nterms: usize, refrow: []const f64, pred: []f64, se_out: []f64) -> f64 {
    var cst = 0.0f64
    var j = 0usize
    while j < k {
        var avx = 0.0f64
        var i = 0usize
        while i < nt {
            avx += xt[i + j * nt]
            i += 1usize
        }
        avx = avx / f64(nt)
        cst += avx * coef[j]
        j += 1usize
    }
    var t = 1usize
    while t <= nterms {
        var i = 0usize
        while i < m {
            var s = 0.0f64
            j = 0usize
            while j < k {
                if assign[j] == t {
                    var avx = 0.0f64
                    var r = 0usize
                    while r < nt {
                        avx += xt[r + j * nt]
                        r += 1usize
                    }
                    avx = avx / f64(nt)
                    s += (xn[i + j * m] - avx) * coef[j]
                }
                j += 1usize
            }
            pred[i + (t - 1usize) * m] = s
            if refrow.len > 0usize {
                var q = 0.0f64
                var l = 0usize
                while l < k {
                    var inner = 0.0f64
                    var u = 0usize
                    while u < k {
                        if assign[u] == t { inner += vm[l + u * k] * (xn[i + u * m] - refrow[u]) }
                        u += 1usize
                    }
                    if assign[l] == t { q += (xn[i + l * m] - refrow[l]) * inner }
                    l += 1usize
                }
                se_out[i + (t - 1usize) * m] = sqrt_f(q)
            }
            i += 1usize
        }
        t += 1usize
    }
    ret cst
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// summary, logistf.pdf, profile, PVR.confint

// summary.logistf: chi-square of each coefficient qchisq(1 - p, 1), the likelihood ratio statistic and p, the Wald statistic coefs' V^-1 coefs
// (NaN when V is singular) and its p
type Summ = struct { lr: f64, lr_p: f64, wald: f64, wald_p: f64 }

fn summary_lf(a: *mem.Arena, f: Lf, terms_fit: []const usize, chi2: []f64) -> (Summ, err) {
    let (b, eb) = bump_for(a, 1usize, f.k)
    if eb != ok { ret (zero, eb) }
    var bm = b
    let bp = &bm
    var i = 0usize
    while i < f.k {
        chi2[i] = nm.qchisq(1.0f64 - f.prob[i], 1.0f64, true, false)
        i += 1usize
    }
    var m = f.k
    if terms_fit.len > 0usize { m = terms_fit.len }
    let (sel, e1) = mem.alloc[usize](a, m)
    let (vr, e2) = mem.alloc[f64](a, m * m)
    let (cs, e3) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, mem.Exhausted) }
    i = 0usize
    while i < m {
        if terms_fit.len > 0usize {
            sel[i] = terms_fit[i] - 1usize
        } else {
            sel[i] = i
        }
        cs[i] = f.coef[sel[i]]
        i += 1usize
    }
    if terms_fit.len > 0usize {
        i = 0usize
        while i < f.k {
            if !in_list(sel, i, m) { chi2[i] = 0.0f64 }
            i += 1usize
        }
    }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            vr[i + j * m] = f.var_m[sel[i] + sel[j] * f.k]
            j += 1usize
        }
        i += 1usize
    }
    let lr = 0.0f64 - 2.0f64 * (f.ll_null - f.ll_full)
    var wald = nan()
    let ei = pd_inv(bp, vr, m)
    if ei == ok {
        var s = 0.0f64
        i = 0usize
        while i < m {
            var t = 0.0f64
            var j = 0usize
            while j < m {
                t += cs[j] * vr[j + i * m]
                j += 1usize
            }
            s += t * cs[i]
            i += 1usize
        }
        wald = s
    }
    ret (Summ { lr: lr, lr_p: pchisq_up(lr, f64(f.df)), wald: wald, wald_p: pchisq_up(wald, f64(f.df)) }, ok)
}

type Pdf = struct { b: f64, chisq: f64, pdf: f64 }

// logistf.pdf: the profile penalized likelihood ratio at b for coefficient pos (0-based), from beta and the full log-likelihood
fn logistf_pdf(a: *mem.Arena, x: []const f64, n: usize, k: usize, y: []const f64, weight: []const f64, offset: []const f64, firth: bool, c: Ctl, pos: usize, bval: f64, beta: []const f64, loglik: f64) -> (Pdf, err) {
    let (bmp, eb) = bump_for(a, n, k)
    if eb != ok { ret (zero, eb) }
    var bm = bmp
    let bp = &bm
    let (init, e1) = mem.alloc[f64](a, k)
    let (vv, e2) = mem.alloc[f64](a, k * k)
    let (us, e3) = mem.alloc[f64](a, k)
    let (pi, e4) = mem.alloc[f64](a, n)
    let (hd, e5) = mem.alloc[f64](a, n)
    let (cf, e6) = mem.alloc[usize](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (zero, mem.Exhausted) }
    i_copy(beta, init, k)
    init[pos] = bval
    var nc = 0usize
    var i = 0usize
    while i < k {
        if i != pos {
            cf[nc] = i + 1usize
            nc += 1usize
        }
        i += 1usize
    }
    if nc == 0usize {
        cf[0usize] = 0usize
        nc = 1usize
    }
    let (core, ef) = fit_fit(bp, x, y, n, k, weight, offset, init, cf[0usize..nc], firth, c, vv, us, pi, hd)
    if ef != ok { ret (zero, ef) }
    let chisq = 2.0f64 * (loglik - core.loglik)
    var p = 1.0f64 - pchisq_up(chisq, 1.0f64) / 2.0f64
    if bval < beta[pos] { p = 1.0f64 - p }
    ret (Pdf { b: bval, chisq: chisq, pdf: p }, ok)
}

fn floor_f(v: f64) -> f64 { ret math.floor[f64](v) }
fn ceil_f(v: f64) -> f64 { ret math.ceil[f64](v) }

// profile.logistf: the profile of coefficient pos on a grid of steps + 1 knots; the arrays (steps + 1 each, ordered by beta) are beta, stdbeta,
// profile, loglik, signed.root and cdf in out (6 * (steps + 1)); the answer is the number of rows kept (a numerically 0/1 fit stops the walk)
fn profile_lf(a: *mem.Arena, x: []const f64, n: usize, k: usize, y: []const f64, weight: []const f64, offset: []const f64, f: Lf, pos: usize, steps: usize, pitch: f64, have_limits: bool, lim_lo: f64, lim_up: f64, alpha: f64, firth: bool, c: Ctl, out: []f64) -> (usize, err) {
    let (bmp, eb) = bump_for(a, n, k)
    if eb != ok { ret (0usize, eb) }
    var bm = bmp
    let bp = &bm
    let std_pos = sqrt_f(f.var_m[pos + pos * k])
    let ll0 = f.ll_full - nm.qchisq(1.0f64 - alpha, 1.0f64, true, false) / 2.0f64
    var lo = lim_lo
    var up = lim_up
    if !have_limits {
        let (hist, eh) = mem.alloc[f64](a, c.plmaxit * k)
        if eh != ok { ret (0usize, eh) }
        let (l1, e1) = logistpl(bp, x, y, n, k, weight, offset, f.coef, pos, ll0, firth, 0.0f64 - 1.0f64, c, hist)
        if e1 != ok { ret (0usize, e1) }
        let (u1, e2) = logistpl(bp, x, y, n, k, weight, offset, f.coef, pos, ll0, firth, 1.0f64, c, hist)
        if e2 != ok { ret (0usize, e2) }
        lo = l1.beta
        up = u1.beta
    }
    lo = (lo - f.coef[pos]) / std_pos
    up = (up - f.coef[pos]) / std_pos
    lo = floor_f(lo / pitch) * pitch
    up = ceil_f(up / pitch) * pitch
    let nn_k = steps + 1usize
    let (std_v, g1) = mem.alloc[f64](a, nn_k)
    let (bet, g2) = mem.alloc[f64](a, nn_k)
    let (ll, g3) = mem.alloc[f64](a, nn_k)
    let (ord, g4) = mem.alloc[usize](a, nn_k)
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok { ret (0usize, mem.Exhausted) }
    var i = 0usize
    while i < nn_k {
        std_v[i] = lo + f64(i) * ((up - lo) / f64(steps))
        bet[i] = f.coef[pos] + std_pos * std_v[i]
        ll[i] = nan()
        ord[i] = i
        i += 1usize
    }
    // the knots by distance from the estimate, stable
    i = 1usize
    while i < nn_k {
        let cur = ord[i]
        let dcur = math.abs[f64](bet[cur] - f.coef[pos])
        var j = i
        while j > 0usize && math.abs[f64](bet[ord[j - 1usize]] - f.coef[pos]) > dcur {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = cur
        i += 1usize
    }
    let (init, h1) = mem.alloc[f64](a, k)
    let (vv, h2) = mem.alloc[f64](a, k * k)
    let (us, h3) = mem.alloc[f64](a, k)
    let (pi, h4) = mem.alloc[f64](a, n)
    let (hd, h5) = mem.alloc[f64](a, n)
    let (cf, h6) = mem.alloc[usize](a, k)
    if h1 != ok || h2 != ok || h3 != ok || h4 != ok || h5 != ok || h6 != ok { ret (0usize, mem.Exhausted) }
    var nc = 0usize
    i = 0usize
    while i < k {
        if i != pos {
            cf[nc] = i + 1usize
            nc += 1usize
        }
        i += 1usize
    }
    i_copy(f.coef, init, k)
    var stopped = nn_k
    var s = 0usize
    while s < nn_k {
        init[pos] = bet[ord[s]]
        let (core, ef) = fit_fit(bp, x, y, n, k, weight, offset, init, cf[0usize..nc], firth, c, vv, us, pi, hd)
        if ef != ok { ret (0usize, ef) }
        if s > 0usize && core.warn {
            stopped = s
            break
        }
        ll[ord[s]] = core.loglik
        s += 1usize
    }
    // rows with a log-likelihood, by beta
    var kept = 0usize
    i = 0usize
    while i < nn_k {
        if ll[i] == ll[i] { kept += 1usize }
        i += 1usize
    }
    var mx = 0.0f64 - infinity()
    i = 0usize
    while i < nn_k {
        if ll[i] == ll[i] && ll[i] > mx { mx = ll[i] }
        i += 1usize
    }
    var w = 0usize
    i = 0usize
    while i < nn_k {
        if ll[i] == ll[i] {
            let sr0 = sqrt_f(2.0f64 * (0.0f64 - ll[i] + mx))
            var sgn = 0.0f64
            if bet[i] > f.coef[pos] {
                sgn = 1.0f64
            } else {
                if bet[i] < f.coef[pos] { sgn = 0.0f64 - 1.0f64 }
            }
            let sr = sr0 * sgn
            out[0usize * nn_k + w] = bet[i]
            out[1usize * nn_k + w] = std_v[i]
            out[2usize * nn_k + w] = 2.0f64 * (ll[i] - mx)
            out[3usize * nn_k + w] = ll[i]
            out[4usize * nn_k + w] = sr
            out[5usize * nn_k + w] = dist.pnorm(sr, 0.0f64, 1.0f64, true, false)
            w += 1usize
        }
        i += 1usize
    }
    ret (kept, ok)
}

// PVR.confint: Rubin's rules with the pseudo-variance modification. coef, lo, up are nimp by nvar (column-major); each answer is nvar long
fn pvr_confint(coef: []const f64, lo: []const f64, up: []const f64, nimp: usize, nvar: usize, zalpha: f64, skew: bool, est: []f64, ci_lo: []f64, ci_up: []f64, var_lo: []f64, var_up: []f64) {
    var v = 0usize
    while v < nvar {
        var mean = 0.0f64
        var i = 0usize
        while i < nimp {
            mean += coef[i + v * nimp]
            i += 1usize
        }
        mean = mean / f64(nimp)
        var tail = 0usize
        while tail < 2usize {
            var num = 0.0f64
            var cnt = 0.0f64
            i = 0usize
            while i < nimp {
                let diff = coef[i + v * nimp] - mean
                var inside = true
                if skew {
                    var sg = 0.0f64
                    if diff > 0.0f64 {
                        sg = 1.0f64
                    } else {
                        if diff < 0.0f64 { sg = 0.0f64 - 1.0f64 }
                    }
                    var want = 1.0f64
                    if tail == 0usize { want = 0.0f64 - 1.0f64 }
                    inside = sg == want
                }
                if inside {
                    num += diff * diff
                    cnt += 1.0f64
                }
                i += 1usize
            }
            let pv = num / (cnt - 1.0f64)
            var avg = 0.0f64
            i = 0usize
            while i < nimp {
                var ps = 0.0f64
                if tail == 0usize {
                    ps = (coef[i + v * nimp] - lo[i + v * nimp]) / zalpha
                } else {
                    ps = 0.0f64 - (coef[i + v * nimp] - up[i + v * nimp]) / zalpha
                }
                avg += ps * ps
                i += 1usize
            }
            avg = avg / f64(nimp)
            let rr = avg + (1.0f64 + 1.0f64 / f64(nimp)) * pv
            if tail == 0usize {
                var_lo[v] = rr
                ci_lo[v] = mean - zalpha * sqrt_f(rr)
            } else {
                var_up[v] = rr
                ci_up[v] = mean + zalpha * sqrt_f(rr)
            }
            tail += 1usize
        }
        est[v] = mean
        v += 1usize
    }
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// CLIP.profile and CLIP.confint: the profile penalized likelihood of imputed data sets pooled by averaging the cdf of the signed root

// the imputations: set i has ns[i] rows; xs holds each set's design (rows by k, column-major) one after another, ys and ws their responses
// and weights; betas (nimp by k, row-major: set i at i * k) and logliks are the fits' coefficients and full penalized log-likelihoods
type Clip = struct {
    xs: []const f64, ys: []const f64, ws: []const f64, ns: []const usize, nimp: usize, k: usize, betas: []const f64, logliks: []const f64,
    pos: usize, firth: bool, c: Ctl
}

// the mean over the imputations of the cdf logistf.pdf gives at z
fn clip_f(a: *mem.Arena, cl: Clip, z: f64) -> (f64, err) {
    var s = 0.0f64
    var xo = 0usize
    var ro = 0usize
    var i = 0usize
    while i < cl.nimp {
        let n = cl.ns[i]
        let (off, e0) = take_off(a, n)
        if e0 != ok { ret (0.0f64, e0) }
        let (r, e) = logistf_pdf(a, cl.xs[xo..xo + n * cl.k], n, cl.k, cl.ys[ro..ro + n], cl.ws[ro..ro + n], off, cl.firth, cl.c, cl.pos, z, cl.betas[i * cl.k..i * cl.k + cl.k], cl.logliks[i])
        if e != ok { ret (0.0f64, e) }
        s += r.pdf
        xo += n * cl.k
        ro += n
        i += 1usize
    }
    ret (s / f64(cl.nimp), ok)
}

fn take_off(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, n)
    if e != ok { ret (r, e) }
    fill_f(r, 0.0f64)
    ret (r, ok)
}

// CLIP.profile: z on steps + 1 knots from..to; cdf and the chi-square -qnorm(cdf)^2 are written (steps + 1 each); the knots to zs
fn clip_profile(a: *mem.Arena, cl: Clip, from: f64, to: f64, steps: usize, zs: []f64, cdf: []f64, chisq: []f64) -> err {
    let by = (to - from) / f64(steps)
    var i = 0usize
    while i <= steps {
        var z = from + f64(i) * by
        if by > 0.0f64 && z > to { z = to }
        zs[i] = z
        let (v, e) = clip_f(a, cl, z)
        if e != ok { ret e }
        cdf[i] = v
        let q = dist.qnorm(v, 0.0f64, 1.0f64, true, false)
        chisq[i] = 0.0f64 - q * q
        i += 1usize
    }
    ret ok
}

error NoBracket

// R_zeroin2 (Brent) for the function clip_f(z) - level, given the end values; the root and the iterations
fn zeroin_clip(a: *mem.Arena, cl: Clip, level: f64, ax: f64, bx: f64, fa_in: f64, fb_in: f64, tol: f64, maxit_in: usize) -> (f64, usize, err) {
    var aa = ax
    var bb = bx
    var fa = fa_in
    var fb = fb_in
    var cc = aa
    var fc = fa
    var maxit = maxit_in + 1usize
    if fa == 0.0f64 { ret (aa, 0usize, ok) }
    if fb == 0.0f64 { ret (bb, 0usize, ok) }
    let eps = eps_dbl()
    while maxit > 0usize {
        maxit -= 1usize
        let prev_step = bb - aa
        if math.abs[f64](fc) < math.abs[f64](fb) {
            aa = bb
            bb = cc
            cc = aa
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps * math.abs[f64](bb) + tol / 2.0f64
        var new_step = (cc - bb) / 2.0f64
        if math.abs[f64](new_step) <= tol_act || fb == 0.0f64 {
            ret (bb, maxit_in - maxit, ok)
        }
        if math.abs[f64](prev_step) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = cc - bb
            var p = 0.0f64
            var q = 0.0f64
            if aa == cc {
                let t1 = fb / fa
                p = cb * t1
                q = 1.0f64 - t1
            } else {
                q = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                p = t2 * (cb * q * (q - t1) - (bb - aa) * (t1 - 1.0f64))
                q = (q - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if p > 0.0f64 {
                q = 0.0f64 - q
            } else {
                p = 0.0f64 - p
            }
            if p < (0.75f64 * cb * q - math.abs[f64](tol_act * q) / 2.0f64) && p < math.abs[f64](prev_step * q / 2.0f64) { new_step = p / q }
        }
        if math.abs[f64](new_step) < tol_act {
            if new_step > 0.0f64 {
                new_step = tol_act
            } else {
                new_step = 0.0f64 - tol_act
            }
        }
        aa = bb
        fa = fb
        bb += new_step
        let (v, e) = clip_f(a, cl, bb)
        if e != ok { ret (0.0f64, 0usize, e) }
        fb = v - level
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            cc = aa
            fc = fa
        }
    }
    ret (bb, 0usize, NoBracket)
}

type ClipCi = struct { estimate: f64, ci_lo: f64, ci_up: f64, pvalue: f64, bound_lo0: f64, bound_lo1: f64, bound_up0: f64, bound_up1: f64, iter0: usize, iter1: usize }

// CLIP.confint for the variable cl.pos, the i-th of nvar. The package overwrites its bound.lo and bound.up arguments with nvar by 2 matrices of
// zeros before the first variable is processed, so the bounds the search starts from are the minimum and maximum of those whole matrices (zero
// on the first variable, the earlier variables' final bounds after) and the fits' own limits and a given bound.lo / bound.up are never used.
// m_lo and m_up (nvar by 2, column-major) carry that state and get this variable's row. estimate is the mean coefficient over the imputations
fn clip_confint(a: *mem.Arena, cl: Clip, i: usize, nvar: usize, m_lo: []f64, m_up: []f64, estimate: f64, level0: f64, level1: f64) -> (ClipCi, err) {
    var lo_lo = m_lo[0usize]
    var lo_hi = m_lo[0usize]
    var up_lo = m_up[0usize]
    var up_hi = m_up[0usize]
    var q = 1usize
    while q < 2usize * nvar {
        if m_lo[q] < lo_lo { lo_lo = m_lo[q] }
        if m_lo[q] > lo_hi { lo_hi = m_lo[q] }
        if m_up[q] < up_lo { up_lo = m_up[q] }
        if m_up[q] > up_hi { up_hi = m_up[q] }
        q += 1usize
    }
    if lo_lo == lo_hi {
        lo_lo = lo_lo - 0.5f64
        lo_hi = lo_hi + 0.5f64
    }
    if up_lo == up_hi {
        up_lo = up_lo - 0.5f64
        up_hi = up_hi + 0.5f64
    }
    var res = ClipCi { estimate: estimate, ci_lo: 0.0f64, ci_up: 0.0f64, pvalue: 0.0f64, bound_lo0: 0.0f64, bound_lo1: 0.0f64, bound_up0: 0.0f64, bound_up1: 0.0f64, iter0: 0usize, iter1: 0usize }
    // the lower limit
    let (v1, e1) = clip_f(a, cl, lo_lo)
    if e1 != ok { ret (zero, e1) }
    let (v2, e2) = clip_f(a, cl, lo_hi)
    if e2 != ok { ret (zero, e2) }
    var f_lower = v1 - level0
    var f_upper = v2 - level0
    var iter = 2usize
    var itw = 0usize
    while f_lower > 0.0f64 && (lo_hi - lo_lo) > 0.0f64 && itw < 5usize {
        itw += 1usize
        lo_lo = lo_lo - (lo_hi - lo_lo) / 2.0f64
        let (v, e) = clip_f(a, cl, lo_lo)
        if e != ok { ret (zero, e) }
        f_lower = v - level0
        iter += 1usize
    }
    if itw >= 5usize && f_upper < 0.0f64 { ret (zero, NoBracket) }
    itw = 0usize
    while f_upper < 0.0f64 && (lo_hi - lo_lo) > 0.0f64 && itw < 5usize {
        itw += 1usize
        lo_hi = lo_hi + (lo_hi - lo_lo) / 2.0f64
        let (v, e) = clip_f(a, cl, lo_hi)
        if e != ok { ret (zero, e) }
        f_upper = v - level0
        iter += 1usize
    }
    if itw >= 5usize && f_upper < 0.0f64 { ret (zero, NoBracket) }
    if f_lower * f_upper > 0.0f64 { ret (zero, NoBracket) }
    let (root0, it0, ez0) = zeroin_clip(a, cl, level0, lo_lo, lo_hi, f_lower, f_upper, 1.220703125e-4f64, 1000usize)
    if ez0 != ok { ret (zero, ez0) }
    res.ci_lo = root0
    res.iter0 = iter + it0
    res.bound_lo0 = lo_lo
    res.bound_lo1 = lo_hi
    // the upper limit
    let (w1, e3) = clip_f(a, cl, up_lo)
    if e3 != ok { ret (zero, e3) }
    let (w2, e4) = clip_f(a, cl, up_hi)
    if e4 != ok { ret (zero, e4) }
    f_lower = w1 - level1
    f_upper = w2 - level1
    iter = 2usize
    itw = 0usize
    while f_lower > 0.0f64 && (up_hi - up_lo) > 0.0f64 && itw < 5usize {
        itw += 1usize
        up_lo = up_lo - (up_hi - up_lo) / 2.0f64
        let (v, e) = clip_f(a, cl, up_lo)
        if e != ok { ret (zero, e) }
        f_lower = v - level1
        iter += 1usize
    }
    if itw >= 5usize && f_lower > 0.0f64 { ret (zero, NoBracket) }
    itw = 0usize
    while f_upper < 0.0f64 && (up_hi - up_lo) > 0.0f64 && itw < 5usize {
        itw += 1usize
        up_hi = up_hi + (up_hi - up_lo) / 2.0f64
        let (v, e) = clip_f(a, cl, up_hi)
        if e != ok { ret (zero, e) }
        f_upper = v - level1
        iter += 1usize
    }
    if itw >= 5usize && f_upper < 0.0f64 { ret (zero, NoBracket) }
    if f_lower * f_upper > 0.0f64 { ret (zero, NoBracket) }
    let (root1, it1, ez1) = zeroin_clip(a, cl, level1, up_lo, up_hi, f_lower, f_upper, 1.220703125e-4f64, 1000usize)
    if ez1 != ok { ret (zero, ez1) }
    res.ci_up = root1
    res.iter1 = iter + it1
    res.bound_up0 = up_lo
    res.bound_up1 = up_hi
    let (p1, e5) = clip_f(a, cl, 0.0f64)
    if e5 != ok { ret (zero, e5) }
    var m = p1
    if 1.0f64 - p1 < m { m = 1.0f64 - p1 }
    res.pvalue = 2.0f64 * m
    m_lo[i] = res.bound_lo0
    m_lo[nvar + i] = res.bound_lo1
    m_up[i] = res.bound_up0
    m_up[nvar + i] = res.bound_up1
    ret (res, ok)
}
