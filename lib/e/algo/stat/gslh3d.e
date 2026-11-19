// R gsl, legendre_H3d_0, legendre_H3d_1, legendre_H3d and legendre_H3d_array with gsl_sf_result.err: a port of specfunc/legendre_H3d.c for the series, the continued-fraction backward
// recurrence and the two small functions. The large-argument and large-degree branches of legendre_H3d_e (the conical-function asymptotics of legendre_con.c) are not here.
// Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslerr as ge
use e.algo.stat.gslerr2 as g2
use e.algo.stat.gslairy as gy

fn h_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn ha(x: f64) -> f64 { ret math.abs[f64](x) }
fn h_lnpi() -> f64 { ret 1.14472988584940017414342735135f64 }
fn h_ln2() -> f64 { ret 0.693147180559945309417232121458f64 }
fn h_pi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn h_sqrt_min() -> f64 { ret 1.4916681462400413e-154f64 }

fn sinh_(x: f64) -> f64 {
    if ha(x) < 1.0f64 { ret gc.sinh_series(x) }
    ret (math.exp[f64](x) - math.exp[f64](0.0f64 - x)) / 2.0f64
}

fn tanh2(x: f64) -> f64 {
    if ha(x) < 1.0f64 { ret gc.sinh_series(x) / (1.0f64 + gc.cosh_m1_series(x)) }
    ret gc.tanh_(x)
}

fn cosh_(x: f64) -> f64 { ret (math.exp[f64](x) + math.exp[f64](0.0f64 - x)) / 2.0f64 }

fn hyp(x: f64, y: f64) -> f64 {
    let (v, _e) = g2.e_hypot(x, y)
    ret v
}

// log of the normalisation N(ell, lambda)
fn h3d_lnnorm(ell: i64, lambda: f64) -> f64 {
    let abs_lam = ha(lambda)
    if abs_lam == 0.0f64 { ret 0.0f64 }
    if lambda > (f64(ell) + 1.0f64) / 6.0554544523933429e-06f64 {
        let rat = (f64(ell) + 1.0f64) / lambda
        let ln_lam2ell2 = 2.0f64 * math.log[f64](lambda) + math.log[f64](1.0f64 + rat * rat)
        let lg_corrected = -2.0f64 * (f64(ell) + 1.0f64) + h_lnpi() + (f64(ell) + 0.5f64) * ln_lam2ell2 + 1.0f64 / (288.0f64 * lambda * lambda)
        let angle_terms = lambda * 2.0f64 * rat * (1.0f64 - rat * rat / 3.0f64)
        ret math.log[f64](abs_lam) + lg_corrected + angle_terms - h_lnpi()
    }
    let (lgr, _lge) = gc.lngamma_complex_lnr(f64(ell) + 1.0f64, lambda)
    let (lsv, _lse) = g2.e_lnsinh(h_pi() * abs_lam)
    ret math.log[f64](abs_lam) + lsv + 2.0f64 * lgr - h_lnpi()
}

fn h3d_series(ell: i64, lambda: f64, eta: f64) -> (f64, f64) {
    let shheta = sinh_(0.5f64 * eta)
    let ln_zp1 = h_ln2() + math.log[f64](1.0f64 + shheta * shheta)
    let ln_zm1 = h_ln2() + 2.0f64 * math.log[f64](shheta)
    let zeta = 0.0f64 - shheta * shheta
    var term = 1.0f64
    var sum = 1.0f64
    var sum_err = 0.0f64
    let (lgv, lge) = gc.lngamma_e(f64(ell) + 1.5f64)
    let (lshv, lshe) = g2.e_lnsinh(eta)
    let ln_n = h3d_lnnorm(ell, lambda)
    let lnprepow = 0.5f64 * (f64(ell) + 0.5f64) * (ln_zm1 - ln_zp1)
    let lnpre_val = lnprepow + 0.5f64 * (ln_n + h_lnpi() - h_ln2() - lshv) - lgv - math.log[f64](ha(lambda))
    var lnpre_err = lshe + lge + h_eps() * ha(lnpre_val)
    lnpre_err += 2.0f64 * h_eps() * (ha(ln_n) + h_lnpi() + h_ln2())
    lnpre_err += 2.0f64 * h_eps() * (0.5f64 * (f64(ell) + 0.5f64) * (ha(ln_zm1) + ha(ln_zp1)))
    var n = 1i64
    while n < 5000i64 {
        let ar = f64(n) - 0.5f64
        term = term * (ar * ar + lambda * lambda) * zeta / (f64(ell + n) + 0.5f64) / f64(n)
        sum += term
        sum_err += 2.0f64 * h_eps() * ha(term)
        if ha(term / sum) < 2.0f64 * h_eps() { break }
        n += 1i64
    }
    let (v, e) = gy.exp_mult_err(lnpre_val, lnpre_err, sum, ha(term) + sum_err)
    ret (v, e)
}

fn h3d_cf1_ser(ell: i64, lambda: f64, coth_eta: f64) -> (f64, f64) {
    let pre = hyp(lambda, f64(ell) + 1.0f64) / ((2.0f64 * f64(ell) + 3.0f64) * coth_eta)
    var tk = 1.0f64
    var sum = 1.0f64
    var rhok = 0.0f64
    var sum_err = 0.0f64
    var k = 1i64
    while k < 20000i64 {
        let tlk = 2.0f64 * f64(ell) + 1.0f64 + 2.0f64 * f64(k)
        let l1k = f64(ell) + 1.0f64 + f64(k)
        let ak = 0.0f64 - (lambda * lambda + l1k * l1k) / (tlk * (tlk + 2.0f64) * coth_eta * coth_eta)
        rhok = 0.0f64 - ak * (1.0f64 + rhok) / (1.0f64 + ak * (1.0f64 + rhok))
        tk = tk * rhok
        sum += tk
        sum_err += 2.0f64 * h_eps() * f64(k) * ha(tk)
        if ha(tk / sum) < h_eps() { break }
        k += 1i64
    }
    let v = pre * sum
    ret (v, ha(pre * tk) + ha(pre * sum_err) + 4.0f64 * h_eps() * ha(v))
}

fn h3d_0(lambda: f64, eta: f64) -> (f64, f64) {
    if eta < 0.0f64 { ret (0.0f64, 0.0f64) }
    if eta == 0.0f64 || lambda == 0.0f64 { ret (1.0f64, 0.0f64) }
    let lam_eta = lambda * eta
    let (sv0, se0) = ge.e_sin(lam_eta)
    let sv = sv0
    let se = se0 + ha(math.cos[f64](lam_eta) * 2.0f64 * h_eps() * ha(lam_eta)) + h_eps() * ha(sv0)
    if eta > 0.5f64 * 36.04365338911715f64 {
        let f = 2.0f64 / lambda * math.exp[f64](0.0f64 - eta)
        let v = f * sv
        var er = ha(f * sv) * (ha(eta) + 1.0f64) * h_eps()
        er += ha(f) * se
        er += 2.0f64 * h_eps() * ha(v)
        ret (v, er)
    }
    let f2 = 1.0f64 / (lambda * sinh_(eta))
    let v2 = f2 * sv
    var er2 = ha(f2 * sv) * (ha(eta) + 1.0f64) * h_eps()
    er2 += ha(f2) * se
    er2 += 2.0f64 * h_eps() * ha(v2)
    ret (v2, er2)
}

fn h3d_1(lambda: f64, eta: f64) -> (f64, f64) {
    let xi = ha(eta * lambda)
    let lsq = lambda * lambda
    let lsqp1 = lsq + 1.0f64
    if eta < 0.0f64 { ret (0.0f64, 0.0f64) }
    if eta == 0.0f64 || lambda == 0.0f64 { ret (0.0f64, 0.0f64) }
    if xi < 7.4009597974140505e-04f64 && eta < 7.4009597974140505e-04f64 {
        let etasq = eta * eta
        let xisq = xi * xi
        let term1 = (etasq + xisq) / 3.0f64
        let term2 = 0.0f64 - (2.0f64 * etasq * etasq + 5.0f64 * etasq * xisq + 3.0f64 * xisq * xisq) / 90.0f64
        let sinh_term = 1.0f64 - eta * eta / 6.0f64 * (1.0f64 - 7.0f64 / 60.0f64 * eta * eta)
        let pre = sinh_term / math.sqrt[f64](lsqp1) / eta
        let v = pre * (term1 + term2)
        ret (v, pre * h_eps() * (ha(term1) + ha(term2)) + 2.0f64 * h_eps() * ha(v))
    }
    var sin_term = 0.0f64
    var cos_term = 0.0f64
    var sin_term_err = 0.0f64
    var cos_term_err = 0.0f64
    if xi < 7.4009597974140505e-04f64 {
        sin_term = 1.0f64 - xi * xi / 6.0f64 * (1.0f64 - xi * xi / 20.0f64)
        cos_term = 1.0f64 - 0.5f64 * xi * xi * (1.0f64 - xi * xi / 12.0f64)
        sin_term_err = h_eps()
        cos_term_err = h_eps()
    }
    if xi >= 7.4009597974140505e-04f64 {
        let (sx, sxe) = ge.e_sin(xi)
        let (cx, cxe) = ge.e_cos(xi)
        sin_term = sx / xi
        cos_term = cx
        sin_term_err = sxe / ha(xi)
        cos_term_err = cxe
    }
    var coth_term = 0.0f64
    var sinh_term2 = 0.0f64
    if eta < 7.4009597974140505e-04f64 {
        coth_term = 1.0f64 + eta * eta / 3.0f64 * (1.0f64 - eta * eta / 15.0f64)
        sinh_term2 = 1.0f64 - eta * eta / 6.0f64 * (1.0f64 - 7.0f64 / 60.0f64 * eta * eta)
    }
    if eta >= 7.4009597974140505e-04f64 {
        coth_term = eta / tanh2(eta)
        sinh_term2 = eta / sinh_(eta)
    }
    let t1 = math.sqrt[f64](lsqp1) * eta
    let pre_val = sinh_term2 / t1
    let pre_err = 2.0f64 * h_eps() * ha(pre_val)
    let term1 = sin_term * coth_term
    let term2 = cos_term
    let v = pre_val * (term1 - term2)
    var er = pre_err * ha(term1 - term2)
    er += pre_val * (sin_term_err * coth_term + cos_term_err)
    er += pre_val * ha(term1 - term2) * (ha(eta) + 1.0f64) * h_eps()
    er += 2.0f64 * h_eps() * ha(v)
    ret (v, er)
}

// legendre_H3d(ell, lambda, eta) for the branches that do not need the conical-function asymptotics
fn h3d(ell: i64, lambda: f64, eta: f64) -> (f64, f64) {
    let abs_lam = ha(lambda)
    let lsq = abs_lam * abs_lam
    let xi = abs_lam * eta
    if eta < 0.0f64 { ret (0.0f64, 0.0f64) }
    if eta > 709.78271289338397f64 { ret (0.0f64, 0.0f64) }
    if ell == 0i64 {
        let (v, e) = h3d_0(lambda, eta)
        ret (v, e)
    }
    if ell == 1i64 {
        let (v1, e1) = h3d_1(lambda, eta)
        ret (v1, e1)
    }
    if eta == 0.0f64 { ret (0.0f64, 0.0f64) }
    if xi < 1.0f64 {
        let (v2, e2) = h3d_series(ell, lambda, eta)
        ret (v2, e2)
    }
    let coth_eta = 1.0f64 / tanh2(eta)
    let coth_err_mult = ha(eta) + 1.0f64
    let (rhv, rhe) = h3d_cf1_ser(ell, lambda, coth_eta)
    var hl = h_sqrt_min()
    var hlp1 = rhv * hl
    var lp = ell
    while lp > 0i64 {
        let rt0 = hyp(lambda, f64(lp))
        let rt1 = hyp(lambda, f64(lp) + 1.0f64)
        let hlm1 = ((2.0f64 * f64(lp) + 1.0f64) * coth_eta * hl - rt1 * hlp1) / rt0
        hlp1 = hl
        hl = hlm1
        lp -= 1i64
    }
    if ha(hl) > ha(hlp1) {
        let (h0v, h0e) = h3d_0(lambda, eta)
        let v3 = h_sqrt_min() / hl * h0v
        var er = h_sqrt_min() / ha(hl) * h0e
        er += ha(rhe / rhv) * (f64(ell) + 1.0f64) * coth_err_mult * ha(v3)
        er += 2.0f64 * h_eps() * ha(v3)
        ret (v3, er)
    }
    let (h1v, h1e) = h3d_1(lambda, eta)
    let v4 = h_sqrt_min() / hlp1 * h1v
    var er2 = h_sqrt_min() / ha(hlp1) * h1e
    er2 += ha(rhe / rhv) * (f64(ell) + 1.0f64) * coth_err_mult * ha(v4)
    er2 += 2.0f64 * h_eps() * ha(v4)
    ret (v4, er2)
}

// element ell of legendre_H3d_array(lmax, lambda, eta)
fn h3d_array_elt(lmax: i64, lambda: f64, eta: f64, ell: i64) -> f64 {
    if lmax == 0i64 {
        let (v, _e) = h3d(0i64, lambda, eta)
        ret v
    }
    let (hlp1_0, _e1) = h3d(lmax, lambda, eta)
    let (hl_0, _e2) = h3d(lmax - 1i64, lambda, eta)
    if ell == lmax { ret hlp1_0 }
    if ell == lmax - 1i64 { ret hl_0 }
    let coth_eta = 1.0f64 / tanh2(eta)
    var hlp1 = hlp1_0
    var hl = hl_0
    var l = lmax - 1i64
    var out = 0.0f64
    while l > 0i64 {
        let rt0 = hyp(lambda, f64(l))
        let rt1 = hyp(lambda, f64(l) + 1.0f64)
        let hlm1 = ((2.0f64 * f64(l) + 1.0f64) * coth_eta * hl - rt1 * hlp1) / rt0
        if l - 1i64 == ell { out = hlm1 }
        hlp1 = hl
        hl = hlm1
        l -= 1i64
    }
    ret out
}
