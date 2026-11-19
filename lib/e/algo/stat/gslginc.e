// R gsl, gamma_inc, gamma_inc_P, gamma_inc_Q and beta_inc with gsl_sf_result.err: a port of specfunc/gamma_inc.c and beta_inc.c (beta_inc for a, b > 0; the hypergeometric branch for a <= 0
// or b <= 0 is not here). Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslerf as gf
use e.algo.stat.gslerr as ge
use e.algo.stat.gslerr2 as g2
use e.algo.stat.gslspecial as gsp

fn i_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn ia(x: f64) -> f64 { ret math.abs[f64](x) }

// gsl_sf_exprel_n_CF_e
fn exprel_n_cf(nn: f64, x: f64) -> (f64, f64) {
    let recur_big = 1.3407807929942596e+154f64
    var n = 1i64
    var anm2 = 1.0f64
    var bnm2 = 0.0f64
    var anm1 = 0.0f64
    var bnm1 = 1.0f64
    let a1 = 1.0f64
    let b1 = 1.0f64
    let a2 = 0.0f64 - x
    let b2 = nn + 1.0f64
    var an = b1 * anm1 + a1 * anm2
    var bn = b1 * bnm1 + a1 * bnm2
    n += 1i64
    anm2 = anm1
    bnm2 = bnm1
    anm1 = an
    bnm1 = bn
    an = b2 * anm1 + a2 * anm2
    bn = b2 * bnm1 + a2 * bnm2
    var fnv = an / bn
    while n < 5000i64 {
        n += 1i64
        anm2 = anm1
        bnm2 = bnm1
        anm1 = an
        bnm1 = bn
        var cn = 0.0f64
        if n % 2i64 == 1i64 { cn = f64((n - 1i64) / 2i64) * x }
        if n % 2i64 == 0i64 { cn = 0.0f64 - (nn + f64(n / 2i64) - 1.0f64) * x }
        let dn = nn + f64(n) - 1.0f64
        an = dn * anm1 + cn * anm2
        bn = dn * bnm1 + cn * bnm2
        if ia(an) > recur_big || ia(bn) > recur_big {
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
        if ia(del - 1.0f64) < 2.0f64 * i_eps() { break }
    }
    ret (fnv, 4.0f64 * (f64(n) + 1.0f64) * i_eps() * ia(fnv))
}

// the dominant part x^a e^-x / Gamma(a+1)
fn gi_d(a: f64, x: f64) -> (f64, f64) {
    if a < 10.0f64 {
        let (lv, _le) = gc.lngamma_e(a + 1.0f64)
        let lnr = a * math.log[f64](x) - x - lv
        let v = math.exp[f64](lnr)
        ret (v, 2.0f64 * i_eps() * (ia(lnr) + 1.0f64) * ia(v))
    }
    var lnt = 0.0f64
    var lne = 0.0f64
    if x < 0.5f64 * a {
        let u = x / a
        let ln_u = math.log[f64](u)
        lnt = ln_u - u + 1.0f64
        lne = (ia(ln_u) + ia(u) + 1.0f64) * i_eps()
    }
    if x >= 0.5f64 * a {
        let mu = (x - a) / a
        let (mv, me) = g2.e_log_1plusx_mx(mu)
        lnt = mv
        lne = me + i_eps() * ia(mu)
    }
    let (gsv, gse) = g2.e_gammastar(a)
    let term1 = math.exp[f64](a * lnt) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64 * a)
    let v = term1 / gsv
    var er = 2.0f64 * i_eps() * (ia(a * lnt) + 1.0f64) * ia(v)
    er += ia(a) * lne * ia(v)
    er += gse / ia(gsv) * ia(v)
    ret (v, er)
}

fn gi_p_series(a: f64, x: f64) -> (f64, f64) {
    let (dv, de) = gi_d(a, x)
    if x > 0.995f64 * a && a > 1.0e5f64 {
        let (cv, ce) = exprel_n_cf(a, x)
        ret (dv * cv, ia(dv * ce) + ia(de * cv))
    }
    if x > a + 10000.0f64 { ret (0.0f64, 0.0f64) }
    var sum = 1.0f64
    var term = 1.0f64
    var n = 1i64
    var nlow = 0i64
    if x > a { nlow = i64(x - a) }
    while n < nlow {
        term = term * (x / (a + f64(n)))
        sum += term
        n += 1i64
    }
    while n < 10000i64 {
        term = term * (x / (a + f64(n)))
        sum += term
        if ia(term / sum) < i_eps() { break }
        n += 1i64
    }
    let tnp1 = (x / (a + f64(n))) * term
    let remainder = tnp1 / (1.0f64 - x / (a + f64(n) + 1.0f64))
    let v = dv * sum
    var er = de * ia(sum) + ia(dv * remainder)
    er += (1.0f64 + f64(n)) * i_eps() * ia(v)
    ret (v, er)
}

fn gi_q_large_x(a: f64, x: f64) -> (f64, f64) {
    let (dv, de) = gi_d(a, x)
    var sum = 1.0f64
    var term = 1.0f64
    var last = 1.0f64
    var n = 1i64
    while n < 5000i64 {
        term = term * ((a - f64(n)) / x)
        if ia(term / last) > 1.0f64 { break }
        if ia(term / sum) < i_eps() { break }
        sum += term
        last = term
        n += 1i64
    }
    let v = dv * (a / x) * sum
    ret (v, de * ia((a / x) * sum) + 2.0f64 * i_eps() * ia(v))
}

fn gi_q_asymp_unif(a: f64, x: f64) -> (f64, f64) {
    let rta = math.sqrt[f64](a)
    let ep = (x - a) / a
    let (lv, _le) = g2.e_log_1plusx_mx(ep)
    var sg = 1.0f64
    if ep < 0.0f64 { sg = -1.0f64 }
    if ep == 0.0f64 { sg = 1.0f64 }
    let eta = sg * math.sqrt[f64](-2.0f64 * lv)
    let (efv, efe) = gf.erfc(eta * rta / 1.4142135623730950488f64)
    var c0 = 0.0f64
    var c1 = 0.0f64
    if ia(ep) < 7.4009597974140505e-04f64 {
        c0 = -1.0f64 / 3.0f64 + ep * (1.0f64 / 12.0f64 - ep * (23.0f64 / 540.0f64 - ep * (353.0f64 / 12960.0f64 - ep * 589.0f64 / 30240.0f64)))
        c1 = -1.0f64 / 540.0f64 - ep / 288.0f64
    }
    if ia(ep) >= 7.4009597974140505e-04f64 {
        let rt_term = math.sqrt[f64](-2.0f64 * lv / (ep * ep))
        let lam = x / a
        c0 = (1.0f64 - 1.0f64 / rt_term) / ep
        c1 = 0.0f64 - (eta * eta * eta * (lam * lam + 10.0f64 * lam + 1.0f64) - 12.0f64 * ep * ep * ep) / (12.0f64 * eta * eta * eta * ep * ep * ep)
    }
    let r = math.exp[f64](-0.5f64 * a * eta * eta) / (1.4142135623730950488f64 * 1.7724538509055160273f64 * rta) * (c0 + c1 / a)
    let v = 0.5f64 * efv + r
    var er = i_eps() * ia(r * 0.5f64 * a * eta * eta) + 0.5f64 * efe
    er += 2.0f64 * i_eps() * ia(v)
    ret (v, er)
}

fn gi_f_cf(a: f64, x: f64) -> (f64, f64) {
    let small = i_eps() * i_eps() * i_eps()
    var hn = 1.0f64
    var cn = 1.0f64 / small
    var dn = 1.0f64
    var n = 2i64
    while n < 5000i64 {
        var an = 0.0f64
        if n % 2i64 == 1i64 { an = 0.5f64 * f64(n - 1i64) / x }
        if n % 2i64 == 0i64 { an = (0.5f64 * f64(n) - a) / x }
        dn = 1.0f64 + an * dn
        if ia(dn) < small { dn = small }
        cn = 1.0f64 + an / cn
        if ia(cn) < small { cn = small }
        dn = 1.0f64 / dn
        let delta = cn * dn
        hn = hn * delta
        if ia(delta - 1.0f64) < i_eps() { break }
        n += 1i64
    }
    var er = 2.0f64 * i_eps() * ia(hn)
    er += i_eps() * (2.0f64 + 0.5f64 * f64(n)) * ia(hn)
    ret (hn, er)
}

fn gi_q_cf(a: f64, x: f64) -> (f64, f64) {
    let (dv, de) = gi_d(a, x)
    let (fv, fe) = gi_f_cf(a, x)
    let v = dv * (a / x) * fv
    ret (v, de * ia((a / x) * fv) + ia(dv * a / x * fe))
}

fn gi_q_series(a: f64, x: f64) -> (f64, f64) {
    let pg21 = -2.404113806319188570799476f64
    let lnx = math.log[f64](x)
    let el = 0.577215664901532860606512090082f64 + lnx
    let pi2 = 3.141592653589793238462643383279f64 * 3.141592653589793238462643383279f64
    let c1 = 0.0f64 - el
    let c2 = pi2 / 12.0f64 - 0.5f64 * el * el
    let c3 = el * (pi2 / 12.0f64 - el * el / 6.0f64) + pg21 / 6.0f64
    let c4 = -0.04166666666666666667f64 * (-1.758243446661483480f64 + lnx) * (-0.764428657272716373f64 + lnx) * (0.723980571623507657f64 + lnx) * (4.107554191916823640f64 + lnx)
    let c5 = -0.0083333333333333333f64 * (-2.06563396085715900f64 + lnx) * (-1.28459889470864700f64 + lnx) * (-0.27583535756454143f64 + lnx) * (1.33677371336239618f64 + lnx) * (5.17537282427561550f64 + lnx)
    let c6 = -0.0013888888888888889f64 * (-2.30814336454783200f64 + lnx) * (-1.65846557706987300f64 + lnx) * (-0.88768082560020400f64 + lnx) * (0.17043847751371778f64 + lnx) * (1.92135970115863890f64 + lnx) * (6.22578557795474900f64 + lnx)
    let c7 = -0.00019841269841269841f64 * (-2.5078657901291800f64 + lnx) * (-1.9478900888958200f64 + lnx) * (-1.3194837322612730f64 + lnx) * (-0.5281322700249279f64 + lnx) * (0.5913834939078759f64 + lnx) * (2.4876819633378140f64 + lnx) * (7.2648160783762400f64 + lnx)
    let c8 = -0.00002480158730158730f64 * (-2.677341544966400f64 + lnx) * (-2.182810448271700f64 + lnx) * (-1.649350342277400f64 + lnx) * (-1.014099048290790f64 + lnx) * (-0.191366955370652f64 + lnx) * (0.995403817918724f64 + lnx) * (3.041323283529310f64 + lnx) * (8.295966556941250f64 + lnx)
    let c9 = -2.75573192239859e-6f64 * (-2.8243487670469080f64 + lnx) * (-2.3798494322701120f64 + lnx) * (-1.9143674728689960f64 + lnx) * (-1.3814529102920370f64 + lnx) * (-0.7294312810261694f64 + lnx) * (0.1299079285269565f64 + lnx) * (1.3873333251885240f64 + lnx) * (3.5857258865210760f64 + lnx) * (9.3214237073814600f64 + lnx)
    let c10 = -2.75573192239859e-7f64 * (-2.9540329644556910f64 + lnx) * (-2.5491366926991850f64 + lnx) * (-2.1348279229279880f64 + lnx) * (-1.6741881076349450f64 + lnx) * (-1.1325949616098420f64 + lnx) * (-0.4590034650618494f64 + lnx) * (0.4399352987435699f64 + lnx) * (1.7702236517651670f64 + lnx) * (4.1231539047474080f64 + lnx) * (10.342627908148680f64 + lnx)
    let term1 = a * (c1 + a * (c2 + a * (c3 + a * (c4 + a * (c5 + a * (c6 + a * (c7 + a * (c8 + a * (c9 + a * c10)))))))))
    var t = 1.0f64
    var sum = 1.0f64
    var n = 1i64
    while n < 5000i64 {
        t = t * (0.0f64 - x / (f64(n) + 1.0f64))
        sum += (a + 1.0f64) / (a + f64(n) + 1.0f64) * t
        if ia(t / sum) < i_eps() { break }
        n += 1i64
    }
    let term2 = (1.0f64 - term1) * a / (a + 1.0f64) * x * sum
    let v = term1 + term2
    ret (v, i_eps() * (ia(term1) + 2.0f64 * ia(term2)) + 2.0f64 * i_eps() * ia(v))
}

fn gi_series(a: f64, x: f64) -> (f64, f64) {
    let (qv, qe) = gi_q_series(a, x)
    let (gv, ge2) = g2.e_gamma(a)
    let v = qv * gv
    ret (v, ia(qv * ge2) + ia(qe * gv) + 2.0f64 * i_eps() * ia(v))
}

fn gamma_inc_q(a: f64, x: f64) -> (f64, f64) {
    if a < 0.0f64 || x < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x == 0.0f64 { ret (1.0f64, 0.0f64) }
    if a == 0.0f64 { ret (0.0f64, 0.0f64) }
    if x <= 0.5f64 * a {
        let (pv, pe) = gi_p_series(a, x)
        let v = 1.0f64 - pv
        ret (v, pe + 2.0f64 * i_eps() * ia(v))
    }
    if a >= 1.0e+06f64 && (x - a) * (x - a) < a {
        let (v, e) = gi_q_asymp_unif(a, x)
        ret (v, e)
    }
    if a < 0.2f64 && x < 5.0f64 {
        let (v, e) = gi_q_series(a, x)
        ret (v, e)
    }
    if a <= x {
        if x <= 1.0e+06f64 {
            let (v, e) = gi_q_cf(a, x)
            ret (v, e)
        }
        let (v2, e2) = gi_q_large_x(a, x)
        ret (v2, e2)
    }
    if x > a - math.sqrt[f64](a) {
        let (v3, e3) = gi_q_cf(a, x)
        ret (v3, e3)
    }
    let (pv2, pe2) = gi_p_series(a, x)
    let v4 = 1.0f64 - pv2
    ret (v4, pe2 + 2.0f64 * i_eps() * ia(v4))
}

fn gamma_inc_p(a: f64, x: f64) -> (f64, f64) {
    if a <= 0.0f64 || x < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 20.0f64 || x < 0.5f64 * a {
        let (v, e) = gi_p_series(a, x)
        ret (v, e)
    }
    if a > 1.0e+06f64 && (x - a) * (x - a) < a {
        let (qv, qe) = gi_q_asymp_unif(a, x)
        let v2 = 1.0f64 - qv
        ret (v2, qe + 2.0f64 * i_eps() * ia(v2))
    }
    if a <= x {
        var qv2 = 0.0f64
        var qe2 = 0.0f64
        if a > 0.2f64 * x {
            let (v3, e3) = gi_q_cf(a, x)
            qv2 = v3
            qe2 = e3
        }
        if a <= 0.2f64 * x {
            let (v4, e4) = gi_q_large_x(a, x)
            qv2 = v4
            qe2 = e4
        }
        let v5 = 1.0f64 - qv2
        ret (v5, qe2 + 2.0f64 * i_eps() * ia(v5))
    }
    if (x - a) * (x - a) < a {
        let (qv3, qe3) = gi_q_cf(a, x)
        let v6 = 1.0f64 - qv3
        ret (v6, qe3 + 2.0f64 * i_eps() * ia(v6))
    }
    let (v7, e7) = gi_p_series(a, x)
    ret (v7, e7)
}

fn gi_a_gt_0(a: f64, x: f64) -> (f64, f64) {
    let (qv, qe) = gamma_inc_q(a, x)
    let (gv, ge2) = g2.e_gamma(a)
    let v = gv * qv
    ret (v, ia(gv * qe) + ia(ge2 * qv) + 2.0f64 * i_eps() * ia(v))
}

fn gi_cf(a: f64, x: f64) -> (f64, f64) {
    let am1lgx = (a - 1.0f64) * math.log[f64](x)
    let (fv, fe) = gi_f_cf(a, x)
    let (pv, pe, _s) = gc.exp_err(am1lgx - x, i_eps() * ia(am1lgx))
    let v = fv * pv
    ret (v, ia(fe * pv) + ia(fv * pe) + 2.0f64 * i_eps() * ia(v))
}

fn gamma_inc(a: f64, x: f64) -> (f64, f64) {
    if x < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x == 0.0f64 {
        let (v, e) = g2.e_gamma(a)
        ret (v, e)
    }
    if a == 0.0f64 {
        let (v1, e1) = gsp.expint_e1(x, false)
        ret (v1, e1)
    }
    if a > 0.0f64 {
        let (v2, e2) = gi_a_gt_0(a, x)
        ret (v2, e2)
    }
    if x > 0.25f64 {
        let (v3, e3) = gi_cf(a, x)
        ret (v3, e3)
    }
    if ia(a) < 0.5f64 {
        let (qv, qe) = gi_series(a, x)
        ret (qv, qe)
    }
    let fl = math.floor[f64](a)
    let da = a - fl
    var gax = 0.0f64
    if da > 0.0f64 {
        let (gv, _ge) = gi_a_gt_0(da, x)
        gax = gv
    }
    if da <= 0.0f64 {
        let (gv2, _ge2) = gsp.expint_e1(x, false)
        gax = gv2
    }
    var alpha = da
    var go = true
    while go {
        let shift = math.exp[f64](0.0f64 - x + (alpha - 1.0f64) * math.log[f64](x))
        gax = (gax - shift) / (alpha - 1.0f64)
        alpha -= 1.0f64
        if !(alpha > a) { go = false }
    }
    ret (gax, 2.0f64 * (1.0f64 + ia(a)) * i_eps() * ia(gax))
}

fn beta_cont_frac(a: f64, b: f64, x: f64) -> (f64, f64) {
    let cutoff = 2.0f64 * 2.2250738585072014e-308f64
    var iter_count = 0i64
    var num_term = 1.0f64
    var den_term = 1.0f64 - (a + b) * x / (a + 1.0f64)
    if ia(den_term) < cutoff { den_term = cutoff }
    den_term = 1.0f64 / den_term
    var cf = den_term
    while iter_count < 512i64 {
        let k = f64(iter_count + 1i64)
        var coeff = k * (b - k) * x / (((a - 1.0f64) + 2.0f64 * k) * (a + 2.0f64 * k))
        den_term = 1.0f64 + coeff * den_term
        num_term = 1.0f64 + coeff / num_term
        if ia(den_term) < cutoff { den_term = cutoff }
        if ia(num_term) < cutoff { num_term = cutoff }
        den_term = 1.0f64 / den_term
        var delta_frac = den_term * num_term
        cf = cf * delta_frac
        coeff = 0.0f64 - (a + k) * (a + b + k) * x / ((a + 2.0f64 * k) * (a + 2.0f64 * k + 1.0f64))
        den_term = 1.0f64 + coeff * den_term
        num_term = 1.0f64 + coeff / num_term
        if ia(den_term) < cutoff { den_term = cutoff }
        if ia(num_term) < cutoff { num_term = cutoff }
        den_term = 1.0f64 / den_term
        delta_frac = den_term * num_term
        cf = cf * delta_frac
        if ia(delta_frac - 1.0f64) < 2.0f64 * i_eps() { break }
        iter_count += 1i64
    }
    ret (cf, f64(iter_count) * 4.0f64 * i_eps() * ia(cf))
}

fn beta_inc(a: f64, b: f64, x: f64) -> (f64, f64) {
    if x < 0.0f64 || x > 1.0f64 { ret (0.0f64, 0.0f64) }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    if x == 1.0f64 { ret (1.0f64, 0.0f64) }
    let (lbv, lbe) = g2.e_lnbeta(a, b)
    let (l1v, l1e) = g2.e_log_1plusx(0.0f64 - x)
    let (lxv, lxe) = ge.e_log(x)
    let ln_pre_val = 0.0f64 - lbv + a * lxv + b * l1v
    let ln_pre_err = lbe + ia(a * lxe) + ia(b * l1e)
    let (pv, pe, _s) = gc.exp_err(ln_pre_val, ln_pre_err)
    if x < (a + 1.0f64) / (a + b + 2.0f64) {
        let (cv, ce) = beta_cont_frac(a, b, x)
        ret (pv * cv / a, (ia(pe * cv) + ia(pv * ce)) / a)
    }
    let (cv2, ce2) = beta_cont_frac(b, a, 1.0f64 - x)
    let term = pv * cv2 / b
    var er = ia(pe * cv2) / b
    er += ia(pv * ce2) / b
    er += 2.0f64 * i_eps() * (1.0f64 + ia(term))
    ret (1.0f64 - term, er)
}
