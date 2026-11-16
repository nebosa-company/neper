// R norm, the EM part: `em_norm` (maximum likelihood estimates of the mean and covariance of multivariate normal
// data with missing values, by EM on the standardised columns exactly as norm::em.norm iterates, so the iterate at
// which the 1e-4 criterion stops is the package's) and `loglik_norm` (the observed-data log-likelihood).
// Missing values are NaN; no row may be entirely missing.
//
// Not here: priors (ecm.norm, the Bayesian em.norm), da.norm, imp.norm, mda.norm, rngseed and the random
// streams of the data-augmentation sampler.

use e.algo.stat.psych as ps
use e.math
use e.mem

// one EM step in the standardised scale: from (mu, sg) to (nmu, nsg); n by p column-major z
fn em_step(a: *mem.Arena, z: []const f64, n: usize, p: usize, mu: []const f64, sg: []const f64, nmu: []f64, nsg: []f64) -> err {
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
        let e = em_step(a, z, n, p, mu, sg, nmu, nsg)
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
