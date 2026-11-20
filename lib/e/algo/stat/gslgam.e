// R gsl, ln |Gamma(x)| with its sign over the whole real line: gsl_sf_lngamma_sgn_e, including lngamma_sgn_sing for x within 0.02 of a negative integer (gslerr.e_lngamma_sgn
// stops at the pole of order one). Returns (value, error, sign); the caller screens the poles.

use e.math
use e.algo.stat.gslpsi as gps
use e.algo.stat.gslerr as ge
use e.algo.stat.gslcoulomb as gc

fn eps_() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }

// lngamma_sgn_sing(N, eps) for x = -N + eps, N >= 2
fn lng_sing(nn: i64, eps: f64) -> (f64, f64, f64) {
    var sg = 1.0f64
    if eps < 0.0f64 { sg = -1.0f64 }
    let cs1 = -1.6449340668482264365f64
    let cs2 = 0.8117424252833536436f64
    let cs3 = -0.1907518241220842137f64
    let cs4 = 0.0261478478176548005f64
    let cs5 = -0.0023460810354558236f64
    let e2 = eps * eps
    let sin_ser = 1.0f64 + e2 * (cs1 + e2 * (cs2 + e2 * (cs3 + e2 * (cs4 + e2 * cs5))))
    let aeps = fa(eps)
    let nf = f64(nn)
    let (c0v, c0e) = gps.lnfact(usize(nn))
    let (p0, _p0e) = gps.psi_int(usize(nn + 1i64))
    let (p1, _p1e) = gps.psi_1_int(usize(nn + 1i64))
    var p2 = 0.0f64
    var p3 = 0.0f64
    var p4 = 0.0f64
    var p5 = 0.0f64
    var p6 = 0.0f64
    if aeps > 0.00001f64 {
        let (q, _qe) = gps.psi_n(2usize, nf + 1.0f64)
        p2 = q
    }
    if aeps > 0.0002f64 {
        let (q, _qe) = gps.psi_n(3usize, nf + 1.0f64)
        p3 = q
    }
    if aeps > 0.001f64 {
        let (q, _qe) = gps.psi_n(4usize, nf + 1.0f64)
        p4 = q
    }
    if aeps > 0.005f64 {
        let (q, _qe) = gps.psi_n(5usize, nf + 1.0f64)
        p5 = q
    }
    if aeps > 0.01f64 {
        let (q, _qe) = gps.psi_n(6usize, nf + 1.0f64)
        p6 = q
    }
    let lng_ser = c0v - eps * (p0 - eps * (p1 / 2.0f64 - eps * (p2 / 6.0f64 - eps * (p3 / 24.0f64 - eps * (p4 / 120.0f64 - eps * (p5 / 720.0f64 - eps * (p6 / 5040.0f64)))))))
    let g = 0.0f64 - lng_ser - math.log[f64](sin_ser)
    let v = g - math.log[f64](fa(eps))
    var sg2 = 1.0f64
    if nn % 2i64 != 0i64 { sg2 = -1.0f64 }
    ret (v, c0e + 2.0f64 * eps_() * (fa(g) + fa(v)), sg2 * sg)
}

fn lngamma_sgn(x: f64) -> (f64, f64, f64) {
    if x < 0.5f64 && fa(x) >= 0.02f64 && fa(x - 1.0f64) >= 0.01f64 && fa(x - 2.0f64) >= 0.01f64 {
        let s = math.sin[f64](3.141592653589793238462643383279f64 * x)
        if fa(s) < 3.141592653589793238462643383279f64 * 0.015f64 && s != 0.0f64 {
            let nn = 0i64 - i64(x - 0.5f64)
            if nn != 1i64 {
                let (v, e, sgn) = lng_sing(nn, x + f64(nn))
                ret (v, e, sgn)
            }
        }
    }
    let (v2, e2, s2) = ge.e_lngamma_sgn(x)
    ret (v2, e2, s2)
}
