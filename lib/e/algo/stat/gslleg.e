// R gsl, legendre_Ql (every l) and legendre_sphPlm with gsl_sf_result.err: a port of specfunc/legendre_Qn.c and the sphPlm routine of legendre_poly.c.
// Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.mem
use e.algo.stat.gslbessel as gb
use e.algo.stat.gslbj as gj
use e.algo.stat.gslerr as ge
use e.algo.stat.gslerr2 as g2
use e.algo.stat.gslpoch as gp

fn l_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn la(x: f64) -> f64 { ret math.abs[f64](x) }
fn sqrt_dbl_min() -> f64 { ret 1.4916681462400413e-154f64 }

// f_{l+1} / f_l of Q^b_{a+l}(x), x > 1
fn ql_cf1_xgt1(ell: i64, a: f64, b: f64, x: f64) -> f64 {
    let recur_big = 1.3407807929942596e+154f64
    var n = 1i64
    var anm2 = 1.0f64
    var bnm2 = 0.0f64
    var anm1 = 0.0f64
    var bnm1 = 1.0f64
    let a1 = f64(ell) + 1.0f64 + a + b
    let b1 = (2.0f64 * (f64(ell) + 1.0f64 + a) + 1.0f64) * x
    var an = b1 * anm1 + a1 * anm2
    var bn = b1 * bnm1 + a1 * bnm2
    var fnv = an / bn
    while n < 5000i64 {
        n += 1i64
        anm2 = anm1
        bnm2 = bnm1
        anm1 = an
        bnm1 = bn
        let lna = f64(ell + n) + a
        let aa = b * b - lna * lna
        let bb = (2.0f64 * lna + 1.0f64) * x
        an = bb * anm1 + aa * anm2
        bn = bb * bnm1 + aa * bnm2
        if la(an) > recur_big || la(bn) > recur_big {
            an = an / recur_big
            bn = bn / recur_big
            anm1 = anm1 / recur_big
            bnm1 = bnm1 / recur_big
            anm2 = anm2 / recur_big
            bnm2 = bnm2 / recur_big
        }
        let old_fn = fnv
        fnv = an / bn
        let del = old_fn / fnv
        if la(del - 1.0f64) < 4.0f64 * l_eps() { break }
    }
    ret fnv
}

fn ql_asymp_unif(ell: f64, x: f64) -> (f64, f64) {
    let pi = 3.141592653589793238462643383279f64
    let u = ell + 0.5f64
    if x < 1.0f64 {
        let th = math.acos[f64](x)
        var pre = 0.0f64
        var b00 = 0.0f64
        if th < 1.2207031250000000e-04f64 {
            b00 = (1.0f64 + th * th / 15.0f64) / 24.0f64
            pre = 1.0f64 + th * th / 12.0f64
        }
        if th >= 1.2207031250000000e-04f64 {
            let sin_th = math.sqrt[f64](1.0f64 - x * x)
            let cot_th = x / sin_th
            b00 = 1.0f64 / 8.0f64 * (1.0f64 - th * cot_th) / (th * th)
            pre = math.sqrt[f64](th / sin_th)
        }
        let (y0, y0e) = gj.y0(u * th)
        let (y1, y1e) = gj.y1(u * th)
        let sum = -0.5f64 * pi * (y0 + th / u * y1 * b00)
        let v = pre * sum
        var er = 2.0f64 * l_eps() * la(v) + 0.5f64 * pi * la(pre) * (y0e + la(th / u * b00) * y1e)
        er += l_eps() * la(v)
        ret (v, er)
    }
    let xi = math.log[f64](x + math.sqrt[f64](x * x - 1.0f64))
    var pre2 = 0.0f64
    var b002 = 0.0f64
    if xi < 1.2207031250000000e-04f64 {
        b002 = (1.0f64 - xi * xi / 15.0f64) / 24.0f64
        pre2 = 1.0f64 - xi * xi / 12.0f64
    }
    if xi >= 1.2207031250000000e-04f64 {
        let sinh_xi = math.sqrt[f64](x * x - 1.0f64)
        let coth_xi = x / sinh_xi
        b002 = -1.0f64 / 8.0f64 * (1.0f64 - xi * coth_xi) / (xi * xi)
        pre2 = math.sqrt[f64](xi / sinh_xi)
    }
    let (k0, _k0e) = gb.k0_scaled(u * xi)
    let (k1, _k1e) = gb.k1_scaled(u * xi)
    let sum2 = k0 - xi / u * k1 * b002
    let v2 = pre2 * sum2 * math.exp[f64](0.0f64 - u * xi)
    ret (v2, l_eps() * la(v2) * la(u * xi) + 2.0f64 * l_eps() * la(v2))
}

fn legendre_ql(l: i64, x: f64) -> (f64, f64) {
    if x <= -1.0f64 || x == 1.0f64 || l < 0i64 { ret (0.0f64, 0.0f64) }
    if l == 0i64 {
        let (v, e) = ge.e_legendre_q0(x)
        ret (v, e)
    }
    if l == 1i64 {
        let (v1, e1) = ge.e_legendre_q1(x)
        ret (v1, e1)
    }
    if l > 100000i64 {
        let (v2, e2) = ql_asymp_unif(f64(l), x)
        ret (v2, e2)
    }
    if x < 1.0f64 {
        let (q0, _e0) = ge.e_legendre_q0(x)
        let (q1, _e1) = ge.e_legendre_q1(x)
        var qm = q0
        var qe = q1
        var ell = 1i64
        while ell < l {
            let qp = (x * (2.0f64 * f64(ell) + 1.0f64) * qe - f64(ell) * qm) / (f64(ell) + 1.0f64)
            qm = qe
            qe = qp
            ell += 1i64
        }
        ret (qe, l_eps() * f64(l) * la(qe))
    }
    let rat = ql_cf1_xgt1(l, 0.0f64, 0.0f64, x)
    var qp2 = rat * sqrt_dbl_min()
    var qell = sqrt_dbl_min()
    var ell2 = l
    while ell2 > 0i64 {
        let qm2 = (x * (2.0f64 * f64(ell2) + 1.0f64) * qell - (f64(ell2) + 1.0f64) * qp2) / f64(ell2)
        qp2 = qell
        qell = qm2
        ell2 -= 1i64
    }
    if la(qell) > la(qp2) {
        let (q0b, _e0b) = ge.e_legendre_q0(x)
        let v3 = sqrt_dbl_min() * q0b / qell
        ret (v3, f64(l) * l_eps() * la(v3))
    }
    let (q1b, _e1b) = ge.e_legendre_q1(x)
    let v4 = sqrt_dbl_min() * q1b / qp2
    ret (v4, f64(l) * l_eps() * la(v4))
}

fn legendre_sphplm(a: *mem.Arena, l: i64, m: i64, x: f64) -> (f64, f64) {
    let pi = 3.141592653589793238462643383279f64
    if m < 0i64 || l < m || x < -1.0f64 || x > 1.0f64 { ret (0.0f64, 0.0f64) }
    if m == 0i64 {
        let (pv, pe) = ge.e_legendre_pl(usize(l), x)
        let pre = math.sqrt[f64]((2.0f64 * f64(l) + 1.0f64) / (4.0f64 * pi))
        let v = pre * pv
        ret (v, pre * pe + 2.0f64 * l_eps() * la(v))
    }
    if x == 1.0f64 || x == -1.0f64 { ret (0.0f64, 0.0f64) }
    var sgn = 1.0f64
    if m % 2i64 == 1i64 { sgn = -1.0f64 }
    let y_mmp1_factor = x * math.sqrt[f64](2.0f64 * f64(m) + 3.0f64)
    let (lcv, lce) = g2.e_log_1plusx(0.0f64 - x * x)
    let (lpv, lpe) = gp.lnpoch(a, f64(m), 0.5f64)
    let lnpre_val = -0.25f64 * 1.14472988584940017414342735135f64 + 0.5f64 * (lpv + f64(m) * lcv)
    let lnpre_err = 0.25f64 * 1.14472988584940017414342735135f64 * l_eps() + 0.5f64 * (lpe + la(f64(m)) * lce)
    let ex_val = math.exp[f64](lnpre_val)
    var sh = (math.exp[f64](lnpre_err) - math.exp[f64](0.0f64 - lnpre_err)) / 2.0f64
    if la(lnpre_err) < 0.01f64 { sh = lnpre_err * (1.0f64 + lnpre_err * lnpre_err / 6.0f64 * (1.0f64 + lnpre_err * lnpre_err / 20.0f64)) }
    let ex_err = 2.0f64 * (sh + l_eps()) * ex_val
    let sr = math.sqrt[f64]((2.0f64 + 1.0f64 / f64(m)) / (4.0f64 * pi))
    var y_mm = sgn * sr * ex_val
    var y_mm_err = 2.0f64 * l_eps() * la(y_mm) + sr * ex_err
    y_mm_err = y_mm_err * (1.0f64 + 1.0f64 / (l_eps() + la(1.0f64 - x)))
    var y_mmp1 = y_mmp1_factor * y_mm
    var y_mmp1_err = la(y_mmp1_factor) * y_mm_err
    if l == m { ret (y_mm, y_mm_err + 2.0f64 * l_eps() * la(y_mm)) }
    if l == m + 1i64 { ret (y_mmp1, y_mmp1_err + 2.0f64 * l_eps() * la(y_mmp1)) }
    var y_ell = 0.0f64
    var y_ell_err = 0.0f64
    var ell = m + 2i64
    while ell <= l {
        let rat1 = f64(ell - m) / f64(ell + m)
        let rat2 = (f64(ell - m) - 1.0f64) / (f64(ell + m) - 1.0f64)
        let factor1 = math.sqrt[f64](rat1 * (2.0f64 * f64(ell) + 1.0f64) * (2.0f64 * f64(ell) - 1.0f64))
        let factor2 = math.sqrt[f64](rat1 * rat2 * (2.0f64 * f64(ell) + 1.0f64) / (2.0f64 * f64(ell) - 3.0f64))
        y_ell = (x * y_mmp1 * factor1 - (f64(ell + m) - 1.0f64) * y_mm * factor2) / f64(ell - m)
        y_mm = y_mmp1
        y_mmp1 = y_ell
        y_ell_err = 0.5f64 * (la(x * factor1) * y_mmp1_err + la((f64(ell + m) - 1.0f64) * factor2) * y_mm_err) / la(f64(ell - m))
        y_mm_err = y_mmp1_err
        y_mmp1_err = y_ell_err
        ell += 1i64
    }
    ret (y_ell, y_ell_err + (0.5f64 * f64(l - m) + 1.0f64) * l_eps() * la(y_ell))
}
