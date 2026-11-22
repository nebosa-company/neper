// R robustbase regression: glmrob (the Mqle fit for the binomial and poisson families, Huber psi, weights.on.x "none" or "hat"), step for step from glmrobMqle.
// Matrices are row-major; the start comes from glm.fit through armglm.glm_fit_gen.

use e.math
use e.algo.linalg.decomp as dc
use e.algo.stat.armglm as ag
use e.algo.stat.armx87 as xe
use e.math.dist as dist
use e.math.nmath as nmm
use e.math.nmath_beta as nb
use e.mem

error RegFail

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// solve a x = b by LU with partial pivoting (LAPACK dgesv order); a is p by p, b is p by m, both row-major and destroyed; the answer replaces b. False when singular.
fn lu_solve(a: []f64, p: usize, b: []f64, m: usize) -> bool {
    var k = 0usize
    while k < p {
        var piv = k
        var best = math.abs[f64](a[k * p + k])
        var i = k + 1usize
        while i < p {
            let v = math.abs[f64](a[i * p + k])
            if v > best {
                best = v
                piv = i
            }
            i += 1usize
        }
        if best == 0.0f64 { ret false }
        if piv != k {
            var j = 0usize
            while j < p {
                let t = a[k * p + j]
                a[k * p + j] = a[piv * p + j]
                a[piv * p + j] = t
                j += 1usize
            }
            j = 0usize
            while j < m {
                let t = b[k * m + j]
                b[k * m + j] = b[piv * m + j]
                b[piv * m + j] = t
                j += 1usize
            }
        }
        i = k + 1usize
        while i < p {
            let f = a[i * p + k] / a[k * p + k]
            a[i * p + k] = f
            var j = k + 1usize
            while j < p {
                a[i * p + j] = a[i * p + j] - f * a[k * p + j]
                j += 1usize
            }
            j = 0usize
            while j < m {
                b[i * m + j] = b[i * m + j] - f * b[k * m + j]
                j += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
    var c = 0usize
    while c < m {
        var ii = p
        while ii > 0usize {
            ii -= 1usize
            var s = b[ii * m + c]
            var j = ii + 1usize
            while j < p {
                s = s - a[ii * p + j] * b[j * m + c]
                j += 1usize
            }
            b[ii * m + c] = s / a[ii * p + ii]
        }
        c += 1usize
    }
    ret true
}

fn b2f(b: bool) -> f64 {
    if b { ret 1.0f64 }
    ret 0.0f64
}

fn dpois_n(x: f64, mu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nmm.dpois(x, mu, false)
}

fn ppois_n(x: f64, mu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nmm.ppois(x, mu, true, false)
}

fn pbin_n(x: f64, n: f64, mu: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret nb.pbinom(x, n, mu, true, false)
}

// Epsi, Epsi2 and EpsiS of the binomial (fam 1) or poisson (fam 2) at one observation: out gets them in that order.
fn glmrob_eps(fam: usize, mu: f64, ni: f64, tcc: f64, sv: f64, sni: f64, vmu: f64, out: []f64) {
    let h = math.floor[f64](mu * ni - tcc * sni * sv)
    let k = math.floor[f64](mu * ni + tcc * sni * sv)
    if fam == 2usize {
        let dph = dpois_n(h, mu)
        let dph1 = dpois_n(h - 1.0f64, mu)
        let dpk = dpois_n(k, mu)
        let dpk1 = dpois_n(k - 1.0f64, mu)
        let phm1 = ppois_n(h - 1.0f64, mu)
        let ph = phm1 + dph
        let pkm1 = ppois_n(k - 1.0f64, mu)
        let pk = pkm1 + dpk
        let e2f = mu * (dph1 - dph - dpk1 + dpk) + pkm1 - phm1
        out[0usize] = tcc * (1.0f64 - pk - ph) + mu * (dph - dpk) / sv
        out[1usize] = tcc * tcc * (ph + 1.0f64 - pk) + e2f
        out[2usize] = tcc * (dph + dpk) + e2f / sv
        ret
    }
    var nm1 = ni - 1.0f64
    if nm1 < 0.0f64 { nm1 = 0.0f64 }
    var nm2 = ni - 2.0f64
    if nm2 < 0.0f64 { nm2 = 0.0f64 }
    let pk = pbin_n(k, ni, mu)
    let ph = pbin_n(h, ni, mu)
    let pkm1 = pbin_n(k - 1.0f64, nm1, mu)
    let phm1 = pbin_n(h - 1.0f64, nm1, mu)
    let pkm2 = pbin_n(k - 2.0f64, nm2, mu)
    let phm2 = pbin_n(h - 2.0f64, nm2, mu)
    var t1 = pkm1 - phm1
    if ni == 1.0f64 { t1 = b2f(h <= 0.0f64) * b2f(k >= 1.0f64) }
    var t2 = pkm2 - phm2
    if ni == 2.0f64 { t2 = b2f(h <= 1.0f64) * b2f(k >= 2.0f64) }
    let qlv = mu / vmu * (mu * ni * (pk - ph) + (1.0f64 - 2.0f64 * mu * ni) * t1 + (ni - 1.0f64) * mu * t2)
    var e1 = (pkm1 - phm1 - pk + ph) * mu * sni / sv
    if ni == 1.0f64 { e1 = (0.0f64 - b2f(h < 0.0f64) + b2f(k >= 1.0f64)) * sv }
    out[0usize] = tcc * (1.0f64 - pk - ph) + e1
    out[1usize] = tcc * tcc * (ph + 1.0f64 - pk) + qlv
    var ha = phm1
    if ni == 1.0f64 { ha = b2f(h >= 1.0f64) }
    var ka = pkm1
    if ni == 1.0f64 { ka = b2f(k > 0.0f64) }
    var tail = 0.0f64
    if ni != 0.0f64 { tail = qlv / (sni * sv) }
    out[2usize] = mu / vmu * (tcc * (ph - ha) + tcc * (pk - ka)) + tail
}

// 1 - H_ii for the weights.on.x = "hat" option: qr(X) at the default tolerance 1e-7, Hii the row sums of squares of the first rank columns of Q.
fn hat_weights(a: *mem.Arena, x: []const f64, n: usize, p: usize, out: []f64) -> err {
    let (cm, e0) = mem.alloc[f64](a, n * p)
    if e0 != ok { ret e0 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            cm[j * n + i] = x[i * p + j]
            j += 1usize
        }
        i += 1usize
    }
    let (f, e1) = dc.qr(a, cm, n, p, 1.0e-7f64)
    if e1 != ok { ret e1 }
    let (col, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    i = 0usize
    while i < n {
        out[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < f.rank {
        i = 0usize
        while i < n {
            col[i] = 0.0f64
            i += 1usize
        }
        col[j] = 1.0f64
        dc.qr_qy(&f, col)
        i = 0usize
        while i < n {
            out[i] = out[i] + col[i] * col[i]
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        let w = 1.0f64 - out[i]
        out[i] = w * w
        i += 1usize
    }
    ret ok
}

type GlmrobFit = struct { iter: usize, conv: bool }

// glmrobMqle for family fam (1 binomial with logit, 2 poisson with log). x is n by p row-major, y the response (a proportion for the binomial), ni the prior weights; coef gets the
// p coefficients, cov the p by p asymptotic covariance, wr the n robustness weights pmin(1, tcc/|r|), disp is 1. wx is the weights.on.x vector (n ones for "none").
fn glmrob_mqle(a: *mem.Arena, x: []const f64, y: []const f64, ni: []const f64, wx: []const f64, n: usize, p: usize, fam: usize, tcc: f64, acc: f64, maxit: usize, coef: []f64, cov: []f64, wr: []f64) -> (GlmrobFit, err) {
    var res = GlmrobFit { iter: 0usize, conv: false }
    var link = 3usize
    if fam == 2usize { link = 1usize }
    let (cv0, e0) = mem.alloc[f64](a, p * p)
    let (inf0, e1) = mem.alloc[f64](a, 8usize)
    let (theta, e2) = mem.alloc[f64](a, p)
    let (told, e3) = mem.alloc[f64](a, p)
    let (eta, e4) = mem.alloc[f64](a, n)
    let (mu, e5) = mem.alloc[f64](a, n)
    let (rp, e6) = mem.alloc[f64](a, n)
    let (sni, e7) = mem.alloc[f64](a, n)
    let (svf, e8) = mem.alloc[f64](a, n)
    let (dm, e9) = mem.alloc[f64](a, n)
    let (eq, e10) = mem.alloc[f64](a, p)
    let (mm, e11) = mem.alloc[f64](a, p * p)
    let (qm, e12) = mem.alloc[f64](a, p * p)
    let (eps, e13) = mem.alloc[f64](a, 3usize * n)
    let (rh, e14) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret (res, RegFail) }
    let noff = ni[0usize..0usize]
    let gi = ag.glm_fit_gen(a, x, y, n, p, fam, link, ni, noff, true, theta, cv0, inf0)
    if gi == 0usize { ret (res, RegFail) }
    var i = 0usize
    var j = 0usize
    while j < p {
        told[j] = theta[j]
        j += 1usize
    }
    i = 0usize
    while i < n {
        var s = 0.0f64
        j = 0usize
        while j < p {
            s = s + x[i * p + j] * theta[j]
            j += 1usize
        }
        eta[i] = s
        mu[i] = ag.linkinv(link, s)
        sni[i] = math.sqrt[f64](ni[i])
        i += 1usize
    }
    var nit = 0usize
    var conv = false
    var it = 1usize
    while it <= maxit {
        // comp.V.resid, comp.scaling (phi = 1), comp.Epsi.init at the current mu and eta
        i = 0usize
        while i < n {
            var vmu = mu[i] * (1.0f64 - mu[i])
            if fam == 2usize { vmu = mu[i] }
            svf[i] = math.sqrt[f64](vmu)
            rp[i] = (y[i] - mu[i]) * sni[i] / svf[i]
            dm[i] = ag.mu_eta(link, eta[i])
            glmrob_eps(fam, mu[i], ni[i], tcc, svf[i], sni[i], vmu, eps[3usize * i..3usize * i + 3usize])
            i += 1usize
        }
        // EEq and the Newton system
        j = 0usize
        while j < p {
            eq[j] = 0.0f64
            j += 1usize
        }
        var jk = 0usize
        while jk < p * p {
            mm[jk] = 0.0f64
            jk += 1usize
        }
        i = 0usize
        while i < n {
            var cl = rp[i]
            if cl > tcc { cl = tcc }
            if cl < 0.0f64 - tcc { cl = 0.0f64 - tcc }
            let cpsi = cl - eps[3usize * i]
            let fe = cpsi * wx[i] * sni[i] / svf[i] * dm[i]
            var db = eps[3usize * i + 2usize] / (sni[i] * svf[i]) * wx[i] * (ni[i] * dm[i]) * (ni[i] * dm[i])
            if ni[i] == 0.0f64 { db = 0.0f64 }
            j = 0usize
            while j < p {
                eq[j] = eq[j] + fe * x[i * p + j]
                var k2 = 0usize
                while k2 < p {
                    mm[j * p + k2] = mm[j * p + k2] + db * x[i * p + j] * x[i * p + k2]
                    k2 += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j < p {
            eq[j] = eq[j] / f64(n)
            j += 1usize
        }
        jk = 0usize
        while jk < p * p {
            mm[jk] = mm[jk] / f64(n)
            jk += 1usize
        }
        if !lu_solve(mm, p, eq, 1usize) { break }
        var dd = 0.0f64
        var tt = 0.0f64
        j = 0usize
        while j < p {
            theta[j] = told[j] + eq[j]
            dd = dd + eq[j] * eq[j]
            tt = tt + told[j] * told[j]
            j += 1usize
        }
        nit = it
        i = 0usize
        while i < n {
            var s = 0.0f64
            j = 0usize
            while j < p {
                s = s + x[i * p + j] * theta[j]
                j += 1usize
            }
            eta[i] = s
            mu[i] = ag.linkinv(link, s)
            i += 1usize
        }
        var den = tt
        if den < 1.0e-20f64 { den = 1.0e-20f64 }
        let rel = math.sqrt[f64](dd / den)
        if rel <= acc {
            conv = true
            // the loop breaks here; the final quantities are computed at the new mu below
            break
        }
        j = 0usize
        while j < p {
            told[j] = theta[j]
            j += 1usize
        }
        it += 1usize
    }
    // after the loop: V, scaling and Epsi at the final mu, then alpha, matQ, matM and the sandwich
    i = 0usize
    while i < n {
        var vmu = mu[i] * (1.0f64 - mu[i])
        if fam == 2usize { vmu = mu[i] }
        svf[i] = math.sqrt[f64](vmu)
        rp[i] = (y[i] - mu[i]) * sni[i] / svf[i]
        dm[i] = ag.mu_eta(link, eta[i])
        glmrob_eps(fam, mu[i], ni[i], tcc, svf[i], sni[i], vmu, eps[3usize * i..3usize * i + 3usize])
        i += 1usize
    }
    j = 0usize
    while j < p {
        coef[j] = theta[j]
        eq[j] = 0.0f64
        j += 1usize
    }
    var jk = 0usize
    while jk < p * p {
        mm[jk] = 0.0f64
        qm[jk] = 0.0f64
        jk += 1usize
    }
    i = 0usize
    while i < n {
        let fe = eps[3usize * i] * wx[i] * sni[i] / svf[i] * dm[i]
        let da = eps[3usize * i + 1usize] / (ni[i] * svf[i] * svf[i]) * wx[i] * wx[i] * (ni[i] * dm[i]) * (ni[i] * dm[i])
        var db = eps[3usize * i + 2usize] / (sni[i] * svf[i]) * wx[i] * (ni[i] * dm[i]) * (ni[i] * dm[i])
        if ni[i] == 0.0f64 { db = 0.0f64 }
        j = 0usize
        while j < p {
            eq[j] = eq[j] + fe * x[i * p + j]
            var k2 = 0usize
            while k2 < p {
                qm[j * p + k2] = qm[j * p + k2] + da * x[i * p + j] * x[i * p + k2]
                mm[j * p + k2] = mm[j * p + k2] + db * x[i * p + j] * x[i * p + k2]
                k2 += 1usize
            }
            j += 1usize
        }
        var w = tcc / math.abs[f64](rp[i])
        if w > 1.0f64 { w = 1.0f64 }
        wr[i] = w
        i += 1usize
    }
    j = 0usize
    while j < p {
        eq[j] = eq[j] / f64(n)
        j += 1usize
    }
    j = 0usize
    while j < p {
        var k2 = 0usize
        while k2 < p {
            qm[j * p + k2] = qm[j * p + k2] / f64(n) - eq[j] * eq[k2]
            mm[j * p + k2] = mm[j * p + k2] / f64(n)
            k2 += 1usize
        }
        j += 1usize
    }
    // asCov = M^-1 Q M^-1 / n: solve M X = Q, then M Y = X'
    if !lu_solve(mm, p, qm, p) { ret (res, RegFail) }
    j = 0usize
    while j < p {
        var k2 = 0usize
        while k2 < p {
            cov[j * p + k2] = qm[k2 * p + j]
            k2 += 1usize
        }
        j += 1usize
    }
    // mm was destroyed by the first solve; rebuild M for the second
    jk = 0usize
    while jk < p * p {
        mm[jk] = 0.0f64
        jk += 1usize
    }
    i = 0usize
    while i < n {
        var db = eps[3usize * i + 2usize] / (sni[i] * svf[i]) * wx[i] * (ni[i] * dm[i]) * (ni[i] * dm[i])
        if ni[i] == 0.0f64 { db = 0.0f64 }
        j = 0usize
        while j < p {
            var k2 = 0usize
            while k2 < p {
                mm[j * p + k2] = mm[j * p + k2] + db * x[i * p + j] * x[i * p + k2]
                k2 += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    jk = 0usize
    while jk < p * p {
        mm[jk] = mm[jk] / f64(n)
        jk += 1usize
    }
    if !lu_solve(mm, p, cov, p) { ret (res, RegFail) }
    jk = 0usize
    while jk < p * p {
        cov[jk] = cov[jk] / f64(n)
        jk += 1usize
    }
    res.iter = nit
    res.conv = conv
    ret (res, ok)
}
