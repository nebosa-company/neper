// R MCMCpack::MCMCfactanal: the Normal theory factor model by Gibbs sampling (scores phi, loadings Lambda with equality and sign constraints,
// uniquenesses Psi with inverse gamma priors) on the Scythe Mersenne-Twister stream, with R's default start values
// (zero, +-0.5 or the constrained loading; Psi = 0.5 var(X)) and the standardising of x.
//
// Not here: user-supplied lambda.start and psi.start.

use e.algo.stat.mcmcpacksamp as ms
use e.math
use e.mem

// x is n by kn row-major (raw data); lam_eq, lam_ineq, l0 and big_l0 are kn by d row-major (eq -999 when free); a0 and b0 have kn entries.
// out is nsamp rows of (Lambda[kn*d], Psi[kn], and phi[n*d] when scores)
fn factanal(a: *mem.Arena, g: *ms.Sc, x_in: []const f64, n: usize, kn: usize, d: usize, std_var: bool, lam_eq: []const f64, lam_ineq: []const f64, l0: []const f64, big_l0: []const f64, a0: []const f64, b0: []const f64, burnin: usize, mcmc: usize, thin: usize, scores: bool, out: []f64) -> err {
    let (x, e1) = mem.alloc[f64](a, n * kn)
    let (lam, e2) = mem.alloc[f64](a, kn * d)
    let (psi, e3) = mem.alloc[f64](a, kn)
    let (pinv, e4) = mem.alloc[f64](a, kn)
    let (phi, e5) = mem.alloc[f64](a, n * d)
    let (m1, e6) = mem.alloc[f64](a, d * d)
    let (pv, e7) = mem.alloc[f64](a, d * d)
    let (pc, e8) = mem.alloc[f64](a, d * d)
    let (zz, e9) = mem.alloc[f64](a, d)
    let (mu, e10) = mem.alloc[f64](a, d)
    let (idx, e11) = mem.alloc[f64](a, d)
    let (nx, e12) = mem.alloc[f64](a, n)
    let (dr, e13) = mem.alloc[f64](a, d)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    // standardise the columns
    var i = 0usize
    var j = 0usize
    var t = 0usize
    while j < kn {
        var s = 0.0f64
        t = 0usize
        while t < n {
            s += x_in[t * kn + j]
            t += 1usize
        }
        let mean = s / f64(n)
        var ss = 0.0f64
        t = 0usize
        while t < n {
            ss += math.pow[f64](x_in[t * kn + j] - mean, 2.0f64)
            t += 1usize
        }
        let sd = math.sqrt[f64](ss / f64(n - 1usize))
        t = 0usize
        while t < n {
            if std_var { x[t * kn + j] = (x_in[t * kn + j] - mean) / sd } else { x[t * kn + j] = x_in[t * kn + j] - mean }
            t += 1usize
        }
        // Psi starts at 0.5 var(X) of the standardised column
        var m2 = 0.0f64
        t = 0usize
        while t < n {
            m2 += x[t * kn + j]
            t += 1usize
        }
        m2 = m2 / f64(n)
        var v2 = 0.0f64
        t = 0usize
        while t < n {
            v2 += math.pow[f64](x[t * kn + j] - m2, 2.0f64)
            t += 1usize
        }
        psi[j] = 0.5f64 * (v2 / f64(n - 1usize))
        pinv[j] = 1.0f64 / psi[j]
        j += 1usize
    }
    // start loadings
    i = 0usize
    while i < kn * d {
        if lam_eq[i] == -999.0f64 {
            lam[i] = 0.0f64
            if lam_ineq[i] > 0.0f64 { lam[i] = 0.5f64 }
            if lam_ineq[i] < 0.0f64 { lam[i] = -0.5f64 }
        } else { lam[i] = lam_eq[i] }
        i += 1usize
    }
    var ld = 0.0f64
    let width = kn * d + kn
    var count = 0usize
    var iter = 0usize
    while iter < burnin + mcmc {
        // scores: phi_i ~ N(V Lambda' Psi^-1 x_i, V) with V = (I + Lambda' Psi^-1 Lambda)^-1
        i = 0usize
        while i < d {
            j = 0usize
            while j < d {
                var s = 0.0f64
                if i == j { s = 1.0f64 }
                var k = 0usize
                while k < kn {
                    s += pinv[k] * lam[k * d + i] * lam[k * d + j]
                    k += 1usize
                }
                m1[i * d + j] = s
                j += 1usize
            }
            i += 1usize
        }
        if ms.inv_pd(a, m1, d, pv, &ld) != ok { ret ms.NotPd }
        if !ms.chol(pv, d, pc) { ret ms.NotPd }
        t = 0usize
        while t < n {
            i = 0usize
            while i < d {
                var s = 0.0f64
                var k = 0usize
                while k < kn {
                    s += lam[k * d + i] * pinv[k] * x[t * kn + k]
                    k += 1usize
                }
                idx[i] = s
                zz[i] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
                i += 1usize
            }
            i = 0usize
            while i < d {
                var s = 0.0f64
                j = 0usize
                while j < d {
                    s += pv[i * d + j] * idx[j]
                    j += 1usize
                }
                mu[i] = s
                i += 1usize
            }
            i = 0usize
            while i < d {
                var s = mu[i]
                j = 0usize
                while j <= i {
                    s += pc[i * d + j] * zz[j]
                    j += 1usize
                }
                phi[t * d + i] = s
                i += 1usize
            }
            t += 1usize
        }
        let el = lambda_draw(a, g, lam, phi, x, pinv, n, kn, d, lam_eq, lam_ineq, l0, big_l0)
        if el != ok { ret el }
        var k = 0usize
        // uniquenesses
        k = 0usize
        while k < kn {
            var sse = 0.0f64
            t = 0usize
            while t < n {
                var s = x[t * kn + k]
                j = 0usize
                while j < d {
                    s -= phi[t * d + j] * lam[k * d + j]
                    j += 1usize
                }
                sse += s * s
                t += 1usize
            }
            let a1 = (a0[k] + f64(n)) * 0.5f64
            let b1 = (b0[k] + sse) * 0.5f64
            psi[k] = ms.sc_rigamma(g, a1, b1)
            k += 1usize
        }
        k = 0usize
        while k < kn {
            pinv[k] = 1.0f64 / psi[k]
            k += 1usize
        }
        if iter >= burnin && iter % thin == 0usize {
            var o = count * (width + n * d)
            if !scores { o = count * width }
            i = 0usize
            while i < kn * d {
                out[o + i] = lam[i]
                i += 1usize
            }
            k = 0usize
            while k < kn {
                out[o + kn * d + k] = psi[k]
                k += 1usize
            }
            if scores {
                i = 0usize
                while i < n * d {
                    out[o + width + i] = phi[i]
                    i += 1usize
                }
            }
            count += 1usize
        }
        iter += 1usize
    }
    ret ok
}

// One Gibbs sweep over the loadings (Scythe NormNormfactanal_Lambda_draw): lam is kn by d, phi n by d, x n by kn, pinv the inverse uniquenesses
fn lambda_draw(a: *mem.Arena, g: *ms.Sc, lam: []f64, phi: []const f64, x: []const f64, pinv: []const f64, n: usize, kn: usize, d: usize, lam_eq: []const f64, lam_ineq: []const f64, l0: []const f64, big_l0: []const f64) -> err {
    let mark = mem.mark(a)
    let (m1, e6) = mem.alloc[f64](a, d * d)
    let (pv, e7) = mem.alloc[f64](a, d * d)
    let (pc, e8) = mem.alloc[f64](a, d * d)
    let (zz, e9) = mem.alloc[f64](a, d)
    let (mu, e10) = mem.alloc[f64](a, d)
    let (idx, e11) = mem.alloc[f64](a, d)
    let (nx, e12) = mem.alloc[f64](a, n)
    let (dr, e13) = mem.alloc[f64](a, d)
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    var ld = 0.0f64
    var t = 0usize
    var j = 0usize
        var k = 0usize
        while k < kn {
            var nf = 0usize
            j = 0usize
            while j < d {
                if lam_eq[k * d + j] == -999.0f64 { nf += 1usize }
                j += 1usize
            }
            if nf > 0usize {
                // free columns in idx order
                var fi = 0usize
                j = 0usize
                while j < d {
                    if lam_eq[k * d + j] == -999.0f64 {
                        idx[fi] = f64(j)
                        fi += 1usize
                    }
                    j += 1usize
                }
                t = 0usize
                while t < n {
                    var s = x[t * kn + k]
                    j = 0usize
                    while j < d {
                        if lam_eq[k * d + j] != -999.0f64 { s -= phi[t * d + j] * lam[k * d + j] }
                        j += 1usize
                    }
                    nx[t] = s
                    t += 1usize
                }
                // precision (nf by nf in m1) and right-hand side
                var p = 0usize
                while p < nf {
                    var q = 0usize
                    while q < nf {
                        var s = 0.0f64
                        t = 0usize
                        while t < n {
                            s += phi[t * d + usize(idx[p])] * phi[t * d + usize(idx[q])]
                            t += 1usize
                        }
                        var pr = pinv[k] * s
                        if p == q { pr += big_l0[k * d + usize(idx[p])] }
                        m1[p * nf + q] = pr
                        q += 1usize
                    }
                    p += 1usize
                }
                if ms.inv_pd(a, m1[0usize..nf * nf], nf, pv, &ld) != ok { ret ms.NotPd }
                if !ms.chol(pv, nf, pc) { ret ms.NotPd }
                p = 0usize
                while p < nf {
                    var s = big_l0[k * d + usize(idx[p])] * l0[k * d + usize(idx[p])]
                    t = 0usize
                    while t < n {
                        s += pinv[k] * phi[t * d + usize(idx[p])] * nx[t]
                        t += 1usize
                    }
                    zz[p] = s
                    p += 1usize
                }
                p = 0usize
                while p < nf {
                    var s = 0.0f64
                    var q = 0usize
                    while q < nf {
                        s += pv[p * nf + q] * zz[q]
                        q += 1usize
                    }
                    mu[p] = s
                    p += 1usize
                }
                var holds = false
                while !holds {
                    p = 0usize
                    while p < nf {
                        zz[p] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
                        p += 1usize
                    }
                    p = 0usize
                    while p < nf {
                        var s = mu[p]
                        var q = 0usize
                        while q <= p {
                            s += pc[p * nf + q] * zz[q]
                            q += 1usize
                        }
                        dr[p] = s
                        p += 1usize
                    }
                    var test = 0.0f64
                    p = 0usize
                    while p < nf {
                        let pr = lam_ineq[k * d + usize(idx[p])] * dr[p]
                        if pr < test { test = pr }
                        p += 1usize
                    }
                    holds = !(test < 0.0f64)
                }
                p = 0usize
                while p < nf {
                    lam[k * d + usize(idx[p])] = dr[p]
                    p += 1usize
                }
            }
            k += 1usize
        }
    mem.reset(a, mark)
    ret ok
}
