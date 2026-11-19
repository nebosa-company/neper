// R gsl: the sine, cosine and hyperbolic integrals Si, Ci, Shi, Chi, the inverse tangent integral and the integral expint_3 with gsl's error estimates, ports of specfunc/sinint.c,
// shint.c, atanint.c and expint3.c over the generated Chebyshev tables. Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.algo.stat.gslcheb as ch
use e.algo.stat.gslspecial as sp
use e.algo.stat.gslerr as ge

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn sqrt_eps() -> f64 { ret 1.4901161193847656e-08f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn mpi() -> f64 { ret 3.141592653589793238462643383279f64 }

// fg_asymp: (f, f error, g, g error)
fn fg_asymp(x: f64) -> (f64, f64, f64, f64) {
    let xbig = 1.0f64 / sqrt_eps()
    let xmaxf = 1.0f64 / 2.2250738585072014e-308f64
    let xmaxg = 1.0f64 / 1.4916681462400413e-154f64
    let xbnd = 7.07106781187f64
    let x2 = x * x
    if x <= xbnd {
        let t = (1.0f64 / x2 - 0.04125f64) / 0.02125f64
        let (c1v, c1e) = ch.cvv_sinint_f1(t)
        let (c2v, c2e) = ch.cvv_sinint_g1(t)
        let fv = (1.0f64 + c1v) / x
        let gv = (1.0f64 + c2v) / x2
        ret (fv, c1e / x + 2.0f64 * c_eps() * fa(fv), gv, c2e / x2 + 2.0f64 * c_eps() * fa(gv))
    }
    if x <= xbig {
        let t = 100.0f64 / x2 - 1.0f64
        let (c1v, c1e) = ch.cvv_sinint_f2(t)
        let (c2v, c2e) = ch.cvv_sinint_g2(t)
        let fv = (1.0f64 + c1v) / x
        let gv = (1.0f64 + c2v) / x2
        ret (fv, c1e / x + 2.0f64 * c_eps() * fa(fv), gv, c2e / x2 + 2.0f64 * c_eps() * fa(gv))
    }
    var fv = 0.0f64
    var gv = 0.0f64
    if x < xmaxf { fv = 1.0f64 / x }
    if x < xmaxg { gv = 1.0f64 / x2 }
    ret (fv, 2.0f64 * c_eps() * fa(fv), gv, 2.0f64 * c_eps() * fa(gv))
}

fn si(x: f64) -> (f64, f64) {
    let ax = fa(x)
    if ax < sqrt_eps() { ret (x, 0.0f64) }
    if ax <= 4.0f64 {
        let (cv, ce) = ch.cvv_sinint_si((x * x - 8.0f64) * 0.125f64)
        let v = x * (0.75f64 + cv)
        ret (v, ax * ce + 2.0f64 * c_eps() * fa(v))
    }
    let (fv, fe, gv, ge_) = fg_asymp(ax)
    var v = 0.5f64 * mpi() - fv * math.cos[f64](ax) - gv * math.sin[f64](ax)
    let e = fe + ge_ + 2.0f64 * c_eps() * fa(v)
    if x < 0.0f64 { v = 0.0f64 - v }
    ret (v, e)
}

fn ci(x: f64) -> (f64, f64) {
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    if x <= 4.0f64 {
        let lx = math.log[f64](x)
        let (cv, ce) = ch.cvv_sinint_ci((x * x - 8.0f64) * 0.125f64)
        let v = lx - 0.5f64 + cv
        ret (v, 2.0f64 * c_eps() * (fa(lx) + 0.5f64) + ce + 2.0f64 * c_eps() * fa(v))
    }
    let (sv, se) = ge.e_sin(x)
    let (cv, ce) = ge.e_cos(x)
    let (fv, fe, gv, ge_) = fg_asymp(x)
    let v = fv * sv - gv * cv
    var e = fa(fe * sv)
    e += fa(ge_ * cv)
    e += fa(fv * se)
    e += fa(gv * ce)
    e += 2.0f64 * c_eps() * fa(v)
    ret (v, e)
}

fn shi(x: f64) -> (f64, f64) {
    let ax = fa(x)
    if ax < sqrt_eps() { ret (x, 0.0f64) }
    if ax <= 0.375f64 {
        let (cv, ce) = ch.cvv_shint_shi(128.0f64 * x * x / 9.0f64 - 1.0f64)
        let v = x * (1.0f64 + cv)
        ret (v, x * ce + 2.0f64 * c_eps() * fa(v))
    }
    let (eiv, eie) = sp.expint_ei(x)
    let (e1v, e1e) = sp.expint_e1(x, false)
    let v = 0.5f64 * (eiv + e1v)
    ret (v, 0.5f64 * (eie + e1e) + 2.0f64 * c_eps() * fa(v))
}

fn chi(x: f64) -> (f64, f64) {
    let (eiv, eie) = sp.expint_ei(x)
    let (e1v, e1e) = sp.expint_e1(x, false)
    let v = 0.5f64 * (eiv - e1v)
    ret (v, 0.5f64 * (eie + e1e) + 2.0f64 * c_eps() * fa(v))
}

fn atanint(x: f64) -> (f64, f64) {
    let ax = fa(x)
    var sgn = 1.0f64
    if x < 0.0f64 { sgn = -1.0f64 }
    if ax == 0.0f64 { ret (0.0f64, 0.0f64) }
    if ax < 0.5f64 * sqrt_eps() { ret (x, 0.0f64) }
    if ax <= 1.0f64 {
        let (cv, ce) = ch.cvv_atanint_atanint(2.0f64 * (x * x - 0.5f64))
        let v = x * cv
        ret (v, x * ce + c_eps() * fa(v))
    }
    if ax < 1.0f64 / sqrt_eps() {
        let (cv, ce) = ch.cvv_atanint_atanint(2.0f64 * (1.0f64 / (x * x) - 0.5f64))
        let v = sgn * (0.5f64 * mpi() * math.log[f64](ax) + cv / ax)
        ret (v, ce / ax + fa(v * c_eps()) + c_eps() * fa(v))
    }
    let v = sgn * (0.5f64 * mpi() * math.log[f64](ax) + 1.0f64 / ax)
    ret (v, 2.0f64 * fa(v * c_eps()))
}

fn expint_3(x: f64) -> (f64, f64) {
    let vinf = 0.892979511569249211f64
    if x < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x < 1.6f64 * 6.0554544523933429e-06f64 { ret (x, 0.0f64) }
    if x <= 2.0f64 {
        let (cv, ce) = ch.cvv_expint3_expint3(x * x * x / 4.0f64 - 1.0f64)
        ret (x * cv, x * ce)
    }
    if x < math.pow[f64](36.04365338911715f64, 1.0f64 / 3.0f64) {
        let t = 16.0f64 / (x * x * x) - 1.0f64
        let s = math.exp[f64](0.0f64 - x * x * x) / (3.0f64 * x * x)
        let (cv, ce) = ch.cvv_expint3_expint3a(t)
        ret (vinf - cv * s, vinf * c_eps() + s * ce)
    }
    ret (vinf, vinf * c_eps())
}
