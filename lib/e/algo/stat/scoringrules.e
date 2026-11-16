// R scoringRules: proper scoring rules. Closed-form CRPS (`crps_*`), log score (`logs_*`) and Dawid-Sebastiani score (`dss_*`) of the
// normal, logistic, Laplace, exponential, uniform, log-normal and gamma forecasts (CRPS of the binomial too), and the sample-based
// scores: the empirical CRPS, the energy score, the variogram score, the kernel-density log score, the empirical Dawid-Sebastiani score,
// the quantile score and the ranked probability score.
//
// Also crps_pois (through the modified Bessel I of order 0 and 1), crps_t and logs_t. Not here: the negative binomial (it needs the Gauss hypergeometric function outside the unit disc), truncated and censored families, the kernel CRPS and the weighted variants.

use e.algo.stat.gslfns as gs
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

fn pn(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }

// ---- normal(location, scale)
fn crps_norm(y0: f64, loc: f64, s: f64) -> f64 {
    let y = y0 - loc
    let z = y / s
    ret y * (2.0f64 * dist.pnorm(y, 0.0f64, s, true, false) - 1.0f64) + s * (math.sqrt[f64](2.0f64) * math.exp[f64](0.0f64 - 0.5f64 * z * z) - 1.0f64) / math.sqrt[f64](pi())
}
fn logs_norm(y: f64, loc: f64, s: f64) -> f64 { ret 0.0f64 - dist.dnorm(y, loc, s, true) }
fn dss_norm(y0: f64, loc: f64, s: f64) -> f64 {
    let y = y0 - loc
    ret (y / s) * (y / s) + 2.0f64 * math.log[f64](s)
}

// ---- logistic(location, scale)
fn crps_logis(y: f64, loc: f64, s: f64) -> f64 {
    let z = (y - loc) / s
    // log of the standard logistic distribution function: -log(1 + exp(-z))
    let lp = 0.0f64 - dist.log1pexp(0.0f64 - z)
    ret s * (z - 2.0f64 * lp - 1.0f64)
}
fn logs_logis(y: f64, loc: f64, s: f64) -> f64 {
    let z = (y - loc) / s
    ret z + 2.0f64 * dist.log1pexp(0.0f64 - z) + math.log[f64](s)
}
fn dss_logis(y0: f64, loc: f64, s0: f64) -> f64 {
    let y = y0 - loc
    let s = s0 * pi() / math.sqrt[f64](3.0f64)
    ret (y / s) * (y / s) + 2.0f64 * math.log[f64](s)
}

// ---- Laplace(location, scale)
fn crps_lapl(y: f64, loc: f64, s: f64) -> f64 {
    let z = math.abs[f64]((y - loc) / s)
    ret s * (z + math.exp[f64](0.0f64 - z) - 0.75f64)
}
fn logs_lapl(y: f64, loc: f64, s: f64) -> f64 { ret 0.0f64 - math.log[f64](math.exp[f64](0.0f64 - math.abs[f64](y - loc) / s) / (2.0f64 * s)) }
fn dss_lapl(y0: f64, loc: f64, s0: f64) -> f64 {
    let y = y0 - loc
    let s = math.sqrt[f64](2.0f64) * s0
    ret (y / s) * (y / s) + 2.0f64 * math.log[f64](s)
}

// ---- exponential(rate)
fn crps_exp(y: f64, rate: f64) -> f64 { ret math.abs[f64](y) - (2.0f64 * nm.pgamma(y * rate, 1.0f64, 1.0f64, true, false) - 0.5f64) / rate }
fn logs_exp(y: f64, rate: f64) -> f64 { ret 0.0f64 - (math.log[f64](rate) - rate * y) }
fn dss_exp(y: f64, rate: f64) -> f64 { ret (y * rate - 1.0f64) * (y * rate - 1.0f64) - 2.0f64 * math.log[f64](rate) }

// ---- uniform(min, max) with point masses lmass at min and umass at max
fn crps_unif(y: f64, mn: f64, mx: f64, lmass: f64, umass: f64) -> f64 {
    let sc = mx - mn
    let yy = (y - mn) / sc
    var z = yy
    if z < 0.0f64 { z = 0.0f64 }
    if z > 1.0f64 { z = 1.0f64 }
    let aa = 1.0f64 - (lmass + umass)
    ret sc * (math.abs[f64](yy - z) + z * z * aa - z * (1.0f64 - 2.0f64 * lmass) + aa * aa / 3.0f64 + (1.0f64 - lmass) * umass)
}
fn logs_unif(y: f64, mn: f64, mx: f64) -> f64 {
    if y < mn || y > mx { ret 1.0f64 / 0.0f64 }
    ret math.log[f64](mx - mn)
}
fn dss_unif(y: f64, mn: f64, mx: f64) -> f64 {
    let m = 0.5f64 * (mn + mx)
    let s = (mx - mn) / math.sqrt[f64](12.0f64)
    ret ((y - m) / s) * ((y - m) / s) + 2.0f64 * math.log[f64](s)
}

// ---- log-normal(meanlog, sdlog)
fn crps_lnorm(y: f64, ml: f64, sl: f64) -> f64 {
    let c1 = y * (2.0f64 * dist.plnorm(y, ml, sl, true, false) - 1.0f64)
    let c2 = 2.0f64 * math.exp[f64](ml + 0.5f64 * sl * sl)
    let c3 = dist.plnorm(y, ml + sl * sl, sl, true, false) + pn(sl / math.sqrt[f64](2.0f64)) - 1.0f64
    ret c1 - c2 * c3
}
fn logs_lnorm(y: f64, ml: f64, sl: f64) -> f64 {
    let lz = (math.log[f64](y) - ml) / sl
    ret 0.0f64 - (0.0f64 - 0.5f64 * lz * lz - math.log[f64](sl) - 0.5f64 * math.log[f64](2.0f64 * pi()) - math.log[f64](y))
}
fn dss_lnorm(y: f64, ml: f64, sl: f64) -> f64 {
    let sl2 = sl * sl
    let m = math.exp[f64](ml + sl2 / 2.0f64)
    let v = m * m * dist.expm1(sl2)
    ret (y - m) * (y - m) / v + math.log[f64](v)
}

// ---- gamma(shape, scale)
fn crps_gamma(y: f64, shape: f64, scale: f64) -> f64 {
    let p1 = nm.pgamma(y, shape, scale, true, false)
    let p2 = nm.pgamma(y, shape + 1.0f64, scale, true, false)
    ret y * (2.0f64 * p1 - 1.0f64) - scale * (shape * (2.0f64 * p2 - 1.0f64) + 1.0f64 / math.exp[f64](nb.lbeta(0.5f64, shape)))
}
fn logs_gamma(y: f64, shape: f64, scale: f64) -> f64 { ret 0.0f64 - nm.dgamma(y, shape, scale, true) }
fn dss_gamma(y: f64, shape: f64, scale: f64) -> f64 {
    let ms = math.sqrt[f64](shape)
    let s = ms * scale
    ret (y / s - ms) * (y / s - ms) + 2.0f64 * math.log[f64](s)
}

// ---- Poisson log and Dawid-Sebastiani scores
fn logs_pois(y: f64, lambda: f64) -> f64 { ret 0.0f64 - nm.dpois(y, lambda, true) }
fn dss_pois(y: f64, lambda: f64) -> f64 { ret (y - lambda) * (y - lambda) / lambda + math.log[f64](lambda) }

// ---- binomial CRPS: 2 sum w ((y < x) - a)(x - y), a = F(x) - w / 2
fn crps_binom(y: f64, size: f64, prob: f64) -> f64 {
    var s = 0.0f64
    var x = 0.0f64
    while x <= size {
        let w = nb.dbinom(x, size, prob, false)
        let a = nb.pbinom(x, size, prob, true, false) - 0.5f64 * w
        var ind = 0.0f64
        if y < x { ind = 1.0f64 }
        s += w * (ind - a) * (x - y)
        x += 1.0f64
    }
    ret 2.0f64 * s
}

// ---- sample-based scores

// crps_sample(y, dat, method = "edf")
fn crps_sample(y: f64, dat: []const f64) -> f64 {
    let n = f64(dat.len)
    var a = 0.0f64
    var b = 0.0f64
    var i = 0usize
    while i < dat.len {
        a += math.abs[f64](dat[i] - y)
        var j = 0usize
        while j < dat.len {
            b += math.abs[f64](dat[i] - dat[j])
            j += 1usize
        }
        i += 1usize
    }
    ret a / n - 0.5f64 * b / (n * n)
}

// dss_sample: the population variance of the draws
fn dss_sample(y: f64, dat: []const f64) -> f64 {
    let n = f64(dat.len)
    var m = 0.0f64
    var i = 0usize
    while i < dat.len {
        m += dat[i]
        i += 1usize
    }
    m = m / n
    var v = 0.0f64
    i = 0usize
    while i < dat.len {
        v += (dat[i] - m) * (dat[i] - m)
        i += 1usize
    }
    v = v / n
    ret (y - m) * (y - m) / v + math.log[f64](v)
}

// es_sample: dat is m draws of dimension d (row-major m by d)
fn es_sample(y: []const f64, dat: []const f64, m: usize) -> f64 {
    let d = y.len
    var xy = 0.0f64
    var xx = 0.0f64
    var i = 0usize
    while i < m {
        var s = 0.0f64
        var c = 0usize
        while c < d {
            s += (dat[i * d + c] - y[c]) * (dat[i * d + c] - y[c])
            c += 1usize
        }
        xy += math.sqrt[f64](s)
        var j = 0usize
        while j < m {
            var t = 0.0f64
            c = 0usize
            while c < d {
                t += (dat[i * d + c] - dat[j * d + c]) * (dat[i * d + c] - dat[j * d + c])
                c += 1usize
            }
            xx += math.sqrt[f64](t)
            j += 1usize
        }
        i += 1usize
    }
    ret xy / f64(m) - 0.5f64 * xx / (f64(m) * f64(m))
}

// vs_sample with p and no weights
fn vs_sample(y: []const f64, dat: []const f64, m: usize, p: f64) -> f64 {
    let d = y.len
    var out = 0.0f64
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            var e = 0.0f64
            var r = 0usize
            while r < m {
                e += math.pow[f64](math.abs[f64](dat[r * d + i] - dat[r * d + j]), p)
                r += 1usize
            }
            e = e / f64(m)
            let o = math.pow[f64](math.abs[f64](y[i] - y[j]), p)
            out += (o - e) * (o - e)
            j += 1usize
        }
        i += 1usize
    }
    ret out
}

// logs_sample: the negative log of the Gaussian kernel density of the draws at y, bandwidth bw.nrd
fn bw_nrd(a: *mem.Arena, x: []const f64) -> f64 {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / n
    var v = 0.0f64
    i = 0usize
    while i < x.len {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    let sd = math.sqrt[f64](v / (n - 1.0f64))
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    let q1 = quant7(s, 0.25f64)
    let q3 = quant7(s, 0.75f64)
    var h = (q3 - q1) / 1.34f64
    if sd < h { h = sd }
    if h == 0.0f64 { h = sd }
    ret 1.06f64 * h * math.pow[f64](n, 0.0f64 - 0.2f64)
}

// R's quantile type 7 of a sorted vector
fn quant7(s: []const f64, p: f64) -> f64 {
    let n = f64(s.len)
    let h = (n - 1.0f64) * p
    let lo = math.floor[f64](h + 4.0f64 * 2.220446049250313e-16f64)
    let fr = h - lo
    let i = usize(lo)
    if i + 1usize >= s.len { ret s[s.len - 1usize] }
    var f = fr
    if f < 4.0f64 * 2.220446049250313e-16f64 { f = 0.0f64 }
    ret s[i] + f * (s[i + 1usize] - s[i])
}

fn logs_sample(a: *mem.Arena, y: f64, dat: []const f64) -> f64 {
    let bw = bw_nrd(a, dat)
    var s = 0.0f64
    var i = 0usize
    while i < dat.len {
        s += dist.dnorm(y, dat[i], bw, false)
        i += 1usize
    }
    ret 0.0f64 - math.log[f64](s / f64(dat.len))
}

// qs_sample: the quantile score of the type-7 sample quantile at level alpha
fn qs_sample(a: *mem.Arena, y: f64, dat: []const f64, alpha: f64) -> f64 {
    let (s, e) = mem.alloc[f64](a, dat.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < dat.len {
        s[i] = dat[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    let q = quant7(s, alpha)
    var ind = 0.0f64
    if y < q { ind = 1.0f64 }
    ret (ind - alpha) * (q - y)
}

// rps_probs(y, x): y the 1-based observed category, x the category probabilities
fn rps_probs(y: usize, x: []const f64) -> f64 {
    var c = 0.0f64
    var s = 0.0f64
    var k = 0usize
    while k < x.len {
        c += x[k]
        var o = 0.0f64
        if k + 1usize >= y { o = 1.0f64 }
        s += (c - o) * (c - o)
        k += 1usize
    }
    ret s
}

// crps_pois(y, lambda): (y - lambda)(2 F(y) - 1) + lambda (2 f(floor y) - exp(-2 lambda) (I0(2 lambda) + I1(2 lambda)))
fn crps_pois(y: f64, lambda: f64) -> f64 {
    let c1 = (y - lambda) * (2.0f64 * nm.ppois(y, lambda, true, false) - 1.0f64)
    let es = math.exp[f64](0.0f64 - 2.0f64 * lambda)
    let c2 = 2.0f64 * nm.dpois(math.floor[f64](y), lambda, false) - es * gs.bessel_inu(0.0f64, 2.0f64 * lambda) - es * gs.bessel_inu(1.0f64, 2.0f64 * lambda)
    ret c1 + lambda * c2
}

// crps_t(y, df, location, scale) for df > 1
fn crps_t(y0: f64, df: f64, loc: f64, scale: f64) -> f64 {
    let y = (y0 - loc) / scale
    let bfrac = math.exp[f64](nb.lbeta(0.5f64, df - 0.5f64) - 2.0f64 * nb.lbeta(0.5f64, 0.5f64 * df))
    let c = y * (2.0f64 * nb.pt(y, df, true, false) - 1.0f64) + 2.0f64 / (df - 1.0f64) * (nb.dt(y, df, false) * (df + y * y) - math.sqrt[f64](df) * bfrac)
    ret scale * c
}

// logs_t(y, df, location, scale)
fn logs_t(y: f64, df: f64, loc: f64, scale: f64) -> f64 { ret 0.0f64 - nb.dt((y - loc) / scale, df, true) + math.log[f64](scale) }
