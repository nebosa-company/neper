// R vars beyond the const-only VAR of e.algo.stat.vars: VAR with the deterministic terms none, const, trend and both, seasonal dummies and exogenous regressors,
// VARselect with the four criteria on those models, roots, predict with its confidence bands, irf (orthogonal or not, cumulative, with the bootstrap bands under
// the seed's draws in the order the package consumes them), fevd, the restrictions of restrict (ser and manual), the Blanchard-Quah decomposition, causality
// (Granger, bootstrapped, and instantaneous), and the residual tests serial.test, arch.test and normality.test.
//
// A model is a Var: the data y (t0 by k, row-major), the regressors z (obs by nz: the k p lags, then const, trend, the season - 1 seasonal dummies and the
// exogenous columns, as vars lays them out), the coefficients coef (k by nz, zero where restricted) and the residuals resid (obs by k).
//
// Not here: causality with a custom vcov., and the structural models (e.algo.stat.vars3).

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.stat.carlmtest as cl
use e.algo.stat.vars as v1
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

type Var = struct { k: usize, p: usize, nz: usize, obs: usize, t0: usize, det: usize, season: usize, nexo: usize, y: []f64, exo: []f64, z: []f64, yend: []f64, coef: []f64, resid: []f64, mask: []f64, restricted: bool }

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

fn zeros(a: *mem.Arena, n: usize) -> []f64 {
    let (x, e) = mem.alloc[f64](a, n + 1usize)
    var i = 0usize
    while i < n + 1usize {
        x[i] = 0.0f64
        i += 1usize
    }
    ret x[0usize..n]
}

// x (m by n) times y (n by q), row-major
fn mmul(a: *mem.Arena, x: []const f64, y: []const f64, m: usize, n: usize, q: usize) -> []f64 {
    let c = zeros(a, m * q)
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var l = 0usize
            while l < n {
                s += x[i * n + l] * y[l * q + j]
                l += 1usize
            }
            c[i * q + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret c
}

fn mtr(a: *mem.Arena, x: []const f64, m: usize, n: usize) -> []f64 {
    let c = zeros(a, m * n)
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            c[j * m + i] = x[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    ret c
}

// x' y for x (n by p) and y (n by q): p by q
fn mcross(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, q: usize) -> []f64 {
    let c = zeros(a, p * q)
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += x[t * p + i] * y[t * q + j]
                t += 1usize
            }
            c[i * q + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret c
}

fn minv(a: *mem.Arena, x: []const f64, k: usize) -> []f64 {
    let o = zeros(a, k * k)
    let e = cl.inverse(a, x, k, o)
    ret o
}

fn mdet(a: *mem.Arena, x: []const f64, k: usize) -> f64 {
    let s = zeros(a, k * k)
    ret v1.det_of(x, k, s)
}

fn trace_of(x: []const f64, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += x[i * k + i]
        i += 1usize
    }
    ret s
}

fn ident(a: *mem.Arena, k: usize) -> []f64 {
    let m = zeros(a, k * k)
    var i = 0usize
    while i < k {
        m[i * k + i] = 1.0f64
        i += 1usize
    }
    ret m
}

// the number of columns the deterministic type adds: 0 none, 1 const, 2 trend, 3 both
fn det_cols(det: usize) -> usize {
    if det == 0usize { ret 0usize }
    if det == 3usize { ret 2usize }
    ret 1usize
}

fn season_cols(season: usize) -> usize {
    if season > 0usize { ret season - 1usize }
    ret 0usize
}

// the seasonal dummy of period position pos for column q: (indicator - 1 / season)
fn season_value(pos: usize, q: usize, season: usize) -> f64 {
    var v = 0.0f64 - 1.0f64 / f64(season)
    if pos % season == q { v = 1.0f64 - 1.0f64 / f64(season) }
    ret v
}

// lm.fit of y on the columns `cols` of z (obs by nz, row-major): coef[cols[j]] = beta_j (the others 0) and the residuals
fn ols_cols(a: *mem.Arena, z: []const f64, obs: usize, nz: usize, cols: []const usize, nsel: usize, y: []const f64, coef: []f64, resid: []f64) -> err {
    let x = zeros(a, obs * nsel)
    var j = 0usize
    while j < nsel {
        var t = 0usize
        while t < obs {
            x[j * obs + t] = z[t * nz + cols[j]]
            t += 1usize
        }
        j += 1usize
    }
    let (f, e) = decomp.lm_fit(a, x, obs, nsel, y, 1.0e-7f64)
    if e != ok { ret e }
    j = 0usize
    while j < nz {
        coef[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < nsel {
        coef[cols[j]] = f.coef[j]
        j += 1usize
    }
    var t = 0usize
    while t < obs {
        resid[t] = f.residuals[t]
        t += 1usize
    }
    ret ok
}

// (x'x)^-1 of x (n by p, column-major) from the R factor of its QR, written row-major in out
fn xtx_inverse_cm(a: *mem.Arena, x: []const f64, n: usize, p: usize, out: []f64) -> err {
    let (f, e) = decomp.qr(a, x, n, p, 1.0e-7f64)
    if e != ok { ret e }
    let ri = zeros(a, p * p)
    // R is upper triangular in f.qr (column-major, leading dimension n); ri = R^-1 by back substitution
    var c = 0usize
    while c < p {
        // column c of R^-1: solve R x = e_c
        var i = c + 1usize
        while i > 0usize {
            i -= 1usize
            var s = 0.0f64
            if i == c { s = 1.0f64 }
            var l = i + 1usize
            while l <= c {
                s -= f.qr[l * n + i] * ri[l * p + c]
                l += 1usize
            }
            ri[i * p + c] = s / f.qr[i * n + i]
        }
        c += 1usize
    }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var l = 0usize
            while l < p {
                s += ri[i * p + l] * ri[j * p + l]
                l += 1usize
            }
            out[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// (x'x)^-1 over the columns `cols` of z (obs by nz row-major), row-major nsel by nsel
fn xtx_inverse_cols(a: *mem.Arena, z: []const f64, obs: usize, nz: usize, cols: []const usize, nsel: usize, out: []f64) -> err {
    let x = zeros(a, obs * nsel)
    var j = 0usize
    while j < nsel {
        var t = 0usize
        while t < obs {
            x[j * obs + t] = z[t * nz + cols[j]]
            t += 1usize
        }
        j += 1usize
    }
    ret xtx_inverse_cm(a, x, obs, nsel, out)
}

// the column indices of the equation i of a model whose mask row marks the free coefficients; returns the count
fn eq_cols(v: *const Var, i: usize, cols: []usize) -> usize {
    var n = 0usize
    var c = 0usize
    while c < v.nz {
        if v.mask[i * v.nz + c] != 0.0f64 {
            cols[n] = c
            n += 1usize
        }
        c += 1usize
    }
    ret n
}

// fit every equation by least squares on its free columns
fn var_fit_eqs(a: *mem.Arena, v: *Var) -> err {
    let cols = zeros_usize(a, v.nz)
    let yy = zeros(a, v.obs)
    let cf = zeros(a, v.nz)
    let rs = zeros(a, v.obs)
    var i = 0usize
    while i < v.k {
        let n = eq_cols(v, i, cols)
        var t = 0usize
        while t < v.obs {
            yy[t] = v.yend[t * v.k + i]
            t += 1usize
        }
        let e = ols_cols(a, v.z, v.obs, v.nz, cols, n, yy, cf, rs)
        if e != ok { ret e }
        var c = 0usize
        while c < v.nz {
            v.coef[i * v.nz + c] = cf[c]
            c += 1usize
        }
        t = 0usize
        while t < v.obs {
            v.resid[t * v.k + i] = rs[t]
            t += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn zeros_usize(a: *mem.Arena, n: usize) -> []usize {
    let (x, e) = mem.alloc[usize](a, n + 1usize)
    var i = 0usize
    while i < n + 1usize {
        x[i] = 0usize
        i += 1usize
    }
    ret x[0usize..n]
}

// VAR(y, p, type, season, exogen): y is t0 by k, exo t0 by nexo (empty when nexo is 0); det 0 none, 1 const, 2 trend, 3 both; season 0 for none
fn var_new(a: *mem.Arena, y: []const f64, t0: usize, k: usize, p: usize, det: usize, season: usize, exo: []const f64, nexo: usize) -> (Var, err) {
    var v: Var = zero
    let obs = t0 - p
    let nd = det_cols(det)
    let ns = season_cols(season)
    let nz = k * p + nd + ns + nexo
    v.k = k
    v.p = p
    v.nz = nz
    v.obs = obs
    v.t0 = t0
    v.det = det
    v.season = season
    v.nexo = nexo
    v.y = zeros(a, t0 * k)
    v.exo = zeros(a, t0 * nexo)
    var i = 0usize
    while i < t0 * k {
        v.y[i] = y[i]
        i += 1usize
    }
    i = 0usize
    while i < t0 * nexo {
        v.exo[i] = exo[i]
        i += 1usize
    }
    v.z = zeros(a, obs * nz)
    v.yend = zeros(a, obs * k)
    v.coef = zeros(a, k * nz)
    v.resid = zeros(a, obs * k)
    v.mask = zeros(a, k * nz)
    i = 0usize
    while i < k * nz {
        v.mask[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < obs {
        let t = p + i
        var l = 0usize
        while l < p {
            var j = 0usize
            while j < k {
                v.z[i * nz + l * k + j] = y[(t - 1usize - l) * k + j]
                j += 1usize
            }
            l += 1usize
        }
        var c = k * p
        if det == 1usize || det == 3usize {
            v.z[i * nz + c] = 1.0f64
            c += 1usize
        }
        if det >= 2usize {
            v.z[i * nz + c] = f64(t + 1usize)
            c += 1usize
        }
        var q = 0usize
        while q < ns {
            v.z[i * nz + c] = season_value(t, q, season)
            c += 1usize
            q += 1usize
        }
        q = 0usize
        while q < nexo {
            v.z[i * nz + c] = exo[t * nexo + q]
            c += 1usize
            q += 1usize
        }
        var j = 0usize
        while j < k {
            v.yend[i * k + j] = y[t * k + j]
            j += 1usize
        }
        i += 1usize
    }
    let e = var_fit_eqs(a, &v)
    ret (v, e)
}

// a copy of the model that can be re-fitted under another mask without touching the original
fn var_copy(a: *mem.Arena, v: *const Var) -> Var {
    var w: Var = zero
    w.k = v.k
    w.p = v.p
    w.nz = v.nz
    w.obs = v.obs
    w.t0 = v.t0
    w.det = v.det
    w.season = v.season
    w.nexo = v.nexo
    w.y = v.y
    w.exo = v.exo
    w.z = v.z
    w.yend = v.yend
    w.restricted = v.restricted
    w.mask = zeros(a, v.k * v.nz)
    w.coef = zeros(a, v.k * v.nz)
    w.resid = zeros(a, v.obs * v.k)
    var i = 0usize
    while i < v.k * v.nz {
        w.mask[i] = v.mask[i]
        w.coef[i] = v.coef[i]
        i += 1usize
    }
    i = 0usize
    while i < v.obs * v.k {
        w.resid[i] = v.resid[i]
        i += 1usize
    }
    ret w
}

// the residual cross products crossprod(resid) / divisor (k by k)
fn resid_cov(a: *mem.Arena, resid: []const f64, obs: usize, k: usize, divisor: f64) -> []f64 {
    let s = mcross(a, resid, resid, obs, k, k)
    var i = 0usize
    while i < k * k {
        s[i] = s[i] / divisor
        i += 1usize
    }
    ret s
}

// the residual degrees of freedom of equation i: obs minus its free coefficients
fn eq_df(v: *const Var, i: usize) -> f64 {
    var n = 0usize
    var c = 0usize
    while c < v.nz {
        if v.mask[i * v.nz + c] != 0.0f64 { n += 1usize }
        c += 1usize
    }
    ret f64(v.obs - n)
}

// VARselect(y, lag.max, type, season, exogen)$criteria: crit[c * lag_max + (i - 1)] with c 0 AIC, 1 HQ, 2 SC, 3 FPE
fn var_select(a: *mem.Arena, y: []const f64, t0: usize, k: usize, lag_max: usize, det: usize, season: usize, exo: []const f64, nexo: usize, crit: []f64) -> err {
    let sample = t0 - lag_max
    let nd = det_cols(det)
    let ns = season_cols(season)
    let detint = nd + ns + nexo
    let w = k * lag_max + detint
    let z = zeros(a, sample * w)
    var i = 0usize
    while i < sample {
        let t = lag_max + i
        var l = 0usize
        while l < lag_max {
            var j = 0usize
            while j < k {
                z[i * w + l * k + j] = y[(t - 1usize - l) * k + j]
                j += 1usize
            }
            l += 1usize
        }
        var c = k * lag_max
        if det == 1usize || det == 3usize {
            z[i * w + c] = 1.0f64
            c += 1usize
        }
        if det >= 2usize {
            z[i * w + c] = f64(t + 1usize)
            c += 1usize
        }
        var q = 0usize
        while q < ns {
            z[i * w + c] = season_value(i, q, season)
            c += 1usize
            q += 1usize
        }
        q = 0usize
        while q < nexo {
            z[i * w + c] = exo[t * nexo + q]
            c += 1usize
            q += 1usize
        }
        i += 1usize
    }
    let cols = zeros_usize(a, w)
    let yy = zeros(a, sample)
    let cf = zeros(a, w)
    let rs = zeros(a, sample)
    let res = zeros(a, sample * k)
    var lag = 1usize
    while lag <= lag_max {
        let nsel = lag * k + detint
        var c = 0usize
        while c < lag * k {
            cols[c] = c
            c += 1usize
        }
        var d = 0usize
        while d < detint {
            cols[lag * k + d] = k * lag_max + d
            d += 1usize
        }
        var j = 0usize
        while j < k {
            var t = 0usize
            while t < sample {
                yy[t] = y[(lag_max + t) * k + j]
                t += 1usize
            }
            let e = ols_cols(a, z, sample, w, cols, nsel, yy, cf, rs)
            if e != ok { ret e }
            t = 0usize
            while t < sample {
                res[t * k + j] = rs[t]
                t += 1usize
            }
            j += 1usize
        }
        let sg = resid_cov(a, res, sample, k, f64(sample))
        let dt = mdet(a, sg, k)
        let tt = f64(sample)
        let npar = f64(lag * k * k + k * detint)
        crit[lag - 1usize] = math.log[f64](dt) + 2.0f64 / tt * npar
        crit[lag_max + lag - 1usize] = math.log[f64](dt) + 2.0f64 * math.log[f64](math.log[f64](tt)) / tt * npar
        crit[2usize * lag_max + lag - 1usize] = math.log[f64](dt) + math.log[f64](tt) / tt * npar
        let ns2 = f64(nsel)
        crit[3usize * lag_max + lag - 1usize] = math.pow[f64]((tt + ns2) / (tt - ns2), f64(k)) * dt
        lag += 1usize
    }
    ret ok
}

// VARselect(...)$selection: the 1-based lag minimising criterion c (first on ties, as which.min)
fn var_selection(crit: []const f64, lag_max: usize, c: usize) -> usize {
    var best = 0usize
    var i = 1usize
    while i < lag_max {
        if crit[c * lag_max + i] < crit[c * lag_max + best] { best = i }
        i += 1usize
    }
    ret best + 1usize
}

// the k by k lag matrices stacked: A_l[i][m] = coef[i nz + l k + m]; the moduli of the eigenvalues of the companion matrix, decreasing, as roots(x)
fn var_roots(a: *mem.Arena, v: *const Var, out: []f64) -> err {
    let kp = v.k * v.p
    // column-major companion for the eigen routine
    let cm = zeros(a, kp * kp)
    var i = 0usize
    while i < v.k {
        var c = 0usize
        while c < kp {
            cm[c * kp + i] = v.coef[i * v.nz + c]
            c += 1usize
        }
        i += 1usize
    }
    i = v.k
    var j = 0usize
    while i < kp {
        cm[j * kp + i] = 1.0f64
        j += 1usize
        i += 1usize
    }
    let (ev, e) = decomp.eigen(a, cm, kp)
    if e != ok { ret e }
    i = 0usize
    while i < kp {
        out[i] = decomp.cabs(ev.re[i], ev.im[i])
        i += 1usize
    }
    // decreasing order
    i = 1usize
    while i < kp {
        let x = out[i]
        var q = i
        while q > 0usize && out[q - 1usize] < x {
            out[q] = out[q - 1usize]
            q -= 1usize
        }
        out[q] = x
        i += 1usize
    }
    ret ok
}

// Phi_0 .. Phi_h (k by k each) of the model's lag matrices
fn var_phi_all(v: *const Var, h: usize, phi: []f64) {
    let k = v.k
    var i = 0usize
    while i < (h + 1usize) * k * k {
        phi[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        phi[i * k + i] = 1.0f64
        i += 1usize
    }
    var s = 1usize
    while s <= h {
        i = 0usize
        while i < k {
            var j = 0usize
            while j < k {
                var t = 0.0f64
                var l = 1usize
                while l <= v.p && l <= s {
                    var m = 0usize
                    while m < k {
                        t += v.coef[i * v.nz + (l - 1usize) * k + m] * phi[(s - l) * k * k + m * k + j]
                        m += 1usize
                    }
                    l += 1usize
                }
                phi[s * k * k + i * k + j] = t
                j += 1usize
            }
            i += 1usize
        }
        s += 1usize
    }
}

// Psi_s = Phi_s P with P the lower Cholesky factor of crossprod(resid) / (obs - nz), as Psi.varest; false when that is not positive definite
fn var_psi_all(a: *mem.Arena, v: *const Var, h: usize, out: []f64) -> bool { ret var_psi_div(a, v, h, f64(v.obs - v.nz), out) }

// Psi with the residual covariance divided by `divisor` (Psi.vec2var divides by obs)
fn var_psi_div(a: *mem.Arena, v: *const Var, h: usize, divisor: f64, out: []f64) -> bool {
    let k = v.k
    let phi = zeros(a, (h + 1usize) * k * k)
    var_phi_all(v, h, phi)
    let sg = resid_cov(a, v.resid, v.obs, k, divisor)
    let pc = zeros(a, k * k)
    if !v1.var_chol(sg, k, pc) { ret false }
    v1.var_oirf(phi, pc, k, h, out)
    ret true
}

// irf(x, ortho, cumulative, boot = FALSE): out holds Theta_s (s = 0 ..= h) as k by k blocks, [s][response][impulse]
fn var_irf(a: *mem.Arena, v: *const Var, h: usize, ortho: bool, cumulative: bool, out: []f64) -> bool {
    let k = v.k
    if ortho {
        if !var_psi_all(a, v, h, out) { ret false }
    } else {
        var_phi_all(v, h, out)
    }
    if cumulative {
        var s = 1usize
        while s <= h {
            var q = 0usize
            while q < k * k {
                out[s * k * k + q] += out[(s - 1usize) * k * k + q]
                q += 1usize
            }
            s += 1usize
        }
    }
    ret true
}

// quantile(x, p) type 7 of n values; x is sorted in place
fn quantile7(x: []f64, n: usize, p: f64) -> f64 {
    var i = 1usize
    while i < n {
        let t = x[i]
        var q = i
        while q > 0usize && x[q - 1usize] > t {
            x[q] = x[q - 1usize]
            q -= 1usize
        }
        x[q] = t
        i += 1usize
    }
    let index = 1.0f64 + f64(n - 1usize) * p
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    let l = usize(lo) - 1usize
    let hh = usize(hi) - 1usize
    var qs = x[l]
    if index > lo && x[hh] != qs {
        let h = index - lo
        qs = (1.0f64 - h) * qs + h * x[hh]
    }
    ret qs
}

// the resampled data of the bootstrap of vars:::.boot for the draw `booted` (1-based rows of the centred residuals): ys is t0 by k
fn boot_series(v: *const Var, resorig: []const f64, booted: []const i64, ys: []f64) {
    let k = v.k
    let p = v.p
    var i = 0usize
    while i < p * k {
        ys[i] = v.y[i]
        i += 1usize
    }
    var j = 0usize
    while j < v.obs {
        let t = p + j
        var q = 0usize
        while q < k {
            var s = 0.0f64
            var l = 0usize
            while l < p {
                var m = 0usize
                while m < k {
                    s += v.coef[q * v.nz + l * k + m] * ys[(t - 1usize - l) * k + m]
                    m += 1usize
                }
                l += 1usize
            }
            var c = k * p
            while c < v.nz {
                s += v.coef[q * v.nz + c] * v.z[j * v.nz + c]
                c += 1usize
            }
            let r = resorig[(usize(booted[j]) - 1usize) * k + q]
            ys[t * k + q] = s + r
            q += 1usize
        }
        j += 1usize
    }
}

// irf(x, boot = TRUE, runs, ci, seed): the (1 - ci) / 2 and (1 + ci) / 2 bootstrap quantiles of every response, same layout as var_irf
fn var_irf_boot(a: *mem.Arena, v: *const Var, h: usize, ortho: bool, cumulative: bool, runs: usize, ci: f64, seed: i64, lower: []f64, upper: []f64) -> err {
    let k = v.k
    let blk = (h + 1usize) * k * k
    let store = zeros(a, runs * blk)
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let resorig = zeros(a, v.obs * k)
    var j = 0usize
    while j < k {
        var m = 0.0f64
        var t = 0usize
        while t < v.obs {
            m += v.resid[t * k + j]
            t += 1usize
        }
        m = m / f64(v.obs)
        t = 0usize
        while t < v.obs {
            resorig[t * k + j] = v.resid[t * k + j] - m
            t += 1usize
        }
        j += 1usize
    }
    var run = 0usize
    while run < runs {
        let start = mem.mark(a)
        let (booted, se) = rng.sample_int(a, &rg, i64(v.obs), i64(v.obs), true)
        if se != ok { ret se }
        let ys = zeros(a, v.t0 * k)
        boot_series(v, resorig, booted, ys)
        let (vb, ne) = var_new(a, ys, v.t0, k, v.p, v.det, v.season, v.exo, v.nexo)
        if ne != ok { ret ne }
        let tmp = zeros(a, blk)
        if !var_irf(a, &vb, h, ortho, cumulative, tmp) { ret rng.TooLarge }
        var q = 0usize
        while q < blk {
            store[run * blk + q] = tmp[q]
            q += 1usize
        }
        mem.reset(a, start)
        run += 1usize
    }
    let col = zeros(a, runs)
    var q = 0usize
    while q < blk {
        run = 0usize
        while run < runs {
            col[run] = store[run * blk + q]
            run += 1usize
        }
        lower[q] = quantile7(col, runs, (1.0f64 - ci) / 2.0f64)
        upper[q] = quantile7(col, runs, 1.0f64 - (1.0f64 - ci) / 2.0f64)
        q += 1usize
    }
    ret ok
}

// .fecov: the forecast error covariances Sigma_yh[i] (i = 1 ..= h, k by k each): sigma_u / df of the equation row, plus the Phi terms
fn var_fecov(a: *mem.Arena, v: *const Var, h: usize, out: []f64) {
    let k = v.k
    let cp = mcross(a, v.resid, v.resid, v.obs, k, k)
    let sg = zeros(a, k * k)
    var i = 0usize
    while i < k {
        let d = eq_df(v, i)
        var j = 0usize
        while j < k {
            sg[i * k + j] = cp[i * k + j] / d
            j += 1usize
        }
        i += 1usize
    }
    fecov_sigma(a, v, sg, h, out)
}

// Sigma_yh[i] = sg + sum_{j = 1 ..< i} Phi_j sg Phi_j' for i = 1 ..= h, for the Phi of the model's lag matrices
fn fecov_sigma(a: *mem.Arena, v: *const Var, sg: []const f64, h: usize, out: []f64) {
    let k = v.k
    let phi = zeros(a, (h + 1usize) * k * k)
    var_phi_all(v, h, phi)
    var n = 1usize
    while n <= h {
        let acc = zeros(a, k * k)
        var jj = 1usize
        while jj < n {
            let pj = phi[jj * k * k..(jj + 1usize) * k * k]
            let t1 = mmul(a, pj, sg, k, k, k)
            let pt = mtr(a, pj, k, k)
            let t2 = mmul(a, t1, pt, k, k, k)
            var q = 0usize
            while q < k * k {
                acc[q] += t2[q]
                q += 1usize
            }
            jj += 1usize
        }
        var q = 0usize
        while q < k * k {
            out[(n - 1usize) * k * k + q] = acc[q] + sg[q]
            q += 1usize
        }
        n += 1usize
    }
}

// predict(x, n.ahead = h, ci, dumvar = exo_future): fc and half (the CI column) are h by k; exo_future is h by nexo
fn var_predict(a: *mem.Arena, v: *const Var, h: usize, ci: f64, exo_future: []const f64, fc: []f64, half: []f64) {
    let k = v.k
    let p = v.p
    let sig = zeros(a, h * k * k)
    var_fecov(a, v, h, sig)
    let zq = 0.0f64 - nm_qnorm((1.0f64 - ci) / 2.0f64)
    var i = 0usize
    while i < h {
        var j = 0usize
        while j < k {
            half[i * k + j] = zq * math.sqrt[f64](sig[i * k * k + j * k + j])
            j += 1usize
        }
        i += 1usize
    }
    let hist = zeros(a, (p + h) * k)
    i = 0usize
    while i < p {
        var j = 0usize
        while j < k {
            hist[i * k + j] = v.y[(v.t0 - p + i) * k + j]
            j += 1usize
        }
        i += 1usize
    }
    let nd = det_cols(v.det)
    let ns = season_cols(v.season)
    var s = 0usize
    while s < h {
        let row = p + s
        // the deterministic row for the observation t0 + s (0-based)
        var j = 0usize
        while j < k {
            var val = 0.0f64
            var l = 0usize
            while l < p {
                var c = 0usize
                while c < k {
                    val += v.coef[j * v.nz + l * k + c] * hist[(row - 1usize - l) * k + c]
                    c += 1usize
                }
                l += 1usize
            }
            var c = k * p
            if v.det == 1usize || v.det == 3usize {
                val += v.coef[j * v.nz + c]
                c += 1usize
            }
            if v.det >= 2usize {
                val += v.coef[j * v.nz + c] * f64(v.t0 + s + 1usize)
                c += 1usize
            }
            var q = 0usize
            while q < ns {
                val += v.coef[j * v.nz + c] * season_value(v.t0 + s, q, v.season)
                c += 1usize
                q += 1usize
            }
            q = 0usize
            while q < v.nexo {
                val += v.coef[j * v.nz + c] * exo_future[s * v.nexo + q]
                c += 1usize
                q += 1usize
            }
            hist[row * k + j] = val
            fc[s * k + j] = val
            j += 1usize
        }
        s += 1usize
    }
}

fn nm_qnorm(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }

// |t| of the coefficients of equation i fitted on the columns `cols` (nsel of them): out[j] for cols[j]
fn eq_abs_t(a: *mem.Arena, v: *const Var, i: usize, cols: []const usize, nsel: usize, out: []f64) -> err {
    let yy = zeros(a, v.obs)
    var t = 0usize
    while t < v.obs {
        yy[t] = v.yend[t * v.k + i]
        t += 1usize
    }
    let cf = zeros(a, v.nz)
    let rs = zeros(a, v.obs)
    let e = ols_cols(a, v.z, v.obs, v.nz, cols, nsel, yy, cf, rs)
    if e != ok { ret e }
    let inv = zeros(a, nsel * nsel)
    let e2 = xtx_inverse_cols(a, v.z, v.obs, v.nz, cols, nsel, inv)
    if e2 != ok { ret e2 }
    var rss = 0.0f64
    t = 0usize
    while t < v.obs {
        rss += rs[t] * rs[t]
        t += 1usize
    }
    let s2 = rss / f64(v.obs - nsel)
    var j = 0usize
    while j < nsel {
        out[j] = math.abs[f64](cf[cols[j]] / math.sqrt[f64](s2 * inv[j * nsel + j]))
        j += 1usize
    }
    ret ok
}

error NoRegressors

// restrict(x, method = "ser", thresh): drop, equation by equation, the regressor with the smallest |t| until every |t| reaches thresh
fn var_restrict_ser(a: *mem.Arena, v: *Var, thresh: f64) -> err {
    let nz = v.nz
    let cols = zeros_usize(a, nz)
    let tv = zeros(a, nz)
    var i = 0usize
    while i < v.k {
        var nsel = nz
        var c = 0usize
        while c < nz {
            cols[c] = c
            c += 1usize
        }
        var e = eq_abs_t(a, v, i, cols, nsel, tv)
        if e != ok { ret e }
        var go = true
        while go {
            var mn = tv[0usize]
            var at = 0usize
            var j = 1usize
            while j < nsel {
                if tv[j] < mn {
                    mn = tv[j]
                    at = j
                }
                j += 1usize
            }
            if mn >= thresh {
                go = false
            } else {
                if nsel > 1usize {
                    j = at
                    while j + 1usize < nsel {
                        cols[j] = cols[j + 1usize]
                        j += 1usize
                    }
                    nsel -= 1usize
                    e = eq_abs_t(a, v, i, cols, nsel, tv)
                    if e != ok { ret e }
                } else {
                    ret NoRegressors
                }
            }
        }
        c = 0usize
        while c < nz {
            v.mask[i * nz + c] = 0.0f64
            c += 1usize
        }
        c = 0usize
        while c < nsel {
            v.mask[i * nz + cols[c]] = 1.0f64
            c += 1usize
        }
        i += 1usize
    }
    v.restricted = true
    ret var_fit_eqs(a, v)
}

// restrict(x, method = "manual", resmat): resmat is k by nz with 1 for a free coefficient
fn var_restrict_manual(a: *mem.Arena, v: *Var, resmat: []const f64) -> err {
    var q = 0usize
    while q < v.k * v.nz {
        v.mask[q] = resmat[q]
        q += 1usize
    }
    v.restricted = true
    ret var_fit_eqs(a, v)
}

// summary(x)$covres: cov(resid) (centred) times (obs - 1) / (obs - nz)
fn var_covres(a: *mem.Arena, v: *const Var) -> []f64 {
    let k = v.k
    let c = zeros(a, v.obs * k)
    var j = 0usize
    while j < k {
        var m = 0.0f64
        var t = 0usize
        while t < v.obs {
            m += v.resid[t * k + j]
            t += 1usize
        }
        m = m / f64(v.obs)
        t = 0usize
        while t < v.obs {
            c[t * k + j] = v.resid[t * k + j] - m
            t += 1usize
        }
        j += 1usize
    }
    ret resid_cov(a, c, v.obs, k, f64(v.obs - v.nz))
}

// logLik(x): -(obs k / 2) log(2 pi) - (obs / 2) log det(Sigma) - (1 / 2) sum of u_t' Sigma^-1 u_t with Sigma = crossprod(resid) / obs
fn var_loglik(a: *mem.Arena, v: *const Var) -> f64 {
    let k = v.k
    let n = f64(v.obs)
    let sg = resid_cov(a, v.resid, v.obs, k, n)
    let inv = minv(a, sg, k)
    let cp = mcross(a, v.resid, v.resid, v.obs, k, k)
    var q = 0.0f64
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            q += inv[i * k + j] * cp[i * k + j]
            j += 1usize
        }
        i += 1usize
    }
    ret 0.0f64 - n * f64(k) / 2.0f64 * math.log[f64](2.0f64 * 3.141592653589793f64) - n / 2.0f64 * math.log[f64](mdet(a, sg, k)) - 0.5f64 * q
}

// fevd(x, n.ahead = h): out[(n - 1) k k + i k + m] is the share of series i's n-step error variance due to the shock m (fevd.varest, which divides by
// the diagonal of .fecov); false when the residual covariance is not positive definite
fn var_fevd_r(a: *mem.Arena, v: *const Var, h: usize, out: []f64) -> bool {
    let k = v.k
    let psi = zeros(a, (h + 1usize) * k * k)
    if !var_psi_all(a, v, h, psi) { ret false }
    let msey = zeros(a, h * k * k)
    var_fecov(a, v, h, msey)
    fevd_shares(psi, msey, k, h, out)
    ret true
}

// the fevd loop of vars: out[(n - 1) k k + i k + m] = sum_{j < n} theta_j[i][m]^2 / mse_n[i][i], theta the blocks (h + 1) of responses, msey the h forecast
// error covariances
fn fevd_shares(psi: []const f64, msey: []const f64, k: usize, h: usize, out: []f64) {
    var n = 1usize
    while n <= h {
        var i = 0usize
        while i < k {
            var m = 0usize
            while m < k {
                var s = 0.0f64
                var j = 0usize
                while j < n {
                    let t = psi[j * k * k + i * k + m]
                    s += t * t
                    j += 1usize
                }
                out[(n - 1usize) * k * k + i * k + m] = s / msey[(n - 1usize) * k * k + i * k + i]
                m += 1usize
            }
            i += 1usize
        }
        n += 1usize
    }
}
