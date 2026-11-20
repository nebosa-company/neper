// R gsl, Bessel functions of real order (Jnu, Ynu, Inu, Knu, their scaled forms and lnKnu) with gsl_sf_result.err, and the integer-order Jn, Yn, Kn and In with their Olver
// uniform asymptotic and Taylor branches: a port of specfunc/bessel_Jnu.c, bessel_Ynu.c, bessel_Inu.c, bessel_Knu.c, bessel_temme.c, bessel_olver.c and the matching branches
// of bessel_Jn.c, bessel_Yn.c, bessel_Kn.c, bessel_In.c (the helpers of bessel.c come from gslbj and gslbn). Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.mem
use e.math.scale as sc
use e.algo.stat.gslbj as gj
use e.algo.stat.gslbn as gn
use e.algo.stat.gslbessel as gb
use e.algo.stat.gslairy as ga
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslcheb2 as c2
use e.algo.stat.gslcheb3 as c3
use e.algo.stat.gslerr2 as g2
use e.algo.stat.gslpoch as gp

fn u_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn u_a(x: f64) -> f64 { ret math.abs[f64](x) }
fn u_pi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn u_root3() -> f64 { ret 6.0554544523933429e-06f64 }
fn u_smin() -> f64 { ret 1.4916681462400413e-154f64 }
fn u_smax() -> f64 { ret 1.3407807929942596e+154f64 }
fn u_lmax() -> f64 { ret 7.0978271289338397e+02f64 }
fn u_lmin() -> f64 { ret -7.0839641853226408e+02f64 }
fn u_ln10() -> f64 { ret 2.30258509299404568401799145468f64 }

type JY = struct { jv: f64, je: f64, j1v: f64, j1e: f64, yv: f64, ye: f64, y1v: f64, y1e: f64 }

// gsl_sf_exp_e as (value, error); overflow and underflow give (0, 0)
fn u_exp(x: f64) -> (f64, f64) {
    if x > u_lmax() { ret (0.0f64, 0.0f64) }
    if x < u_lmin() { ret (0.0f64, 0.0f64) }
    let v = math.exp[f64](x)
    ret (v, 2.0f64 * u_eps() * u_a(v))
}

// gsl_sf_sin_pi_e and gsl_sf_cos_pi_e
fn sin_pi_taylor(x: f64) -> (f64, f64) {
    var v = 0.0f64
    if 16.0f64 * u_a(x) < 1.0f64 {
        let y = u_pi() * x
        let s = y * y
        v = y * (1.0f64 - s * (1.0f64 - s * (1.0f64 - s * (1.0f64 - s * (1.0f64 - s / 110.0f64) / 72.0f64) / 42.0f64) / 20.0f64) / 6.0f64)
    } else {
        v = math.sin[f64](u_pi() * x)
    }
    ret (v, u_eps() * u_a(v))
}

fn cos_pi_taylor(x: f64) -> (f64, f64) {
    var v = 0.0f64
    if 20.0f64 * u_a(x) < 1.0f64 {
        let y = u_pi() * x
        let s = y * y
        v = 1.0f64 - 0.5f64 * s * (1.0f64 - s * (1.0f64 - s * (1.0f64 - s * (1.0f64 - s / 90.0f64) / 56.0f64) / 30.0f64) / 12.0f64)
    } else {
        v = math.cos[f64](u_pi() * x)
    }
    ret (v, u_eps() * u_a(v))
}

fn sin_pi(x: f64) -> (f64, f64) {
    let intx = math.trunc[f64](x)
    var fracx = x - intx
    if fracx == 0.0f64 { ret (0.0f64, 0.0f64) }
    if u_a(intx) >= 2.0f64 / u_eps() { ret (0.0f64, 0.0f64) }
    var sign = 1.0f64
    if math.floor[f64](intx / 2.0f64) * 2.0f64 != intx { sign = -1.0f64 }
    if u_a(fracx) == 0.5f64 {
        if fracx < 0.0f64 { sign = 0.0f64 - sign }
        ret (sign, 0.0f64)
    }
    if u_a(fracx) > 0.5f64 {
        sign = 0.0f64 - sign
        if fracx > 0.0f64 { fracx = fracx - 1.0f64 } else { fracx = fracx + 1.0f64 }
    }
    var rv = 0.0f64
    var re = 0.0f64
    if fracx > 0.25f64 {
        let (cv, ce) = cos_pi_taylor(fracx - 0.5f64)
        rv = cv
        re = ce
    } else {
        if fracx < -0.25f64 {
            let (cv2, ce2) = cos_pi_taylor(fracx + 0.5f64)
            rv = cv2
            re = ce2
            sign = 0.0f64 - sign
        } else {
            let (sv, se) = sin_pi_taylor(fracx)
            rv = sv
            re = se
        }
    }
    if sign != 1.0f64 { rv = 0.0f64 - rv }
    ret (rv, re)
}

fn cos_pi(x: f64) -> (f64, f64) {
    let intx = math.trunc[f64](x)
    var fracx = x - intx
    if u_a(fracx) == 0.5f64 { ret (0.0f64, 0.0f64) }
    if u_a(intx) >= 2.0f64 / u_eps() { ret (1.0f64, 0.0f64) }
    var sign = 1.0f64
    if math.floor[f64](intx / 2.0f64) * 2.0f64 != intx { sign = -1.0f64 }
    if fracx == 0.0f64 { ret (sign, 0.0f64) }
    if u_a(fracx) > 0.5f64 {
        sign = 0.0f64 - sign
        if fracx > 0.0f64 { fracx = fracx - 1.0f64 } else { fracx = fracx + 1.0f64 }
    }
    var rv = 0.0f64
    var re = 0.0f64
    if fracx > 0.25f64 {
        let (sv, se) = sin_pi_taylor(fracx - 0.5f64)
        rv = sv
        re = se
        sign = 0.0f64 - sign
    } else {
        if fracx < -0.25f64 {
            let (sv2, se2) = sin_pi_taylor(fracx + 0.5f64)
            rv = sv2
            re = se2
        } else {
            let (cv, ce) = cos_pi_taylor(fracx)
            rv = cv
            re = ce
        }
    }
    if sign != 1.0f64 { rv = 0.0f64 - rv }
    ret (rv, re)
}

// gsl_sf_bessel_IJ_taylor_e(nu, x, sgn, kmax, eps)
fn ij_taylor(ar: *mem.Arena, nu: f64, x: f64, sgn: f64, kmax: i64) -> (f64, f64) {
    if nu < 0.0f64 || x < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x == 0.0f64 {
        if nu == 0.0f64 { ret (1.0f64, 0.0f64) }
        ret (0.0f64, 0.0f64)
    }
    var pre_v = 1.0f64
    var pre_e = 0.0f64
    if nu != 0.0f64 {
        let nn = math.floor[f64](nu + 0.5f64)
        let f = nu - nn
        let (pov, poe) = gp.poch(ar, nn + 1.0f64, f)
        let (tcv, tce) = g2.e_taylorcoeff(i64(nn), 0.5f64 * x)
        let p = math.pow[f64](0.5f64 * x, f)
        pre_v = tcv * p / pov
        pre_e = tce * p / pov
        pre_e += u_a(pre_v) / pov * poe
        pre_e += 2.0f64 * u_eps() * u_a(pre_v)
    }
    let y = sgn * 0.25f64 * x * x
    var sumk = 1.0f64
    var term = 1.0f64
    var k = 1i64
    while k <= kmax {
        term = term * (y / ((nu + f64(k)) * f64(k)))
        sumk += term
        if u_a(term / sumk) < u_eps() { break }
        k += 1i64
    }
    let sum_e = u_eps() * u_a(sumk)
    let v = pre_v * sumk
    ret (v, 2.0f64 * u_eps() * u_a(v) + u_a(pre_e * sumk) + u_a(sum_e * pre_v))
}

// the Debye polynomials of A&S 9.3.9, with t^k built by repeated multiplication as gsl does
fn debye_sum(t: f64, sgn: f64, nu: f64) -> f64 {
    let t1 = t
    let t2 = t * t1
    let t3 = t * t2
    let t4 = t * t3
    let t5 = t * t4
    let t6 = t * t5
    let t7 = t * t6
    let t8 = t * t7
    let t9 = t * t8
    let t10 = t * t9
    let t11 = t * t10
    let t12 = t * t11
    let t13 = t * t12
    let t15 = t * (t * t13)
    let u1 = (3.0f64 * t1 - 5.0f64 * t3) / 24.0f64
    let u2 = (81.0f64 * t2 - 462.0f64 * t4 + 385.0f64 * t6) / 1152.0f64
    let u3 = (30375.0f64 * t3 - 369603.0f64 * t5 + 765765.0f64 * t7 - 425425.0f64 * t9) / 414720.0f64
    let u4 = (4465125.0f64 * t4 - 94121676.0f64 * t6 + 349922430.0f64 * t8 - 446185740.0f64 * t10 + 185910725.0f64 * t12) / 39813120.0f64
    let u5 = (1519035525.0f64 * t5 - 49286948607.0f64 * t7 + 284499769554.0f64 * t9 - 614135872350.0f64 * t11 + 566098157625.0f64 * t13 - 188699385875.0f64 * t15) / 6688604160.0f64
    ret 1.0f64 + sgn * u1 / nu + u2 / (nu * nu) + sgn * u3 / (nu * nu * nu) + u4 / (nu * nu * nu * nu) + sgn * u5 / (nu * nu * nu * nu * nu)
}

fn hypot1(z: f64) -> f64 {
    ret math.sqrt[f64](1.0f64 + z * z)
}

// gsl_sf_bessel_Inu_scaled_asymp_unif_e
fn inu_scaled_unif(nu: f64, x: f64) -> (f64, f64) {
    let z = x / nu
    let root_term = hypot1(z)
    let pre = 1.0f64 / math.sqrt[f64](2.0f64 * u_pi() * nu * root_term)
    let eta = root_term + math.log[f64](z / (1.0f64 + root_term))
    var ex_arg = 0.0f64 - 0.5f64 * nu / z * (1.0f64 - 1.0f64 / (12.0f64 * z * z))
    if z < 1.0f64 / u_root3() { ex_arg = nu * (0.0f64 - z + eta) }
    let (exv, exe) = u_exp(ex_arg)
    if exv == 0.0f64 { ret (0.0f64, 0.0f64) }
    let sum = debye_sum(1.0f64 / root_term, 1.0f64, nu)
    let v = pre * exv * sum
    var er = pre * exv / (nu * nu * nu * nu * nu * nu)
    er += pre * exe * u_a(sum)
    er += 2.0f64 * u_eps() * u_a(v)
    ret (v, er)
}

// gsl_sf_bessel_Knu_scaled_asymp_unif_e
fn knu_scaled_unif(nu: f64, x: f64) -> (f64, f64) {
    let z = x / nu
    let root_term = hypot1(z)
    let pre = math.sqrt[f64](u_pi() / (2.0f64 * nu * root_term))
    let eta = root_term + math.log[f64](z / (1.0f64 + root_term))
    var ex_arg = 0.5f64 * nu / z * (1.0f64 + 1.0f64 / (12.0f64 * z * z))
    if z < 1.0f64 / u_root3() { ex_arg = nu * (z - eta) }
    let (exv, exe) = u_exp(ex_arg)
    if exv == 0.0f64 { ret (0.0f64, 0.0f64) }
    let sum = debye_sum(1.0f64 / root_term, -1.0f64, nu)
    let v = pre * exv * sum
    var er = pre * exe * u_a(sum)
    er += pre * exv / (nu * nu * nu * nu * nu * nu)
    er += 2.0f64 * u_eps() * u_a(v)
    ret (v, er)
}

// ---- bessel_olver.c ----

fn olver_b0(z: f64, abs_zeta: f64) -> f64 {
    if z < 0.98f64 {
        let t = 1.0f64 / math.sqrt[f64](1.0f64 - z * z)
        ret -5.0f64 / (48.0f64 * abs_zeta * abs_zeta) + t * (-3.0f64 + 5.0f64 * t * t) / (24.0f64 * math.sqrt[f64](abs_zeta))
    }
    if z < 1.02f64 {
        let aa = 1.0f64 - z
        let c0 = 0.0179988721413553309252458658183f64
        let c1 = 0.0111992982212877614645974276203f64
        let c2_ = 0.0059404069786014304317781160605f64
        let c3_ = 0.0028676724516390040844556450173f64
        let c4 = 0.0012339189052567271708525111185f64
        let c5 = 0.0004169250674535178764734660248f64
        let c6 = 0.0000330173385085949806952777365f64
        let c7 = -0.0001318076238578203009990106425f64
        let c8 = -0.0001906870370050847239813945647f64
        ret c0 + aa * (c1 + aa * (c2_ + aa * (c3_ + aa * (c4 + aa * (c5 + aa * (c6 + aa * (c7 + aa * c8)))))))
    }
    let t = 1.0f64 / (z * math.sqrt[f64](1.0f64 - 1.0f64 / (z * z)))
    ret -5.0f64 / (48.0f64 * abs_zeta * abs_zeta) + t * (3.0f64 + 5.0f64 * t * t) / (24.0f64 * math.sqrt[f64](abs_zeta))
}

fn olver_b1(z: f64, abs_zeta: f64) -> f64 {
    if z < 0.88f64 {
        let t = 1.0f64 / math.sqrt[f64](1.0f64 - z * z)
        let t2 = t * t
        let rz = math.sqrt[f64](abs_zeta)
        let z32 = rz * rz * rz
        let z92 = z32 * z32 * z32
        let term1 = t * t * t * (30375.0f64 - 369603.0f64 * t2 + 765765.0f64 * t2 * t2 - 425425.0f64 * t2 * t2 * t2) / 414720.0f64
        let term2 = 85085.0f64 / (663552.0f64 * z92)
        let term3 = 385.0f64 / 110592.0f64 * t * (3.0f64 - 5.0f64 * t2) / (abs_zeta * abs_zeta * abs_zeta)
        let term4 = 5.0f64 / 55296.0f64 * t2 * (81.0f64 - 462.0f64 * t2 + 385.0f64 * t2 * t2) / z32
        ret 0.0f64 - (term1 + term2 + term3 + term4) / rz
    }
    if z < 1.12f64 {
        let aa = 1.0f64 - z
        let c0 = -0.00149282953213429172050073403334f64
        let c1 = -0.00175640941909277865678308358128f64
        let c2_ = -0.00113346148874174912576929663517f64
        let c3_ = -0.00034691090981382974689396961817f64
        let c4 = 0.00022752516104839243675693256916f64
        let c5 = 0.00051764145724244846447294636552f64
        let c6 = 0.00058906174858194233998714243010f64
        let c7 = 0.00053485514521888073087240392846f64
        let c8 = 0.00042891792986220150647633418796f64
        let c9 = 0.00031639765900613633260381972850f64
        let c10 = 0.00021908147678699592975840749194f64
        ret c0 + aa * (c1 + aa * (c2_ + aa * (c3_ + aa * (c4 + aa * (c5 + aa * (c6 + aa * (c7 + aa * (c8 + aa * (c9 + aa * c10)))))))))
    }
    let t = 1.0f64 / (z * math.sqrt[f64](1.0f64 - 1.0f64 / (z * z)))
    let t2 = t * t
    let rz = math.sqrt[f64](abs_zeta)
    let z32 = rz * rz * rz
    let z92 = z32 * z32 * z32
    let term1 = 0.0f64 - t2 * t * (30375.0f64 + 369603.0f64 * t2 + 765765.0f64 * t2 * t2 + 425425.0f64 * t2 * t2 * t2) / 414720.0f64
    let term2 = 85085.0f64 / (663552.0f64 * z92)
    let term3 = -385.0f64 / 110592.0f64 * t * (3.0f64 + 5.0f64 * t2) / (abs_zeta * abs_zeta * abs_zeta)
    let term4 = 5.0f64 / 55296.0f64 * t2 * (81.0f64 + 462.0f64 * t2 + 385.0f64 * t2 * t2) / z32
    ret (term1 + term2 + term3 + term4) / rz
}

fn olver_b2(z: f64) -> f64 {
    if z < 0.8f64 {
        let (cv, _ce) = c3.cvv_bessel_olver_B2_lt1(5.0f64 * z / 2.0f64 - 1.0f64)
        ret cv / z
    }
    if z <= 1.2f64 {
        let aa = 1.0f64 - z
        let c0 = 0.00055221307672129279005986982501f64
        let c1 = 0.00089586516310476929281129228969f64
        let c2_ = 0.00067015003441569770883539158863f64
        let c3_ = 0.00010166263361949045682945811828f64
        let c4 = -0.00044086345133806887291336488582f64
        let c5 = -0.00073963081508788743392883072523f64
        let c6 = -0.00076745494377839561259903887331f64
        let c7 = -0.00060829038106040362291568012663f64
        let c8 = -0.00037128707528893496121336168683f64
        let c9 = -0.00014116325105702609866850307176f64
        ret c0 + aa * (c1 + aa * (c2_ + aa * (c3_ + aa * (c4 + aa * (c5 + aa * (c6 + aa * (c7 + aa * (c8 + aa * c9))))))))
    }
    let zi = 1.0f64 / z
    let (gv, _ge) = c3.cvv_bessel_olver_B2_gt1(12.0f64 / 5.0f64 * zi - 1.0f64)
    ret gv * zi * zi * zi
}

fn olver_b3(z: f64) -> f64 {
    if z < 0.8f64 {
        let (cv, _ce) = c3.cvv_bessel_olver_B3_lt1(5.0f64 * z / 2.0f64 - 1.0f64)
        ret cv
    }
    if z < 1.2f64 {
        let aa = 1.0f64 - z
        let c0 = -0.00047461779655995980754441833105f64
        let c1 = -0.00095572913429464297452176811898f64
        let c2_ = -0.00080369634512082892655558133973f64
        let c3_ = -0.00000727921669154784138080600339f64
        let c4 = 0.00093162500331581345235746518994f64
        let c5 = 0.00149848796913751497227188612403f64
        let c6 = 0.00148406039675949727870390426462f64
        ret c0 + aa * (c1 + aa * (c2_ + aa * (c3_ + aa * (c4 + aa * (c5 + aa * c6)))))
    }
    let xx = 12.0f64 / (5.0f64 * z) - 1.0f64
    let zi2 = 1.0f64 / (z * z)
    let (gv, _ge) = c3.cvv_bessel_olver_B3_gt1(xx)
    ret gv * zi2 * zi2 * zi2
}

// (value, err)
fn olver_a1(z: f64, abs_zeta: f64) -> (f64, f64) {
    if z < 0.98f64 {
        let t = 1.0f64 / math.sqrt[f64](1.0f64 - z * z)
        let rz = math.sqrt[f64](abs_zeta)
        let t2 = t * t
        let term1 = t2 * (81.0f64 - 462.0f64 * t2 + 385.0f64 * t2 * t2) / 1152.0f64
        let term2 = -455.0f64 / (4608.0f64 * abs_zeta * abs_zeta * abs_zeta)
        let term3 = 7.0f64 * t * (-3.0f64 + 5.0f64 * t2) / (1152.0f64 * rz * rz * rz)
        ret (term1 + term2 + term3, 2.0f64 * u_eps() * (u_a(term1) + u_a(term2) + u_a(term3)))
    }
    if z < 1.02f64 {
        let aa = 1.0f64 - z
        let c0 = -0.00444444444444444444444444444444f64
        let c1 = -0.00184415584415584415584415584416f64
        let c2_ = 0.00056812076812076812076812076812f64
        let c3_ = 0.00168137865661675185484709294233f64
        let c4 = 0.00186744042139000122193399504324f64
        let c5 = 0.00161330105833747826430066790326f64
        let c6 = 0.00123177312220625816558607537838f64
        let c7 = 0.00087334711007377573881689318421f64
        let c8 = 0.00059004942455353250141217015410f64
        let sum = c0 + aa * (c1 + aa * (c2_ + aa * (c3_ + aa * (c4 + aa * (c5 + aa * (c6 + aa * (c7 + aa * c8)))))))
        ret (sum, 2.0f64 * u_eps() * u_a(sum))
    }
    let t = 1.0f64 / (z * math.sqrt[f64](1.0f64 - 1.0f64 / (z * z)))
    let rz = math.sqrt[f64](abs_zeta)
    let t2 = t * t
    let term1 = 0.0f64 - t2 * (81.0f64 + 462.0f64 * t2 + 385.0f64 * t2 * t2) / 1152.0f64
    let term2 = 455.0f64 / (4608.0f64 * abs_zeta * abs_zeta * abs_zeta)
    let term3 = -7.0f64 * t * (3.0f64 + 5.0f64 * t2) / (1152.0f64 * rz * rz * rz)
    ret (term1 + term2 + term3, 2.0f64 * u_eps() * (u_a(term1) + u_a(term2) + u_a(term3)))
}

fn olver_a2(z: f64, abs_zeta: f64) -> f64 {
    if z < 0.88f64 {
        let t = 1.0f64 / math.sqrt[f64](1.0f64 - z * z)
        let t2 = t * t
        let t4 = t2 * t2
        let t6 = t4 * t2
        let t8 = t4 * t4
        let rz = math.sqrt[f64](abs_zeta)
        let z3 = abs_zeta * abs_zeta * abs_zeta
        let z32 = rz * rz * rz
        let z92 = z3 * z32
        let term1 = t4 * (4465125.0f64 - 94121676.0f64 * t2 + 349922430.0f64 * t4 - 446185740.0f64 * t6 + 185910725.0f64 * t8) / 39813120.0f64
        let term2 = -40415375.0f64 / (127401984.0f64 * z3 * z3)
        let term3 = -95095.0f64 / 15925248.0f64 * t * (3.0f64 - 5.0f64 * t2) / z92
        let term4 = -455.0f64 / 5308416.0f64 * t2 * (81.0f64 - 462.0f64 * t2 + 385.0f64 * t4) / z3
        let term5 = -7.0f64 / 19906560.0f64 * t * t2 * (30375.0f64 - 369603.0f64 * t2 + 765765.0f64 * t4 - 425425.0f64 * t6) / z32
        ret term1 + term2 + term3 + term4 + term5
    }
    if z < 1.12f64 {
        let aa = 1.0f64 - z
        let c0 = 0.000693735541354588973636592684210f64
        let c1 = 0.000464483490365843307019777608010f64
        let c2_ = -0.000289036254605598132482570468291f64
        let c3_ = -0.000874764943953712638574497548110f64
        let c4 = -0.001029716376139865629968584679350f64
        let c5 = -0.000836857329713810600584714031650f64
        let c6 = -0.000488910893527218954998270124540f64
        let c7 = -0.000144236747940817220502256810151f64
        let c8 = 0.000114363800986163478038576460325f64
        let c9 = 0.000266806881492777536223944807117f64
        let c10 = -0.011975517576151069627471048587000f64
        ret c0 + aa * (c1 + aa * (c2_ + aa * (c3_ + aa * (c4 + aa * (c5 + aa * (c6 + aa * (c7 + aa * (c8 + aa * (c9 + aa * c10)))))))))
    }
    let t = 1.0f64 / (z * math.sqrt[f64](1.0f64 - 1.0f64 / (z * z)))
    let t2 = t * t
    let t4 = t2 * t2
    let t6 = t4 * t2
    let t8 = t4 * t4
    let rz = math.sqrt[f64](abs_zeta)
    let z3 = abs_zeta * abs_zeta * abs_zeta
    let z32 = rz * rz * rz
    let z92 = z3 * z32
    let term1 = t4 * (4465125.0f64 + 94121676.0f64 * t2 + 349922430.0f64 * t4 + 446185740.0f64 * t6 + 185910725.0f64 * t8) / 39813120.0f64
    let term2 = -40415375.0f64 / (127401984.0f64 * z3 * z3)
    let term3 = 95095.0f64 / 15925248.0f64 * t * (3.0f64 + 5.0f64 * t2) / z92
    let term4 = -455.0f64 / 5308416.0f64 * t2 * (81.0f64 + 462.0f64 * t2 + 385.0f64 * t4) / z3
    let term5 = 7.0f64 / 19906560.0f64 * t * t2 * (30375.0f64 + 369603.0f64 * t2 + 765765.0f64 * t4 + 425425.0f64 * t6) / z32
    ret term1 + term2 + term3 + term4 + term5
}

fn olver_a3(z: f64) -> f64 {
    if z < 0.9f64 {
        let (cv, _ce) = c3.cvv_bessel_olver_A3_lt1(20.0f64 * z / 9.0f64 - 1.0f64)
        ret cv
    }
    if z < 1.1f64 {
        let aa = 1.0f64 - z
        let c0 = -0.000354211971457743840771125759200f64
        let c1 = -0.000312322527890318832782774881353f64
        let c2_ = 0.000277947465383133980329617631915f64
        let c3_ = 0.000919803044747966977054155192400f64
        let c4 = 0.001147600388275977640983696906320f64
        let c5 = 0.000869239326123625742931772044544f64
        let c6 = 0.000287392257282507334785281718027f64
        ret c0 + aa * (c1 + aa * (c2_ + aa * (c3_ + aa * (c4 + aa * (c5 + aa * c6)))))
    }
    let xx = 11.0f64 / (5.0f64 * z) - 1.0f64
    let zi2 = 1.0f64 / (z * z)
    let (gv, _ge) = c3.cvv_bessel_olver_A3_gt1(xx)
    ret gv * zi2 * zi2 * zi2
}

fn olver_a4(z: f64) -> f64 {
    if z < 0.8f64 {
        let (cv, _ce) = c3.cvv_bessel_olver_A4_lt1(5.0f64 * z / 2.0f64 - 1.0f64)
        ret cv
    }
    if z < 1.2f64 {
        let aa = 1.0f64 - z
        let c0 = 0.00037819419920177291402661228437f64
        let c1 = 0.00040494390552363233477213857527f64
        let c2_ = -0.00045764735528936113047289344569f64
        let c3_ = -0.00165361044229650225813161341879f64
        let c4 = -0.00217527517983360049717137015539f64
        let c5 = -0.00152003287866490735107772795537f64
        ret c0 + aa * (c1 + aa * (c2_ + aa * (c3_ + aa * (c4 + aa * c5))))
    }
    let xx = 12.0f64 / (5.0f64 * z) - 1.0f64
    let zi2 = 1.0f64 / (z * z)
    let (gv, _ge) = c3.cvv_bessel_olver_A4_gt1(xx)
    ret gv * zi2 * zi2 * zi2 * zi2
}

// (Asum, its error)
fn olver_asum(nu: f64, z: f64, abs_zeta: f64) -> (f64, f64) {
    let nu2 = nu * nu
    let (a1, a1e) = olver_a1(z, abs_zeta)
    let a2 = olver_a2(z, abs_zeta)
    let a3 = olver_a3(z)
    let a4 = olver_a4(z)
    ret (1.0f64 + a1 / nu2 + a2 / (nu2 * nu2) + a3 / (nu2 * nu2 * nu2) + a4 / (nu2 * nu2 * nu2 * nu2), a1e / nu2 + u_eps())
}

fn olver_bsum(nu: f64, z: f64, abs_zeta: f64) -> f64 {
    let nu2 = nu * nu
    let b0 = olver_b0(z, abs_zeta)
    let b1 = olver_b1(z, abs_zeta)
    let b2 = olver_b2(z)
    let b3 = olver_b3(z)
    ret b0 + b1 / nu2 + b2 / (nu2 * nu2) + b3 / (nu2 * nu2 * nu2 * nu2)
}

// (zeta, |zeta|, pre) of the three z regions; the Y form differs from the J form only in how pre is rounded for z > 1
fn olver_zeta(z: f64, yform: bool) -> (f64, f64, f64) {
    if u_a(1.0f64 - z) < 0.02f64 {
        let aa = 1.0f64 - z
        let c0 = 1.25992104989487316476721060728f64
        let c1 = 0.37797631496846194943016318218f64
        let c2_ = 0.230385563409348235843147082474f64
        let c3_ = 0.165909603649648694839821892031f64
        let c4 = 0.12931387086451008907f64
        let c5 = 0.10568046188858133991f64
        let c6 = 0.08916997952268186978f64
        let c7 = 0.07700014900618802456f64
        let pr = c0 + aa * (c1 + aa * (c2_ + aa * (c3_ + aa * (c4 + aa * (c5 + aa * (c6 + aa * c7))))))
        let zeta = aa * pr
        ret (zeta, u_a(zeta), math.sqrt[f64](2.0f64 * math.sqrt[f64](pr / (1.0f64 + z))))
    }
    if z < 1.0f64 {
        let rt = math.sqrt[f64](1.0f64 - z * z)
        let abs_zeta = math.pow[f64](1.5f64 * (math.log[f64]((1.0f64 + rt) / z) - rt), 2.0f64 / 3.0f64)
        ret (abs_zeta, abs_zeta, math.sqrt[f64](2.0f64 * math.sqrt[f64](abs_zeta / (rt * rt))))
    }
    let rt = z * math.sqrt[f64](1.0f64 - 1.0f64 / (z * z))
    let abs_zeta = math.pow[f64](1.5f64 * (rt - math.acos[f64](1.0f64 / z)), 2.0f64 / 3.0f64)
    if yform {
        ret (0.0f64 - abs_zeta, abs_zeta, math.sqrt[f64](2.0f64 * math.sqrt[f64](abs_zeta) / rt))
    }
    ret (0.0f64 - abs_zeta, abs_zeta, math.sqrt[f64](2.0f64 * math.sqrt[f64](abs_zeta / (rt * rt))))
}

// gsl_sf_bessel_Jnu_asymp_Olver_e
fn jnu_olver(nu: f64, x: f64) -> (f64, f64) {
    if x <= 0.0f64 || nu <= 0.0f64 { ret (0.0f64, 0.0f64) }
    let z = x / nu
    let crnu = math.pow[f64](nu, 1.0f64 / 3.0f64)
    let nu3 = nu * nu * nu
    let nu11 = nu3 * nu3 * nu3 * nu * nu
    let (zeta, abs_zeta, pre) = olver_zeta(z, false)
    let (asum, asum_err) = olver_asum(nu, z, abs_zeta)
    let bsum = olver_bsum(nu, z, abs_zeta)
    let arg = crnu * crnu * zeta
    let (aiv, aie) = ga.airy_ai(arg, 0usize)
    let (apv, _ape) = ga.airy_ai_deriv(arg, 0usize)
    let v = pre * (aiv * asum / crnu + apv * bsum / (nu * crnu * crnu))
    var er = pre * (aie * u_a(asum / crnu))
    er += pre * u_a(aiv) * asum_err / crnu
    er += pre * u_a(aiv * asum) / (crnu * nu11)
    er += 8.0f64 * u_eps() * u_a(v)
    ret (v, er)
}

// gsl_sf_bessel_Ynu_asymp_Olver_e
fn ynu_olver(nu: f64, x: f64) -> (f64, f64) {
    if x <= 0.0f64 || nu <= 0.0f64 { ret (0.0f64, 0.0f64) }
    let z = x / nu
    let crnu = math.pow[f64](nu, 1.0f64 / 3.0f64)
    let nu3 = nu * nu * nu
    let nu11 = nu3 * nu3 * nu3 * nu * nu
    let (zeta, abs_zeta, pre) = olver_zeta(z, true)
    let (asum, asum_err) = olver_asum(nu, z, abs_zeta)
    let bsum = olver_bsum(nu, z, abs_zeta)
    let arg = crnu * crnu * zeta
    let (biv, bie) = ga.airy_bi(arg, 0usize)
    let (bpv, _bpe) = ga.airy_bi_deriv(arg, 0usize)
    let v = 0.0f64 - pre * (biv * asum / crnu + bpv * bsum / (nu * crnu * crnu))
    var er = pre * (bie * u_a(asum / crnu))
    er += pre * u_a(biv) * asum_err / crnu
    er += pre * u_a(biv * asum) / (crnu * nu11)
    er += 8.0f64 * u_eps() * u_a(v)
    ret (v, er)
}

// ---- bessel_temme.c ----

// (1/Gamma(1+nu), 1/Gamma(1-nu), g1, g2) as gsl_sf_temme_gamma returns (g_1pnu, g_1mnu, g1, g2)
fn temme_gamma(nu: f64) -> (f64, f64, f64, f64) {
    let anu = u_a(nu)
    let xx = 4.0f64 * anu - 1.0f64
    let (g1, _e1) = c2.cvv_bessel_temme_g1(xx)
    let (g2v, _e2) = c2.cvv_bessel_temme_g2(xx)
    let g_1mnu = 1.0f64 / (g2v + nu * g1)
    let g_1pnu = 1.0f64 / (g2v - nu * g1)
    ret (g_1pnu, g_1mnu, g1, g2v)
}

// gsl_sf_bessel_Y_temme: (Ynu, err, Ynup1, err)
fn y_temme(nu: f64, x: f64) -> (f64, f64, f64, f64) {
    let half_x = 0.5f64 * x
    let ln_half_x = math.log[f64](half_x)
    let half_x_nu = math.exp[f64](nu * ln_half_x)
    let pi_nu = u_pi() * nu
    let alpha = pi_nu / 2.0f64
    let sigma = 0.0f64 - nu * ln_half_x
    var sinrat = pi_nu / math.sin[f64](pi_nu)
    if u_a(pi_nu) < u_eps() { sinrat = 1.0f64 }
    var sinhrat = sc.sinh(sigma) / sigma
    if u_a(sigma) < u_eps() { sinhrat = 1.0f64 }
    var sinhalf = math.sin[f64](alpha) / alpha
    if u_a(alpha) < u_eps() { sinhalf = 1.0f64 }
    let sin_sqr = nu * u_pi() * u_pi() * 0.5f64 * sinhalf * sinhalf
    let (g_1pnu, g_1mnu, g1, g2v) = temme_gamma(nu)
    var fk = 2.0f64 / u_pi() * sinrat * (sc.cosh(sigma) * g1 - sinhrat * ln_half_x * g2v)
    var pk = 1.0f64 / u_pi() / half_x_nu * g_1pnu
    var qk = 1.0f64 / u_pi() * half_x_nu * g_1mnu
    var hk = pk
    var ck = 1.0f64
    var sum0 = fk + sin_sqr * qk
    var sum1 = pk
    var k = 0i64
    while k < 15000i64 {
        k += 1i64
        let kf = f64(k)
        fk = (kf * fk + pk + qk) / (f64(k * k) - nu * nu)
        ck = ck * (0.0f64 - half_x * half_x / kf)
        pk = pk / (kf - nu)
        qk = qk / (kf + nu)
        let gk = fk + sin_sqr * qk
        hk = 0.0f64 - kf * gk + pk
        let del0 = ck * gk
        let del1 = ck * hk
        sum0 += del0
        sum1 += del1
        if u_a(del0) < 0.5f64 * (1.0f64 + u_a(sum0)) * u_eps() { break }
    }
    let yv = 0.0f64 - sum0
    let y1 = 0.0f64 - sum1 * 2.0f64 / x
    let ee = (2.0f64 + 0.5f64 * f64(k)) * u_eps()
    ret (yv, ee * u_a(yv), y1, ee * u_a(y1))
}

// gsl_sf_bessel_K_scaled_temme: (K_nu, K_nup1, Kp_nu)
fn k_scaled_temme(nu: f64, x: f64) -> (f64, f64, f64) {
    let half_x = 0.5f64 * x
    let ln_half_x = math.log[f64](half_x)
    let half_x_nu = math.exp[f64](nu * ln_half_x)
    let pi_nu = u_pi() * nu
    let sigma = 0.0f64 - nu * ln_half_x
    var sinrat = pi_nu / math.sin[f64](pi_nu)
    if u_a(pi_nu) < u_eps() { sinrat = 1.0f64 }
    var sinhrat = sc.sinh(sigma) / sigma
    if u_a(sigma) < u_eps() { sinhrat = 1.0f64 }
    let ex = math.exp[f64](x)
    let (g_1pnu, g_1mnu, g1, g2v) = temme_gamma(nu)
    var fk = sinrat * (sc.cosh(sigma) * g1 - sinhrat * ln_half_x * g2v)
    var pk = 0.5f64 / half_x_nu * g_1pnu
    var qk = 0.5f64 * half_x_nu * g_1mnu
    var hk = pk
    var ck = 1.0f64
    var sum0 = fk
    var sum1 = hk
    var k = 0i64
    while k < 15000i64 {
        k += 1i64
        let kf = f64(k)
        fk = (kf * fk + pk + qk) / (f64(k * k) - nu * nu)
        ck = ck * (half_x * half_x / kf)
        pk = pk / (kf - nu)
        qk = qk / (kf + nu)
        hk = 0.0f64 - kf * fk + pk
        let del0 = ck * fk
        let del1 = ck * hk
        sum0 += del0
        sum1 += del1
        if u_a(del0) < 0.5f64 * u_a(sum0) * u_eps() { break }
    }
    let k_nu = sum0 * ex
    let k_nup1 = sum1 * 2.0f64 / x * ex
    ret (k_nu, k_nup1, 0.0f64 - k_nup1 + nu / x * k_nu)
}

// gsl_sf_bessel_JY_steed_CF2: (P, Q)
fn jy_steed_cf2(nu: f64, x: f64) -> (f64, f64) {
    let small = 1.0e-100f64
    let x_inv = 1.0f64 / x
    var aa = 0.25f64 - nu * nu
    var p = -0.5f64 * x_inv
    var q = 1.0f64
    let br = 2.0f64 * x
    var bi = 2.0f64
    var fact = aa * x_inv / (p * p + q * q)
    var cr = br + q * fact
    var ci = bi + p * fact
    var den = br * br + bi * bi
    var dr = br / den
    var di = 0.0f64 - bi / den
    var dlr = cr * dr - ci * di
    var dli = cr * di + ci * dr
    var temp = p * dlr - q * dli
    q = p * dli + q * dlr
    p = temp
    var i = 2i64
    while i <= 10000i64 {
        aa += f64(2i64 * (i - 1i64))
        bi += 2.0f64
        dr = aa * dr + br
        di = aa * di + bi
        if u_a(dr) + u_a(di) < small { dr = small }
        fact = aa / (cr * cr + ci * ci)
        cr = br + cr * fact
        ci = bi - ci * fact
        if u_a(cr) + u_a(ci) < small { cr = small }
        den = dr * dr + di * di
        dr = dr / den
        di = di / (0.0f64 - den)
        dlr = cr * dr - ci * di
        dli = cr * di + ci * dr
        temp = p * dlr - q * dli
        q = p * dli + q * dlr
        p = temp
        if u_a(dlr - 1.0f64) + u_a(dli) < u_eps() { break }
        i += 1i64
    }
    ret (p, q)
}

// gsl_sf_bessel_K_scaled_steed_temme_CF2: (K_nu, K_nup1, Kp_nu)
fn k_scaled_steed_cf2(nu: f64, x: f64) -> (f64, f64, f64) {
    var bi = 2.0f64 * (1.0f64 + x)
    var di = 1.0f64 / bi
    var delhi = di
    var hi = di
    var qi = 0.0f64
    var qip1 = 1.0f64
    var ai = 0.0f64 - (0.25f64 - nu * nu)
    let a1 = ai
    var ci = 0.0f64 - ai
    var qq = 0.0f64 - ai
    var s = 1.0f64 + qq * delhi
    var i = 2i64
    while i <= 10000i64 {
        ai -= 2.0f64 * f64(i - 1i64)
        ci = 0.0f64 - ai * ci / f64(i)
        let tmp = (qi - bi * qip1) / ai
        qi = qip1
        qip1 = tmp
        qq += ci * qip1
        bi += 2.0f64
        di = 1.0f64 / (bi + ai * di)
        delhi = (bi * di - 1.0f64) * delhi
        hi += delhi
        let dels = qq * delhi
        s += dels
        if u_a(dels / s) < u_eps() { break }
        i += 1i64
    }
    hi = hi * (0.0f64 - a1)
    let k_nu = math.sqrt[f64](u_pi() / (2.0f64 * x)) / s
    let k_nup1 = k_nu * (nu + x + 0.5f64 - hi) / x
    ret (k_nu, k_nup1, 0.0f64 - k_nup1 + nu / x * k_nu)
}

// gsl_sf_bessel_JY_mu_restricted for 0 < x, |mu| <= 1/2
fn jy_mu_restricted(ar: *mem.Arena, mu: f64, x: f64) -> JY {
    var r: JY = zero
    if x < 2.0f64 {
        let (j1v, j1e) = ij_taylor(ar, mu + 1.0f64, x, -1.0f64, 100i64)
        let (j2v, j2e) = ij_taylor(ar, mu + 2.0f64, x, -1.0f64, 100i64)
        let cc = 2.0f64 * (mu + 1.0f64) / x
        r.j1v = j1v
        r.j1e = j1e
        r.jv = cc * j1v - j2v
        r.je = cc * j1e + j2e
        r.je += 2.0f64 * u_eps() * u_a(r.jv)
        let (yv, ye, y1v, y1e) = y_temme(mu, x)
        r.yv = yv
        r.ye = ye
        r.y1v = y1v
        r.y1e = y1e
        ret r
    }
    if x < 1000.0f64 {
        let (ratio, jsgn) = gj.j_cf1(mu, x)
        let (pp, qq) = jy_steed_cf2(mu, x)
        let jpr = mu / x - ratio
        let gamma = (pp - jpr) / qq
        r.jv = jsgn * math.sqrt[f64](2.0f64 / (u_pi() * x) / (qq + gamma * (pp - jpr)))
        r.je = 4.0f64 * u_eps() * u_a(r.jv)
        r.j1v = ratio * r.jv
        r.j1e = u_a(ratio) * r.je
        r.yv = gamma * r.jv
        r.ye = u_a(gamma) * r.je
        r.y1v = r.yv * (mu / x - pp - qq / gamma)
        r.y1e = r.ye * u_a(mu / x - pp - qq / gamma) + 4.0f64 * u_eps() * u_a(r.y1v)
        ret r
    }
    let (j0v, j0e) = gj.jnu_asympx(mu, x)
    let (j1v2, j1e2) = gj.jnu_asympx(mu + 1.0f64, x)
    let (y0v, y0e) = gn.ynu_asympx(mu, x)
    let (y1v2, y1e2) = gn.ynu_asympx(mu + 1.0f64, x)
    r.jv = j0v
    r.je = j0e
    r.j1v = j1v2
    r.j1e = j1e2
    r.yv = y0v
    r.ye = y0e
    r.y1v = y1v2
    r.y1e = y1e2
    ret r
}

// ---- Jnu, Ynu ----

// gsl_sf_bessel_Jnupos_e (nu >= 0, x >= 0)
fn jnupos(ar: *mem.Arena, nu: f64, x: f64) -> (f64, f64) {
    if x == 0.0f64 {
        if nu == 0.0f64 { ret (1.0f64, 0.0f64) }
        ret (0.0f64, 0.0f64)
    }
    if x * x < 10.0f64 * (nu + 1.0f64) {
        let (tv, te) = ij_taylor(ar, nu, x, -1.0f64, 100i64)
        ret (tv, te)
    }
    if nu > 50.0f64 {
        let (ov, oe) = jnu_olver(nu, x)
        ret (ov, oe)
    }
    if x > 1000.0f64 {
        let (av, ae) = gj.jnu_asympx(nu, x)
        ret (av, ae)
    }
    let nn = i64(nu + 0.5f64)
    let mu = nu - f64(nn)
    let (ratio, sgn_jnu) = gj.j_cf1(nu, x)
    if x < 2.0f64 {
        let (ymu, _ymue, ymup1, _ymup1e) = y_temme(mu, x)
        var ynm1 = ymu
        var yn = ymup1
        var ynp1 = 0.0f64
        var n = 1i64
        while n < nn {
            ynp1 = 2.0f64 * (mu + f64(n)) / x * yn - ynm1
            ynm1 = yn
            yn = ynp1
            n += 1i64
        }
        let v = 2.0f64 / (u_pi() * x) / (ratio * yn - ynp1)
        ret (v, u_eps() * (f64(nn) + 2.0f64) * u_a(v))
    }
    let (pp, qq) = jy_steed_cf2(mu, x)
    var jnp1 = sgn_jnu * u_smin() * ratio
    var jn = sgn_jnu * u_smin()
    var n2 = nn
    while n2 > 0i64 {
        let jnm1 = 2.0f64 * (mu + f64(n2)) / x * jn - jnp1
        jnp1 = jn
        jn = jnm1
        n2 -= 1i64
    }
    let jmup1_jmu = jnp1 / jn
    var sgn_jmu = 1.0f64
    if jn < 0.0f64 { sgn_jmu = -1.0f64 }
    let jmuprime_jmu = mu / x - jmup1_jmu
    let gamma = (pp - jmuprime_jmu) / qq
    let jmu = sgn_jmu * math.sqrt[f64](2.0f64 / (u_pi() * x) / (qq + gamma * (pp - jmuprime_jmu)))
    let v2 = jmu * (sgn_jnu * u_smin()) / jn
    ret (v2, 2.0f64 * u_eps() * (f64(nn) + 2.0f64) * u_a(v2))
}

// gsl_sf_bessel_Ynupos_e (nu >= 0, x > 0)
fn ynupos(ar: *mem.Arena, nu: f64, x: f64) -> (f64, f64) {
    if nu > 50.0f64 {
        let (ov, oe) = ynu_olver(nu, x)
        ret (ov, oe)
    }
    let nn = i64(nu + 0.5f64)
    let mu = nu - f64(nn)
    var ymu = 0.0f64
    var ymue = 0.0f64
    var ymup1 = 0.0f64
    var ymup1e = 0.0f64
    if x < 2.0f64 {
        let (a0, a1, a2, a3) = y_temme(mu, x)
        ymu = a0
        ymue = a1
        ymup1 = a2
        ymup1e = a3
    } else {
        let jy = jy_mu_restricted(ar, mu, x)
        ymu = jy.yv
        ymue = jy.ye
        ymup1 = jy.y1v
        ymup1e = jy.y1e
    }
    var ynm1 = ymu
    var yn = ymup1
    var n = 1i64
    while n <= nn {
        let ynp1 = 2.0f64 * (mu + f64(n)) / x * yn - ynm1
        ynm1 = yn
        yn = ynp1
        n += 1i64
    }
    var er = (f64(nn) + 1.0f64) * u_a(ynm1) * (u_a(ymue / ymu) + u_a(ymup1e / ymup1))
    er += 2.0f64 * u_eps() * u_a(ynm1)
    ret (ynm1, er)
}

// gsl_sf_bessel_Jnu_e
fn bessel_jnu(ar: *mem.Arena, nu: f64, x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if nu < 0.0f64 {
        let (jv, je) = jnupos(ar, 0.0f64 - nu, x)
        let (yv, ye) = ynupos(ar, 0.0f64 - nu, x)
        let (s, serr) = sin_pi(nu)
        let (c, cerr) = cos_pi(nu)
        ret (s * yv + c * jv, u_a(c * ye) + u_a(s * je) + u_a(cerr * yv) + u_a(serr * jv))
    }
    let (v, e) = jnupos(ar, nu, x)
    ret (v, e)
}

// gsl_sf_bessel_Ynu_e
fn bessel_ynu(ar: *mem.Arena, nu: f64, x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if nu < 0.0f64 {
        let (jv, je) = jnupos(ar, 0.0f64 - nu, x)
        let (yv, ye) = ynupos(ar, 0.0f64 - nu, x)
        let (s, serr) = sin_pi(nu)
        let (c, cerr) = cos_pi(nu)
        ret (c * yv - s * jv, u_a(c * ye) + u_a(s * je) + u_a(cerr * yv) + u_a(serr * jv))
    }
    let (v, e) = ynupos(ar, nu, x)
    ret (v, e)
}

// ---- Inu, Knu ----

// gsl_sf_bessel_Inu_scaled_e
fn inu_scaled(ar: *mem.Arena, nu: f64, x: f64) -> (f64, f64) {
    if x < 0.0f64 || nu < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x * x < 10.0f64 * (nu + 1.0f64) {
        let ex = math.exp[f64](0.0f64 - x)
        let (bv, be) = ij_taylor(ar, nu, x, 1.0f64, 100i64)
        let v = bv * ex
        ret (v, be * ex + 2.0f64 * u_eps() * u_a(v))
    }
    if 0.5f64 / (nu * nu + x * x) < u_root3() {
        let (uv, ue) = inu_scaled_unif(nu, x)
        ret (uv, ue)
    }
    let nn = i64(nu + 0.5f64)
    let mu = nu - f64(nn)
    var k_mu = 0.0f64
    var k_mup1 = 0.0f64
    if x < 2.0f64 {
        let (t0, t1, _t2) = k_scaled_temme(mu, x)
        k_mu = t0
        k_mup1 = t1
    } else {
        let (s0, s1, _s2) = k_scaled_steed_cf2(mu, x)
        k_mu = s0
        k_mup1 = s1
    }
    var k_nu = k_mu
    var k_nup1 = k_mup1
    var n = 0i64
    while n < nn {
        let k_num1 = k_nu
        k_nu = k_nup1
        k_nup1 = 2.0f64 * (mu + f64(n) + 1.0f64) / x * k_nu + k_num1
        n += 1i64
    }
    let ratio = gn.i_cf1_ser(nu, x)
    let v = 1.0f64 / (x * (k_nup1 + ratio * k_nu))
    ret (v, u_eps() * (0.5f64 * f64(nn) + 2.0f64) * u_a(v))
}

// gsl_sf_bessel_Inu_e
fn inu(ar: *mem.Arena, nu: f64, x: f64) -> (f64, f64) {
    let (bv, be) = inu_scaled(ar, nu, x)
    let (v, e) = ga.exp_mult_err(x, u_a(x * u_eps()), bv, be)
    ret (v, e)
}

// gsl_sf_bessel_Knu_scaled_e10_e: (value, error, e10)
fn knu_scaled_e10(nu: f64, x: f64) -> (f64, f64, f64) {
    if x <= 0.0f64 || nu < 0.0f64 { ret (0.0f64, 0.0f64, 0.0f64) }
    let nn = i64(nu + 0.5f64)
    let mu = nu - f64(nn)
    var k_mu = 0.0f64
    var k_mup1 = 0.0f64
    if x < 2.0f64 {
        let (t0, t1, _t2) = k_scaled_temme(mu, x)
        k_mu = t0
        k_mup1 = t1
    } else {
        let (s0, s1, _s2) = k_scaled_steed_cf2(mu, x)
        k_mu = s0
        k_mup1 = s1
    }
    var k_nu = k_mu
    var k_nup1 = k_mup1
    var e10 = 0.0f64
    var n = 0i64
    while n < nn {
        var k_num1 = k_nu
        k_nu = k_nup1
        if u_a(k_nu) > u_smax() {
            let p = math.floor[f64](math.log[f64](u_a(k_nu)) / u_ln10())
            let factor = math.pow[f64](10.0f64, p)
            k_num1 = k_num1 / factor
            k_nu = k_nu / factor
            e10 = math.trunc[f64](e10 + p)
        }
        k_nup1 = 2.0f64 * (mu + f64(n) + 1.0f64) / x * k_nu + k_num1
        n += 1i64
    }
    ret (k_nu, 2.0f64 * u_eps() * (f64(nn) + 4.0f64) * u_a(k_nu), e10)
}

// gsl_sf_result_smash_e
fn smash(v: f64, e: f64, e10: f64) -> (f64, f64) {
    if e10 == 0.0f64 { ret (v, e) }
    let av = u_a(v)
    let ae = u_a(e)
    if u_smin() < av && av < u_smax() && u_smin() < ae && ae < u_smax() && 0.49f64 * u_lmin() < e10 && e10 < 0.49f64 * u_lmax() {
        let scale = math.exp[f64](e10 * u_ln10())
        ret (v * scale, e * scale)
    }
    let (rv, re) = ga.exp_mult_err(e10 * u_ln10(), 0.0f64, v, e)
    ret (rv, re)
}

// gsl_sf_bessel_Knu_scaled_e
fn knu_scaled(nu: f64, x: f64) -> (f64, f64) {
    if x <= 0.0f64 || nu < 0.0f64 { ret (0.0f64, 0.0f64) }
    let (v, e, e10) = knu_scaled_e10(nu, x)
    let (sv, se) = smash(v, e, e10)
    ret (sv, se)
}

// gsl_sf_bessel_Knu_e
fn knu(nu: f64, x: f64) -> (f64, f64) {
    let (bv, be) = knu_scaled(nu, x)
    let (v, e) = ga.exp_mult_err(0.0f64 - x, 0.0f64, bv, be)
    ret (v, e)
}

// gsl_sf_bessel_lnKnu_e
fn bessel_lnknu(nu: f64, x: f64) -> (f64, f64) {
    if x <= 0.0f64 || nu < 0.0f64 { ret (0.0f64, 0.0f64) }
    if nu == 0.0f64 {
        let (kv, ke) = gb.k0_scaled(x)
        let v = 0.0f64 - x + math.log[f64](u_a(kv))
        var er = u_eps() * u_a(x) + u_a(ke / kv)
        er += u_eps() * u_a(v)
        ret (v, er)
    }
    if x < 2.0f64 && nu > 1.0f64 {
        let (lgv, lge) = gc.lngamma_e(nu)
        let ln_bound = -0.693147180559945309417232121458f64 - nu * math.log[f64](0.5f64 * x) + lgv
        if ln_bound > u_lmax() - 20.0f64 {
            let xi = 0.25f64 * x * x
            var sum = 1.0f64 - xi / (nu - 1.0f64)
            if nu > 2.0f64 { sum += (xi / (nu - 1.0f64)) * (xi / (nu - 2.0f64)) }
            let v = ln_bound + math.log[f64](sum)
            ret (v, lge + 2.0f64 * u_eps() * u_a(v))
        }
    }
    let (kv2, ke2, e10) = knu_scaled_e10(nu, x)
    let v2 = 0.0f64 - x + math.log[f64](u_a(kv2)) + e10 * u_ln10()
    var er2 = u_eps() * u_a(x) + u_a(ke2 / kv2)
    er2 += u_eps() * u_a(v2)
    ret (v2, er2)
}

// ---- integer orders with the Olver and Taylor branches ----

fn jn_full(ar: *mem.Arena, n0: i64, x0: f64) -> (f64, f64) {
    var n = n0
    var x = x0
    var sign = 1.0f64
    if n < 0i64 {
        n = 0i64 - n
        if n % 2i64 == 1i64 { sign = 0.0f64 - sign }
    }
    if x < 0.0f64 {
        x = 0.0f64 - x
        if n % 2i64 == 1i64 { sign = 0.0f64 - sign }
    }
    if n == 0i64 {
        let (v0, e0) = gj.j0(x)
        ret (sign * v0, e0)
    }
    if n == 1i64 {
        let (v1, e1) = gj.j1(x)
        ret (sign * v1, e1)
    }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    let nf = f64(n)
    if x * x < 10.0f64 * (nf + 1.0f64) * 7.4009597974140505e-04f64 {
        let (tv, te) = ij_taylor(ar, nf, x, -1.0f64, 50i64)
        let v = sign * tv
        ret (v, te + u_eps() * u_a(v))
    }
    if 1.2207031250000000e-04f64 * x > nf * nf + 1.0f64 {
        let (av, ae) = gj.jnu_asympx(nf, x)
        ret (sign * av, ae)
    }
    if n > 50i64 {
        let (ov, oe) = jnu_olver(nf, x)
        ret (sign * ov, oe)
    }
    if x > 1000.0f64 {
        let (bv, be) = gj.jnu_asympx(nf, x)
        ret (sign * bv, be)
    }
    let (v2, e2) = gj.jn(n0, x0)
    ret (v2, e2)
}

fn yn_full(n0: i64, x: f64) -> (f64, f64) {
    var n = n0
    if n < 0i64 { n = 0i64 - n }
    var sign = 1.0f64
    if n0 < 0i64 && n % 2i64 == 1i64 { sign = -1.0f64 }
    if n > 50i64 && x >= 5.0f64 && !(u_root3() * x > f64(n) * f64(n) + 1.0f64) {
        let (ov, oe) = ynu_olver(f64(n), x)
        ret (sign * ov, oe)
    }
    let (v, e) = gn.bessel_yn(n0, x)
    ret (v, e)
}

fn kn_scaled_full(n0: i64, x: f64) -> (f64, f64) {
    var n = n0
    if n < 0i64 { n = 0i64 - n }
    let nf = f64(n)
    var cut = 0.29f64 / (nf * nf)
    if 0.5f64 / (nf * nf + x * x) < cut { cut = 0.5f64 / (nf * nf + x * x) }
    if n >= 2i64 && x > 5.0f64 && !(u_root3() * x > 0.25f64 * (nf * nf + 1.0f64)) && cut < u_root3() {
        let (uv, ue) = knu_scaled_unif(nf, x)
        ret (uv, ue)
    }
    let (v, e) = gn.kn_scaled(n0, x)
    ret (v, e)
}

fn kn_full(n0: i64, x: f64) -> (f64, f64) {
    let (sv, se) = kn_scaled_full(n0, x)
    let ex = math.exp[f64](0.0f64 - x)
    let v = sv * ex
    ret (v, se * ex + x * u_eps() * u_a(v))
}

fn in_scaled_full(ar: *mem.Arena, n0: i64, x: f64) -> (f64, f64) {
    var n = n0
    if n < 0i64 { n = 0i64 - n }
    let ax = u_a(x)
    let nf = f64(n)
    if n <= 1i64 || x == 0.0f64 || x * x < 10.0f64 * (nf + 1.0f64) / 2.718281828459045235360287471353f64 || (n < 150i64 && ax < 1.0e7f64) {
        let (v, e) = gn.in_scaled(ar, n0, x)
        ret (v, e)
    }
    var odd_neg = false
    if x < 0.0f64 && n % 2i64 == 1i64 { odd_neg = true }
    var cut = 0.29f64 / (nf * nf)
    if 0.5f64 / (nf * nf + x * x) < cut { cut = 0.5f64 / (nf * nf + x * x) }
    if cut < 0.5f64 * u_root3() {
        let (uv, ue) = inu_scaled_unif(nf, ax)
        if odd_neg { ret (0.0f64 - uv, ue) }
        ret (uv, ue)
    }
    let nhi = 2i64 + i64(1.2f64 / 2.4607833005759251e-03f64)
    let (r1v, r1e) = inu_scaled_unif(f64(nhi) + 1.0f64, ax)
    let (r0v, r0e) = inu_scaled_unif(f64(nhi), ax)
    var ikp1 = r1v
    var ik = r0v
    var k = nhi
    while k > n {
        let ikm1 = ikp1 + 2.0f64 * f64(k) / ax * ik
        ikp1 = ik
        ik = ikm1
        k -= 1i64
    }
    let er = ik * (r1e / r1v + r0e / r0v)
    if odd_neg { ret (0.0f64 - ik, er) }
    ret (ik, er)
}

fn in_full(ar: *mem.Arena, n0: i64, x: f64) -> (f64, f64) {
    var n = n0
    if n < 0i64 { n = 0i64 - n }
    let ax = u_a(x)
    let (sv, se) = in_scaled_full(ar, n, ax)
    if ax > u_lmax() - 1.0f64 { ret (0.0f64, 0.0f64) }
    let ex = math.exp[f64](ax)
    var v = ex * sv
    let e = ex * se + ax * u_eps() * u_a(v)
    if x < 0.0f64 && n % 2i64 == 1i64 { v = 0.0f64 - v }
    ret (v, e)
}
