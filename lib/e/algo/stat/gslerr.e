// R gsl, value and gsl_sf_result.err together (the `val` and `err` that give = TRUE returns) for the families whose error terms are closed forms in GSL's source: the elementary
// functions (sin, cos, log, log_abs, pow_int, fact, choose, erf_Z), ln Gamma and its sign, psi(1 + i y), the low-order and recurrence-built orthogonal polynomials (Legendre P1, P2, P3, Pl,
// Plm, Laguerre 1 to 3, Gegenbauer 1 to 3 and n), Legendre Q0 and Q1. The coulomb functions with their errors are in gslcoulomb.
// Every function returns (value, error); a domain error returns (0, 0) like gsl does.

use e.math
use e.algo.stat.gslcoulomb as gc

fn eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }

fn e_sin(x: f64) -> (f64, f64) {
    let abs_x = fa(x)
    if abs_x < 1.2207031250000000e-04f64 {
        let x2 = x * x
        ret (x * (1.0f64 - x2 / 6.0f64), fa(x * x2 * x2 / 100.0f64))
    }
    let v = math.sin[f64](x)
    let sq = 1.4901161193847656e-08f64
    var e = 2.0f64 * eps() * fa(v)
    if abs_x > 0.1f64 / sq { e = 2.0f64 * sq * fa(v) }
    if abs_x > 100.0f64 / sq { e = 2.0f64 * abs_x * eps() * fa(v) }
    if abs_x > 1.0f64 / eps() { e = fa(v) }
    ret (v, e)
}

fn e_cos(x: f64) -> (f64, f64) {
    let abs_x = fa(x)
    if abs_x < 1.2207031250000000e-04f64 {
        let x2 = x * x
        ret (1.0f64 - 0.5f64 * x2, fa(x2 * x2 / 12.0f64))
    }
    let v = math.cos[f64](x)
    let sq = 1.4901161193847656e-08f64
    var e = 2.0f64 * eps() * fa(v)
    if abs_x > 0.1f64 / sq { e = 2.0f64 * sq * fa(v) }
    if abs_x > 100.0f64 / sq { e = 2.0f64 * abs_x * eps() * fa(v) }
    if abs_x > 1.0f64 / eps() { e = fa(v) }
    ret (v, e)
}

fn e_log(x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    let v = math.log[f64](x)
    ret (v, 2.0f64 * eps() * fa(v))
}

fn e_log_abs(x: f64) -> (f64, f64) {
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    let v = math.log[f64](fa(x))
    ret (v, 2.0f64 * eps() * fa(v))
}

fn e_pow_int(x0: f64, n0: i64) -> (f64, f64) {
    var x = x0
    var n = n0
    if n < 0i64 {
        n = 0i64 - n
        x = 1.0f64 / x
    }
    var v = 1.0f64
    var count = 0i64
    while true {
        if n % 2i64 == 1i64 { v = v * x }
        n = n / 2i64
        x = x * x
        count += 1i64
        if n == 0i64 { break }
    }
    ret (v, 2.0f64 * eps() * (f64(count) + 1.0f64) * fa(v))
}

fn e_fact(n: usize) -> (f64, f64) {
    var r = 1.0f64
    var i = 2usize
    while i <= n {
        r = r * f64(i)
        i += 1usize
    }
    if n < 18usize { ret (r, 0.0f64) }
    ret (r, 2.0f64 * eps() * fa(r))
}

// gsl_sf_choose_e for n <= 170
fn e_choose(n: usize, m: usize) -> (f64, f64) {
    if m > n { ret (0.0f64, 0.0f64) }
    if m == n || m == 0usize { ret (1.0f64, 0.0f64) }
    let (fnn, _e1) = e_fact(n)
    let (fm, _e2) = e_fact(m)
    let (fnm, _e3) = e_fact(n - m)
    let v = (fnn / fm) / fnm
    ret (v, 6.0f64 * eps() * fa(v))
}

fn e_erf_z(x: f64) -> (f64, f64) {
    let ex2 = math.exp[f64](0.0f64 - x * x / 2.0f64)
    let v = ex2 / (1.4142135623730950488f64 * 1.7724538509055160273f64)
    ret (v, fa(x * v) * eps() + 2.0f64 * eps() * fa(v))
}

// ln |Gamma(x)| with its sign, x > -1 or away from a negative integer by more than 0.0147 (the series near a pole of order two or more is not here)
fn e_lngamma_sgn(x: f64) -> (f64, f64, f64) {
    let (v, e) = gc.lngamma_e(x)
    if x >= 0.5f64 || fa(x - 1.0f64) < 0.01f64 || fa(x - 2.0f64) < 0.01f64 { ret (v, e, 1.0f64) }
    if fa(x) < 0.02f64 {
        if x > 0.0f64 { ret (v, e, 1.0f64) }
        ret (v, e, -1.0f64)
    }
    let s = math.sin[f64](3.141592653589793238462643383279f64 * x)
    if fa(s) < 3.141592653589793238462643383279f64 * 0.015f64 {
        if x + 1.0f64 > 0.0f64 { ret (v, e, -1.0f64) }
        ret (v, e, 1.0f64)
    }
    if s > 0.0f64 { ret (v, e, 1.0f64) }
    ret (v, e, -1.0f64)
}

fn e_lngamma(x: f64) -> (f64, f64) {
    let (v, e) = gc.lngamma_e(x)
    ret (v, e)
}

// Re psi(1 + i y) with its error
fn e_psi_1piy(y: f64) -> (f64, f64) {
    let ay = fa(y)
    let v = gc.psi_1piy(y)
    let eu = 0.577215664901532860606512090082f64
    if ay > 1000.0f64 {
        let yi2 = 1.0f64 / (ay * ay)
        let lny = math.log[f64](ay)
        let sum = yi2 * (1.0f64 / 12.0f64 + 1.0f64 / 120.0f64 * yi2 + 1.0f64 / 252.0f64 * yi2 * yi2)
        ret (v, 2.0f64 * eps() * (fa(lny) + fa(sum)))
    }
    if ay > 10.0f64 {
        let yi2 = 1.0f64 / (ay * ay)
        let lny = math.log[f64](ay)
        let sum = yi2 * (1.0f64 / 12.0f64 + yi2 * (1.0f64 / 120.0f64 + yi2 * (1.0f64 / 252.0f64 + yi2 * (1.0f64 / 240.0f64 + yi2 * (1.0f64 / 132.0f64 + 691.0f64 / 32760.0f64 * yi2)))))
        ret (v, 2.0f64 * eps() * (fa(lny) + fa(sum)))
    }
    if ay > 1.0f64 {
        let y2 = ay * ay
        let x = (2.0f64 * ay - 11.0f64) / 9.0f64
        let vv = y2 * (1.0f64 / (1.0f64 + y2) + 0.5f64 / (4.0f64 + y2))
        let (cv, ce) = r1py_cheb_err(x)
        var er = ce
        er += 2.0f64 * eps() * (fa(vv) + eu + fa(cv))
        er += 2.0f64 * eps() * fa(v)
        er *= 5.0f64
        ret (v, er)
    }
    let vv = v + eu
    ret (v, eps() * (eu + fa(vv)) + 2.0f64 * eps() * fa(v))
}

// cheb_eval_e on [-1, 1], order 29: (value, error)
fn r1py_cheb_err(x: f64) -> (f64, f64) {
    var d = 0.0f64
    var dd = 0.0f64
    var e = 0.0f64
    let y = x
    let y2 = 2.0f64 * y
    var j = 29usize
    while j >= 1usize {
        let temp = d
        let cj = gc.r1py_c(j)
        d = y2 * d - dd + cj
        e += fa(y2 * temp) + fa(dd) + fa(cj)
        dd = temp
        j -= 1usize
    }
    let temp = d
    let c0 = gc.r1py_c(0usize)
    d = y * d - dd + 0.5f64 * c0
    e += fa(y * temp) + fa(dd) + 0.5f64 * fa(c0)
    ret (d, eps() * e + fa(gc.r1py_c(29usize)))
}

fn e_legendre_p1(x: f64) -> (f64, f64) { ret (x, 0.0f64) }

fn e_legendre_p2(x: f64) -> (f64, f64) { ret (0.5f64 * (3.0f64 * x * x - 1.0f64), eps() * (fa(3.0f64 * x * x) + 1.0f64)) }

fn e_legendre_p3(x: f64) -> (f64, f64) {
    let v = 0.5f64 * x * (5.0f64 * x * x - 3.0f64)
    ret (v, eps() * (fa(v) + 0.5f64 * fa(x) * (fa(5.0f64 * x * x) + 3.0f64)))
}

// P_l(x) for l < 100000 by the upward recurrence
fn e_legendre_pl(l: usize, x: f64) -> (f64, f64) {
    if l == 0usize { ret (1.0f64, 0.0f64) }
    if l == 1usize { ret (x, 0.0f64) }
    if l == 2usize {
        let (rv, re_) = e_legendre_p2(x)
        ret (rv, re_)
    }
    if x == 1.0f64 { ret (1.0f64, 0.0f64) }
    if x == -1.0f64 {
        if l % 2usize == 1usize { ret (-1.0f64, 0.0f64) }
        ret (1.0f64, 0.0f64)
    }
    var pm2 = 1.0f64
    var pm1 = x
    var p = pm1
    var em2 = eps()
    var em1 = fa(x) * eps()
    var e = em1
    var ell = 2usize
    while ell <= l {
        let lf = f64(ell)
        p = (x * (2.0f64 * lf - 1.0f64) * pm1 - (lf - 1.0f64) * pm2) / lf
        pm2 = pm1
        pm1 = p
        e = 0.5f64 * (fa(x) * (2.0f64 * lf - 1.0f64) * em1 + (lf - 1.0f64) * em2) / lf
        em2 = em1
        em1 = e
        ell += 1usize
    }
    ret (p, e + f64(l) * fa(p) * eps())
}

fn e_legendre_plm(l: usize, m: usize, x: f64) -> (f64, f64) {
    let err_amp = 1.0f64 / (eps() + fa(1.0f64 - fa(x)))
    var pmm = 1.0f64
    if m > 0usize {
        let root_factor = math.sqrt[f64](1.0f64 - x) * math.sqrt[f64](1.0f64 + x)
        var fc = 1.0f64
        var i = 1usize
        while i <= m {
            pmm = pmm * (0.0f64 - fc * root_factor)
            fc += 2.0f64
            i += 1usize
        }
    }
    let pmmp1 = x * f64(2usize * m + 1usize) * pmm
    if l == m { ret (pmm, err_amp * 2.0f64 * eps() * fa(pmm)) }
    if l == m + 1usize { ret (pmmp1, err_amp * 2.0f64 * eps() * fa(pmmp1)) }
    var pm2 = pmm
    var pm1 = pmmp1
    var p = 0.0f64
    var ell = m + 2usize
    while ell <= l {
        p = (x * f64(2usize * ell - 1usize) * pm1 - f64(ell + m - 1usize) * pm2) / f64(ell - m)
        pm2 = pm1
        pm1 = p
        ell += 1usize
    }
    ret (p, err_amp * (0.5f64 * f64(l - m) + 1.0f64) * eps() * fa(p))
}

fn e_laguerre_1(a: f64, x: f64) -> (f64, f64) { ret (1.0f64 + a - x, 2.0f64 * eps() * (1.0f64 + fa(a) + fa(x))) }

fn e_laguerre_2(a: f64, x: f64) -> (f64, f64) {
    if a == -2.0f64 {
        let v = 0.5f64 * x * x
        ret (v, 2.0f64 * eps() * fa(v))
    }
    let c0 = 0.5f64 * (2.0f64 + a) * (1.0f64 + a)
    let c1 = 0.0f64 - (2.0f64 + a)
    let c2 = -0.5f64 / (2.0f64 + a)
    let v = c0 + c1 * x * (1.0f64 + c2 * x)
    let e = 2.0f64 * eps() * (fa(c0) + 2.0f64 * fa(c1 * x) * (1.0f64 + 2.0f64 * fa(c2 * x))) + 2.0f64 * eps() * fa(v)
    ret (v, e)
}

fn e_laguerre_3(a: f64, x: f64) -> (f64, f64) {
    if a == -2.0f64 {
        let x2_6 = x * x / 6.0f64
        let v = x2_6 * (3.0f64 - x)
        ret (v, x2_6 * (3.0f64 + fa(x)) * 2.0f64 * eps() + 2.0f64 * eps() * fa(v))
    }
    if a == -3.0f64 {
        let v = 0.0f64 - x * x / 6.0f64
        ret (v, 2.0f64 * eps() * fa(v))
    }
    let c0 = (3.0f64 + a) * (2.0f64 + a) * (1.0f64 + a) / 6.0f64
    let c1 = 0.0f64 - c0 * 3.0f64 / (1.0f64 + a)
    let c2 = -1.0f64 / (2.0f64 + a)
    let c3 = -1.0f64 / (3.0f64 * (3.0f64 + a))
    let v = c0 + c1 * x * (1.0f64 + c2 * x * (1.0f64 + c3 * x))
    var er = 1.0f64 + 2.0f64 * fa(c3 * x)
    er = 1.0f64 + 2.0f64 * fa(c2 * x) * er
    er = 2.0f64 * eps() * (fa(c0) + 2.0f64 * fa(c1 * x) * er)
    er += 2.0f64 * eps() * fa(v)
    ret (v, er)
}

fn e_gegenpoly_1(lam: f64, x: f64) -> (f64, f64) {
    if lam == 0.0f64 {
        let v = 2.0f64 * x
        ret (v, 2.0f64 * eps() * fa(v))
    }
    let v = 2.0f64 * lam * x
    ret (v, 4.0f64 * eps() * fa(v))
}

fn e_gegenpoly_2(lam: f64, x: f64) -> (f64, f64) {
    if lam == 0.0f64 {
        let txx = 2.0f64 * x * x
        let v = -1.0f64 + txx
        ret (v, 2.0f64 * eps() * fa(txx) + 2.0f64 * eps() * fa(v))
    }
    let v = lam * (-1.0f64 + 2.0f64 * (1.0f64 + lam) * x * x)
    ret (v, eps() * (2.0f64 * fa(v) + fa(lam)))
}

fn e_gegenpoly_3(lam: f64, x: f64) -> (f64, f64) {
    if lam == 0.0f64 {
        let v = x * (-2.0f64 + 4.0f64 / 3.0f64 * x * x)
        ret (v, eps() * (2.0f64 * fa(v) + fa(x)))
    }
    let c = 4.0f64 + lam * (6.0f64 + 2.0f64 * lam)
    let v = 2.0f64 * lam * x * (-1.0f64 - lam + c * x * x / 3.0f64)
    ret (v, eps() * (2.0f64 * fa(v) + fa(lam * x)))
}

fn e_gegenpoly_n(n: usize, lam: f64, x: f64) -> (f64, f64) {
    if lam <= -0.5f64 { ret (0.0f64, 0.0f64) }
    if n == 0usize { ret (1.0f64, 0.0f64) }
    if n == 1usize {
        let (rv, re_) = e_gegenpoly_1(lam, x)
        ret (rv, re_)
    }
    if n == 2usize {
        let (rv, re_) = e_gegenpoly_2(lam, x)
        ret (rv, re_)
    }
    if n == 3usize {
        let (rv, re_) = e_gegenpoly_3(lam, x)
        ret (rv, re_)
    }
    if lam == 0.0f64 && x >= -1.0f64 && x <= 1.0f64 {
        let z = f64(n) * math.acos[f64](x)
        let v = 2.0f64 * math.cos[f64](z) / f64(n)
        ret (v, 2.0f64 * eps() * fa(z * v))
    }
    let (g2, _e2) = e_gegenpoly_2(lam, x)
    let (g3, _e3) = e_gegenpoly_3(lam, x)
    var gkm2 = g2
    var gkm1 = g3
    var gk = 0.0f64
    var k = 4usize
    while k <= n {
        let kf = f64(k)
        gk = (2.0f64 * (kf + lam - 1.0f64) * x * gkm1 - (kf + 2.0f64 * lam - 2.0f64) * gkm2) / kf
        gkm2 = gkm1
        gkm1 = gk
        k += 1usize
    }
    ret (gk, 2.0f64 * eps() * 0.5f64 * f64(n) * fa(gk))
}

fn e_legendre_q0(x: f64) -> (f64, f64) {
    if x <= -1.0f64 || x == 1.0f64 { ret (0.0f64, 0.0f64) }
    if x * x < 2.4607833005759251e-03f64 {
        let y = x * x
        let series = 1.0f64 + y * (1.0f64 / 3.0f64 + y * (1.0f64 / 5.0f64 + y * (1.0f64 / 7.0f64 + y * (1.0f64 / 9.0f64 + y * (1.0f64 / 11.0f64)))))
        ret (x * series, 2.0f64 * eps() * fa(x))
    }
    if x < 1.0f64 {
        let v = 0.5f64 * math.log[f64]((1.0f64 + x) / (1.0f64 - x))
        ret (v, 2.0f64 * eps() * fa(v))
    }
    if x < 10.0f64 {
        let v = 0.5f64 * math.log[f64]((x + 1.0f64) / (x - 1.0f64))
        ret (v, 2.0f64 * eps() * fa(v))
    }
    let y = 1.0f64 / (x * x)
    let v = (1.0f64 / x) * (1.0f64 + y * (1.0f64 / 3.0f64 + y * (1.0f64 / 5.0f64 + y * (1.0f64 / 7.0f64 + y * (1.0f64 / 9.0f64 + y * (1.0f64 / 11.0f64 + y * (1.0f64 / 13.0f64 + y * (1.0f64 / 15.0f64))))))))
    ret (v, 2.0f64 * eps() * fa(v))
}

fn e_legendre_q1(x: f64) -> (f64, f64) {
    if x <= -1.0f64 || x == 1.0f64 { ret (0.0f64, 0.0f64) }
    if x * x < 2.4607833005759251e-03f64 {
        let y = x * x
        let series = 1.0f64 + y * (1.0f64 / 3.0f64 + y * (1.0f64 / 5.0f64 + y * (1.0f64 / 7.0f64 + y * (1.0f64 / 9.0f64 + y * (1.0f64 / 11.0f64)))))
        let v = x * x * series - 1.0f64
        ret (v, 2.0f64 * eps() * fa(v))
    }
    if x < 1.0f64 {
        let v = 0.5f64 * x * math.log[f64]((1.0f64 + x) / (1.0f64 - x)) - 1.0f64
        ret (v, 2.0f64 * eps() * fa(v))
    }
    if x < 6.0f64 {
        let v = 0.5f64 * x * math.log[f64]((x + 1.0f64) / (x - 1.0f64)) - 1.0f64
        ret (v, 2.0f64 * eps() * fa(v))
    }
    let y = 1.0f64 / (x * x)
    let sum = 1.0f64 + y * (3.0f64 / 5.0f64 + y * (3.0f64 / 7.0f64 + y * (3.0f64 / 9.0f64 + y * (3.0f64 / 11.0f64 + y * (3.0f64 / 13.0f64 + y * (3.0f64 / 15.0f64 + y * (3.0f64 / 17.0f64 + y * (3.0f64 / 19.0f64))))))))
    let v = sum / (3.0f64 * x * x)
    ret (v, 2.0f64 * eps() * fa(v))
}
