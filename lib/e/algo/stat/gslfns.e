// R gsl: modified Bessel K of real order, modified Bessel I of real order, Bessel J of integer order, the Lambert W branches W0 and W-1, and the Hurwitz and
// Riemann zeta functions for s > 1.
//
// Not here: Y, the scaled forms, Airy, elliptic integrals, hypergeometric and Legendre functions, the other families and the error estimates.

use e.math
use e.math.special as sp
use e.math.nmath as nmg
use e.math.nmath_beta as nbt
use e.math.dist as dist
use e.math.quadpack as qp
use e.mem

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

// K_nu(x), x > 0: the trapezoid rule (step 0.1, whose error falls like exp(-pi^2 / h)) on integral_0^inf exp(-x cosh t) cosh(nu t) dt, whose terms fall off doubly exponentially
fn bessel_knu(nu: f64, x: f64) -> f64 {
    let h = 0.1f64
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
    var pochv = s
    var pw = math.pow[f64](a, 0.0f64 - s - 1.0f64)
    sum += c0 * pochv * pw
    pochv = pochv * (s + 1.0f64) * (s + 2.0f64)
    pw = pw / (a * a)
    sum += c1 * pochv * pw
    pochv = pochv * (s + 3.0f64) * (s + 4.0f64)
    pw = pw / (a * a)
    sum += c2 * pochv * pw
    pochv = pochv * (s + 5.0f64) * (s + 6.0f64)
    pw = pw / (a * a)
    sum += c3 * pochv * pw
    pochv = pochv * (s + 7.0f64) * (s + 8.0f64)
    pw = pw / (a * a)
    sum += c4 * pochv * pw
    pochv = pochv * (s + 9.0f64) * (s + 10.0f64)
    pw = pw / (a * a)
    sum += c5 * pochv * pw
    pochv = pochv * (s + 11.0f64) * (s + 12.0f64)
    pw = pw / (a * a)
    sum += c6 * pochv * pw
    pochv = pochv * (s + 13.0f64) * (s + 14.0f64)
    pw = pw / (a * a)
    sum += c7 * pochv * pw
    ret sum
}

fn euler_gamma() -> f64 { ret 0.577215664901532860606512090082f64 }

// E_1(x), x > 0: the power series up to x = 1, the Lentz continued fraction beyond
fn expint_e1(x: f64) -> f64 {
    if x <= 1.0f64 {
        var s = 0.0f64
        var t = 1.0f64
        var k = 1usize
        while k < 200usize {
            t = t * (0.0f64 - x) / f64(k)
            let term = t / f64(k)
            s += term
            if math.abs[f64](term) < 1.0e-18f64 { break }
            k += 1usize
        }
        ret 0.0f64 - euler_gamma() - math.log[f64](x) - s
    }
    var b = x + 1.0f64
    var c = 1.0e300f64
    var d = 1.0f64 / b
    var h = d
    var i = 1usize
    while i < 500usize {
        let an = 0.0f64 - f64(i) * f64(i)
        b += 2.0f64
        d = 1.0f64 / (an * d + b)
        c = b + an / c
        let del = c * d
        h = h * del
        if math.abs[f64](del - 1.0f64) < 1.0e-16f64 { break }
        i += 1usize
    }
    ret h * math.exp[f64](0.0f64 - x)
}

// Ei(x): the series for x > 0, minus E_1(-x) for x < 0
fn expint_ei(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - expint_e1(0.0f64 - x) }
    var s = 0.0f64
    var t = 1.0f64
    var k = 1usize
    while k < 500usize {
        t = t * x / f64(k)
        let term = t / f64(k)
        s += term
        if term < s * 1.0e-17f64 { break }
        k += 1usize
    }
    ret euler_gamma() + math.log[f64](x) + s
}

// Dawson's integral F(x) = exp(-x^2) integral_0^x exp(t^2) dt by Rybicki's sum over odd multiples of h = 0.2, whose error is below e^-240
fn dawson(x: f64) -> f64 {
    let h = 0.2f64
    let n0 = 2.0f64 * math.floor[f64](0.5f64 * x / h + 0.5f64)
    var s = 0.0f64
    var m = -61i64
    while m <= 61i64 {
        let n = n0 + f64(m)
        let z = x - n * h
        s += math.exp[f64](0.0f64 - z * z) / n
        m += 2i64
    }
    ret s / 1.7724538509055160273f64
}

// the Clausen function Cl_2(x) for 0 < x <= 1.5 by its Bernoulli-number series
fn clausen(x: f64) -> f64 {
    var s = x - x * math.log[f64](x)
    var pw = x
    var fact = 1.0f64
    var k = 1usize
    while k <= 10usize {
        pw = pw * x * x
        fact = fact * f64(2usize * k) * f64(2usize * k + 1usize)
        s += bern(k) * pw / (f64(2usize * k) * fact)
        k += 1usize
    }
    ret s
}

// |B_2k| for k = 1 .. 10
fn bern(k: usize) -> f64 {
    if k == 1usize { ret 1.0f64 / 6.0f64 }
    if k == 2usize { ret 1.0f64 / 30.0f64 }
    if k == 3usize { ret 1.0f64 / 42.0f64 }
    if k == 4usize { ret 1.0f64 / 30.0f64 }
    if k == 5usize { ret 5.0f64 / 66.0f64 }
    if k == 6usize { ret 691.0f64 / 2730.0f64 }
    if k == 7usize { ret 7.0f64 / 6.0f64 }
    if k == 8usize { ret 3617.0f64 / 510.0f64 }
    if k == 9usize { ret 43867.0f64 / 798.0f64 }
    ret 174611.0f64 / 330.0f64
}

// J_nu(x), x > 0, by the alternating power series (fine to x of about 15)
fn bessel_jnu(nu: f64, x: f64) -> f64 {
    let hx = x / 2.0f64
    var t = math.exp[f64](nu * math.log[f64](hx) - sp.lgamma(nu + 1.0f64))
    var s = t
    var k = 0usize
    while k < 200usize {
        t = 0.0f64 - t * hx * hx / (f64(k + 1usize) * (f64(k + 1usize) + nu))
        s += t
        if math.abs[f64](t) < 1.0e-18f64 * math.abs[f64](s) { break }
        k += 1usize
    }
    ret s
}

// the Airy functions: Ai through K_{1/3} and Bi through I_{+-1/3} for x > 0, and both through J_{+-1/3} for x < 0
fn airy_ai(x: f64) -> f64 {
    if x > 0.0f64 {
        let z = 2.0f64 / 3.0f64 * math.pow[f64](x, 1.5f64)
        ret math.sqrt[f64](x / 3.0f64) / pi() * bessel_knu(1.0f64 / 3.0f64, z)
    }
    let a = 0.0f64 - x
    let z = 2.0f64 / 3.0f64 * math.pow[f64](a, 1.5f64)
    ret math.sqrt[f64](a) / 3.0f64 * (bessel_jnu(1.0f64 / 3.0f64, z) + bessel_jnu(0.0f64 - 1.0f64 / 3.0f64, z))
}

fn airy_bi(x: f64) -> f64 {
    if x > 0.0f64 {
        let z = 2.0f64 / 3.0f64 * math.pow[f64](x, 1.5f64)
        ret math.sqrt[f64](x / 3.0f64) * (bessel_inu(0.0f64 - 1.0f64 / 3.0f64, z) + bessel_inu(1.0f64 / 3.0f64, z))
    }
    let a = 0.0f64 - x
    let z = 2.0f64 / 3.0f64 * math.pow[f64](a, 1.5f64)
    ret math.sqrt[f64](a / 3.0f64) * (bessel_jnu(0.0f64 - 1.0f64 / 3.0f64, z) - bessel_jnu(1.0f64 / 3.0f64, z))
}

// Carlson's R_F(x, y, z) by duplication and the fifth-order series
fn ellint_rf(x: f64, y: f64, z: f64) -> f64 {
    var xt = x
    var yt = y
    var zt = z
    var ave = 0.0f64
    var dx = 0.0f64
    var dy = 0.0f64
    var dz = 0.0f64
    var i = 0usize
    while i < 200usize {
        let sx = math.sqrt[f64](xt)
        let sy = math.sqrt[f64](yt)
        let sz = math.sqrt[f64](zt)
        let al = sx * (sy + sz) + sy * sz
        xt = 0.25f64 * (xt + al)
        yt = 0.25f64 * (yt + al)
        zt = 0.25f64 * (zt + al)
        ave = (xt + yt + zt) / 3.0f64
        dx = (ave - xt) / ave
        dy = (ave - yt) / ave
        dz = (ave - zt) / ave
        var m = math.abs[f64](dx)
        if math.abs[f64](dy) > m { m = math.abs[f64](dy) }
        if math.abs[f64](dz) > m { m = math.abs[f64](dz) }
        if m < 0.0025f64 { break }
        i += 1usize
    }
    let e2 = dx * dy - dz * dz
    let e3 = dx * dy * dz
    ret (1.0f64 + (e2 / 24.0f64 - 0.1f64 - 3.0f64 * e3 / 44.0f64) * e2 + e3 / 14.0f64) / math.sqrt[f64](ave)
}

// Carlson's R_D(x, y, z)
fn ellint_rd(x: f64, y: f64, z: f64) -> f64 {
    var xt = x
    var yt = y
    var zt = z
    var sum = 0.0f64
    var fac = 1.0f64
    var ave = 0.0f64
    var dx = 0.0f64
    var dy = 0.0f64
    var dz = 0.0f64
    var i = 0usize
    while i < 200usize {
        let sx = math.sqrt[f64](xt)
        let sy = math.sqrt[f64](yt)
        let sz = math.sqrt[f64](zt)
        let al = sx * (sy + sz) + sy * sz
        sum += fac / (sz * (zt + al))
        fac = 0.25f64 * fac
        xt = 0.25f64 * (xt + al)
        yt = 0.25f64 * (yt + al)
        zt = 0.25f64 * (zt + al)
        ave = 0.2f64 * (xt + yt + 3.0f64 * zt)
        dx = (ave - xt) / ave
        dy = (ave - yt) / ave
        dz = (ave - zt) / ave
        var m = math.abs[f64](dx)
        if math.abs[f64](dy) > m { m = math.abs[f64](dy) }
        if math.abs[f64](dz) > m { m = math.abs[f64](dz) }
        if m < 0.0015f64 { break }
        i += 1usize
    }
    let c1 = 3.0f64 / 14.0f64
    let c2 = 1.0f64 / 6.0f64
    let c3 = 9.0f64 / 22.0f64
    let c4 = 3.0f64 / 26.0f64
    let c5 = 0.25f64 * c3
    let c6 = 1.5f64 * c4
    let ea = dx * dy
    let eb = dz * dz
    let ec = ea - eb
    let ed = ea - 6.0f64 * eb
    let ee = ed + ec + ec
    ret 3.0f64 * sum + fac * (1.0f64 + ed * (0.0f64 - c1 + c5 * ed - c6 * dz * ee) + dz * (c2 * ee + dz * (0.0f64 - c3 * ec + dz * c4 * ea))) / (ave * math.sqrt[f64](ave))
}

// the Legendre forms with modulus k: F(phi, k), E(phi, k), and the complete K(k) and E(k)
fn ellint_f(phi: f64, k: f64) -> f64 {
    let s = math.sin[f64](phi)
    let c = math.cos[f64](phi)
    ret s * ellint_rf(c * c, 1.0f64 - k * k * s * s, 1.0f64)
}

fn ellint_e(phi: f64, k: f64) -> f64 {
    let s = math.sin[f64](phi)
    let c = math.cos[f64](phi)
    let q = 1.0f64 - k * k * s * s
    ret s * ellint_rf(c * c, q, 1.0f64) - k * k * s * s * s * ellint_rd(c * c, q, 1.0f64) / 3.0f64
}

fn ellint_kcomp(k: f64) -> f64 { ret ellint_rf(0.0f64, 1.0f64 - k * k, 1.0f64) }

fn ellint_ecomp(k: f64) -> f64 {
    let q = 1.0f64 - k * k
    ret ellint_rf(0.0f64, q, 1.0f64) - k * k * ellint_rd(0.0f64, q, 1.0f64) / 3.0f64
}

// 0F1(; b; x), 1F1(a; b; x) and 2F1(a, b; c; x) (|x| < 1) by their power series
fn hyperg_0f1(b: f64, x: f64) -> f64 {
    var t = 1.0f64
    var s = 1.0f64
    var k = 0usize
    while k < 500usize {
        t = t * x / ((b + f64(k)) * f64(k + 1usize))
        s += t
        if math.abs[f64](t) < 1.0e-18f64 * math.abs[f64](s) { break }
        k += 1usize
    }
    ret s
}

fn hyperg_1f1(a: f64, b: f64, x: f64) -> f64 {
    var t = 1.0f64
    var s = 1.0f64
    var k = 0usize
    while k < 1000usize {
        t = t * (a + f64(k)) * x / ((b + f64(k)) * f64(k + 1usize))
        s += t
        if math.abs[f64](t) < 1.0e-18f64 * math.abs[f64](s) { break }
        k += 1usize
    }
    ret s
}

fn hyperg_2f1(a: f64, b: f64, c: f64, x: f64) -> f64 {
    var t = 1.0f64
    var s = 1.0f64
    var k = 0usize
    while k < 3000usize {
        t = t * (a + f64(k)) * (b + f64(k)) * x / ((c + f64(k)) * f64(k + 1usize))
        s += t
        if math.abs[f64](t) < 1.0e-18f64 * math.abs[f64](s) { break }
        k += 1usize
    }
    ret s
}

// P_l(x) and the associated P_l^m(x) with the Condon-Shortley phase, by the upward recurrence
fn legendre_plm(l: usize, m: usize, x: f64) -> f64 {
    var pmm = 1.0f64
    if m > 0usize {
        let somx2 = math.sqrt[f64]((1.0f64 - x) * (1.0f64 + x))
        var fact = 1.0f64
        var i = 1usize
        while i <= m {
            pmm = 0.0f64 - pmm * fact * somx2
            fact += 2.0f64
            i += 1usize
        }
    }
    if l == m { ret pmm }
    var pm1 = x * f64(2usize * m + 1usize) * pmm
    if l == m + 1usize { ret pm1 }
    var ll = m + 2usize
    var pll = 0.0f64
    while ll <= l {
        pll = (x * f64(2usize * ll - 1usize) * pm1 - f64(ll + m - 1usize) * pmm) / f64(ll - m)
        pmm = pm1
        pm1 = pll
        ll += 1usize
    }
    ret pll
}

fn legendre_pl(l: usize, x: f64) -> f64 { ret legendre_plm(l, 0usize, x) }

// the Fermi-Dirac integral of order 0, ln(1 + e^x)
fn fermi_dirac_0(x: f64) -> f64 {
    if x > 35.0f64 { ret x + math.exp[f64](0.0f64 - x) }
    ret math.log[f64](1.0f64 + math.exp[f64](x))
}

// Li_2(x) for real x <= 1: the series on [0, 1/2], Landen's transformation for x < 0, the reflection formula above 1/2
fn dilog(x: f64) -> f64 {
    if x == 1.0f64 { ret pi() * pi() / 6.0f64 }
    if x < 0.0f64 {
        let l = math.log[f64](1.0f64 - x)
        ret 0.0f64 - dilog(x / (x - 1.0f64)) - 0.5f64 * l * l
    }
    if x > 0.5f64 { ret pi() * pi() / 6.0f64 - math.log[f64](x) * math.log[f64](1.0f64 - x) - dilog(1.0f64 - x) }
    var t = 1.0f64
    var s = 0.0f64
    var k = 1usize
    while k < 200usize {
        t = t * x
        let term = t / (f64(k) * f64(k))
        s += term
        if term < 1.0e-18f64 { break }
        k += 1usize
    }
    ret s
}

// the digamma function for x > 0: upward recurrence to x >= 12, then the asymptotic series
fn psi(x0: f64) -> f64 {
    var x = x0
    var s = 0.0f64
    while x < 12.0f64 {
        s -= 1.0f64 / x
        x += 1.0f64
    }
    let i2 = 1.0f64 / (x * x)
    let ser = i2 * (1.0f64 / 12.0f64 - i2 * (1.0f64 / 120.0f64 - i2 * (1.0f64 / 252.0f64 - i2 * (1.0f64 / 240.0f64 - i2 * (1.0f64 / 132.0f64 - i2 * 691.0f64 / 32760.0f64)))))
    ret s + math.log[f64](x) - 0.5f64 / x - ser
}

// ---- Debye, transport, Fermi-Dirac and synchrotron functions by adaptive quadrature (e.math.quadpack, tolerance 1e-13), for x > 0 (the Debye and transport
// functions) and any real x (Fermi-Dirac)
type Qd = struct { kind: usize, n: f64, x: f64 }

fn qd_fn(c: *Qd, t: f64) -> f64 {
    if c.kind == 0usize {
        // Debye: t^n / (e^t - 1)
        if t == 0.0f64 {
            if c.n == 1.0f64 { ret 1.0f64 }
            ret 0.0f64
        }
        ret math.pow[f64](t, c.n) / dist.expm1(t)
    }
    if c.kind == 1usize {
        // transport: t^n e^t / (e^t - 1)^2
        if t == 0.0f64 {
            if c.n == 2.0f64 { ret 1.0f64 }
            ret 0.0f64
        }
        let em = dist.expm1(t)
        ret math.pow[f64](t, c.n) * math.exp[f64](t) / (em * em)
    }
    if c.kind == 2usize {
        // Fermi-Dirac of order n > -1: t^n / (e^(t - x) + 1)
        if t == 0.0f64 && c.n < 0.0f64 { ret 0.0f64 }
        ret math.pow[f64](t, c.n) / (math.exp[f64](t - c.x) + 1.0f64)
    }
    if c.kind == 3usize {
        // Fermi-Dirac of order -1/2 after t = u^2: 2 / (e^(u^2 - x) + 1)
        ret 2.0f64 / (math.exp[f64](t * t - c.x) + 1.0f64)
    }
    // synchrotron_1: K(5/3, t)
    ret bessel_knu(5.0f64 / 3.0f64, t)
}

fn qd_finite(a: *mem.Arena, kind: usize, n: f64, x: f64, hi: f64) -> f64 {
    var c: Qd = zero
    c.kind = kind
    c.n = n
    c.x = x
    let (r, e) = qp.qags[Qd](a, &c, qd_fn, 0.0f64, hi, 0.0f64, 0.0000000000001f64, 200usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret r.result
}

fn qd_infinite(a: *mem.Arena, kind: usize, n: f64, x: f64, lo: f64) -> f64 {
    var c: Qd = zero
    c.kind = kind
    c.n = n
    c.x = x
    let (r, e) = qp.qagi[Qd](a, &c, qd_fn, lo, 1i64, 0.0f64, 0.0000000000001f64, 200usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret r.result
}

fn debye(a: *mem.Arena, n: usize, x: f64) -> f64 { ret f64(n) / math.pow[f64](x, f64(n)) * qd_finite(a, 0usize, f64(n), 0.0f64, x) }

fn transport(a: *mem.Arena, n: usize, x: f64) -> f64 { ret qd_finite(a, 1usize, f64(n), 0.0f64, x) }

// fermi_dirac_j(x) = F_j(x) = 1 / Gamma(j + 1) integral_0^Inf t^j / (e^(t - x) + 1) dt, for the orders gsl exposes (-1, -1/2, 1/2, 1, 3/2, 2)
fn fermi_dirac(a: *mem.Arena, j: f64, x: f64) -> f64 {
    if j == 0.0f64 - 1.0f64 { ret math.exp[f64](x) / (1.0f64 + math.exp[f64](x)) }
    if j == 0.0f64 - 0.5f64 { ret qd_infinite(a, 3usize, 0.0f64, x, 0.0f64) / math.exp[f64](sp.lgamma(0.5f64)) }
    ret qd_infinite(a, 2usize, j, x, 0.0f64) / math.exp[f64](sp.lgamma(j + 1.0f64))
}

fn synchrotron_1(a: *mem.Arena, x: f64) -> f64 { ret x * qd_infinite(a, 4usize, 0.0f64, 0.0f64, x) }

fn synchrotron_2(x: f64) -> f64 { ret x * bessel_knu(2.0f64 / 3.0f64, x) }

// ---- gamma-family helpers of gsl: the incomplete gamma functions (gamma_inc the unnormalised upper one), the regularised incomplete beta, the Pochhammer symbol and
// its log and relative forms, the error functions, sinc, the factorial families, lnbeta and the hyperbolic logs
fn gamma_inc_q(a: f64, x: f64) -> f64 { ret nmg.pgamma(x, a, 1.0f64, false, false) }

fn gamma_inc_p(a: f64, x: f64) -> f64 { ret nmg.pgamma(x, a, 1.0f64, true, false) }

fn gamma_inc(a: f64, x: f64) -> f64 { ret math.exp[f64](sp.lgamma(a)) * nmg.pgamma(x, a, 1.0f64, false, false) }

fn beta_inc(a: f64, b: f64, x: f64) -> f64 { ret nbt.pbeta(x, a, b, true, false) }

fn poch(a: f64, x: f64) -> f64 { ret math.exp[f64](sp.lgamma(a + x) - sp.lgamma(a)) }

fn lnpoch(a: f64, x: f64) -> f64 { ret sp.lgamma(a + x) - sp.lgamma(a) }

// pochrel(a, x) = ((a)_x - 1) / x
fn pochrel(a: f64, x: f64) -> f64 { ret (poch(a, x) - 1.0f64) / x }

fn erf(x: f64) -> f64 { ret 2.0f64 * dist.pnorm(x * math.sqrt[f64](2.0f64), 0.0f64, 1.0f64, true, false) - 1.0f64 }

fn erfc(x: f64) -> f64 { ret 2.0f64 * dist.pnorm(0.0f64 - x * math.sqrt[f64](2.0f64), 0.0f64, 1.0f64, true, false) }

fn log_erfc(x: f64) -> f64 { ret math.log[f64](2.0f64) + dist.pnorm(0.0f64 - x * math.sqrt[f64](2.0f64), 0.0f64, 1.0f64, true, true) }

fn sinc(x: f64) -> f64 {
    if x == 0.0f64 { ret 1.0f64 }
    ret math.sin[f64](3.141592653589793238462643383279f64 * x) / (3.141592653589793238462643383279f64 * x)
}

fn lnchoose(n: f64, m: f64) -> f64 { ret sp.lgamma(n + 1.0f64) - sp.lgamma(m + 1.0f64) - sp.lgamma(n - m + 1.0f64) }

// gsl_sf_choose; the R package's lnchoose wrapper returns this value (the binomial coefficient), not its log
fn choose_(n: f64, m: f64) -> f64 { ret math.floor[f64](math.exp[f64](lnchoose(n, m)) + 0.5f64) }

fn lnbeta(a: f64, b: f64) -> f64 { ret sp.lgamma(a) + sp.lgamma(b) - sp.lgamma(a + b) }

fn lnfact(n: f64) -> f64 { ret sp.lgamma(n + 1.0f64) }

// doublefact(n) = n!! and lndoublefact(n): n (n - 2) (n - 4) ... down to 1 or 2
fn lndoublefact(n: usize) -> f64 {
    var s = 0.0f64
    var k = n
    while k > 1usize {
        s += math.log[f64](f64(k))
        k -= 2usize
    }
    ret s
}

fn doublefact(n: usize) -> f64 { ret math.exp[f64](lndoublefact(n)) }

fn lnsinh(x: f64) -> f64 { ret x + math.log[f64](1.0f64 - math.exp[f64](0.0f64 - 2.0f64 * x)) - math.log[f64](2.0f64) }

fn lncosh(x: f64) -> f64 { ret x + math.log[f64](1.0f64 + math.exp[f64](0.0f64 - 2.0f64 * x)) - math.log[f64](2.0f64) }

fn taylorcoeff(n: usize, x: f64) -> f64 { ret math.exp[f64](f64(n) * math.log[f64](x) - sp.lgamma(f64(n) + 1.0f64)) }

// ---- the polygamma functions through the Hurwitz zeta function, and a few gamma-related helpers (positive arguments)
fn psi_n(n: usize, x: f64) -> f64 {
    var sgn = 1.0f64
    if n % 2usize == 0usize { sgn = 0.0f64 - 1.0f64 }
    ret sgn * math.exp[f64](sp.lgamma(f64(n) + 1.0f64)) * hzeta(f64(n) + 1.0f64, x)
}

fn psi_1(x: f64) -> f64 { ret hzeta(2.0f64, x) }

fn gammainv(x: f64) -> f64 { ret math.exp[f64](0.0f64 - sp.lgamma(x)) }

fn gammastar(x: f64) -> f64 { ret math.exp[f64](sp.lgamma(x) - (x - 0.5f64) * math.log[f64](x) + x - 0.5f64 * math.log[f64](2.0f64 * 3.141592653589793238462643383279f64)) }

fn hypot(x: f64, y: f64) -> f64 { ret math.sqrt[f64](x * x + y * y) }
