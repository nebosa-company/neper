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
