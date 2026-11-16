// R gsl: modified Bessel K of real order, modified Bessel I of real order, Bessel J of integer order, the Lambert W branches W0 and W-1, and the Hurwitz and
// Riemann zeta functions for s > 1.
//
// Not here: Y, the scaled forms, Airy, elliptic integrals, hypergeometric and Legendre functions, the other families and the error estimates.

use e.math
use e.math.special as sp

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

// K_nu(x), x > 0: the trapezoid rule on integral_0^inf exp(-x cosh t) cosh(nu t) dt, whose terms fall off doubly exponentially
fn bessel_knu(nu: f64, x: f64) -> f64 {
    let h = 0.02f64
    var s = 0.5f64 * math.exp[f64](0.0f64 - x)
    var k = 1usize
    while k < 4000usize {
        let t = h * f64(k)
        let e = x * (math.exp[f64](t) + math.exp[f64](0.0f64 - t)) / 2.0f64
        if e > 745.0f64 { break }
        s += math.exp[f64](0.0f64 - e) * (math.exp[f64](nu * t) + math.exp[f64](0.0f64 - nu * t)) / 2.0f64
        k += 1usize
    }
    ret s * h
}

// I_nu(x), x >= 0, nu >= 0: the power series, every term positive
fn bessel_inu(nu: f64, x: f64) -> f64 {
    if x == 0.0f64 {
        if nu == 0.0f64 { ret 1.0f64 }
        ret 0.0f64
    }
    let hx = x / 2.0f64
    var t = math.exp[f64](nu * math.log[f64](hx) - sp.lgamma(nu + 1.0f64))
    var s = t
    var k = 0usize
    while k < 2000usize {
        t = t * hx * hx / (f64(k + 1usize) * (f64(k + 1usize) + nu))
        s += t
        if t < s * 1.0e-17f64 { break }
        k += 1usize
    }
    ret s
}

// J_n(x) for integer n: the mean of cos(n theta - x sin theta) over a full period, exact to rounding once the rule has more points than the integrand's frequency
fn bessel_jn(n: i64, x: f64) -> f64 {
    var nn = f64(n)
    if nn < 0.0f64 { nn = 0.0f64 - nn }
    let pts = usize(2.0f64 * (math.abs[f64](x) + nn) + 64.0f64)
    var s = 0.0f64
    var j = 0usize
    while j < pts {
        let th = 2.0f64 * pi() * f64(j) / f64(pts)
        s += math.cos[f64](f64(n) * th - x * math.sin[f64](th))
        j += 1usize
    }
    ret s / f64(pts)
}

// Lambert W on branch 0 (x >= -1/e) or -1 (-1/e <= x < 0) by Halley's iteration
fn lambert_w(x: f64, branch: i64) -> f64 {
    var w = 0.0f64
    if branch == 0i64 {
        if x < 1.0f64 { w = x / (1.0f64 + x) } else { w = math.log[f64](x) - math.log[f64](math.log[f64](x) + 1.0f64) }
        if x < 0.0f64 { w = x }
    } else {
        let l1 = math.log[f64](0.0f64 - x)
        w = l1 - math.log[f64](0.0f64 - l1)
    }
    var i = 0usize
    while i < 100usize {
        let ew = math.exp[f64](w)
        let f = w * ew - x
        let d = ew * (w + 1.0f64) - (w + 2.0f64) * f / (2.0f64 * w + 2.0f64)
        let nw = w - f / d
        if math.abs[f64](nw - w) <= 1.0e-16f64 * math.abs[f64](nw) {
            w = nw
            break
        }
        w = nw
        i += 1usize
    }
    ret w
}

// the Hurwitz zeta function sum_{k >= 0} (q + k)^-s for s > 1, q > 0: 25 explicit terms and the Euler-Maclaurin tail
fn hzeta(s: f64, q: f64) -> f64 {
    let n = 25usize
    var sum = 0.0f64
    var k = 0usize
    while k < n {
        sum += math.pow[f64](q + f64(k), 0.0f64 - s)
        k += 1usize
    }
    let a = q + f64(n)
    sum += math.pow[f64](a, 1.0f64 - s) / (s - 1.0f64) + 0.5f64 * math.pow[f64](a, 0.0f64 - s)
    // B_2j / (2j)! for j = 1 .. 8
    let c0 = 1.0f64 / 12.0f64
    let c1 = 0.0f64 - 1.0f64 / 720.0f64
    let c2 = 1.0f64 / 30240.0f64
    let c3 = 0.0f64 - 1.0f64 / 1209600.0f64
    let c4 = 1.0f64 / 47900160.0f64
    let c5 = 0.0f64 - 691.0f64 / 1307674368000.0f64
    let c6 = 1.0f64 / 74724249600.0f64
    let c7 = 0.0f64 - 3617.0f64 / 10670622842880000.0f64
    var poch = s
    var pw = math.pow[f64](a, 0.0f64 - s - 1.0f64)
    sum += c0 * poch * pw
    poch = poch * (s + 1.0f64) * (s + 2.0f64)
    pw = pw / (a * a)
    sum += c1 * poch * pw
    poch = poch * (s + 3.0f64) * (s + 4.0f64)
    pw = pw / (a * a)
    sum += c2 * poch * pw
    poch = poch * (s + 5.0f64) * (s + 6.0f64)
    pw = pw / (a * a)
    sum += c3 * poch * pw
    poch = poch * (s + 7.0f64) * (s + 8.0f64)
    pw = pw / (a * a)
    sum += c4 * poch * pw
    poch = poch * (s + 9.0f64) * (s + 10.0f64)
    pw = pw / (a * a)
    sum += c5 * poch * pw
    poch = poch * (s + 11.0f64) * (s + 12.0f64)
    pw = pw / (a * a)
    sum += c6 * poch * pw
    poch = poch * (s + 13.0f64) * (s + 14.0f64)
    pw = pw / (a * a)
    sum += c7 * poch * pw
    ret sum
}
