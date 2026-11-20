// R gsl: the conical Legendre functions conicalP_half, conicalP_mhalf, conicalP_0, conicalP_1, conicalP_sph_reg and conicalP_cyl_reg with gsl's error estimates: a port of specfunc/legendre_con.c
// (the hypergeometric representation, the large-x expansion, the Kolbig large-lambda expansions and the two continued fractions). Not here: the large-negative-mu and large-tau Olver
// asymptotics, which only legendre_H3d uses. Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.math.scale as sc
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslerr as ge
use e.algo.stat.gslairy as gy
use e.algo.stat.gslell as gl
use e.algo.stat.gslbj as gj
use e.algo.stat.gslbessel as gb
use e.algo.stat.gslfns as gf

fn k_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn ka(x: f64) -> f64 { ret math.abs[f64](x) }
fn k_sqrt_min() -> f64 { ret 1.4916681462400413e-154f64 }
fn k_sqrt_eps() -> f64 { ret 1.4901161193847656e-08f64 }
fn k_ln2() -> f64 { ret 0.693147180559945309417232121458f64 }
fn k_lnpi() -> f64 { ret 1.14472988584940017414342735135f64 }
fn k_pi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn k_root2opi() -> f64 { ret 0.797884560802865355879892f64 }

fn kmax2(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn acosh_(x: f64) -> f64 {
    let y = x - 1.0f64
    ret sc.log1p(y + math.sqrt[f64](y * (x + 1.0f64)))
}

// gsl_sf_exp_mult_err_e with its overflow and underflow statuses: ok is false where gsl answers an error
fn emult(x: f64, dx: f64, y: f64, dy: f64) -> (f64, f64, bool) {
    if y == 0.0f64 {
        let (v0, e0) = gy.exp_mult_err(x, dx, y, dy)
        ret (v0, e0, true)
    }
    let lnr = x + math.log[f64](ka(y))
    let fast = x < 0.5f64 * 7.0978271289338397e+02f64 && x > 0.5f64 * -7.0839641853226408e+02f64 && ka(y) < 0.8f64 * 1.3407807929942596e+154f64 && ka(y) > 1.2f64 * k_sqrt_min()
    var good = true
    if !fast {
        if lnr > 7.0978271289338397e+02f64 - 0.01f64 { good = false }
        if lnr < -7.0839641853226408e+02f64 + 0.01f64 { good = false }
    }
    let (v, e) = gy.exp_mult_err(x, dx, y, dy)
    ret (v, e, good)
}

// hyperg_2F1_conj_series(aR, aI, c, x): a = aR + i aI, b = aR - i aI
fn conj_series(ar: f64, ai: f64, c: f64, x: f64) -> (f64, f64) {
    var sum_pos = 1.0f64
    var sum_neg = 0.0f64
    var del_pos = 1.0f64
    var del_neg = 0.0f64
    var del = 1.0f64
    var k = 0.0f64
    while true {
        del = del * ((((ar + k) * (ar + k) + ai * ai) / ((k + 1.0f64) * (c + k))) * x)
        if del >= 0.0f64 {
            del_pos = del
            sum_pos += del
        } else {
            del_neg = 0.0f64 - del
            sum_neg -= del
        }
        if k > 30000.0f64 {
            let v1 = sum_pos - sum_neg
            var e1 = del_pos + del_neg
            e1 += 2.0f64 * k_eps() * (sum_pos + sum_neg)
            e1 += 2.0f64 * k_eps() * (2.0f64 * math.sqrt[f64](k) + 1.0f64) * ka(v1)
            ret (v1, e1)
        }
        k += 1.0f64
        if !(ka((del_pos + del_neg) / (sum_pos - sum_neg)) > k_eps()) { break }
    }
    let v = sum_pos - sum_neg
    var e = del_pos + del_neg
    e += 2.0f64 * k_eps() * (sum_pos + sum_neg)
    e += 2.0f64 * k_eps() * (2.0f64 * math.sqrt[f64](k) + 1.0f64) * ka(v)
    ret (v, e)
}

// P^mu_{-1/2 + I tau}(x), -1 < x < 1, the first hypergeometric representation
fn hyperg_a(mu: f64, tau: f64, x: f64) -> (f64, f64) {
    let x2 = x * x
    let err_amp = 1.0f64 + 1.0f64 / (k_eps() + ka(1.0f64 - ka(x)))
    let pre_val = 1.77245385090551602729816748334f64 / math.pow[f64](0.5f64 * math.sqrt[f64](1.0f64 - x2), mu)
    let pre_err = err_amp * k_eps() * (ka(mu) + 1.0f64) * ka(pre_val)
    let (f1v, f1e) = conj_series(0.25f64 - 0.5f64 * mu, 0.5f64 * tau, 0.5f64, x2)
    let (f2v, f2e) = conj_series(0.75f64 - 0.5f64 * mu, 0.5f64 * tau, 1.5f64, x2)
    let (g1v, g1e) = gc.lngamma_complex_lnr(0.75f64 - 0.5f64 * mu, -0.5f64 * tau)
    let (g2v, g2e) = gc.lngamma_complex_lnr(0.25f64 - 0.5f64 * mu, -0.5f64 * tau)
    let (p1v, p1e, _s1) = gc.exp_err(-2.0f64 * g1v, 2.0f64 * g1e)
    let (p2v0, p2e0, _s2) = gc.exp_err(-2.0f64 * g2v, 2.0f64 * g2e)
    let p2v = p2v0 * (-2.0f64 * x)
    var p2e = p2e0 * (2.0f64 * ka(x))
    p2e += k_eps() * ka(p2v)
    let t1v = p1v * f1v
    let t1e = ka(p1v) * f1e + p1e * ka(f1v)
    let t2v = p2v * f2v
    let t2e = ka(p2v) * f2e + p2e * ka(f2v)
    let v = pre_val * (t1v + t2v)
    var e = pre_val * (t1e + t2e)
    e += pre_err * ka(t1v + t2v)
    e += 2.0f64 * k_eps() * ka(v)
    ret (v, e)
}

// 2F1(1/4 - mu/2 - I tau/2, 3/4 - mu/2 - I tau/2, 1 - I tau, y): (re, im)
fn hyperg_large_x(mu: f64, tau: f64, y: f64) -> (f64, f64) {
    let re_a = 0.25f64 - 0.5f64 * mu
    let re_b = 0.75f64 - 0.5f64 * mu
    let re_c = 1.0f64
    let im_a = -0.5f64 * tau
    let im_b = -0.5f64 * tau
    let im_c = 0.0f64 - tau
    var re_sum = 1.0f64
    var im_sum = 0.0f64
    var re_term = 1.0f64
    var im_term = 0.0f64
    var k = 1i64
    while k <= 1000i64 {
        let kf = f64(k)
        let re_ak = re_a + kf - 1.0f64
        let re_bk = re_b + kf - 1.0f64
        let re_ck = re_c + kf - 1.0f64
        let den = re_ck * re_ck + im_c * im_c
        let re_m = ((re_ak * re_bk - im_a * im_b) * re_ck + im_c * (im_a * re_bk + re_ak * im_b)) / den
        let im_m = ((im_a * re_bk + re_ak * im_b) * re_ck - im_c * (re_ak * re_bk - im_a * im_b)) / den
        let re_tmp = re_m * re_term - im_m * im_term
        let im_tmp = im_m * re_term + re_m * im_term
        let asum = ka(re_sum) + ka(im_sum)
        re_term = y / kf * re_tmp
        im_term = y / kf * im_tmp
        if ka(re_term / asum) < k_eps() && ka(im_term / asum) < k_eps() { break }
        re_sum += re_term
        im_sum += im_term
        k += 1i64
    }
    ret (re_sum, im_sum)
}

// gsl_sf_conicalP_large_x_e: (value, error, ln_multiplier)
fn large_x(mu: f64, tau: f64, x: f64) -> (f64, f64, f64) {
    var y = 0.0f64
    if x < 0.5f64 * 1.3407807929942596e+154f64 { y = 1.0f64 / (x * x) }
    let (re_f, im_f) = hyperg_large_x(mu, tau, y)
    let (lnr_v, lnr_e) = gc.lngamma_complex_lnr(0.0f64, tau)
    let (lds_v, lds_e) = gc.lngamma_complex_lnr(0.5f64 - mu, tau)
    var go: [2]f64 = zero
    var gt: [2]f64 = zero
    gf.lngamma_complex(0.0f64, tau, go[0usize..2usize], gt[0usize..2usize])
    let th_num = go[1usize]
    gf.lngamma_complex(0.5f64 - mu, tau, go[0usize..2usize], gt[0usize..2usize])
    let th_den = go[1usize]
    let angle = th_num - th_den + math.atan2[f64](im_f, re_f)
    let lnx = math.log[f64](x)
    let lnxp1 = math.log[f64](x + 1.0f64)
    let lnxm1 = math.log[f64](x - 1.0f64)
    let lnpre_const = 0.5f64 * k_ln2() - 0.5f64 * k_lnpi()
    let lnpre_comm = (mu - 0.5f64) * lnx - 0.5f64 * mu * (lnxp1 + lnxm1)
    var lnpre_err = k_eps() * (0.5f64 * k_ln2() + 0.5f64 * k_lnpi())
    lnpre_err += k_eps() * ka((mu - 0.5f64) * lnx)
    lnpre_err += k_eps() * ka(0.5f64 * mu) * (ka(lnxp1) + ka(lnxm1))
    let (cv, ce) = ge.e_cos(angle + tau * (math.log[f64](x) + k_ln2()))
    if cv == 0.0f64 { ret (0.0f64, 0.0f64, 0.0f64) }
    let ln_ff_val = 0.5f64 * math.log[f64](re_f * re_f + im_f * im_f) + lnr_v - lds_v
    let ln_ff_err = lnr_e + lds_e + k_eps() * ka(ln_ff_val)
    let lnnoc_val = lnpre_const + lnpre_comm + ln_ff_val
    let lnnoc_err = lnpre_err + ln_ff_err + k_eps() * ka(lnnoc_val)
    let (v, e, fine) = emult(lnnoc_val, lnnoc_err, cv, ce)
    if fine { ret (v, e, 0.0f64) }
    ret (cv, ce + 2.0f64 * k_eps() * ka(cv), lnnoc_val)
}

// V0, V1 of Kolbig for m = 0
fn p0_v(t: f64, f: f64, tau: f64, sgn: f64) -> (f64, f64) {
    var c: [8]f64 = zero
    var tt: [8]f64 = zero
    var h: [8]f64 = zero
    var v: [12]f64 = zero
    tt[0usize] = 1.0f64
    h[0usize] = 1.0f64
    v[0usize] = 1.0f64
    var i = 1usize
    while i <= 7usize {
        tt[i] = tt[i - 1usize] * t
        h[i] = h[i - 1usize] * (t * f)
        i += 1usize
    }
    i = 1usize
    while i <= 11usize {
        v[i] = v[i - 1usize] * tau
        i += 1usize
    }
    c[0usize] = 1.0f64
    c[1usize] = (h[1usize] - 1.0f64) / (8.0f64 * tt[1usize])
    c[2usize] = (9.0f64 * h[2usize] + 6.0f64 * h[1usize] - 15.0f64 - sgn * 8.0f64 * tt[2usize]) / (128.0f64 * tt[2usize])
    c[3usize] = 5.0f64 * (15.0f64 * h[3usize] + 27.0f64 * h[2usize] + 21.0f64 * h[1usize] - 63.0f64 - sgn * tt[2usize] * (16.0f64 * h[1usize] + 24.0f64)) / (1024.0f64 * tt[3usize])
    c[4usize] = 7.0f64 * (525.0f64 * h[4usize] + 1500.0f64 * h[3usize] + 2430.0f64 * h[2usize] + 1980.0f64 * h[1usize] - 6435.0f64 + 192.0f64 * tt[4usize] - sgn * tt[2usize] * (720.0f64 * h[2usize] + 1600.0f64 * h[1usize] + 2160.0f64)) / (32768.0f64 * tt[4usize])
    c[5usize] = 21.0f64 * (2835.0f64 * h[5usize] + 11025.0f64 * h[4usize] + 24750.0f64 * h[3usize] + 38610.0f64 * h[2usize] + 32175.0f64 * h[1usize] - 109395.0f64 + tt[4usize] * (1984.0f64 * h[1usize] + 4032.0f64) - sgn * tt[2usize] * (4800.0f64 * h[3usize] + 15120.0f64 * h[2usize] + 26400.0f64 * h[1usize] + 34320.0f64)) / (262144.0f64 * tt[5usize])
    c[6usize] = 11.0f64 * (218295.0f64 * h[6usize] + 1071630.0f64 * h[5usize] + 3009825.0f64 * h[4usize] + 6142500.0f64 * h[3usize] + 9398025.0f64 * h[2usize] + 7936110.0f64 * h[1usize] - 27776385.0f64 + tt[4usize] * (254016.0f64 * h[2usize] + 749952.0f64 * h[1usize] + 1100736.0f64) - sgn * tt[2usize] * (441000.0f64 * h[4usize] + 1814400.0f64 * h[3usize] + 4127760.0f64 * h[2usize] + 6552000.0f64 * h[1usize] + 8353800.0f64 + 31232.0f64 * tt[4usize])) / (4194304.0f64 * tt[6usize])
    let v0 = c[0usize] + (-4.0f64 * c[3usize] / tt[1usize] + c[4usize]) / v[4usize] + (-192.0f64 * c[5usize] / tt[3usize] + 144.0f64 * c[6usize] / tt[2usize]) / v[8usize] + sgn * (-c[2usize] / v[2usize] + (-24.0f64 * c[4usize] / tt[2usize] + 12.0f64 * c[5usize] / tt[1usize] - c[6usize]) / v[6usize] + (-1920.0f64 * c[6usize] / tt[4usize]) / v[10usize])
    let v1 = c[1usize] / v[1usize] + (8.0f64 * (c[3usize] / tt[2usize] - c[4usize] / tt[1usize]) + c[5usize]) / v[5usize] + (384.0f64 * c[5usize] / tt[4usize] - 768.0f64 * c[6usize] / tt[3usize]) / v[9usize] + sgn * ((2.0f64 * c[2usize] / tt[1usize] - c[3usize]) / v[3usize] + (48.0f64 * c[4usize] / tt[3usize] - 72.0f64 * c[5usize] / tt[2usize] + 18.0f64 * c[6usize] / tt[1usize]) / v[7usize] + (3840.0f64 * c[6usize] / tt[5usize]) / v[11usize])
    ret (v0, v1)
}

// V0, V1 of Kolbig for m = 1
fn p1_v(t: f64, f: f64, tau: f64, sgn: f64) -> (f64, f64) {
    var c: [8]f64 = zero
    var tt: [8]f64 = zero
    var h: [8]f64 = zero
    var v: [12]f64 = zero
    tt[0usize] = 1.0f64
    h[0usize] = 1.0f64
    v[0usize] = 1.0f64
    var i = 1usize
    while i <= 7usize {
        tt[i] = tt[i - 1usize] * t
        h[i] = h[i - 1usize] * (t * f)
        i += 1usize
    }
    i = 1usize
    while i <= 11usize {
        v[i] = v[i - 1usize] * tau
        i += 1usize
    }
    let cm1 = -1.0f64
    c[0usize] = 3.0f64 * (1.0f64 - h[1usize]) / (8.0f64 * tt[1usize])
    c[1usize] = (-15.0f64 * h[2usize] + 6.0f64 * h[1usize] + 9.0f64 + sgn * 8.0f64 * tt[2usize]) / (128.0f64 * tt[2usize])
    c[2usize] = 3.0f64 * (-35.0f64 * h[3usize] - 15.0f64 * h[2usize] + 15.0f64 * h[1usize] + 35.0f64 + sgn * tt[2usize] * (32.0f64 * h[1usize] + 8.0f64)) / (1024.0f64 * tt[3usize])
    c[3usize] = (-4725.0f64 * h[4usize] - 6300.0f64 * h[3usize] - 3150.0f64 * h[2usize] + 3780.0f64 * h[1usize] + 10395.0f64 - 1216.0f64 * tt[4usize] + sgn * tt[2usize] * (6000.0f64 * h[2usize] + 5760.0f64 * h[1usize] + 1680.0f64)) / (32768.0f64 * tt[4usize])
    c[4usize] = 7.0f64 * (-10395.0f64 * h[5usize] - 23625.0f64 * h[4usize] - 28350.0f64 * h[3usize] - 14850.0f64 * h[2usize] + 19305.0f64 * h[1usize] + 57915.0f64 - tt[4usize] * (6336.0f64 * h[1usize] + 6080.0f64) + sgn * tt[2usize] * (16800.0f64 * h[3usize] + 30000.0f64 * h[2usize] + 25920.0f64 * h[1usize] + 7920.0f64)) / (262144.0f64 * tt[5usize])
    c[5usize] = (-2837835.0f64 * h[6usize] - 9168390.0f64 * h[5usize] - 16372125.0f64 * h[4usize] - 18918900.0f64 * h[3usize] - 10135125.0f64 * h[2usize] + 13783770.0f64 * h[1usize] + 43648605.0f64 - tt[4usize] * (3044160.0f64 * h[2usize] + 5588352.0f64 * h[1usize] + 4213440.0f64) + sgn * tt[2usize] * (5556600.0f64 * h[4usize] + 14817600.0f64 * h[3usize] + 20790000.0f64 * h[2usize] + 17297280.0f64 * h[1usize] + 5405400.0f64 + 323072.0f64 * tt[4usize])) / (4194304.0f64 * tt[6usize])
    c[6usize] = 0.0f64
    let v0 = c[0usize] + (-4.0f64 * c[3usize] / tt[1usize] + c[4usize]) / v[4usize] + (-192.0f64 * c[5usize] / tt[3usize] + 144.0f64 * c[6usize] / tt[2usize]) / v[8usize] + sgn * (-c[2usize] / v[2usize] + (-24.0f64 * c[4usize] / tt[2usize] + 12.0f64 * c[5usize] / tt[1usize] - c[6usize]) / v[6usize])
    let v1 = c[1usize] / v[1usize] + (8.0f64 * (c[3usize] / tt[2usize] - c[4usize] / tt[1usize]) + c[5usize]) / v[5usize] + (384.0f64 * c[5usize] / tt[4usize] - 768.0f64 * c[6usize] / tt[3usize]) / v[9usize] + sgn * (cm1 * v[1usize] + (2.0f64 * c[2usize] / tt[1usize] - c[3usize]) / v[3usize] + (48.0f64 * c[4usize] / tt[3usize] - 72.0f64 * c[5usize] / tt[2usize] + 18.0f64 * c[6usize] / tt[1usize]) / v[7usize])
    ret (v0, v1)
}

// the large-x branch shared by conicalP_0 and conicalP_1
fn via_large_x(mu: f64, lam: f64, x: f64) -> (f64, f64) {
    let (pv, pe, lm) = large_x(mu, lam, x)
    let (v, e, _fine) = emult(lm, 2.0f64 * k_eps() * ka(lm), pv, pe)
    ret (v, e)
}

fn con_half(lam: f64, x: f64) -> (f64, f64) {
    if x <= -1.0f64 { ret (0.0f64, 0.0f64) }
    if x < 1.0f64 {
        let err_amp = 1.0f64 + 1.0f64 / (k_eps() + ka(1.0f64 - ka(x)))
        let ac = math.acos[f64](x)
        let den = math.sqrt[f64](math.sqrt[f64](1.0f64 - x) * math.sqrt[f64](1.0f64 + x))
        let v = k_root2opi() / den * sc.cosh(ac * lam)
        var e = err_amp * 3.0f64 * k_eps() * ka(v)
        e = e * (ka(ac * lam) + 1.0f64)
        ret (v, e)
    }
    if x == 1.0f64 { ret (0.0f64, 0.0f64) }
    let err_amp = 1.0f64 + 1.0f64 / (k_eps() + ka(1.0f64 - ka(x)))
    let sq_term = math.sqrt[f64](x - 1.0f64) * math.sqrt[f64](x + 1.0f64)
    let ln_term = math.log[f64](x + sq_term)
    let den = math.sqrt[f64](sq_term)
    let carg_val = lam * ln_term
    let carg_err = 2.0f64 * k_eps() * ka(carg_val)
    let (c0, c1) = ge.e_cos(carg_val)
    let cos_err = c1 + ka(math.sin[f64](carg_val) * carg_err) + k_eps() * ka(c0)
    let v = k_root2opi() / den * c0
    var e = err_amp * k_root2opi() / den * cos_err
    e += 4.0f64 * k_eps() * ka(v)
    ret (v, e)
}

fn con_mhalf(lam: f64, x: f64) -> (f64, f64) {
    if x <= -1.0f64 { ret (0.0f64, 0.0f64) }
    if x < 1.0f64 {
        let ac = math.acos[f64](x)
        let den = math.sqrt[f64](math.sqrt[f64](1.0f64 - x) * math.sqrt[f64](1.0f64 + x))
        let arg = ac * lam
        let err_amp = 1.0f64 + 1.0f64 / (k_eps() + ka(1.0f64 - ka(x)))
        if ka(arg) < k_sqrt_eps() {
            let v = k_root2opi() / den * ac
            var e = 2.0f64 * k_eps() * ka(v)
            e = e * err_amp
            ret (v, e)
        }
        let v = k_root2opi() / (den * lam) * sc.sinh(arg)
        var e = k_eps() * (ka(arg) + 1.0f64) * ka(v)
        e = e * err_amp
        e += 2.0f64 * k_eps() * ka(v)
        ret (v, e)
    }
    if x == 1.0f64 { ret (0.0f64, 0.0f64) }
    let sq_term = math.sqrt[f64](x - 1.0f64) * math.sqrt[f64](x + 1.0f64)
    let ln_term = math.log[f64](x + sq_term)
    let den = math.sqrt[f64](sq_term)
    let arg_val = lam * ln_term
    let arg_err = 2.0f64 * k_eps() * ka(arg_val)
    if arg_val < k_sqrt_eps() {
        let v = k_root2opi() / den * ln_term
        ret (v, 2.0f64 * k_eps() * ka(v))
    }
    let (s0, s1) = ge.e_sin(arg_val)
    let sin_err = s1 + ka(math.cos[f64](arg_val) * arg_err) + k_eps() * ka(s0)
    let v = k_root2opi() / (den * lam) * s0
    var e = k_root2opi() / ka(den * lam) * sin_err
    e += 3.0f64 * k_eps() * ka(v)
    ret (v, e)
}

fn con_0(lam: f64, x: f64) -> (f64, f64) {
    if x <= -1.0f64 { ret (0.0f64, 0.0f64) }
    if x == 1.0f64 { ret (1.0f64, 0.0f64) }
    if lam == 0.0f64 {
        if x < 1.0f64 {
            let th = math.acos[f64](x)
            let s = math.sin[f64](0.5f64 * th)
            let (kv, ke) = gl.kcomp(s, 0usize)
            let v = 2.0f64 / k_pi() * kv
            var e = 2.0f64 / k_pi() * ke
            e += 2.0f64 * k_eps() * ka(v)
            ret (v, e)
        }
        let xi = acosh_(x)
        let c = sc.cosh(0.5f64 * xi)
        let t = sc.tanh(0.5f64 * xi)
        let (kv2, ke2) = gl.kcomp(t, 0usize)
        let v = 2.0f64 / k_pi() / c * kv2
        var e = 2.0f64 / k_pi() / c * ke2
        e += 2.0f64 * k_eps() * ka(v)
        ret (v, e)
    }
    if (x <= 0.0f64 && lam < 1000.0f64) || (x < 0.1f64 && lam < 17.0f64) || (x < 0.2f64 && lam < 5.0f64) {
        let (av, ae) = hyperg_a(0.0f64, lam, x)
        ret (av, ae)
    }
    if (x <= 0.2f64 && lam < 17.0f64) || (x <= 1.5f64 && lam < 20.0f64) {
        let (fv, fe) = conj_series(0.5f64, lam, 1.0f64, (1.0f64 - x) / 2.0f64)
        ret (fv, fe)
    }
    if 1.5f64 < x && lam < kmax2(x, 20.0f64) {
        let (lv, le) = via_large_x(0.0f64, lam, x)
        ret (lv, le)
    }
    if x < 1.0f64 {
        let th = math.acos[f64](x)
        let sth = math.sqrt[f64](1.0f64 - x * x)
        let (i0v, i0e) = gb.i0_scaled(th * lam)
        let (i1v, i1e) = gb.i1_scaled(th * lam)
        let (v0, v1) = p0_v(th, x / sth, lam, -1.0f64)
        let bessterm = v0 * i0v + v1 * i1v
        let besserr = ka(v0) * i0e + ka(v1) * i1e
        let arg1 = th * lam
        let sqts = math.sqrt[f64](th / sth)
        let (rv, re, _fine) = emult(arg1, 4.0f64 * k_eps() * ka(arg1), sqts * bessterm, sqts * besserr)
        ret (rv, re)
    }
    let sh = math.sqrt[f64](x - 1.0f64) * math.sqrt[f64](x + 1.0f64)
    let xi = math.log[f64](x + sh)
    let (j0v, j0e) = gj.j0(xi * lam)
    let (j1v, j1e) = gj.j1(xi * lam)
    let (v0, v1) = p0_v(xi, x / sh, lam, 1.0f64)
    let bessterm = v0 * j0v + v1 * j1v
    let besserr = ka(v0) * j0e + ka(v1) * j1e
    let pre_val = math.sqrt[f64](xi / sh)
    let pre_err = 2.0f64 * ka(pre_val)
    let v = pre_val * bessterm
    var e = pre_val * besserr
    e += pre_err * ka(bessterm)
    e += 2.0f64 * k_eps() * ka(v)
    ret (v, e)
}

fn con_1(lam: f64, x: f64) -> (f64, f64) {
    if x <= -1.0f64 { ret (0.0f64, 0.0f64) }
    if lam == 0.0f64 {
        if x == 1.0f64 { ret (0.0f64, 0.0f64) }
        if x < 1.0f64 {
            if 1.0f64 - x < k_sqrt_eps() {
                let err_amp = kmax2(1.0f64, 1.0f64 / (k_eps() + ka(1.0f64 - x)))
                let v = 0.25f64 / 1.4142135623730950488f64 * math.sqrt[f64](1.0f64 - x) * (1.0f64 + 5.0f64 / 16.0f64 * (1.0f64 - x))
                ret (v, err_amp * 3.0f64 * k_eps() * ka(v))
            }
            let th = math.acos[f64](x)
            let s = math.sin[f64](0.5f64 * th)
            let c2 = 1.0f64 - s * s
            let sth = math.sin[f64](th)
            let pre = 2.0f64 / (k_pi() * sth)
            let (kv, ke) = gl.kcomp(s, 0usize)
            let (ev, ee) = gl.ecomp(s, 0usize)
            let v = pre * (ev - c2 * kv)
            var e = pre * (ee + ka(c2) * ke)
            e += 2.0f64 * k_eps() * ka(v)
            ret (v, e)
        }
        if x - 1.0f64 < k_sqrt_eps() {
            let err_amp = kmax2(1.0f64, 1.0f64 / (k_eps() + ka(1.0f64 - x)))
            let v = -0.25f64 / 1.4142135623730950488f64 * math.sqrt[f64](x - 1.0f64) * (1.0f64 - 5.0f64 / 16.0f64 * (x - 1.0f64))
            ret (v, err_amp * 3.0f64 * k_eps() * ka(v))
        }
        let xi = acosh_(x)
        let c = sc.cosh(0.5f64 * xi)
        let t = sc.tanh(0.5f64 * xi)
        let sxi = sc.sinh(xi)
        let pre = 2.0f64 / (k_pi() * sxi) * c
        let (kv2, ke2) = gl.kcomp(t, 0usize)
        let (ev2, ee2) = gl.ecomp(t, 0usize)
        let v = pre * (ev2 - kv2)
        var e = pre * (ee2 + ke2)
        e += 2.0f64 * k_eps() * ka(v)
        ret (v, e)
    }
    if (x <= 0.0f64 && lam < 1000.0f64) || (x < 0.1f64 && lam < 17.0f64) || (x < 0.2f64 && lam < 5.0f64) {
        let (av, ae) = hyperg_a(1.0f64, lam, x)
        ret (av, ae)
    }
    if (x <= 0.2f64 && lam < 17.0f64) || (x < 1.5f64 && lam < 20.0f64) {
        let arg = ka(x * x - 1.0f64)
        var sgn = 1.0f64
        if 1.0f64 - x < 0.0f64 { sgn = -1.0f64 }
        let pre = 0.5f64 * (lam * lam + 0.25f64) * sgn * math.sqrt[f64](arg)
        let (fv, fe) = conj_series(1.5f64, lam, 2.0f64, (1.0f64 - x) / 2.0f64)
        let v = pre * fv
        var e = ka(pre) * fe
        e += 2.0f64 * k_eps() * ka(v)
        ret (v, e)
    }
    if 1.5f64 <= x && lam < kmax2(x, 20.0f64) {
        let (lv, le) = via_large_x(1.0f64, lam, x)
        ret (lv, le)
    }
    if x < 1.0f64 {
        let sqrt_1mx = math.sqrt[f64](1.0f64 - x)
        let sqrt_1px = math.sqrt[f64](1.0f64 + x)
        let th = math.acos[f64](x)
        let sth = sqrt_1mx * sqrt_1px
        let (i0v, i0e) = gb.i0_scaled(th * lam)
        let (i1v, i1e) = gb.i1_scaled(th * lam)
        let (v0, v1) = p1_v(th, x / sth, lam, -1.0f64)
        let bessterm = v0 * i0v + v1 * i1v
        let besserr = ka(v0) * i0e + ka(v1) * i1e + 2.0f64 * k_eps() * ka(v0 * i0v) + 2.0f64 * k_eps() * ka(v1 * i1v)
        let arg1 = th * lam
        let sqts = math.sqrt[f64](th / sth)
        let (rv, re, _fine) = emult(arg1, 2.0f64 * k_eps() * ka(arg1), sqts * bessterm, sqts * besserr)
        ret (rv, re * (1.0f64 / sqrt_1mx))
    }
    let sqrt_xm1 = math.sqrt[f64](x - 1.0f64)
    let sqrt_xp1 = math.sqrt[f64](x + 1.0f64)
    let sh = sqrt_xm1 * sqrt_xp1
    let xi = math.log[f64](x + sh)
    let xi_lam = xi * lam
    let (j0v, j0e) = gj.j0(xi_lam)
    let (j1v, j1e) = gj.j1(xi_lam)
    let (v0, v1) = p1_v(xi, x / sh, lam, 1.0f64)
    let bessterm = v0 * j0v + v1 * j1v
    let besserr = ka(v0) * j0e + ka(v1) * j1e + 512.0f64 * 2.0f64 * k_eps() * ka(v0 * j0v) + 512.0f64 * 2.0f64 * k_eps() * ka(v1 * j1v) + k_eps() * ka(xi_lam * v0 * j1v) + k_eps() * ka(xi_lam * v1 * j0v)
    let pre = math.sqrt[f64](xi / sh)
    let v = pre * bessterm
    var e = pre * besserr * sqrt_xp1 / sqrt_xm1
    e += 4.0f64 * k_eps() * ka(v)
    ret (v, e)
}

// continued fraction for f_{ell+1}/f_ell, f_ell = P^{-mu-ell}_{-1/2 + I tau}(x), x < 1: (value, error)
fn negmu_xlt1_cf1(mu: f64, ell: i64, tau: f64, x: f64) -> (f64, f64) {
    let big = 1.3407807929942596e+154f64
    let lf = f64(ell)
    let xi = x / (math.sqrt[f64](1.0f64 - x) * math.sqrt[f64](1.0f64 + x))
    var anm2 = 1.0f64
    var bnm2 = 0.0f64
    var anm1 = 0.0f64
    var bnm1 = 1.0f64
    let a1 = 1.0f64
    let b1 = 2.0f64 * (mu + lf + 1.0f64) * xi
    var an = b1 * anm1 + a1 * anm2
    var bn = b1 * bnm1 + a1 * bnm2
    var fn_ = an / bn
    var n = 1i64
    while n < 5000i64 {
        n += 1i64
        let nf = f64(n)
        anm2 = anm1
        bnm2 = bnm1
        anm1 = an
        bnm1 = bn
        let a_n = tau * tau + (mu - 0.5f64 + lf + nf) * (mu - 0.5f64 + lf + nf)
        let b_n = 2.0f64 * (lf + mu + nf) * xi
        an = b_n * anm1 + a_n * anm2
        bn = b_n * bnm1 + a_n * bnm2
        if ka(an) > big || ka(bn) > big {
            an = an / big
            bn = bn / big
            anm1 = anm1 / big
            bnm1 = bnm1 / big
            anm2 = anm2 / big
            bnm2 = bnm2 / big
        }
        let old_fn = fn_
        fn_ = an / bn
        let del = old_fn / fn_
        if ka(del - 1.0f64) < 2.0f64 * k_eps() { break }
    }
    ret (fn_, 4.0f64 * k_eps() * (math.sqrt[f64](f64(n)) + 1.0f64) * ka(fn_))
}

// the same for x >= 1, by Gautschi's Euler-equivalent series
fn negmu_xgt1_cf1(mu: f64, ell: i64, tau: f64, x: f64) -> (f64, f64) {
    let lf = f64(ell)
    let gamma = 1.0f64 - 1.0f64 / (x * x)
    let pre = math.sqrt[f64](x - 1.0f64) * math.sqrt[f64](x + 1.0f64) / (x * (2.0f64 * (lf + mu + 1.0f64)))
    var tk = 1.0f64
    var sum = 1.0f64
    var rhok = 0.0f64
    var k = 1i64
    while k < 20000i64 {
        let kf = f64(k)
        let tlk = 2.0f64 * (lf + mu + kf)
        let l1k = lf + mu - 0.5f64 + 1.0f64 + kf
        let ak = -(tau * tau + l1k * l1k) / (tlk * (tlk + 2.0f64)) * gamma
        rhok = -ak * (1.0f64 + rhok) / (1.0f64 + ak * (1.0f64 + rhok))
        tk = tk * rhok
        sum += tk
        if ka(tk / sum) < k_eps() { break }
        k += 1i64
    }
    var e = ka(pre * tk)
    e += 2.0f64 * k_eps() * (math.sqrt[f64](f64(k)) + 1.0f64) * ka(pre * sum)
    ret (pre * sum, e)
}

fn con_sph_reg(l: i64, lam: f64, x: f64) -> (f64, f64) {
    if x <= -1.0f64 || l < -1i64 { ret (0.0f64, 0.0f64) }
    if l == -1i64 {
        let (hv, he) = con_half(lam, x)
        ret (hv, he)
    }
    if l == 0i64 {
        let (mv, me) = con_mhalf(lam, x)
        ret (mv, me)
    }
    if x == 1.0f64 { ret (0.0f64, 0.0f64) }
    let lf = f64(l)
    if x < 0.0f64 {
        let c = 1.0f64 / math.sqrt[f64](1.0f64 - x * x)
        let (r0, _e0) = con_half(lam, x)
        let (r1, _e1) = con_mhalf(lam, x)
        var pellm1 = r0
        var pell = r1
        var ell = 0i64
        while ell < l {
            let ef = f64(ell)
            let d = (ef + 1.0f64) * (ef + 1.0f64) + lam * lam
            let pellp1 = (pellm1 - (2.0f64 * ef + 1.0f64) * c * x * pell) / d
            pellm1 = pell
            pell = pellp1
            ell += 1i64
        }
        var e = (0.5f64 * lf + 1.0f64) * k_eps() * ka(pell)
        e += k_eps() * lf * ka(pell)
        ret (pell, e)
    }
    if x < 1.0f64 {
        let xi = x / (math.sqrt[f64](1.0f64 - x) * math.sqrt[f64](1.0f64 + x))
        let (rv, re) = negmu_xlt1_cf1(0.5f64, l, lam, x)
        let (phv, phe) = con_half(lam, x)
        var pellp1 = rv * k_sqrt_min()
        var pell = k_sqrt_min()
        var ell = l
        while ell >= 0i64 {
            let ef = f64(ell)
            let d = (ef + 1.0f64) * (ef + 1.0f64) + lam * lam
            let pellm1 = (2.0f64 * ef + 1.0f64) * xi * pell + d * pellp1
            pellp1 = pell
            pell = pellm1
            ell -= 1i64
        }
        let v = k_sqrt_min() * phv / pell
        var e = k_sqrt_min() * phe / ka(pell)
        e += ka(re / rv) * (lf + 1.0f64) * ka(v)
        e += 2.0f64 * k_eps() * ka(v)
        ret (v, e)
    }
    let xi = x / math.sqrt[f64]((x - 1.0f64) * (x + 1.0f64))
    let (rv, re) = negmu_xgt1_cf1(0.5f64, l, lam, x)
    var pellp1 = rv * k_sqrt_min()
    var pell = k_sqrt_min()
    var ell = l
    while ell >= 0i64 {
        let ef = f64(ell)
        let d = (ef + 1.0f64) * (ef + 1.0f64) + lam * lam
        let pellm1 = (2.0f64 * ef + 1.0f64) * xi * pell - d * pellp1
        pellp1 = pell
        pell = pellm1
        ell -= 1i64
    }
    if ka(pell) > ka(pellp1) {
        let (phv, phe) = con_half(lam, x)
        let v = k_sqrt_min() * phv / pell
        var e = 2.0f64 * k_sqrt_min() * phe / ka(pell)
        e += 2.0f64 * ka(re / rv) * (lf + 1.0f64) * ka(v)
        e += 2.0f64 * k_eps() * ka(v)
        ret (v, e)
    }
    let (pmv, pme) = con_mhalf(lam, x)
    let v = k_sqrt_min() * pmv / pellp1
    var e = 2.0f64 * k_sqrt_min() * pme / ka(pellp1)
    e += 2.0f64 * ka(re / rv) * (lf + 1.0f64) * ka(v)
    e += 2.0f64 * k_eps() * ka(v)
    ret (v, e)
}

fn con_cyl_reg(m: i64, lam: f64, x: f64) -> (f64, f64) {
    if x <= -1.0f64 || m < -1i64 { ret (0.0f64, 0.0f64) }
    if m == -1i64 {
        let (v1, e1) = con_1(lam, x)
        ret (v1, e1)
    }
    if m == 0i64 {
        let (v0, e0) = con_0(lam, x)
        ret (v0, e0)
    }
    if x == 1.0f64 { ret (0.0f64, 0.0f64) }
    let mf = f64(m)
    if x < 0.0f64 {
        let c = 1.0f64 / math.sqrt[f64](1.0f64 - x * x)
        let (r0, _e0) = con_1(lam, x)
        let (r1, _e1) = con_0(lam, x)
        var pkm1 = r0
        var pk = r1
        var k = 0i64
        while k < m {
            let kf = f64(k)
            let d = (kf + 0.5f64) * (kf + 0.5f64) + lam * lam
            let pkp1 = (pkm1 - 2.0f64 * kf * c * x * pk) / d
            pkm1 = pk
            pk = pkp1
            k += 1i64
        }
        let e = (mf + 2.0f64) * k_eps() * ka(pk) + 2.0f64 * k_eps() * ka(pk)
        ret (pk, e)
    }
    if x < 1.0f64 {
        let xi = x / (math.sqrt[f64](1.0f64 - x) * math.sqrt[f64](1.0f64 + x))
        let (rv, re) = negmu_xlt1_cf1(0.0f64, m, lam, x)
        let (p0v, p0e) = con_0(lam, x)
        var pkp1 = rv * k_sqrt_min()
        var pk = k_sqrt_min()
        var k = m
        while k > 0i64 {
            let kf = f64(k)
            let d = (kf + 0.5f64) * (kf + 0.5f64) + lam * lam
            let pkm1 = 2.0f64 * kf * xi * pk + d * pkp1
            pkp1 = pk
            pk = pkm1
            k -= 1i64
        }
        let v = k_sqrt_min() * p0v / pk
        var e = 2.0f64 * k_sqrt_min() * p0e / ka(pk)
        e += 2.0f64 * ka(re / rv) * (mf + 1.0f64) * ka(v)
        e += 2.0f64 * k_eps() * ka(v)
        ret (v, e)
    }
    let xi = x / math.sqrt[f64]((x - 1.0f64) * (x + 1.0f64))
    let (rv, re) = negmu_xgt1_cf1(0.0f64, m, lam, x)
    var pkp1 = rv * k_sqrt_min()
    var pk = k_sqrt_min()
    var k = m
    while k > -1i64 {
        let kf = f64(k)
        let d = (kf + 0.5f64) * (kf + 0.5f64) + lam * lam
        let pkm1 = 2.0f64 * kf * xi * pk - d * pkp1
        pkp1 = pk
        pk = pkm1
        k -= 1i64
    }
    if ka(pk) > ka(pkp1) {
        let (p1v, p1e) = con_1(lam, x)
        let v = k_sqrt_min() * p1v / pk
        var e = 2.0f64 * k_sqrt_min() * p1e / ka(pk)
        e += 2.0f64 * ka(re / rv) * (mf + 2.0f64) * ka(v)
        e += 2.0f64 * k_eps() * ka(v)
        ret (v, e)
    }
    let (p0v, p0e) = con_0(lam, x)
    let v = k_sqrt_min() * p0v / pkp1
    var e = 2.0f64 * k_sqrt_min() * p0e / ka(pkp1)
    e += 2.0f64 * ka(re / rv) * (mf + 2.0f64) * ka(v)
    e += 2.0f64 * k_eps() * ka(v)
    ret (v, e)
}
