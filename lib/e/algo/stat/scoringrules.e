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
use e.math.special as sp
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

// crps_gtcnorm(y, location, scale, lower, upper, lmass, umass) for scale > 0: the CRPS of a normal truncated to [lower, upper] with point masses lmass and umass at the ends (crps_tnorm
// has masses 0 and crps_cnorm the tail probabilities). The unit-scale core flips the sign when lower > 3 for accuracy, as the package does.
fn crps_gtc_unit(y0: f64, lower0: f64, upper0: f64, lmass0: f64, umass0: f64) -> f64 {
    var y = y0
    var lower = lower0
    var upper = upper0
    var lmass = lmass0
    var umass = umass0
    if lower > 3.0f64 {
        y = 0.0f64 - y
        let nl = 0.0f64 - upper
        let nu = 0.0f64 - lower
        lower = nl
        upper = nu
        let tl = lmass
        lmass = umass
        umass = tl
    }
    let inf = 1.0f64 / 0.0f64
    var out_l1 = 0.0f64
    var out_l2 = 0.0f64
    var out_l3 = 0.0f64
    var out_u1 = 0.0f64
    var out_u2 = 0.0f64
    var out_u3 = 1.0f64
    var p_l = 0.0f64
    var p_u = 1.0f64
    var z = y
    if lower != 0.0f64 - inf || lmass != 0.0f64 {
        p_l = pn(lower)
        if lmass != 0.0f64 { out_l1 = lower * lmass * lmass }
        out_l2 = 2.0f64 * dist.dnorm(lower, 0.0f64, 1.0f64, false) * lmass
        out_l3 = dist.pnorm(lower, 0.0f64, math.sqrt[f64](0.5f64), true, false)
        if lower > z { z = lower }
    }
    if upper != inf || umass != 0.0f64 {
        p_u = pn(upper)
        if umass != 0.0f64 { out_u1 = upper * umass * umass }
        out_u2 = 2.0f64 * dist.dnorm(upper, 0.0f64, 1.0f64, false) * umass
        out_u3 = dist.pnorm(upper, 0.0f64, math.sqrt[f64](0.5f64), true, false)
        if upper < z { z = upper }
    }
    let a1 = p_u - p_l
    let a2 = 1.0f64 - (umass + lmass)
    let b = out_u3 - out_l3
    let out = out_u1 - out_l1 + (z * (2.0f64 * a2 * pn(z) - (1.0f64 - 2.0f64 * lmass) * p_u - (1.0f64 - 2.0f64 * umass) * p_l) + (2.0f64 * dist.dnorm(z, 0.0f64, 1.0f64, false) - out_u2 - out_l2 - a2 * b / a1 / math.sqrt[f64](pi())) * a2) / a1
    ret out + math.abs[f64](y - z)
}

fn crps_gtcnorm(y: f64, loc: f64, scale: f64, lower: f64, upper: f64, lmass: f64, umass: f64) -> f64 {
    ret scale * crps_gtc_unit((y - loc) / scale, (lower - loc) / scale, (upper - loc) / scale, lmass, umass)
}

fn plogis_std(x: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) }

// log(plogis(-x)) = -log(1 + exp(x)), stable for either sign
fn log_plogis_neg(x: f64) -> f64 {
    var m = x
    if m < 0.0f64 { m = 0.0f64 }
    ret 0.0f64 - (m + math.log[f64](1.0f64 + math.exp[f64](0.0f64 - math.abs[f64](x))))
}

// crps_gtclogis(y, location, scale, lower, upper, lmass, umass): the logistic analogue of crps_gtcnorm, with the package's small-p series for the end terms
fn crps_gtcl_unit(y0: f64, lower0: f64, upper0: f64, lmass0: f64, umass0: f64) -> f64 {
    var y = y0
    var lower = lower0
    var upper = upper0
    var lmass = lmass0
    var umass = umass0
    if lower > 3.0f64 {
        y = 0.0f64 - y
        let nl = 0.0f64 - upper
        let nu = 0.0f64 - lower
        lower = nl
        upper = nu
        let tl = lmass
        lmass = umass
        umass = tl
    }
    let inf = 1.0f64 / 0.0f64
    var out_l1 = 0.0f64
    var out_l2 = 0.0f64
    var out_l3 = 0.0f64
    var out_u1 = 0.0f64
    var out_u2 = 0.0f64
    var out_u3 = 1.0f64
    var p_l = 0.0f64
    var p_u = 1.0f64
    var z = y
    if lower != 0.0f64 - inf || lmass != 0.0f64 {
        p_l = plogis_std(lower)
        if lower != 0.0f64 - inf {
            let lp = log_plogis_neg(lower)
            if lmass != 0.0f64 { out_l1 = lower * lmass * lmass }
            out_l2 = 2.0f64 * (lower * p_l + lp) * lmass
            var t = 0.0f64
            if p_l > 1.0e-8f64 { t = p_l + lp } else { t = 0.0f64 - p_l * p_l / 2.0f64 - p_l * p_l * p_l / 3.0f64 }
            out_l3 = t - p_l * (lower * p_l + 2.0f64 * lp)
        }
        if lower > z { z = lower }
    }
    if upper != inf || umass != 0.0f64 {
        p_u = plogis_std(upper)
        if upper != inf {
            let lp = log_plogis_neg(upper)
            if umass != 0.0f64 { out_u1 = upper * umass * umass }
            out_u2 = 2.0f64 * (upper * p_u + lp) * umass
            var t = 0.0f64
            if p_u > 1.0e-8f64 { t = p_u + lp } else { t = 0.0f64 - p_u * p_u / 2.0f64 - p_u * p_u * p_u / 3.0f64 }
            out_u3 = t - p_u * (upper * p_u + 2.0f64 * lp)
        }
        if upper < z { z = upper }
    }
    let a1 = p_u - p_l
    let a2 = 1.0f64 - (umass + lmass)
    let b = out_u3 - out_l3
    let out = out_u1 - out_l1 - (z * ((1.0f64 - 2.0f64 * lmass) * p_u + (1.0f64 - 2.0f64 * umass) * p_l) + (2.0f64 * log_plogis_neg(z) - out_u2 - out_l2 + a2 * b / a1) * a2) / a1
    ret out + math.abs[f64](y - z)
}

fn crps_gtclogis(y: f64, loc: f64, scale: f64, lower: f64, upper: f64, lmass: f64, umass: f64) -> f64 {
    ret scale * crps_gtcl_unit((y - loc) / scale, (lower - loc) / scale, (upper - loc) / scale, lmass, umass)
}

// crps_gtct(y, df, location, scale, lower, upper, lmass, umass) for df > 1 and scale > 0: the t analogue of crps_gtcnorm, through the t cdf and density and the incomplete beta function
fn gt_term(x: f64, df: f64, inf: f64) -> f64 {
    if x == inf || x == 0.0f64 - inf { ret 0.0f64 }
    ret 0.0f64 - (df + x * x) / (df - 1.0f64) * nb.dt(x, df, false)
}

fn crps_gtct_unit(y0: f64, df: f64, lower0: f64, upper0: f64, lmass0: f64, umass0: f64) -> f64 {
    var y = y0
    var lower = lower0
    var upper = upper0
    var lmass = lmass0
    var umass = umass0
    if lower > 3.0f64 {
        y = 0.0f64 - y
        let nl = 0.0f64 - upper
        let nu = 0.0f64 - lower
        lower = nl
        upper = nu
        let tl = lmass
        lmass = umass
        umass = tl
    }
    let inf = 1.0f64 / 0.0f64
    var out_l1 = 0.0f64
    var out_l2 = 0.0f64
    var out_l3 = 0.0f64
    var out_u1 = 0.0f64
    var out_u2 = 0.0f64
    var out_u3 = 1.0f64
    var p_l = 0.0f64
    var p_u = 1.0f64
    var z = y
    if lower != 0.0f64 - inf || lmass != 0.0f64 {
        p_l = nb.pt(lower, df, true, false)
        let g_l = gt_term(lower, df, inf)
        var pb_l = 0.0f64
        if lower != 0.0f64 - inf { pb_l = nb.pbeta(df / (df + lower * lower), df - 0.5f64, 0.5f64, true, false) }
        if lmass != 0.0f64 { out_l1 = lower * lmass * lmass }
        out_l2 = 2.0f64 * g_l * lmass
        if p_l <= 0.5f64 { out_l3 = 0.5f64 * pb_l } else { out_l3 = 0.5f64 * (2.0f64 - pb_l) }
        if lower > z { z = lower }
    }
    if upper != inf || umass != 0.0f64 {
        p_u = nb.pt(upper, df, true, false)
        let g_u = gt_term(upper, df, inf)
        var pb_u = 0.0f64
        if upper != inf { pb_u = nb.pbeta(df / (df + upper * upper), df - 0.5f64, 0.5f64, true, false) }
        if umass != 0.0f64 { out_u1 = upper * umass * umass }
        out_u2 = 2.0f64 * g_u * umass
        if p_u <= 0.5f64 { out_u3 = 0.5f64 * pb_u } else { out_u3 = 0.5f64 * (2.0f64 - pb_u) }
        if upper < z { z = upper }
    }
    let a1 = p_u - p_l
    let a2 = 1.0f64 - (umass + lmass)
    let b = out_u3 - out_l3
    let bfrac = 2.0f64 * math.sqrt[f64](df) / (df - 1.0f64) * math.exp[f64](nb.lbeta(0.5f64, df - 0.5f64) - 2.0f64 * nb.lbeta(0.5f64, 0.5f64 * df))
    let g_z = gt_term(z, df, inf)
    let out = out_u1 - out_l1 + (z * (2.0f64 * a2 * nb.pt(z, df, true, false) - (1.0f64 - 2.0f64 * lmass) * p_u - (1.0f64 - 2.0f64 * umass) * p_l) - (2.0f64 * g_z - out_u2 - out_l2 + a2 * b / a1 * bfrac) * a2) / a1
    ret out + math.abs[f64](y - z)
}

fn crps_gtct(y: f64, df: f64, loc: f64, scale: f64, lower: f64, upper: f64, lmass: f64, umass: f64) -> f64 {
    ret scale * crps_gtct_unit((y - loc) / scale, df, (lower - loc) / scale, (upper - loc) / scale, lmass, umass)
}

// crps_sample(y, dat, w = w): the weighted empirical-distribution CRPS, 2 / P sum w_i ((y < x_i) - a_i)(x_i - y) over the sorted sample with a_i = (cumsum(w)_i - w_i / 2) / P
fn crps_edf_w(a: *mem.Arena, y: f64, dat: []const f64, w: []const f64) -> f64 {
    let n = dat.len
    let (idx, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let t = idx[i]
        var j = i
        while j > 0usize && dat[idx[j - 1usize]] > dat[t] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = t
        i += 1usize
    }
    var total = 0.0f64
    i = 0usize
    while i < n {
        total += w[i]
        i += 1usize
    }
    var run = 0.0f64
    var s = 0.0f64
    i = 0usize
    while i < n {
        let k = idx[i]
        run += w[k]
        let ai = (run - 0.5f64 * w[k]) / total
        var ind = 0.0f64
        if y < dat[k] { ind = 1.0f64 }
        s += w[k] * (ind - ai) * (dat[k] - y)
        i += 1usize
    }
    ret 2.0f64 / total * s
}

// A(mu, s2) = mu (2 Phi(mu / s) - 1) + 2 s phi(mu / s)
fn a_mix(mu: f64, s2: f64) -> f64 {
    let s = math.sqrt[f64](s2)
    ret mu * (2.0f64 * pn(mu / s) - 1.0f64) + 2.0f64 * s * dist.dnorm(mu / s, 0.0f64, 1.0f64, false)
}

// crps_sample(y, dat, method = "kde", bw): the CRPS of the Gaussian kernel density with bandwidth bw (bw.nrd when bw is not positive), as a normal mixture with equal weights
fn crps_kde(a: *mem.Arena, y: f64, dat: []const f64, bw0: f64) -> f64 {
    var bw = bw0
    if bw <= 0.0f64 { bw = bw_nrd(a, dat) }
    let n = dat.len
    let wt = 1.0f64 / f64(n)
    var s1 = 0.0f64
    var i = 0usize
    while i < n {
        s1 += wt * a_mix(y - dat[i], bw * bw)
        i += 1usize
    }
    var s2 = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            s2 += wt * wt * a_mix(dat[i] - dat[j], 2.0f64 * bw * bw)
            j += 1usize
        }
        i += 1usize
    }
    ret s1 - 0.5f64 * s2
}

// 2F1(a, 0.5; 2; z) for z <= 0 by Pfaff's transformation (1 - z)^(-0.5) 2F1(2 - a, 0.5; 2; z / (z - 1)), whose argument lies in [0, 1)
fn hypergeo_half_2(a: f64, z: f64) -> f64 {
    let w = z / (z - 1.0f64)
    var t = 1.0f64
    var s = 1.0f64
    var k = 0usize
    while k < 200000usize {
        t = t * (2.0f64 - a + f64(k)) * (0.5f64 + f64(k)) * w / ((2.0f64 + f64(k)) * f64(k + 1usize))
        s += t
        if math.abs[f64](t) < 1.0e-17f64 * math.abs[f64](s) && f64(k) > 2.0f64 - a { break }
        k += 1usize
    }
    ret s / math.sqrt[f64](1.0f64 - z)
}

// crps_nbinom(y, size, prob)
fn crps_nbinom(y: f64, size: f64, prob: f64) -> f64 {
    let c1 = y * (2.0f64 * nb.pnbinom(y, size, prob, true, false) - 1.0f64)
    let c2 = (1.0f64 - prob) / (prob * prob)
    let c3 = prob * (2.0f64 * nb.pnbinom(y - 1.0f64, size + 1.0f64, prob, true, false) - 1.0f64) + hypergeo_half_2(size + 1.0f64, 0.0f64 - 4.0f64 * c2)
    ret c1 - size * c2 * c3
}

// crps_mixnorm(y, m, s, w): the CRPS of a normal mixture, sum w_i A(y - m_i, s_i^2) - 0.5 sum sum w_i w_j A(m_i - m_j, s_i^2 + s_j^2), weights normalised
fn crps_mixnorm(y: f64, m: []const f64, s: []const f64, w: []const f64) -> f64 {
    var tw = 0.0f64
    var i = 0usize
    while i < m.len {
        tw += w[i]
        i += 1usize
    }
    var s1 = 0.0f64
    i = 0usize
    while i < m.len {
        s1 += w[i] / tw * a_mix(y - m[i], s[i] * s[i])
        i += 1usize
    }
    var s2 = 0.0f64
    i = 0usize
    while i < m.len {
        var j = 0usize
        while j < m.len {
            s2 += w[i] / tw * w[j] / tw * a_mix(m[i] - m[j], s[i] * s[i] + s[j] * s[j])
            j += 1usize
        }
        i += 1usize
    }
    ret s1 - 0.5f64 * s2
}

// crps_expM(y, location, scale, mass)
fn crps_expm(y0: f64, loc: f64, scale: f64, mass: f64) -> f64 {
    let y = y0 - loc
    let a = 1.0f64 - mass
    var pe = 0.0f64
    if y > 0.0f64 { pe = 1.0f64 - math.exp[f64](0.0f64 - y / scale) }
    ret math.abs[f64](y) - scale * a * (2.0f64 * pe - 0.5f64 * a)
}

// crps_2pexp(y, scale1, scale2, location)
fn crps_2pexp(y0: f64, s1: f64, s2: f64, loc: f64) -> f64 {
    let y = y0 - loc
    var z = y
    if z < 0.0f64 { z = 0.0f64 }
    var yn = y
    if yn > 0.0f64 { yn = 0.0f64 }
    var s = s1 + s2
    if s == 0.0f64 { s = 1.0f64 / 0.0f64 }
    ret crps_expm(0.0f64 - yn, 0.0f64, s1, s2 / s) + crps_expm(z, 0.0f64, s2, s1 / s)
}

// crps_2pnorm(y, scale1, scale2, location)
fn crps_2pnorm(y0: f64, s1: f64, s2: f64, loc: f64) -> f64 {
    let y = y0 - loc
    var z = y
    if z < 0.0f64 { z = 0.0f64 }
    var yn = y
    if yn > 0.0f64 { yn = 0.0f64 }
    var s = s1 + s2
    if s == 0.0f64 { s = 1.0f64 / 0.0f64 }
    let inf = 1.0f64 / 0.0f64
    ret crps_gtcnorm(yn, 0.0f64, s1, 0.0f64 - inf, 0.0f64, 0.0f64, s2 / s) + crps_gtcnorm(z, 0.0f64, s2, 0.0f64, inf, s1 / s, 0.0f64)
}

// crps_gpd(y, shape, location, scale, mass) for shape < 1
fn crps_gpd(y0: f64, shape: f64, loc: f64, scale: f64, mass: f64) -> f64 {
    let y = y0 - loc
    let z = y / scale
    var x = 1.0f64 + shape * z
    if x < 0.0f64 { x = 0.0f64 }
    if math.abs[f64](shape) < 1.0e-12f64 { x = math.exp[f64](0.0f64 - z) } else { x = math.pow[f64](x, 0.0f64 - 1.0f64 / shape) }
    if x > 1.0f64 { x = 1.0f64 }
    let a = 1.0f64 - mass
    let b = 1.0f64 - shape
    ret math.abs[f64](y) - scale * a * (2.0f64 / b * (1.0f64 - math.pow[f64](x, b)) - a / (2.0f64 - shape))
}

// crps_gev(y, shape, location, scale) for shape < 1
fn crps_gev(y0: f64, shape: f64, loc: f64, scale: f64) -> f64 {
    let y = (y0 - loc) / scale
    if math.abs[f64](shape) < 1.0e-12f64 {
        ret scale * (0.0f64 - y - gs.psi(1.0f64) - math.log[f64](2.0f64) - 2.0f64 * gs.expint_ei(0.0f64 - math.exp[f64](0.0f64 - y)))
    }
    var x = 1.0f64 + shape * y
    if x < 0.0f64 { x = 0.0f64 }
    x = math.pow[f64](x, 0.0f64 - 1.0f64 / shape)
    let c1 = 2.0f64 * math.exp[f64](0.0f64 - x) - 1.0f64
    let out = (y + 1.0f64 / shape) * c1 + math.exp[f64](sp.lgamma(1.0f64 - shape)) / shape * (2.0f64 * nm.pgamma(x, 1.0f64 - shape, 1.0f64, true, false) - math.pow[f64](2.0f64, shape))
    ret scale * out
}

// crps_llapl(y, locationlog, scalelog) for scalelog in [0, 1)
fn crps_llapl(y: f64, ll: f64, sl: f64) -> f64 {
    var y1 = y
    if y1 < 0.0f64 { y1 = 0.0f64 }
    let z = (math.log[f64](y1) - ll) / sl
    var sg = 0.0f64
    if z > 0.0f64 { sg = 1.0f64 }
    if z < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    let p = 0.5f64 + 0.5f64 * sg * (1.0f64 - math.exp[f64](0.0f64 - math.abs[f64](z)))
    let c1 = y * (2.0f64 * p - 1.0f64)
    var c2 = 0.0f64
    if z < 0.0f64 { c2 = (1.0f64 - math.pow[f64](2.0f64 * p, 1.0f64 + sl)) / (1.0f64 + sl) } else { c2 = 0.0f64 - (1.0f64 - math.pow[f64](2.0f64 * (1.0f64 - p), 1.0f64 - sl)) / (1.0f64 - sl) }
    let c3 = sl / (4.0f64 - sl * sl)
    ret c1 + math.exp[f64](ll) * (c2 + c3)
}

// crps_llogis(y, locationlog, scalelog) for scalelog in [0, 1)
fn crps_llogis(y: f64, ll: f64, sl: f64) -> f64 {
    var y1 = y
    if y1 < 0.0f64 { y1 = 0.0f64 }
    let p = plogis_std((math.log[f64](y1) - ll) / sl)
    let c1 = y * (2.0f64 * p - 1.0f64)
    let c2 = 2.0f64 * math.exp[f64](ll) * math.exp[f64](nb.lbeta(1.0f64 + sl, 1.0f64 - sl))
    let c3 = (1.0f64 - sl) / 2.0f64 - nb.pbeta(p, 1.0f64 + sl, 1.0f64 - sl, true, false)
    ret c1 + c2 * c3
}

// crps_beta(y, shape1, shape2, lower, upper)
fn crps_beta(y0: f64, a: f64, b: f64, lower: f64, upper: f64) -> f64 {
    let scale = upper - lower
    let y = (y0 - lower) / scale
    let c1 = y * (2.0f64 * nb.pbeta(y, a, b, true, false) - 1.0f64)
    let c2 = a / (a + b)
    let c3 = 1.0f64 - 2.0f64 * nb.pbeta(y, a + 1.0f64, b, true, false)
    var c4 = 2.0f64 / a * math.exp[f64](nb.lbeta(2.0f64 * a, 2.0f64 * b) - 2.0f64 * nb.lbeta(a, b))
    if !(c4 < 1.0e300f64) { c4 = math.sqrt[f64](b / (pi() * a * (a + b))) }
    ret scale * (c1 + c2 * (c3 - c4))
}

// crps_hyper(y, m, n, k): the hypergeometric CRPS, 2 sum w ((y < x) - a)(x - y) over x = max(0, k - n) .. min(k, m)
fn crps_hyper(y: f64, m: f64, n: f64, k: f64) -> f64 {
    var lo = k - n
    if lo < 0.0f64 { lo = 0.0f64 }
    var hi = k
    if m < hi { hi = m }
    var s = 0.0f64
    var x = lo
    while x <= hi {
        let w = nb.dhyper(x, m, n, k, false)
        let a = nb.phyper(x, m, n, k, true, false) - 0.5f64 * w
        var ind = 0.0f64
        if y < x { ind = 1.0f64 }
        s += w * (ind - a) * (x - y)
        x += 1.0f64
    }
    ret 2.0f64 * s
}

fn logs_nbinom(y: f64, size: f64, prob: f64) -> f64 { ret 0.0f64 - nb.dnbinom(y, size, prob, true) }

fn dss_moments(y: f64, mean: f64, v: f64) -> f64 { ret (y - mean) * (y - mean) / v + math.log[f64](v) }

fn dss_nbinom(y: f64, size: f64, prob: f64) -> f64 {
    let mu = size * (1.0f64 - prob) / prob
    ret dss_moments(y, mu, mu / prob)
}

fn dss_t(y0: f64, df: f64, loc: f64, scale: f64) -> f64 {
    let v = scale * scale * df / (df - 2.0f64)
    let y = y0 - loc
    ret y * y / v + math.log[f64](v)
}

fn dss_beta(y0: f64, a: f64, b: f64, lower: f64, upper: f64) -> f64 {
    let scale = upper - lower
    let r = b / a
    let m = scale / (1.0f64 + r)
    let v = m * m * r / (1.0f64 + a + b)
    ret dss_moments(y0 - lower, m, v)
}

fn dss_gev(y0: f64, shape: f64, loc: f64, scale: f64) -> f64 {
    var m1 = 0.0f64
    var v1 = 0.0f64
    if math.abs[f64](shape) < 1.0e-12f64 {
        m1 = 0.0f64 - gs.psi(1.0f64)
        v1 = pi() * pi() / 6.0f64
    } else {
        let g1 = math.exp[f64](sp.lgamma(1.0f64 - shape))
        m1 = (g1 - 1.0f64) / shape
        v1 = (math.exp[f64](sp.lgamma(1.0f64 - 2.0f64 * shape)) - g1 * g1) / (shape * shape)
    }
    ret dss_moments(y0 - loc, m1 * scale, v1 * scale * scale)
}

fn dss_gpd(y0: f64, shape: f64, loc: f64, scale: f64) -> f64 {
    let m = scale / (1.0f64 - shape)
    ret dss_moments(y0 - loc, m, m * m / (1.0f64 - 2.0f64 * shape))
}

fn dss_llapl(y: f64, ll: f64, sl: f64) -> f64 {
    let sl2 = sl * sl
    let ell = math.exp[f64](ll)
    ret dss_moments(y, ell / (1.0f64 - sl2), ell * ell * (1.0f64 / (1.0f64 - 4.0f64 * sl2) - 1.0f64 / ((1.0f64 - sl2) * (1.0f64 - sl2))))
}

fn dss_llogis(y: f64, ll: f64, sl: f64) -> f64 {
    let b = pi() * sl
    let sb = math.sin[f64](b)
    let ell = math.exp[f64](ll)
    ret dss_moments(y, ell * b / sb, ell * ell * 2.0f64 * b / math.sin[f64](2.0f64 * b) - b * b / (sb * sb))
}

fn logs_beta(y: f64, a: f64, b: f64, lower: f64, upper: f64) -> f64 {
    let scale = upper - lower
    ret 0.0f64 - nb.dbeta((y - lower) / scale, a, b, true) + math.log[f64](scale)
}

fn logs_hyper(y: f64, m: f64, n: f64, k: f64) -> f64 { ret 0.0f64 - nb.dhyper(y, m, n, k, true) }

fn logs_gev(y0: f64, shape: f64, loc: f64, scale: f64) -> f64 {
    let z = (y0 - loc) / scale
    var f = 0.0f64
    if math.abs[f64](shape) < 1.0e-12f64 {
        f = math.exp[f64](0.0f64 - z - math.exp[f64](0.0f64 - z)) / scale
    } else {
        let t0 = 1.0f64 + shape * z
        if t0 > 0.0f64 {
            let t = math.pow[f64](t0, 0.0f64 - 1.0f64 / shape)
            f = math.pow[f64](t, shape + 1.0f64) * math.exp[f64](0.0f64 - t) / scale
        }
    }
    ret 0.0f64 - math.log[f64](f)
}

fn logs_gpd(y0: f64, shape: f64, loc: f64, scale: f64) -> f64 {
    let z = (y0 - loc) / scale
    var lf = 0.0f64
    if math.abs[f64](shape) < 1.0e-12f64 {
        lf = 0.0f64 - z - math.log[f64](scale)
    } else {
        lf = (0.0f64 - 1.0f64 / shape - 1.0f64) * math.log[f64](1.0f64 + shape * z) - math.log[f64](scale)
    }
    ret 0.0f64 - lf
}

fn logs_llapl(y: f64, ll: f64, sl: f64) -> f64 {
    let z = (math.log[f64](y) - ll) / sl
    ret 0.0f64 - math.log[f64](math.exp[f64](0.0f64 - math.abs[f64](z)) / (2.0f64 * sl * y))
}

fn logs_llogis(y: f64, ll: f64, sl: f64) -> f64 {
    let z = (math.log[f64](y) - ll) / sl
    let e = math.exp[f64](0.0f64 - z)
    ret 0.0f64 - math.log[f64](e / (sl * (1.0f64 + e) * (1.0f64 + e) * y))
}

fn logs_2pexp(y0: f64, s1: f64, s2: f64, loc: f64) -> f64 {
    let z = y0 - loc
    var f = 0.0f64
    if z < 0.0f64 { f = math.exp[f64](z / s1) / (s1 + s2) } else { f = math.exp[f64](0.0f64 - z / s2) / (s1 + s2) }
    ret 0.0f64 - math.log[f64](f)
}

fn logs_2pnorm(y0: f64, s1: f64, s2: f64, loc: f64) -> f64 {
    let z = y0 - loc
    var f = 0.0f64
    if z < 0.0f64 { f = 2.0f64 / (s1 + s2) * dist.dnorm(z / s1, 0.0f64, 1.0f64, false) } else { f = 2.0f64 / (s1 + s2) * dist.dnorm(z / s2, 0.0f64, 1.0f64, false) }
    ret 0.0f64 - math.log[f64](f)
}

fn logs_tnorm(y: f64, loc: f64, scale: f64, lower: f64, upper: f64) -> f64 {
    let p = pn((upper - loc) / scale) - pn((lower - loc) / scale)
    ret 0.0f64 - (dist.dnorm((y - loc) / scale, 0.0f64, 1.0f64, true) - math.log[f64](scale) - math.log[f64](p))
}

fn logs_mixnorm(y: f64, m: []const f64, s: []const f64, w: []const f64) -> f64 {
    var tw = 0.0f64
    var i = 0usize
    while i < m.len {
        tw += w[i]
        i += 1usize
    }
    var d = 0.0f64
    i = 0usize
    while i < m.len {
        d += w[i] / tw * dist.dnorm((y - m[i]) / s[i], 0.0f64, 1.0f64, false) / s[i]
        i += 1usize
    }
    ret 0.0f64 - math.log[f64](d)
}

fn dss_mixnorm(y: f64, m: []const f64, s: []const f64, w: []const f64) -> f64 {
    var tw = 0.0f64
    var i = 0usize
    while i < m.len {
        tw += w[i]
        i += 1usize
    }
    var mean = 0.0f64
    var m2 = 0.0f64
    i = 0usize
    while i < m.len {
        mean += w[i] / tw * m[i]
        m2 += w[i] / tw * (s[i] * s[i] + m[i] * m[i])
        i += 1usize
    }
    ret dss_moments(y, mean, m2 - mean * mean)
}
