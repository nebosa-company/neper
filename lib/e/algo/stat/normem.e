// R norm, the EM part: `em_norm` (maximum likelihood estimates of the mean and covariance of multivariate normal
// data with missing values, by EM on the standardised columns exactly as norm::em.norm iterates, so the iterate at
// which the 1e-4 criterion stops is the package's) and `loglik_norm` (the observed-data log-likelihood).
// Missing values are NaN; no row may be entirely missing.
//
// Not here: priors (ecm.norm, the Bayesian em.norm), da.norm, imp.norm, mda.norm, rngseed and the random
// streams of the data-augmentation sampler.

use e.algo.stat.psych as ps
use e.math
use e.math.nmath_beta as nb
use e.mem

// one EM step in the standardised scale: from (mu, sg) to (nmu, nsg); n by p column-major z
// the prior of em.norm / logpost.norm on the standardised scale; mle = true ignores the rest
type Prior = struct { mle: bool, tau: f64, m: f64, mu0: []const f64, lambdainv: []const f64 }

fn em_step(a: *mem.Arena, z: []const f64, n: usize, p: usize, mu: []const f64, sg: []const f64, nmu: []f64, nsg: []f64, pr: *const Prior) -> err {
    let (t1, e1) = mem.alloc[f64](a, p)
    let (t2, e2) = mem.alloc[f64](a, p * p)
    let (xt, e3) = mem.alloc[f64](a, p)
    let (c, e4) = mem.alloc[f64](a, p * p)
    let (oi, e5) = mem.alloc[usize](a, p)
    let (mi, e6) = mem.alloc[usize](a, p)
    let (soo, e7) = mem.alloc[f64](a, p * p)
    let (inv, e8) = mem.alloc[f64](a, p * p)
    let (g, e9) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret e1 }
    var k = 0usize
    while k < p {
        t1[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < p * p {
        t2[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < n {
        var no = 0usize
        var nm = 0usize
        var j = 0usize
        while j < p {
            if z[j * n + i] == z[j * n + i] {
                oi[no] = j
                no += 1usize
            } else {
                mi[nm] = j
                nm += 1usize
            }
            j += 1usize
        }
        j = 0usize
        while j < p * p {
            c[j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < no {
            xt[oi[j]] = z[oi[j] * n + i]
            j += 1usize
        }
        if nm > 0usize {
            var r = 0usize
            while r < no {
                var s = 0usize
                while s < no {
                    soo[r * no + s] = sg[oi[r] * p + oi[s]]
                    s += 1usize
                }
                r += 1usize
            }
            if no > 0usize {
                if !ps.invert(a, soo[0usize..no * no], no, inv) { ret Singular }
            }
            // g[m][o] = Sigma_mo Sigma_oo^-1
            var q = 0usize
            while q < nm {
                var s = 0usize
                while s < no {
                    var v = 0.0f64
                    var t = 0usize
                    while t < no {
                        v += sg[mi[q] * p + oi[t]] * inv[t * no + s]
                        t += 1usize
                    }
                    g[q * p + s] = v
                    s += 1usize
                }
                q += 1usize
            }
            q = 0usize
            while q < nm {
                var v = mu[mi[q]]
                var s = 0usize
                while s < no {
                    v += g[q * p + s] * (z[oi[s] * n + i] - mu[oi[s]])
                    s += 1usize
                }
                xt[mi[q]] = v
                var q2 = 0usize
                while q2 < nm {
                    var cv = sg[mi[q] * p + mi[q2]]
                    var s2 = 0usize
                    while s2 < no {
                        cv -= g[q * p + s2] * sg[oi[s2] * p + mi[q2]]
                        s2 += 1usize
                    }
                    c[mi[q] * p + mi[q2]] = cv
                    q2 += 1usize
                }
                q += 1usize
            }
        }
        j = 0usize
        while j < p {
            t1[j] += xt[j]
            var l = 0usize
            while l < p {
                t2[j * p + l] += xt[j] * xt[l] + c[j * p + l]
                l += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let nf = f64(n)
    var j = 0usize
    if !pr.mle {
        // the posterior mode: the prior shrinks the sums before they are divided by n (norm's moden)
        let cc = pr.tau / (nf * (pr.tau + nf))
        let ee = nf / (nf + pr.m + f64(p) + 2.0f64)
        while j < p {
            nmu[j] = t1[j] / (pr.tau + nf) + pr.tau * pr.mu0[j] / (pr.tau + nf)
            j += 1usize
        }
        j = 0usize
        while j < p {
            var l = 0usize
            while l < p {
                let v = t2[j * p + l] + pr.lambdainv[j * p + l] - t1[j] * t1[l] / nf + cc * (t1[j] - nf * pr.mu0[j]) * (t1[l] - nf * pr.mu0[l])
                nsg[j * p + l] = v * ee / nf
                l += 1usize
            }
            j += 1usize
        }
        ret ok
    }
    while j < p {
        nmu[j] = t1[j] / nf
        j += 1usize
    }
    j = 0usize
    while j < p {
        var l = 0usize
        while l < p {
            nsg[j * p + l] = t2[j * p + l] / nf - nmu[j] * nmu[l]
            l += 1usize
        }
        j += 1usize
    }
    ret ok
}

// em_norm(x): standardises each column by its observed mean and ML standard deviation, runs EM from (0, I) until
// the largest parameter change is at most `criterion`, and answers the mean and covariance on the original scale;
// returns the iteration count
fn em_norm(a: *mem.Arena, x: []const f64, n: usize, p: usize, criterion: f64, maxits: usize, mu_out: []f64, sigma_out: []f64) -> (usize, err) {
    let pr = Prior { mle: true, tau: 0.0f64, m: 0.0f64, mu0: mu_out, lambdainv: sigma_out }
    let (it, e) = em_norm_prior(a, x, n, p, criterion, maxits, mu_out, sigma_out, &pr)
    ret (it, e)
}

// em.norm with a prior: the posterior mode by EM
fn em_norm_prior(a: *mem.Arena, x: []const f64, n: usize, p: usize, criterion: f64, maxits: usize, mu_out: []f64, sigma_out: []f64, pr: *const Prior) -> (usize, err) {
    let (z, e1) = mem.alloc[f64](a, n * p)
    let (xbar, e2) = mem.alloc[f64](a, p)
    let (sdv, e3) = mem.alloc[f64](a, p)
    let (mu, e4) = mem.alloc[f64](a, p)
    let (sg, e5) = mem.alloc[f64](a, p * p)
    let (nmu, e6) = mem.alloc[f64](a, p)
    let (nsg, e7) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (0usize, e1) }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        var c = 0.0f64
        var i = 0usize
        while i < n {
            if x[j * n + i] == x[j * n + i] {
                s += x[j * n + i]
                c += 1.0f64
            }
            i += 1usize
        }
        xbar[j] = s / c
        var v = 0.0f64
        i = 0usize
        while i < n {
            if x[j * n + i] == x[j * n + i] { v += (x[j * n + i] - xbar[j]) * (x[j * n + i] - xbar[j]) }
            i += 1usize
        }
        sdv[j] = math.sqrt[f64](v / c)
        i = 0usize
        while i < n {
            z[j * n + i] = (x[j * n + i] - xbar[j]) / sdv[j]
            i += 1usize
        }
        mu[j] = 0.0f64
        var l = 0usize
        while l < p {
            sg[j * p + l] = 0.0f64
            if j == l { sg[j * p + l] = 1.0f64 }
            l += 1usize
        }
        j += 1usize
    }
    var it = 0usize
    var converged = false
    while !converged && it < maxits {
        let e = em_step(a, z, n, p, mu, sg, nmu, nsg, pr)
        if e != ok { ret (it, e) }
        var mx = 0.0f64
        j = 0usize
        while j < p {
            let d = math.abs[f64](nmu[j] - mu[j])
            if d > mx { mx = d }
            mu[j] = nmu[j]
            j += 1usize
        }
        j = 0usize
        while j < p * p {
            let d = math.abs[f64](nsg[j] - sg[j])
            if d > mx { mx = d }
            sg[j] = nsg[j]
            j += 1usize
        }
        it += 1usize
        converged = mx <= criterion
    }
    j = 0usize
    while j < p {
        mu_out[j] = xbar[j] + sdv[j] * mu[j]
        var l = 0usize
        while l < p {
            sigma_out[j * p + l] = sdv[j] * sdv[l] * sg[j * p + l]
            l += 1usize
        }
        j += 1usize
    }
    ret (it, ok)
}

// loglik.norm: the observed-data log-likelihood of the standardised data without the 2 pi constant, which on the
// original scale is `-1/2 sum (log|S_oo| + quad)` plus `sum_j n_j log sd_j` (n_j observed values, ML sd of column j)
fn loglik_norm(a: *mem.Arena, x: []const f64, n: usize, p: usize, mu: []const f64, sigma: []const f64) -> (f64, err) {
    let (oi, e1) = mem.alloc[usize](a, p)
    let (soo, e2) = mem.alloc[f64](a, p * p)
    let (inv, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, e1) }
    var ll = 0.0f64
    var i = 0usize
    while i < n {
        var no = 0usize
        var j = 0usize
        while j < p {
            if x[j * n + i] == x[j * n + i] {
                oi[no] = j
                no += 1usize
            }
            j += 1usize
        }
        var r = 0usize
        while r < no {
            var s = 0usize
            while s < no {
                soo[r * no + s] = sigma[oi[r] * p + oi[s]]
                s += 1usize
            }
            r += 1usize
        }
        if no > 0usize {
            if !ps.invert(a, soo[0usize..no * no], no, inv) { ret (0.0f64, Singular) }
            var quad = 0.0f64
            r = 0usize
            while r < no {
                var s = 0usize
                while s < no {
                    quad += (x[oi[r] * n + i] - mu[oi[r]]) * inv[r * no + s] * (x[oi[s] * n + i] - mu[oi[s]])
                    s += 1usize
                }
                r += 1usize
            }
            ll -= 0.5f64 * (ps.logdet(a, soo[0usize..no * no], no) + quad)
        }
        i += 1usize
    }
    var j2 = 0usize
    while j2 < p {
        var c = 0.0f64
        var m = 0.0f64
        var t = 0usize
        while t < n {
            if x[j2 * n + t] == x[j2 * n + t] {
                c += 1.0f64
                m += x[j2 * n + t]
            }
            t += 1usize
        }
        m = m / c
        var v = 0.0f64
        t = 0usize
        while t < n {
            if x[j2 * n + t] == x[j2 * n + t] { v += (x[j2 * n + t] - m) * (x[j2 * n + t] - m) }
            t += 1usize
        }
        ll += c * 0.5f64 * math.log[f64](v / c)
        j2 += 1usize
    }
    ret (ll, ok)
}

error Singular

// logpost.norm: loglik.norm plus the log of the normal-inverted-Wishart prior (tau, m, mu0, lambdainv) at the parameter, the prior being on the standardised scale as in the package (mu0 length p, lambdainv p by p row-major); without a prior the package passes tau = 0, m = -1 and a zero lambdainv, which is Jeffreys' prior -(p + 1) / 2 log|Sigma|
fn logpost_norm(a: *mem.Arena, x: []const f64, n: usize, p: usize, mu: []const f64, sigma: []const f64, tau: f64, m: f64, mu0: []const f64, lambdainv: []const f64) -> (f64, err) {
    let (ll, e0) = loglik_norm(a, x, n, p, mu, sigma)
    if e0 != ok { ret (0.0f64, e0) }
    let (ms, e1) = mem.alloc[f64](a, p)
    let (ss, e2) = mem.alloc[f64](a, p * p)
    let (sd, e3) = mem.alloc[f64](a, p)
    let (inv, e4) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, e1) }
    var j = 0usize
    while j < p {
        var c = 0.0f64
        var s = 0.0f64
        var i = 0usize
        while i < n {
            if x[j * n + i] == x[j * n + i] {
                c += 1.0f64
                s += x[j * n + i]
            }
            i += 1usize
        }
        let xb = s / c
        var v = 0.0f64
        i = 0usize
        while i < n {
            if x[j * n + i] == x[j * n + i] { v += (x[j * n + i] - xb) * (x[j * n + i] - xb) }
            i += 1usize
        }
        sd[j] = math.sqrt[f64](v / c)
        ms[j] = (mu[j] - xb) / sd[j]
        j += 1usize
    }
    j = 0usize
    while j < p {
        var l = 0usize
        while l < p {
            ss[j * p + l] = sigma[j * p + l] / (sd[j] * sd[l])
            l += 1usize
        }
        j += 1usize
    }
    if !ps.invert(a, ss, p, inv) { ret (0.0f64, Singular) }
    let logdet = ps.logdet(a, ss, p)
    var trace = 0.0f64
    j = 0usize
    while j < p {
        var l = 0usize
        while l < p {
            trace += inv[j * p + l] * (lambdainv[j * p + l] + tau * (ms[j] - mu0[j]) * (ms[l] - mu0[l]))
            l += 1usize
        }
        j += 1usize
    }
    ret (ll - logdet * (m + f64(p) + 2.0f64) / 2.0f64 - trace / 2.0f64, ok)
}

// mi.inference for one quantity: the m estimates and standard errors; answers (est, std.err, df, signif, lower, upper, r, fminf) in `out` (8 values)
fn mi_inference(est: []const f64, se: []const f64, confidence: f64, out: []f64) {
    let m = f64(est.len)
    var qbar = 0.0f64
    var ubar = 0.0f64
    var i = 0usize
    while i < est.len {
        qbar += est[i]
        ubar += se[i] * se[i]
        i += 1usize
    }
    qbar = qbar / m
    ubar = ubar / m
    var bm = 0.0f64
    i = 0usize
    while i < est.len {
        bm += (est[i] - qbar) * (est[i] - qbar)
        i += 1usize
    }
    bm = bm / (m - 1.0f64)
    let tm = ubar + (1.0f64 + 1.0f64 / m) * bm
    let rem = (1.0f64 + 1.0f64 / m) * bm / ubar
    let nu = (m - 1.0f64) * (1.0f64 + 1.0f64 / rem) * (1.0f64 + 1.0f64 / rem)
    let alpha = 1.0f64 - (1.0f64 - confidence) / 2.0f64
    let q = nb.qt(alpha, nu, true, false)
    out[0usize] = qbar
    out[1usize] = math.sqrt[f64](tm)
    out[2usize] = nu
    out[3usize] = 2.0f64 * (1.0f64 - nb.pt(math.abs[f64](qbar / math.sqrt[f64](tm)), nu, true, false))
    out[4usize] = qbar - q * math.sqrt[f64](tm)
    out[5usize] = qbar + q * math.sqrt[f64](tm)
    out[6usize] = rem
    out[7usize] = (rem + 2.0f64 / (nu + 3.0f64)) / (rem + 1.0f64)
}
