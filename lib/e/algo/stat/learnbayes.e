// R LearnBayes: the closed-form helpers: pbetap (beta-binomial predictive), discint (discrete highest-probability set), mnormt.onesided
// (one-sided Bayes factor for a normal mean), normal.select and beta.select (prior from two quantiles), and bfexch (exchangeable-model
// log Bayes factor).
//
// Not here: laplace, rejectsampling, importance sampling, the Gibbs and Metropolis helpers and the other book models.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem
use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.bayesmpkg as bz

fn pbetap(a: f64, b: f64, n: f64, s: f64) -> f64 {
    let lcon = nm.lgammafn(n + 1.0f64) - nm.lgammafn(s + 1.0f64) - nm.lgammafn(n - s + 1.0f64)
    ret math.exp[f64](lcon + nb.lbeta(s + a, n - s + b) - nb.lbeta(a, b))
}

// the probability reached and the number of points in the set: values sorted by decreasing probability until the cumulative reaches prob.
// Returns (eprob, count); the points themselves are the first `count` entries of the order, `order_out` receives that order.
fn discint(a: *mem.Arena, p: []const f64, prob: f64, order_out: []usize) -> (f64, usize) {
    let n = p.len
    var i = 0usize
    while i < n {
        order_out[i] = i
        i += 1usize
    }
    // stable insertion sort of the indices by decreasing probability; R sorts ascending and reverses, so ties come out reversed
    i = 1usize
    while i < n {
        let t = order_out[i]
        var j = i
        while j > 0usize && p[order_out[j - 1usize]] > p[t] {
            order_out[j] = order_out[j - 1usize]
            j -= 1usize
        }
        order_out[j] = t
        i += 1usize
    }
    var lo = 0usize
    var hi = n - 1usize
    while lo < hi {
        let t = order_out[lo]
        order_out[lo] = order_out[hi]
        order_out[hi] = t
        lo += 1usize
        hi -= 1usize
    }
    var cp = 0.0f64
    i = 0usize
    while i < n {
        cp += p[order_out[i]]
        if cp >= prob { ret (cp, i + 1usize) }
        i += 1usize
    }
    ret (cp, n)
}

// the Bayes factor of mu <= m0 against mu > m0; the data are (xbar, n, s)
fn mnormt_onesided_bf(m0: f64, pm: f64, psd: f64, xbar: f64, n: f64, s: f64) -> f64 {
    let pv = psd * psd
    let prior_h = dist.pnorm(m0, pm, psd, true, false)
    let prior_odds = prior_h / (1.0f64 - prior_h)
    let prec = 1.0f64 / pv + n / (s * s)
    let post_sd = math.sqrt[f64](1.0f64 / prec)
    let post_mean = (xbar * n / (s * s) + pm / pv) / prec
    let post_h = dist.pnorm(m0, post_mean, post_sd, true, false)
    ret (post_h / (1.0f64 - post_h)) / prior_odds
}

// normal.select: (mu, sigma) from the quantiles (p1, x1) and (p2, x2)
fn normal_select(p1: f64, x1: f64, p2: f64, x2: f64) -> (f64, f64) {
    let sigma = (x1 - x2) / (dist.qnorm(p1, 0.0f64, 1.0f64, true, false) - dist.qnorm(p2, 0.0f64, 1.0f64, true, false))
    ret (x1 - sigma * dist.qnorm(p1, 0.0f64, 1.0f64, true, false), sigma)
}

fn betaprior1(k: f64, x: f64, p: f64) -> f64 {
    var lo = 0.0f64
    var hi = 1.0f64
    var m0 = 0.5f64
    var it = 0usize
    while it < 200usize {
        m0 = (lo + hi) / 2.0f64
        let p0 = nb.pbeta(x, k * m0, k * (1.0f64 - m0), true, false)
        if p0 < p { hi = m0 } else { lo = m0 }
        if math.abs[f64](p0 - p) < 1.0e-4f64 { break }
        it += 1usize
    }
    ret m0
}

// beta.select: the beta prior (a, b), rounded to two digits, matching two quantiles
fn beta_select(a: *mem.Arena, p1: f64, x1: f64, p2: f64, x2: f64) -> (f64, f64, err) {
    let np = 100usize
    let (lk, e1) = mem.alloc[f64](a, np)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    let (pr, e2) = mem.alloc[f64](a, np)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    var i = 0usize
    var cnt = 0usize
    while i < np {
        let lg = 0.0f64 - 3.0f64 + 11.0f64 * f64(i) / 99.0f64
        let k = math.exp[f64](lg)
        let m = betaprior1(k, x1, p1)
        let q = nb.pbeta(x2, k * m, k * (1.0f64 - m), true, false)
        if q > 0.0f64 && q < 1.0f64 {
            lk[cnt] = lg
            pr[cnt] = q
            cnt += 1usize
        }
        i += 1usize
    }
    // approx: sort by the probability, interpolate the log K at p2
    i = 1usize
    while i < cnt {
        let tp = pr[i]
        let tl = lk[i]
        var j = i
        while j > 0usize && pr[j - 1usize] > tp {
            pr[j] = pr[j - 1usize]
            lk[j] = lk[j - 1usize]
            j -= 1usize
        }
        pr[j] = tp
        lk[j] = tl
        i += 1usize
    }
    var y = 0.0f64 / 0.0f64
    i = 0usize
    while i + 1usize < cnt {
        if p2 >= pr[i] && p2 <= pr[i + 1usize] {
            if pr[i + 1usize] == pr[i] { y = lk[i] } else { y = lk[i] + (lk[i + 1usize] - lk[i]) * (p2 - pr[i]) / (pr[i + 1usize] - pr[i]) }
            break
        }
        i += 1usize
    }
    let k0 = math.exp[f64](y)
    let m0 = betaprior1(k0, x1, p1)
    ret (k0 * m0, k0 * (1.0f64 - m0), ok)
}

// bfexch: the log Bayes factor of the exchangeable model at theta (logit of eta) with precision K
fn bfexch(theta: f64, k: f64, y: []const f64, n: []const f64) -> f64 {
    let eta = math.exp[f64](theta) / (1.0f64 + math.exp[f64](theta))
    var s = 0.0f64
    var sy = 0.0f64
    var sn = 0.0f64
    var i = 0usize
    while i < y.len {
        s += nb.lbeta(k * eta + y[i], k * (1.0f64 - eta) + n[i] - y[i]) - nb.lbeta(k * eta, k * (1.0f64 - eta))
        sy += y[i]
        sn += n[i] - y[i]
        i += 1usize
    }
    ret s + math.log[f64](eta * (1.0f64 - eta)) - nb.lbeta(sy + 1.0f64, sn + 1.0f64)
}

// ---- the random-walk and independence Metropolis samplers of LearnBayes, drawing with R's streams ----

// the fixed log posteriors the oracle uses: 0 independent normals (m_i, s_i), 1 a banana-shaped density
fn logpost_fixed(kind: usize, par: []const f64, th: []const f64) -> f64 {
    if kind == 0usize {
        var s = 0.0f64
        var i = 0usize
        while i < th.len {
            let z = (th[i] - par[2usize * i]) / par[2usize * i + 1usize]
            s -= 0.5f64 * z * z
            i += 1usize
        }
        ret s
    }
    let u = th[1usize] - par[0usize] * th[0usize] * th[0usize]
    ret 0.0f64 - 0.5f64 * (th[0usize] * th[0usize] / 4.0f64 + u * u)
}

// rwmetrop(logpost, list(var, scale), start, m): out is m by pb column-major, returns the acceptance rate; the candidate adds scale * t(chol(var)) z with z standard normal, one uniform per step
fn rwmetrop(a: *mem.Arena, r: *rng.Rng, kind: usize, par: []const f64, vr: []const f64, scale: f64, start: []const f64, m: usize, out: []f64) -> f64 {
    let pb = start.len
    let (u, e1) = mem.alloc[f64](a, pb * pb)
    let (b, e2) = mem.alloc[f64](a, pb)
    let (bc, e3) = mem.alloc[f64](a, pb)
    let (z, e4) = mem.alloc[f64](a, pb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    if !bz.chol_upper(vr, pb, u) { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < pb {
        b[i] = start[i]
        i += 1usize
    }
    var lb = logpost_fixed(kind, par, b)
    var acc = 0.0f64
    var it = 0usize
    while it < m {
        i = 0usize
        while i < pb {
            z[i] = rng.norm(r)
            i += 1usize
        }
        i = 0usize
        while i < pb {
            // (t(a) z)_i = sum_j a[j, i] z[j]
            var sv = 0.0f64
            var j = 0usize
            while j <= i {
                sv += u[i * pb + j] * z[j]
                j += 1usize
            }
            bc[i] = b[i] + scale * sv
            i += 1usize
        }
        let lbc = logpost_fixed(kind, par, bc)
        let prob = math.exp[f64](lbc - lb)
        if prob == prob {
            if rng.unif(r) < prob {
                lb = lbc
                i = 0usize
                while i < pb {
                    b[i] = bc[i]
                    i += 1usize
                }
                acc += 1.0f64
            }
        }
        i = 0usize
        while i < pb {
            out[i * m + it] = b[i]
            i += 1usize
        }
        it += 1usize
    }
    ret acc / f64(m)
}

// indepmetrop(logpost, list(mu, var), start, m): the independence sampler with a normal proposal
fn indepmetrop(a: *mem.Arena, r: *rng.Rng, kind: usize, par: []const f64, mu: []const f64, vr: []const f64, start: []const f64, m: usize, out: []f64) -> f64 {
    let pb = start.len
    let (u, e1) = mem.alloc[f64](a, pb * pb)
    let (ui, e2) = mem.alloc[f64](a, pb * pb)
    let (th0, e3) = mem.alloc[f64](a, pb)
    let (th1, e4) = mem.alloc[f64](a, pb)
    let (z, e5) = mem.alloc[f64](a, pb)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    if !bz.chol_upper(vr, pb, u) { ret 0.0f64 / 0.0f64 }
    bz.inv_upper(u, pb, ui)
    var i = 0usize
    while i < pb {
        th0[i] = start[i]
        i += 1usize
    }
    var f0 = logpost_fixed(kind, par, th0)
    var acc = 0.0f64
    var it = 0usize
    while it < m {
        i = 0usize
        while i < pb {
            z[i] = rng.norm(r)
            i += 1usize
        }
        i = 0usize
        while i < pb {
            var sv = 0.0f64
            var j = 0usize
            while j <= i {
                sv += u[i * pb + j] * z[j]
                j += 1usize
            }
            th1[i] = mu[i] + sv
            i += 1usize
        }
        let f1 = logpost_fixed(kind, par, th1)
        // log N kernels: -0.5 (x - mu)' V^-1 (x - mu) = -0.5 |Ui' (x - mu)|^2
        var q0 = 0.0f64
        var q1 = 0.0f64
        var c = 0usize
        while c < pb {
            var s0 = 0.0f64
            var s1 = 0.0f64
            var j = 0usize
            while j <= c {
                s0 += ui[c * pb + j] * (th0[j] - mu[j])
                s1 += ui[c * pb + j] * (th1[j] - mu[j])
                j += 1usize
            }
            q0 += s0 * s0
            q1 += s1 * s1
            c += 1usize
        }
        let rr = math.exp[f64](0.0f64 - 0.5f64 * q0 + 0.5f64 * q1 + f1 - f0)
        if rng.unif(r) < rr {
            i = 0usize
            while i < pb {
                th0[i] = th1[i]
                i += 1usize
            }
            f0 = f1
            acc += 1.0f64
        }
        i = 0usize
        while i < pb {
            out[i * m + it] = th0[i]
            i += 1usize
        }
        it += 1usize
    }
    ret acc / f64(m)
}

// rigamma(n, a, b): 1 / rgamma(shape a, rate b), one value per call
fn rigamma(r: *rng.Rng, a: f64, b: f64) -> f64 { ret 1.0f64 / rd.rgamma(r, a, 1.0f64 / b) }

// rmnorm(n, mean, varcov): the n by d matrix of z %*% chol(varcov) + mean with z filled column by column from rnorm(n d); out is n by d column-major
fn rmnorm(a: *mem.Arena, r: *rng.Rng, n: usize, mean: []const f64, vr: []const f64, out: []f64) -> err {
    let d = mean.len
    let (u, e1) = mem.alloc[f64](a, d * d)
    let (z, e2) = mem.alloc[f64](a, n * d)
    if e1 != ok || e2 != ok { ret mem.Full }
    if !bz.chol_upper(vr, d, u) { ret mem.Full }
    var i = 0usize
    while i < n * d {
        z[i] = rng.norm(r)
        i += 1usize
    }
    var c = 0usize
    while c < d {
        i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j <= c {
                s += z[j * n + i] * u[c * d + j]
                j += 1usize
            }
            out[c * n + i] = mean[c] + s
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// pdisc(p, prior, data = (s, f)): the posterior of a discrete prior on the proportions p given s successes and f failures
fn pdisc(p: []const f64, prior: []const f64, s: f64, f: f64, post: []f64) {
    let n = p.len
    var mx = 0.0f64 - 1.0e300f64
    var i = 0usize
    while i < n {
        var p1 = p[i]
        if p[i] == 0.0f64 { p1 = 0.5f64 }
        if p[i] == 1.0f64 { p1 = 0.5f64 }
        var like = s * math.log[f64](p1) + f * math.log[f64](1.0f64 - p1)
        var edge = 0.0f64
        if p[i] > 0.0f64 && p[i] < 1.0f64 { edge = 1.0f64 }
        var pen = 0.0f64
        if p[i] == 0.0f64 && s > 0.0f64 { pen = 1.0f64 }
        if p[i] == 1.0f64 && f > 0.0f64 { pen = 1.0f64 }
        like = like * edge - 999.0f64 * pen
        post[i] = like
        if like > mx { mx = like }
        i += 1usize
    }
    var tot = 0.0f64
    i = 0usize
    while i < n {
        post[i] = math.exp[f64](post[i] - mx) * prior[i]
        tot += post[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        post[i] = post[i] / tot
        i += 1usize
    }
}

// pbetat(p0, prob, ab, data): the Bayes factor against the point null p0 under a beta(a, b) alternative and the posterior probability of the null
fn pbetat(p0: f64, prob: f64, a: f64, b: f64, s: f64, f: f64) -> (f64, f64) {
    let lbf = s * math.log[f64](p0) + f * math.log[f64](1.0f64 - p0) + lbeta2(a, b) - lbeta2(a + s, b + f)
    let bf = math.exp[f64](lbf)
    ret (bf, prob * bf / (prob * bf + 1.0f64 - prob))
}

fn lbeta2(a: f64, b: f64) -> f64 { ret nm.lgammafn(a) + nm.lgammafn(b) - nm.lgammafn(a + b) }

// binomial.beta.mix(probs, betapar, data = (s, f)): the posterior mixture probabilities (post) and beta parameters (pa, pb) of a mixture of beta priors for a binomial proportion
fn binomial_beta_mix(probs: []const f64, a: []const f64, b: []const f64, s: f64, f: f64, post: []f64, pa: []f64, pb: []f64) {
    let n = probs.len
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        pa[i] = a[i] + s
        pb[i] = b[i] + f
        let p = pa[i] / (pa[i] + pb[i])
        let mp = math.exp[f64](nb.dbinom(s, s + f, p, true) + nb.dbeta(p, a[i], b[i], true) - nb.dbeta(p, pa[i], pb[i], true))
        post[i] = probs[i] * mp
        tot += post[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        post[i] = post[i] / tot
        i += 1usize
    }
}

// normal.normal.mix(probs, normalpar, data = (y, sigma2)): the posterior probabilities, means and variances of a mixture of normal priors for a normal mean with known variance
fn normal_normal_mix(probs: []const f64, pm: []const f64, pv: []const f64, y: f64, s2: f64, post: []f64, mean: []f64, vr: []f64) {
    let n = probs.len
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        let prec = 1.0f64 / pv[i] + 1.0f64 / s2
        vr[i] = 1.0f64 / prec
        mean[i] = (y / s2 + pm[i] / pv[i]) / prec
        let mp = dist.dnorm(y, pm[i], math.sqrt[f64](s2 + pv[i]), false)
        post[i] = probs[i] * mp
        tot += post[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        post[i] = post[i] / tot
        i += 1usize
    }
}

// poisson.gamma.mix(probs, gammapar, data = list(y, t)): the posterior probabilities and gamma parameters of a mixture of gamma priors for a Poisson rate with exposures t
fn poisson_gamma_mix(probs: []const f64, ga: []const f64, gb: []const f64, y: []const f64, t: []const f64, post: []f64, pa: []f64, pb: []f64) {
    let n = probs.len
    var sy = 0.0f64
    var st = 0.0f64
    var j = 0usize
    while j < y.len {
        sy += y[j]
        st += t[j]
        j += 1usize
    }
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        pa[i] = ga[i] + sy
        pb[i] = gb[i] + st
        let l = pa[i] / pb[i]
        var ll = 0.0f64
        j = 0usize
        while j < y.len {
            ll += nm.dpois(y[j], l * t[j], true)
            j += 1usize
        }
        let mp = math.exp[f64](ll + nm.dgamma(l, ga[i], 1.0f64 / gb[i], true) - nm.dgamma(l, pa[i], 1.0f64 / pb[i], true))
        post[i] = probs[i] * mp
        tot += post[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        post[i] = post[i] / tot
        i += 1usize
    }
}

// ---- the log posteriors LearnBayes ships for its book examples ----

// normchi2post(theta = (mu, sig2), data): the normal likelihood with the prior 1 / sig2
fn normchi2post(mu: f64, sig2: f64, y: []const f64) -> f64 {
    var z = 0.0f64
    var i = 0usize
    while i < y.len {
        z += 0.0f64 - (y[i] - mu) * (y[i] - mu) / 2.0f64 / sig2 - math.log[f64](sig2) / 2.0f64
        i += 1usize
    }
    ret z - math.log[f64](sig2)
}

fn bbx_sum(eta: f64, k: f64, y: []const f64, n: []const f64) -> f64 {
    var v = 0.0f64
    var i = 0usize
    while i < y.len {
        v += lbeta2f(k * eta + y[i], k * (1.0f64 - eta) + n[i] - y[i]) - lbeta2f(k * eta, k * (1.0f64 - eta))
        i += 1usize
    }
    ret v
}

fn lbeta2f(a: f64, b: f64) -> f64 { ret nb.lbeta(a, b) }

// betabinexch0(theta = (eta, K), data): the beta-binomial exchangeable model on the probability scale with the prior 1 / (eta (1 - eta) (1 + K)^2)
fn betabinexch0(eta: f64, k: f64, y: []const f64, n: []const f64) -> f64 {
    ret bbx_sum(eta, k, y, n) - 2.0f64 * math.log[f64](1.0f64 + k) - math.log[f64](eta) - math.log[f64](1.0f64 - eta)
}

// betabinexch(theta = (logit eta, log K), data)
fn betabinexch(t1: f64, t2: f64, y: []const f64, n: []const f64) -> f64 {
    let eta = math.exp[f64](t1) / (1.0f64 + math.exp[f64](t1))
    let k = math.exp[f64](t2)
    ret bbx_sum(eta, k, y, n) + t2 - 2.0f64 * math.log[f64](1.0f64 + math.exp[f64](t2))
}

// poissgamexch(theta = (log alpha, log mu), datapar): the Poisson-gamma exchangeable model, e the exposures, y the counts, z0 the prior constant
fn poissgamexch(t1: f64, t2: f64, e: []const f64, y: []const f64, z0: f64) -> f64 {
    let alpha = math.exp[f64](t1)
    let mu = math.exp[f64](t2)
    let beta = alpha / mu
    var v = 0.0f64
    var i = 0usize
    while i < y.len {
        v += nm.lgammafn(alpha + y[i]) - (y[i] + alpha) * math.log[f64](e[i] + beta) + alpha * math.log[f64](beta) - nm.lgammafn(alpha)
        i += 1usize
    }
    ret v + math.log[f64](alpha) - 2.0f64 * math.log[f64](alpha + z0)
}

// lbinorm(xy, list(m, v)): the bivariate normal kernel
fn lbinorm(x: f64, y: f64, m1: f64, m2: f64, v11: f64, v12: f64, v22: f64) -> f64 {
    let zx = (x - m1) / math.sqrt[f64](v11)
    let zy = (y - m2) / math.sqrt[f64](v22)
    let r = v12 / math.sqrt[f64](v11 * v22)
    ret 0.0f64 - 0.5f64 / (1.0f64 - r * r) * (zx * zx - 2.0f64 * r * zx * zy + zy * zy)
}

// cauchyerrorpost(theta = (location, log scale), data): the Cauchy-error likelihood
fn cauchyerrorpost(loc: f64, lscale: f64, y: []const f64) -> f64 {
    let s = math.exp[f64](lscale)
    var v = 0.0f64
    var i = 0usize
    while i < y.len {
        let z = (y[i] - loc) / s
        v += math.log[f64](1.0f64 / (3.141592653589793f64 * (1.0f64 + z * z)) / s)
        i += 1usize
    }
    ret v
}

// logisticpost(beta, data): the binomial logistic regression log likelihood, x the covariate, n the trials, y the successes
fn logisticpost(b0: f64, b1: f64, x: []const f64, n: []const f64, y: []const f64) -> f64 {
    var v = 0.0f64
    var i = 0usize
    while i < x.len {
        let lp = b0 + b1 * x[i]
        let p = math.exp[f64](lp) / (1.0f64 + math.exp[f64](lp))
        v += y[i] * math.log[f64](p) + (n[i] - y[i]) * math.log[f64](1.0f64 - p)
        i += 1usize
    }
    ret v
}

// weibullregpost(theta = (log sigma, mu, beta...), data = (t, c, X)): the Weibull regression log likelihood with right censoring (c = 1 observed); x is m by p column-major
fn weibullregpost(theta: []const f64, t: []const f64, cens: []const f64, x: []const f64, m: usize, p: usize) -> f64 {
    let sigma = math.exp[f64](theta[0usize])
    let mu = theta[1usize]
    var v = 0.0f64
    var i = 0usize
    while i < m {
        var xb = 0.0f64
        var j = 0usize
        while j < p {
            xb += x[j * m + i] * theta[2usize + j]
            j += 1usize
        }
        let z = (math.log[f64](t[i]) - mu - xb) / sigma
        let f = 1.0f64 / sigma * math.exp[f64](z - math.exp[f64](z))
        let s = math.exp[f64](0.0f64 - math.exp[f64](z))
        v += cens[i] * math.log[f64](f) + (1.0f64 - cens[i]) * math.log[f64](s)
        i += 1usize
    }
    ret v
}

// groupeddatapost(theta = (mu, log sigma), data): grouped normal data, f the counts and (lo, hi) the interval ends
fn groupeddatapost(mu: f64, lsig: f64, f: []const f64, lo: []const f64, hi: []const f64) -> f64 {
    let sigma = math.exp[f64](lsig)
    var v = 0.0f64
    var i = 0usize
    while i < f.len {
        v += f[i] * math.log[f64](dist.pnorm(hi[i], mu, sigma, true, false) - dist.pnorm(lo[i], mu, sigma, true, false))
        i += 1usize
    }
    ret v
}

// logctablepost(theta, data = (s1, f1, s2, f2)): two binomials on the logit scale, theta = (the sum, the difference of the logits)
fn logctablepost(t1: f64, t2: f64, s1: f64, f1: f64, s2: f64, f2: f64) -> f64 {
    let l1 = (t1 + t2) / 2.0f64
    let l2 = (t2 - t1) / 2.0f64
    ret s1 * l1 - (s1 + f1) * math.log[f64](1.0f64 + math.exp[f64](l1)) + s2 * l2 - (s2 + f2) * math.log[f64](1.0f64 + math.exp[f64](l2))
}

// transplantpost(theta = (log tau, log lambda, log p), data = (x, t, y, d)): the Pareto survival model of the heart transplant example; t = 1 rows are the transplanted
fn transplantpost(th: []const f64, x: []const f64, t: []const f64, y: []const f64, d: []const f64) -> f64 {
    let tau = math.exp[f64](th[0usize])
    let lambda = math.exp[f64](th[1usize])
    let p = math.exp[f64](th[2usize])
    var v = 0.0f64
    var i = 0usize
    while i < x.len {
        if t[i] == 0.0f64 {
            if d[i] == 0.0f64 { v += p * math.log[f64](lambda) + math.log[f64](p) - (p + 1.0f64) * math.log[f64](lambda + x[i]) }
            if d[i] == 1.0f64 { v += p * math.log[f64](lambda / (lambda + x[i])) }
        } else {
            if d[i] == 0.0f64 { v += p * math.log[f64](lambda) + math.log[f64](p * tau) - (p + 1.0f64) * math.log[f64](lambda + y[i] + tau * x[i]) }
            if d[i] == 1.0f64 { v += p * math.log[f64](lambda / (lambda + y[i] + tau * x[i])) }
        }
        i += 1usize
    }
    ret v + th[0usize] + th[1usize] + th[2usize]
}

// rmt(n, mean, S, df): n draws of a multivariate t, the n chi-square draws first (df finite), then the n d normal draws of rmnorm; out is n by d column-major
fn rmt(a: *mem.Arena, r: *rng.Rng, n: usize, mean: []const f64, vr: []const f64, df: f64, out: []f64) -> err {
    let d = mean.len
    let (xc, e1) = mem.alloc[f64](a, n)
    let (zero_mean, e2) = mem.alloc[f64](a, d)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        xc[i] = rd.rchisq(r, df) / df
        i += 1usize
    }
    i = 0usize
    while i < d {
        zero_mean[i] = 0.0f64
        i += 1usize
    }
    let e = rmnorm(a, r, n, zero_mean, vr, out)
    if e != ok { ret e }
    var c = 0usize
    while c < d {
        i = 0usize
        while i < n {
            out[c * n + i] = mean[c] + out[c * n + i] / math.sqrt[f64](xc[i])
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// the log density of a multivariate t at one point x (length d): lgamma((df + d) / 2) - (d log(pi df) + log det S) / 2 - lgamma(df / 2) - (df + d) / 2 log(1 + Q / df)
fn dmt_log(a: *mem.Arena, x: []const f64, mean: []const f64, vr: []const f64, df: f64) -> f64 {
    let d = mean.len
    let (u, e1) = mem.alloc[f64](a, d * d)
    let (iu, e2) = mem.alloc[f64](a, d * d)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    if !bz.chol_upper(vr, d, u) { ret 0.0f64 / 0.0f64 }
    bz.inv_upper(u, d, iu)
    var q = 0.0f64
    var c = 0usize
    while c < d {
        var s = 0.0f64
        var j = 0usize
        while j <= c {
            s += iu[c * d + j] * (x[j] - mean[j])
            j += 1usize
        }
        q += s * s
        c += 1usize
    }
    var logdet = 0.0f64
    c = 0usize
    while c < d {
        logdet += 2.0f64 * math.log[f64](u[c * d + c])
        c += 1usize
    }
    let fd = f64(d)
    ret nm.lgammafn((df + fd) / 2.0f64) - 0.5f64 * (fd * math.log[f64](3.141592653589793f64 * df) + logdet) - nm.lgammafn(df / 2.0f64) - 0.5f64 * (df + fd) * math.log[f64](1.0f64 + q / df)
}

// the draws and log densities shared by rejectsampling and impsampling: theta (n by d), lf the target log density at each row, lg the proposal's
fn proposal_draws[Ctx: type](a: *mem.Arena, r: *rng.Rng, ctx: *Ctx, logf: fn(*Ctx, []const f64) -> f64, mean: []const f64, vr: []const f64, df: f64, n: usize, theta: []f64, lf: []f64, lg: []f64) -> err {
    let d = mean.len
    let e = rmt(a, r, n, mean, vr, df, theta)
    if e != ok { ret e }
    let (row, e2) = mem.alloc[f64](a, d)
    if e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < d {
            row[c] = theta[c * n + i]
            c += 1usize
        }
        lf[i] = logf(ctx, row)
        lg[i] = dmt_log(a, row, mean, vr, df)
        i += 1usize
    }
    ret ok
}

// rejectsampling(logf, tpar, dmax, n): keeps the proposal draws whose uniform falls below exp(lf - lg - dmax); returns how many, the kept rows (n by d column-major, compacted to the front of keep with leading dimension n) in keep
fn rejectsampling[Ctx: type](a: *mem.Arena, r: *rng.Rng, ctx: *Ctx, logf: fn(*Ctx, []const f64) -> f64, mean: []const f64, vr: []const f64, df: f64, dmax: f64, n: usize, keep: []f64) -> usize {
    let d = mean.len
    let (theta, e1) = mem.alloc[f64](a, n * d)
    let (lf, e2) = mem.alloc[f64](a, n)
    let (lg, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    if proposal_draws[Ctx](a, r, ctx, logf, mean, vr, df, n, theta, lf, lg) != ok { ret 0usize }
    var m = 0usize
    var i = 0usize
    while i < n {
        let prob = math.exp[f64](lf[i] - lg[i] - dmax)
        if rng.unif(r) < prob {
            var c = 0usize
            while c < d {
                keep[c * n + m] = theta[c * n + i]
                c += 1usize
            }
            m += 1usize
        }
        i += 1usize
    }
    ret m
}

// impsampling(logf, tpar, h, n): the importance-sampling estimate of the posterior mean of the h-th coordinate (hidx, 0-based) and its standard error; out = (est, se)
fn impsampling[Ctx: type](a: *mem.Arena, r: *rng.Rng, ctx: *Ctx, logf: fn(*Ctx, []const f64) -> f64, mean: []const f64, vr: []const f64, df: f64, n: usize, hidx: usize, out: []f64) -> err {
    let d = mean.len
    let (theta, e1) = mem.alloc[f64](a, n * d)
    let (lf, e2) = mem.alloc[f64](a, n)
    let (lg, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let e = proposal_draws[Ctx](a, r, ctx, logf, mean, vr, df, n, theta, lf, lg)
    if e != ok { ret e }
    var md = lf[0usize] - lg[0usize]
    var i = 1usize
    while i < n {
        if lf[i] - lg[i] > md { md = lf[i] - lg[i] }
        i += 1usize
    }
    var sw = 0.0f64
    var swh = 0.0f64
    i = 0usize
    while i < n {
        let wt = math.exp[f64](lf[i] - lg[i] - md)
        sw += wt
        swh += wt * theta[hidx * n + i]
        i += 1usize
    }
    let est = swh / sw
    var v = 0.0f64
    i = 0usize
    while i < n {
        let wt = math.exp[f64](lf[i] - lg[i] - md)
        let hh = theta[hidx * n + i] - est
        v += hh * hh * wt * wt
        i += 1usize
    }
    out[0usize] = est
    out[1usize] = math.sqrt[f64](v) / sw
    ret ok
}

// normpostsim(data, prior, m): without a prior m draws of sigma2 = S / rchisq(n - 1) then m draws of mu | sigma2; with the prior (sigma2 ~ inverse gamma(a, b), mu ~ N(mu0, tau2)) m Gibbs steps, mu then sigma2 each. out_mu and out_s2 have length m
fn normpostsim(r: *rng.Rng, y: []const f64, has_prior: bool, a: f64, b: f64, mu0: f64, tau2: f64, m: usize, out_mu: []f64, out_s2: []f64) {
    let n = f64(y.len)
    var xbar = 0.0f64
    var i = 0usize
    while i < y.len {
        xbar += y[i]
        i += 1usize
    }
    xbar = xbar / n
    var s = 0.0f64
    i = 0usize
    while i < y.len {
        s += (y[i] - xbar) * (y[i] - xbar)
        i += 1usize
    }
    if !has_prior {
        i = 0usize
        while i < m {
            out_s2[i] = s / rd.rchisq(r, n - 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < m {
            out_mu[i] = xbar + math.sqrt[f64](out_s2[i]) / math.sqrt[f64](n) * rng.norm(r)
            i += 1usize
        }
        ret
    }
    var sigma2 = s / n
    var j = 0usize
    while j < m {
        let prec = n / sigma2 + 1.0f64 / tau2
        let mu1 = (xbar * n / sigma2 + mu0 / tau2) / prec
        let v1 = 1.0f64 / prec
        let mu = mu1 + math.sqrt[f64](v1) * rng.norm(r)
        let a1 = a + n / 2.0f64
        var ss = 0.0f64
        i = 0usize
        while i < y.len {
            ss += (y[i] - mu) * (y[i] - mu)
            i += 1usize
        }
        sigma2 = rigamma(r, a1, b + ss / 2.0f64)
        out_s2[j] = sigma2
        out_mu[j] = mu
        j += 1usize
    }
}

// blinreg(y, X, m, prior = list(c0, b0)): m draws of (sigma, beta) from the regression posterior, sigma = sqrt(1 / rgamma(m, shape, rate)) then beta = rmnorm(m, 0, V) scaled by sigma and shifted; x is n by p column-major, b0 the prior mean (ignored without a prior);
// sigma_out has length m, beta_out is m by p column-major
fn blinreg(a: *mem.Arena, r: *rng.Rng, y: []const f64, x: []const f64, n: usize, p: usize, m: usize, has_prior: bool, c0: f64, b0: []const f64, sigma_out: []f64, beta_out: []f64) -> err {
    let (xtx, e1) = mem.alloc[f64](a, p * p)
    let (u, e2) = mem.alloc[f64](a, p * p)
    let (iu, e3) = mem.alloc[f64](a, p * p)
    let (xtxi, e4) = mem.alloc[f64](a, p * p)
    let (bhat, e5) = mem.alloc[f64](a, p)
    let (bm, e6) = mem.alloc[f64](a, p)
    let (vb, e7) = mem.alloc[f64](a, p * p)
    let (zz, e8) = mem.alloc[f64](a, m * p)
    let (zm, e9) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Full }
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += x[j * n + i] * x[k * n + i]
                i += 1usize
            }
            xtx[k * p + j] = s
            k += 1usize
        }
        j += 1usize
    }
    if !bz.chol_upper(xtx, p, u) { ret mem.Full }
    bz.inv_upper(u, p, iu)
    // (X'X)^-1 = Ui Ui'
    j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += iu[q * p + j] * iu[q * p + k]
                q += 1usize
            }
            xtxi[k * p + j] = s
            k += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        var s = 0.0f64
        var k = 0usize
        while k < p {
            var xy = 0.0f64
            var i = 0usize
            while i < n {
                xy += x[k * n + i] * y[i]
                i += 1usize
            }
            s += xtxi[k * p + j] * xy
            k += 1usize
        }
        bhat[j] = s
        j += 1usize
    }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        var f = 0.0f64
        j = 0usize
        while j < p {
            f += x[j * n + i] * bhat[j]
            j += 1usize
        }
        rss += (y[i] - f) * (y[i] - f)
        i += 1usize
    }
    let dfr = f64(n - p)
    var shape = dfr / 2.0f64
    var rate = rss / 2.0f64
    var scale_v = 1.0f64
    j = 0usize
    while j < p {
        bm[j] = bhat[j]
        j += 1usize
    }
    if has_prior {
        shape = f64(n) / 2.0f64
        var q = 0.0f64
        j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                q += (b0[j] - bhat[j]) * xtx[k * p + j] * (b0[k] - bhat[k])
                k += 1usize
            }
            j += 1usize
        }
        rate = rss / 2.0f64 + q / 2.0f64 / (c0 + 1.0f64)
        j = 0usize
        while j < p {
            bm[j] = c0 / (c0 + 1.0f64) * (b0[j] / c0 + bhat[j])
            j += 1usize
        }
        scale_v = c0 / (c0 + 1.0f64)
    }
    j = 0usize
    while j < p * p {
        vb[j] = xtxi[j] * scale_v
        j += 1usize
    }
    i = 0usize
    while i < m {
        sigma_out[i] = math.sqrt[f64](1.0f64 / rd.rgamma(r, shape, 1.0f64 / rate))
        i += 1usize
    }
    j = 0usize
    while j < p {
        zm[j] = 0.0f64
        j += 1usize
    }
    let e = rmnorm(a, r, m, zm, vb, zz)
    if e != ok { ret e }
    j = 0usize
    while j < p {
        i = 0usize
        while i < m {
            beta_out[j * m + i] = bm[j] + sigma_out[i] * zz[j * m + i]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// sir(logf, tpar, n): sampling importance resampling, the proposal draws weighted by exp(lf - lg - max), n indices drawn with replacement the way R's sample does for fewer than 200 values (the weights sorted into decreasing order,
// a cumulative sum searched with one uniform per draw); out is the resampled n by d matrix, column-major
fn sir[Ctx: type](a: *mem.Arena, r: *rng.Rng, ctx: *Ctx, logf: fn(*Ctx, []const f64) -> f64, mean: []const f64, vr: []const f64, df: f64, n: usize, out: []f64) -> err {
    let d = mean.len
    let (theta, e1) = mem.alloc[f64](a, n * d)
    let (lf, e2) = mem.alloc[f64](a, n)
    let (lg, e3) = mem.alloc[f64](a, n)
    let (pr, e4) = mem.alloc[f64](a, n)
    let (perm, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    let e = proposal_draws[Ctx](a, r, ctx, logf, mean, vr, df, n, theta, lf, lg)
    if e != ok { ret e }
    var md = lf[0usize] - lg[0usize]
    var i = 1usize
    while i < n {
        if lf[i] - lg[i] > md { md = lf[i] - lg[i] }
        i += 1usize
    }
    var sw = 0.0f64
    i = 0usize
    while i < n {
        pr[i] = math.exp[f64](lf[i] - lg[i] - md)
        sw += pr[i]
        perm[i] = i
        i += 1usize
    }
    i = 0usize
    while i < n {
        pr[i] = pr[i] / sw
        i += 1usize
    }
    // decreasing order of the probabilities, an insertion sort carrying the indices
    i = 1usize
    while i < n {
        let kp = pr[i]
        let ki = perm[i]
        var j = i
        while j > 0usize && pr[j - 1usize] < kp {
            pr[j] = pr[j - 1usize]
            perm[j] = perm[j - 1usize]
            j -= 1usize
        }
        pr[j] = kp
        perm[j] = ki
        i += 1usize
    }
    i = 1usize
    while i < n {
        pr[i] += pr[i - 1usize]
        i += 1usize
    }
    var q = 0usize
    while q < n {
        let ru = rng.unif(r)
        var j = 0usize
        while j < n - 1usize {
            if ru <= pr[j] { break }
            j += 1usize
        }
        var c = 0usize
        while c < d {
            out[c * n + q] = theta[c * n + perm[j]]
            c += 1usize
        }
        q += 1usize
    }
    ret ok
}
