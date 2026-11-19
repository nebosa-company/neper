// R gsl, second batch: the Jacobian elliptic functions of a complex argument (sn_cn_dn and the twelve gsl_xx ratios), the scaled Airy functions and their derivatives,
// hypergeometric helpers and small special functions with a gsl name of their own.

use e.math
use e.math.special as sp
use e.mem
use e.algo.stat.gslfns as gs
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslmore as gm

// Re sn, Im sn, Re cn, Im cn, Re dn, Im dn into o (6 entries); r needs 3 entries, em and en 32 each
fn jacobi_c(zr: f64, zi: f64, m: f64, o: []f64, r: []f64, em: []f64, en: []f64) {
    gs.elljac(zr, m, r, em, en)
    let s = r[0usize]
    let c = r[1usize]
    let d = r[2usize]
    if zi == 0.0f64 {
        o[0usize] = s
        o[1usize] = 0.0f64
        o[2usize] = c
        o[3usize] = 0.0f64
        o[4usize] = d
        o[5usize] = 0.0f64
        ret
    }
    gs.elljac(zi, 1.0f64 - m, r, em, en)
    let s1 = r[0usize]
    let c1 = r[1usize]
    let d1 = r[2usize]
    let den = c1 * c1 + m * s * s * s1 * s1
    o[0usize] = s * d1 / den
    o[1usize] = c * d * s1 * c1 / den
    o[2usize] = c * c1 / den
    o[3usize] = 0.0f64 - s * d * s1 * d1 / den
    o[4usize] = d * c1 * d1 / den
    o[5usize] = 0.0f64 - m * s * c * s1 / den
}

// the twelve functions in R's order 0 cd, 1 cn, 2 cs, 3 dc, 4 dn, 5 ds, 6 nc, 7 nd, 8 ns, 9 sc, 10 sd, 11 sn: (Re, Im) of the part asked for
fn jacobi_ratio(code: usize, part: usize, zr: f64, zi: f64, m: f64, o: []f64, r: []f64, em: []f64, en: []f64) -> f64 {
    jacobi_c(zr, zi, m, o, r, em, en)
    var ni_i = 99usize
    var di_i = 99usize
    if code == 0usize {
        ni_i = 1usize
        di_i = 2usize
    }
    if code == 1usize { ni_i = 1usize }
    if code == 2usize {
        ni_i = 1usize
        di_i = 0usize
    }
    if code == 3usize {
        ni_i = 2usize
        di_i = 1usize
    }
    if code == 4usize { ni_i = 2usize }
    if code == 5usize {
        ni_i = 2usize
        di_i = 0usize
    }
    if code == 6usize { di_i = 1usize }
    if code == 7usize { di_i = 2usize }
    if code == 8usize { di_i = 0usize }
    if code == 9usize {
        ni_i = 0usize
        di_i = 1usize
    }
    if code == 10usize {
        ni_i = 0usize
        di_i = 2usize
    }
    if code == 11usize { ni_i = 0usize }
    var nr = 1.0f64
    var ni = 0.0f64
    var dr = 1.0f64
    var di = 0.0f64
    if ni_i != 99usize {
        nr = o[2usize * ni_i]
        ni = o[2usize * ni_i + 1usize]
    }
    if di_i != 99usize {
        dr = o[2usize * di_i]
        di = o[2usize * di_i + 1usize]
    }
    let q = dr * dr + di * di
    if part == 0usize { ret (nr * dr + ni * di) / q }
    ret (ni * dr - nr * di) / q
}

// exp(-|2/3 x^(3/2)|) scaled Airy functions: kind 0 Ai, 1 Bi, 2 Ai', 3 Bi'; for x <= 0 the functions themselves (the scale is 1 there)
fn airy_scaled_kind(kind: usize, x: f64) -> f64 {
    if x <= 0.0f64 { ret gs.airy_kind(kind, x) }
    let z = 2.0f64 / 3.0f64 * x * math.sqrt[f64](x)
    let s3 = 1.7320508075688772935274463415f64
    if kind == 0usize { ret gc.airy_scaled(x, false) }
    if kind == 1usize { ret gc.airy_scaled(x, true) }
    if kind == 2usize { ret 0.0f64 - x / (gm.mpi() * s3) * gm.kn_sc(2.0f64 / 3.0f64, z) }
    ret x / s3 * (gm.in_sc(2.0f64 / 3.0f64, z) + gm.in_sc(0.0f64 - 2.0f64 / 3.0f64, z))
}

// gsl_sf_choose(n, m) exactly as the product of ratios in gsl (m <= n), and the gamma function with its sign
fn choose_(n: usize, m0: usize) -> f64 {
    var m = m0
    if m > n { ret 0.0f64 }
    if m * 2usize > n { m = n - m }
    var r = 1.0f64
    var k = 1usize
    while k <= m {
        r = r * f64(n - m + k) / f64(k)
        k += 1usize
    }
    ret r
}

fn gamma_fn(x: f64) -> f64 { ret gm.gamma_sign(x) * math.exp[f64](gm.lngamma_abs(x)) }

fn lnpoch_sgn_val(a: f64, x: f64) -> f64 { ret gm.lngamma_abs(a + x) - gm.lngamma_abs(a) }

fn lnpoch_sgn_sign(a: f64, x: f64) -> f64 { ret gm.gamma_sign(a + x) * gm.gamma_sign(a) }
