// R gsl, coupling_3j, coupling_6j and coupling_9j with gsl_sf_result.err: a port of specfunc/coupling.c (arguments are twice the angular momenta). Each returns (value, error);
// a domain error, a selection rule or an overflow returns (0, 0).

use e.math
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslerr as ge
use e.algo.stat.gslerr2 as g2

fn k_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn ka(x: f64) -> f64 { ret math.abs[f64](x) }
fn iabs(x: i64) -> i64 {
    if x < 0i64 { ret 0i64 - x }
    ret x
}
fn imax(a: i64, b: i64) -> i64 {
    if a > b { ret a }
    ret b
}
fn imin(a: i64, b: i64) -> i64 {
    if a < b { ret a }
    ret b
}
fn is_odd(x: i64) -> bool { ret x % 2i64 != 0i64 }

// gsl_sf_fact_e; n above 170 overflows
fn fact_e(n: i64) -> (f64, f64, bool) {
    if n < 0i64 || n > 170i64 { ret (0.0f64, 0.0f64, false) }
    let (v, e) = ge.e_fact(usize(n))
    ret (v, e, true)
}

fn triangle_fails(a: i64, b: i64, c: i64) -> bool {
    ret b < iabs(a - c) || b > a + c || is_odd(a + b + c)
}

fn m_fails(ja: i64, jb: i64, jc: i64, ma: i64, mb: i64, mc: i64) -> bool {
    ret iabs(ma) > ja || iabs(mb) > jb || iabs(mc) > jc || is_odd(ja + ma) || is_odd(jb + mb) || is_odd(jc + mc) || ma + mb + mc != 0i64
}

fn lnc(n: i64, m: i64) -> (f64, f64) {
    let (v, e) = g2.e_lnchoose(usize(n), usize(m))
    ret (v, e)
}

fn coupling_3j(ja: i64, jb: i64, jc: i64, ma: i64, mb: i64, mc: i64) -> (f64, f64) {
    if ja < 0i64 || jb < 0i64 || jc < 0i64 { ret (0.0f64, 0.0f64) }
    if triangle_fails(ja, jb, jc) || m_fails(ja, jb, jc, ma, mb, mc) { ret (0.0f64, 0.0f64) }
    if ma == 0i64 && mb == 0i64 && mc == 0i64 && (ja + jb + jc) % 4i64 == 2i64 { ret (0.0f64, 0.0f64) }
    let jca = (0i64 - ja + jb + jc) / 2i64
    let jcb = (ja - jb + jc) / 2i64
    let jcc = (ja + jb - jc) / 2i64
    let jmma = (ja - ma) / 2i64
    let jmmb = (jb - mb) / 2i64
    let jpmb = (jb + mb) / 2i64
    let jpmc = (jc + mc) / 2i64
    let jsum = (ja + jb + jc) / 2i64
    let jpma = (ja + ma) / 2i64
    let kmin = imax(imax(0i64, jpmb - (jc - mc) / 2i64), jmma - jpmc)
    let kmax = imin(imin(jcc, jmma), jpmb)
    var sign = 1i64
    if is_odd(kmin - jpma + jmmb) { sign = -1i64 }
    var sum_pos = 0.0f64
    var sum_neg = 0.0f64
    var sum_err = 0.0f64
    let (n1v, n1e) = lnc(ja, jcc)
    let (n2v, n2e) = lnc(jb, jcc)
    let (d1v, d1e) = lnc(jsum + 1i64, jcc)
    let (d2v, d2e) = lnc(ja, jmma)
    let (d3v, d3e) = lnc(jb, jmmb)
    let (d4v, d4e) = lnc(jc, jpmc)
    let lnorm_v = 0.5f64 * (n1v + n2v - d1v - d2v - d3v - d4v - math.log[f64](f64(jc) + 1.0f64))
    let lnorm_e = 0.5f64 * (n1e + n2e + d1e + d2e + d3e + d4e + k_eps() * math.log[f64](f64(jc) + 1.0f64))
    var k = kmin
    while k <= kmax {
        let (b1v, b1e) = lnc(jcc, k)
        let (b2v, b2e) = lnc(jcb, jmma - k)
        let (b3v, b3e) = lnc(jca, jpmb - k)
        let (tv, te, _s) = gc.exp_err(b1v + b2v + b3v + lnorm_v, b1e + b2e + b3e + lnorm_e)
        if sign < 0i64 {
            sum_neg += tv
        }
        if sign >= 0i64 {
            sum_pos += tv
        }
        sum_err += te
        sign = 0i64 - sign
        k += 1i64
    }
    let v = sum_pos - sum_neg
    var er = sum_err
    er += 2.0f64 * k_eps() * (sum_pos + sum_neg)
    er += 2.0f64 * k_eps() * f64(kmax - kmin) * ka(v)
    ret (v, er)
}

// the delta of the 6j symbol
fn delta6(ta: i64, tb: i64, tc: i64) -> (f64, f64, bool) {
    let (f1, _e1, o1) = fact_e((ta + tb - tc) / 2i64)
    let (f2, _e2, o2) = fact_e((ta + tc - tb) / 2i64)
    let (f3, _e3, o3) = fact_e((tb + tc - ta) / 2i64)
    let (f4, _e4, o4) = fact_e((ta + tb + tc) / 2i64 + 1i64)
    if !(o1 && o2 && o3 && o4) { ret (0.0f64, 0.0f64, false) }
    let v = f1 * f2 * f3 / f4
    ret (v, 4.0f64 * k_eps() * ka(v), true)
}

fn coupling_6j(ja: i64, jb: i64, jc: i64, jd: i64, je: i64, jf: i64) -> (f64, f64) {
    if ja < 0i64 || jb < 0i64 || jc < 0i64 || jd < 0i64 || je < 0i64 || jf < 0i64 { ret (0.0f64, 0.0f64) }
    if triangle_fails(ja, jb, jc) || triangle_fails(ja, je, jf) || triangle_fails(jb, jd, jf) || triangle_fails(je, jd, jc) { ret (0.0f64, 0.0f64) }
    let (d1, _a1, k1) = delta6(ja, jb, jc)
    let (d2, _a2, k2) = delta6(ja, je, jf)
    let (d3, _a3, k3) = delta6(jb, jd, jf)
    let (d4, _a4, k4) = delta6(je, jd, jc)
    if !(k1 && k2 && k3 && k4) { ret (0.0f64, 0.0f64) }
    let norm = math.sqrt[f64](d1) * math.sqrt[f64](d2) * math.sqrt[f64](d3) * math.sqrt[f64](d4)
    let tkmin = imax(imax(0i64, ja + jd - jc - jf), jb + je - jc - jf)
    let tkmax = imin(imin(imin(ja + jb + je + jd + 2i64, ja + jb - jc), imin(je + jd - jc, ja + je - jf)), jb + jd - jf)
    var phase = 1.0f64
    if is_odd((ja + jb + je + jd + tkmin) / 2i64) { phase = -1.0f64 }
    var sum_pos = 0.0f64
    var sum_neg = 0.0f64
    var sumsq_err = 0.0f64
    var tk = tkmin
    while tk <= tkmax {
        let (n1, n1e, o1) = fact_e((ja + jb + je + jd - tk) / 2i64 + 1i64)
        let (d1a, d1ae, o2) = fact_e(tk / 2i64)
        let (d1b, d1be, o3) = fact_e((jc + jf - ja - jd + tk) / 2i64)
        let (e2, e2e, o4) = fact_e((jc + jf - jb - je + tk) / 2i64)
        let (e3, e3e, o5) = fact_e((ja + jb - jc - tk) / 2i64)
        let (e4, e4e, o6) = fact_e((je + jd - jc - tk) / 2i64)
        let (e5, e5e, o7) = fact_e((ja + je - jf - tk) / 2i64)
        let (e6, e6e, o8) = fact_e((jb + jd - jf - tk) / 2i64)
        if !(o1 && o2 && o3 && o4 && o5 && o6 && o7 && o8) { ret (0.0f64, 0.0f64) }
        let e1v = d1a * d1b
        let e1e = d1ae * ka(d1b) + ka(d1a) * d1be
        let den1v = e1v * e2 * e3
        var den1e = e1e * ka(e2 * e3)
        den1e += e2e * ka(e1v * e3)
        den1e += e3e * ka(e1v * e2)
        let den2v = e4 * e5 * e6
        var den2e = e4e * ka(e5 * e6)
        den2e += e5e * ka(e4 * e6)
        den2e += e6e * ka(e4 * e5)
        let term = phase * n1 / den1v / den2v
        phase = 0.0f64 - phase
        var term_err = n1e / ka(den1v) / ka(den2v)
        term_err += ka(term / den1v) * den1e
        term_err += ka(term / den2v) * den2e
        if term >= 0.0f64 {
            sum_pos += norm * term
        }
        if term < 0.0f64 {
            sum_neg -= norm * term
        }
        sumsq_err += norm * norm * term_err * term_err
        tk += 2i64
    }
    let v = sum_pos - sum_neg
    var er = 2.0f64 * k_eps() * (sum_pos + sum_neg)
    er += math.sqrt[f64](sumsq_err / (0.5f64 * f64(tkmax - tkmin) + 1.0f64))
    er += 2.0f64 * k_eps() * (f64(tkmax - tkmin) + 2.0f64) * ka(v)
    ret (v, er)
}

fn coupling_9j(ja: i64, jb: i64, jc: i64, jd: i64, je: i64, jf: i64, jg: i64, jh: i64, ji: i64) -> (f64, f64) {
    if ja < 0i64 || jb < 0i64 || jc < 0i64 || jd < 0i64 || je < 0i64 || jf < 0i64 || jg < 0i64 || jh < 0i64 || ji < 0i64 { ret (0.0f64, 0.0f64) }
    if triangle_fails(ja, jb, jc) || triangle_fails(jd, je, jf) || triangle_fails(jg, jh, ji) || triangle_fails(ja, jd, jg) || triangle_fails(jb, je, jh) || triangle_fails(jc, jf, ji) { ret (0.0f64, 0.0f64) }
    let tkmin = imax(imax(iabs(ja - ji), iabs(jh - jd)), iabs(jb - jf))
    let tkmax = imin(imin(ja + ji, jh + jd), jb + jf)
    var sum_pos = 0.0f64
    var sum_neg = 0.0f64
    var sumsq_err = 0.0f64
    var tk = tkmin
    while tk <= tkmax {
        let (s1, s1e) = coupling_6j(ja, ji, tk, jh, jd, jg)
        let (s2, s2e) = coupling_6j(jb, jf, tk, jd, jh, je)
        let (s3, s3e) = coupling_6j(ja, ji, tk, jf, jb, jc)
        let term = s1 * s2 * s3
        var term_err = s1e * ka(s2 * s3)
        term_err += s2e * ka(s1 * s3)
        term_err += s3e * ka(s1 * s2)
        if term >= 0.0f64 {
            sum_pos += f64(tk + 1i64) * term
        }
        if term < 0.0f64 {
            sum_neg -= f64(tk + 1i64) * term
        }
        sumsq_err += (f64(tk + 1i64) * term_err) * (f64(tk + 1i64) * term_err)
        tk += 2i64
    }
    var phase = 1.0f64
    if is_odd(tkmin) { phase = -1.0f64 }
    let v = phase * (sum_pos - sum_neg)
    var er = 2.0f64 * k_eps() * (sum_pos + sum_neg)
    er += math.sqrt[f64](sumsq_err / (0.5f64 * f64(tkmax - tkmin) + 1.0f64))
    er += 2.0f64 * k_eps() * (f64(tkmax - tkmin) + 2.0f64) * ka(v)
    ret (v, er)
}
