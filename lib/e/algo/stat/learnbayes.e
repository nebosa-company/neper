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
