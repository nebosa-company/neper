// lavaan: maximum-likelihood confirmatory factor analysis of one factor measured by p indicators (cfa("f =~ x1 + ... + xp"), the first loading fixed at 1, free residual variances and factor variance), from the
// sample covariance matrix: parameter estimates, the chi-square test of the model and its degrees of freedom, with lavaan's normal-theory likelihood (the covariance divided by n).
//
// Not here: several factors, means, standard errors, the other estimators, fit indices beyond chi-square, categorical data, general model syntax.

use e.algo.stat.psych as ps
use e.math
use e.math.nmath as nm
use e.math.opt as opt
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
