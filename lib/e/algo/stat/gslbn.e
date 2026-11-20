// R gsl, the integer-order Bessel functions Yn, Kn (scaled and plain) and In (scaled and plain) with gsl_sf_result.err: a port of specfunc/bessel_Yn.c, bessel_Kn.c, bessel_In.c and the
// Taylor and continued-fraction helpers of bessel.c. The Olver uniform asymptotic branches (Yn and Kn with n > 50 or a large argument, In with n >= 150) are in gslnu (yn_full, kn_full, in_full).
// Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.mem
use e.algo.stat.gslbessel as gb
use e.algo.stat.gslbj as gj
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslerr2 as g2
use e.algo.stat.gslpoch as gp
use e.algo.stat.gslpsi as gs

fn n_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn na(x: f64) -> f64 { ret math.abs[f64](x) }
fn n_pi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn n_root3() -> f64 { ret 6.0554544523933429e-06f64 }
fn n_euler() -> f64 { ret 0.577215664901532860606512090082f64 }

fn amp_mnu(nu: f64, x: f64) -> f64 {
    let r = 2.0f64 * nu / x
    let r2 = r * r
    let x2 = x * x
    let term1 = (r2 - 1.0f64 / x2) / 8.0f64
    let term2 = (r2 - 1.0f64 / x2) * (r2 - 9.0f64 / x2) * 3.0f64 / 128.0f64
    let c = 2.0f64 / n_pi() * (1.0f64 + term1 + term2)
    ret math.sqrt[f64](c) / math.sqrt[f64](x)
}

fn theta_corr(nu: f64, x: f64) -> f64 {
    let r = 2.0f64 * nu / x
    let r2 = r * r
    let x2 = x * x
    let term1 = x * (r2 - 1.0f64 / x2) / 8.0f64
    let term2 = x * (r2 - 1.0f64 / x2) * (r2 - 25.0f64 / x2) / 384.0f64
    ret -0.25f64 * n_pi() + term1 + term2
}

fn ynu_asympx(nu: f64, x: f64) -> (f64, f64) {
    let ampl = amp_mnu(nu, x)
    let theta = theta_corr(nu, x)
    let beta = -0.5f64 * nu * n_pi()
    let sin_alpha = math.sin[f64](x)
    let cos_alpha = math.cos[f64](x)
    let sin_chi = math.sin[f64](beta + theta)
    let cos_chi = math.cos[f64](beta + theta)
    let sin_term = sin_alpha * cos_chi + sin_chi * cos_alpha
    let sin_term_mag = na(sin_alpha * cos_chi) + na(sin_chi * cos_alpha)
    let v = ampl * sin_term
    var er = na(ampl) * n_eps() * sin_term_mag
    er += na(v) * 2.0f64 * n_eps()
    if na(x) > 1.0f64 / n_eps() {
        er = er * 0.5f64 * na(x)
    }
    if na(x) <= 1.0f64 / n_eps() && na(x) > 1.0f64 / 1.4901161193847656e-08f64 {
        er = er * 256.0f64 * na(x) * 1.4901161193847656e-08f64
    }
    ret (v, er)
}

fn knu_scaled_asympx(nu: f64, x: f64) -> (f64, f64) {
    let mu = 4.0f64 * nu * nu
    let mum1 = mu - 1.0f64
    let mum9 = mu - 9.0f64
    let pre = math.sqrt[f64](n_pi() / (2.0f64 * x))
    let r = nu / x
    let v = pre * (1.0f64 + mum1 / (8.0f64 * x) + mum1 * mum9 / (128.0f64 * x * x))
    ret (v, 2.0f64 * n_eps() * na(v) + pre * na(0.1f64 * r * r * r))
}

// the small-x series shared by Yn and Kn: returns (term1, term2, ln_pre1) pieces through the sums
fn small_sums(n: i64, x: f64, sgn_y: f64) -> (f64, f64, f64) {
    let y = 0.25f64 * x * x
    let ln_x_2 = math.log[f64](0.5f64 * x)
    let (lnf, _lfe) = g2.e_lnfact(usize(n - 1i64))
    let ln_pre1 = 0.0f64 - f64(n) * ln_x_2 + lnf
    var sum1 = 1.0f64
    var k_term = 1.0f64
    var k = 1i64
    while k <= n - 1i64 {
        k_term = k_term * (sgn_y * y / (f64(k) * f64(n - k)))
        sum1 += k_term
        k += 1i64
    }
    ret (sum1, ln_pre1, ln_x_2)
}

fn sum2_series(n: i64, x: f64, sgn_y: f64) -> f64 {
    let y = 0.25f64 * x * x
    let ln_x_2 = math.log[f64](0.5f64 * x)
    var yk = 1.0f64
    var k_fact = 1.0f64
    var psi_kp1 = 0.0f64 - n_euler()
    let (psn, _pe) = gs.psi_int(usize(n))
    var npk_fact = g2.fact_val(usize(n))
    var psi_npkp1 = psn + 1.0f64 / f64(n)
    var sum2 = (psi_kp1 + psi_npkp1 - 2.0f64 * ln_x_2) / npk_fact
    var k = 1i64
    while k < 20i64 {
        psi_kp1 += 1.0f64 / f64(k)
        psi_npkp1 += 1.0f64 / f64(n + k)
        k_fact = k_fact * f64(k)
        npk_fact = npk_fact * f64(n + k)
        yk = yk * (sgn_y * y)
        let k_term = yk * (psi_kp1 + psi_npkp1 - 2.0f64 * ln_x_2) / (k_fact * npk_fact)
        sum2 += k_term
        k += 1i64
    }
    ret sum2
}

fn yn_small_x(n: i64, x: f64) -> (f64, f64) {
    let (sum1, ln_pre1, ln_x_2) = small_sums(n, x, 1.0f64)
    let term1 = 0.0f64 - math.exp[f64](ln_pre1) * sum1 / n_pi()
    let pre2 = 0.0f64 - math.exp[f64](f64(n) * ln_x_2) / n_pi()
    var term2 = 0.0f64
    if na(pre2) > 0.0f64 {
        term2 = pre2 * sum2_series(n, x, -1.0f64)
    }
    let v = term1 + term2
    ret (v, n_eps() * (na(ln_pre1) * na(term1) + na(term2)) + 2.0f64 * n_eps() * na(v))
}

fn bessel_yn(n0: i64, x: f64) -> (f64, f64) {
    var n = n0
    var sign = 1.0f64
    if n < 0i64 {
        n = 0i64 - n
        if n % 2i64 == 1i64 { sign = -1.0f64 }
    }
    if n == 0i64 {
        let (v, e) = gj.y0(x)
        ret (v * sign, e)
    }
    if n == 1i64 {
        let (v1, e1) = gj.y1(x)
        ret (v1 * sign, e1)
    }
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 5.0f64 {
        let (v2, e2) = yn_small_x(n, x)
        ret (v2 * sign, e2)
    }
    if n_root3() * x > f64(n) * f64(n) + 1.0f64 {
        let (v3, e3) = ynu_asympx(f64(n), x)
        ret (v3 * sign, e3)
    }
    let two_over_x = 2.0f64 / x
    let (by1, by1e) = gj.y1(x)
    let (bym0, bym0e) = gj.y0(x)
    var bym = bym0
    var by = by1
    var j = 1i64
    while j < n {
        let byp = f64(j) * two_over_x * by - bym
        bym = by
        by = byp
        j += 1i64
    }
    let v4 = sign * by
    ret (v4, na(v4) * (na(by1e / by1) + na(bym0e / bym0)) + 2.0f64 * n_eps() * na(v4))
}

fn kn_small_x_scaled(n: i64, x: f64) -> (f64, f64) {
    let (sum1, ln_pre1, ln_x_2) = small_sums(n, x, -1.0f64)
    let ex = math.exp[f64](x)
    let term1 = 0.5f64 * math.exp[f64](ln_pre1) * sum1
    let pre2 = 0.5f64 * math.exp[f64](f64(n) * ln_x_2)
    var term2 = 0.0f64
    if pre2 > 0.0f64 {
        var sg = 1.0f64
        if n % 2i64 == 1i64 { sg = -1.0f64 }
        term2 = sg * pre2 * sum2_series(n, x, 1.0f64)
    }
    let v = ex * (term1 + term2)
    ret (v, ex * n_eps() * (na(ln_pre1) * na(term1) + na(term2)) + 2.0f64 * n_eps() * na(v))
}

fn kn_scaled(n0: i64, x: f64) -> (f64, f64) {
    var n = n0
    if n < 0i64 { n = 0i64 - n }
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if n == 0i64 {
        let (v, e) = gb.k0_scaled(x)
        ret (v, e)
    }
    if n == 1i64 {
        let (v1, e1) = gb.k1_scaled(x)
        ret (v1, e1)
    }
    if x <= 5.0f64 {
        let (v2, e2) = kn_small_x_scaled(n, x)
        ret (v2, e2)
    }
    if n_root3() * x > 0.25f64 * (f64(n) * f64(n) + 1.0f64) {
        let (v3, e3) = knu_scaled_asympx(f64(n), x)
        ret (v3, e3)
    }
    let two_over_x = 2.0f64 / x
    let (jm1, jm1e) = gb.k0_scaled(x)
    let (jj, jje) = gb.k1_scaled(x)
    var b_jm1 = jm1
    var b_j = jj
    var j = 1i64
    while j < n {
        let b_jp1 = b_jm1 + f64(j) * two_over_x * b_j
        b_jm1 = b_j
        b_j = b_jp1
        j += 1i64
    }
    ret (b_j, f64(n) * (na(b_j) * (na(jm1e / jm1) + na(jje / jj))) + 2.0f64 * n_eps() * na(b_j))
}

fn kn(n: i64, x: f64) -> (f64, f64) {
    let (sv, se) = kn_scaled(n, x)
    let ex = math.exp[f64](0.0f64 - x)
    let v = sv * ex
    ret (v, se * ex + x * n_eps() * na(v))
}

// gsl_sf_bessel_IJ_taylor_e(nu, x, sign = 1, kmax = 50, threshold = eps) for an integer nu >= 2
fn ij_taylor(a: *mem.Arena, nu: f64, x: f64) -> (f64, f64) {
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    let nn = math.floor[f64](nu + 0.5f64)
    let f = nu - nn
    let (pov, poe) = gp.poch(a, nn + 1.0f64, f)
    let (tcv, tce) = g2.e_taylorcoeff(i64(nn), 0.5f64 * x)
    let p = math.pow[f64](0.5f64 * x, f)
    let pre_v = tcv * p / pov
    var pre_e = tce * p / pov
    pre_e += na(pre_v) / pov * poe
    pre_e += 2.0f64 * n_eps() * na(pre_v)
    let y = 0.25f64 * x * x
    var sumk = 1.0f64
    var term = 1.0f64
    var k = 1i64
    while k <= 50i64 {
        term = term * (y / ((nu + f64(k)) * f64(k)))
        sumk += term
        if na(term / sumk) < n_eps() { break }
        k += 1i64
    }
    let sum_e = n_eps() * na(sumk)
    let v = pre_v * sumk
    var er = 0.0f64
    // gsl_sf_multiply_err_e: multiply_e error 2 eps |v| plus the two propagated terms
    er = 2.0f64 * n_eps() * na(v) + na(pre_e * sumk) + na(sum_e * pre_v)
    ret (v, er)
}

fn i_cf1_ser(nu: f64, x: f64) -> f64 {
    var tk = 1.0f64
    var sum = 1.0f64
    var rhok = 0.0f64
    var k = 1i64
    while k < 20000i64 {
        let ak = 0.25f64 * (x / (nu + f64(k))) * x / (nu + f64(k) + 1.0f64)
        rhok = 0.0f64 - ak * (1.0f64 + rhok) / (1.0f64 + ak * (1.0f64 + rhok))
        tk = tk * rhok
        sum += tk
        if na(tk / sum) < n_eps() { break }
        k += 1i64
    }
    ret x / (2.0f64 * (nu + 1.0f64)) * sum
}

fn in_scaled(a: *mem.Arena, n0: i64, x: f64) -> (f64, f64) {
    var n = n0
    if n < 0i64 { n = 0i64 - n }
    let ax = na(x)
    if n == 0i64 {
        let (v, e) = gb.i0_scaled(x)
        ret (v, e)
    }
    if n == 1i64 {
        let (v1, e1) = gb.i1_scaled(x)
        ret (v1, e1)
    }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    var odd_neg = false
    if x < 0.0f64 && n % 2i64 == 1i64 { odd_neg = true }
    if x * x < 10.0f64 * (f64(n) + 1.0f64) / 2.718281828459045235360287471353f64 {
        let ex = math.exp[f64](0.0f64 - ax)
        let (tv, te) = ij_taylor(a, f64(n), ax)
        var v2 = tv * ex
        let e2 = te * ex + 2.0f64 * n_eps() * na(v2)
        if odd_neg { v2 = 0.0f64 - v2 }
        ret (v2, e2)
    }
    if n < 150i64 && ax < 1.0e7f64 {
        let (i0v, i0e) = gb.i0_scaled(ax)
        let rat = i_cf1_ser(f64(n), ax)
        var ikp1 = rat * 1.4916681462400413e-154f64
        var ik = 1.4916681462400413e-154f64
        var k = n
        while k >= 1i64 {
            let ikm1 = ikp1 + 2.0f64 * f64(k) / ax * ik
            ikp1 = ik
            ik = ikm1
            k -= 1i64
        }
        var v3 = i0v * (1.4916681462400413e-154f64 / ik)
        let e3 = i0e * (1.4916681462400413e-154f64 / ik) + 2.0f64 * n_eps() * na(v3)
        if odd_neg { v3 = 0.0f64 - v3 }
        ret (v3, e3)
    }
    ret (0.0f64, 0.0f64)
}

fn in_(a: *mem.Arena, n0: i64, x: f64) -> (f64, f64) {
    var n = n0
    if n < 0i64 { n = 0i64 - n }
    let ax = na(x)
    let (sv, se) = in_scaled(a, n, ax)
    if ax > 7.0978271289338397e+02f64 - 1.0f64 { ret (0.0f64, 0.0f64) }
    let ex = math.exp[f64](ax)
    var v = ex * sv
    let e = ex * se + ax * n_eps() * na(v)
    if x < 0.0f64 && n % 2i64 == 1i64 { v = 0.0f64 - v }
    ret (v, e)
}
