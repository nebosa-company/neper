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
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn infinity() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

fn negative_infinity() -> f64 { ret 0.0f64 - infinity() }

// The term count a series/continued fraction needs grows like sqrt(parameter); a fixed
// 1000 silently truncates for large degrees of freedom.
fn iteration_cap(parameter: f64) -> usize {
    var cap = 1000usize
    if parameter > 0.0f64 {
        let wanted = 10.0f64 + 12.0f64 * math.sqrt[f64](parameter)
        if wanted > 1000.0f64 && wanted < 1000000000.0f64 { cap = usize(wanted) }
    }
    ret cap
}

// ln |Γ(x)|, as R's lgamma: infinite at zero and the negative integers, NaN at -Infinity.
fn lgamma(x: f64) -> f64 {
    if x != x { ret x }
    if x == negative_infinity() { ret nan() }
    if x <= 0.0f64 && x == math.floor[f64](x) { ret infinity() }
    if x == infinity() { ret infinity() }
    if x < 0.5f64 {
        // Reflection: Γ(x) Γ(1 - x) = π / sin(π x).
        let pi = 3.141592653589793f64
        var s = math.sin[f64](pi * x)
        if s < 0.0f64 { s = 0.0f64 - s }
        ret math.log[f64](pi / s) - lgamma(1.0f64 - x)
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

// Γ(x), as R's gammafn: NaN at zero and the negative integers, the reflection formula for
// negative x; overflows to infinity past about 171.6.
fn gamma(x: f64) -> f64 {
    if x != x { ret x }
    if x == negative_infinity() { ret nan() }
    if x <= 0.0f64 && x == math.floor[f64](x) { ret nan() }
    if x == infinity() { ret infinity() }
    if x < 0.0f64 {
        let pi = 3.141592653589793f64
        ret pi / (math.sin[f64](pi * x) * gamma(1.0f64 - x))
    }
    ret math.exp[f64](lgamma(x))
}

// The error function, by the erfc continued fraction for |x| >= 2 and the
// Taylor series below (Abramowitz & Stegun 7.1.5 / 7.1.14).
fn erf(x: f64) -> f64 {
    if x == infinity() { ret 1.0f64 }
    if x == negative_infinity() { ret 0.0f64 - 1.0f64 }
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
    if x == infinity() { ret 0.0f64 }
    if x == negative_infinity() { ret 2.0f64 }
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
    if a == infinity() {
        if x == infinity() { ret nan() }
        ret 0.0f64
    }
    if x == infinity() { ret 1.0f64 }
    if x == 0.0f64 { ret 0.0f64 }
    if x < a + 1.0f64 {
        // Series.
        var ap = a
        var sum = 1.0f64 / a
        var del = sum
        var i = 0usize
        while i < iteration_cap(a) {
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
    if a == infinity() {
        if x == infinity() { ret nan() }
        ret 1.0f64
    }
    if x == infinity() { ret 0.0f64 }
    if x < a + 1.0f64 { ret 1.0f64 - gamma_p(a, x) }
    // Lentz's continued fraction.
    var b = x + 1.0f64 - a
    var c = 1.0e300f64
    var d = 1.0f64 / b
    var h = d
    var i = 1.0f64
    var n = 0usize
    while n < iteration_cap(a) {
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
    while n < iteration_cap(a + b) {
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

// The standard normal quantile, Wichura's AS 241 as R's qnorm computes it (lower tail,
// not on the log scale): -Infinity at 0, Infinity at 1, NaN outside [0, 1]. R's asymptotic
// series for r > 27 (p below 2.5e-317) is not ported; the r <= 27 polynomial stands in.
fn normal_quantile(p: f64) -> f64 {
    if p != p { ret p }
    if p < 0.0f64 || p > 1.0f64 { ret nan() }
    if p == 0.0f64 { ret negative_infinity() }
    if p == 1.0f64 { ret infinity() }
    let q = p - 0.5f64
    var aq = q
    if aq < 0.0f64 { aq = 0.0f64 - aq }
    var val = 0.0f64
    if aq <= 0.425f64 {
        let r = 0.180625f64 - q * q
        val = q * (((((((r * 2509.0809287301226727f64 + 33430.575583588128105f64) * r + 67265.770927008700853f64) * r + 45921.953931549871457f64) * r + 13731.693765509461125f64) * r + 1971.5909503065514427f64) * r + 133.14166789178437745f64) * r + 3.387132872796366608f64) / (((((((r * 5226.495278852854561f64 + 28729.085735721942674f64) * r + 39307.89580009271061f64) * r + 21213.794301586595867f64) * r + 5394.1960214247511077f64) * r + 687.1870074920579083f64) * r + 42.313330701600911252f64) * r + 1.0f64)
        ret val
    }
    var tail = p
    if q > 0.0f64 { tail = 1.0f64 - p }
    var r = math.sqrt[f64](0.0f64 - math.log[f64](tail))
    if r <= 5.0f64 {
        r = r - 1.6f64
        val = (((((((r * 7.7454501427834140764e-4f64 + 0.0227238449892691845833f64) * r + 0.24178072517745061177f64) * r + 1.27045825245236838258f64) * r + 3.64784832476320460504f64) * r + 5.7694972214606914055f64) * r + 4.6303378461565452959f64) * r + 1.42343711074968357734f64) / (((((((r * 1.05075007164441684324e-9f64 + 5.475938084995344946e-4f64) * r + 0.0151986665636164571966f64) * r + 0.14810397642748007459f64) * r + 0.68976733498510000455f64) * r + 1.6763848301838038494f64) * r + 2.05319162663775882187f64) * r + 1.0f64)
    } else {
        r = r - 5.0f64
        val = (((((((r * 2.01033439929228813265e-7f64 + 2.71155556874348757815e-5f64) * r + 0.0012426609473880784386f64) * r + 0.026532189526576123093f64) * r + 0.29656057182850489123f64) * r + 1.7848265399172913358f64) * r + 5.4637849111641143699f64) * r + 6.6579046435011037772f64) / (((((((r * 2.04426310338993978564e-15f64 + 1.4215117583164458887e-7f64) * r + 1.8463183175100546818e-5f64) * r + 7.868691311456132591e-4f64) * r + 0.0148753612908506148525f64) * r + 0.13692988092273580531f64) * r + 0.59983220655588793769f64) * r + 1.0f64)
    }
    if q < 0.0f64 { val = 0.0f64 - val }
    ret val
}

// Student's t distribution function with `df` degrees of freedom.
fn t_cdf(t: f64, df: f64) -> f64 {
    if df <= 0.0f64 { ret nan() }
    if t == infinity() { ret 1.0f64 }
    if t == negative_infinity() { ret 0.0f64 }
    let x = df / (df + t * t)
    let tail = 0.5f64 * beta_i(df / 2.0f64, 0.5f64, x)
    if t >= 0.0f64 { ret 1.0f64 - tail }
    ret tail
}

// The chi-squared distribution function with `df` degrees of freedom.
fn chi_squared_cdf(x: f64, df: f64) -> f64 {
    if df <= 0.0f64 || x < 0.0f64 { ret nan() }
    if x == infinity() { ret 1.0f64 }
    ret gamma_p(df / 2.0f64, x / 2.0f64)
}

// The F distribution function with `d1` and `d2` degrees of freedom.
fn f_cdf(x: f64, d1: f64, d2: f64) -> f64 {
    if d1 <= 0.0f64 || d2 <= 0.0f64 || x < 0.0f64 { ret nan() }
    if x == infinity() { ret 1.0f64 }
    // d1*x/(d1*x+d2) written as 1/(1+d2/(d1*x)) so a huge finite x does not overflow both
    // the numerator and the denominator into infinity/infinity (NaN).
    var ratio = 0.0f64
    if x > 0.0f64 { ratio = 1.0f64 / (1.0f64 + d2 / (d1 * x)) }
    ret beta_i(d1 / 2.0f64, d2 / 2.0f64, ratio)
}

// The binomial coefficient as a real number, through the log-gamma.
fn choose(n: f64, k: f64) -> f64 {
    if n != n || k != k { ret n + k }
    let k0 = math.round[f64](k)
    var kk = k0
    var whole = n - math.round[f64](n)
    if whole < 0.0f64 { whole = 0.0f64 - whole }
    var scale = n
    if scale < 0.0f64 { scale = 0.0f64 - scale }
    if scale < 1.0f64 { scale = 1.0f64 }
    let is_int = whole <= 1.0e-9f64 * scale
    if kk < 30.0f64 {
        if n - kk < kk && n >= 0.0f64 && is_int { kk = math.round[f64](n - kk) }
        if kk < 0.0f64 { ret 0.0f64 }
        if kk == 0.0f64 { ret 1.0f64 }
        var r = n
        var j = 2.0f64
        while j <= kk {
            r = r * ((n - j + 1.0f64) / j)
            j += 1.0f64
        }
        if is_int { ret math.round[f64](r) }
        ret r
    }
    if n < 0.0f64 {
        let r = choose(0.0f64 - n + kk - 1.0f64, kk)
        if kk != 2.0f64 * math.floor[f64](kk / 2.0f64) { ret 0.0f64 - r }
        ret r
    }
    if is_int {
        let m = math.round[f64](n)
        if m < kk { ret 0.0f64 }
        if m - kk < 30.0f64 { ret choose(m, m - kk) }
        ret math.round[f64](math.exp[f64](lgamma(m + 1.0f64) - lgamma(kk + 1.0f64) - lgamma(m - kk + 1.0f64)))
    }
    ret gamma(n + 1.0f64) / (gamma(kk + 1.0f64) * gamma(n - kk + 1.0f64))
}


