// Special functions over `f64`: the gamma function and its logarithm, the error
// function, the regularised incomplete gamma and beta functions, and the
// distribution functions built from them (normal, Student's t, chi-squared, F)
// with the normal quantile.
//
// `lgamma` is the Lanczos approximation (g = 7, nine coefficients), good to
// about fifteen digits for positive arguments; the incomplete functions use the
// series and continued-fraction forms from Numerical Recipes, iterated to
// double precision. Arguments outside each function's domain answer NaN.

use e.math

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// ln Γ(x) for x > 0.
fn lgamma(x: f64) -> f64 {
    if x <= 0.0f64 { ret nan() }
    if x < 0.5f64 {
        // Reflection: Γ(x) Γ(1 - x) = π / sin(π x).
        let pi = 3.141592653589793f64
        ret math.log[f64](pi / math.sin[f64](pi * x)) - lgamma(1.0f64 - x)
    }
    let z = x - 1.0f64
    var sum = 0.99999999999980993f64
    sum += 676.5203681218851f64 / (z + 1.0f64)
    sum += 0.0f64 - 1259.1392167224028f64 / (z + 2.0f64)
    sum += 771.32342877765313f64 / (z + 3.0f64)
    sum += 0.0f64 - 176.61502916214059f64 / (z + 4.0f64)
    sum += 12.507343278686905f64 / (z + 5.0f64)
    sum += 0.0f64 - 0.13857109526572012f64 / (z + 6.0f64)
    sum += 0.0000099843695780195716f64 / (z + 7.0f64)
    sum += 0.00000015056327351493116f64 / (z + 8.0f64)
    let t = z + 7.5f64
    ret 0.91893853320467274f64 + (z + 0.5f64) * math.log[f64](t) - t + math.log[f64](sum)
}

// Γ(x) for x > 0; overflows to infinity past about 171.6.
fn gamma(x: f64) -> f64 {
    if x <= 0.0f64 { ret nan() }
    ret math.exp[f64](lgamma(x))
}

// The error function, by the erfc continued fraction for |x| >= 2 and the
// Taylor series below (Abramowitz & Stegun 7.1.5 / 7.1.14).
fn erf(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - erf(0.0f64 - x) }
    if x < 2.5f64 {
        var term = x
        var sum = x
        var n = 0.0f64
        var i = 0usize
        while i < 200usize {
            n += 1.0f64
            term = term * (0.0f64 - x * x) / n
            let add = term / (2.0f64 * n + 1.0f64)
            sum += add
            if math.abs[f64](add) < 1.0e-17f64 * math.abs[f64](sum) { break }
            i += 1usize
        }
        ret 1.1283791670955126f64 * sum
    }
    ret 1.0f64 - erfc(x)
}

// The complementary error function, accurate in the tail.
fn erfc(x: f64) -> f64 {
    if x < 2.5f64 { ret 1.0f64 - erf(x) }
    // Lentz's continued fraction: erfc(x) = exp(-x^2)/sqrt(pi) * 1/(x + 1/2/(x + 1/(x + 3/2/(x + ...)))).
    var f = x
    var c = x
    var d = 0.0f64
    var n = 1.0f64
    var i = 0usize
    while i < 300usize {
        let a = n / 2.0f64
        d = x + a * d
        if d == 0.0f64 { d = 1.0e-300f64 }
        d = 1.0f64 / d
        c = x + a / c
        if c == 0.0f64 { c = 1.0e-300f64 }
        let delta = c * d
        f = f * delta
        if math.abs[f64](delta - 1.0f64) < 1.0e-16f64 { break }
        n += 1.0f64
        i += 1usize
    }
    ret math.exp[f64](0.0f64 - x * x) / (1.7724538509055159f64 * f)
}

// The regularised lower incomplete gamma P(a, x), a > 0, x >= 0.
fn gamma_p(a: f64, x: f64) -> f64 {
    if a <= 0.0f64 || x < 0.0f64 { ret nan() }
    if x == 0.0f64 { ret 0.0f64 }
    if x < a + 1.0f64 {
        // Series.
        var ap = a
        var sum = 1.0f64 / a
        var del = sum
        var i = 0usize
        while i < 1000usize {
            ap += 1.0f64
            del = del * x / ap
            sum += del
            if math.abs[f64](del) < math.abs[f64](sum) * 1.0e-16f64 { break }
            i += 1usize
        }
        ret sum * math.exp[f64](0.0f64 - x + a * math.log[f64](x) - lgamma(a))
    }
    ret 1.0f64 - gamma_q(a, x)
}

// The regularised upper incomplete gamma Q(a, x) = 1 - P(a, x).
fn gamma_q(a: f64, x: f64) -> f64 {
    if a <= 0.0f64 || x < 0.0f64 { ret nan() }
    if x < a + 1.0f64 { ret 1.0f64 - gamma_p(a, x) }
    // Lentz's continued fraction.
    var b = x + 1.0f64 - a
    var c = 1.0e300f64
    var d = 1.0f64 / b
    var h = d
    var i = 1.0f64
    var n = 0usize
    while n < 1000usize {
        let an = 0.0f64 - i * (i - a)
        b += 2.0f64
        d = an * d + b
        if math.abs[f64](d) < 1.0e-300f64 { d = 1.0e-300f64 }
        c = b + an / c
        if math.abs[f64](c) < 1.0e-300f64 { c = 1.0e-300f64 }
        d = 1.0f64 / d
        let del = d * c
        h = h * del
        if math.abs[f64](del - 1.0f64) < 1.0e-16f64 { break }
        i += 1.0f64
        n += 1usize
    }
    ret math.exp[f64](0.0f64 - x + a * math.log[f64](x) - lgamma(a)) * h
}

// The regularised incomplete beta I_x(a, b) for 0 <= x <= 1, a, b > 0.
fn beta_i(a: f64, b: f64, x: f64) -> f64 {
    if a <= 0.0f64 || b <= 0.0f64 || x < 0.0f64 || x > 1.0f64 { ret nan() }
    if x == 0.0f64 { ret 0.0f64 }
    if x == 1.0f64 { ret 1.0f64 }
    let front = math.exp[f64](lgamma(a + b) - lgamma(a) - lgamma(b) + a * math.log[f64](x) + b * math.log[f64](1.0f64 - x))
    if x < (a + 1.0f64) / (a + b + 2.0f64) { ret front * beta_fraction(a, b, x) / a }
    ret 1.0f64 - front * beta_fraction(b, a, 1.0f64 - x) / b
}

// The continued fraction of the incomplete beta by Lentz's method.
fn beta_fraction(a: f64, b: f64, x: f64) -> f64 {
    let qab = a + b
    let qap = a + 1.0f64
    let qam = a - 1.0f64
    var c = 1.0f64
    var d = 1.0f64 - qab * x / qap
    if math.abs[f64](d) < 1.0e-300f64 { d = 1.0e-300f64 }
    d = 1.0f64 / d
    var h = d
    var m = 1.0f64
    var n = 0usize
    while n < 1000usize {
        let m2 = 2.0f64 * m
        var aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0f64 + aa * d
        if math.abs[f64](d) < 1.0e-300f64 { d = 1.0e-300f64 }
        c = 1.0f64 + aa / c
        if math.abs[f64](c) < 1.0e-300f64 { c = 1.0e-300f64 }
        d = 1.0f64 / d
        h = h * d * c
        aa = 0.0f64 - (a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0f64 + aa * d
        if math.abs[f64](d) < 1.0e-300f64 { d = 1.0e-300f64 }
        c = 1.0f64 + aa / c
        if math.abs[f64](c) < 1.0e-300f64 { c = 1.0e-300f64 }
        d = 1.0f64 / d
        let del = d * c
        h = h * del
        if math.abs[f64](del - 1.0f64) < 1.0e-16f64 { break }
        m += 1.0f64
        n += 1usize
    }
    ret h
}

// The standard normal distribution function.
fn normal_cdf(z: f64) -> f64 { ret 0.5f64 * erfc(0.0f64 - z / 1.4142135623730951f64) }

// The standard normal quantile (Acklam's rational approximation refined by one
// Newton step), for 0 < p < 1.
fn normal_quantile(p: f64) -> f64 {
    if p <= 0.0f64 || p >= 1.0f64 { ret nan() }
    var x = 0.0f64
    if p < 0.02425f64 || p > 0.97575f64 {
        var q = p
        if p > 0.5f64 { q = 1.0f64 - p }
        let t = math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](q))
        x = (((((0.0f64 - 0.007784894002430293f64 * t - 0.3223964580411365f64) * t - 2.400758277161838f64) * t - 2.549732539343734f64) * t + 4.374664141464968f64) * t + 2.938163982698783f64) / ((((0.007784695709041462f64 * t + 0.3224671290700398f64) * t + 2.445134137142996f64) * t + 3.754408661907416f64) * t + 1.0f64)
        if p > 0.5f64 { x = 0.0f64 - x }
    } else {
        let q = p - 0.5f64
        let r = q * q
        x = (((((0.0f64 - 39.69683028665376f64 * r + 220.9460984245205f64) * r - 275.9285104469687f64) * r + 138.3577518672690f64) * r - 30.66479806614716f64) * r + 2.506628277459239f64) * q / (((((0.0f64 - 54.47609879822406f64 * r + 161.5858368580409f64) * r - 155.6989798598866f64) * r + 66.80131188771972f64) * r - 13.28068155288572f64) * r + 1.0f64)
    }
    // One Newton step on the CDF.
    let e = normal_cdf(x) - p
    let density = 0.3989422804014327f64 * math.exp[f64](0.0f64 - x * x / 2.0f64)
    ret x - e / density
}

// Student's t distribution function with `df` degrees of freedom.
fn t_cdf(t: f64, df: f64) -> f64 {
    if df <= 0.0f64 { ret nan() }
    let x = df / (df + t * t)
    let tail = 0.5f64 * beta_i(df / 2.0f64, 0.5f64, x)
    if t >= 0.0f64 { ret 1.0f64 - tail }
    ret tail
}

// The chi-squared distribution function with `df` degrees of freedom.
fn chi_squared_cdf(x: f64, df: f64) -> f64 {
    if df <= 0.0f64 || x < 0.0f64 { ret nan() }
    ret gamma_p(df / 2.0f64, x / 2.0f64)
}

// The F distribution function with `d1` and `d2` degrees of freedom.
fn f_cdf(x: f64, d1: f64, d2: f64) -> f64 {
    if d1 <= 0.0f64 || d2 <= 0.0f64 || x < 0.0f64 { ret nan() }
    ret beta_i(d1 / 2.0f64, d2 / 2.0f64, d1 * x / (d1 * x + d2))
}

// The binomial coefficient as a real number, through the log-gamma.
fn choose(n: f64, k: f64) -> f64 {
    if k < 0.0f64 || k > n { ret 0.0f64 }
    ret math.floor[f64](0.5f64 + math.exp[f64](lgamma(n + 1.0f64) - lgamma(k + 1.0f64) - lgamma(n - k + 1.0f64)))
}
