// R bayesm: the log densities and the samplers that draw with R's own streams, equal to the package under set.seed.
//
// lndMvn, lndMvst, lndIWishart, lndIChisq, llmnl, condMom; rdirichlet, rtrun, rwishart, breg.
// Matrices are column-major as R passes them.
//
// Not here: the Gibbs samplers (runiregGibbs, rmultireg, rhierMnlRwMixture and the rest), mixture helpers, llmnp, ghkvec.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.math
use e.math.dist as mdist
use e.math.nmath as nm
use e.mem

fn ln_2pi() -> f64 { ret 1.8378770664093453f64 }

// the upper Cholesky factor U (A = U'U) of the k by k column-major A into u (strictly lower part zero); false when A is not positive definite
fn chol_upper(a: []const f64, k: usize, u: []f64) -> bool {
    var j = 0usize
    while j < k {
        var i = 0usize
        while i < k {
            u[j * k + i] = 0.0f64
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < k {
        var s = a[j * k + j]
        var t = 0usize
        while t < j {
            s -= u[j * k + t] * u[j * k + t]
            t += 1usize
        }
        if s <= 0.0f64 { ret false }
        let d = math.sqrt[f64](s)
        u[j * k + j] = d
        var c = j + 1usize
        while c < k {
            var v = a[c * k + j]
            t = 0usize
            while t < j {
                v -= u[j * k + t] * u[c * k + t]
                t += 1usize
            }
            u[c * k + j] = v / d
            c += 1usize
        }
        j += 1usize
    }
    ret true
}

// the inverse of the upper-triangular u (k by k column-major) into inv
fn inv_upper(u: []const f64, k: usize, inv: []f64) {
    var c = 0usize
    while c < k {
        var r = k
        while r > 0usize {
            r -= 1usize
            var s = 0.0f64
            if r == c { s = 1.0f64 }
            var t = r + 1usize
            while t < k {
                s -= u[t * k + r] * inv[c * k + t]
                t += 1usize
            }
            inv[c * k + r] = s / u[r * k + r]
        }
        c += 1usize
    }
}

// the sum of the logs of the diagonal
fn log_diag(m: []const f64, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += math.log[f64](m[i * k + i])
        i += 1usize
    }
    ret s
}

// z = t(rooti) (x - mu) for the upper-triangular rooti
fn rooti_z(x: []const f64, mu: []const f64, rooti: []const f64, k: usize, z: []f64) -> f64 {
    var ss = 0.0f64
    var i = 0usize
    while i < k {
        var s = 0.0f64
        var t = 0usize
        while t <= i {
            s += rooti[i * k + t] * (x[t] - mu[t])
            t += 1usize
        }
        z[i] = s
        ss += s * s
        i += 1usize
    }
    ret ss
}

// lndMvn(x, mu, rooti)
fn lnd_mvn(a: *mem.Arena, x: []const f64, mu: []const f64, rooti: []const f64, k: usize) -> f64 {
    let (z, e) = mem.alloc[f64](a, k)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let ss = rooti_z(x, mu, rooti, k, z)
    ret 0.0f64 - f64(k) / 2.0f64 * ln_2pi() + log_diag(rooti, k) - 0.5f64 * ss
}

// lndMvst(x, nu, mu, rooti, NORMC)
fn lnd_mvst(a: *mem.Arena, x: []const f64, nu: f64, mu: []const f64, rooti: []const f64, k: usize, normc: bool) -> f64 {
    let (z, e) = mem.alloc[f64](a, k)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let ss = rooti_z(x, mu, rooti, k, z)
    let kk = f64(k)
    var d = 0.0f64 - (nu + kk) / 2.0f64 * math.log[f64](nu + ss) + log_diag(rooti, k)
    if normc { d += nu / 2.0f64 * math.log[f64](nu) + nm.lgammafn((nu + kk) / 2.0f64) - nm.lgammafn(nu / 2.0f64) - kk / 2.0f64 * math.log[f64](3.141592653589793f64) }
    ret d
}

fn log_mv_gamma(av: f64, k: usize) -> f64 {
    var s = f64(k) * (f64(k) - 1.0f64) / 4.0f64 * math.log[f64](3.141592653589793f64)
    var i = 0usize
    while i < k {
        s += nm.lgammafn(av - f64(i) / 2.0f64)
        i += 1usize
    }
    ret s
}

fn log_det_chol(u: []const f64, k: usize) -> f64 { ret 2.0f64 * log_diag(u, k) }

// lndIWishart(nu, V, IW): the log density of the inverse Wishart matrix IW with scale V
fn lnd_iwishart(a: *mem.Arena, nu: f64, v: []const f64, iw: []const f64, k: usize) -> f64 {
    let (uv, e1) = mem.alloc[f64](a, k * k)
    let (ui, e2) = mem.alloc[f64](a, k * k)
    let (rinv, e3) = mem.alloc[f64](a, k * k)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    if !chol_upper(v, k, uv) || !chol_upper(iw, k, ui) { ret 0.0f64 / 0.0f64 }
    inv_upper(ui, k, rinv)
    // tr(V IW^-1) = sum of squares of (chol(V) rinv)
    var tr = 0.0f64
    var c = 0usize
    while c < k {
        var r = 0usize
        while r < k {
            var s = 0.0f64
            var t = 0usize
            while t < k {
                s += uv[t * k + r] * rinv[c * k + t]
                t += 1usize
            }
            tr += s * s
            r += 1usize
        }
        c += 1usize
    }
    let kk = f64(k)
    ret nu / 2.0f64 * log_det_chol(uv, k) - nu * kk / 2.0f64 * 0.6931471805599453f64 - log_mv_gamma(nu / 2.0f64, k) - (nu + kk + 1.0f64) / 2.0f64 * log_det_chol(ui, k) - 0.5f64 * tr
}

// lndIChisq(nu, ssq, x)
fn lnd_ichisq(nu: f64, ssq: f64, x: f64) -> f64 {
    ret nu / 2.0f64 * math.log[f64](nu * ssq / 2.0f64) - nm.lgammafn(nu / 2.0f64) - (nu / 2.0f64 + 1.0f64) * math.log[f64](x) - nu * ssq / (2.0f64 * x)
}

// llmnl(beta, y, X): the multinomial logit log likelihood, X stacked n blocks of p rows by k columns (column-major, n p rows), y the 1-based choices
fn llmnl(beta: []const f64, y: []const f64, x: []const f64, k: usize, p: usize) -> f64 {
    let n = y.len
    var ll = 0.0f64
    var i = 0usize
    while i < n {
        var denom = 0.0f64
        var num = 0.0f64
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var c = 0usize
            while c < k {
                s += x[c * n * p + i * p + j] * beta[c]
                c += 1usize
            }
            let e = math.exp[f64](s)
            denom += e
            if usize(y[i]) == j + 1usize { num = s }
            j += 1usize
        }
        ll += num - math.log[f64](denom)
        i += 1usize
    }
    ret ll
}

// condMom(x, mu, sigi, i): the conditional mean and variance of x[i] (0-based) given the rest under the precision sigi
fn cond_mom(x: []const f64, mu: []const f64, sigi: []const f64, k: usize, i: usize) -> (f64, f64) {
    var s = 0.0f64
    var j = 0usize
    while j < k {
        if j != i { s += sigi[j * k + i] * (x[j] - mu[j]) }
        j += 1usize
    }
    ret (mu[i] - s / sigi[i * k + i], 1.0f64 / sigi[i * k + i])
}

// rdirichlet(alpha): independent gammas normalised
fn rdirichlet(r: *rng.Rng, alpha: []const f64, out: []f64) {
    var s = 0.0f64
    var i = 0usize
    while i < alpha.len {
        out[i] = rd.rgamma(r, alpha[i], 1.0f64)
        s += out[i]
        i += 1usize
    }
    i = 0usize
    while i < alpha.len {
        out[i] = out[i] / s
        i += 1usize
    }
}

// rtrun(mu, sigma, a, b): the inverse-cdf draw of a normal truncated to (a, b)
fn rtrun(r: *rng.Rng, mu: f64, sigma: f64, lo: f64, hi: f64) -> f64 {
    let fa = mdist.pnorm((lo - mu) / sigma, 0.0f64, 1.0f64, true, false)
    let fb = mdist.pnorm((hi - mu) / sigma, 0.0f64, 1.0f64, true, false)
    let u = rng.unif(r)
    ret mu + sigma * mdist.qnorm(u * (fb - fa) + fa, 0.0f64, 1.0f64, true, false)
}

// rwishart(nu, V): W (out_w), its inverse (out_iw), the upper factor C with W = C'C (out_c) and its inverse (out_ci), all k by k column-major
fn rwishart(a: *mem.Arena, r: *rng.Rng, nu: f64, v: []const f64, k: usize, out_w: []f64, out_iw: []f64, out_c: []f64, out_ci: []f64) -> err {
    let (t, e1) = mem.alloc[f64](a, k * k)
    let (cv, e2) = mem.alloc[f64](a, k * k)
    if e1 != ok || e2 != ok { ret mem.Full }
    if !chol_upper(v, k, cv) { ret mem.Full }
    var i = 0usize
    while i < k * k {
        t[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        t[i * k + i] = math.sqrt[f64](rd.rchisq(r, nu - f64(i)))
        i += 1usize
    }
    i = 0usize
    while i < k {
        var j = i + 1usize
        while j < k {
            t[j * k + i] = rng.norm(r)
            j += 1usize
        }
        i += 1usize
    }
    // C = T chol(V)
    var c = 0usize
    while c < k {
        var rr = 0usize
        while rr < k {
            var s = 0.0f64
            var q = 0usize
            while q < k {
                s += t[q * k + rr] * cv[c * k + q]
                q += 1usize
            }
            out_c[c * k + rr] = s
            rr += 1usize
        }
        c += 1usize
    }
    inv_upper(out_c, k, out_ci)
    c = 0usize
    while c < k {
        var rr = 0usize
        while rr < k {
            var s = 0.0f64
            var s2 = 0.0f64
            var q = 0usize
            while q < k {
                s += out_c[rr * k + q] * out_c[c * k + q]
                s2 += out_ci[q * k + rr] * out_ci[q * k + c]
                q += 1usize
            }
            out_w[c * k + rr] = s
            out_iw[c * k + rr] = s2
            rr += 1usize
        }
        c += 1usize
    }
    ret ok
}

// breg(y, X, betabar, A): one draw of the regression coefficients under the normal prior (X is n by k column-major, A k by k)
fn breg(a: *mem.Arena, r: *rng.Rng, y: []const f64, x: []const f64, betabar: []const f64, am: []const f64, k: usize, out: []f64) -> err {
    let n = y.len
    let (ra, e1) = mem.alloc[f64](a, k * k)
    let (w, e2) = mem.alloc[f64](a, (n + k) * k)
    let (z, e3) = mem.alloc[f64](a, n + k)
    let (wtw, e4) = mem.alloc[f64](a, k * k)
    let (u, e5) = mem.alloc[f64](a, k * k)
    let (ir, e6) = mem.alloc[f64](a, k * k)
    let (wz, e7) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    if !chol_upper(am, k, ra) { ret mem.Full }
    var i = 0usize
    var c = 0usize
    while c < k {
        i = 0usize
        while i < n {
            w[c * (n + k) + i] = x[c * n + i]
            i += 1usize
        }
        i = 0usize
        while i < k {
            w[c * (n + k) + n + i] = ra[c * k + i]
            i += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < n {
        z[i] = y[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += ra[j * k + i] * betabar[j]
            j += 1usize
        }
        z[n + i] = s
        i += 1usize
    }
    c = 0usize
    while c < k {
        var c2 = 0usize
        while c2 < k {
            var s = 0.0f64
            i = 0usize
            while i < n + k {
                s += w[c * (n + k) + i] * w[c2 * (n + k) + i]
                i += 1usize
            }
            wtw[c2 * k + c] = s
            c2 += 1usize
        }
        var s2 = 0.0f64
        i = 0usize
        while i < n + k {
            s2 += w[c * (n + k) + i] * z[i]
            i += 1usize
        }
        wz[c] = s2
        c += 1usize
    }
    if !chol_upper(wtw, k, u) { ret mem.Full }
    inv_upper(u, k, ir)
    // IR t(IR) (t(W) z) + IR rnorm(k)
    let (tmp, e8) = mem.alloc[f64](a, k)
    let (nz, e9) = mem.alloc[f64](a, k)
    if e8 != ok || e9 != ok { ret mem.Full }
    i = 0usize
    while i < k {
        nz[i] = rng.norm(r)
        i += 1usize
    }
    i = 0usize
    while i < k {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += ir[i * k + j] * wz[j]
            j += 1usize
        }
        tmp[i] = s
        i += 1usize
    }
    i = 0usize
    while i < k {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += ir[j * k + i] * tmp[j]
            j += 1usize
        }
        var s2 = 0.0f64
        j = 0usize
        while j < k {
            s2 += ir[j * k + i] * nz[j]
            j += 1usize
        }
        out[i] = s + s2
        i += 1usize
    }
    ret ok
}

// the posterior pieces shared by the regression draws: with the prior stacked under the data, W = [X; chol(A)], z = [y; chol(A) betabar] (m response columns at once), IR = chol(W'W)^-1, Btilde = IR IR' W'z and the residual cross-product S
// (X is n by k, y n by m, all column-major)
fn stacked_fit(a: *mem.Arena, y: []const f64, x: []const f64, betabar: []const f64, am: []const f64, n: usize, k: usize, m: usize, ir: []f64, bt: []f64, s: []f64) -> err {
    let (ra, e1) = mem.alloc[f64](a, k * k)
    let (w, e2) = mem.alloc[f64](a, (n + k) * k)
    let (z, e3) = mem.alloc[f64](a, (n + k) * m)
    let (wtw, e4) = mem.alloc[f64](a, k * k)
    let (u, e5) = mem.alloc[f64](a, k * k)
    let (wz, e6) = mem.alloc[f64](a, k * m)
    let (t1, e7) = mem.alloc[f64](a, k * m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    if !chol_upper(am, k, ra) { ret mem.Full }
    let nk = n + k
    var c = 0usize
    var i = 0usize
    while c < k {
        i = 0usize
        while i < n {
            w[c * nk + i] = x[c * n + i]
            i += 1usize
        }
        i = 0usize
        while i < k {
            w[c * nk + n + i] = ra[c * k + i]
            i += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < m {
        i = 0usize
        while i < n {
            z[c * nk + i] = y[c * n + i]
            i += 1usize
        }
        i = 0usize
        while i < k {
            var sv = 0.0f64
            var j = 0usize
            while j < k {
                sv += ra[j * k + i] * betabar[c * k + j]
                j += 1usize
            }
            z[c * nk + n + i] = sv
            i += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < k {
        var c2 = 0usize
        while c2 < k {
            var sv = 0.0f64
            i = 0usize
            while i < nk {
                sv += w[c * nk + i] * w[c2 * nk + i]
                i += 1usize
            }
            wtw[c2 * k + c] = sv
            c2 += 1usize
        }
        var q = 0usize
        while q < m {
            var sv = 0.0f64
            i = 0usize
            while i < nk {
                sv += w[c * nk + i] * z[q * nk + i]
                i += 1usize
            }
            wz[q * k + c] = sv
            q += 1usize
        }
        c += 1usize
    }
    if !chol_upper(wtw, k, u) { ret mem.Full }
    inv_upper(u, k, ir)
    c = 0usize
    while c < m {
        i = 0usize
        while i < k {
            var sv = 0.0f64
            var j = 0usize
            while j < k {
                sv += ir[i * k + j] * wz[c * k + j]
                j += 1usize
            }
            t1[c * k + i] = sv
            i += 1usize
        }
        i = 0usize
        while i < k {
            var sv = 0.0f64
            var j = 0usize
            while j < k {
                sv += ir[j * k + i] * t1[c * k + j]
                j += 1usize
            }
            bt[c * k + i] = sv
            i += 1usize
        }
        c += 1usize
    }
    let (ev, e8) = mem.alloc[f64](a, nk * m)
    if e8 != ok { ret mem.Full }
    c = 0usize
    while c < m {
        i = 0usize
        while i < nk {
            var sv = 0.0f64
            var j = 0usize
            while j < k {
                sv += w[j * nk + i] * bt[c * k + j]
                j += 1usize
            }
            ev[c * nk + i] = z[c * nk + i] - sv
            i += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < m {
        var c2 = 0usize
        while c2 < m {
            var sv = 0.0f64
            i = 0usize
            while i < nk {
                sv += ev[c * nk + i] * ev[c2 * nk + i]
                i += 1usize
            }
            s[c2 * m + c] = sv
            c2 += 1usize
        }
        c += 1usize
    }
    ret ok
}

// rmultireg(Y, X, Bbar, A, nu, V): one draw of the coefficient matrix B (k by m) and the covariance Sigma (m by m) of the multivariate regression
fn rmultireg(a: *mem.Arena, r: *rng.Rng, y: []const f64, x: []const f64, bbar: []const f64, am: []const f64, nu: f64, v: []const f64, n: usize, k: usize, m: usize, outb: []f64, outs: []f64) -> err {
    let (ir, e1) = mem.alloc[f64](a, k * k)
    let (bt, e2) = mem.alloc[f64](a, k * m)
    let (s, e3) = mem.alloc[f64](a, m * m)
    let (vs, e4) = mem.alloc[f64](a, m * m)
    let (uvs, e5) = mem.alloc[f64](a, m * m)
    let (ivs, e6) = mem.alloc[f64](a, m * m)
    let (ivsm, e7) = mem.alloc[f64](a, m * m)
    let (cw, e8) = mem.alloc[f64](a, m * m)
    let (ci, e9) = mem.alloc[f64](a, m * m)
    let (wm, e10) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
    let fe = stacked_fit(a, y, x, bbar, am, n, k, m, ir, bt, s)
    if fe != ok { ret fe }
    var i = 0usize
    while i < m * m {
        vs[i] = v[i] + s[i]
        i += 1usize
    }
    if !chol_upper(vs, m, uvs) { ret mem.Full }
    inv_upper(uvs, m, ivs)
    var c = 0usize
    while c < m {
        var rr = 0usize
        while rr < m {
            var sv = 0.0f64
            var q = 0usize
            while q < m {
                sv += ivs[q * m + rr] * ivs[q * m + c]
                q += 1usize
            }
            ivsm[c * m + rr] = sv
            rr += 1usize
        }
        c += 1usize
    }
    let we = rwishart(a, r, nu + f64(n), ivsm, m, wm, outs, cw, ci)
    if we != ok { ret we }
    let (draw, e11) = mem.alloc[f64](a, k * m)
    let (idr, e12) = mem.alloc[f64](a, k * m)
    if e11 != ok || e12 != ok { ret mem.Full }
    i = 0usize
    while i < k * m {
        draw[i] = rng.norm(r)
        i += 1usize
    }
    c = 0usize
    while c < m {
        i = 0usize
        while i < k {
            var sv = 0.0f64
            var j = 0usize
            while j < k {
                sv += ir[j * k + i] * draw[c * k + j]
                j += 1usize
            }
            idr[c * k + i] = sv
            i += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < m {
        i = 0usize
        while i < k {
            var sv = 0.0f64
            var j = 0usize
            while j < m {
                sv += idr[j * k + i] * ci[j * m + c]
                j += 1usize
            }
            outb[c * k + i] = bt[c * k + i] + sv
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// runireg(Data, Prior, Mcmc) with keep = 1: nr iid draws of the coefficients (nr by k, column-major) and of sigma squared, each a chi-square then k normals
fn runireg(a: *mem.Arena, r: *rng.Rng, y: []const f64, x: []const f64, betabar: []const f64, am: []const f64, nu: f64, ssq: f64, n: usize, k: usize, nr: usize, outb: []f64, outs: []f64) -> err {
    let (ir, e1) = mem.alloc[f64](a, k * k)
    let (bt, e2) = mem.alloc[f64](a, k)
    let (s, e3) = mem.alloc[f64](a, 1usize)
    let (nz, e4) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let fe = stacked_fit(a, y, x, betabar, am, n, k, 1usize, ir, bt, s)
    if fe != ok { ret fe }
    var it = 0usize
    while it < nr {
        let sig = (nu * ssq + s[0usize]) / rd.rchisq(r, nu + f64(n))
        let sd = math.sqrt[f64](sig)
        var i = 0usize
        while i < k {
            nz[i] = rng.norm(r)
            i += 1usize
        }
        i = 0usize
        while i < k {
            var sv = 0.0f64
            var j = 0usize
            while j < k {
                sv += ir[j * k + i] * nz[j]
                j += 1usize
            }
            outb[i * nr + it] = bt[i] + sd * sv
            i += 1usize
        }
        outs[it] = sig
        it += 1usize
    }
    ret ok
}

// runiregGibbs(Data, Prior, Mcmc) with keep = 1: nr Gibbs sweeps from sigma squared = sigmasq0, each drawing beta given sigma squared (k normals) and then sigma squared given beta (one chi-square); outb is nr by k column-major
fn runireg_gibbs(a: *mem.Arena, r: *rng.Rng, y: []const f64, x: []const f64, betabar: []const f64, am: []const f64, nu: f64, ssq: f64, sigmasq0: f64, n: usize, k: usize, nr: usize, outb: []f64, outs: []f64) -> err {
    let (xpx, e1) = mem.alloc[f64](a, k * k)
    let (xpy, e2) = mem.alloc[f64](a, k)
    let (mx, e3) = mem.alloc[f64](a, k * k)
    let (u, e4) = mem.alloc[f64](a, k * k)
    let (ir, e5) = mem.alloc[f64](a, k * k)
    let (rhs, e6) = mem.alloc[f64](a, k)
    let (t1, e7) = mem.alloc[f64](a, k)
    let (nz, e8) = mem.alloc[f64](a, k)
    let (beta, e9) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Full }
    var c = 0usize
    var i = 0usize
    while c < k {
        var c2 = 0usize
        while c2 < k {
            var sv = 0.0f64
            i = 0usize
            while i < n {
                sv += x[c * n + i] * x[c2 * n + i]
                i += 1usize
            }
            xpx[c2 * k + c] = sv
            c2 += 1usize
        }
        var sy = 0.0f64
        i = 0usize
        while i < n {
            sy += x[c * n + i] * y[i]
            i += 1usize
        }
        xpy[c] = sy
        c += 1usize
    }
    var sg = sigmasq0
    var it = 0usize
    while it < nr {
        c = 0usize
        while c < k {
            var rr = 0usize
            while rr < k {
                mx[c * k + rr] = xpx[c * k + rr] / sg + am[c * k + rr]
                rr += 1usize
            }
            c += 1usize
        }
        if !chol_upper(mx, k, u) { ret mem.Full }
        inv_upper(u, k, ir)
        i = 0usize
        while i < k {
            var sv = xpy[i] / sg
            var j = 0usize
            while j < k {
                sv += am[j * k + i] * betabar[j]
                j += 1usize
            }
            rhs[i] = sv
            i += 1usize
        }
        i = 0usize
        while i < k {
            var sv = 0.0f64
            var j = 0usize
            while j < k {
                sv += ir[i * k + j] * rhs[j]
                j += 1usize
            }
            t1[i] = sv
            i += 1usize
        }
        i = 0usize
        while i < k {
            nz[i] = rng.norm(r)
            i += 1usize
        }
        i = 0usize
        while i < k {
            var sv = 0.0f64
            var sn = 0.0f64
            var j = 0usize
            while j < k {
                sv += ir[j * k + i] * t1[j]
                sn += ir[j * k + i] * nz[j]
                j += 1usize
            }
            beta[i] = sv + sn
            i += 1usize
        }
        var ss = 0.0f64
        i = 0usize
        while i < n {
            var f = 0.0f64
            var j = 0usize
            while j < k {
                f += x[j * n + i] * beta[j]
                j += 1usize
            }
            ss += (y[i] - f) * (y[i] - f)
            i += 1usize
        }
        sg = (nu * ssq + ss) / rd.rchisq(r, nu + f64(n))
        i = 0usize
        while i < k {
            outb[i * nr + it] = beta[i]
            i += 1usize
        }
        outs[it] = sg
        it += 1usize
    }
    ret ok
}

// mnlHess(beta, y, X): the k by k information matrix of the multinomial logit, the sum over observations of X_i' (diag(p_i) - p_i p_i') X_i, column-major in out (y is not used by the formula)
fn mnl_hess(a: *mem.Arena, beta: []const f64, x: []const f64, k: usize, p: usize, n: usize, out: []f64) -> err {
    let (pr, e) = mem.alloc[f64](a, p)
    if e != ok { ret e }
    var q = 0usize
    while q < k * k {
        out[q] = 0.0f64
        q += 1usize
    }
    var i = 0usize
    while i < n {
        var denom = 0.0f64
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var c = 0usize
            while c < k {
                s += x[c * n * p + i * p + j] * beta[c]
                c += 1usize
            }
            pr[j] = math.exp[f64](s)
            denom += pr[j]
            j += 1usize
        }
        j = 0usize
        while j < p {
            pr[j] = pr[j] / denom
            j += 1usize
        }
        var c1 = 0usize
        while c1 < k {
            var c2 = 0usize
            while c2 < k {
                var s = 0.0f64
                var j1 = 0usize
                while j1 < p {
                    var j2 = 0usize
                    while j2 < p {
                        var am = 0.0f64 - pr[j1] * pr[j2]
                        if j1 == j2 { am += pr[j1] }
                        s += x[c1 * n * p + i * p + j1] * am * x[c2 * n * p + i * p + j2]
                        j2 += 1usize
                    }
                    j1 += 1usize
                }
                out[c2 * k + c1] += s
                c2 += 1usize
            }
            c1 += 1usize
        }
        i += 1usize
    }
    ret ok
}

// numEff(x, m): the standard error of the mean allowing for autocorrelation, sqrt(var(x) f / n) with f = 1 + 2 sum_{l = 1..m} ((m + 1 - l) / (m + 1)) acf(l); out = (stderr, f)
fn num_eff(x: []const f64, m: usize, out: []f64) {
    let n = x.len
    let nf = f64(n)
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / nf
    var c0 = 0.0f64
    i = 0usize
    while i < n {
        c0 += (x[i] - mean) * (x[i] - mean)
        i += 1usize
    }
    var f = 1.0f64
    var l = 1usize
    while l <= m {
        var cl = 0.0f64
        i = 0usize
        while i + l < n {
            cl += (x[i] - mean) * (x[i + l] - mean)
            i += 1usize
        }
        f += 2.0f64 * f64(m + 1usize - l) / f64(m + 1usize) * (cl / c0)
        l += 1usize
    }
    out[0usize] = math.sqrt[f64](c0 / (nf - 1.0f64) * f / nf)
    out[1usize] = f
}

// the mixture moments of bayesm's momMix for one draw: nc components with means mus (nc by k, column-major) and the upper-triangular rooti matrices rootis (k by k each, stacked); the covariance of a component is t(root) root with root = backsolve(rooti, I).
// mu_out receives the mixture mean, sigma_out (k by k) its covariance sum_i p_i Sigma_i + p_i (mu_i - mu)(mu_i - mu)'
fn mix_mom(a: *mem.Arena, prob: []const f64, mus: []const f64, rootis: []const f64, nc: usize, k: usize, mu_out: []f64, sigma_out: []f64) -> err {
    let (root, e) = mem.alloc[f64](a, k * k)
    if e != ok { ret e }
    var j = 0usize
    while j < k {
        mu_out[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < nc {
        j = 0usize
        while j < k {
            mu_out[j] += prob[i] * mus[j * nc + i]
            j += 1usize
        }
        i += 1usize
    }
    var q = 0usize
    while q < k * k {
        sigma_out[q] = 0.0f64
        q += 1usize
    }
    i = 0usize
    while i < nc {
        inv_upper(rootis[i * k * k..(i + 1usize) * k * k], k, root)
        var c1 = 0usize
        while c1 < k {
            var c2 = 0usize
            while c2 < k {
                var s = 0.0f64
                var r = 0usize
                while r < k {
                    s += root[c1 * k + r] * root[c2 * k + r]
                    r += 1usize
                }
                let d1 = mus[c1 * nc + i] - mu_out[c1]
                let d2 = mus[c2 * nc + i] - mu_out[c2]
                sigma_out[c2 * k + c1] += prob[i] * s + prob[i] * d1 * d2
                c2 += 1usize
            }
            c1 += 1usize
        }
        i += 1usize
    }
    ret ok
}

// mixDen for one margin: the density at x of margin `dim` (0-based) of the mixture, sum_j p_j dnorm(x, mu_j[dim], sd_j[dim]) with sd_j[dim] the root of the dim-th diagonal of t(root_j) root_j
fn mix_den(a: *mem.Arena, x: f64, prob: []const f64, mus: []const f64, rootis: []const f64, nc: usize, k: usize, dim: usize) -> f64 {
    let (root, e) = mem.alloc[f64](a, k * k)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    var i = 0usize
    while i < nc {
        inv_upper(rootis[i * k * k..(i + 1usize) * k * k], k, root)
        var v = 0.0f64
        var r = 0usize
        while r < k {
            v += root[dim * k + r] * root[dim * k + r]
            r += 1usize
        }
        s += prob[i] * mdist.dnorm(x, mus[dim * nc + i], math.sqrt[f64](v), false)
        i += 1usize
    }
    ret s
}
