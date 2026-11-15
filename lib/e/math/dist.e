// R's d, p and q functions for the distributions that need no incomplete gamma or beta, ported from
// nmath with `lower_tail` and `log_p`: norm (R's Cody pnorm, dnorm4), unif, exp (by scale), weibull,
// logis, cauchy and lnorm. Parameters are the ones R names (exp takes the scale, 1 / rate).
//
// Not here: the gamma, beta, t, chisq, F, binomial, Poisson, hypergeometric, signrank, wilcox and
// tukey families (they rest on toms708, pgamma and bd0).

use e.math
use e.math.special as special

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn expm1(x: f64) -> f64 {
    let u = math.exp[f64](x)
    if u == 1.0f64 { ret x }
    let um1 = u - 1.0f64
    if um1 == -1.0f64 { ret -1.0f64 }
    if u == inf() { ret u }
    ret um1 * x / math.log[f64](u)
}

fn log1p(x: f64) -> f64 {
    if x == inf() { ret x }
    let u = 1.0f64 + x
    if u == 1.0f64 { ret x }
    ret math.log[f64](u) * x / (u - 1.0f64)
}

// log(1 - exp(x)) for x <= 0.
fn log1_exp(x: f64) -> f64 {
    if x > -0.693147180559945309417232121458f64 { ret math.log[f64](0.0f64 - expm1(x)) }
    ret log1p(0.0f64 - math.exp[f64](x))
}

// log(1 + exp(x))
fn log1pexp(x: f64) -> f64 {
    if x <= 18.0f64 { ret log1p(math.exp[f64](x)) }
    if x > 33.3f64 { ret x }
    ret x + math.exp[f64](0.0f64 - x)
}

// The R_D_ and R_DT_ macros of dpq.h.
fn d0(lg: bool) -> f64 { if lg { ret 0.0f64 - inf() } else { ret 0.0f64 } }

fn d1(lg: bool) -> f64 { if lg { ret 0.0f64 } else { ret 1.0f64 } }

fn dt0(lower: bool, lg: bool) -> f64 { if lower { ret d0(lg) } else { ret d1(lg) } }

fn dt1(lower: bool, lg: bool) -> f64 { if lower { ret d1(lg) } else { ret d0(lg) } }

fn dval(x: f64, lg: bool) -> f64 { if lg { ret math.log[f64](x) } else { ret x } }

fn dclog(p: f64, lg: bool) -> f64 { if lg { ret log1p(0.0f64 - p) } else { ret 0.5f64 - p + 0.5f64 } }

fn dlexp(x: f64, lg: bool) -> f64 { if lg { ret log1_exp(x) } else { ret log1p(0.0f64 - x) } }

fn dlog(p: f64, lg: bool) -> f64 { if lg { ret p } else { ret math.log[f64](p) } }

// R_DT_qIv: the lower-tail probability a (p, lower, log) triple stands for.
fn dt_qiv(p: f64, lower: bool, lg: bool) -> f64 {
    if lg {
        if lower { ret math.exp[f64](p) }
        ret 0.0f64 - expm1(p)
    }
    if lower { ret p }
    ret 0.5f64 - p + 0.5f64
}

// R_DT_Clog: log(1 - p_lower) from the triple.
fn dt_clog(p: f64, lower: bool, lg: bool) -> f64 {
    if lower { ret dlexp(p, lg) }
    ret dlog(p, lg)
}

// R_Q_P01_check: p outside [0, 1] (or > 0 on the log scale) is not a probability.
fn bad_p(p: f64, lg: bool) -> bool {
    if lg { ret p > 0.0f64 }
    ret p < 0.0f64 || p > 1.0f64
}

// --- normal

fn pnorm_both(x: f64, i_tail: i64, lg: bool) -> (f64, f64) {
    let a0 = 2.2352520354606839287f64
    let a1 = 161.02823106855587881f64
    let a2 = 1067.6894854603709582f64
    let a3 = 18154.981253343561249f64
    let a4 = 0.065682337918207449113f64
    let b0 = 47.20258190468824187f64
    let b1 = 976.09855173777669322f64
    let b2 = 10260.932208618978205f64
    let b3 = 45507.789335026729956f64
    let c0 = 0.39894151208813466764f64
    let c1 = 8.8831497943883759412f64
    let c2 = 93.506656132177855979f64
    let c3 = 597.27027639480026226f64
    let c4 = 2494.5375852903726711f64
    let c5 = 6848.1904505362823326f64
    let c6 = 11602.651437647350124f64
    let c7 = 9842.7148383839780218f64
    let c8 = 1.0765576773720192317e-8f64
    let d0v = 22.266688044328115691f64
    let d1v = 235.38790178262499861f64
    let d2v = 1519.377599407554805f64
    let d3v = 6485.558298266760755f64
    let d4v = 18615.571640885098091f64
    let d5v = 34900.952721145977266f64
    let d6v = 38912.003286093271411f64
    let d7v = 19685.429676859990727f64
    let p0 = 0.21589853405795699f64
    let p1 = 0.1274011611602473639f64
    let p2 = 0.022235277870649807f64
    let p3 = 0.001421619193227893466f64
    let p4 = 2.9112874951168792e-5f64
    let p5 = 0.02307344176494017303f64
    let q0 = 1.28426009614491121f64
    let q1 = 0.468238212480865118f64
    let q2 = 0.0659881378689285515f64
    let q3 = 0.00378239633202758244f64
    let q4 = 7.29751555083966205e-5f64
    if x != x { ret (x, x) }
    let eps = 2.220446049250313e-16f64 * 0.5f64
    let lower = i_tail != 1i64
    let upper = i_tail != 0i64
    let y = abs_of(x)
    var cum = 0.0f64
    var ccum = 0.0f64
    if y <= 0.67448975f64 {
        var xnum = 0.0f64
        var xden = 0.0f64
        if y > eps {
            let xsq = x * x
            xnum = a4 * xsq
            xden = xsq
            xnum = (xnum + a0) * xsq
            xden = (xden + b0) * xsq
            xnum = (xnum + a1) * xsq
            xden = (xden + b1) * xsq
            xnum = (xnum + a2) * xsq
            xden = (xden + b2) * xsq
        }
        let temp = x * (xnum + a3) / (xden + b3)
        if lower { cum = 0.5f64 + temp }
        if upper { ccum = 0.5f64 - temp }
        if lg {
            if lower { cum = math.log[f64](cum) }
            if upper { ccum = math.log[f64](ccum) }
        }
        ret (cum, ccum)
    }
    var temp = 0.0f64
    var xsq = 0.0f64
    var big = false
    if y <= 5.656854249492380195206754896838f64 {
        var xnum = c8 * y
        var xden = y
        xnum = (xnum + c0) * y
        xden = (xden + d0v) * y
        xnum = (xnum + c1) * y
        xden = (xden + d1v) * y
        xnum = (xnum + c2) * y
        xden = (xden + d2v) * y
        xnum = (xnum + c3) * y
        xden = (xden + d3v) * y
        xnum = (xnum + c4) * y
        xden = (xden + d4v) * y
        xnum = (xnum + c5) * y
        xden = (xden + d5v) * y
        xnum = (xnum + c6) * y
        xden = (xden + d6v) * y
        temp = (xnum + c7) / (xden + d7v)
    } else if (lg && y < 1.0e170f64) || (lower && -38.4674f64 < x && x < 8.2924f64) || (upper && -8.2924f64 < x && x < 38.4674f64) {
        let xs = 1.0f64 / (x * x)
        var xnum = p5 * xs
        var xden = xs
        xnum = (xnum + p0) * xs
        xden = (xden + q0) * xs
        xnum = (xnum + p1) * xs
        xden = (xden + q1) * xs
        xnum = (xnum + p2) * xs
        xden = (xden + q2) * xs
        xnum = (xnum + p3) * xs
        xden = (xden + q3) * xs
        temp = xs * (xnum + p4) / (xden + q4)
        temp = (0.398942280401432677939946059934f64 - temp) / y
        big = true
    } else {
        if x > 0.0f64 {
            cum = d1(lg)
            ccum = d0(lg)
        } else {
            cum = d0(lg)
            ccum = d1(lg)
        }
        ret (cum, ccum)
    }
    // do_del(X): X is y in the middle range and x in the tail
    var xx = y
    if big { xx = x }
    xsq = math.trunc[f64](xx * 16.0f64) / 16.0f64
    let del = (xx - xsq) * (xx + xsq)
    if lg {
        cum = (0.0f64 - xsq * (xsq / 2.0f64)) - del / 2.0f64 + math.log[f64](temp)
        if (lower && x > 0.0f64) || (upper && x <= 0.0f64) {
            ccum = log1p(0.0f64 - math.exp[f64](0.0f64 - xsq * (xsq / 2.0f64)) * math.exp[f64](0.0f64 - del / 2.0f64) * temp)
        }
    } else {
        cum = math.exp[f64](0.0f64 - xsq * (xsq / 2.0f64)) * math.exp[f64](0.0f64 - del / 2.0f64) * temp
        ccum = 1.0f64 - cum
    }
    if x > 0.0f64 {
        let t = cum
        if lower { cum = ccum }
        ccum = t
    }
    ret (cum, ccum)
}

fn pnorm(x0: f64, mu: f64, sigma: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || mu != mu || sigma != sigma { ret x0 + mu + sigma }
    if !finite(x0) && mu == x0 { ret nan() }
    if sigma <= 0.0f64 {
        if sigma < 0.0f64 { ret nan() }
        if x0 < mu { ret dt0(lower, lg) }
        ret dt1(lower, lg)
    }
    let p = (x0 - mu) / sigma
    if !finite(p) {
        if x0 < mu { ret dt0(lower, lg) }
        ret dt1(lower, lg)
    }
    var tail = 1i64
    if lower { tail = 0i64 }
    let (cum, ccum) = pnorm_both(p, tail, lg)
    if lower { ret cum }
    ret ccum
}

fn dnorm(x0: f64, mu: f64, sigma: f64, lg: bool) -> f64 {
    if x0 != x0 || mu != mu || sigma != sigma { ret x0 + mu + sigma }
    if sigma < 0.0f64 { ret nan() }
    if !finite(sigma) { ret d0(lg) }
    if !finite(x0) && mu == x0 { ret nan() }
    if sigma == 0.0f64 {
        if x0 == mu { ret inf() }
        ret d0(lg)
    }
    var x = (x0 - mu) / sigma
    if !finite(x) { ret d0(lg) }
    x = abs_of(x)
    if x >= 2.0f64 * math.sqrt[f64](1.7976931348623157e308f64) { ret d0(lg) }
    if lg { ret 0.0f64 - (0.918938533204672741780329736406f64 + 0.5f64 * x * x + math.log[f64](sigma)) }
    if x < 5.0f64 { ret 0.398942280401432677939946059934f64 * math.exp[f64](-0.5f64 * x * x) / sigma }
    if x > 38.56804624911f64 { ret 0.0f64 }
    let x1 = math.round[f64](x * 65536.0f64) / 65536.0f64
    let x2 = x - x1
    ret 0.398942280401432677939946059934f64 / sigma * (math.exp[f64](-0.5f64 * x1 * x1) * math.exp[f64]((0.0f64 - 0.5f64 * x2 - x1) * x2))
}

fn qnorm(p: f64, mu: f64, sigma: f64, lower: bool, lg: bool) -> f64 {
    if p != p || mu != mu || sigma != sigma { ret p + mu + sigma }
    // R_Q_P01_boundaries(p, -Inf, Inf)
    if lg {
        if p > 0.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret inf() }
            ret 0.0f64 - inf()
        }
        if p == 0.0f64 - inf() {
            if lower { ret 0.0f64 - inf() }
            ret inf()
        }
    } else {
        if p < 0.0f64 || p > 1.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret 0.0f64 - inf() }
            ret inf()
        }
        if p == 1.0f64 {
            if lower { ret inf() }
            ret 0.0f64 - inf()
        }
    }
    if sigma < 0.0f64 { ret nan() }
    if sigma == 0.0f64 { ret mu }
    let p_ = dt_qiv(p, lower, lg)
    let q = p_ - 0.5f64
    var val = 0.0f64
    if abs_of(q) <= 0.425f64 {
        let r = 0.180625f64 - q * q
        val = q * (((((((r * 2509.0809287301226727f64 + 33430.575583588128105f64) * r + 67265.770927008700853f64) * r + 45921.953931549871457f64) * r + 13731.693765509461125f64) * r + 1971.5909503065514427f64) * r + 133.14166789178437745f64) * r + 3.387132872796366608f64) / (((((((r * 5226.495278852854561f64 + 28729.085735721942674f64) * r + 39307.89580009271061f64) * r + 21213.794301586595867f64) * r + 5394.1960214247511077f64) * r + 687.1870074920579083f64) * r + 42.313330701600911252f64) * r + 1.0f64)
        ret mu + sigma * val
    }
    var lp = 0.0f64
    if lg && ((lower && q <= 0.0f64) || (!lower && q > 0.0f64)) {
        lp = p
    } else {
        var civ = p
        if q > 0.0f64 {
            // R_DT_CIv(p), the upper-tail probability
            if lg {
                if lower { civ = 0.0f64 - expm1(p) } else { civ = math.exp[f64](p) }
            } else {
                if lower { civ = 0.5f64 - p + 0.5f64 } else { civ = p }
            }
            lp = math.log[f64](civ)
        } else {
            lp = math.log[f64](p_)
        }
    }
    var r = math.sqrt[f64](0.0f64 - lp)
    if r <= 5.0f64 {
        r = r - 1.6f64
        val = (((((((r * 7.7454501427834140764e-4f64 + 0.0227238449892691845833f64) * r + 0.24178072517745061177f64) * r + 1.27045825245236838258f64) * r + 3.64784832476320460504f64) * r + 5.7694972214606914055f64) * r + 4.6303378461565452959f64) * r + 1.42343711074968357734f64) / (((((((r * 1.05075007164441684324e-9f64 + 5.475938084995344946e-4f64) * r + 0.0151986665636164571966f64) * r + 0.14810397642748007459f64) * r + 0.68976733498510000455f64) * r + 1.6763848301838038494f64) * r + 2.05319162663775882187f64) * r + 1.0f64)
    } else if r <= 27.0f64 {
        r = r - 5.0f64
        val = (((((((r * 2.01033439929228813265e-7f64 + 2.71155556874348757815e-5f64) * r + 0.0012426609473880784386f64) * r + 0.026532189526576123093f64) * r + 0.29656057182850489123f64) * r + 1.7848265399172913358f64) * r + 5.4637849111641143699f64) * r + 6.6579046435011037772f64) / (((((((r * 2.04426310338993978564e-15f64 + 1.4215117583164458887e-7f64) * r + 1.8463183175100546818e-5f64) * r + 7.868691311456132591e-4f64) * r + 0.0148753612908506148525f64) * r + 0.13692988092273580531f64) * r + 0.59983220655588793769f64) * r + 1.0f64)
    } else if r >= 6.4e8f64 {
        val = r * 1.41421356237309504880168872421f64
    } else {
        let s2 = 0.0f64 - 2.0f64 * lp
        let m2pi = 6.283185307179586476925286766559f64
        var x2 = s2 - math.log[f64](m2pi * s2)
        if r < 36000.0f64 {
            x2 = s2 - math.log[f64](m2pi * x2) - 2.0f64 / (2.0f64 + x2)
            if r < 840.0f64 {
                x2 = s2 - math.log[f64](m2pi * x2) + 2.0f64 * log1p(0.0f64 - (1.0f64 - 1.0f64 / (4.0f64 + x2)) / (2.0f64 + x2))
                if r < 109.0f64 {
                    x2 = s2 - math.log[f64](m2pi * x2) + 2.0f64 * log1p(0.0f64 - (1.0f64 - (1.0f64 - 5.0f64 / (6.0f64 + x2)) / (4.0f64 + x2)) / (2.0f64 + x2))
                    if r < 55.0f64 {
                        x2 = s2 - math.log[f64](m2pi * x2) + 2.0f64 * log1p(0.0f64 - (1.0f64 - (1.0f64 - (5.0f64 - 9.0f64 / (8.0f64 + x2)) / (6.0f64 + x2)) / (4.0f64 + x2)) / (2.0f64 + x2))
                    }
                }
            }
        }
        val = math.sqrt[f64](x2)
    }
    if q < 0.0f64 { val = 0.0f64 - val }
    ret mu + sigma * val
}

// --- uniform

fn dunif(x: f64, a: f64, b: f64, lg: bool) -> f64 {
    if x != x || a != a || b != b { ret x + a + b }
    if b <= a { ret nan() }
    if a <= x && x <= b {
        if lg { ret 0.0f64 - math.log[f64](b - a) }
        ret 1.0f64 / (b - a)
    }
    ret d0(lg)
}

fn punif(x: f64, a: f64, b: f64, lower: bool, lg: bool) -> f64 {
    if x != x || a != a || b != b { ret x + a + b }
    if b < a { ret nan() }
    if !finite(a) || !finite(b) { ret nan() }
    if x >= b { ret dt1(lower, lg) }
    if x <= a { ret dt0(lower, lg) }
    if lower { ret dval((x - a) / (b - a), lg) }
    ret dval((b - x) / (b - a), lg)
}

fn qunif(p: f64, a: f64, b: f64, lower: bool, lg: bool) -> f64 {
    if p != p || a != a || b != b { ret p + a + b }
    if bad_p(p, lg) { ret nan() }
    if !finite(a) || !finite(b) { ret nan() }
    if b < a { ret nan() }
    if b == a { ret a }
    ret a + dt_qiv(p, lower, lg) * (b - a)
}

// --- exponential (scale = 1 / rate)

fn dexp(x: f64, scale: f64, lg: bool) -> f64 {
    if x != x || scale != scale { ret x + scale }
    if scale <= 0.0f64 { ret nan() }
    if x < 0.0f64 { ret d0(lg) }
    if lg { ret (0.0f64 - x / scale) - math.log[f64](scale) }
    ret math.exp[f64](0.0f64 - x / scale) / scale
}

fn pexp(x0: f64, scale: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || scale != scale { ret x0 + scale }
    if scale < 0.0f64 { ret nan() }
    if x0 <= 0.0f64 { ret dt0(lower, lg) }
    let x = 0.0f64 - x0 / scale
    if lower {
        if lg { ret log1_exp(x) }
        ret 0.0f64 - expm1(x)
    }
    if lg { ret x }
    ret math.exp[f64](x)
}

fn qexp(p: f64, scale: f64, lower: bool, lg: bool) -> f64 {
    if p != p || scale != scale { ret p + scale }
    if scale < 0.0f64 { ret nan() }
    if bad_p(p, lg) { ret nan() }
    if p == dt0(lower, lg) { ret 0.0f64 }
    ret 0.0f64 - scale * dt_clog(p, lower, lg)
}

// --- Weibull

fn dweibull(x: f64, shape: f64, scale: f64, lg: bool) -> f64 {
    if x != x || shape != shape || scale != scale { ret x + shape + scale }
    if shape <= 0.0f64 || scale <= 0.0f64 { ret nan() }
    if x < 0.0f64 { ret d0(lg) }
    if !finite(x) { ret d0(lg) }
    if x == 0.0f64 && shape < 1.0f64 { ret inf() }
    let tmp1 = math.pow[f64](x / scale, shape - 1.0f64)
    let tmp2 = tmp1 * (x / scale)
    if lg { ret 0.0f64 - tmp2 + math.log[f64](shape * tmp1 / scale) }
    ret shape * tmp1 * math.exp[f64](0.0f64 - tmp2) / scale
}

fn pweibull(x0: f64, shape: f64, scale: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || shape != shape || scale != scale { ret x0 + shape + scale }
    if shape <= 0.0f64 || scale <= 0.0f64 { ret nan() }
    if x0 <= 0.0f64 { ret dt0(lower, lg) }
    let x = 0.0f64 - math.pow[f64](x0 / scale, shape)
    if lower {
        if lg { ret log1_exp(x) }
        ret 0.0f64 - expm1(x)
    }
    if lg { ret x }
    ret math.exp[f64](x)
}

fn qweibull(p: f64, shape: f64, scale: f64, lower: bool, lg: bool) -> f64 {
    if p != p || shape != shape || scale != scale { ret p + shape + scale }
    if shape <= 0.0f64 || scale <= 0.0f64 { ret nan() }
    if bad_p(p, lg) { ret nan() }
    if p == dt0(lower, lg) { ret 0.0f64 }
    if p == dt1(lower, lg) { ret inf() }
    ret scale * math.pow[f64](0.0f64 - dt_clog(p, lower, lg), 1.0f64 / shape)
}

// --- logistic

fn dlogis(x0: f64, location: f64, scale: f64, lg: bool) -> f64 {
    if x0 != x0 || location != location || scale != scale { ret x0 + location + scale }
    if scale <= 0.0f64 { ret nan() }
    let x = abs_of((x0 - location) / scale)
    let e = math.exp[f64](0.0f64 - x)
    let f = 1.0f64 + e
    if lg { ret 0.0f64 - (x + math.log[f64](scale * f * f)) }
    ret e / (scale * f * f)
}

fn plogis(x0: f64, location: f64, scale: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || location != location || scale != scale { ret x0 + location + scale }
    if scale <= 0.0f64 { ret nan() }
    var x = (x0 - location) / scale
    if x != x { ret nan() }
    if !finite(x) {
        if x < 0.0f64 { ret dt0(lower, lg) }
        ret dt1(lower, lg)
    }
    if lg {
        if lower { ret 0.0f64 - log1pexp(0.0f64 - x) }
        ret 0.0f64 - log1pexp(x)
    }
    if lower { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) }
    ret 1.0f64 / (1.0f64 + math.exp[f64](x))
}

fn qlogis(p0: f64, location: f64, scale: f64, lower: bool, lg: bool) -> f64 {
    if p0 != p0 || location != location || scale != scale { ret p0 + location + scale }
    if bad_p(p0, lg) { ret nan() }
    if p0 == dt0(lower, lg) { ret 0.0f64 - inf() }
    if p0 == dt1(lower, lg) { ret inf() }
    if scale < 0.0f64 { ret nan() }
    if scale == 0.0f64 { ret location }
    var p = p0
    if lg {
        if lower { p = p - log1_exp(p) } else { p = log1_exp(p) - p }
    } else {
        if lower { p = math.log[f64](p / (1.0f64 - p)) } else { p = math.log[f64]((1.0f64 - p) / p) }
    }
    ret location + scale * p
}

// --- Cauchy

fn dcauchy(x: f64, location: f64, scale: f64, lg: bool) -> f64 {
    if x != x || location != location || scale != scale { ret x + location + scale }
    if scale <= 0.0f64 { ret nan() }
    let y = (x - location) / scale
    if lg { ret 0.0f64 - math.log[f64](3.141592653589793238462643383280f64 * scale * (1.0f64 + y * y)) }
    ret 1.0f64 / (3.141592653589793238462643383280f64 * scale * (1.0f64 + y * y))
}

fn pcauchy(x0: f64, location: f64, scale: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || location != location || scale != scale { ret x0 + location + scale }
    if scale <= 0.0f64 { ret nan() }
    var x = (x0 - location) / scale
    if x != x { ret nan() }
    if !finite(x) {
        if x < 0.0f64 { ret dt0(lower, lg) }
        ret dt1(lower, lg)
    }
    if !lower { x = 0.0f64 - x }
    if abs_of(x) > 1.0f64 {
        let y = math.atan[f64](1.0f64 / x) / 3.141592653589793238462643383280f64
        if x > 0.0f64 { ret dclog(y, lg) }
        ret dval(0.0f64 - y, lg)
    }
    ret dval(0.5f64 + math.atan[f64](x) / 3.141592653589793238462643383280f64, lg)
}

fn qcauchy(p0: f64, location: f64, scale: f64, lower0: bool, lg: bool) -> f64 {
    if p0 != p0 || location != location || scale != scale { ret p0 + location + scale }
    if bad_p(p0, lg) { ret nan() }
    if scale <= 0.0f64 || !finite(scale) {
        if scale == 0.0f64 { ret location }
        ret nan()
    }
    var p = p0
    var lower = lower0
    if lg {
        if p > -1.0f64 {
            if p == 0.0f64 {
                var sgn = 1.0f64
                if lower { sgn = 1.0f64 } else { sgn = -1.0f64 }
                ret location + sgn * scale * inf()
            }
            lower = !lower
            p = 0.0f64 - expm1(p)
        } else {
            p = math.exp[f64](p)
        }
    } else {
        if p > 0.5f64 {
            if p == 1.0f64 {
                var sgn = 1.0f64
                if lower { sgn = 1.0f64 } else { sgn = -1.0f64 }
                ret location + sgn * scale * inf()
            }
            p = 1.0f64 - p
            lower = !lower
        }
    }
    if p == 0.5f64 { ret location }
    if p == 0.0f64 {
        var sgn = -1.0f64
        if lower { sgn = -1.0f64 } else { sgn = 1.0f64 }
        ret location + sgn * scale * inf()
    }
    var sg = 1.0f64
    if lower { sg = -1.0f64 }
    ret location + sg * scale / math.tan[f64](3.141592653589793238462643383280f64 * p)
}

// --- log-normal

fn dlnorm(x: f64, meanlog: f64, sdlog: f64, lg: bool) -> f64 {
    if x != x || meanlog != meanlog || sdlog != sdlog { ret x + meanlog + sdlog }
    if sdlog < 0.0f64 { ret nan() }
    if !finite(x) && math.log[f64](x) == meanlog { ret nan() }
    if sdlog == 0.0f64 {
        if math.log[f64](x) == meanlog { ret inf() }
        ret d0(lg)
    }
    if x <= 0.0f64 { ret d0(lg) }
    let y = (math.log[f64](x) - meanlog) / sdlog
    if lg { ret 0.0f64 - (0.918938533204672741780329736406f64 + 0.5f64 * y * y + math.log[f64](x * sdlog)) }
    ret 0.398942280401432677939946059934f64 * math.exp[f64](-0.5f64 * y * y) / (x * sdlog)
}

fn plnorm(x: f64, meanlog: f64, sdlog: f64, lower: bool, lg: bool) -> f64 {
    if x != x || meanlog != meanlog || sdlog != sdlog { ret x + meanlog + sdlog }
    if sdlog < 0.0f64 { ret nan() }
    if x > 0.0f64 { ret pnorm(math.log[f64](x), meanlog, sdlog, lower, lg) }
    ret dt0(lower, lg)
}

fn qlnorm(p: f64, meanlog: f64, sdlog: f64, lower: bool, lg: bool) -> f64 {
    if p != p || meanlog != meanlog || sdlog != sdlog { ret p + meanlog + sdlog }
    if bad_p(p, lg) { ret nan() }
    if p == dt0(lower, lg) { ret 0.0f64 }
    if p == dt1(lower, lg) { ret inf() }
    ret math.exp[f64](qnorm(p, meanlog, sdlog, lower, lg))
}
