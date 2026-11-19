// lavaan: maximum-likelihood confirmatory factor analysis of one factor measured by p indicators (cfa("f =~ x1 + ... + xp"), the first loading fixed at 1, free residual variances and factor variance), from the
// sample covariance matrix: parameter estimates, the chi-square test of the model and its degrees of freedom, with lavaan's normal-theory likelihood (the covariance divided by n).
//
// Not here: several factors, means, standard errors, the other estimators, fit indices beyond chi-square, categorical data, general model syntax.

use e.algo.stat.psych as ps
use e.math
use e.math.nmath as nm
use e.math.opt as opt
use e.algo.stat.quantreg as qrb
use e.mem

type CfaCtx = struct { a: *mem.Arena, s: []const f64, p: usize, logs: f64 }

// Sigma = psi l l' + diag(theta) at par = (l_2 .. l_p, log theta_1 .. log theta_p, log psi); the ML discrepancy log|Sigma| + tr(Sigma^-1 S) - log|S| - p
fn cfa_f(c: *CfaCtx, par: []const f64) -> f64 {
    let mk = mem.mark(c.a)
    let v = cfa_f_inner(c, par)
    mem.reset(c.a, mk)
    ret v
}

fn cfa_f_inner(c: *CfaCtx, par: []const f64) -> f64 {
    let p = c.p
    let (sg, e1) = mem.alloc[f64](c.a, p * p)
    let (inv, e2) = mem.alloc[f64](c.a, p * p)
    if e1 != ok || e2 != ok { ret 1.0e30f64 }
    let psi = math.exp[f64](par[2usize * p - 1usize])
    var i = 0usize
    while i < p {
        var li = 1.0f64
        if i > 0usize { li = par[i - 1usize] }
        var j = 0usize
        while j < p {
            var lj = 1.0f64
            if j > 0usize { lj = par[j - 1usize] }
            sg[i * p + j] = psi * li * lj
            j += 1usize
        }
        sg[i * p + i] += math.exp[f64](par[p - 1usize + i])
        i += 1usize
    }
    if !ps.invert(c.a, sg, p, inv) { ret 1.0e30f64 }
    let ld = ps.logdet(c.a, sg, p)
    var tr = 0.0f64
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            tr += inv[i * p + j] * c.s[j * p + i]
            j += 1usize
        }
        i += 1usize
    }
    let f = ld + tr - c.logs - f64(p)
    if f != f { ret 1.0e30f64 }
    ret f
}

fn cfa_g(c: *CfaCtx, par: []const f64, g: []f64) {
    var q: [32]f64 = zero
    let m = par.len
    var i = 0usize
    while i < m {
        q[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        let h = 1.0e-6f64 * (1.0f64 + math.abs[f64](par[i]))
        q[i] = par[i] + h
        let fp = cfa_f(c, q[0usize..m])
        q[i] = par[i] - h
        let fm = cfa_f(c, q[0usize..m])
        q[i] = par[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// cfa of one factor from the sample covariance s (p by p row-major, divisor n - 1) of n observations. out: loadings (p, the first 1), residual variances (p), the factor variance, then the chi-square (n F),
// its degrees of freedom p (p + 1) / 2 - 2 p and the p value; false when the optimisation fails
fn cfa_one_factor(a: *mem.Arena, s: []const f64, n: usize, p: usize, out: []f64) -> bool {
    let nn = f64(n)
    let (sm, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret false }
    var i = 0usize
    while i < p * p {
        sm[i] = s[i] * (nn - 1.0f64) / nn
        i += 1usize
    }
    var c = CfaCtx { a: a, s: sm, p: p, logs: ps.logdet(a, sm, p) }
    let m = 2usize * p
    let (par, e2) = mem.alloc[f64](a, m)
    if e2 != ok { ret false }
    var off = 0.0f64
    var cnt = 0.0f64
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            if i != j {
                off += sm[i * p + j]
                cnt += 1.0f64
            }
            j += 1usize
        }
        i += 1usize
    }
    let psi0 = off / cnt
    i = 0usize
    while i + 1usize < p {
        par[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        var th = sm[i * p + i] - psi0
        if th < 0.05f64 { th = 0.05f64 }
        par[p - 1usize + i] = math.log[f64](th)
        i += 1usize
    }
    par[m - 1usize] = math.log[f64](psi0)
    let (scr, e3) = mem.alloc[f64](a, (m + 1usize) * (m + 1usize) + 8usize * m + 64usize)
    if e3 != ok { ret false }
    var round = 0usize
    while round < 3usize {
        let (r1, e4) = opt.nelder_mead[CfaCtx](&c, cfa_f, par, 0.2f64, 1.0e-15f64, 4000u32, scr)
        if e4 != ok { ret false }
        round += 1usize
    }
    let (scb, e5) = mem.alloc[f64](a, 4usize * m * m + 16usize * m + 64usize)
    if e5 != ok { ret false }
    let (rb, e6) = opt.bfgs[CfaCtx](&c, cfa_f, cfa_g, par, 1.0e-10f64, 500u32, scb)
    if e6 != ok { ret false }
    let fmin = cfa_f(&c, par)
    out[0usize] = 1.0f64
    i = 1usize
    while i < p {
        out[i] = par[i - 1usize]
        i += 1usize
    }
    i = 0usize
    while i < p {
        out[p + i] = math.exp[f64](par[p - 1usize + i])
        i += 1usize
    }
    out[2usize * p] = math.exp[f64](par[m - 1usize])
    out[2usize * p + 1usize] = nn * fmin
    let df = f64(p * (p + 1usize) / 2usize) - f64(2usize * p)
    out[2usize * p + 2usize] = df
    out[2usize * p + 3usize] = nm.pchisq(nn * fmin, df, false, false)
    ret true
}

// the standard errors of `cfa_one_factor` from the expected information (n / 2) tr(Sigma^-1 dSigma_i Sigma^-1 dSigma_j) at the estimates est (its layout), for the parameters (loadings 2 .. p, residual variances,
// factor variance); se receives them in that order (p - 1 + p + 1 values); false when the information is singular
fn cfa_se(a: *mem.Arena, est: []const f64, n: usize, p: usize, se: []f64) -> bool {
    let m = 2usize * p
    let psi = est[2usize * p]
    let (sg, e1) = mem.alloc[f64](a, p * p)
    let (inv, e2) = mem.alloc[f64](a, p * p)
    let (ds, e3) = mem.alloc[f64](a, m * p * p)
    let (ms, e4) = mem.alloc[f64](a, m * p * p)
    let (info, e5) = mem.alloc[f64](a, m * m)
    let (mat, e6) = mem.alloc[f64](a, m * m)
    let (col, e7) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret false }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            sg[i * p + j] = psi * est[i] * est[j]
            j += 1usize
        }
        sg[i * p + i] += est[p + i]
        i += 1usize
    }
    if !ps.invert(a, sg, p, inv) { ret false }
    var z = 0usize
    while z < m * p * p {
        ds[z] = 0.0f64
        z += 1usize
    }
    // loading k (k = 1 .. p - 1, parameter k - 1): psi (e_k l' + l e_k'); residual variance i (parameter p - 1 + i): e_i e_i'; factor variance (parameter 2 p - 1): l l'
    var k = 1usize
    while k < p {
        var j = 0usize
        while j < p {
            ds[(k - 1usize) * p * p + k * p + j] += psi * est[j]
            ds[(k - 1usize) * p * p + j * p + k] += psi * est[j]
            j += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < p {
        ds[(p - 1usize + i) * p * p + i * p + i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            ds[(m - 1usize) * p * p + i * p + j] = est[i] * est[j]
            j += 1usize
        }
        i += 1usize
    }
    // M_i = Sigma^-1 dSigma_i
    var q = 0usize
    while q < m {
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                var t = 0.0f64
                var l = 0usize
                while l < p {
                    t += inv[i * p + l] * ds[q * p * p + l * p + j]
                    l += 1usize
                }
                ms[q * p * p + i * p + j] = t
                j += 1usize
            }
            i += 1usize
        }
        q += 1usize
    }
    let nn = f64(n)
    q = 0usize
    while q < m {
        var r = 0usize
        while r < m {
            var t = 0.0f64
            i = 0usize
            while i < p {
                var j = 0usize
                while j < p {
                    t += ms[q * p * p + i * p + j] * ms[r * p * p + j * p + i]
                    j += 1usize
                }
                i += 1usize
            }
            info[q * m + r] = nn / 2.0f64 * t
            r += 1usize
        }
        q += 1usize
    }
    // the parameter vector has m - 1 free entries after the first loading is dropped: parameters 0 .. m - 2 plus the factor variance, all m of them but the p - 1 + p + 1 = 2 p of them
    var c = 0usize
    while c < m {
        var r = 0usize
        while r < m * m {
            mat[r] = info[r]
            r += 1usize
        }
        r = 0usize
        while r < m {
            col[r] = 0.0f64
            r += 1usize
        }
        col[c] = 1.0f64
        if !qrb.solve_dense(mat, col, m) { ret false }
        se[c] = math.sqrt[f64](col[c])
        c += 1usize
    }
    ret true
}

// ---- several factors: each indicator loads on one factor (fac[i] in 0 .. nf - 1), the first indicator of every factor fixed at 1, free residual variances, free factor variances and covariances ----

type MfCtx = struct { a: *mem.Arena, s: []const f64, p: usize, nf: usize, fac: []const usize, first: []const usize, logs: f64 }

// the model covariance at par = (free loadings in indicator order, log residual variances, then the factor covariance matrix by its Cholesky-free parametrisation: log variances and the correlations scaled by tanh),
// written into sg (p by p row-major); false when the factor covariance matrix is not positive definite
fn mf_sigma(c: *const MfCtx, par: []const f64, sg: []f64) -> bool {
    let p = c.p
    let nf = c.nf
    let nl = p - nf
    var lam: [32]f64 = zero
    var k = 0usize
    var i = 0usize
    while i < p {
        if c.first[c.fac[i]] == i {
            lam[i] = 1.0f64
        } else {
            lam[i] = par[k]
            k += 1usize
        }
        i += 1usize
    }
    var ph: [64]f64 = zero
    var u = 0usize
    while u < nf {
        ph[u * nf + u] = math.exp[f64](par[nl + p + u])
        u += 1usize
    }
    var q = nl + p + nf
    u = 1usize
    while u < nf {
        var v = 0usize
        while v < u {
            var r = 0.0f64
            let z = par[q]
            let e2 = math.exp[f64](2.0f64 * z)
            r = (e2 - 1.0f64) / (e2 + 1.0f64)
            ph[u * nf + v] = r * math.sqrt[f64](ph[u * nf + u] * ph[v * nf + v])
            ph[v * nf + u] = ph[u * nf + v]
            q += 1usize
            v += 1usize
        }
        u += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            sg[i * p + j] = lam[i] * lam[j] * ph[c.fac[i] * nf + c.fac[j]]
            j += 1usize
        }
        sg[i * p + i] += math.exp[f64](par[nl + i])
        i += 1usize
    }
    ret true
}

fn mf_f(c: *MfCtx, par: []const f64) -> f64 {
    let mk = mem.mark(c.a)
    let v = mf_f_inner(c, par)
    mem.reset(c.a, mk)
    ret v
}

fn mf_f_inner(c: *MfCtx, par: []const f64) -> f64 {
    let p = c.p
    let (sg, e1) = mem.alloc[f64](c.a, p * p)
    let (inv, e2) = mem.alloc[f64](c.a, p * p)
    if e1 != ok || e2 != ok { ret 1.0e30f64 }
    if !mf_sigma(c, par, sg) { ret 1.0e30f64 }
    if !ps.invert(c.a, sg, p, inv) { ret 1.0e30f64 }
    let ld = ps.logdet(c.a, sg, p)
    var tr = 0.0f64
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            tr += inv[i * p + j] * c.s[j * p + i]
            j += 1usize
        }
        i += 1usize
    }
    let f = ld + tr - c.logs - f64(p)
    if f != f { ret 1.0e30f64 }
    ret f
}

fn mf_g(c: *MfCtx, par: []const f64, g: []f64) {
    var q: [64]f64 = zero
    let m = par.len
    var i = 0usize
    while i < m {
        q[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        let h = 1.0e-6f64 * (1.0f64 + math.abs[f64](par[i]))
        q[i] = par[i] + h
        let fp = mf_f(c, q[0usize..m])
        q[i] = par[i] - h
        let fm = mf_f(c, q[0usize..m])
        q[i] = par[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// cfa with nf factors of simple structure (indicator i on factor fac[i], every factor with at least two indicators) from the sample covariance s (divisor n - 1). out: loadings (p, the first of each factor 1), residual variances (p),
// the factor variances and covariances (nf (nf + 1) / 2, row-major lower triangle: (0,0), (1,0), (1,1), (2,0), ...), then chi-square, degrees of freedom and p value
fn cfa_factors(a: *mem.Arena, s: []const f64, n: usize, p: usize, nf: usize, fac: []const usize, out: []f64) -> bool {
    let nn = f64(n)
    let (sm, e1) = mem.alloc[f64](a, p * p)
    let (first, e2) = mem.alloc[usize](a, nf)
    if e1 != ok || e2 != ok { ret false }
    var i = 0usize
    while i < p * p {
        sm[i] = s[i] * (nn - 1.0f64) / nn
        i += 1usize
    }
    var u = 0usize
    while u < nf {
        first[u] = p
        u += 1usize
    }
    i = 0usize
    while i < p {
        if first[fac[i]] == p { first[fac[i]] = i }
        i += 1usize
    }
    var c = MfCtx { a: a, s: sm, p: p, nf: nf, fac: fac, first: first, logs: ps.logdet(a, sm, p) }
    let nl = p - nf
    let ncor = nf * (nf - 1usize) / 2usize
    let m = nl + p + nf + ncor
    let (par, e3) = mem.alloc[f64](a, m)
    if e3 != ok { ret false }
    // starts: loadings 1, residual variance half the variance, factor variance the mean covariance of its indicators with each other (at least 0.05), no correlation
    i = 0usize
    while i < nl {
        par[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        par[nl + i] = math.log[f64](math.max[f64](0.5f64 * sm[i * p + i], 0.05f64))
        i += 1usize
    }
    u = 0usize
    while u < nf {
        var off = 0.0f64
        var cnt = 0.0f64
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                if i != j && fac[i] == u && fac[j] == u {
                    off += sm[i * p + j]
                    cnt += 1.0f64
                }
                j += 1usize
            }
            i += 1usize
        }
        par[nl + p + u] = math.log[f64](math.max[f64](off / cnt, 0.05f64))
        u += 1usize
    }
    i = 0usize
    while i < ncor {
        par[nl + p + nf + i] = 0.2f64
        i += 1usize
    }
    let (scr, e4) = mem.alloc[f64](a, (m + 1usize) * (m + 1usize) + 8usize * m + 64usize)
    if e4 != ok { ret false }
    var round = 0usize
    while round < 1usize {
        let (r1, e5) = opt.nelder_mead[MfCtx](&c, mf_f, par, 0.2f64, 1.0e-10f64, 2500u32, scr)
        if e5 != ok { ret false }
        round += 1usize
    }
    let (scb, e6) = mem.alloc[f64](a, 4usize * m * m + 16usize * m + 64usize)
    if e6 != ok { ret false }
    let (rb, e7) = opt.bfgs[MfCtx](&c, mf_f, mf_g, par, 1.0e-10f64, 500u32, scb)
    if e7 != ok { ret false }
    let fmin = mf_f(&c, par)
    var k = 0usize
    i = 0usize
    while i < p {
        if first[fac[i]] == i {
            out[i] = 1.0f64
        } else {
            out[i] = par[k]
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        out[p + i] = math.exp[f64](par[nl + i])
        i += 1usize
    }
    // the factor covariance matrix, lower triangle row-major
    var vv: [8]f64 = zero
    u = 0usize
    while u < nf {
        vv[u] = math.exp[f64](par[nl + p + u])
        u += 1usize
    }
    var o = 2usize * p
    var q = nl + p + nf
    u = 0usize
    while u < nf {
        var v = 0usize
        while v <= u {
            if v == u {
                out[o] = vv[u]
            } else {
                let ex2 = math.exp[f64](2.0f64 * par[q])
                out[o] = (ex2 - 1.0f64) / (ex2 + 1.0f64) * math.sqrt[f64](vv[u] * vv[v])
                q += 1usize
            }
            o += 1usize
            v += 1usize
        }
        u += 1usize
    }
    let npar = nl + p + nf * (nf + 1usize) / 2usize
    let df = f64(p * (p + 1usize) / 2usize) - f64(npar)
    out[o] = nn * fmin
    out[o + 1usize] = df
    out[o + 2usize] = nm.pchisq(nn * fmin, df, false, false)
    // the fit measures of lavaan at the estimates: out[o + 3 ..] the baseline chi-square (the independence model, n (sum log s_ii - log|S|)), its df, CFI, TLI, RMSEA, SRMR, logl, AIC, BIC
    let (sgf, e8) = mem.alloc[f64](a, p * p)
    let (sgi, e9) = mem.alloc[f64](a, p * p)
    if e8 != ok || e9 != ok { ret false }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            let fu = fac[i]
            let fv = fac[j]
            var hi = fu
            var lo = fv
            if fv > fu {
                hi = fv
                lo = fu
            }
            sgf[i * p + j] = out[i] * out[j] * out[2usize * p + hi * (hi + 1usize) / 2usize + lo]
            j += 1usize
        }
        sgf[i * p + i] += out[p + i]
        i += 1usize
    }
    if !ps.invert(a, sgf, p, sgi) { ret false }
    var trs = 0.0f64
    var sumlog = 0.0f64
    var srm = 0.0f64
    i = 0usize
    while i < p {
        sumlog += math.log[f64](sm[i * p + i])
        var j = 0usize
        while j < p {
            trs += sgi[i * p + j] * sm[j * p + i]
            if j <= i {
                let rr = (sm[i * p + j] - sgf[i * p + j]) / math.sqrt[f64](sm[i * p + i] * sm[j * p + j])
                srm += rr * rr
            }
            j += 1usize
        }
        i += 1usize
    }
    let chi = nn * fmin
    let cb = nn * (sumlog - c.logs)
    let dfb = f64(p * (p - 1usize) / 2usize)
    let d0 = math.max[f64](chi - df, 0.0f64)
    let denom = math.max[f64](math.max[f64](chi - df, cb - dfb), 0.0f64)
    var cfi = 1.0f64
    if denom > 0.0f64 { cfi = 1.0f64 - d0 / denom }
    let tli = ((cb / dfb) - (chi / df)) / ((cb / dfb) - 1.0f64)
    let logl = 0.0f64 - nn / 2.0f64 * (f64(p) * math.log[f64](2.0f64 * 3.141592653589793f64) + ps.logdet(a, sgf, p) + trs)
    out[o + 3usize] = cb
    out[o + 4usize] = dfb
    out[o + 5usize] = cfi
    out[o + 6usize] = tli
    out[o + 7usize] = math.sqrt[f64](d0 / (df * nn))
    out[o + 8usize] = math.sqrt[f64](srm / f64(p * (p + 1usize) / 2usize))
    out[o + 9usize] = logl
    out[o + 10usize] = 0.0f64 - 2.0f64 * logl + 2.0f64 * f64(npar)
    out[o + 11usize] = 0.0f64 - 2.0f64 * logl + f64(npar) * math.log[f64](nn)
    ret true
}

// the standard errors of `cfa_factors` from the expected information (n / 2) tr(Sigma^-1 dSigma_i Sigma^-1 dSigma_j) at its estimates est (the same layout): se receives, in order, the free loadings (indicator order, the first of each
// factor excluded), the residual variances, then the factor variances and covariances (lower triangle, row-major); false when the information is singular
fn cfa_factors_se(a: *mem.Arena, est: []const f64, n: usize, p: usize, nf: usize, fac: []const usize, se: []f64, vc: []f64) -> bool {
    let (first, e0) = mem.alloc[usize](a, nf)
    if e0 != ok { ret false }
    var u = 0usize
    while u < nf {
        first[u] = p
        u += 1usize
    }
    var i = 0usize
    while i < p {
        if first[fac[i]] == p { first[fac[i]] = i }
        i += 1usize
    }
    let nl = p - nf
    let nph = nf * (nf + 1usize) / 2usize
    let m = nl + p + nph
    let (sg, e1) = mem.alloc[f64](a, p * p)
    let (inv, e2) = mem.alloc[f64](a, p * p)
    let (ds, e3) = mem.alloc[f64](a, m * p * p)
    let (ms, e4) = mem.alloc[f64](a, m * p * p)
    let (info, e5) = mem.alloc[f64](a, m * m)
    let (mat, e6) = mem.alloc[f64](a, m * m)
    let (col, e7) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret false }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var hi = fac[i]
            var lo = fac[j]
            if fac[j] > fac[i] {
                hi = fac[j]
                lo = fac[i]
            }
            sg[i * p + j] = est[i] * est[j] * est[2usize * p + hi * (hi + 1usize) / 2usize + lo]
            j += 1usize
        }
        sg[i * p + i] += est[p + i]
        i += 1usize
    }
    if !ps.invert(a, sg, p, inv) { ret false }
    var z = 0usize
    while z < m * p * p {
        ds[z] = 0.0f64
        z += 1usize
    }
    // free loading of indicator k
    var q = 0usize
    var k = 0usize
    while k < p {
        if first[fac[k]] != k {
            var j = 0usize
            while j < p {
                var hi = fac[k]
                var lo = fac[j]
                if fac[j] > fac[k] {
                    hi = fac[j]
                    lo = fac[k]
                }
                let d = est[j] * est[2usize * p + hi * (hi + 1usize) / 2usize + lo]
                if j == k {
                    ds[q * p * p + k * p + k] += 2.0f64 * d
                } else {
                    ds[q * p * p + k * p + j] += d
                    ds[q * p * p + j * p + k] += d
                }
                j += 1usize
            }
            q += 1usize
        }
        k += 1usize
    }
    // residual variances
    i = 0usize
    while i < p {
        ds[(nl + i) * p * p + i * p + i] = 1.0f64
        i += 1usize
    }
    // factor variances and covariances: parameter (hi, lo) of the lower triangle
    var hi2 = 0usize
    while hi2 < nf {
        var lo2 = 0usize
        while lo2 <= hi2 {
            let qq = nl + p + hi2 * (hi2 + 1usize) / 2usize + lo2
            i = 0usize
            while i < p {
                var j = 0usize
                while j < p {
                    var hit = false
                    if fac[i] == hi2 && fac[j] == lo2 { hit = true }
                    if fac[i] == lo2 && fac[j] == hi2 { hit = true }
                    if hit {
                        var mult = 1.0f64
                        if hi2 == lo2 && fac[i] == fac[j] { mult = 1.0f64 }
                        ds[qq * p * p + i * p + j] = est[i] * est[j] * mult
                    }
                    j += 1usize
                }
                i += 1usize
            }
            lo2 += 1usize
        }
        hi2 += 1usize
    }
    q = 0usize
    while q < m {
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                var t = 0.0f64
                var l = 0usize
                while l < p {
                    t += inv[i * p + l] * ds[q * p * p + l * p + j]
                    l += 1usize
                }
                ms[q * p * p + i * p + j] = t
                j += 1usize
            }
            i += 1usize
        }
        q += 1usize
    }
    let nn = f64(n)
    q = 0usize
    while q < m {
        var r = 0usize
        while r < m {
            var t = 0.0f64
            i = 0usize
            while i < p {
                var j = 0usize
                while j < p {
                    t += ms[q * p * p + i * p + j] * ms[r * p * p + j * p + i]
                    j += 1usize
                }
                i += 1usize
            }
            info[q * m + r] = nn / 2.0f64 * t
            r += 1usize
        }
        q += 1usize
    }
    var c = 0usize
    while c < m {
        var r = 0usize
        while r < m * m {
            mat[r] = info[r]
            r += 1usize
        }
        r = 0usize
        while r < m {
            col[r] = 0.0f64
            r += 1usize
        }
        col[c] = 1.0f64
        if !qrb.solve_dense(mat, col, m) { ret false }
        se[c] = math.sqrt[f64](col[c])
        var vr = 0usize
        while vr < m {
            vc[vr * m + c] = col[vr]
            vr += 1usize
        }
        c += 1usize
    }
    ret true
}

// the regression f2 ~ f1 of a two-factor model (sem("f1 =~ ...; f2 =~ ...; f2 ~ f1")), a reparametrisation of the covariance structure of `cfa_factors` (same fit, same degrees of freedom): beta = phi21 / phi11,
// the variance of f1 phi11 and the residual variance of f2 psi2 = phi22 - phi21^2 / phi11, from the factor covariance matrix at est and the covariance matrix vc (m by m, the parameters of `cfa_factors_se`) of its estimates;
// nl is the number of free loadings and p the indicators. out[0 .. 3] the estimates (beta, phi11, psi2) and out[3 .. 6] their delta-method standard errors
fn sem_regression(est: []const f64, vc: []const f64, m: usize, nl: usize, p: usize, out: []f64) {
    let p11 = est[2usize * p]
    let p21 = est[2usize * p + 1usize]
    let p22 = est[2usize * p + 2usize]
    let k11 = nl + p
    let k21 = nl + p + 1usize
    let k22 = nl + p + 2usize
    out[0usize] = p21 / p11
    out[1usize] = p11
    out[2usize] = p22 - p21 * p21 / p11
    var g: [3]f64 = zero
    var r = 0usize
    while r < 3usize {
        if r == 0usize {
            g[0usize] = 0.0f64 - p21 / (p11 * p11)
            g[1usize] = 1.0f64 / p11
            g[2usize] = 0.0f64
        }
        if r == 1usize {
            g[0usize] = 1.0f64
            g[1usize] = 0.0f64
            g[2usize] = 0.0f64
        }
        if r == 2usize {
            g[0usize] = p21 * p21 / (p11 * p11)
            g[1usize] = 0.0f64 - 2.0f64 * p21 / p11
            g[2usize] = 1.0f64
        }
        var v = 0.0f64
        var a1 = 0usize
        while a1 < 3usize {
            var b1 = 0usize
            while b1 < 3usize {
                var ia = k11
                if a1 == 1usize { ia = k21 }
                if a1 == 2usize { ia = k22 }
                var ib = k11
                if b1 == 1usize { ib = k21 }
                if b1 == 2usize { ib = k22 }
                v += g[a1] * vc[ia * m + ib] * g[b1]
                b1 += 1usize
            }
            a1 += 1usize
        }
        out[3usize + r] = math.sqrt[f64](v)
        r += 1usize
    }
}
