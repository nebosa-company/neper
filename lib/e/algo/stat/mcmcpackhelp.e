// R MCMCpack's conjugate Monte Carlo samplers (MCbinomialbeta, MCpoissongamma, MCnormalnormal, MCmultinomdirichlet) under R's own generator (set.seed
// stream), and the model comparison helpers BayesFactor (the matrices from the log marginal likelihoods) and PostProbMod.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.classint as ci
use e.algo.stat.mcmcpackdraw as md
use e.math
use e.mem

// rbeta(mc, alpha + y, beta + n - y) with y and n of the same length, recycled as R recycles the shape vectors
fn mc_binomialbeta(g: *rng.Rng, y: []const f64, n: []const f64, alpha: f64, beta: f64, mc: usize, out: []f64) {
    var i = 0usize
    while i < mc {
        let yi = y[i % y.len]
        let ni = n[i % n.len]
        out[i] = rd.rbeta(g, alpha + yi, beta + ni - yi)
        i += 1usize
    }
}

// rgamma(mc, alpha + sum(y), beta + length(y))
fn mc_poissongamma(g: *rng.Rng, y: []const f64, alpha: f64, beta: f64, mc: usize, out: []f64) {
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        s += y[i]
        i += 1usize
    }
    i = 0usize
    while i < mc {
        out[i] = md.rgamma(g, alpha + s, 1.0f64 / (beta + f64(y.len)))
        i += 1usize
    }
}

// rnorm(mc, mu1, sqrt(tau21)) with the posterior of a normal mean with known variance sigma2
fn mc_normalnormal(g: *rng.Rng, y: []const f64, sigma2: f64, mu0: f64, tau20: f64, mc: usize, out: []f64) {
    let n = f64(y.len)
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        s += y[i]
        i += 1usize
    }
    let mean = s / n
    let mu1 = (1.0f64 / tau20 * mu0 + n / sigma2 * mean) / (1.0f64 / tau20 + n / sigma2)
    let tau21 = 1.0f64 / (1.0f64 / tau20 + n / sigma2)
    i = 0usize
    while i < mc {
        out[i] = rng.rnorm(g, mu1, math.sqrt[f64](tau21))
        i += 1usize
    }
}

// rdirichlet(mc, y + alpha0): out is mc by length(y) row-major; ya is scratch of that length
fn mc_multinomdirichlet(g: *rng.Rng, y: []const f64, alpha0: []const f64, mc: usize, ya: []f64, out: []f64) {
    var i = 0usize
    while i < y.len {
        ya[i] = y[i] + alpha0[i]
        i += 1usize
    }
    md.rdirichlet(g, mc, ya, out)
}

// BayesFactor of models with the same y: bf[i * m + j] = exp(logml[i] - logml[j]) and logbf the difference
fn bayes_factor(logml: []const f64, bf: []f64, logbf: []f64) {
    let m = logml.len
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            logbf[i * m + j] = logml[i] - logml[j]
            bf[i * m + j] = math.exp[f64](logml[i] - logml[j])
            j += 1usize
        }
        i += 1usize
    }
}

// PostProbMod: posterior model probabilities from log marginal likelihoods and prior probabilities recycled to the model count
fn post_prob_mod(logml: []const f64, prior: []const f64, out: []f64) {
    let m = logml.len
    var psum = 0.0f64
    var i = 0usize
    while i < m {
        psum += prior[i % prior.len]
        i += 1usize
    }
    var mx = -1.0f64 / 0.0f64
    i = 0usize
    while i < m {
        let ln = logml[i] + math.log[f64](prior[i % prior.len] / psum)
        out[i] = ln
        if ln > mx { mx = ln }
        i += 1usize
    }
    var denom = 0.0f64
    i = 0usize
    while i < m {
        denom += math.exp[f64](out[i] - mx)
        i += 1usize
    }
    let logdenom = math.log[f64](denom)
    i = 0usize
    while i < m {
        out[i] = math.exp[f64]((out[i] - mx) - logdenom)
        i += 1usize
    }
}

// coda::HPDinterval(mcmc(x), prob): the shortest interval holding round(n * prob) steps of the sorted draws; out is lower, upper
fn hpd_interval(a: *mem.Arena, x: []const f64, prob: f64, out: []f64) -> err {
    let (s, e) = ci.sorted_copy(a, x)
    if e != ok { ret e }
    let n = s.len
    var gap = usize(math.round[f64](f64(n) * prob))
    if gap > n - 1usize { gap = n - 1usize }
    if gap < 1usize { gap = 1usize }
    var best = 0usize
    var i = 1usize
    while i < n - gap {
        if s[i + gap] - s[i] < s[best + gap] - s[best] { best = i }
        i += 1usize
    }
    out[0usize] = s[best]
    out[1usize] = s[best + gap]
    ret ok
}

// coda::spectrum0.ar(x)$spec: var.pred / (1 - sum(ar))^2 for the Yule-Walker fit ar(x) with the AIC order
fn spectrum0_ar(a: *mem.Arena, x: []const f64) -> (f64, err) {
    let n = x.len
    let nf = f64(n)
    var om = usize(math.floor[f64](10.0f64 * math.log10[f64](nf)))
    if om > n - 1usize { om = n - 1usize }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / nf
    let (r, e1) = mem.alloc[f64](a, om + 1usize)
    let (phi, e2) = mem.alloc[f64](a, om + 1usize)
    let (prev, e3) = mem.alloc[f64](a, om + 1usize)
    let (vars, e4) = mem.alloc[f64](a, om + 1usize)
    let (sums, e5) = mem.alloc[f64](a, om + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, e1) }
    var k = 0usize
    while k <= om {
        var s = 0.0f64
        i = 0usize
        while i + k < n {
            s += (x[i] - mean) * (x[i + k] - mean)
            i += 1usize
        }
        r[k] = s / nf
        phi[k] = 0.0f64
        k += 1usize
    }
    vars[0usize] = r[0usize]
    sums[0usize] = 0.0f64
    var m = 1usize
    while m <= om {
        var acc = r[m]
        var j = 1usize
        while j < m {
            acc -= phi[j] * r[m - j]
            j += 1usize
        }
        let kk = acc / vars[m - 1usize]
        j = 1usize
        while j < m {
            prev[j] = phi[j]
            j += 1usize
        }
        j = 1usize
        while j < m {
            phi[j] = prev[j] - kk * prev[m - j]
            j += 1usize
        }
        phi[m] = kk
        vars[m] = vars[m - 1usize] * (1.0f64 - kk * kk)
        var t = 0.0f64
        j = 1usize
        while j <= m {
            t += phi[j]
            j += 1usize
        }
        sums[m] = t
        m += 1usize
    }
    var best = 0usize
    var bestaic = nf * math.log[f64](vars[0usize]) + 2.0f64
    m = 1usize
    while m <= om {
        let aic = nf * math.log[f64](vars[m]) + 2.0f64 * f64(m) + 2.0f64
        if aic < bestaic {
            bestaic = aic
            best = m
        }
        m += 1usize
    }
    let vp = vars[best] * nf / (nf - f64(best + 1usize))
    let d = 1.0f64 - sums[best]
    ret (vp / (d * d), ok)
}

// coda summary.mcmc of one chain: out is mean, sd, naive se, time-series se, then quantiles .025 .25 .5 .75 .975
fn summary_mcmc(a: *mem.Arena, x: []const f64, out: []f64) -> err {
    let n = x.len
    let nf = f64(n)
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / nf
    var t = 0.0f64
    var ss = 0.0f64
    i = 0usize
    while i < n {
        t += x[i] - mean
        i += 1usize
    }
    mean += t / nf
    i = 0usize
    while i < n {
        ss += (x[i] - mean) * (x[i] - mean)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / (nf - 1.0f64))
    let (spec, e) = spectrum0_ar(a, x)
    if e != ok { ret e }
    out[0usize] = mean
    out[1usize] = sd
    out[2usize] = sd / math.sqrt[f64](nf)
    out[3usize] = math.sqrt[f64](spec / nf)
    let (s, e2) = ci.sorted_copy(a, x)
    if e2 != ok { ret e2 }
    out[4usize] = ci.quantile7(s, 0.025f64)
    out[5usize] = ci.quantile7(s, 0.25f64)
    out[6usize] = ci.quantile7(s, 0.5f64)
    out[7usize] = ci.quantile7(s, 0.75f64)
    out[8usize] = ci.quantile7(s, 0.975f64)
    ret ok
}
