// R gsl, value and gsl_sf_result.err of the elementary and gamma-family functions whose gsl routines are short: hypot, sinc, lnsinh, lncosh, log_1plusx, taylorcoeff,
// doublefact, lnfact, lndoublefact, lnchoose, gammastar, gamma, lnbeta. Each returns (value, error); a domain error returns (0, 0).

use e.math
use e.algo.stat.gslcheb2 as ch
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslerr as ge

fn q_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn qa(x: f64) -> f64 { ret math.abs[f64](x) }
fn q_pi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn q_ln2() -> f64 { ret 0.693147180559945309417232121458f64 }
fn q_lnpi() -> f64 { ret 1.14472988584940017414342735135f64 }

fn e_hypot(x: f64, y: f64) -> (f64, f64) {
    if x == 0.0f64 && y == 0.0f64 { ret (0.0f64, 0.0f64) }
    let a = qa(x)
    let b = qa(y)
    var lo = a
    var hi = b
    if b < a {
        lo = b
        hi = a
    }
    let rat = lo / hi
    let v = hi * math.sqrt[f64](1.0f64 + rat * rat)
    ret (v, 2.0f64 * q_eps() * qa(v))
}

fn e_sinc(x: f64) -> (f64, f64) {
    let ax = qa(x)
    if ax < 0.8f64 {
        let (v, e) = ch.cvv_trig_sinc(2.0f64 * ax - 1.0f64)
        ret (v, e)
    }
    if ax < 100.0f64 {
        let v = math.sin[f64](q_pi() * ax) / (q_pi() * ax)
        ret (v, 2.0f64 * q_eps() * qa(v))
    }
    let r = q_pi() * ax
    let (sv, se) = ge.e_sin(r)
    let v = sv / r
    ret (v, se / r + 2.0f64 * q_eps() * qa(v))
}

fn e_log_1plusx(x: f64) -> (f64, f64) {
    if x <= -1.0f64 { ret (0.0f64, 0.0f64) }
    if qa(x) < 2.4607833005759251e-03f64 {
        let c1 = -0.5f64
        let c2 = 1.0f64 / 3.0f64
        let c3 = -1.0f64 / 4.0f64
        let c4 = 1.0f64 / 5.0f64
        let c5 = -1.0f64 / 6.0f64
        let c6 = 1.0f64 / 7.0f64
        let c7 = -1.0f64 / 8.0f64
        let c8 = 1.0f64 / 9.0f64
        let c9 = -1.0f64 / 10.0f64
        let t = c5 + x * (c6 + x * (c7 + x * (c8 + x * c9)))
        let v = x * (1.0f64 + x * (c1 + x * (c2 + x * (c3 + x * (c4 + x * t)))))
        ret (v, q_eps() * qa(v))
    }
    if qa(x) < 0.5f64 {
        let t = 0.5f64 * (8.0f64 * x + 1.0f64) / (x + 2.0f64)
        let (cv, ce) = ch.cvv_log_lopx(t)
        ret (x * cv, qa(x * ce))
    }
    let v = math.log[f64](1.0f64 + x)
    ret (v, q_eps() * qa(v))
}

fn e_log_1plusx_mx(x: f64) -> (f64, f64) {
    if x <= -1.0f64 { ret (0.0f64, 0.0f64) }
    if qa(x) < 7.4009597974140505e-04f64 {
        let c1 = -0.5f64
        let c2 = 1.0f64 / 3.0f64
        let c3 = -1.0f64 / 4.0f64
        let c4 = 1.0f64 / 5.0f64
        let c5 = -1.0f64 / 6.0f64
        let c6 = 1.0f64 / 7.0f64
        let c7 = -1.0f64 / 8.0f64
        let c8 = 1.0f64 / 9.0f64
        let c9 = -1.0f64 / 10.0f64
        let t = c5 + x * (c6 + x * (c7 + x * (c8 + x * c9)))
        let v = x * x * (c1 + x * (c2 + x * (c3 + x * (c4 + x * t))))
        ret (v, q_eps() * qa(v))
    }
    if qa(x) < 0.5f64 {
        let t = 0.5f64 * (8.0f64 * x + 1.0f64) / (x + 2.0f64)
        let (cv, ce) = ch.cvv_log_lopxmx(t)
        ret (x * x * cv, x * x * ce)
    }
    let lterm = math.log[f64](1.0f64 + x)
    ret (lterm - x, q_eps() * (qa(lterm) + qa(x)))
}

fn e_lnsinh(x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if qa(x) < 1.0f64 {
        let v = math.log[f64](gc.sinh_series(x))
        ret (v, 2.0f64 * q_eps() * qa(v))
    }
    if x < 0.5f64 * 36.04365338911715f64 {
        let v = x + math.log[f64](0.5f64 * (1.0f64 - math.exp[f64](-2.0f64 * x)))
        ret (v, 2.0f64 * q_eps() * qa(v))
    }
    let v = x - q_ln2()
    ret (v, 2.0f64 * q_eps() * qa(v))
}

fn e_lncosh(x: f64) -> (f64, f64) {
    if qa(x) < 1.0f64 {
        let (v, e) = e_log_1plusx(gc.cosh_m1_series(x))
        ret (v, e)
    }
    if qa(x) < 0.5f64 * 36.04365338911715f64 {
        let v = qa(x) + math.log[f64](0.5f64 * (1.0f64 + math.exp[f64](-2.0f64 * qa(x))))
        ret (v, 2.0f64 * q_eps() * qa(v))
    }
    let v = qa(x) - q_ln2()
    ret (v, 2.0f64 * q_eps() * qa(v))
}

// gsl_sf_taylorcoeff_e: x^n / n!
fn e_taylorcoeff(n: i64, x: f64) -> (f64, f64) {
    if x < 0.0f64 || n < 0i64 { ret (0.0f64, 0.0f64) }
    if n == 0i64 { ret (1.0f64, 0.0f64) }
    if n == 1i64 { ret (x, 0.0f64) }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    var product = 1.0f64
    var k = 1i64
    while k <= n {
        product = product * (x / f64(k))
        k += 1i64
    }
    ret (product, f64(n) * q_eps() * product)
}

fn fact_val(n: usize) -> f64 {
    var r = 1.0f64
    var i = 2usize
    while i <= n {
        r = r * f64(i)
        i += 1usize
    }
    ret r
}

fn doublefact_val(n: usize) -> f64 {
    var r = 1.0f64
    var i = n
    while i >= 2usize {
        r = r * f64(i)
        i -= 2usize
    }
    ret r
}

fn e_doublefact(n: usize) -> (f64, f64) {
    let v = doublefact_val(n)
    if n < 26usize { ret (v, 0.0f64) }
    ret (v, 2.0f64 * q_eps() * qa(v))
}

fn e_lnfact(n: usize) -> (f64, f64) {
    if n <= 170usize {
        let v = math.log[f64](fact_val(n))
        ret (v, 2.0f64 * q_eps() * qa(v))
    }
    let (lv, le) = gc.lngamma_e(f64(n) + 1.0f64)
    ret (lv, le)
}

fn e_lndoublefact(n: usize) -> (f64, f64) {
    if n <= 297usize {
        let v = math.log[f64](doublefact_val(n))
        ret (v, 2.0f64 * q_eps() * qa(v))
    }
    if n % 2usize == 1usize {
        let (lv, le) = gc.lngamma_e(0.5f64 * (f64(n) + 2.0f64))
        let v = 0.5f64 * (f64(n) + 1.0f64) * q_ln2() - 0.5f64 * q_lnpi() + lv
        ret (v, 2.0f64 * q_eps() * qa(v) + le)
    }
    let (lv2, le2) = gc.lngamma_e(0.5f64 * f64(n) + 1.0f64)
    let v2 = 0.5f64 * f64(n) * q_ln2() + lv2
    ret (v2, 2.0f64 * q_eps() * qa(v2) + le2)
}

fn e_lnchoose(n: usize, m0: usize) -> (f64, f64) {
    if m0 > n { ret (0.0f64, 0.0f64) }
    if m0 == n || m0 == 0usize { ret (0.0f64, 0.0f64) }
    var m = m0
    if m * 2usize > n { m = n - m }
    let (nv, ne) = e_lnfact(n)
    let (mv, me) = e_lnfact(m)
    let (kv, ke) = e_lnfact(n - m)
    let v = nv - mv - kv
    ret (v, ne + me + ke + 2.0f64 * q_eps() * qa(v))
}

// gsl_sf_choose_e for any n (R's lnchoose is this function: its C wrapper calls choose)
fn e_choose_full(n: usize, m0: usize) -> (f64, f64) {
    if m0 > n { ret (0.0f64, 0.0f64) }
    if m0 == n || m0 == 0usize { ret (1.0f64, 0.0f64) }
    if n <= 170usize {
        let (v, e) = ge.e_choose(n, m0)
        ret (v, e)
    }
    var m = m0
    if m * 2usize < n { m = n - m }
    if n - m < 64usize {
        var prod = 1.0f64
        var k = n
        while k >= m + 1usize {
            prod = prod * (f64(k) / f64(k - m))
            k -= 1usize
        }
        ret (prod, 2.0f64 * q_eps() * prod * qa(f64(n) - f64(m)))
    }
    let (lv, le) = e_lnchoose(n, m)
    let (v2, e2, _s) = gc.exp_err(lv, le)
    ret (v2, e2)
}

fn gammastar_ser(x: f64) -> (f64, f64) {
    let y = 1.0f64 / (x * x)
    let c0 = 1.0f64 / 12.0f64
    let c1 = -1.0f64 / 360.0f64
    let c2 = 1.0f64 / 1260.0f64
    let c3 = -1.0f64 / 1680.0f64
    let c4 = 1.0f64 / 1188.0f64
    let c5 = -691.0f64 / 360360.0f64
    let c6 = 1.0f64 / 156.0f64
    let c7 = -3617.0f64 / 122400.0f64
    let ser = c0 + y * (c1 + y * (c2 + y * (c3 + y * (c4 + y * (c5 + y * (c6 + y * c7))))))
    let v = math.exp[f64](ser / x)
    var m = 1.0f64
    if ser / x > 1.0f64 { m = ser / x }
    ret (v, 2.0f64 * q_eps() * v * m)
}

fn e_gammastar(x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 0.5f64 {
        let (lv, le) = gc.lngamma_e(x)
        let lx = math.log[f64](x)
        let c = 0.5f64 * (q_ln2() + q_lnpi())
        let lnr_val = lv - (x - 0.5f64) * lx + x - c
        let lnr_err = le + 2.0f64 * q_eps() * ((x + 0.5f64) * qa(lx) + c)
        let (v, e, _s) = gc.exp_err(lnr_val, lnr_err)
        ret (v, e)
    }
    if x < 2.0f64 {
        let t = 4.0f64 / 3.0f64 * (x - 0.5f64) - 1.0f64
        let (v, e) = ch.cvv_gamma_gstar_a(t)
        ret (v, e)
    }
    if x < 10.0f64 {
        let t = 0.25f64 * (x - 2.0f64) - 1.0f64
        let (cv, ce) = ch.cvv_gamma_gstar_b(t)
        let v = cv / (x * x) + 1.0f64 + 1.0f64 / (12.0f64 * x)
        ret (v, ce / (x * x) + 2.0f64 * q_eps() * qa(v))
    }
    if x < 1.0f64 / 1.2207031250000000e-04f64 {
        let (v, e) = gammastar_ser(x)
        ret (v, e)
    }
    if x < 1.0f64 / q_eps() {
        let xi = 1.0f64 / x
        let v = 1.0f64 + xi / 12.0f64 * (1.0f64 + xi / 24.0f64 * (1.0f64 - xi * (139.0f64 / 180.0f64 + 571.0f64 / 8640.0f64 * xi)))
        ret (v, 2.0f64 * q_eps() * qa(v))
    }
    ret (1.0f64, 1.0f64 / x)
}

// gamma_xgthalf for x >= 0.5, up to GSL_SF_GAMMA_XMAX = 171
fn gamma_xgthalf(x: f64) -> (f64, f64) {
    if x == 0.5f64 {
        let v = 1.77245385090551602729817f64
        ret (v, q_eps() * v)
    }
    if x <= 171.0f64 && x == math.floor[f64](x) {
        let v = fact_val(usize(x) - 1usize)
        ret (v, q_eps() * v)
    }
    if qa(x - 1.0f64) < 0.01f64 {
        let ep = x - 1.0f64
        let c1 = 0.4227843350984671394f64
        let c2 = -0.01094400467202744461f64
        let c3 = 0.09252092391911371098f64
        let c4 = -0.018271913165599812664f64
        let c5 = 0.018004931096854797895f64
        let c6 = -0.006850885378723806846f64
        let c7 = 0.003998239557568466030f64
        ret (1.0f64 / x + ep * (c1 + ep * (c2 + ep * (c3 + ep * (c4 + ep * (c5 + ep * (c6 + ep * c7)))))), q_eps())
    }
    if qa(x - 2.0f64) < 0.01f64 {
        let ep = x - 2.0f64
        let c1 = 0.4227843350984671394f64
        let c2 = 0.4118403304264396948f64
        let c3 = 0.08157691924708626638f64
        let c4 = 0.07424901075351389832f64
        let c5 = -0.00026698206874501476832f64
        let c6 = 0.011154045718130991049f64
        let c7 = -0.002852645821155340816f64
        let c8 = 0.0021039333406973880085f64
        ret (1.0f64 + ep * (c1 + ep * (c2 + ep * (c3 + ep * (c4 + ep * (c5 + ep * (c6 + ep * (c7 + ep * c8))))))), q_eps())
    }
    if x < 5.0f64 {
        let (lv, le) = gc.lngamma_lanczos(x)
        let v = math.exp[f64](lv)
        ret (v, v * (le + 2.0f64 * q_eps()))
    }
    if x < 10.0f64 {
        let t = (2.0f64 * x - 15.0f64) / 5.0f64
        let (cv, ce) = ch.cvv_gamma_gamma_5_10(t)
        let v = math.exp[f64](cv) * 5040.0f64
        ret (v, v * ce + 2.0f64 * q_eps() * v)
    }
    let p = math.pow[f64](x, 0.5f64 * x)
    let ex = math.exp[f64](-x)
    let q = (p * ex) * p
    let pre = 1.4142135623730950488f64 * 1.7724538509055160273f64 * q / math.sqrt[f64](x)
    let (gv, _ge) = gammastar_ser(x)
    let v = pre * gv
    ret (v, (x + 2.5f64) * q_eps() * v)
}

fn e_gamma(x: f64) -> (f64, f64) {
    if x >= 0.5f64 {
        let (v, e) = gamma_xgthalf(x)
        ret (v, e)
    }
    let rint_x = math.floor[f64](x + 0.5f64)
    let f_x = x - rint_x
    var sgn_gamma = 1.0f64
    if math.floor[f64](rint_x / 2.0f64) * 2.0f64 != rint_x { sgn_gamma = -1.0f64 }
    let sin_term = sgn_gamma * math.sin[f64](q_pi() * f_x) / q_pi()
    if sin_term == 0.0f64 { ret (0.0f64, 0.0f64) }
    let (gv, ge2) = gamma_xgthalf(1.0f64 - x)
    let v = 1.0f64 / (sin_term * gv)
    ret (v, qa(ge2 / gv) * qa(v) + 2.0f64 * q_eps() * qa(v))
}

// gsl_sf_lnbeta_e
fn e_lnbeta(x: f64, y: f64) -> (f64, f64) {
    var big = x
    var small = y
    if y > x {
        big = y
        small = x
    }
    if x > 0.0f64 && y > 0.0f64 && small / big < 0.2f64 {
        let rat = small / big
        let (gx, gxe) = e_gammastar(x)
        let (gy, gye) = e_gammastar(y)
        let (gxy, gxye) = e_gammastar(x + y)
        let (lo, loe) = e_log_1plusx(rat)
        let lnpre_val = math.log[f64](gx * gy / gxy * 1.4142135623730950488f64 * 1.7724538509055160273f64)
        let lnpre_err = gxe / gx + gye / gy + gxye / gxy
        let t1 = small * math.log[f64](rat)
        let t2 = 0.5f64 * math.log[f64](small)
        let t3 = (x + y - 0.5f64) * lo
        let lnpow_val = t1 - t2 - t3
        var lnpow_err = q_eps() * (qa(t1) + qa(t2) + qa(t3))
        lnpow_err += qa(x + y - 0.5f64) * loe
        let v = lnpre_val + lnpow_val
        ret (v, lnpre_err + lnpow_err + 2.0f64 * q_eps() * qa(v))
    }
    let (lgx, lgxe, _sx) = ge.e_lngamma_sgn(x)
    let (lgy, lgye, _sy) = ge.e_lngamma_sgn(y)
    let (lgxy, lgxye, _sxy) = ge.e_lngamma_sgn(x + y)
    let v2 = lgx + lgy - lgxy
    var er = lgxe + lgye + lgxye
    er += 2.0f64 * q_eps() * (qa(lgx) + qa(lgy) + qa(lgxy))
    er += 2.0f64 * q_eps() * qa(v2)
    ret (v2, er)
}
