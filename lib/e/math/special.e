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

// (ah, al) / d for a single double divisor: the quotient is corrected by its own product residual.
fn dd_div_d(ah: f64, al: f64, d: f64) -> (f64, f64) {
    let q = ah / d
    let (p, e) = math.two_prod(q, d)
    let (h, l) = math.two_sum(q, ((ah - p) - e + al) / d)
    ret (h, l)
}

// (ah, al) / (bh, bl): one Newton step on the high quotient, the residual taken with two_prod (D7785).
fn dd_div(ah: f64, al: f64, bh: f64, bl: f64) -> (f64, f64) {
    let q1 = ah / bh
    let (p, e) = math.two_prod(q1, bh)
    let r = ((ah - p) - e) + (al - q1 * bl)
    let (h, l) = math.two_sum(q1, r / bh)
    ret (h, l)
}

// erf(x) as a double-double pair by its Taylor series; only used below 1, where the terms stay small.
fn erf_pair(x: f64) -> (f64, f64) {
    let (x2h, x2l) = math.two_prod(x, x)
    var th = x
    var tl = 0.0f64
    var sh = x
    var sl = 0.0f64
    var k = 0usize
    while k < 200usize {
        let (mh, ml) = math.dd_mul(th, tl, 0.0f64 - x2h, 0.0f64 - x2l)
        let num = 2.0f64 * f64(k) + 1.0f64
        let den = (f64(k) + 1.0f64) * (2.0f64 * f64(k) + 3.0f64)
        let (m2h, m2l) = math.dd_mul(mh, ml, num, 0.0f64)
        let (t2h, t2l) = dd_div_d(m2h, m2l, den)
        th = t2h
        tl = t2l
        let (nh, nl) = math.dd_add(sh, sl, th, tl)
        sh = nh
        sl = nl
        if math.abs[f64](th) < 1.0e-30f64 { break }
        k += 1usize
    }
    let (eh, el) = math.dd_mul(sh, sl, 1.1283791670955126f64, 0.0f64)
    ret (eh, el)
}

// erfc(x) for x >= 1 by Lentz's continued fraction carried in double-double: erfc is small here, so it must
// be produced directly - 1 - erf would have lost the digits in the subtraction (D7784, D7785).
fn erfc_cf(x: f64) -> f64 {
    var fh = x
    var fl = 0.0f64
    var ch = x
    var cl = 0.0f64
    var dh = 0.0f64
    var dl = 0.0f64
    var n = 1.0f64
    var i = 0usize
    while i < 400usize {
        let ah = n / 2.0f64
        let (pdh, pdl) = math.dd_mul(dh, dl, ah, 0.0f64)
        let (tdh, tdl) = math.dd_add(x, 0.0f64, pdh, pdl)
        let (ndh, ndl) = dd_div(1.0f64, 0.0f64, tdh, tdl)
        dh = ndh
        dl = ndl
        let (qch, qcl) = dd_div(ah, 0.0f64, ch, cl)
        let (tch, tcl) = math.dd_add(x, 0.0f64, qch, qcl)
        ch = tch
        cl = tcl
        let (dh1, dl1) = math.dd_mul(ch, cl, dh, dl)
        let (fh1, fl1) = math.dd_mul(fh, fl, dh1, dl1)
        fh = fh1
        fl = fl1
        let (mh, ml) = math.dd_add(dh1, dl1, 0.0f64 - 1.0f64, 0.0f64)
        if math.abs[f64](mh) < 1.0e-30f64 { break }
        n += 1.0f64
        i += 1usize
    }
    let (x2h, x2l) = math.two_prod(x, x)
    let ev = math.exp_dd(0.0f64 - x2h, 0.0f64 - x2l)
    let (mh2, ml2) = math.dd_mul(1.7724538509055159f64, 0.0f64, fh, fl)
    let (rh, rl) = dd_div(ev, 0.0f64, mh2, ml2)
    ret rh + rl
}

// The error function: the series below 1, and 1 - erfc above.
fn erf(x: f64) -> f64 {
    if x == infinity() { ret 1.0f64 }
    if x == negative_infinity() { ret 0.0f64 - 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - erf(0.0f64 - x) }
    if x < 1.0f64 {
        let (h, l) = erf_pair(x)
        ret h + l
    }
    ret 1.0f64 - erfc(x)
}

// The complementary error function, evaluated directly from 1 (D7785).
fn erfc(x: f64) -> f64 {
    if x == infinity() { ret 0.0f64 }
    if x == negative_infinity() { ret 2.0f64 }
    if x < 0.0f64 { ret 2.0f64 - erfc(0.0f64 - x) }
    if x < 1.0f64 {
        let (eh, el) = erf_pair(x)
        let (ch, cl) = math.dd_add(1.0f64, 0.0f64, 0.0f64 - eh, 0.0f64 - el)
        ret ch + cl
    }
    ret erfc_cf(x)
}
// The previous implementation, kept beside the pair-based one for one A/B in a single build (D7783): the same
// Taylor series and Lentz fraction, evaluated in plain double. Comparing the two against the same MPFR
// expectations removes any question of which binary ran.
fn erf_plain(x: f64) -> f64 {
    if x == infinity() { ret 1.0f64 }
    if x == negative_infinity() { ret 0.0f64 - 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - erf_plain(0.0f64 - x) }
    if x < 2.5f64 {
        var term = x
        var sum = x
        var n = 0.0f64
        var i = 0usize
        while i < 200usize {
            n += 1.0f64
            term = term * (0.0f64 - x * x) / n
            let add2 = term / (2.0f64 * n + 1.0f64)
            sum += add2
            if math.abs[f64](add2) < 1.0e-17f64 * math.abs[f64](sum) { break }
            i += 1usize
        }
        ret 1.1283791670955126f64 * sum
    }
    ret 1.0f64 - erfc_plain(x)
}

fn erfc_plain(x: f64) -> f64 {
    if x == infinity() { ret 0.0f64 }
    if x == negative_infinity() { ret 2.0f64 }
    if x < 2.5f64 { ret 1.0f64 - erf_plain(x) }
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