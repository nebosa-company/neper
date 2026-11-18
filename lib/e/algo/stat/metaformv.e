// R metafor rma.mv: the multivariate and multilevel random-effects model y = X b + u + e with Var(e) = V (a vector of sampling variances or a full matrix), Var(u) = sum_j sigma2_j Z_j Z_j'
// (one variance per random intercept, each over its own grouping variable) + (Z1 G Z1') * (Z2 Z2') for a ~ inner | outer term with the structures CS, HCS, DIAG, ID, AR and HAR.
//
// The likelihood is R's .ll.rma.mv on the log (variances) and atanh (correlations) scale, ML or REML with REMLf; the starting values are rma.mv's; the optimisation is R's optim with
// Nelder-Mead (nmmin, reltol 1.49e-8, 500 evaluations) or BFGS (vmmin with the central-difference gradient of optim, ndeps 1e-3, 100 iterations), step for step as R runs them, or the
// default optimizer, nlminb (e.algo.stat.nlminb, PORT with finite-difference gradients and no bounds), which makes R's evaluations one for one.
//
// Not here: see metaformv2 for the Hessian based vvc, UN, CAR, GEN, spatial structures, the second random term (H), user weights (A), knha/adhoc, dfs and fixed components;
// phylogenetic structures, R matrices and sparse matrices are in neither.

use e.math
use e.mem
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.scale as sc
use e.algo.stat.rnm as nmd
use e.algo.stat.rbfgs as bf
use e.algo.stat.nlminb as nlmb

const MVOUT: usize = 160usize

type Mv = struct {
    a: *mem.Arena, k: usize, p: usize, y: []const f64, x: []const f64, v: []const f64, ns: usize, sid: []const f64, gk: usize, nin: usize, inner: []const f64, outer: []const f64,
    reml: bool, m: []f64, w: []f64, l: []f64, aug: []f64, xtwx: []f64, sinv: []f64, paug: []f64, beta: []f64, vb: []f64, res: []f64, tmpv: []f64, ev: []f64, ee: []f64,
    llml: f64, llreml: f64, ntau: usize, nrho: usize, sig: []f64, tau: []f64, rho: []f64, step: f64, count: usize
}

fn nanv() -> f64 { ret 0.0f64 / 0.0f64 }

// the numbers of tau2 and rho parameters of a structure: 1 CS (1 and 1), 2 HCS (nin and 1), 3 DIAG (nin and 0), 4 ID (1 and 0), 5 AR (1 and 1), 6 HAR (nin and 1)
fn ntau_of(gk: usize, nin: usize) -> usize {
    if gk == 0usize { ret 0usize }
    if gk == 2usize || gk == 3usize || gk == 6usize { ret nin }
    ret 1usize
}

fn nrho_of(gk: usize) -> usize {
    if gk == 1usize || gk == 2usize || gk == 5usize || gk == 6usize { ret 1usize }
    ret 0usize
}

fn eps10() -> f64 { ret 10.0f64 * 2.220446049250313e-16f64 }

// the Cholesky factor of the n by n symmetric m into l (lower), false when not positive definite
fn chol_of(m: []const f64, n: usize, l: []f64) -> bool {
    var j = 0usize
    while j < n {
        var s = m[j * n + j]
        var q = 0usize
        while q < j {
            s -= l[j * n + q] * l[j * n + q]
            q += 1usize
        }
        if !(s > 0.0f64) { ret false }
        let d = math.sqrt[f64](s)
        l[j * n + j] = d
        var i = j + 1usize
        while i < n {
            var t = m[i * n + j]
            q = 0usize
            while q < j {
                t -= l[i * n + q] * l[j * n + q]
                q += 1usize
            }
            l[i * n + j] = t / d
            i += 1usize
        }
        var u = j + 1usize
        while u < n {
            l[j * n + u] = 0.0f64
            u += 1usize
        }
        j += 1usize
    }
    ret true
}

// out = chol2inv: the inverse of l l' for the lower factor l; also the log determinant of the matrix
fn chol_inv(l: []const f64, n: usize, w: []f64, tmp: []f64) -> f64 {
    // tmp = inverse of l (lower triangular)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = 0.0f64
            if i == j { s = 1.0f64 }
            var q = j
            while q < i {
                s -= l[i * n + q] * tmp[q * n + j]
                q += 1usize
            }
            tmp[i * n + j] = s / l[i * n + i]
            j += 1usize
        }
        var u = i + 1usize
        while u < n {
            tmp[i * n + u] = 0.0f64
            u += 1usize
        }
        i += 1usize
    }
    // w = tmp' tmp
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var q = if_max(i, j)
            while q < n {
                s += tmp[q * n + i] * tmp[q * n + j]
                q += 1usize
            }
            w[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
    var ld = 0.0f64
    i = 0usize
    while i < n {
        ld += 2.0f64 * math.log[f64](l[i * n + i])
        i += 1usize
    }
    ret ld
}

fn if_max(a: usize, b: usize) -> usize {
    if a > b { ret a }
    ret b
}

// log of the (positive) determinant of the p by p matrix via its Cholesky factor, false when it fails
fn logdet_spd(m: []const f64, n: usize, l: []f64) -> f64 {
    if !chol_of(m, n, l) { ret nanv() }
    var ld = 0.0f64
    var i = 0usize
    while i < n {
        ld += 2.0f64 * math.log[f64](l[i * n + i])
        i += 1usize
    }
    ret ld
}

// the inner by inner matrix E of the ~ inner | outer term for the parameters tau (variances) and rho (the correlation)
fn make_e(c: *Mv, tau: []const f64, rho: f64, e: []f64) {
    let n = c.nin
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var v = 0.0f64
            let gk = c.gk
            if gk == 1usize {
                if i == j { v = tau[0usize] } else { v = rho * tau[0usize] }
            }
            if gk == 2usize {
                if i == j { v = tau[i] } else { v = rho * math.sqrt[f64](tau[i]) * math.sqrt[f64](tau[j]) }
            }
            if gk == 3usize {
                if i == j { v = tau[i] }
            }
            if gk == 4usize {
                if i == j { v = tau[0usize] }
            }
            if gk == 5usize || gk == 6usize {
                var dd = i
                if j > i { dd = j - i } else { dd = i - j }
                let r = math.pow[f64](rho, f64(dd))
                if gk == 5usize {
                    if i == j { v = tau[0usize] } else { v = tau[0usize] * r }
                } else {
                    if i == j { v = tau[i] } else { v = math.sqrt[f64](tau[i]) * math.sqrt[f64](tau[j]) * r }
                }
            }
            e[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

// R's .ll.rma.mv for the parameters par on the transformed scale: sets beta, vb, llml, llreml and the variance components; returns -1 times the log-likelihood chosen by reml
fn mv_nll(c: *Mv, par: []const f64) -> f64 {
    let k = c.k
    let p = c.p
    var i = 0usize
    while i < k * k {
        c.m[i] = c.v[i]
        i += 1usize
    }
    var j = 0usize
    while j < c.ns {
        var s2 = math.exp[f64](par[j])
        if s2 <= eps10() { s2 = 0.0f64 }
        c.sig[j] = s2
        i = 0usize
        while i < k {
            var q = 0usize
            while q < k {
                if c.sid[j * k + i] == c.sid[j * k + q] { c.m[i * k + q] += s2 }
                q += 1usize
            }
            i += 1usize
        }
        j += 1usize
    }
    if c.gk > 0usize {
        var t = 0usize
        while t < c.ntau {
            var v = math.exp[f64](par[slot_s(c) + t])
            if v <= eps10() { v = 0.0f64 }
            c.tau[t] = v
            t += 1usize
        }
        var r = 0.0f64
        if c.nrho > 0usize {
            r = sc.tanh(par[slot_s(c) + slot_t(c)])
            c.rho[0usize] = r
        }
        make_e(c, c.tau, r, c.ee)
        i = 0usize
        while i < k {
            var q = 0usize
            while q < k {
                if c.outer[i] == c.outer[q] { c.m[i * k + q] += c.ee[usize(c.inner[i]) * c.nin + usize(c.inner[q])] }
                q += 1usize
            }
            i += 1usize
        }
    }
    if !chol_of(c.m, k, c.l) {
        c.llml = 0.0f64 - 1.0f64 / 0.0f64
        c.llreml = c.llml
        ret 1.0f64 / 0.0f64
    }
    let ldm = chol_inv(c.l, k, c.w, c.aug)
    // X' W X, its inverse and beta
    var a = 0usize
    while a < p {
        var b = 0usize
        while b < p {
            var s = 0.0f64
            i = 0usize
            while i < k {
                var q = 0usize
                while q < k {
                    s += c.x[i * p + a] * c.w[i * k + q] * c.x[q * p + b]
                    q += 1usize
                }
                i += 1usize
            }
            c.xtwx[a * p + b] = s
            b += 1usize
        }
        a += 1usize
    }
    if !chol_of(c.xtwx, p, c.paug) {
        c.llml = 0.0f64 - 1.0f64 / 0.0f64
        c.llreml = c.llml
        ret 1.0f64 / 0.0f64
    }
    let ldxwx = chol_inv(c.paug, p, c.sinv, c.ev)
    a = 0usize
    while a < p {
        var s = 0.0f64
        i = 0usize
        while i < k {
            var q = 0usize
            while q < k {
                s += c.x[i * p + a] * c.w[i * k + q] * c.y[q]
                q += 1usize
            }
            i += 1usize
        }
        c.tmpv[a] = s
        a += 1usize
    }
    a = 0usize
    while a < p {
        var s = 0.0f64
        var b = 0usize
        while b < p {
            s += c.sinv[a * p + b] * c.tmpv[b]
            b += 1usize
        }
        c.beta[a] = s
        b = 0usize
        while b < p {
            c.vb[a * p + b] = c.sinv[a * p + b]
            b += 1usize
        }
        a += 1usize
    }
    i = 0usize
    while i < k {
        var f = 0.0f64
        a = 0usize
        while a < p {
            f += c.x[i * p + a] * c.beta[a]
            a += 1usize
        }
        c.res[i] = c.y[i] - f
        i += 1usize
    }
    var rss = 0.0f64
    i = 0usize
    while i < k {
        var q = 0usize
        while q < k {
            rss += c.res[i] * c.w[i * k + q] * c.res[q]
            q += 1usize
        }
        i += 1usize
    }
    let kf = f64(k)
    let pf = f64(p)
    let pi2 = 2.0f64 * 3.141592653589793f64
    c.llml = 0.0f64 - 0.5f64 * kf * math.log[f64](pi2) - 0.5f64 * ldm - 0.5f64 * rss
    // log det X'X
    a = 0usize
    while a < p {
        var b = 0usize
        while b < p {
            var s = 0.0f64
            i = 0usize
            while i < k {
                s += c.x[i * p + a] * c.x[i * p + b]
                i += 1usize
            }
            c.xtwx[a * p + b] = s
            b += 1usize
        }
        a += 1usize
    }
    let ldxx = logdet_spd(c.xtwx, p, c.paug)
    c.llreml = 0.0f64 - 0.5f64 * (kf - pf) * math.log[f64](pi2) + 0.5f64 * ldxx - 0.5f64 * ldm - 0.5f64 * ldxwx - 0.5f64 * rss
    c.count += 1usize
    if c.reml { ret 0.0f64 - c.llreml }
    ret 0.0f64 - c.llml
}

fn mv_f(c: *Mv, par: []const f64) -> f64 { ret mv_nll(c, par) }

// optim's finite-difference gradient (ndeps = step)
fn mv_g(c: *Mv, par: []const f64, g: []f64) {
    let n = par.len
    var i = 0usize
    while i < n {
        let hold = par[i]
        let (cp, e) = mem.alloc[f64](c.a, n)
        if e != ok { ret }
        var j = 0usize
        while j < n {
            cp[j] = par[j]
            j += 1usize
        }
        cp[i] = hold + c.step
        let v1 = mv_nll(c, cp)
        cp[i] = hold - c.step
        let v2 = mv_nll(c, cp)
        g[i] = (v1 - v2) / (2.0f64 * c.step)
        i += 1usize
    }
}

fn slot_s(c: *Mv) -> usize {
    if c.ns == 0usize { ret 1usize }
    ret c.ns
}

fn slot_t(c: *Mv) -> usize {
    if c.ntau == 0usize { ret 1usize }
    ret c.ntau
}

// rma.mv's sigma2s + tau2s + gamma2s, in which an absent term still counts one variance
fn denom_of(c: *Mv) -> usize {
    var s = c.ns
    if s == 0usize { s = 1usize }
    var t = c.ntau
    if t == 0usize { t = 1usize }
    ret s + t + 1usize
}

// the mean of 1 / diag(V) and the like for the starting values; returns the total variance R starts from
fn start_total(c: *Mv) -> f64 {
    let k = c.k
    let p = c.p
    let kf = f64(k)
    // V must be invertible: chol of V, the GLS fit with V
    if !chol_of(c.v, k, c.l) { ret nanv() }
    let _ = chol_inv(c.l, k, c.w, c.aug)
    var a = 0usize
    while a < p {
        var b = 0usize
        while b < p {
            var s = 0.0f64
            var i = 0usize
            while i < k {
                var q = 0usize
                while q < k {
                    s += c.x[i * p + a] * c.w[i * k + q] * c.x[q * p + b]
                    q += 1usize
                }
                i += 1usize
            }
            c.xtwx[a * p + b] = s
            b += 1usize
        }
        a += 1usize
    }
    if !chol_of(c.xtwx, p, c.paug) { ret nanv() }
    let _ = chol_inv(c.paug, p, c.sinv, c.ev)
    a = 0usize
    while a < p {
        var s = 0.0f64
        var i = 0usize
        while i < k {
            var q = 0usize
            while q < k {
                s += c.x[i * p + a] * c.w[i * k + q] * c.y[q]
                q += 1usize
            }
            i += 1usize
        }
        c.tmpv[a] = s
        a += 1usize
    }
    var i = 0usize
    var mean = 0.0f64
    while i < k {
        var f = 0.0f64
        a = 0usize
        while a < p {
            var s = 0.0f64
            var b = 0usize
            while b < p {
                s += c.sinv[a * p + b] * c.tmpv[b]
                b += 1usize
            }
            f += c.x[i * p + a] * s
            a += 1usize
        }
        c.res[i] = c.y[i] - f
        mean += c.res[i]
        i += 1usize
    }
    mean = mean / kf
    var vr = 0.0f64
    var mi = 0.0f64
    i = 0usize
    while i < k {
        vr += (c.res[i] - mean) * (c.res[i] - mean)
        mi += 1.0f64 / c.v[i * k + i]
        i += 1usize
    }
    vr = vr / (kf - 1.0f64)
    mi = mi / kf
    var tot = vr - 1.0f64 / mi
    let lo = 0.001f64 * f64(denom_of(c))
    if tot < lo { tot = lo }
    ret tot
}

// fit rma.mv: optimizer 0 Nelder-Mead, 1 BFGS, 2 nlminb; out per the layout at the top of metaformvrun
fn fit_mv(c: *Mv, optimizer: usize, test: usize, out: []f64) {
    let a = c.a
    let k = c.k
    let p = c.p
    c.ntau = ntau_of(c.gk, c.nin)
    c.nrho = nrho_of(c.gk)
    var i = 0usize
    while i < out.len {
        out[i] = nanv()
        i += 1usize
    }
    // optim runs over sigma2s + tau2s + rhos + gamma2s + phis values in which an absent term keeps one unused slot (a sigma2 and a tau2 and a rho and a gamma2 and a phi)
    let np = slot_s(c) + slot_t(c) + 3usize
    let total = start_total(c)
    if total != total { ret }
    let init = total / f64(denom_of(c))
    let (par, e1) = mem.alloc[f64](a, np)
    if e1 != ok { ret }
    i = 0usize
    while i < np {
        par[i] = math.log[f64](init)
        i += 1usize
    }
    par[slot_s(c) + slot_t(c)] = sc.atanh(0.5f64)
    par[slot_s(c) + slot_t(c) + 2usize] = sc.atanh(0.5f64)
    c.count = 0usize
    c.step = 0.001f64
    if optimizer == 0usize {
        let (best, e2) = mem.alloc[f64](a, np)
        if e2 != ok { ret }
        let (fm, fc, fail) = nmd.nmmin[Mv](a, c, mv_f, par, 0.0f64 - 1.0f64 / 0.0f64, 1.490116119384766e-08f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, best)
        let _ = fm
        let _ = fc
        let _ = fail
        i = 0usize
        while i < np {
            par[i] = best[i]
            i += 1usize
        }
    } else if optimizer == 2usize {
        let nlm = nlmb.nlminb[Mv](a, c, mv_f, mv_g, false, par, par[0usize..0usize])
        let _ = nlm
    } else {
        let _ = bf.vmmin[Mv](a, c, mv_f, mv_g, par, 1.490116119384766e-08f64, 100usize)
    }
    let nfn = c.count
    let _ = mv_nll(c, par)
    // the results
    i = 0usize
    while i < c.ns {
        out[i] = c.sig[i]
        i += 1usize
    }
    i = 0usize
    while i < c.ntau {
        out[8usize + i] = c.tau[i]
        i += 1usize
    }
    if c.nrho > 0usize { out[16usize] = c.rho[0usize] }
    if c.gk > 0usize && c.nrho == 0usize { out[16usize] = 0.0f64 }
    let alpha = 0.05f64
    var ddf = nanv()
    if test == 1usize { ddf = f64(k - p) }
    var crit = dist.qnorm(alpha / 2.0f64, 0.0f64, 1.0f64, false, false)
    if test == 1usize { crit = nb.qt(alpha / 2.0f64, ddf, false, false) }
    var a2 = 0usize
    while a2 < p {
        let se = math.sqrt[f64](c.vb[a2 * p + a2])
        let z = c.beta[a2] / se
        out[24usize + a2] = c.beta[a2]
        out[32usize + a2] = se
        out[40usize + a2] = z
        if test == 1usize { out[48usize + a2] = 2.0f64 * nb.pt(math.abs[f64](z), ddf, false, false) } else { out[48usize + a2] = 2.0f64 * dist.pnorm(math.abs[f64](z), 0.0f64, 1.0f64, false, false) }
        out[56usize + a2] = c.beta[a2] - crit * se
        out[64usize + a2] = c.beta[a2] + crit * se
        var b2 = 0usize
        while b2 < p {
            out[72usize + a2 * p + b2] = c.vb[a2 * p + b2]
            b2 += 1usize
        }
        a2 += 1usize
    }
    // QE with V only (GLS with V), QM over the moderators
    let ts = start_total(c)
    let _ = ts
    var qe = 0.0f64
    i = 0usize
    while i < k {
        var q = 0usize
        while q < k {
            qe += c.res[i] * c.w[i * k + q] * c.res[q]
            q += 1usize
        }
        i += 1usize
    }
    out[136usize] = qe
    out[137usize] = nm.pchisq(qe, f64(k - p), false, false)
    let _ = mv_nll(c, par)
    var btt0 = 0usize
    if c.p > 1usize { btt0 = 1usize }
    let m = p - btt0
    var qm = nanv()
    if m > 0usize {
        let (sub, e3) = mem.alloc[f64](a, m * m)
        let (inv, e4) = mem.alloc[f64](a, m * m)
        let (ag, e5) = mem.alloc[f64](a, 2usize * m * m)
        if e3 == ok && e4 == ok && e5 == ok {
            var r1 = 0usize
            while r1 < m {
                var c1 = 0usize
                while c1 < m {
                    sub[r1 * m + c1] = c.vb[(r1 + btt0) * p + c1 + btt0]
                    c1 += 1usize
                }
                r1 += 1usize
            }
            if chol_of(sub, m, ag) {
                let _ = chol_inv(ag, m, inv, ag[m * m..2usize * m * m])
                qm = 0.0f64
                r1 = 0usize
                while r1 < m {
                    var c1 = 0usize
                    while c1 < m {
                        qm += c.beta[r1 + btt0] * inv[r1 * m + c1] * c.beta[c1 + btt0]
                        c1 += 1usize
                    }
                    r1 += 1usize
                }
            }
        }
    }
    if test == 1usize {
        qm = qm / f64(m)
        out[138usize] = qm
        out[139usize] = nb.pf(qm, f64(m), ddf, false, false)
    } else {
        out[138usize] = qm
        out[139usize] = nm.pchisq(qm, f64(m), false, false)
    }
    out[140usize] = c.llml
    out[141usize] = c.llreml
    out[143usize] = f64(nfn)
}

// the case of the oracle: args = [reml, test, optimizer, k, p, ns, gk, nin, vmode (0 the vector vi, 1 the full matrix), y (k), X (k p, row-major), V (k or k k), group ids (ns k), inner (k), outer (k)]
// out: 0 .. 7 sigma2, 8 .. 15 tau2, 16 rho, 24 beta, 32 se, 40 zval, 48 pval, 56 ci.lb, 64 ci.ub, 72 vb, 136 QE, 137 QEp, 138 QM, 139 QMp, 140 ll ML, 141 ll REML, 143 evaluations
fn mv_run(a: *mem.Arena, args: []const f64, out: []f64) -> bool {
    var c: Mv = zero
    c.a = a
    c.reml = args[0usize] != 0.0f64
    let test = usize(args[1usize])
    let optimizer = usize(args[2usize])
    let k = usize(args[3usize])
    let p = usize(args[4usize])
    c.k = k
    c.p = p
    c.ns = usize(args[5usize])
    c.gk = usize(args[6usize])
    c.nin = usize(args[7usize])
    let vmode = usize(args[8usize])
    var at = 9usize
    c.y = args[at..at + k]
    at += k
    c.x = args[at..at + k * p]
    at += k * p
    let (vfull, e0) = mem.alloc[f64](a, k * k)
    if e0 != ok { ret false }
    var i = 0usize
    while i < k * k {
        vfull[i] = 0.0f64
        i += 1usize
    }
    if vmode == 0usize {
        i = 0usize
        while i < k {
            vfull[i * k + i] = args[at + i]
            i += 1usize
        }
        at += k
    } else {
        i = 0usize
        while i < k * k {
            vfull[i] = args[at + i]
            i += 1usize
        }
        at += k * k
    }
    c.v = vfull
    c.sid = args[at..at + c.ns * k]
    at += c.ns * k
    c.inner = args[at..at + k]
    at += k
    c.outer = args[at..at + k]
    let (m1, ea) = mem.alloc[f64](a, k * k)
    let (w1, eb) = mem.alloc[f64](a, k * k)
    let (l1, ec) = mem.alloc[f64](a, k * k)
    let (au, ed) = mem.alloc[f64](a, 2usize * k * k)
    let (xt, ee) = mem.alloc[f64](a, p * p)
    let (si, ef) = mem.alloc[f64](a, p * p)
    let (pa, eg) = mem.alloc[f64](a, 2usize * p * p)
    let (be, eh) = mem.alloc[f64](a, p)
    let (vb, ei) = mem.alloc[f64](a, p * p)
    let (rs, ej) = mem.alloc[f64](a, k)
    let (tv, ek) = mem.alloc[f64](a, k + p)
    let (ev, el) = mem.alloc[f64](a, p * p + k)
    let (ee2, em) = mem.alloc[f64](a, c.nin * c.nin + 1usize)
    let (sg, en) = mem.alloc[f64](a, c.ns + 1usize)
    let (ta, eo) = mem.alloc[f64](a, c.nin + 1usize)
    let (rh, ep) = mem.alloc[f64](a, 2usize)
    if ea != ok || eb != ok || ec != ok || ed != ok || ee != ok || ef != ok || eg != ok || eh != ok || ei != ok || ej != ok || ek != ok || el != ok || em != ok || en != ok || eo != ok || ep != ok { ret false }
    c.m = m1
    c.w = w1
    c.l = l1
    c.aug = au
    c.xtwx = xt
    c.sinv = si
    c.paug = pa
    c.beta = be
    c.vb = vb
    c.res = rs
    c.tmpv = tv
    c.ev = ev
    c.ee = ee2
    c.sig = sg
    c.tau = ta
    c.rho = rh
    fit_mv(&c, optimizer, test, out)
    ret true
}
