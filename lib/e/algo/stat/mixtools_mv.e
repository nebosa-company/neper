// R mixtools mvnormalmixEM: the EM fit of a multivariate normal mixture (n by p data, row-major), arbmean and arbvar as in the package,
// including its starting values (mvnormalmix.init: the covariance guesses 1/rexp(rate = 1/var) of each bin, the means drawn by rmvnorm
// of a diagonal covariance) and its quirks: with arbmean = FALSE the first E-step reads mu[[m]] of a plain vector, a scalar.
// Means are k by p and covariances k blocks of p by p (one block when arbvar = FALSE).

use e.algo.rand.r as rg
use e.algo.stat.mixtools as mt
use e.math
use e.mem

type MvNorm = struct { lambda: []f64, mu: []f64, sigma: []f64, post: []f64, ll: []f64, loglik: f64, iter: usize, restarts: usize, k: usize }

// Gauss-Jordan inverse of the p by p row-major m with partial pivoting; returns the determinant
fn inv_det(a: *mem.Arena, m: []const f64, p: usize, inv: []f64) -> f64 {
    let w = mt.buf(a, p * p)
    var i = 0usize
    while i < p * p {
        w[i] = m[i]
        inv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        inv[i * p + i] = 1.0f64
        i += 1usize
    }
    var det = 1.0f64
    var c = 0usize
    while c < p {
        var piv = c
        var r = c + 1usize
        while r < p {
            var u = w[r * p + c]
            if u < 0.0f64 { u = 0.0f64 - u }
            var v = w[piv * p + c]
            if v < 0.0f64 { v = 0.0f64 - v }
            if u > v { piv = r }
            r += 1usize
        }
        if piv != c {
            var q = 0usize
            while q < p {
                let t1 = w[c * p + q]
                w[c * p + q] = w[piv * p + q]
                w[piv * p + q] = t1
                let t2 = inv[c * p + q]
                inv[c * p + q] = inv[piv * p + q]
                inv[piv * p + q] = t2
                q += 1usize
            }
            det = 0.0f64 - det
        }
        let d = w[c * p + c]
        det = det * d
        var q = 0usize
        while q < p {
            w[c * p + q] = w[c * p + q] / d
            inv[c * p + q] = inv[c * p + q] / d
            q += 1usize
        }
        r = 0usize
        while r < p {
            if r != c {
                let f = w[r * p + c]
                q = 0usize
                while q < p {
                    w[r * p + q] -= f * w[c * p + q]
                    inv[r * p + q] -= f * inv[c * p + q]
                    q += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    ret det
}

// quadratic form (x - mu)' inv (x - mu) for row i of x
fn quad(x: []const f64, i: usize, p: usize, mu: []const f64, mu_scalar: bool, inv: []const f64) -> f64 {
    var s = 0.0f64
    var r = 0usize
    while r < p {
        var dr = 0.0f64
        if mu_scalar { dr = x[i * p + r] - mu[0usize] } else { dr = x[i * p + r] - mu[r] }
        var t = 0.0f64
        var c = 0usize
        while c < p {
            var dc = 0.0f64
            if mu_scalar { dc = x[i * p + c] - mu[0usize] } else { dc = x[i * p + c] - mu[c] }
            t += inv[r * p + c] * dc
            c += 1usize
        }
        s += dr * t
        r += 1usize
    }
    ret s
}

// sum log(sum_j lambda_j dmvnorm(x, mu_j, sigma_j))
fn mv_loglik(a: *mem.Arena, x: []const f64, n: usize, p: usize, k: usize, lambda: []const f64, mu: []const f64, sigma: []const f64, arbvar: bool) -> f64 {
    let inv = mt.buf(a, p * p)
    let tmp = mt.buf(a, n)
    var j = 0usize
    while j < k {
        var blk = 0usize
        if arbvar { blk = j * p * p }
        let det = inv_det(a, sigma[blk..blk + p * p], p, inv)
        let logdet = math.log[f64](math.abs[f64](det))
        var i = 0usize
        while i < n {
            let q = quad(x, i, p, mu[j * p..j * p + p], false, inv)
            let dens = math.exp[f64](0.0f64 - 0.5f64 * (q + logdet + f64(p) * 1.8378770664093454836f64))
            if j == 0usize { tmp[i] = lambda[j] * dens } else { tmp[i] += lambda[j] * dens }
            i += 1usize
        }
        j += 1usize
    }
    var s = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var i2 = 0usize
    while i2 < n {
        mt.acc_add(&s, math.log[f64](tmp[i2]))
        i2 += 1usize
    }
    ret mt.acc_val(s)
}

// mvnormalmix.init: fills lambda (k), mu (k by p) and sigma; mu_vec is set when the means came back as one vector (arbmean = FALSE)
fn mv_init(a: *mem.Arena, g: *rg.Rng, x: []const f64, n: usize, p: usize, k: usize, arbmean: bool, arbvar: bool, lambda: []f64, mu: []f64, sigma: []f64) {
    let rm = mt.buf(a, n)
    var i = 0usize
    while i < n {
        rm[i] = mt.rmean(x, i * p, p, 1usize)
        i += 1usize
    }
    let o = mt.order_of(a, rm)
    let xs = mt.buf(a, n * p)
    i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xs[i * p + c] = x[o[i] * p + c]
            c += 1usize
        }
        i += 1usize
    }
    let hyp = mt.buf(a, k * p)
    let mhyp = mt.buf(a, k * p)
    var j = 0usize
    while j < k {
        let (f, cnt) = mt.bin_of(n, k, j + 1usize)
        var c = 0usize
        while c < p {
            hyp[j * p + c] = 1.0f64 / mt.rvar(xs, f * p + c, cnt, p)
            mhyp[j * p + c] = mt.rmean(xs, f * p + c, cnt, p)
            c += 1usize
        }
        j += 1usize
    }
    let sd = mt.buf(a, k * p)
    var c2 = 0usize
    if arbvar {
        j = 0usize
        while j < k {
            c2 = 0usize
            while c2 < p {
                sd[j * p + c2] = 1.0f64 / rg.rexp(g, 1.0f64 / hyp[j * p + c2])
                c2 += 1usize
            }
            j += 1usize
        }
    } else {
        // apply(sapply(..), 2, mean) averages over the p columns of each component: a k-vector recycled for the p draws
        let rate = mt.buf(a, k)
        j = 0usize
        while j < k {
            rate[j] = mt.rmean(hyp, j * p, p, 1usize)
            j += 1usize
        }
        c2 = 0usize
        while c2 < p {
            sd[c2] = 1.0f64 / rg.rexp(g, 1.0f64 / rate[c2 % k])
            c2 += 1usize
        }
    }
    var nb = 1usize
    if arbvar { nb = k }
    j = 0usize
    while j < nb * p * p {
        sigma[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < nb {
        c2 = 0usize
        while c2 < p {
            sigma[j * p * p + c2 * p + c2] = sd[j * p + c2]
            c2 += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < k {
        var b = 0usize
        if arbvar { b = j }
        c2 = 0usize
        while c2 < p {
            mu[j * p + c2] = mhyp[j * p + c2] + math.sqrt[f64](sigma[b * p * p + c2 * p + c2]) * rg.norm(g)
            c2 += 1usize
        }
        j += 1usize
    }
    if !arbmean {
        c2 = 0usize
        while c2 < p {
            var s = 0.0f64
            j = 0usize
            while j < k {
                s += mu[j * p + c2]
                j += 1usize
            }
            let m1 = s / f64(k)
            j = 0usize
            while j < k {
                mu[j * p + c2] = m1
                j += 1usize
            }
            c2 += 1usize
        }
    }
    var tot = 0.0f64
    j = 0usize
    while j < k {
        lambda[j] = rg.runif(g, 0.0f64, 1.0f64)
        tot += lambda[j]
        j += 1usize
    }
    j = 0usize
    while j < k {
        lambda[j] = lambda[j] / tot
        j += 1usize
    }
}

// mvnormalmixEM(x, lambda, mu, sigma, k, arbmean, arbvar, epsilon, maxit). lambda0 (k), mu0 (k by p, or p when not arbmean) and
// sigma0 (k blocks of p by p, or one) are NULL when empty. The draws of a NULL part are made as mvnormalmix.init makes them, all or none.
fn mvnormal_mix_em(a: *mem.Arena, g: *rg.Rng, x: []const f64, n: usize, p: usize, lambda0: []const f64, mu0: []const f64, sigma0: []const f64, k: usize, arbmean: bool, arbvar: bool, epsilon: f64, maxit: usize) -> (MvNorm, err) {
    var empty: MvNorm = zero
    var nb = 1usize
    if arbvar { nb = k }
    let lambda = mt.buf(a, k)
    let mu = mt.buf(a, k * p)
    let sigma = mt.buf(a, nb * p * p)
    var from_user = false
    var mu_vec = false
    if lambda0.len > 0usize && mu0.len > 0usize && sigma0.len > 0usize {
        from_user = true
        var i = 0usize
        while i < k {
            lambda[i] = lambda0[i]
            i += 1usize
        }
        i = 0usize
        while i < k * p {
            if arbmean { mu[i] = mu0[i] } else { mu[i] = mu0[i % p] }
            i += 1usize
        }
        i = 0usize
        while i < nb * p * p {
            sigma[i] = sigma0[i]
            i += 1usize
        }
        mu_vec = !arbmean
    } else {
        mv_init(a, g, x, n, p, k, arbmean, arbvar, lambda, mu, sigma)
        mu_vec = !arbmean
    }
    let z = mt.buf(a, n * k)
    let invs = mt.buf(a, nb * p * p)
    let dets = mt.buf(a, nb)
    let ll = mt.buf(a, maxit + 2usize)
    var nll = 0usize
    var diff = 1.0f64
    var iter = 0usize
    var obs = mv_loglik(a, x, n, p, k, lambda, mu, sigma, arbvar)
    ll[nll] = obs
    nll += 1usize
    var restarts = 0usize
    var newobs = 0.0f64
    let lamn = mt.buf(a, k)
    let mun = mt.buf(a, k * p)
    let sgn = mt.buf(a, nb * p * p)
    while diff > epsilon && iter < maxit {
        var b = 0usize
        while b < nb {
            dets[b] = inv_det(a, sigma[b * p * p..b * p * p + p * p], p, invs[b * p * p..b * p * p + p * p])
            b += 1usize
        }
        // E-step: z[i, j] = 1 / sum_m (lambda_m / lambda_j) sqrt(det_j / det_m) exp(-(q_m - q_j) / 2)
        let qm = mt.buf(a, k)
        var i = 0usize
        var nan_seen = 0usize
        while i < n {
            var m = 0usize
            while m < k {
                var bm = 0usize
                if arbvar { bm = m }
                if mu_vec { qm[m] = quad(x, i, p, mu[m..m + 1usize], true, invs[bm * p * p..bm * p * p + p * p]) } else { qm[m] = quad(x, i, p, mu[m * p..m * p + p], false, invs[bm * p * p..bm * p * p + p * p]) }
                m += 1usize
            }
            var rs = 0.0f64
            var j = 0usize
            while j < k {
                var bj = 0usize
                if arbvar { bj = j }
                var den = 0.0f64
                m = 0usize
                while m < k {
                    var bm = 0usize
                    if arbvar { bm = m }
                    var ratio = 1.0f64
                    if arbvar { ratio = math.sqrt[f64](dets[bj] / dets[bm]) }
                    den += lambda[m] / lambda[j] * ratio * math.exp[f64](0.0f64 - 0.5f64 * (qm[m] - qm[j]))
                    m += 1usize
                }
                z[i * k + j] = 1.0f64 / den
                rs += z[i * k + j]
                j += 1usize
            }
            j = 0usize
            while j < k {
                z[i * k + j] = z[i * k + j] / rs
                if z[i * k + j] != z[i * k + j] { nan_seen += 1usize }
                j += 1usize
            }
            i += 1usize
        }
        var sing = nan_seen
        mt.col_means(z, n, k, lamn)
        var bad = false
        var j2 = 0usize
        while j2 < k {
            if lamn[j2] < 0.00000001f64 || lamn[j2] != lamn[j2] { bad = true }
            j2 += 1usize
        }
        var have_new = false
        if bad {
            sing = 1usize
        } else {
            // M-step
            let zs = mt.buf(a, k)
            let sx = mt.buf(a, k * p)
            var jj = 0usize
            while jj < k {
                var c = 0usize
                while c < p {
                    var s = 0.0f64
                    i = 0usize
                    while i < n {
                        s += z[i * k + jj] * x[i * p + c]
                        i += 1usize
                    }
                    sx[jj * p + c] = s
                    c += 1usize
                }
                var t = 0.0f64
                i = 0usize
                while i < n {
                    t += z[i * k + jj]
                    i += 1usize
                }
                zs[jj] = t
                jj += 1usize
            }
            jj = 0usize
            while jj < k {
                var c = 0usize
                while c < p {
                    if arbmean {
                        mun[jj * p + c] = sx[jj * p + c] / zs[jj]
                    } else {
                        var s = 0.0f64
                        var q = 0usize
                        while q < k {
                            s += sx[q * p + c]
                            q += 1usize
                        }
                        mun[jj * p + c] = s / f64(n)
                    }
                    c += 1usize
                }
                jj += 1usize
            }
            var bb = 0usize
            while bb < nb * p * p {
                sgn[bb] = 0.0f64
                bb += 1usize
            }
            jj = 0usize
            while jj < k {
                var bq = 0usize
                if arbvar { bq = jj }
                var r = 0usize
                while r < p {
                    var c = 0usize
                    while c < p {
                        var s = 0.0f64
                        i = 0usize
                        while i < n {
                            s += z[i * k + jj] * (x[i * p + r] - mun[jj * p + r]) * (x[i * p + c] - mun[jj * p + c])
                            i += 1usize
                        }
                        if arbvar { sgn[bq * p * p + r * p + c] = s / zs[jj] } else { sgn[r * p + c] += s }
                        c += 1usize
                    }
                    r += 1usize
                }
                jj += 1usize
            }
            if !arbvar {
                bb = 0usize
                while bb < p * p {
                    sgn[bb] = sgn[bb] / f64(n)
                    bb += 1usize
                }
            }
            jj = 0usize
            while jj < k {
                lambda[jj] = lamn[jj]
                jj += 1usize
            }
            jj = 0usize
            while jj < k * p {
                mu[jj] = mun[jj]
                jj += 1usize
            }
            jj = 0usize
            while jj < nb * p * p {
                sigma[jj] = sgn[jj]
                jj += 1usize
            }
            mu_vec = false
            newobs = mv_loglik(a, x, n, p, k, lambda, mu, sigma, arbvar)
            have_new = true
        }
        var restart = sing > 0usize
        if have_new && (newobs != newobs || math.abs[f64](newobs) == 1.0f64 / 0.0f64) { restart = true }
        if restart {
            restarts += 1usize
            if restarts > 15usize { ret (empty, mt.TooManyTries) }
            mv_init(a, g, x, n, p, k, arbmean, arbvar, lambda, mu, sigma)
            mu_vec = !arbmean
            diff = 1.0f64
            iter = 0usize
            obs = mv_loglik(a, x, n, p, k, lambda, mu, sigma, arbvar)
            nll = 0usize
            ll[nll] = obs
            nll += 1usize
        } else {
            diff = newobs - obs
            obs = newobs
            ll[nll] = obs
            nll += 1usize
            iter += 1usize
        }
    }
    ret (MvNorm { lambda: lambda, mu: mu, sigma: sigma, post: z, ll: ll[0usize..nll], loglik: obs, iter: iter, restarts: restarts, k: k }, ok)
}
