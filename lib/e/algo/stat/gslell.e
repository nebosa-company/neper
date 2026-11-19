// R gsl: the Carlson elliptic integrals RC, RD, RF, RJ and the Legendre forms F, E, P, D, Kcomp, Ecomp with gsl's error estimates, a port of specfunc/ellint.c.
// `mode` is gsl's precision mode (0 double, 1 single, 2 approximate): it sets the stopping tolerance of the duplication loop (0.001 for double, 0.03 otherwise) and the
// precision recorded in the error (2.22e-16, 1.19e-7, 4.88e-4). Every function returns (value, error); a domain error returns (0, 0).

use e.math

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn dbl_min() -> f64 { ret 2.2250738585072014e-308f64 }
fn dbl_max() -> f64 { ret 1.7976931348623157e308f64 }
fn fmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}
fn fmin(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}
fn max3(x: f64, y: f64, z: f64) -> f64 { ret fmax(fmax(x, y), z) }
fn max4(x: f64, y: f64, z: f64, w: f64) -> f64 { ret fmax(fmax(fmax(x, y), z), w) }

fn errtol_of(mode: usize) -> f64 {
    if mode % 8usize == 0usize { ret 0.001f64 }
    ret 0.03f64
}

fn prec_of(mode: usize) -> f64 {
    let g = mode % 8usize
    if g == 0usize { ret c_eps() }
    if g == 1usize { ret 1.1920928955078125e-07f64 }
    ret 4.8828125e-04f64
}

fn rc(x: f64, y: f64, mode: usize) -> (f64, f64) {
    let lolim = 5.0f64 * dbl_min()
    let uplim = 0.2f64 * dbl_max()
    let errtol = errtol_of(mode)
    if x < 0.0f64 || y < 0.0f64 || x + y < lolim { ret (0.0f64, 0.0f64) }
    if !(fmax(x, y) < uplim) { ret (0.0f64, 0.0f64) }
    let c1 = 1.0f64 / 7.0f64
    let c2 = 9.0f64 / 22.0f64
    var xn = x
    var yn = y
    var mu = 0.0f64
    var sn = 0.0f64
    var n = 0i64
    while true {
        mu = (xn + yn + yn) / 3.0f64
        sn = (yn + mu) / mu - 2.0f64
        if fa(sn) < errtol { break }
        let lamda = 2.0f64 * math.sqrt[f64](xn) * math.sqrt[f64](yn) + yn
        xn = (xn + lamda) * 0.25f64
        yn = (yn + lamda) * 0.25f64
        n += 1i64
        if n == 10000i64 { ret (0.0f64, 0.0f64) }
    }
    let s = sn * sn * (0.3f64 + sn * (c1 + sn * (0.375f64 + sn * c2)))
    let v = (1.0f64 + s) / math.sqrt[f64](mu)
    ret (v, prec_of(mode) * fa(v))
}

fn rd(x: f64, y: f64, z: f64, mode: usize) -> (f64, f64) {
    let errtol = errtol_of(mode)
    let lolim = 2.0f64 / math.pow[f64](dbl_max(), 2.0f64 / 3.0f64)
    let uplim = math.pow[f64](0.1f64 * errtol / dbl_min(), 2.0f64 / 3.0f64)
    if fmin(x, y) < 0.0f64 || fmin(x + y, z) < lolim { ret (0.0f64, 0.0f64) }
    if !(max3(x, y, z) < uplim) { ret (0.0f64, 0.0f64) }
    let c1 = 3.0f64 / 14.0f64
    let c2 = 1.0f64 / 6.0f64
    let c3 = 9.0f64 / 22.0f64
    let c4 = 3.0f64 / 26.0f64
    var xn = x
    var yn = y
    var zn = z
    var sigma = 0.0f64
    var power4 = 1.0f64
    var mu = 0.0f64
    var xndev = 0.0f64
    var yndev = 0.0f64
    var zndev = 0.0f64
    var n = 0i64
    while true {
        mu = (xn + yn + 3.0f64 * zn) * 0.2f64
        xndev = (mu - xn) / mu
        yndev = (mu - yn) / mu
        zndev = (mu - zn) / mu
        let epslon = max3(fa(xndev), fa(yndev), fa(zndev))
        if epslon < errtol { break }
        let xnroot = math.sqrt[f64](xn)
        let ynroot = math.sqrt[f64](yn)
        let znroot = math.sqrt[f64](zn)
        let lamda = xnroot * (ynroot + znroot) + ynroot * znroot
        sigma += power4 / (znroot * (zn + lamda))
        power4 *= 0.25f64
        xn = (xn + lamda) * 0.25f64
        yn = (yn + lamda) * 0.25f64
        zn = (zn + lamda) * 0.25f64
        n += 1i64
        if n == 10000i64 { ret (0.0f64, 0.0f64) }
    }
    let ea = xndev * yndev
    let eb = zndev * zndev
    let ec = ea - eb
    let ed = ea - 6.0f64 * eb
    let ef = ed + ec + ec
    let s1 = ed * (0.0f64 - c1 + 0.25f64 * c3 * ed - 1.5f64 * c4 * zndev * ef)
    let s2 = zndev * (c2 * ef + zndev * (0.0f64 - c3 * ec + zndev * c4 * ea))
    let v = 3.0f64 * sigma + power4 * (1.0f64 + s1 + s2) / (mu * math.sqrt[f64](mu))
    ret (v, prec_of(mode) * fa(v))
}

fn rf(x: f64, y: f64, z: f64, mode: usize) -> (f64, f64) {
    let lolim = 5.0f64 * dbl_min()
    let uplim = 0.2f64 * dbl_max()
    let errtol = errtol_of(mode)
    if x < 0.0f64 || y < 0.0f64 || z < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x + y < lolim || x + z < lolim || y + z < lolim { ret (0.0f64, 0.0f64) }
    if !(max3(x, y, z) < uplim) { ret (0.0f64, 0.0f64) }
    let c1 = 1.0f64 / 24.0f64
    let c2 = 3.0f64 / 44.0f64
    let c3 = 1.0f64 / 14.0f64
    var xn = x
    var yn = y
    var zn = z
    var mu = 0.0f64
    var xndev = 0.0f64
    var yndev = 0.0f64
    var zndev = 0.0f64
    var n = 0i64
    while true {
        mu = (xn + yn + zn) / 3.0f64
        xndev = 2.0f64 - (mu + xn) / mu
        yndev = 2.0f64 - (mu + yn) / mu
        zndev = 2.0f64 - (mu + zn) / mu
        let epslon = max3(fa(xndev), fa(yndev), fa(zndev))
        if epslon < errtol { break }
        let xnroot = math.sqrt[f64](xn)
        let ynroot = math.sqrt[f64](yn)
        let znroot = math.sqrt[f64](zn)
        let lamda = xnroot * (ynroot + znroot) + ynroot * znroot
        xn = (xn + lamda) * 0.25f64
        yn = (yn + lamda) * 0.25f64
        zn = (zn + lamda) * 0.25f64
        n += 1i64
        if n == 10000i64 { ret (0.0f64, 0.0f64) }
    }
    let e2 = xndev * yndev - zndev * zndev
    let e3 = xndev * yndev * zndev
    let s = 1.0f64 + (c1 * e2 - 0.1f64 - c2 * e3) * e2 + c3 * e3
    let v = s / math.sqrt[f64](mu)
    ret (v, prec_of(mode) * fa(v))
}

fn rj(x: f64, y: f64, z: f64, p: f64, mode: usize) -> (f64, f64) {
    let errtol = errtol_of(mode)
    let lolim = math.pow[f64](5.0f64 * dbl_min(), 1.0f64 / 3.0f64)
    let uplim = 0.3f64 * math.pow[f64](0.2f64 * dbl_max(), 1.0f64 / 3.0f64)
    if x < 0.0f64 || y < 0.0f64 || z < 0.0f64 { ret (0.0f64, 0.0f64) }
    if x + y < lolim || x + z < lolim || y + z < lolim || p < lolim { ret (0.0f64, 0.0f64) }
    if !(max4(x, y, z, p) < uplim) { ret (0.0f64, 0.0f64) }
    let c1 = 3.0f64 / 14.0f64
    let c2 = 1.0f64 / 3.0f64
    let c3 = 3.0f64 / 22.0f64
    let c4 = 3.0f64 / 26.0f64
    var xn = x
    var yn = y
    var zn = z
    var pn = p
    var sigma = 0.0f64
    var power4 = 1.0f64
    var mu = 0.0f64
    var xndev = 0.0f64
    var yndev = 0.0f64
    var zndev = 0.0f64
    var pndev = 0.0f64
    var n = 0i64
    while true {
        mu = (xn + yn + zn + pn + pn) * 0.2f64
        xndev = (mu - xn) / mu
        yndev = (mu - yn) / mu
        zndev = (mu - zn) / mu
        pndev = (mu - pn) / mu
        let epslon = max4(fa(xndev), fa(yndev), fa(zndev), fa(pndev))
        if epslon < errtol { break }
        let xnroot = math.sqrt[f64](xn)
        let ynroot = math.sqrt[f64](yn)
        let znroot = math.sqrt[f64](zn)
        let lamda = xnroot * (ynroot + znroot) + ynroot * znroot
        var alfa = pn * (xnroot + ynroot + znroot) + xnroot * ynroot * znroot
        alfa = alfa * alfa
        let beta = pn * (pn + lamda) * (pn + lamda)
        let (rcv, rce) = rc(alfa, beta, mode)
        if rcv == 0.0f64 && rce == 0.0f64 { ret (0.0f64, 0.0f64) }
        sigma += power4 * rcv
        power4 *= 0.25f64
        xn = (xn + lamda) * 0.25f64
        yn = (yn + lamda) * 0.25f64
        zn = (zn + lamda) * 0.25f64
        pn = (pn + lamda) * 0.25f64
        n += 1i64
        if n == 10000i64 { ret (0.0f64, 0.0f64) }
    }
    let ea = xndev * (yndev + zndev) + yndev * zndev
    let eb = xndev * yndev * zndev
    let ec = pndev * pndev
    let e2 = ea - 3.0f64 * ec
    let e3 = eb + 2.0f64 * pndev * (ea - ec)
    let s1 = 1.0f64 + e2 * (0.0f64 - c1 + 0.75f64 * c3 * e2 - 1.5f64 * c4 * e3)
    let s2 = eb * (0.5f64 * c2 + pndev * (0.0f64 - c3 - c3 + pndev * c4))
    let s3 = pndev * ea * (c2 - pndev * c3) - c2 * pndev * ec
    let v = 3.0f64 * sigma + power4 * (s1 + s2 + s3) / (mu * math.sqrt[f64](mu))
    ret (v, prec_of(mode) * fa(v))
}

fn kcomp(k: f64, mode: usize) -> (f64, f64) {
    if k * k >= 1.0f64 { ret (0.0f64, 0.0f64) }
    if k * k >= 1.0f64 - 1.4901161193847656e-08f64 {
        let y = 1.0f64 - k * k
        let ta = 1.38629436112f64 + y * (0.09666344259f64 + y * 0.03590092383f64)
        let tb = 0.0f64 - math.log[f64](y) * (0.5f64 + y * (0.12498593597f64 + y * 0.06880248576f64))
        let v = ta + tb
        ret (v, 2.0f64 * c_eps() * (fa(v) + fa(k / y)))
    }
    let y = 1.0f64 - k * k
    let (v, e) = rf(0.0f64, y, 1.0f64, mode)
    ret (v, e + 0.5f64 * c_eps() / y)
}

fn ecomp(k: f64, mode: usize) -> (f64, f64) {
    if k * k >= 1.0f64 { ret (0.0f64, 0.0f64) }
    if k * k >= 1.0f64 - 1.4901161193847656e-08f64 {
        let y = 1.0f64 - k * k
        let ta = 1.0f64 + y * (0.44325141463f64 + y * (0.06260601220f64 + 0.04757383546f64 * y))
        let tb = 0.0f64 - y * math.log[f64](y) * (0.24998368310f64 + y * (0.09200180037f64 + 0.04069697526f64 * y))
        let v = ta + tb
        ret (v, 2.0f64 * c_eps() * v)
    }
    let y = 1.0f64 - k * k
    let (fv, fe) = rf(0.0f64, y, 1.0f64, mode)
    let (dv, de) = rd(0.0f64, y, 1.0f64, mode)
    ret (fv - k * k / 3.0f64 * dv, fe + k * k / 3.0f64 * de)
}

fn pcomp(k: f64, n: f64, mode: usize) -> (f64, f64) {
    if k * k >= 1.0f64 { ret (0.0f64, 0.0f64) }
    let y = 1.0f64 - k * k
    let (fv, fe) = rf(0.0f64, y, 1.0f64, mode)
    let (jv, je) = rj(0.0f64, y, 1.0f64, 1.0f64 + n, mode)
    ret (fv - (n / 3.0f64) * jv, fe + fa(n / 3.0f64) * je)
}

fn dcomp(k: f64, mode: usize) -> (f64, f64) {
    if k * k >= 1.0f64 { ret (0.0f64, 0.0f64) }
    let y = 1.0f64 - k * k
    let (dv, de) = rd(0.0f64, y, 1.0f64, mode)
    let v = (1.0f64 / 3.0f64) * dv
    ret (v, c_eps() * fa(v) + fa(1.0f64 / 3.0f64 * de))
}

fn sgn(x: f64) -> f64 {
    if x >= 0.0f64 { ret 1.0f64 }
    ret -1.0f64
}

fn pi_() -> f64 { ret 3.141592653589793238462643383279f64 }

fn ell_f(phi0: f64, k: f64, mode: usize) -> (f64, f64) {
    let nc = math.floor[f64](phi0 / pi_() + 0.5f64)
    let phi = phi0 - nc * pi_()
    let sin_phi = math.sin[f64](phi)
    let sin2_phi = sin_phi * sin_phi
    let x = 1.0f64 - sin2_phi
    let y = 1.0f64 - k * k * sin2_phi
    let (rv, re) = rf(x, y, 1.0f64, mode)
    var v = sin_phi * rv
    var e = c_eps() * fa(v) + fa(sin_phi * re)
    if nc != 0.0f64 {
        let (kv, ke) = kcomp(k, mode)
        v += 2.0f64 * nc * kv
        e += 2.0f64 * fa(nc) * ke
    }
    ret (v, e)
}

fn ell_e(phi0: f64, k: f64, mode: usize) -> (f64, f64) {
    let nc = math.floor[f64](phi0 / pi_() + 0.5f64)
    let phi = phi0 - nc * pi_()
    let sin_phi = math.sin[f64](phi)
    let sin2_phi = sin_phi * sin_phi
    let x = 1.0f64 - sin2_phi
    let y = 1.0f64 - k * k * sin2_phi
    if x < c_eps() {
        let (ev, ee) = ecomp(k, mode)
        ret (2.0f64 * nc * ev + sgn(sin_phi) * ev, 2.0f64 * fa(nc) * ee + ee)
    }
    let sin3_phi = sin2_phi * sin_phi
    let (fv, fe) = rf(x, y, 1.0f64, mode)
    let (dv, de) = rd(x, y, 1.0f64, mode)
    var v = sin_phi * fv - k * k / 3.0f64 * sin3_phi * dv
    var e = c_eps() * fa(sin_phi * fv)
    e += fa(sin_phi * fe)
    e += k * k / 3.0f64 * c_eps() * fa(sin3_phi * dv)
    e += k * k / 3.0f64 * fa(sin3_phi * de)
    if nc != 0.0f64 {
        let (ev, ee) = ecomp(k, mode)
        v += 2.0f64 * nc * ev
        e += 2.0f64 * fa(nc) * ee
    }
    ret (v, e)
}

fn ell_p(phi0: f64, k: f64, n: f64, mode: usize) -> (f64, f64) {
    let nc = math.floor[f64](phi0 / pi_() + 0.5f64)
    let phi = phi0 - nc * pi_()
    let sin_phi = math.sin[f64](phi)
    let sin2_phi = sin_phi * sin_phi
    let sin3_phi = sin2_phi * sin_phi
    let x = 1.0f64 - sin2_phi
    let y = 1.0f64 - k * k * sin2_phi
    let (fv, fe) = rf(x, y, 1.0f64, mode)
    let (jv, je) = rj(x, y, 1.0f64, 1.0f64 + n * sin2_phi, mode)
    var v = sin_phi * fv - n / 3.0f64 * sin3_phi * jv
    var e = c_eps() * fa(sin_phi * fv)
    e += fa(sin_phi * fe)
    e += n / 3.0f64 * c_eps() * fa(sin3_phi * jv)
    e += n / 3.0f64 * fa(sin3_phi * je)
    if nc != 0.0f64 {
        let (pv, pe) = pcomp(k, n, mode)
        v += 2.0f64 * nc * pv
        e += 2.0f64 * fa(nc) * pe
    }
    ret (v, e)
}

fn ell_d(phi0: f64, k: f64, mode: usize) -> (f64, f64) {
    let nc = math.floor[f64](phi0 / pi_() + 0.5f64)
    let phi = phi0 - nc * pi_()
    let sin_phi = math.sin[f64](phi)
    let sin2_phi = sin_phi * sin_phi
    let sin3_phi = sin2_phi * sin_phi
    let x = 1.0f64 - sin2_phi
    let y = 1.0f64 - k * k * sin2_phi
    let (dv, de) = rd(x, y, 1.0f64, mode)
    var v = sin3_phi / 3.0f64 * dv
    var e = c_eps() * fa(v) + fa(sin3_phi / 3.0f64 * de)
    if nc != 0.0f64 {
        let (cv, ce) = dcomp(k, mode)
        v += 2.0f64 * nc * cv
        e += 2.0f64 * fa(nc) * ce
    }
    ret (v, e)
}
