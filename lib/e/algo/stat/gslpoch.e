// R gsl, lnpoch, lnpoch_sgn, poch and pochrel with gsl_sf_result.err: a port of specfunc/poch.c over the error-carrying helpers (gamma, gammainv, ln gamma, psi, expm1, log_1plusx).
// Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.mem
use e.os
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslairy as gy
use e.algo.stat.gslerr as ge
use e.algo.stat.gslerr2 as g2
use e.algo.stat.gslpsi as gp

fn p_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn pa(x: f64) -> f64 { ret math.abs[f64](x) }

fn grab(a: *mem.Arena, n: usize) -> []f64 {
    let (p, g) = mem.alloc[f64](a, n)
    if g != ok { os.exit(4) }
    ret p
}

fn bern(k: usize) -> f64 {
    if k == 1usize { ret 0.0833333333333333333333333333333333f64 }
    if k == 2usize { ret -0.00138888888888888888888888888888f64 }
    if k == 3usize { ret 0.0000330687830687830687830687830687830f64 }
    if k == 4usize { ret -0.000000826719576719576719576719576719576f64 }
    if k == 5usize { ret 0.0000000208767569878680989792100903212014f64 }
    if k == 6usize { ret -5.28419013868749318484768220217955e-10f64 }
    if k == 7usize { ret 1.33825365306846788328269809751291e-11f64 }
    if k == 8usize { ret -3.38968029632258286683019539124944e-13f64 }
    if k == 9usize { ret 8.58606205627784456413590545042562e-15f64 }
    if k == 10usize { ret -2.17486869855806187304151642386591e-16f64 }
    if k == 11usize { ret 5.50900282836022951520265260890225e-18f64 }
    if k == 12usize { ret -1.39544646858125233407076862640635e-19f64 }
    if k == 13usize { ret 3.53470703962946747169322997780379e-21f64 }
    if k == 14usize { ret -8.95351742703754685040261131811274e-23f64 }
    if k == 15usize { ret 2.26795245233768306031095073886816e-24f64 }
    if k == 16usize { ret -5.74472439520264523834847971943400e-25f64 }
    if k == 17usize { ret 1.45517247561486490186626486727132e-27f64 }
    if k == 18usize { ret -3.68599494066531017818178247990866e-29f64 }
    if k == 19usize { ret 9.33673425709504467203255515278562e-31f64 }
    if k == 20usize { ret -2.36502241570062993455963519636983e-32f64 }
    ret 0.0f64
}

fn e_expm1(x: f64) -> (f64, f64) {
    if x < -7.0839641853226408e+02f64 { ret (-1.0f64, p_eps()) }
    if x < -0.002f64 {
        let v = math.exp[f64](x) - 1.0f64
        ret (v, 2.0f64 * p_eps() * pa(v))
    }
    if x < 0.002f64 {
        let v = x * (1.0f64 + 0.5f64 * x * (1.0f64 + x / 3.0f64 * (1.0f64 + 0.25f64 * x * (1.0f64 + 0.2f64 * x))))
        ret (v, 2.0f64 * p_eps() * pa(v))
    }
    let v = math.exp[f64](x) - 1.0f64
    ret (v, 2.0f64 * p_eps() * pa(v))
}

// gsl_sf_gammainv_e
fn e_gammainv(x: f64) -> (f64, f64) {
    if x <= 0.0f64 && x == math.floor[f64](x) { ret (0.0f64, 0.0f64) }
    if x < 0.5f64 {
        let (lv, le, sg) = ge.e_lngamma_sgn(x)
        let (v, e) = gy.exp_mult_err(0.0f64 - lv, le, sg, 0.0f64)
        ret (v, e)
    }
    let (gv, ge2) = g2.gamma_xgthalf(x)
    let v2 = 1.0f64 / gv
    ret (v2, pa(ge2 / gv) * pa(v2) + 2.0f64 * p_eps() * pa(v2))
}

// ((a)_x - 1) / x for small x
fn pochrel_smallx(a: *mem.Arena, ap: f64, x: f64) -> (f64, f64) {
    if x == 0.0f64 {
        let (v, e) = gp.psi(ap)
        ret (v, e)
    }
    let sqtbig = 1.0f64 / (2.0f64 * 1.4142135623730950488f64 * 1.7320508075688772935f64 * 1.4916681462400413e-154f64)
    let alneps = -36.04365338911715f64 - 0.693147180559945309417232121458f64
    var bp = ap
    if ap < -0.5f64 { bp = 1.0f64 - ap - x }
    var incr = 0i64
    if bp < 10.0f64 { incr = i64(11.0f64 - bp) }
    let b = bp + f64(incr)
    let vr = b + 0.5f64 * (x - 1.0f64)
    let alnvar = math.log[f64](vr)
    let q = x * alnvar
    var poly1 = 0.0f64
    if vr < sqtbig {
        let nterms = i64(-0.5f64 * alneps / alnvar + 1.0f64)
        let var2 = (1.0f64 / vr) / vr
        let rho = 0.5f64 * (x + 1.0f64)
        var term = var2
        let gbern = grab(a, 26usize)
        gbern[1usize] = 1.0f64
        gbern[2usize] = 0.0f64 - rho / 12.0f64
        poly1 = gbern[2usize] * term
        if nterms > 20i64 { ret (0.0f64, 0.0f64) }
        var k = 2i64
        while k <= nterms {
            var gbk = 0.0f64
            var j = 1i64
            while j <= k {
                gbk += bern(usize(k - j + 1i64)) * gbern[usize(j)]
                j += 1i64
            }
            gbern[usize(k + 1i64)] = 0.0f64 - rho * gbk / f64(k)
            term = term * (f64(2i64 * k - 2i64) - x) * (f64(2i64 * k - 1i64) - x) * var2
            poly1 += gbern[usize(k + 1i64)] * term
            k += 1i64
        }
    }
    let (dxv, _dxe) = e_expm1(q)
    let dexprl = dxv / q
    poly1 = poly1 * (x - 1.0f64)
    var dpoch1 = dexprl * (alnvar + q * poly1) + poly1
    var i = incr - 1i64
    while i >= 0i64 {
        let binv = 1.0f64 / (bp + f64(i))
        dpoch1 = (dpoch1 - binv) / (1.0f64 + x * binv)
        i -= 1i64
    }
    if bp == ap {
        ret (dpoch1, 2.0f64 * p_eps() * (pa(f64(incr)) + 1.0f64) * pa(dpoch1))
    }
    let sinpxx = math.sin[f64](3.141592653589793238462643383279f64 * x) / x
    let sinpx2 = math.sin[f64](0.5f64 * 3.141592653589793238462643383279f64 * x)
    let t1 = sinpxx / math.tan[f64](3.141592653589793238462643383279f64 * b)
    let t2 = 2.0f64 * sinpx2 * (sinpx2 / x)
    let trig = t1 - t2
    let v = dpoch1 * (1.0f64 + x * trig) + trig
    var er = (pa(dpoch1 * x) + 1.0f64) * p_eps() * (pa(t1) + pa(t2))
    er += 2.0f64 * p_eps() * (pa(f64(incr)) + 1.0f64) * pa(v)
    ret (v, er)
}

// assumes a > 0 and a + x > 0
fn lnpoch_pos(ar: *mem.Arena, a: f64, x: f64) -> (f64, f64) {
    let absx = pa(x)
    var big = a
    if big < 2.0f64 { big = 2.0f64 }
    if absx > 0.1f64 * a || absx * math.log[f64](big) > 0.1f64 {
        if a < 171.0f64 && a + x < 171.0f64 {
            let (g1, g1e) = e_gammainv(a)
            let (g2v, g2e) = e_gammainv(a + x)
            let v = 0.0f64 - math.log[f64](g2v / g1)
            ret (v, g1e / pa(g1) + g2e / pa(g2v) + 2.0f64 * p_eps() * pa(v))
        }
        let (l1, l1e) = gc.lngamma_e(a)
        let (l2, l2e) = gc.lngamma_e(a + x)
        let v2 = l2 - l1
        ret (v2, l2e + l1e + 2.0f64 * p_eps() * pa(v2))
    }
    if absx < 0.1f64 * a && a > 15.0f64 {
        let ep = x / a
        let den = 1.0f64 + ep
        let d3 = den * den * den
        let d5 = d3 * den * den
        let d7 = d5 * den * den
        let c1 = 0.0f64 - ep / den
        let c3 = 0.0f64 - ep * (3.0f64 + ep * (3.0f64 + ep)) / d3
        let c5 = 0.0f64 - ep * (5.0f64 + ep * (10.0f64 + ep * (10.0f64 + ep * (5.0f64 + ep)))) / d5
        let c7 = 0.0f64 - ep * (7.0f64 + ep * (21.0f64 + ep * (35.0f64 + ep * (35.0f64 + ep * (21.0f64 + ep * (7.0f64 + ep)))))) / d7
        let (p8, _p8e) = ge.e_pow_int(1.0f64 + ep, 8i64)
        let c8 = 1.0f64 / p8 - 1.0f64
        let c9 = 1.0f64 / (p8 * (1.0f64 + ep)) - 1.0f64
        let a4 = a * a * a * a
        let a6 = a4 * a * a
        let ser1 = c1 + c3 / (30.0f64 * a * a) + c5 / (105.0f64 * a4) + c7 / (140.0f64 * a6)
        let ser2 = c8 / (99.0f64 * a6 * a * a) - 691.0f64 / 360360.0f64 * c9 / (a6 * a4)
        let ser = (ser1 + ser2) / (12.0f64 * a)
        let term1 = x * math.log[f64](a / 2.718281828459045235360287471353f64)
        let (lnv, lne) = g2.e_log_1plusx(ep)
        let term2 = (x + a - 0.5f64) * lnv
        let v = term1 + term2 + ser
        var er = p_eps() * pa(term1)
        er += pa((x + a - 0.5f64) * lne)
        er += pa(lnv) * p_eps() * (pa(x) + pa(a) + 0.5f64)
        er += 2.0f64 * p_eps() * pa(v)
        ret (v, er)
    }
    let (pv, pe) = pochrel_smallx(ar, a, x)
    let ep2 = x * pv
    let (lv, _le) = g2.e_log_1plusx(ep2)
    var er2 = 2.0f64 * pa(x * pe / (1.0f64 + ep2))
    er2 += 2.0f64 * p_eps() * pa(lv)
    ret (lv, er2)
}

fn lnpoch(ar: *mem.Arena, a: f64, x: f64) -> (f64, f64) {
    if a <= 0.0f64 || a + x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    let (v, e) = lnpoch_pos(ar, a, x)
    ret (v, e)
}

// (value, error, sign); minus infinity (a pole of Gamma(a + x) with a finite Gamma(a)) as in gsl
fn lnpoch_sgn(ar: *mem.Arena, a: f64, x: f64) -> (f64, f64, f64) {
    if x == 0.0f64 { ret (0.0f64, 0.0f64, 1.0f64) }
    if a > 0.0f64 && a + x > 0.0f64 {
        let (v, e) = lnpoch_pos(ar, a, x)
        ret (v, e, 1.0f64)
    }
    if a <= 0.0f64 && a == math.floor[f64](a) {
        if a + x < 0.0f64 && x == math.floor[f64](x) {
            let (pv, pe) = lnpoch_pos(ar, 0.0f64 - a, 0.0f64 - x)
            let f = math.log[f64](a / (a + x))
            var s = -1.0f64
            if math.floor[f64](x / 2.0f64) * 2.0f64 == x { s = 1.0f64 }
            ret (f - pv, pe + 2.0f64 * p_eps() * f, s)
        }
        if a + x == 0.0f64 {
            let (lv, le, sg) = ge.e_lngamma_sgn(0.0f64 - a + 1.0f64)
            var s2 = -1.0f64
            if math.floor[f64](a / 2.0f64) * 2.0f64 == a { s2 = 1.0f64 }
            ret (lv, le, sg * s2)
        }
        ret (-1.0f64 / 0.0f64, 0.0f64, 1.0f64)
    }
    if a < 0.0f64 && a + x < 0.0f64 {
        let sin1 = math.sin[f64](3.141592653589793238462643383279f64 * (1.0f64 - a))
        let sin2 = math.sin[f64](3.141592653589793238462643383279f64 * (1.0f64 - a - x))
        if sin1 == 0.0f64 || sin2 == 0.0f64 { ret (0.0f64, 0.0f64, 0.0f64) }
        let (pv, pe) = lnpoch_pos(ar, 1.0f64 - a, 0.0f64 - x)
        let lnterm = math.log[f64](pa(sin1 / sin2))
        let v = lnterm - pv
        var er = pe
        er += 2.0f64 * p_eps() * (pa(1.0f64 - a) + pa(1.0f64 - a - x)) * pa(lnterm)
        er += 2.0f64 * p_eps() * pa(v)
        var sg = 1.0f64
        if sin1 * sin2 < 0.0f64 { sg = -1.0f64 }
        ret (v, er, sg)
    }
    let (l1, l1e, s1) = ge.e_lngamma_sgn(a + x)
    let (l2, l2e, s2b) = ge.e_lngamma_sgn(a)
    let v3 = l1 - l2
    ret (v3, l1e + l2e + 2.0f64 * p_eps() * pa(v3), s1 * s2b)
}

fn poch(ar: *mem.Arena, a: f64, x: f64) -> (f64, f64) {
    if x == 0.0f64 { ret (1.0f64, 0.0f64) }
    let (lv, le, sg) = lnpoch_sgn(ar, a, x)
    if lv == -1.0f64 / 0.0f64 { ret (0.0f64, 0.0f64) }
    let (ev, ee, _s) = gc.exp_err(lv, le)
    let v = ev * sg
    ret (v, ee + 2.0f64 * p_eps() * pa(v))
}

fn pochrel(ar: *mem.Arena, a: f64, x: f64) -> (f64, f64) {
    let absx = pa(x)
    let absa = pa(a)
    var big = absa
    if big < 2.0f64 { big = 2.0f64 }
    if absx > 0.1f64 * absa || absx * math.log[f64](big) > 0.1f64 {
        let (lv, le, sg) = lnpoch_sgn(ar, a, x)
        if lv > 7.0978271289338397e+02f64 { ret (0.0f64, 0.0f64) }
        let el = math.exp[f64](lv)
        let v = (sg * el - 1.0f64) / x
        var er = pa(v) * (le + 2.0f64 * p_eps())
        er += 2.0f64 * p_eps() * (pa(sg * el) + 1.0f64) / pa(x)
        ret (v, er)
    }
    let (v2, e2) = pochrel_smallx(ar, a, x)
    ret (v2, e2)
}
