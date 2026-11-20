// R gsl, hyperg_2F1, hyperg_2F1_conj, hyperg_2F1_renorm and hyperg_2F1_conj_renorm with gsl_sf_result.err: a port of specfunc/hyperg_2F1.c over the gamma, psi and 1F1 pieces of the sibling
// gsl modules. Every function returns (value, error); a domain error returns (NaN, NaN) and an unimplemented region (0, 0), both of which gsl reports with a nonzero status.

use e.math
use e.mem
use e.algo.stat.gslhg as gg
use e.algo.stat.gslpsi as gps
use e.algo.stat.gslcoulomb as gc

fn k_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn k_loc() -> f64 { ret 1000.0f64 * 2.2204460492503131e-16f64 }
fn k_nan() -> f64 { ret 0.0f64 / 0.0f64 }
fn k_lmax() -> f64 { ret 7.0978271289338397e+02f64 }
fn ka(x: f64) -> f64 { ret math.abs[f64](x) }
fn kfl(x: f64) -> f64 { ret math.floor[f64](x) }
fn klg(x: f64) -> f64 { ret math.log[f64](x) }
fn kodd(n: i64) -> bool { ret n % 2i64 != 0i64 }

fn series(a: f64, b: f64, c: f64, x: f64) -> (f64, f64) {
    var sum_pos = 1.0f64
    var sum_neg = 0.0f64
    var del_pos = 1.0f64
    var del_neg = 0.0f64
    var del = 1.0f64
    var k = 0.0f64
    var i = 0i64
    if ka(c) < k_eps() { ret (0.0f64, 1.0f64) }
    while true {
        i += 1i64
        if i > 30000i64 {
            let v0 = sum_pos - sum_neg
            var e0 = del_pos + del_neg
            e0 += 2.0f64 * k_eps() * (sum_pos + sum_neg)
            e0 += 2.0f64 * k_eps() * (2.0f64 * math.sqrt[f64](k) + 1.0f64) * ka(v0)
            ret (v0, e0)
        }
        let del_prev = del
        del = del * ((a + k) * (b + k) * x / ((c + k) * (k + 1.0f64)))
        if del > 0.0f64 {
            del_pos = del
            sum_pos += del
        } else {
            if del == 0.0f64 {
                del_pos = 0.0f64
                del_neg = 0.0f64
                break
            }
            del_neg = 0.0f64 - del
            sum_neg -= del
        }
        if ka(del_prev / (sum_pos - sum_neg)) < k_eps() && ka(del / (sum_pos - sum_neg)) < k_eps() { break }
        k += 1.0f64
        if !(ka((del_pos + del_neg) / (sum_pos - sum_neg)) > k_eps()) { break }
    }
    let v = sum_pos - sum_neg
    var e = del_pos + del_neg
    e += 2.0f64 * k_eps() * (sum_pos + sum_neg)
    e += 2.0f64 * k_eps() * (2.0f64 * math.sqrt[f64](k) + 1.0f64) * ka(v)
    ret (v, e)
}

fn conj_series(ar: f64, ai: f64, c: f64, x: f64) -> (f64, f64) {
    if c == 0.0f64 { ret (0.0f64, 0.0f64) }
    var sum_pos = 1.0f64
    var sum_neg = 0.0f64
    var del_pos = 1.0f64
    var del_neg = 0.0f64
    var del = 1.0f64
    var k = 0.0f64
    while true {
        del = del * (((ar + k) * (ar + k) + ai * ai) / ((k + 1.0f64) * (c + k)) * x)
        if del >= 0.0f64 {
            del_pos = del
            sum_pos += del
        } else {
            del_neg = 0.0f64 - del
            sum_neg -= del
        }
        if k > 30000.0f64 {
            let v0 = sum_pos - sum_neg
            var e0 = del_pos + del_neg
            e0 += 2.0f64 * k_eps() * (sum_pos + sum_neg)
            e0 += 2.0f64 * k_eps() * (2.0f64 * math.sqrt[f64](k) + 1.0f64) * ka(v0)
            ret (v0, e0)
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

fn luke(a: f64, b: f64, c: f64, xin: f64) -> (f64, f64) {
    let big = 1.0e+50f64
    var n = 3i64
    let x = 0.0f64 - xin
    let x3 = x * x * x
    let t0 = a * b / c
    let t1 = (a + 1.0f64) * (b + 1.0f64) / (2.0f64 * c)
    let t2 = (a + 2.0f64) * (b + 2.0f64) / (2.0f64 * (c + 1.0f64))
    var fv = 1.0f64
    var prec = 0.0f64
    var bnm3 = 1.0f64
    var bnm2 = 1.0f64 + t1 * x
    var bnm1 = 1.0f64 + t2 * x * (1.0f64 + t1 / 3.0f64 * x)
    var anm3 = 1.0f64
    var anm2 = bnm2 - t0 * x
    var anm1 = bnm1 - t0 * (1.0f64 + t2 * x) * x + t0 * t1 * (c / (c + 1.0f64)) * x * x
    while true {
        let nf = f64(n)
        let npam1 = nf + a - 1.0f64
        let npbm1 = nf + b - 1.0f64
        let npcm1 = nf + c - 1.0f64
        let npam2 = nf + a - 2.0f64
        let npbm2 = nf + b - 2.0f64
        let npcm2 = nf + c - 2.0f64
        let tnm1 = 2.0f64 * nf - 1.0f64
        let tnm3 = 2.0f64 * nf - 3.0f64
        let tnm5 = 2.0f64 * nf - 5.0f64
        let n2 = nf * nf
        let f1 = (3.0f64 * n2 + (a + b - 6.0f64) * nf + 2.0f64 - a * b - 2.0f64 * (a + b)) / (2.0f64 * tnm3 * npcm1)
        let f2 = 0.0f64 - (3.0f64 * n2 - (a + b + 6.0f64) * nf + 2.0f64 - a * b) * npam1 * npbm1 / (4.0f64 * tnm1 * tnm3 * npcm2 * npcm1)
        let f3 = (npam2 * npam1 * npbm2 * npbm1 * (nf - a - 2.0f64) * (nf - b - 2.0f64)) / (8.0f64 * tnm3 * tnm3 * tnm5 * (nf + c - 3.0f64) * npcm2 * npcm1)
        let ee = 0.0f64 - npam1 * npbm1 * (nf - c - 1.0f64) / (2.0f64 * tnm3 * npcm2 * npcm1)
        var an = (1.0f64 + f1 * x) * anm1 + (ee + f2 * x) * x * anm2 + f3 * x3 * anm3
        var bn = (1.0f64 + f1 * x) * bnm1 + (ee + f2 * x) * x * bnm2 + f3 * x3 * bnm3
        let r = an / bn
        prec = ka((fv - r) / fv)
        fv = r
        if prec < k_eps() || n > 20000i64 { break }
        if ka(an) > big || ka(bn) > big {
            an = an / big
            bn = bn / big
            anm1 = anm1 / big
            bnm1 = bnm1 / big
            anm2 = anm2 / big
            bnm2 = bnm2 / big
            anm3 = anm3 / big
            bnm3 = bnm3 / big
        } else {
            if ka(an) < 1.0f64 / big || ka(bn) < 1.0f64 / big {
                an = an * big
                bn = bn * big
                anm1 = anm1 * big
                bnm1 = bnm1 * big
                anm2 = anm2 * big
                bnm2 = bnm2 * big
                anm3 = anm3 * big
                bnm3 = bnm3 * big
            }
        }
        n += 1i64
        bnm3 = bnm2
        bnm2 = bnm1
        bnm1 = bn
        anm3 = anm2
        anm2 = anm1
        anm1 = an
    }
    var er = 2.0f64 * ka(prec * fv)
    er += 2.0f64 * k_eps() * (f64(n) + 1.0f64) * ka(fv)
    er = er * (8.0f64 * (ka(a) + ka(b) + 1.0f64))
    ret (fv, er)
}

fn conj_luke(ar: f64, ai: f64, c: f64, xin: f64) -> (f64, f64) {
    let big = 1.0e+50f64
    var n = 3i64
    let x = 0.0f64 - xin
    let x3 = x * x * x
    let atimesb = ar * ar + ai * ai
    let apb = 2.0f64 * ar
    let t0 = atimesb / c
    let t1 = (atimesb + apb + 1.0f64) / (2.0f64 * c)
    let t2 = (atimesb + 2.0f64 * apb + 4.0f64) / (2.0f64 * (c + 1.0f64))
    var fv = 1.0f64
    var prec = 0.0f64
    var bnm3 = 1.0f64
    var bnm2 = 1.0f64 + t1 * x
    var bnm1 = 1.0f64 + t2 * x * (1.0f64 + t1 / 3.0f64 * x)
    var anm3 = 1.0f64
    var anm2 = bnm2 - t0 * x
    var anm1 = bnm1 - t0 * (1.0f64 + t2 * x) * x + t0 * t1 * (c / (c + 1.0f64)) * x * x
    while true {
        let nf = f64(n)
        let nm1 = nf - 1.0f64
        let nm2 = nf - 2.0f64
        let npam1_npbm1 = atimesb + nm1 * apb + nm1 * nm1
        let npam2_npbm2 = atimesb + nm2 * apb + nm2 * nm2
        let npcm1 = nm1 + c
        let npcm2 = nm2 + c
        let tnm1 = 2.0f64 * nf - 1.0f64
        let tnm3 = 2.0f64 * nf - 3.0f64
        let tnm5 = 2.0f64 * nf - 5.0f64
        let n2 = nf * nf
        let f1 = (3.0f64 * n2 + (apb - 6.0f64) * nf + 2.0f64 - atimesb - 2.0f64 * apb) / (2.0f64 * tnm3 * npcm1)
        let f2 = 0.0f64 - (3.0f64 * n2 - (apb + 6.0f64) * nf + 2.0f64 - atimesb) * npam1_npbm1 / (4.0f64 * tnm1 * tnm3 * npcm2 * npcm1)
        let f3 = (npam2_npbm2 * npam1_npbm1 * (nm2 * nm2 - nm2 * apb + atimesb)) / (8.0f64 * tnm3 * tnm3 * tnm5 * (nf + c - 3.0f64) * npcm2 * npcm1)
        let ee = 0.0f64 - npam1_npbm1 * (nf - c - 1.0f64) / (2.0f64 * tnm3 * npcm2 * npcm1)
        var an = (1.0f64 + f1 * x) * anm1 + (ee + f2 * x) * x * anm2 + f3 * x3 * anm3
        var bn = (1.0f64 + f1 * x) * bnm1 + (ee + f2 * x) * x * bnm2 + f3 * x3 * bnm3
        let r = an / bn
        prec = ka(fv - r) / ka(fv)
        fv = r
        if prec < k_eps() || n > 10000i64 { break }
        if ka(an) > big || ka(bn) > big {
            an = an / big
            bn = bn / big
            anm1 = anm1 / big
            bnm1 = bnm1 / big
            anm2 = anm2 / big
            bnm2 = bnm2 / big
            anm3 = anm3 / big
            bnm3 = bnm3 / big
        } else {
            if ka(an) < 1.0f64 / big || ka(bn) < 1.0f64 / big {
                an = an * big
                bn = bn * big
                anm1 = anm1 * big
                bnm1 = bnm1 * big
                anm2 = anm2 * big
                bnm2 = bnm2 * big
                anm3 = anm3 * big
                bnm3 = bnm3 * big
            }
        }
        n += 1i64
        bnm3 = bnm2
        bnm2 = bnm1
        bnm1 = bn
        anm3 = anm2
        anm2 = anm1
        anm1 = an
    }
    var er = 2.0f64 * ka(prec * fv)
    er += 2.0f64 * k_eps() * (f64(n) + 1.0f64) * ka(fv)
    er = er * (8.0f64 * (ka(ar) + ka(ai) + 1.0f64))
    ret (fv, er)
}

fn reflect(a: f64, b: f64, c: f64, x: f64) -> (f64, f64) {
    let d = c - a - b
    let intd = i64(kfl(d + 0.5f64))
    let d_integer = ka(d - f64(intd)) < k_loc()
    if d_integer {
        let ln_omx = klg(1.0f64 - x)
        let ad = ka(d)
        var d1 = 0.0f64
        var d2 = 0.0f64
        if d >= 0.0f64 {
            d1 = d
            d2 = 0.0f64
        } else {
            d1 = 0.0f64
            d2 = d
        }
        let (lad2v, lad2e, sad2) = gg.lngamma(a + d2)
        let (lbd2v, lbd2e, sbd2) = gg.lngamma(b + d2)
        let (lcv, lce, _sc) = gg.lngamma(c)
        var f1v = 0.0f64
        var f1e = 0.0f64
        if ad >= k_eps() {
            let (ladv, lade, sad) = gg.lngamma(ad)
            let (lad1v, lad1e, sad1) = gg.lngamma(a + d1)
            let (lbd1v, lbd1e, sbd1) = gg.lngamma(b + d1)
            if sad1 == 0i64 && sbd1 == 0i64 && sad == 0i64 {
                var sum1 = 1.0f64
                var term = 1.0f64
                let lnp1v = ladv + lcv + d2 * ln_omx - lad1v - lbd1v
                let lnp1e = lade + lce + lad1e + lbd1e + k_eps() * ka(lnp1v)
                var i = 1i64
                while f64(i) < ad {
                    let j = f64(i - 1i64)
                    term = term * ((a + d2 + j) * (b + d2 + j) / (1.0f64 + d2 + j) / f64(i) * (1.0f64 - x))
                    sum1 += term
                    i += 1i64
                }
                let (fv, fe, fs) = gg.emx(lnp1v, lnp1e, sum1, k_eps() * ka(sum1))
                if fs == 2i64 { ret (k_nan(), k_nan()) }
                f1v = fv
                f1e = fe
            }
        }
        var f2v = 0.0f64
        var f2e = 0.0f64
        if sad2 == 0i64 && sbd2 == 0i64 {
            var psi1 = -0.57721566490153286061f64
            let (p1pdv, p1pde) = gps.psi(1.0f64 + ad)
            let (pa1v, pa1e) = gps.psi(a + d1)
            let (pb1v, pb1e) = gps.psi(b + d1)
            var psi_val = psi1 + p1pdv - pa1v - pb1v - ln_omx
            var psi_err = p1pde + pa1e + pb1e + k_eps() * ka(psi_val)
            var fact = 1.0f64
            var sum2v = psi_val
            var sum2e = psi_err
            let lnp2v = lcv + d1 * ln_omx - lad2v - lbd2v
            let lnp2e = lce + lad2e + lbd2e + k_eps() * ka(lnp2v)
            var j = 1i64
            while j < 2000i64 {
                let jf = f64(j)
                let term1 = 1.0f64 / jf + 1.0f64 / (ad + jf)
                let term2 = 1.0f64 / (a + d1 + jf - 1.0f64) + 1.0f64 / (b + d1 + jf - 1.0f64)
                psi_val += term1 - term2
                psi_err += k_eps() * (ka(term1) + ka(term2))
                fact = fact * ((a + d1 + jf - 1.0f64) * (b + d1 + jf - 1.0f64) / ((ad + jf) * jf) * (1.0f64 - x))
                let delta = fact * psi_val
                sum2v += delta
                sum2e += ka(fact * psi_err) + k_eps() * ka(delta)
                if ka(delta) < k_eps() * ka(sum2v) { break }
                j += 1i64
            }
            if sum2v != 0.0f64 {
                let (fv2, fe2, fs2) = gg.emx(lnp2v, lnp2e, sum2v, sum2e)
                if fs2 == 2i64 { ret (0.0f64, 0.0f64) }
                f2v = fv2
                f2e = fe2
            }
        }
        var sgn2 = 1.0f64
        if kodd(intd) { sgn2 = -1.0f64 }
        let v = f1v + sgn2 * f2v
        var e = f1e + f2e
        e += 2.0f64 * k_eps() * (ka(f1v) + ka(f2v))
        e += 2.0f64 * k_eps() * ka(v)
        ret (v, e)
    }
    let (g1cav, g1cae, sg1ca, st1ca) = gg.lngamma_sgn(c - a)
    let (g1cbv, g1cbe, sg1cb, st1cb) = gg.lngamma_sgn(c - b)
    let (g2av, g2ae, sg2a, st2a) = gg.lngamma_sgn(a)
    let (g2bv, g2be, sg2b, st2b) = gg.lngamma_sgn(b)
    let ok1 = st1ca == 0i64 && st1cb == 0i64
    let ok2 = st2a == 0i64 && st2b == 0i64
    let (gcv, gce, sgc, _s1) = gg.lngamma_sgn(c)
    let (gdv, gde, sgd, _s2) = gg.lngamma_sgn(d)
    let (gmdv, gmde, sgmd, _s3) = gg.lngamma_sgn(0.0f64 - d)
    let sgn1 = sgc * sgd * sg1ca * sg1cb
    let sgn2b = sgc * sgmd * sg2a * sg2b
    var pre1v = 0.0f64
    var pre1e = 0.0f64
    var pre2v = 0.0f64
    var pre2e = 0.0f64
    if ok1 && ok2 {
        let lp1v = gcv + gdv - g1cav - g1cbv
        let lp2v = gcv + gmdv - g2av - g2bv + d * klg(1.0f64 - x)
        let lp1e = gce + gde + g1cae + g1cbe
        let lp2e = gce + gmde + g2ae + g2be
        if lp1v < k_lmax() && lp2v < k_lmax() {
            let (a1, a2, _t1) = gg.exp_err(lp1v, lp1e)
            let (b1, b2, _t2) = gg.exp_err(lp2v, lp2e)
            pre1v = a1 * sgn1
            pre1e = a2
            pre2v = b1 * sgn2b
            pre2e = b2
        } else {
            ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64)
        }
    } else {
        if ok1 {
            let lp1v = gcv + gdv - g1cav - g1cbv
            let lp1e = gce + gde + g1cae + g1cbe
            if lp1v < k_lmax() {
                let (a1, a2, _t1) = gg.exp_err(lp1v, lp1e)
                pre1v = a1 * sgn1
                pre1e = a2
            } else {
                ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64)
            }
        } else {
            if ok2 {
                let lp2v = gcv + gmdv - g2av - g2bv + d * klg(1.0f64 - x)
                let lp2e = gce + gmde + g2ae + g2be
                if lp2v < k_lmax() {
                    let (b1, b2, _t2) = gg.exp_err(lp2v, lp2e)
                    pre2v = b1 * sgn2b
                    pre2e = b2
                } else {
                    ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64)
                }
            } else {
                ret (0.0f64, 2.2250738585072014e-308f64)
            }
        }
    }
    let (fv1, fe1) = series(a, b, 1.0f64 - d, 1.0f64 - x)
    let (fv2, fe2) = series(c - a, c - b, 1.0f64 + d, 1.0f64 - x)
    let v = pre1v * fv1 + pre2v * fv2
    var e = ka(pre1v * fe1) + ka(pre2v * fe2)
    e += ka(pre1e * fv1) + ka(pre2e * fv2)
    e += 2.0f64 * k_eps() * (ka(pre1v * fv1) + ka(pre2v * fv2))
    e += 2.0f64 * k_eps() * ka(v)
    ret (v, e)
}

fn pow_omx(x: f64, p: f64) -> (f64, f64) {
    var ln_omx = 0.0f64
    if ka(x) < 7.4009597974140505e-04f64 {
        ln_omx = 0.0f64 - x * (1.0f64 + x * (1.0f64 / 2.0f64 + x * (1.0f64 / 3.0f64 + x / 4.0f64 + x * x / 5.0f64)))
    } else {
        ln_omx = klg(1.0f64 - x)
    }
    let ln_result = p * ln_omx
    let (v, e, _s) = gg.exp_err(ln_result, k_eps() * ka(ln_result))
    ret (v, e)
}

// gsl_sf_hyperg_2F1_e
fn hyperg_2f1(ar: *mem.Arena, a: f64, b: f64, c: f64, x: f64) -> (f64, f64) {
    let d = c - a - b
    let rinta = kfl(a + 0.5f64)
    let rintb = kfl(b + 0.5f64)
    let rintc = kfl(c + 0.5f64)
    let a_neg_integer = a < 0.0f64 && ka(a - rinta) < k_loc()
    let b_neg_integer = b < 0.0f64 && ka(b - rintb) < k_loc()
    let c_neg_integer = c < 0.0f64 && ka(c - rintc) < k_loc()
    if ka(x - 1.0f64) < k_loc() && (c - a - b) > 0.0f64 && c != 0.0f64 && !c_neg_integer {
        let (lcv, lce, lcs, s1) = gg.lngamma_sgn(c)
        let (labv, labe, s2) = gg.lngamma(c - a - b)
        let (lav, lae, las, s3) = gg.lngamma_sgn(c - a)
        let (lbv, lbe, lbs, s4) = gg.lngamma_sgn(c - b)
        if s1 != 0i64 || s2 != 0i64 || s3 != 0i64 || s4 != 0i64 { ret (k_nan(), k_nan()) }
        let (v, e, _s) = gg.exp_err(lcv + labv - lav - lbv, lce + labe + lae + lbe)
        ret (v * (lcs / (las * lbs)), e)
    }
    if x < -1.0f64 || 1.0f64 <= x { ret (k_nan(), k_nan()) }
    if c_neg_integer {
        if !(a_neg_integer && a > c + 0.1f64) && !(b_neg_integer && b > c + 0.1f64) { ret (k_nan(), k_nan()) }
    }
    if ka(c - b) < k_loc() || ka(c - a) < k_loc() {
        let (pv, pe) = pow_omx(x, d)
        ret (pv, pe)
    }
    if a >= 0.0f64 && b >= 0.0f64 && c >= 0.0f64 && x >= 0.0f64 && x < 0.995f64 {
        let (v1, e1) = series(a, b, c, x)
        ret (v1, e1)
    }
    if ka(a) < 10.0f64 && ka(b) < 10.0f64 {
        if a_neg_integer {
            let (v2, e2) = series(rinta, b, c, x)
            ret (v2, e2)
        }
        if b_neg_integer {
            let (v3, e3) = series(a, rintb, c, x)
            ret (v3, e3)
        }
        if x < -0.25f64 {
            let (v4, e4) = luke(a, b, c, x)
            ret (v4, e4)
        }
        if x < 0.5f64 {
            let (v5, e5) = series(a, b, c, x)
            ret (v5, e5)
        }
        if ka(c) > 10.0f64 {
            let (v6, e6) = series(a, b, c, x)
            ret (v6, e6)
        }
        let (v7, e7) = reflect(a, b, c, x)
        ret (v7, e7)
    }
    var ap = a
    var bp = b
    if ka(a) > ka(b) {
        bp = a
        ap = b
    }
    if x < 0.0f64 {
        let (v8, e8) = luke(a, b, c, x)
        ret (v8, e8)
    }
    var apm = ka(ap)
    if apm < 1.0f64 { apm = 1.0f64 }
    if apm * ka(bp) * ka(x) < 2.0f64 * ka(c) {
        let (v9, e9) = series(a, b, c, x)
        ret (v9, e9)
    }
    if ka(bp * bp * x * x) < 0.001f64 * ka(bp) && ka(ap) < 10.0f64 {
        let (fv, _fe) = gg.hyperg_1f1(ar, ap, c, bp * x)
        ret (fv, 0.001f64 * ka(fv))
    }
    ret (0.0f64, 0.0f64)
}

fn hyperg_2f1_conj(ar_: f64, ai: f64, c: f64, x: f64) -> (f64, f64) {
    let ax = ka(x)
    let rintc = kfl(c + 0.5f64)
    let c_neg_integer = c < 0.0f64 && ka(c - rintc) < k_loc()
    if ax >= 1.0f64 || c_neg_integer || c == 0.0f64 { ret (k_nan(), k_nan()) }
    if (ax < 0.25f64 && ka(ar_) < 20.0f64 && ka(ai) < 20.0f64) || (c > 0.0f64 && x > 0.0f64) {
        let (v1, e1) = conj_series(ar_, ai, c, x)
        ret (v1, e1)
    }
    if ka(ar_) < 10.0f64 && ka(ai) < 10.0f64 {
        if x < -0.25f64 {
            let (v2, e2) = conj_luke(ar_, ai, c, x)
            ret (v2, e2)
        }
        let (v3, e3) = conj_series(ar_, ai, c, x)
        ret (v3, e3)
    }
    if x < 0.0f64 {
        let (v4, e4) = conj_luke(ar_, ai, c, x)
        ret (v4, e4)
    }
    ret (0.0f64, 0.0f64)
}

fn hyperg_2f1_renorm(ar: *mem.Arena, a: f64, b: f64, c: f64, x: f64) -> (f64, f64) {
    let rinta = kfl(a + 0.5f64)
    let rintb = kfl(b + 0.5f64)
    let rintc = kfl(c + 0.5f64)
    let a_neg_integer = a < 0.0f64 && ka(a - rinta) < k_loc()
    let b_neg_integer = b < 0.0f64 && ka(b - rintb) < k_loc()
    let c_neg_integer = c < 0.0f64 && ka(c - rintc) < k_loc()
    if c_neg_integer {
        if (a_neg_integer && a > c + 0.1f64) || (b_neg_integer && b > c + 0.1f64) { ret (0.0f64, 0.0f64) }
        let (g1v, g1e, s1, t1) = gg.lngamma_sgn(a - c + 1.0f64)
        let (g2v, g2e, s2, t2) = gg.lngamma_sgn(b - c + 1.0f64)
        let (g3v, g3e, s3, t3) = gg.lngamma_sgn(a)
        let (g4v, g4e, s4, t4) = gg.lngamma_sgn(b)
        let (g5v, g5e, s5, t5) = gg.lngamma_sgn(0.0f64 - c + 2.0f64)
        if t1 + t2 + t3 + t4 + t5 != 0i64 { ret (k_nan(), k_nan()) }
        let (fv, fe) = hyperg_2f1(ar, a - c + 1.0f64, b - c + 1.0f64, 0.0f64 - c + 2.0f64, x)
        let lpv = g1v + g2v - g3v - g4v - g5v
        let lpe = g1e + g2e + g3e + g4e + g5e
        let sg = s1 * s2 * s3 * s4 * s5
        let (v, e, _s) = gg.emx(lpv, lpe, sg * fv, fe)
        ret (v, e)
    }
    let (lv, le, sgn, _st) = gg.lngamma_sgn(c)
    let (fv2, fe2) = hyperg_2f1(ar, a, b, c, x)
    let (v2, e2, _s2) = gg.emx(0.0f64 - lv, le, sgn * fv2, fe2)
    ret (v2, e2)
}

fn hyperg_2f1_conj_renorm(ar_: f64, ai: f64, c: f64, x: f64) -> (f64, f64) {
    let rintc = kfl(c + 0.5f64)
    let rinta = kfl(ar_ + 0.5f64)
    let a_neg_integer = ar_ < 0.0f64 && ka(ar_ - rinta) < k_loc() && ai == 0.0f64
    let c_neg_integer = c < 0.0f64 && ka(c - rintc) < k_loc()
    if c_neg_integer {
        if a_neg_integer && ar_ > c + 0.1f64 { ret (0.0f64, 0.0f64) }
        let (g1v, g1e) = gc.lngamma_complex_lnr(ar_ - c + 1.0f64, ai)
        let (g2v, g2e) = gc.lngamma_complex_lnr(ar_, ai)
        let (g3v, g3e, t3) = gg.lngamma(0.0f64 - c + 2.0f64)
        if t3 != 0i64 { ret (k_nan(), k_nan()) }
        let (fv, fe) = hyperg_2f1_conj(ar_ - c + 1.0f64, ai, 0.0f64 - c + 2.0f64, x)
        let lpv = 2.0f64 * (g1v - g2v) - g3v
        let lpe = 2.0f64 * (g1e + g2e) + g3e
        let (v, e, _s) = gg.emx(lpv, lpe, fv, fe)
        ret (v, e)
    }
    let (lv, le, sgn, _st) = gg.lngamma_sgn(c)
    let (fv2, fe2) = hyperg_2f1_conj(ar_, ai, c, x)
    let (v2, e2, _s2) = gg.emx(0.0f64 - lv, le, sgn * fv2, fe2)
    ret (v2, e2)
}
