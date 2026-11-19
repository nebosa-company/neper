// R gsl: the Coulomb wave functions, a port of GSL specfunc/coulomb.c with its error estimates (gsl_sf_result.err), and the pieces of gamma.c, trig.c, log.c, exp.c and psi.c it
// rests on: lngamma_e and the real part of the complex lngamma_e (value and error), exp_err_e, psi(1+iy) and the scaled Airy functions for x > 0.
//
// Results come back through `out` of at least 10 entries: F, F', G, G' at 0..3, their errors at 4..7, then the two exponents (F = out[0] exp(-out[8]), G = out[2] exp(out[9])).
// A function's status is gsl's: 0 success, 1 EDOM, 10 ERUNAWAY, 11 EMAXITER, 15 EUNDRFLW, 16 EOVRFLW, 17 ELOSS.

use e.math
use e.math.special as sp
use e.math.dist as dist

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn c_pi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn c_ln2() -> f64 { ret 0.693147180559945309417232121458f64 }
fn c_lnpi() -> f64 { ret 1.14472988584940017414342735135f64 }
fn c_euler() -> f64 { ret 0.577215664901532860606512090082f64 }
fn c_log_max() -> f64 { ret 7.0978271289338397e+02f64 }
fn c_log_min() -> f64 { ret -7.0839641853226408e+02f64 }
fn c_inf() -> f64 { ret 1.0f64 / 0.0f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn fmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}
fn fmin(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}
fn hyp(x: f64, y: f64) -> f64 {
    let ax = fa(x)
    let ay = fa(y)
    let mn = fmin(ax, ay)
    let mx = fmax(ax, ay)
    if mx == 0.0f64 { ret 0.0f64 }
    let r = mn / mx
    ret mx * math.sqrt[f64](1.0f64 + r * r)
}
fn sgn(x: f64) -> f64 {
    if x >= 0.0f64 { ret 1.0f64 }
    ret -1.0f64
}

// gsl_sf_exp_err_e: (value, error, status)
fn exp_err(x: f64, dx: f64) -> (f64, f64, i64) {
    let adx = fa(dx)
    if x + adx > c_log_max() { ret (c_inf(), c_inf(), 16i64) }
    if x - adx < c_log_min() { ret (0.0f64, 0.0f64, 15i64) }
    let ex = math.exp[f64](x)
    let edx = math.exp[f64](adx)
    let v = ex
    let e = ex * fmax(c_eps(), edx - 1.0f64 / edx) + 2.0f64 * c_eps() * fa(v)
    ret (v, e, 0i64)
}

fn lanczos_c(k: usize) -> f64 {
    if k == 0usize { ret 0.99999999999980993227684700473478f64 }
    if k == 1usize { ret 676.520368121885098567009190444019f64 }
    if k == 2usize { ret -1259.13921672240287047156078755283f64 }
    if k == 3usize { ret 771.3234287776530788486528258894f64 }
    if k == 4usize { ret -176.61502916214059906584551354f64 }
    if k == 5usize { ret 12.507343278686904814458936853f64 }
    if k == 6usize { ret -0.13857109526572011689554707f64 }
    if k == 7usize { ret 9.984369578019570859563e-6f64 }
    ret 1.50563273514931155834e-7f64
}

fn lngamma_lanczos(x0: f64) -> (f64, f64) {
    let x = x0 - 1.0f64
    var ag = lanczos_c(0usize)
    var k = 1usize
    while k <= 8usize {
        ag += lanczos_c(k) / (x + f64(k))
        k += 1usize
    }
    let term1 = (x + 0.5f64) * math.log[f64]((x + 7.5f64) / 2.718281828459045235360287471353f64)
    let term2 = 0.9189385332046727417803297364f64 + math.log[f64](ag)
    let v = term1 + (term2 - 7.0f64)
    let e = 2.0f64 * c_eps() * (fa(term1) + fa(term2) + 7.0f64) + c_eps() * fa(v)
    ret (v, e)
}

fn lngamma_1_pade(ep: f64) -> (f64, f64) {
    let n1 = -1.0017419282349508699871138440f64
    let n2 = 1.7364839209922879823280541733f64
    let d1 = 1.2433006018858751556055436011f64
    let d2 = 5.0456274100274010152489597514f64
    let num = (ep + n1) * (ep + n2)
    let den = (ep + d1) * (ep + d2)
    let pade = 2.0816265188662692474880210318f64 * num / den
    let c0 = 0.004785324257581753f64
    let c1 = -0.01192457083645441f64
    let c2 = 0.01931961413960498f64
    let c3 = -0.02594027398725020f64
    let c4 = 0.03141928755021455f64
    let ep5 = ep * ep * ep * ep * ep
    let corr = ep5 * (c0 + ep * (c1 + ep * (c2 + ep * (c3 + c4 * ep))))
    let v = ep * (pade + corr)
    ret (v, 2.0f64 * c_eps() * fa(v))
}

fn lngamma_2_pade(ep: f64) -> (f64, f64) {
    let n1 = 1.000895834786669227164446568f64
    let n2 = 4.209376735287755081642901277f64
    let d1 = 2.618851904903217274682578255f64
    let d2 = 10.85766559900983515322922936f64
    let num = (ep + n1) * (ep + n2)
    let den = (ep + d1) * (ep + d2)
    let pade = 2.85337998765781918463568869f64 * num / den
    let c0 = 0.0001139406357036744f64
    let c1 = -0.0001365435269792533f64
    let c2 = 0.0001067287169183665f64
    let c3 = -0.0000693271800931282f64
    let c4 = 0.0000407220927867950f64
    let ep5 = ep * ep * ep * ep * ep
    let corr = ep5 * (c0 + ep * (c1 + ep * (c2 + ep * (c3 + c4 * ep))))
    let v = ep * (pade + corr)
    ret (v, 2.0f64 * c_eps() * fa(v))
}

fn lngamma_sgn_0(ep: f64) -> (f64, f64) {
    let c1 = -0.07721566490153286061f64
    let c2 = -0.01094400467202744461f64
    let c3 = 0.09252092391911371098f64
    let c4 = -0.01827191316559981266f64
    let c5 = 0.01800493109685479790f64
    let c6 = -0.00685088537872380685f64
    let c7 = 0.00399823955756846603f64
    let c8 = -0.00189430621687107802f64
    let c9 = 0.00097473237804513221f64
    let c10 = -0.00048434392722255893f64
    let g6 = c6 + ep * (c7 + ep * (c8 + ep * (c9 + ep * c10)))
    let g = ep * (c1 + ep * (c2 + ep * (c3 + ep * (c4 + ep * (c5 + ep * g6)))))
    let gee = g + 1.0f64 / (1.0f64 + ep) + 0.5f64 * ep
    let v = math.log[f64](gee / fa(ep))
    ret (v, 4.0f64 * c_eps() * fa(v))
}

// x = -1 + ep near the pole at -1 (the only singular case the Coulomb functions reach, N = 1)
fn lngamma_sgn_sing1(ep: f64) -> (f64, f64) {
    let c0 = 0.07721566490153286061f64
    let c1 = 0.08815966957356030521f64
    let c2 = -0.00436125434555340577f64
    let c3 = 0.01391065882004640689f64
    let c4 = -0.00409427227680839100f64
    let c5 = 0.00275661310191541584f64
    let c6 = -0.00124162645565305019f64
    let c7 = 0.00065267976121802783f64
    let c8 = -0.00032205261682710437f64
    let c9 = 0.00016229131039545456f64
    let g5 = c5 + ep * (c6 + ep * (c7 + ep * (c8 + ep * c9)))
    let g = ep * (c0 + ep * (c1 + ep * (c2 + ep * (c3 + ep * (c4 + ep * g5)))))
    let gam_e = g - 1.0f64 - 0.5f64 * ep * (1.0f64 + 3.0f64 * ep) / (1.0f64 - ep * ep)
    let v = math.log[f64](fa(gam_e) / fa(ep))
    ret (v, 2.0f64 * c_eps() * fa(v))
}

// gsl_sf_lngamma_e for x > -1 (value, error); x = 0 gives (0, 0) as the domain error does
fn lngamma_e(x: f64) -> (f64, f64) {
    if fa(x - 1.0f64) < 0.01f64 {
        let (v, e) = lngamma_1_pade(x - 1.0f64)
        ret (v, e * (1.0f64 / (c_eps() + fa(x - 1.0f64))))
    }
    if fa(x - 2.0f64) < 0.01f64 {
        let (v, e) = lngamma_2_pade(x - 2.0f64)
        ret (v, e * (1.0f64 / (c_eps() + fa(x - 2.0f64))))
    }
    if x >= 0.5f64 {
        let (v, e) = lngamma_lanczos(x)
        ret (v, e)
    }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    if fa(x) < 0.02f64 {
        let (v, e) = lngamma_sgn_0(x)
        ret (v, e)
    }
    let z = 1.0f64 - x
    let s = math.sin[f64](c_pi() * z)
    let ass = fa(s)
    if s == 0.0f64 { ret (0.0f64, 0.0f64) }
    if ass < c_pi() * 0.015f64 {
        let (v, e) = lngamma_sgn_sing1(x + 1.0f64)
        ret (v, e)
    }
    let (lv, le) = lngamma_lanczos(z)
    let v = c_lnpi() - (math.log[f64](ass) + lv)
    ret (v, 2.0f64 * c_eps() * fa(v) + le)
}

// the real part of gsl's lanczos complex log-gamma (value, error)
fn lngamma_lanczos_complex_re(zr0: f64, zi: f64) -> (f64, f64) {
    let zr = zr0 - 1.0f64
    var agr = lanczos_c(0usize)
    var agi = 0.0f64
    var k = 1usize
    while k <= 8usize {
        let rr = zr + f64(k)
        let a = lanczos_c(k) / (rr * rr + zi * zi)
        agr += a * rr
        agi -= a * zi
        k += 1usize
    }
    let ax1 = fa(zr + 7.5f64)
    let ay1 = fa(zi)
    let l1r = math.log[f64](fmax(ax1, ay1)) + 0.5f64 * math.log[f64](1.0f64 + (fmin(ax1, ay1) / fmax(ax1, ay1)) * (fmin(ax1, ay1) / fmax(ax1, ay1)))
    let l1i = math.atan2[f64](zi, zr + 7.5f64)
    let ax2 = fa(agr)
    let ay2 = fa(agi)
    let l2r = math.log[f64](fmax(ax2, ay2)) + 0.5f64 * math.log[f64](1.0f64 + (fmin(ax2, ay2) / fmax(ax2, ay2)) * (fmin(ax2, ay2) / fmax(ax2, ay2)))
    let v = (zr + 0.5f64) * l1r - zi * l1i - (zr + 7.5f64) + 0.9189385332046727417803297364f64 + l2r
    ret (v, 4.0f64 * c_eps() * fa(v))
}

fn sinh_series(x: f64) -> f64 {
    let y = x * x
    let c0 = 1.0f64 / 6.0f64
    let c1 = 1.0f64 / 120.0f64
    let c2 = 1.0f64 / 5040.0f64
    let c3 = 1.0f64 / 362880.0f64
    let c4 = 1.0f64 / 39916800.0f64
    let c5 = 1.0f64 / 6227020800.0f64
    let c6 = 1.0f64 / 1307674368000.0f64
    let c7 = 1.0f64 / 355687428096000.0f64
    ret x * (1.0f64 + y * (c0 + y * (c1 + y * (c2 + y * (c3 + y * (c4 + y * (c5 + y * (c6 + y * c7))))))))
}

fn cosh_m1_series(x: f64) -> f64 {
    let y = x * x
    let c0 = 0.5f64
    let c1 = 1.0f64 / 24.0f64
    let c2 = 1.0f64 / 720.0f64
    let c3 = 1.0f64 / 40320.0f64
    let c4 = 1.0f64 / 3628800.0f64
    let c5 = 1.0f64 / 479001600.0f64
    let c6 = 1.0f64 / 87178291200.0f64
    let c7 = 1.0f64 / 20922789888000.0f64
    let c8 = 1.0f64 / 6402373705728000.0f64
    ret y * (c0 + y * (c1 + y * (c2 + y * (c3 + y * (c4 + y * (c5 + y * (c6 + y * (c7 + y * c8))))))))
}

// the real part of gsl_sf_complex_logsin_e (value, error)
fn complex_logsin_re(zr: f64, zi: f64) -> (f64, f64) {
    if zi > 60.0f64 {
        let v = 0.0f64 - c_ln2() + zi
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    if zi < -60.0f64 {
        let v = 0.0f64 - c_ln2() - zi
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    var sr = 0.0f64
    var si = 0.0f64
    if fa(zi) < 1.0f64 {
        let sh = sinh_series(zi)
        let chm1 = cosh_m1_series(zi)
        sr = math.sin[f64](zr) * (chm1 + 1.0f64)
        si = math.cos[f64](zr) * sh
    }
    if fa(zi) >= 1.0f64 {
        let ex = math.exp[f64](zi)
        let ch = 0.5f64 * (ex + 1.0f64 / ex)
        let sh = 0.5f64 * (ex - 1.0f64 / ex)
        sr = math.sin[f64](zr) * ch
        si = math.cos[f64](zr) * sh
    }
    let ax = fa(sr)
    let ay = fa(si)
    let mn = fmin(ax, ay)
    let mx = fmax(ax, ay)
    let v = math.log[f64](mx) + 0.5f64 * math.log[f64](1.0f64 + (mn / mx) * (mn / mx))
    ret (v, 2.0f64 * c_eps() * fa(v))
}

// gsl_sf_lngamma_complex_e, the modulus part lnr (value, error)
fn lngamma_complex_lnr(zr: f64, zi: f64) -> (f64, f64) {
    if zr <= 0.5f64 {
        let (av, ae) = lngamma_lanczos_complex_re(1.0f64 - zr, 0.0f64 - zi)
        let (sv, se) = complex_logsin_re(c_pi() * zr, c_pi() * zi)
        let v = c_lnpi() - sv - av
        let e = se + ae + 2.0f64 * c_eps() * fa(v)
        ret (v, e)
    }
    let (v, e) = lngamma_lanczos_complex_re(zr, zi)
    ret (v, e)
}

// the normalisation C0(eta)^2
fn c0sq(eta: f64) -> f64 {
    let tpe = 2.0f64 * c_pi() * eta
    if fa(eta) < c_eps() { ret 1.0f64 }
    if tpe > c_log_max() { ret 0.0f64 }
    ret tpe / dist.expm1(tpe)
}

// C_L(eta): (value, error, status)
fn cl_eta(l: f64, eta: f64) -> (f64, f64, i64) {
    var l1v = 0.0f64
    var l1e = 0.0f64
    if fa(eta / (l + 1.0f64)) < c_eps() {
        let (v, e) = lngamma_e(l + 1.0f64)
        l1v = v
        l1e = e
    }
    if fa(eta / (l + 1.0f64)) >= c_eps() {
        let (v, e) = lngamma_complex_lnr(l + 1.0f64, eta)
        l1v = v
        l1e = e
    }
    let (l2v, l2e) = lngamma_e(2.0f64 * (l + 1.0f64))
    let av = l * c_ln2() - 0.5f64 * eta * c_pi() + l1v - l2v
    var ae = l1e + l2e
    ae += c_eps() * (fa(l * c_ln2()) + fa(0.5f64 * eta * c_pi()))
    let (v, e, st) = exp_err(av, ae)
    ret (v, e, st)
}

// gsl_sf_coulomb_CL_e: (value, error, status)
fn coulomb_cl(lam: f64, eta: f64) -> (f64, f64, i64) {
    if lam <= -1.0f64 { ret (0.0f64, 0.0f64, 1i64) }
    if fa(lam) < c_eps() {
        let v = math.sqrt[f64](c0sq(eta))
        ret (v, 2.0f64 * c_eps() * v, 0i64)
    }
    let (v, e, st) = cl_eta(lam, eta)
    ret (v, e, st)
}

// cl[0..=kmax] = C_{lam_min + k}(eta)
fn coulomb_cl_array(lam_min: f64, kmax: usize, eta: f64, cl: []f64) {
    let (v, _e, _s) = coulomb_cl(lam_min, eta)
    cl[0usize] = v
    var k = 1usize
    while k <= kmax {
        let l = lam_min + f64(k)
        cl[k] = cl[k - 1usize] * hyp(l, eta) / (l * (2.0f64 * l + 1.0f64))
        k += 1usize
    }
}

// Re psi(1 + i y), the value of gsl_sf_psi_1piy_e
fn psi_1piy(y: f64) -> f64 {
    let ay = fa(y)
    if ay > 1000.0f64 {
        let yi2 = 1.0f64 / (ay * ay)
        let lny = math.log[f64](ay)
        let sum = yi2 * (1.0f64 / 12.0f64 + 1.0f64 / 120.0f64 * yi2 + 1.0f64 / 252.0f64 * yi2 * yi2)
        ret lny + sum
    }
    if ay > 10.0f64 {
        let yi2 = 1.0f64 / (ay * ay)
        let lny = math.log[f64](ay)
        let sum = yi2 * (1.0f64 / 12.0f64 + yi2 * (1.0f64 / 120.0f64 + yi2 * (1.0f64 / 252.0f64 + yi2 * (1.0f64 / 240.0f64 + yi2 * (1.0f64 / 132.0f64 + 691.0f64 / 32760.0f64 * yi2)))))
        ret lny + sum
    }
    if ay > 1.0f64 {
        let y2 = ay * ay
        let x = (2.0f64 * ay - 11.0f64) / 9.0f64
        let v = y2 * (1.0f64 / (1.0f64 + y2) + 0.5f64 / (4.0f64 + y2))
        ret r1py_cheb(x) - c_euler() + v
    }
    let y2 = y * y
    let c0 = 0.00019603999466879846570f64
    let c2 = 3.8426659205114376860e-08f64
    let c4 = 1.0041592839497643554e-11f64
    let c6 = 2.9516743763500191289e-15f64
    let p = c0 + y2 * (0.0f64 - c2 + y2 * (c4 - y2 * c6))
    var sum = 0.0f64
    var n = 1usize
    while n <= 50usize {
        let nf = f64(n)
        sum += 1.0f64 / (nf * (nf * nf + y * y))
        n += 1usize
    }
    ret 0.0f64 - c_euler() + y2 * (sum + p)
}

fn r1py_c(k: usize) -> f64 {
    if k == 0usize { ret 1.59888328244976954803168395603f64 }
    if k == 1usize { ret 0.67905625353213463845115658455f64 }
    if k == 2usize { ret -0.068485802980122530009506482524f64 }
    if k == 3usize { ret -0.005788184183095866792008831182f64 }
    if k == 4usize { ret 0.008511258167108615980419855648f64 }
    if k == 5usize { ret -0.004042656134699693434334556409f64 }
    if k == 6usize { ret 0.001352328406159402601778462956f64 }
    if k == 7usize { ret -0.000311646563930660566674525382f64 }
    if k == 8usize { ret 0.000018507563785249135437219139f64 }
    if k == 9usize { ret 0.000028348705427529850296492146f64 }
    if k == 10usize { ret -0.000019487536014574535567541960f64 }
    if k == 11usize { ret 8.0709788710834469408621587335e-06f64 }
    if k == 12usize { ret -2.2983564321340518037060346561e-06f64 }
    if k == 13usize { ret 3.0506629599604749843855962658e-07f64 }
    if k == 14usize { ret 1.3042238632418364610774284846e-07f64 }
    if k == 15usize { ret -1.2308657181048950589464690208e-07f64 }
    if k == 16usize { ret 5.7710855710682427240667414345e-08f64 }
    if k == 17usize { ret -1.8275559342450963966092636354e-08f64 }
    if k == 18usize { ret 3.1020471300626589420759518930e-09f64 }
    if k == 19usize { ret 6.8989327480593812470039430640e-10f64 }
    if k == 20usize { ret -8.7182290258923059852334818997e-10f64 }
    if k == 21usize { ret 4.4069147710243611798213548777e-10f64 }
    if k == 22usize { ret -1.4727311099198535963467200277e-10f64 }
    if k == 23usize { ret 2.7589682523262644748825844248e-11f64 }
    if k == 24usize { ret 4.1871826756975856411554363568e-12f64 }
    if k == 25usize { ret -6.5673460487260087541400767340e-12f64 }
    if k == 26usize { ret 3.4487900886723214020103638000e-12f64 }
    if k == 27usize { ret -1.1807251417448690607973794078e-12f64 }
    if k == 28usize { ret 2.3798314343969589258709315574e-13f64 }
    ret 2.1663630410818831824259465821e-15f64
}

// gsl cheb_eval_e on [-1, 1] with order 29: the value
fn r1py_cheb(x: f64) -> f64 {
    var d = 0.0f64
    var dd = 0.0f64
    let y = x
    let y2 = 2.0f64 * y
    var j = 29usize
    while j >= 1usize {
        let temp = d
        d = y2 * d - dd + r1py_c(j)
        dd = temp
        j -= 1usize
    }
    let temp = d
    d = y * d - dd + 0.5f64 * r1py_c(0usize)
    ret d
}

// exp(2/3 x^(3/2)) Ai(x) for x > 0 and exp(-2/3 x^(3/2)) Bi(x): the Maclaurin series up to 1, then K_{1/3} by the trapezoid rule and I_{1/3} by its power series or
// Hankel's expansion, both on exponents that never leave the range
fn airy_scaled(x: f64, bi: bool) -> f64 {
    let z = 2.0f64 / 3.0f64 * x * math.sqrt[f64](x)
    if x <= 1.0f64 {
        let x3 = x * x * x
        var f = 1.0f64
        var g = x
        var tf = 1.0f64
        var tg = x
        var k = 0usize
        while k < 40usize {
            let k3 = f64(3usize * k)
            tf = tf * x3 / ((k3 + 2.0f64) * (k3 + 3.0f64))
            tg = tg * x3 / ((k3 + 3.0f64) * (k3 + 4.0f64))
            f += tf
            g += tg
            k += 1usize
        }
        let c1 = 0.355028053887817239260063186004f64
        let c2 = 0.258819403792806798405183560189f64
        if bi { ret math.exp[f64](0.0f64 - z) * 1.7320508075688772935274463415f64 * (c1 * f + c2 * g) }
        ret math.exp[f64](z) * (c1 * f - c2 * g)
    }
    if !bi {
        var h = 0.1f64
        if 0.3f64 / math.sqrt[f64](z) < h { h = 0.3f64 / math.sqrt[f64](z) }
        var s = 0.5f64
        var k = 1usize
        while k < 100000usize {
            let t = h * f64(k)
            let ex = z * (math.exp[f64](t) + math.exp[f64](0.0f64 - t) - 2.0f64) / 2.0f64
            if ex > 70.0f64 { break }
            let nt = t / 3.0f64
            s += math.exp[f64](0.0f64 - ex) * (math.exp[f64](nt) + math.exp[f64](0.0f64 - nt)) / 2.0f64
            k += 1usize
        }
        ret math.sqrt[f64](x / 3.0f64) / c_pi() * s * h
    }
    // Bi: 2 sqrt(x/3) I_{1/3}(z) e^{-z} (the I_{-1/3} + I_{1/3} sum)
    if z < 25.0f64 {
        var side = 0usize
        var total = 0.0f64
        while side < 2usize {
            var nu = 1.0f64 / 3.0f64
            if side == 0usize { nu = 0.0f64 - 1.0f64 / 3.0f64 }
            let hz = z / 2.0f64
            var t = math.exp[f64](nu * math.log[f64](hz) - sp.lgamma(nu + 1.0f64) - z)
            var s = t
            var k = 0usize
            while k < 400usize {
                t = t * hz * hz / (f64(k + 1usize) * (f64(k + 1usize) + nu))
                s += t
                if t < s * 1.0e-18f64 { break }
                k += 1usize
            }
            total += s
            side += 1usize
        }
        ret math.sqrt[f64](x / 3.0f64) * total
    }
    var term = 1.0f64
    var sum = 1.0f64
    var k = 1usize
    let mu = 4.0f64 / 9.0f64
    while k < 60usize {
        let kk = 2.0f64 * f64(k) - 1.0f64
        let nt = term * (0.0f64 - (mu - kk * kk)) / (8.0f64 * f64(k) * z)
        if fa(nt) > fa(term) { break }
        term = nt
        sum += term
        if fa(term) < 1.0e-18f64 { break }
        k += 1usize
    }
    ret 2.0f64 * math.sqrt[f64](x / 3.0f64) * sum / math.sqrt[f64](2.0f64 * c_pi() * z)
}

// the connection phase: (status, cos phi, sin phi)
fn coulomb_connection(lam: f64, eta: f64) -> (i64, f64, f64) {
    if eta > 0.0f64 - c_log_min() / 2.0f64 * c_pi() - 1.0f64 { ret (15i64, 1.0f64, 0.0f64) }
    let lim = 36.04365338911715f64 / (4.0f64 * c_pi())
    if eta > lim {
        let ep = 2.0f64 * math.exp[f64](-2.0f64 * c_pi() * eta)
        let tpl = math.tan[f64](c_pi() * lam)
        let dth = ep * tpl / (tpl * tpl + 1.0f64)
        ret (0i64, -1.0f64 + 0.5f64 * dth * dth, 0.0f64 - dth)
    }
    let xx = tanh_(c_pi() * eta) / math.tan[f64](c_pi() * lam)
    let phi = 0.0f64 - math.atan[f64](xx) - (lam + 0.5f64) * c_pi()
    ret (0i64, math.cos[f64](phi), math.sin[f64](phi))
}

fn tanh_(x: f64) -> f64 {
    if x > 20.0f64 { ret 1.0f64 }
    if x < -20.0f64 { ret -1.0f64 }
    let e2 = math.exp[f64](2.0f64 * x)
    if fa(x) < 1.0e-5f64 { ret x - x * x * x / 3.0f64 }
    ret (e2 - 1.0f64) / (e2 + 1.0f64)
}

// the Frobenius series for F_lam and G_lam (not lam <= -1/2, 0, >= 1/2): o = F, F err, G, G err; returns the status
fn coulomb_fg_series(lam: f64, eta: f64, x: f64, o: []f64) -> i64 {
    let max_iter = 800usize
    let (cav, cae, sta) = cl_eta(lam, eta)
    let (cbv, cbe, stb) = cl_eta(0.0f64 - lam - 1.0f64, eta)
    let tlp1 = 2.0f64 * lam + 1.0f64
    let pow_x = math.pow[f64](x, lam)
    let (stc, cosp, sinp) = coulomb_connection(lam, eta)
    if stc == 15i64 {
        o[0usize] = 0.0f64
        o[1usize] = 0.0f64
        o[2usize] = c_inf()
        o[3usize] = c_inf()
        ret 16i64
    }
    var ua2 = 1.0f64
    var ua1 = x * eta / (lam + 1.0f64)
    var ub2 = 1.0f64
    var ub1 = 0.0f64 - x * eta / lam
    var a_sum = ua2 + ua1
    var b_sum = ub2 + ub1
    var a_prev = fa(a_sum)
    var b_prev = fa(b_sum)
    var m = 2usize
    while m < max_iter {
        let mf = f64(m)
        let ua = x * (2.0f64 * eta * ua1 - x * ua2) / (mf * (mf + tlp1))
        let ub = x * (2.0f64 * eta * ub1 - x * ub2) / (mf * (mf - tlp1))
        a_sum += ua
        b_sum += ub
        let ada = fa(ua)
        let adb = fa(ub)
        if m > 15usize {
            let ma = fmax(ada, a_prev)
            let mb = fmax(adb, b_prev)
            let aa = fa(a_sum)
            let ab = fa(b_sum)
            if ma / (ma + aa) < 4.0f64 * c_eps() && mb / (mb + ab) < 4.0f64 * c_eps() { break }
        }
        a_prev = ada
        b_prev = adb
        ua2 = ua1
        ua1 = ua
        ub2 = ub1
        ub1 = ub
        m += 1usize
    }
    let fav = a_sum * cav * pow_x * x
    let fae = fa(a_sum) * cae * pow_x * x + 2.0f64 * c_eps() * fa(fav)
    let fbv = b_sum * cbv / pow_x
    let fbe = fa(b_sum) * cbe / pow_x + 2.0f64 * c_eps() * fa(fbv)
    o[0usize] = fav
    o[1usize] = fae
    o[2usize] = (fav * cosp - fbv) / sinp
    o[3usize] = (fae * fa(cosp) + fbe) / fa(sinp)
    if m >= max_iter { ret 11i64 }
    if sta != 0i64 { ret sta }
    ret stb
}

// F_0 and G_0 (Bardin et al. 1972)
fn coulomb_fg0_series(eta: f64, x: f64, o: []f64) -> i64 {
    let max_iter = 800usize
    let x2 = x * x
    let tex = 2.0f64 * eta * x
    let (c0v, c0e, stcl) = cl_eta(0.0f64, eta)
    let r1pie = psi_1piy(eta)
    var um2 = 0.0f64
    var um1 = x
    var vm2 = 1.0f64
    var vm1 = tex * (2.0f64 * c_euler() - 1.0f64 + r1pie)
    var u_sum = um2 + um1
    var v_sum = vm2 + vm1
    var u_prev = fa(u_sum)
    var v_prev = fa(v_sum)
    var m = 2usize
    var u_err = 2.0f64 * c_eps() * fa(u_sum)
    var v_err = 2.0f64 * c_eps() * fa(v_sum)
    let ln2x = math.log[f64](2.0f64 * x)
    while m < max_iter {
        let mf = f64(m)
        let mm1 = mf * (mf - 1.0f64)
        let um = (tex * um1 - x2 * um2) / mm1
        let vm = (tex * vm1 - x2 * vm2 - 2.0f64 * eta * f64(2usize * m - 1usize) * um) / mm1
        u_sum += um
        v_sum += vm
        let adu = fa(um)
        let adv = fa(vm)
        u_err += 2.0f64 * c_eps() * adu
        v_err += 2.0f64 * c_eps() * adv
        if m > 15usize {
            let mu = fmax(adu, u_prev)
            let mv = fmax(adv, v_prev)
            let au = fa(u_sum)
            let av = fa(v_sum)
            if mu / (mu + au) < 40.0f64 * c_eps() && mv / (mv + av) < 40.0f64 * c_eps() { break }
        }
        u_prev = adu
        v_prev = adv
        um2 = um1
        um1 = um
        vm2 = vm1
        vm1 = vm
        m += 1usize
    }
    let fv = c0v * u_sum
    var fe = c0e * fa(u_sum)
    fe += fa(c0v) * u_err
    fe += 2.0f64 * c_eps() * fa(fv)
    let gv = (v_sum + 2.0f64 * eta * u_sum * ln2x) / c0v
    var ge = (fa(v_sum) + fa(2.0f64 * eta * u_sum * ln2x)) / fa(c0v) * fa(c0e / c0v)
    ge += (v_err + fa(2.0f64 * eta * u_err * ln2x)) / fa(c0v)
    ge += 2.0f64 * c_eps() * fa(gv)
    o[0usize] = fv
    o[1usize] = fe
    o[2usize] = gv
    o[3usize] = ge
    if m == max_iter { ret 11i64 }
    ret stcl
}

// F_{-1/2} and G_{-1/2}
fn coulomb_fgmhalf_series(eta: f64, x: f64, o: []f64) -> i64 {
    let max_iter = 800usize
    let rx = math.sqrt[f64](x)
    let x2 = x * x
    let tex = 2.0f64 * eta * x
    let (cmv, cme, stcl) = cl_eta(-0.5f64, eta)
    var um2 = 1.0f64
    var um1 = tex * um2
    let rp1 = psi_1piy(eta)
    let rp2 = psi_1piy(2.0f64 * eta)
    var vm2 = 2.0f64 * c_euler() - c_ln2() - rp1 + 2.0f64 * rp2
    var vm1 = tex * (vm2 - 2.0f64 * um2)
    var f_sum = um2 + um1
    var g_sum = vm2 + vm1
    var m = 2usize
    while m < max_iter {
        let mf = f64(m)
        let m2 = mf * mf
        let um = (tex * um1 - x2 * um2) / m2
        let vm = (tex * vm1 - x2 * vm2 - 2.0f64 * mf * um) / m2
        f_sum += um
        g_sum += vm
        if f_sum != 0.0f64 && g_sum != 0.0f64 && (fa(um / f_sum) + fa(vm / g_sum) < 10.0f64 * c_eps()) { break }
        um2 = um1
        um1 = um
        vm2 = vm1
        vm1 = vm
        m += 1usize
    }
    let fv = cmv * rx * f_sum
    let fe = cme * fa(rx * f_sum) + 2.0f64 * c_eps() * fa(fv)
    let tmp1 = f_sum * math.log[f64](x)
    let gv = 0.0f64 - rx * (tmp1 + g_sum) / cmv
    let ge = fa(rx) * (fa(tmp1) + fa(g_sum)) / fa(cmv) * fa(cme / cmv)
    o[0usize] = fv
    o[1usize] = fe
    o[2usize] = gv
    o[3usize] = ge
    if m == max_iter { ret 11i64 }
    ret stcl
}

// backward recurrence for F, F': (F_lam_min, Fp_lam_min)
fn coulomb_f_recur(lam_min: f64, kmax: i64, eta: f64, x: f64, f_max: f64, fp_max: f64) -> (f64, f64) {
    let x_inv = 1.0f64 / x
    var fcl = f_max
    var fpl = fp_max
    var lam = lam_min + f64(kmax)
    var k = kmax - 1i64
    while k >= 0i64 {
        let el = eta / lam
        let rl = hyp(1.0f64, el)
        let sl = el + lam * x_inv
        let fc_lm1 = (fcl * sl + fpl) / rl
        fpl = fc_lm1 * sl - fcl * rl
        fcl = fc_lm1
        lam -= 1.0f64
        k -= 1i64
    }
    ret (fcl, fpl)
}

// forward recurrence for G, G': (G_lam_max, Gp_lam_max)
fn coulomb_g_recur(lam_min: f64, kmax: i64, eta: f64, x: f64, g_min: f64, gp_min: f64) -> (f64, f64) {
    let x_inv = 1.0f64 / x
    var gcl = g_min
    var gpl = gp_min
    var lam = lam_min + 1.0f64
    var k = 1i64
    while k <= kmax {
        let el = eta / lam
        let rl = hyp(1.0f64, el)
        let sl = el + lam * x_inv
        let gcl1 = (sl * gcl - gpl) / rl
        gpl = rl * gcl - sl * gcl1
        gcl = gcl1
        lam += 1.0f64
        k += 1i64
    }
    ret (gcl, gpl)
}

// the first continued fraction: (status, sign of F, F'/F, iteration count)
fn coulomb_cf1(lambda: f64, eta: f64, x: f64) -> (i64, f64, f64, i64) {
    let small = 1.0e-30f64
    let abort = 1.0e+05f64
    let acc = 2.0f64 * c_eps()
    let x_inv = 1.0f64 / x
    let px = lambda + 1.0f64 + abort
    var pk = lambda + 1.0f64
    var f = eta / pk + pk * x_inv
    var d = 0.0f64
    var c = 0.0f64
    var df = 0.0f64
    var sign = 1.0f64
    var count = 0i64
    if fa(f) < small { f = small }
    c = f
    while true {
        let pk1 = pk + 1.0f64
        let ek = eta / pk
        let rk2 = 1.0f64 + ek * ek
        let tk = (pk + pk1) * (x_inv + ek / pk1)
        d = tk - rk2 * d
        c = tk - rk2 / c
        if fa(c) < small { c = small }
        if fa(d) < small { d = small }
        d = 1.0f64 / d
        df = d * c
        f = f * df
        if d < 0.0f64 { sign = 0.0f64 - sign }
        pk = pk1
        if pk > px { ret (10i64, sign, f, count) }
        count += 1i64
        if !(fa(df - 1.0f64) > acc) { break }
    }
    ret (0i64, sign, f, count)
}

// the second continued fraction: (status, P, Q, count)
fn coulomb_cf2(lambda: f64, eta: f64, x: f64) -> (i64, f64, f64, i64) {
    var status = 0i64
    let acc = 4.0f64 * c_eps()
    let abort = 2.0e+05f64
    let wi = 2.0f64 * eta
    let x_inv = 1.0f64 / x
    let e2mm1 = eta * eta + lambda * (lambda + 1.0f64)
    var ar = 0.0f64 - e2mm1
    var ai = eta
    let br = 2.0f64 * (x - eta)
    var bi = 2.0f64
    var dr = br / (br * br + bi * bi)
    var di = 0.0f64 - bi / (br * br + bi * bi)
    var dp = 0.0f64 - x_inv * (ar * di + ai * dr)
    var dq = x_inv * (ar * dr - ai * di)
    var pk = 0.0f64
    var p = 0.0f64
    var q = 1.0f64 - eta * x_inv
    var count = 0i64
    while true {
        p += dp
        q += dq
        pk += 2.0f64
        ar += pk
        ai += wi
        bi += 2.0f64
        let dd = ar * dr - ai * di + br
        di = ai * dr + ar * di + bi
        var cc = 1.0f64 / (dd * dd + di * di)
        dr = cc * dd
        di = 0.0f64 - cc * di
        let aa = br * dr - bi * di - 1.0f64
        let bb = bi * dr + br * di
        cc = dp * aa - dq * bb
        dq = dp * bb + dq * aa
        dp = cc
        if pk > abort {
            status = 10i64
            break
        }
        count += 1i64
        if !(fa(dp) + fa(dq) > (fa(p) + fa(q)) * acc) { break }
    }
    if q < abort * c_eps() * fa(p) { status = 17i64 }
    ret (status, p, q, count)
}

// WKB values below the turning point: out of (status, F, F err, G, G err, exponent)
fn coulomb_jwkb(lam: f64, eta: f64, x: f64) -> (i64, f64, f64, f64, f64, f64) {
    let llp1 = lam * (lam + 1.0f64) + 6.0f64 / 35.0f64
    let llp1_eff = fmax(llp1, 0.0f64)
    let rho_ghalf = math.sqrt[f64](x * (2.0f64 * eta - x) + llp1_eff)
    let sinh_arg = math.sqrt[f64](llp1_eff / (eta * eta + llp1_eff)) * rho_ghalf / x
    let sinh_inv = math.log[f64](sinh_arg + hyp(1.0f64, sinh_arg))
    let phi = fa(rho_ghalf - eta * math.atan2[f64](rho_ghalf, x - eta) - math.sqrt[f64](llp1_eff) * sinh_inv)
    let zeta_half = math.pow[f64](3.0f64 * phi / 2.0f64, 1.0f64 / 3.0f64)
    let prefactor = math.sqrt[f64](c_pi() * phi * x / (6.0f64 * rho_ghalf))
    var f = prefactor * 3.0f64 / zeta_half
    var g = prefactor * 3.0f64 / zeta_half
    let ai = airy_scaled(zeta_half * zeta_half, false)
    let bi = airy_scaled(zeta_half * zeta_half, true)
    f *= ai
    g *= bi
    let f_exp = math.log[f64](f) - phi
    let g_exp = math.log[f64](g) + phi
    if g_exp >= c_log_max() { ret (16i64, f, 1.0e-3f64 * fa(f), g, 1.0e-3f64 * fa(g), phi) }
    let fv = math.exp[f64](f_exp)
    let gv = math.exp[f64](g_exp)
    ret (0i64, fv, 1.0e-3f64 * fa(fv), gv, 1.0e-3f64 * fa(gv), 0.0f64)
}

fn set4(o: []f64, f: f64, fe: f64, fp: f64, fpe: f64, g: f64, ge: f64, gp: f64, gpe: f64) {
    o[0usize] = f
    o[1usize] = fp
    o[2usize] = g
    o[3usize] = gp
    o[4usize] = fe
    o[5usize] = fpe
    o[6usize] = ge
    o[7usize] = gpe
    o[8usize] = 0.0f64
    o[9usize] = 0.0f64
}

// gsl_sf_coulomb_wave_FG_e: F and F' at lam_F, G and G' at lam_F - k_g; o is the 10 entry layout above; ser holds 4 scratch entries
fn coulomb_wave_fg(eta: f64, x: f64, lam_f: f64, k_g: i64, o: []f64, ser: []f64) -> i64 {
    let lam_g = lam_f - f64(k_g)
    if x < 0.0f64 || lam_f <= -0.5f64 || lam_g <= -0.5f64 {
        set4(o, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
        ret 1i64
    }
    if x == 0.0f64 {
        let (c0v, c0e, _s0) = cl_eta(0.0f64, eta)
        set4(o, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
        if lam_f == 0.0f64 {
            o[1usize] = c0v
            o[5usize] = c0e
        }
        if lam_g == 0.0f64 {
            o[3usize] = 1.0f64 / c0v
            o[7usize] = fa(c0e / c0v) / fa(c0v)
        }
        ret 1i64
    }
    if x < 1.2f64 && 2.0f64 * c_pi() * eta < 0.9f64 * (0.0f64 - c_log_min()) && fa(eta * x) < 10.0f64 {
        let small = 1.4901161193847656e-08f64
        let nn = i64(lam_f + 0.5f64)
        var span = nn
        if k_g > span { span = k_g }
        let lam_min = lam_f - f64(nn)
        let (st1, f_sign, fp_over_f, cf1_count) = coulomb_cf1(lam_f, eta, x)
        var f_lam_f = small
        var fp_lam_f = fp_over_f * f_lam_f
        var f_min_un = f_lam_f
        var fp_min_un = fp_lam_f
        if span != 0i64 {
            let (a1, a2) = coulomb_f_recur(lam_min, span, eta, x, f_lam_f, fp_lam_f)
            f_min_un = a1
            fp_min_un = a2
        }
        var stat_ser = 0i64
        if lam_min == -0.5f64 { stat_ser = coulomb_fgmhalf_series(eta, x, ser) }
        if lam_min == 0.0f64 { stat_ser = coulomb_fg0_series(eta, x, ser) }
        if lam_min != -0.5f64 && lam_min != 0.0f64 { stat_ser = coulomb_fg_series(lam_min, eta, x, ser) }
        let f_min_v = ser[0usize]
        let f_min_e = ser[1usize]
        let g_min_v = ser[2usize]
        let g_min_e = ser[3usize]
        let fp_over_f_min = fp_min_un / f_min_un
        let gp_min_v = fp_over_f_min * g_min_v - 1.0f64 / f_min_v
        var gp_min_e = fa(fp_over_f_min) * g_min_e
        gp_min_e += fa(1.0f64 / f_min_v) * fa(f_min_e / f_min_v)
        let f_scale = f_min_v / f_min_un
        let f_scale_frac_err = fa(f_min_e / f_min_v)
        let f_unnorm_frac_err = 2.0f64 * c_eps() * f64(cf1_count + span + 1i64)
        f_lam_f *= f_scale
        let f_lam_f_err = fa(f_lam_f) * (f_unnorm_frac_err + f_scale_frac_err)
        fp_lam_f *= f_scale
        let fp_lam_f_err = fa(fp_lam_f) * (f_unnorm_frac_err + f_scale_frac_err)
        var gstep = nn - k_g
        if gstep < 0i64 { gstep = 0i64 }
        let (g_lam_g, gp_lam_g) = coulomb_g_recur(lam_min, gstep, eta, x, g_min_v, gp_min_v)
        let gerr_frac = fa(g_min_e / g_min_v) + fa(gp_min_e / gp_min_v)
        o[0usize] = f_lam_f
        o[4usize] = f_lam_f_err + 2.0f64 * c_eps() * fa(f_lam_f)
        o[1usize] = fp_lam_f
        o[5usize] = fp_lam_f_err + 2.0f64 * c_eps() * fa(fp_lam_f)
        o[2usize] = g_lam_g
        o[6usize] = gerr_frac * fa(g_lam_g) + 2.0f64 * f64(cf1_count + 1i64) * c_eps() * fa(g_lam_g)
        o[3usize] = gp_lam_g
        o[7usize] = gerr_frac * fa(gp_lam_g) + 2.0f64 * f64(cf1_count + 1i64) * c_eps() * fa(gp_lam_g)
        o[8usize] = 0.0f64
        o[9usize] = 0.0f64
        if stat_ser != 0i64 { ret stat_ser }
        ret st1
    }
    if x < 2.0f64 * eta {
        let (s_f, fv_f, fe_f, gv_f, ge_f, ex_f) = coulomb_jwkb(lam_f, eta, x)
        var s_g = s_f
        var fv_g = fv_f
        var fe_g = fe_f
        var gv_g = gv_f
        var ge_g = ge_f
        var ex_g = ex_f
        if k_g != 0i64 {
            let (a1, a2, a3, a4, a5, a6) = coulomb_jwkb(lam_g, eta, x)
            s_g = a1
            fv_g = a2
            fe_g = a3
            gv_g = a4
            ge_g = a5
            ex_g = a6
        }
        let (st1, _sg1, fpf_f, _c1) = coulomb_cf1(lam_f, eta, x)
        var fpf_g = fpf_f
        var st2 = st1
        if k_g != 0i64 {
            let (b1, _b2, b3, _b4) = coulomb_cf1(lam_g, eta, x)
            st2 = b1
            fpf_g = b3
        }
        o[0usize] = fv_f
        o[4usize] = fe_f
        o[2usize] = gv_g
        o[6usize] = ge_g
        o[1usize] = fpf_f * fv_f
        o[5usize] = fa(fpf_f) * fe_f + 2.0f64 * c_eps() * fa(o[1usize])
        o[3usize] = fpf_g * gv_g - 1.0f64 / fv_g
        o[7usize] = fa(fpf_g) * ge_g + fa(1.0f64 / fv_g) * fa(fe_g / fv_g)
        o[8usize] = ex_f
        o[9usize] = ex_g
        if s_f == 16i64 || s_g == 16i64 { ret 16i64 }
        if s_f != 0i64 { ret s_f }
        ret s_g
    }
    let small = 1.4901161193847656e-08f64
    let cc = math.sqrt[f64](1.0f64 + 4.0f64 * x * (x - 2.0f64 * eta))
    let nn = i64(math.ceil[f64](lam_f - cc + 0.5f64))
    var n0 = nn
    if n0 < 0i64 { n0 = 0i64 }
    let lam_0 = lam_f - f64(n0)
    let lam_min = fmin(lam_0, lam_g)
    let (st_cf1, f_sign_f, fp_over_f_f, cf1_count) = coulomb_cf1(lam_f, eta, x)
    var f_lam_f = f_sign_f * small
    var fp_lam_f = fp_over_f_f * f_lam_f
    var f_recur_count = k_g
    if nn > f_recur_count { f_recur_count = nn }
    let (f_min_un, fp_min_un) = coulomb_f_recur(lam_min, f_recur_count, eta, x, f_lam_f, fp_lam_f)
    let fp_over_f_min = fp_min_un / f_min_un
    let (st_cf2, p_min, q_min, cf2_count) = coulomb_cf2(lam_min, eta, x)
    let alpha = fp_over_f_min - p_min
    let gamma = alpha / q_min
    let f_min = sgn(f_min_un) / math.sqrt[f64](alpha * alpha / q_min + q_min)
    let fp_min = fp_over_f_min * f_min
    let g_min = gamma * f_min
    let gp_min = (p_min * gamma - q_min) * f_min
    let f_scale = f_min / f_min_un
    f_lam_f *= f_scale
    fp_lam_f *= f_scale
    var g_recur_count = nn - k_g
    if g_recur_count < 0i64 { g_recur_count = 0i64 }
    let (g_lam_g, gp_lam_g) = coulomb_g_recur(lam_min, g_recur_count, eta, x, g_min, gp_min)
    let amp = f64(cf1_count + cf2_count + f_recur_count + g_recur_count + 1i64)
    o[0usize] = f_lam_f
    o[4usize] = 8.0f64 * amp * c_eps() * fa(f_lam_f)
    o[1usize] = fp_lam_f
    o[5usize] = 8.0f64 * amp * c_eps() * fa(fp_lam_f)
    o[2usize] = g_lam_g
    o[6usize] = 8.0f64 * amp * c_eps() * fa(g_lam_g)
    o[3usize] = gp_lam_g
    o[7usize] = 8.0f64 * amp * c_eps() * fa(gp_lam_g)
    o[8usize] = 0.0f64
    o[9usize] = 0.0f64
    if st_cf1 != 0i64 { ret st_cf1 }
    if st_cf2 != 0i64 { ret st_cf2 }
    ret 0i64
}

// F_{lam_min + k}(eta, x), k = 0..=kmax, into fc; returns (F exponent, status)
fn coulomb_wave_f_array(lam_min: f64, kmax: usize, eta: f64, x: f64, fc: []f64, o: []f64, ser: []f64) -> (f64, i64) {
    if x == 0.0f64 {
        var k = 0usize
        while k <= kmax {
            fc[k] = 0.0f64
            k += 1usize
        }
        if lam_min == 0.0f64 {
            let (c0v, _c0e, _s0) = cl_eta(0.0f64, eta)
            fc[0usize] = c0v
        }
        ret (0.0f64, 0i64)
    }
    let x_inv = 1.0f64 / x
    let lam_max = lam_min + f64(kmax)
    let st = coulomb_wave_fg(eta, x, lam_max, 0i64, o, ser)
    var fcl = o[0usize]
    var fpl = o[1usize]
    var lam = lam_max
    fc[kmax] = fcl
    var k = i64(kmax) - 1i64
    while k >= 0i64 {
        let el = eta / lam
        let rl = hyp(1.0f64, el)
        let sl = el + lam * x_inv
        let fc_lm1 = (fcl * sl + fpl) / rl
        fc[usize(k)] = fc_lm1
        fpl = fc_lm1 * sl - fcl * rl
        fcl = fc_lm1
        lam -= 1.0f64
        k -= 1i64
    }
    ret (o[8usize], st)
}

// F and G arrays (and, when fcp and gcp are not empty, their derivatives); returns (F exponent, G exponent, status)
fn coulomb_wave_fg_array(lam_min: f64, kmax: usize, eta: f64, x: f64, fc: []f64, fcp: []f64, gc: []f64, gcp: []f64, with_p: bool, o: []f64, ser: []f64) -> (f64, f64, i64) {
    let x_inv = 1.0f64 / x
    let lam_max = lam_min + f64(kmax)
    let st = coulomb_wave_fg(eta, x, lam_max, i64(kmax), o, ser)
    var fcl = o[0usize]
    var fpl = o[1usize]
    var lam = lam_max
    fc[kmax] = fcl
    if with_p { fcp[kmax] = fpl }
    var k = i64(kmax) - 1i64
    while k >= 0i64 {
        let el = eta / lam
        let rl = hyp(1.0f64, el)
        let sl = el + lam * x_inv
        let fc_lm1 = (fcl * sl + fpl) / rl
        fc[usize(k)] = fc_lm1
        fpl = fc_lm1 * sl - fcl * rl
        if with_p { fcp[usize(k)] = fpl }
        fcl = fc_lm1
        lam -= 1.0f64
        k -= 1i64
    }
    var gcl = o[2usize]
    var gpl = o[3usize]
    lam = lam_min + 1.0f64
    gc[0usize] = gcl
    if with_p { gcp[0usize] = gpl }
    var j = 1usize
    while j <= kmax {
        let el = eta / lam
        let rl = hyp(1.0f64, el)
        let sl = el + lam * x_inv
        let gcl1 = (sl * gcl - gpl) / rl
        gc[j] = gcl1
        gpl = rl * gcl - sl * gcl1
        if with_p { gcp[j] = gpl }
        gcl = gcl1
        lam += 1.0f64
        j += 1usize
    }
    ret (o[8usize], o[9usize], st)
}

// the spherical form F / x; returns (F exponent, status)
fn coulomb_wave_sphf_array(lam_min: f64, kmax: usize, eta: f64, x: f64, fc: []f64, o: []f64, ser: []f64) -> (f64, i64) {
    if x < 0.0f64 || lam_min < -0.5f64 { ret (0.0f64, 1i64) }
    if x < 10.0f64 / 1.7976931348623157e308f64 {
        var k = 0usize
        while k <= kmax {
            fc[k] = 0.0f64
            k += 1usize
        }
        if lam_min == 0.0f64 { fc[0usize] = math.sqrt[f64](c0sq(eta)) }
        if x == 0.0f64 { ret (0.0f64, 0i64) }
        ret (0.0f64, 15i64)
    }
    let (ex, st) = coulomb_wave_f_array(lam_min, kmax, eta, x, fc, o, ser)
    var k = 0usize
    while k <= kmax {
        fc[k] = fc[k] / x
        k += 1usize
    }
    ret (ex, st)
}
