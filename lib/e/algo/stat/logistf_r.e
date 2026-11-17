// R logistf (Heinze, Ploner, Jiricka, Steiner), port of the package's C code and R code: Firth's penalized logistic regression with the
// package's own iteration (logistffit_revised and logistffit_IRLS), the profile penalized likelihood limits (logistplfit), the penalized
// likelihood ratio tests (logistftest, anova, add1, drop1, forward, backward), FLIC, FLAC, predict, profile, logistf.pdf and PVR.confint.
//
// A design matrix x is n by k, column-major (as R holds it), the intercept column included when the model has one. y is 0/1. weight and
// offset are n long, or empty for the defaults (ones, zeros). A term is a column here; the selection functions work on subsets of the
// columns of one full design matrix, indexed from 0. The collapse of identical rows (logistf.control(collapse)) is not replayed: the
// weighted fit of the collapsed rows and the fit of the rows agree to rounding, and nothing it changes is observable.
//
// Not here: the multiple-imputation pooling of CLIP.confint and CLIP.profile (they need the imputed data sets and uniroot).

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
    maxit: usize, maxstep: f64, maxhs: usize, lconv: f64, gconv: f64, xconv: f64, irls: bool, tau: f64,
    plmaxit: usize, plmaxstep: f64, plmaxhs: usize, pllconv: f64, plxconv: f64
}

fn ctl_default() -> Ctl {
    ret Ctl {
        maxit: 25usize, maxstep: 5.0f64, maxhs: 0usize, lconv: 1.0e-5f64, gconv: 1.0e-5f64, xconv: 1.0e-5f64, irls: false, tau: 0.5f64,
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
        selcol[q] = colfit[q] - 1usize
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
        selcol[q] = colfit[q] - 1usize
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
fn fit_fit(b: *Bump, x: []const f64, y: []const f64, n: usize, k: usize, weight: []const f64, offset: []const f64, beta: []f64, colfit: []const usize, firth: bool, c: Ctl, var_out: []f64, ustar: []f64, pi: []f64, hdiag: []f64) -> (Core, err) {
    if c.irls {
        let (r1, e1) = fit_irls(b, x, y, n, k, weight, offset, beta, colfit, firth, c, var_out, pi, hdiag)
        ret (r1, e1)
    }
    let (r2, e2) = fit_nr(b, x, y, n, k, weight, offset, beta, colfit, firth, c, var_out, ustar, pi, hdiag)
    ret (r2, e2)
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
    init: []const f64, has_init: bool, flic: bool
}

fn opt_default() -> Opt {
    ret Opt {
        firth: true, pl: true, alpha: 0.05f64, c: ctl_default(), has_int: true,
        plconf: zero, has_plconf: false, terms_fit: zero, has_terms: false,
        init: zero, has_init: false, flic: false
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
    let (b, e) = bump_new(a, 80usize * (n * k + n + k * k + 64usize) + 8192usize, 8usize * k + 256usize)
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
        var restart = 0usize
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
        restart = 0usize
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
