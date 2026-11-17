// R geosphere: Karney's geodesic on an ellipsoid (the GeographicLib 2.7 series of order 6 that the package compiles in) and what is built on it:
// distGeo, bearing, finalBearing, destPoint, midPoint, areaPolygon, perimeter and centroid. Degrees in, metres (square metres) out; a is the
// equatorial radius and f the flattening (R defaults 6378137 and 1/298.257223563).

use e.math
use e.mem

type Geod = struct {
    a: f64,
    f: f64,
    f1: f64,
    e2: f64,
    ep2: f64,
    n: f64,
    b: f64,
    c2: f64,
    etol2: f64,
    tiny: f64,
    a3x: [6]f64,
    c3x: [15]f64,
    c4x: [21]f64,
}

// the outputs of one inverse solution and the state its iteration carries
type Sol = struct {
    salp1: f64,
    calp1: f64,
    salp2: f64,
    calp2: f64,
    sig12: f64,
    ssig1: f64,
    csig1: f64,
    ssig2: f64,
    csig2: f64,
    eps: f64,
    domg12: f64,
    dnm: f64,
    dlam12: f64,
    s12: f64,
    area12: f64,
    lat2: f64,
    lon2: f64,
    azi2: f64,
}

type Acc = struct {
    s: f64,
    t: f64,
}

fn ga_pi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn ga_degree() -> f64 { ret ga_pi() / 180.0f64 }
fn ga_nan() -> f64 { ret 0.0f64 / 0.0f64 }
fn ga_isnan(x: f64) -> bool { ret x != x }
fn ga_signbit(x: f64) -> bool { ret math.is_negative[f64](x) }
fn ga_abs(x: f64) -> f64 { ret math.abs[f64](x) }
fn ga_tol0() -> f64 { ret 2.220446049250313e-16f64 }
fn ga_tol2() -> f64 { ret 1.4901161193847656e-8f64 }
fn ga_maxit1() -> usize { ret 20usize }
fn ga_maxit2() -> usize { ret 83usize }

fn ga_fmax(x: f64, y: f64) -> f64 {
    if ga_isnan(x) { ret y }
    if ga_isnan(y) { ret x }
    if x > y { ret x }
    ret y
}

fn ga_fmin(x: f64, y: f64) -> f64 {
    if ga_isnan(x) { ret y }
    if ga_isnan(y) { ret x }
    if x < y { ret x }
    ret y
}

fn ga_hypot(x: f64, y: f64) -> f64 {
    let ax = ga_abs(x)
    let ay = ga_abs(y)
    let m = ga_fmax(ax, ay)
    if m == 0.0f64 { ret 0.0f64 }
    if m < 1.0e-100f64 {
        let sx = ax / m
        let sy = ay / m
        ret m * math.sqrt[f64](sx * sx + sy * sy)
    }
    ret math.sqrt[f64](ax * ax + ay * ay)
}

// libm cbrt to within an ulp: pow, then one Newton step
fn ga_cbrt(x: f64) -> f64 {
    if x == 0.0f64 || ga_isnan(x) { ret x }
    var y = math.pow[f64](ga_abs(x), 1.0f64 / 3.0f64)
    if x < 0.0f64 { y = 0.0f64 - y }
    ret y - (y * y * y - x) / (3.0f64 * y * y)
}

// round to nearest, ties to even
fn ga_round_even(x: f64) -> f64 {
    let fl = math.floor[f64](x)
    let d = x - fl
    if d < 0.5f64 { ret fl }
    if d > 0.5f64 { ret fl + 1.0f64 }
    let h = fl * 0.5f64
    if math.floor[f64](h) == h { ret fl }
    ret fl + 1.0f64
}

// IEEE remainder: x - n y with n the nearest integer to x / y
fn ga_remainder(x: f64, y: f64) -> f64 {
    let n = ga_round_even(x / y)
    let r = math.fma[f64](0.0f64 - n, y, x)
    if r == 0.0f64 { ret math.copysign[f64](0.0f64, x) }
    ret r
}

fn ga_sum(u: f64, v: f64) -> (f64, f64) {
    let s = u + v
    var up = s - v
    var vpp = s - up
    up = up - u
    vpp = vpp - v
    var t = s
    if s != 0.0f64 { t = 0.0f64 - (up + vpp) }
    ret (s, t)
}

fn ga_angnormalize(x: f64) -> f64 {
    let y = ga_remainder(x, 360.0f64)
    if ga_abs(y) == 180.0f64 { ret math.copysign[f64](180.0f64, x) }
    ret y
}

// the difference y - x of two angles in (-180, 180] and its rounding error
fn ga_angdiff(x: f64, y: f64) -> (f64, f64) {
    let (d0, e0) = ga_sum(ga_remainder(0.0f64 - x, 360.0f64), ga_remainder(y, 360.0f64))
    let (d1, e1) = ga_sum(ga_remainder(d0, 360.0f64), e0)
    var d = d1
    if d == 0.0f64 || ga_abs(d) == 180.0f64 {
        if e1 == 0.0f64 {
            d = math.copysign[f64](d, y - x)
        } else {
            d = math.copysign[f64](d, 0.0f64 - e1)
        }
    }
    ret (d, e1)
}

fn ga_round(x: f64) -> f64 {
    let z = 1.0f64 / 16.0f64
    var y = ga_abs(x)
    let w = z - y
    if w > 0.0f64 { y = z - w }
    ret math.copysign[f64](y, x)
}

fn ga_latfix(x: f64) -> f64 {
    if ga_abs(x) > 90.0f64 { ret ga_nan() }
    ret x
}

// sin and cos of an angle in degrees with the exact values at multiples of 30 and 45 degrees
fn ga_sincos_reduced(d: f64, n: f64, x: f64) -> (f64, f64) {
    let r = d * ga_degree()
    var s = math.sin[f64](r)
    var c = math.cos[f64](r)
    if 2.0f64 * ga_abs(d) == 90.0f64 {
        c = math.sqrt[f64](0.5f64)
        s = math.copysign[f64](c, r)
    } else if 3.0f64 * ga_abs(d) == 90.0f64 {
        c = math.sqrt[f64](3.0f64) / 2.0f64
        s = math.copysign[f64](0.5f64, r)
    }
    let q = n - 4.0f64 * math.floor[f64](n / 4.0f64)
    var sx = 0.0f64
    var cx = 0.0f64
    if q == 0.0f64 {
        sx = s
        cx = c
    } else if q == 1.0f64 {
        sx = c
        cx = 0.0f64 - s
    } else if q == 2.0f64 {
        sx = 0.0f64 - s
        cx = 0.0f64 - c
    } else {
        sx = 0.0f64 - c
        cx = s
    }
    cx = cx + 0.0f64
    if sx == 0.0f64 { sx = math.copysign[f64](sx, x) }
    ret (sx, cx)
}

fn ga_sincosd(x: f64) -> (f64, f64) {
    let n = ga_round_even(x / 90.0f64)
    let d = math.fma[f64](0.0f64 - n, 90.0f64, x)
    let (sx, cx) = ga_sincos_reduced(d, n, x)
    ret (sx, cx)
}

fn ga_sincosde(x: f64, t: f64) -> (f64, f64) {
    let n = ga_round_even(x / 90.0f64)
    let d0 = math.fma[f64](0.0f64 - n, 90.0f64, x)
    let (sx, cx) = ga_sincos_reduced(ga_round(d0 + t), n, x)
    ret (sx, cx)
}

fn ga_atan2d(y0: f64, x0: f64) -> f64 {
    var x = x0
    var y = y0
    var q = 0i64
    if ga_abs(y) > ga_abs(x) {
        let tmp = x
        x = y
        y = tmp
        q = 2i64
    }
    if ga_signbit(x) {
        x = 0.0f64 - x
        q = q + 1i64
    }
    var ang = (math.atan2[f64](y, x) / ga_pi()) * 180.0f64
    if q == 1i64 {
        ang = math.copysign[f64](180.0f64, y) - ang
    } else if q == 2i64 {
        ang = 90.0f64 - ang
    } else if q == 3i64 {
        ang = ang - 90.0f64
    }
    ret ang
}

fn ga_norm(x: f64, y: f64) -> (f64, f64) {
    let r = ga_hypot(x, y)
    ret (x / r, y / r)
}

fn ga_polyval(n: i64, p: []const f64, o: usize, x: f64) -> f64 {
    var y = 0.0f64
    var i = o
    if n >= 0i64 {
        y = p[i]
        i = i + 1usize
    }
    var k = n
    while k > 0i64 {
        y = y * x + p[i]
        i = i + 1usize
        k = k - 1i64
    }
    ret y
}

fn ga_sincosseries(sinp: bool, sinx: f64, cosx: f64, c: []const f64, n: usize) -> f64 {
    var pos = n
    if sinp { pos = pos + 1usize }
    let ar = 2.0f64 * (cosx - sinx) * (cosx + sinx)
    var y0 = 0.0f64
    var y1 = 0.0f64
    if n % 2usize == 1usize {
        pos = pos - 1usize
        y0 = c[pos]
    }
    var k = n / 2usize
    while k > 0usize {
        pos = pos - 1usize
        y1 = ar * y0 - y1 + c[pos]
        pos = pos - 1usize
        y0 = ar * y1 - y0 + c[pos]
        k = k - 1usize
    }
    if sinp { ret 2.0f64 * sinx * cosx * y0 }
    ret cosx * (y0 - y1)
}

fn ga_a1m1f(eps: f64) -> f64 {
    let co = [5]f64{ 1.0f64, 4.0f64, 64.0f64, 0.0f64, 256.0f64 }
    let t = ga_polyval(3i64, co[..], 0usize, eps * eps) / co[4usize]
    ret (t + eps) / (1.0f64 - eps)
}

fn ga_a2m1f(eps: f64) -> f64 {
    let co = [5]f64{ -11.0f64, -28.0f64, -192.0f64, 0.0f64, 256.0f64 }
    let t = ga_polyval(3i64, co[..], 0usize, eps * eps) / co[4usize]
    ret (t - eps) / (1.0f64 + eps)
}

// C1, C1p and C2 share one shape: c[l] = eps^l P_l(eps^2) over the last coefficient of its row
fn ga_series_coeffs(co: []const f64, eps: f64, c: []f64) {
    let eps2 = eps * eps
    var d = eps
    var o = 0usize
    var l = 1usize
    while l <= 6usize {
        let m = (6usize - l) / 2usize
        c[l] = d * ga_polyval(i64(m), co, o, eps2) / co[o + m + 1usize]
        o = o + m + 2usize
        d = d * eps
        l = l + 1usize
    }
}

fn ga_c1f(eps: f64, c: []f64) {
    let co = ga_t_c1()
    ga_series_coeffs(co[..], eps, c)
}

fn ga_c1pf(eps: f64, c: []f64) {
    let co = ga_t_c1p()
    ga_series_coeffs(co[..], eps, c)
}

fn ga_c2f(eps: f64, c: []f64) {
    let co = ga_t_c2()
    ga_series_coeffs(co[..], eps, c)
}

fn ga_a3f(g: *const Geod, eps: f64) -> f64 {
    ret ga_polyval(5i64, g.a3x[..], 0usize, eps)
}

fn ga_c3f(g: *const Geod, eps: f64, c: []f64) {
    var mult = 1.0f64
    var o = 0usize
    var l = 1usize
    while l < 6usize {
        let m = 5usize - l
        mult = mult * eps
        c[l] = mult * ga_polyval(i64(m), g.c3x[..], o, eps)
        o = o + m + 1usize
        l = l + 1usize
    }
}

fn ga_c4f(g: *const Geod, eps: f64, c: []f64) {
    var mult = 1.0f64
    var o = 0usize
    var l = 0usize
    while l < 6usize {
        let m = 5usize - l
        c[l] = mult * ga_polyval(i64(m), g.c4x[..], o, eps)
        o = o + m + 1usize
        mult = mult * eps
        l = l + 1usize
    }
}

fn ga_eatanhe(x: f64, es: f64) -> f64 {
    if es > 0.0f64 {
        let z = es * x
        ret es * 0.5f64 * math.log[f64]((1.0f64 + z) / (1.0f64 - z))
    }
    ret (0.0f64 - es) * math.atan[f64](es * x)
}

fn ga_init(g: *Geod, a: f64, f: f64) {
    g.a = a
    g.f = f
    g.f1 = 1.0f64 - f
    g.e2 = f * (2.0f64 - f)
    g.ep2 = g.e2 / (g.f1 * g.f1)
    g.n = f / (2.0f64 - f)
    g.b = a * g.f1
    g.tiny = math.sqrt[f64](mem.bitcast[f64](4503599627370496u64))
    var ee = 1.0f64
    if g.e2 != 0.0f64 {
        var es = math.sqrt[f64](ga_abs(g.e2))
        if f < 0.0f64 { es = 0.0f64 - es }
        ee = ga_eatanhe(1.0f64, es) / g.e2
    }
    g.c2 = (a * a + g.b * g.b * ee) / 2.0f64
    g.etol2 = 0.1f64 * ga_tol2() / math.sqrt[f64](ga_fmax(0.001f64, ga_abs(f)) * ga_fmin(1.0f64, 1.0f64 - f / 2.0f64) / 2.0f64)
    let t3 = ga_t_a3()
    var o = 0usize
    var k = 0usize
    var j = 5i64
    while j >= 0i64 {
        let m = ga_imin(5i64 - j, j)
        g.a3x[k] = ga_polyval(m, t3[..], o, g.n) / t3[o + usize(m) + 1usize]
        k = k + 1usize
        o = o + usize(m) + 2usize
        j = j - 1i64
    }
    let t4 = ga_t_c3()
    o = 0usize
    k = 0usize
    var l = 1i64
    while l < 6i64 {
        j = 5i64
        while j >= l {
            let m = ga_imin(5i64 - j, j)
            g.c3x[k] = ga_polyval(m, t4[..], o, g.n) / t4[o + usize(m) + 1usize]
            k = k + 1usize
            o = o + usize(m) + 2usize
            j = j - 1i64
        }
        l = l + 1i64
    }
    let t5 = ga_t_c4()
    o = 0usize
    k = 0usize
    l = 0i64
    while l < 6i64 {
        j = 5i64
        while j >= l {
            let m = 5i64 - j
            g.c4x[k] = ga_polyval(m, t5[..], o, g.n) / t5[o + usize(m) + 1usize]
            k = k + 1usize
            o = o + usize(m) + 2usize
            j = j - 1i64
        }
        l = l + 1i64
    }
}

fn ga_imin(x: i64, y: i64) -> i64 {
    if x < y { ret x }
    ret y
}

// the distance, reduced length and m0 of a geodesic segment from its auxiliary-sphere arc; dist and red say which are wanted
fn ga_lengths(g: *const Geod, eps: f64, sig12: f64, ssig1: f64, csig1: f64, dn1: f64, ssig2: f64, csig2: f64, dn2: f64, dist: bool, red: bool, ca: []f64) -> (f64, f64, f64) {
    var s12b = 0.0f64
    var m0x = 0.0f64
    var j12 = 0.0f64
    var a1 = 0.0f64
    var a2 = 0.0f64
    var cb: [7]f64 = zero
    if dist || red {
        a1 = ga_a1m1f(eps)
        ga_c1f(eps, ca)
        if red {
            a2 = ga_a2m1f(eps)
            ga_c2f(eps, cb[..])
            m0x = a1 - a2
            a2 = 1.0f64 + a2
        }
        a1 = 1.0f64 + a1
    }
    if dist {
        let b1 = ga_sincosseries(true, ssig2, csig2, ca, 6usize) - ga_sincosseries(true, ssig1, csig1, ca, 6usize)
        s12b = a1 * (sig12 + b1)
        if red {
            let b2 = ga_sincosseries(true, ssig2, csig2, cb[..], 6usize) - ga_sincosseries(true, ssig1, csig1, cb[..], 6usize)
            j12 = m0x * sig12 + (a1 * b1 - a2 * b2)
        }
    } else if red {
        var l = 1usize
        while l <= 6usize {
            cb[l] = a1 * ca[l] - a2 * cb[l]
            l = l + 1usize
        }
        j12 = m0x * sig12 + (ga_sincosseries(true, ssig2, csig2, cb[..], 6usize) - ga_sincosseries(true, ssig1, csig1, cb[..], 6usize))
    }
    var m12b = 0.0f64
    if red { m12b = dn2 * (csig1 * ssig2) - dn1 * (ssig1 * csig2) - csig1 * csig2 * j12 }
    ret (s12b, m12b, m0x)
}

fn ga_astroid(x: f64, y: f64) -> f64 {
    var k = 0.0f64
    let p = x * x
    let q = y * y
    let r = (p + q - 1.0f64) / 6.0f64
    if !(q == 0.0f64 && r <= 0.0f64) {
        let s = p * q / 4.0f64
        let r2 = r * r
        let r3 = r * r2
        let disc = s * (s + 2.0f64 * r3)
        var u = r
        if disc >= 0.0f64 {
            var t3 = s + r3
            if t3 < 0.0f64 {
                t3 = t3 - math.sqrt[f64](disc)
            } else {
                t3 = t3 + math.sqrt[f64](disc)
            }
            let t = ga_cbrt(t3)
            var add = 0.0f64
            if t != 0.0f64 { add = r2 / t }
            u = u + t + add
        } else {
            let ang = math.atan2[f64](math.sqrt[f64](0.0f64 - disc), 0.0f64 - (s + r3))
            u = u + 2.0f64 * r * math.cos[f64](ang / 3.0f64)
        }
        let v = math.sqrt[f64](u * u + q)
        var uv = u + v
        if u < 0.0f64 { uv = q / (v - u) }
        let w = (uv - q) / (2.0f64 * v)
        k = uv / (math.sqrt[f64](uv + w * w) + w)
    }
    ret k
}

fn ga_inverse_start(g: *const Geod, sbet1: f64, cbet1: f64, dn1: f64, sbet2: f64, cbet2: f64, dn2: f64, lam12: f64, slam12: f64, clam12: f64, o: *Sol, ca: []f64) -> f64 {
    var sig12 = 0.0f64 - 1.0f64
    let sbet12 = sbet2 * cbet1 - cbet2 * sbet1
    let cbet12 = cbet2 * cbet1 + sbet2 * sbet1
    let sbet12a = sbet2 * cbet1 + cbet2 * sbet1
    let shortline = cbet12 >= 0.0f64 && sbet12 < 0.5f64 && cbet2 * lam12 < 0.5f64
    var somg12 = slam12
    var comg12 = clam12
    if shortline {
        var sbetm2 = (sbet1 + sbet2) * (sbet1 + sbet2)
        sbetm2 = sbetm2 / (sbetm2 + (cbet1 + cbet2) * (cbet1 + cbet2))
        o.dnm = math.sqrt[f64](1.0f64 + g.ep2 * sbetm2)
        let omg12 = lam12 / (g.f1 * o.dnm)
        somg12 = math.sin[f64](omg12)
        comg12 = math.cos[f64](omg12)
    }
    o.salp1 = cbet2 * somg12
    if comg12 >= 0.0f64 {
        o.calp1 = sbet12 + cbet2 * sbet1 * somg12 * somg12 / (1.0f64 + comg12)
    } else {
        o.calp1 = sbet12a - cbet2 * sbet1 * somg12 * somg12 / (1.0f64 - comg12)
    }
    let ssig12 = ga_hypot(o.salp1, o.calp1)
    let csig12 = sbet1 * sbet2 + cbet1 * cbet2 * comg12
    if shortline && ssig12 < g.etol2 {
        o.salp2 = cbet1 * somg12
        var corr = 1.0f64 - comg12
        if comg12 >= 0.0f64 { corr = somg12 * somg12 / (1.0f64 + comg12) }
        o.calp2 = sbet12 - cbet1 * sbet2 * corr
        let (ns2, nc2) = ga_norm(o.salp2, o.calp2)
        o.salp2 = ns2
        o.calp2 = nc2
        sig12 = math.atan2[f64](ssig12, csig12)
    } else if !(ga_abs(g.n) > 0.1f64 || csig12 >= 0.0f64 || ssig12 >= 6.0f64 * ga_abs(g.n) * ga_pi() * cbet1 * cbet1) {
        var x = 0.0f64
        var y = 0.0f64
        var lamscale = 0.0f64
        var betscale = 0.0f64
        let lam12x = math.atan2[f64](0.0f64 - slam12, 0.0f64 - clam12)
        if g.f >= 0.0f64 {
            let k2 = sbet1 * sbet1 * g.ep2
            let eps = k2 / (2.0f64 * (1.0f64 + math.sqrt[f64](1.0f64 + k2)) + k2)
            lamscale = g.f * cbet1 * ga_a3f(g, eps) * ga_pi()
            betscale = lamscale * cbet1
            x = lam12x / lamscale
            y = sbet12a / betscale
        } else {
            let cbet12a = cbet2 * cbet1 - sbet2 * sbet1
            let bet12a = math.atan2[f64](sbet12a, cbet12a)
            let (dummy, m12b, m0) = ga_lengths(g, g.n, ga_pi() + bet12a, sbet1, 0.0f64 - cbet1, dn1, sbet2, cbet2, dn2, false, true, ca)
            x = 0.0f64 - 1.0f64 + m12b / (cbet1 * cbet2 * m0 * ga_pi())
            if x < 0.0f64 - 0.01f64 {
                betscale = sbet12a / x
            } else {
                betscale = (0.0f64 - g.f) * cbet1 * cbet1 * ga_pi()
            }
            lamscale = betscale / cbet1
            y = lam12x / lamscale
        }
        if y > 0.0f64 - 200.0f64 * ga_tol0() && x > 0.0f64 - 1.0f64 - 1000.0f64 * ga_tol2() {
            if g.f >= 0.0f64 {
                o.salp1 = ga_fmin(1.0f64, 0.0f64 - x)
                o.calp1 = 0.0f64 - math.sqrt[f64](1.0f64 - o.salp1 * o.salp1)
            } else {
                var lo = 0.0f64 - 1.0f64
                if x > 0.0f64 - 200.0f64 * ga_tol0() { lo = 0.0f64 }
                o.calp1 = ga_fmax(lo, x)
                o.salp1 = math.sqrt[f64](1.0f64 - o.calp1 * o.calp1)
            }
        } else {
            let k = ga_astroid(x, y)
            var omg12a = 0.0f64
            if g.f >= 0.0f64 {
                omg12a = lamscale * (0.0f64 - x * k / (1.0f64 + k))
            } else {
                omg12a = lamscale * (0.0f64 - y * (1.0f64 + k) / k)
            }
            somg12 = math.sin[f64](omg12a)
            comg12 = 0.0f64 - math.cos[f64](omg12a)
            o.salp1 = cbet2 * somg12
            o.calp1 = sbet12a - cbet2 * sbet1 * somg12 * somg12 / (1.0f64 - comg12)
        }
    }
    if !(o.salp1 <= 0.0f64) {
        let (ns1, nc1) = ga_norm(o.salp1, o.calp1)
        o.salp1 = ns1
        o.calp1 = nc1
    } else {
        o.salp1 = 1.0f64
        o.calp1 = 0.0f64
    }
    ret sig12
}

// lam12(alp1) minus the target longitude difference, and in o.dlam12 its derivative when diffp
fn ga_lambda12(g: *const Geod, sbet1: f64, cbet1: f64, dn1: f64, sbet2: f64, cbet2: f64, dn2: f64, salp1: f64, calp1in: f64, slam120: f64, clam120: f64, diffp: bool, o: *Sol, ca: []f64) -> f64 {
    var calp1 = calp1in
    if sbet1 == 0.0f64 && calp1 == 0.0f64 { calp1 = 0.0f64 - g.tiny }
    let salp0 = salp1 * cbet1
    let calp0 = ga_hypot(calp1, salp1 * sbet1)
    o.ssig1 = sbet1
    let somg1 = salp0 * sbet1
    o.csig1 = calp1 * cbet1
    let comg1 = o.csig1
    let (ns1, nc1) = ga_norm(o.ssig1, o.csig1)
    o.ssig1 = ns1
    o.csig1 = nc1
    if cbet2 != cbet1 {
        o.salp2 = salp0 / cbet2
    } else {
        o.salp2 = salp1
    }
    if cbet2 != cbet1 || ga_abs(sbet2) != 0.0f64 - sbet1 {
        var tail = (sbet1 - sbet2) * (sbet1 + sbet2)
        if cbet1 < 0.0f64 - sbet1 { tail = (cbet2 - cbet1) * (cbet1 + cbet2) }
        o.calp2 = math.sqrt[f64]((calp1 * cbet1) * (calp1 * cbet1) + tail) / cbet2
    } else {
        o.calp2 = ga_abs(calp1)
    }
    o.ssig2 = sbet2
    let somg2 = salp0 * sbet2
    o.csig2 = o.calp2 * cbet2
    let comg2 = o.csig2
    let (ns2, nc2) = ga_norm(o.ssig2, o.csig2)
    o.ssig2 = ns2
    o.csig2 = nc2
    o.sig12 = math.atan2[f64](ga_fmax(0.0f64, o.csig1 * o.ssig2 - o.ssig1 * o.csig2) + 0.0f64, o.csig1 * o.csig2 + o.ssig1 * o.ssig2)
    let somg12 = ga_fmax(0.0f64, comg1 * somg2 - somg1 * comg2) + 0.0f64
    let comg12 = comg1 * comg2 + somg1 * somg2
    let eta = math.atan2[f64](somg12 * clam120 - comg12 * slam120, comg12 * clam120 + somg12 * slam120)
    let k2 = calp0 * calp0 * g.ep2
    o.eps = k2 / (2.0f64 * (1.0f64 + math.sqrt[f64](1.0f64 + k2)) + k2)
    ga_c3f(g, o.eps, ca)
    let b312 = ga_sincosseries(true, o.ssig2, o.csig2, ca, 5usize) - ga_sincosseries(true, o.ssig1, o.csig1, ca, 5usize)
    o.domg12 = (0.0f64 - g.f) * ga_a3f(g, o.eps) * salp0 * (o.sig12 + b312)
    let lam12 = eta + o.domg12
    if diffp {
        if o.calp2 == 0.0f64 {
            o.dlam12 = 0.0f64 - 2.0f64 * g.f1 * dn1 / sbet1
        } else {
            let (dummy, m12b, m0) = ga_lengths(g, o.eps, o.sig12, o.ssig1, o.csig1, dn1, o.ssig2, o.csig2, dn2, false, true, ca)
            o.dlam12 = m12b * g.f1 / (o.calp2 * cbet2)
        }
    }
    ret lam12
}

// the inverse problem: fills o.s12 and the end azimuths (salp/calp 1 and 2); with area also o.area12 (S12, the area under the geodesic)
fn ga_inverse(g: *const Geod, lat1in: f64, lon1: f64, lat2in: f64, lon2: f64, area: bool, o: *Sol) {
    let tiny = g.tiny
    var ca: [7]f64 = zero
    let (lon12a, lon12sa) = ga_angdiff(lon1, lon2)
    var lonsign = 1.0f64
    if ga_signbit(lon12a) { lonsign = 0.0f64 - 1.0f64 }
    let lon12 = lon12a * lonsign
    let lam12 = lon12 * ga_degree()
    let (slam12, clam12) = ga_sincosde(lon12, lon12sa * lonsign)
    let lon12s = (180.0f64 - lon12) - lon12sa * lonsign
    var lat1 = ga_round(ga_latfix(lat1in))
    var lat2 = ga_round(ga_latfix(lat2in))
    var swapp = 1.0f64
    if ga_abs(lat1) < ga_abs(lat2) || ga_isnan(lat2) { swapp = 0.0f64 - 1.0f64 }
    if swapp < 0.0f64 {
        lonsign = 0.0f64 - lonsign
        let tl = lat1
        lat1 = lat2
        lat2 = tl
    }
    var latsign = 0.0f64 - 1.0f64
    if ga_signbit(lat1) { latsign = 1.0f64 }
    lat1 = lat1 * latsign
    lat2 = lat2 * latsign
    let (sb1, cb1) = ga_sincosd(lat1)
    let (nsb1, ncb1) = ga_norm(sb1 * g.f1, cb1)
    let sbet1 = nsb1
    let cbet1 = ga_fmax(tiny, ncb1)
    let (sb2, cb2) = ga_sincosd(lat2)
    let (nsb2, ncb2) = ga_norm(sb2 * g.f1, cb2)
    var sbet2 = nsb2
    var cbet2 = ga_fmax(tiny, ncb2)
    if cbet1 < 0.0f64 - sbet1 {
        if cbet2 == cbet1 { sbet2 = math.copysign[f64](sbet1, sbet2) }
    } else {
        if ga_abs(sbet2) == 0.0f64 - sbet1 { cbet2 = cbet1 }
    }
    let dn1 = math.sqrt[f64](1.0f64 + g.ep2 * sbet1 * sbet1)
    let dn2 = math.sqrt[f64](1.0f64 + g.ep2 * sbet2 * sbet2)
    var salp1 = 0.0f64
    var calp1 = 0.0f64
    var salp2 = 0.0f64
    var calp2 = 0.0f64
    var sig12 = 0.0f64
    var s12x = 0.0f64
    var m12x = ga_nan()
    var meridian = lat1 == 0.0f64 - 90.0f64 || slam12 == 0.0f64
    if meridian {
        calp1 = clam12
        salp1 = slam12
        calp2 = 1.0f64
        salp2 = 0.0f64
        let ssig1 = sbet1
        let csig1 = calp1 * cbet1
        let ssig2 = sbet2
        let csig2 = calp2 * cbet2
        sig12 = math.atan2[f64](ga_fmax(0.0f64, csig1 * ssig2 - ssig1 * csig2) + 0.0f64, csig1 * csig2 + ssig1 * ssig2)
        let (ls, lm, l0) = ga_lengths(g, g.n, sig12, ssig1, csig1, dn1, ssig2, csig2, dn2, true, true, ca[..])
        s12x = ls
        m12x = lm
        if sig12 < ga_tol2() || m12x >= 0.0f64 {
            if sig12 < 3.0f64 * tiny || (sig12 < ga_tol0() && (s12x < 0.0f64 || m12x < 0.0f64)) {
                sig12 = 0.0f64
                m12x = 0.0f64
                s12x = 0.0f64
            }
            m12x = m12x * g.b
            s12x = s12x * g.b
        } else {
            meridian = false
        }
    }
    var omg12 = 0.0f64
    var somg12 = 2.0f64
    var comg12 = 0.0f64
    if !meridian && sbet1 == 0.0f64 && (g.f <= 0.0f64 || lon12s >= g.f * 180.0f64) {
        calp1 = 0.0f64
        calp2 = 0.0f64
        salp1 = 1.0f64
        salp2 = 1.0f64
        s12x = g.a * lam12
        sig12 = lam12 / g.f1
        omg12 = sig12
    } else if !meridian {
        let sg = ga_inverse_start(g, sbet1, cbet1, dn1, sbet2, cbet2, dn2, lam12, slam12, clam12, o, ca[..])
        salp1 = o.salp1
        calp1 = o.calp1
        salp2 = o.salp2
        calp2 = o.calp2
        sig12 = sg
        if sig12 >= 0.0f64 {
            s12x = sig12 * g.b * o.dnm
            omg12 = lam12 / (g.f1 * o.dnm)
        } else {
            var numit = 0usize
            var salp1a = tiny
            var calp1a = 1.0f64
            var salp1b = tiny
            var calp1b = 0.0f64 - 1.0f64
            var tripn = false
            var tripb = false
            var go = true
            while go {
                let v = ga_lambda12(g, sbet1, cbet1, dn1, sbet2, cbet2, dn2, salp1, calp1, slam12, clam12, numit < ga_maxit1(), o, ca[..])
                let dv = o.dlam12
                var tn = 1.0f64
                if tripn { tn = 8.0f64 }
                if tripb || !(ga_abs(v) >= tn * ga_tol0()) || numit == ga_maxit2() {
                    go = false
                } else {
                    if v > 0.0f64 && (numit > ga_maxit1() || calp1 / salp1 > calp1b / salp1b) {
                        salp1b = salp1
                        calp1b = calp1
                    } else if v < 0.0f64 && (numit > ga_maxit1() || calp1 / salp1 < calp1a / salp1a) {
                        salp1a = salp1
                        calp1a = calp1
                    }
                    var took = false
                    if numit < ga_maxit1() && dv > 0.0f64 {
                        let dalp1 = 0.0f64 - v / dv
                        if ga_abs(dalp1) < ga_pi() {
                            let sdalp1 = math.sin[f64](dalp1)
                            let cdalp1 = math.cos[f64](dalp1)
                            let nsalp1 = salp1 * cdalp1 + calp1 * sdalp1
                            if nsalp1 > 0.0f64 {
                                let ncalp1 = calp1 * cdalp1 - salp1 * sdalp1
                                let (ps, pc) = ga_norm(nsalp1, ncalp1)
                                salp1 = ps
                                calp1 = pc
                                tripn = ga_abs(v) <= 16.0f64 * ga_tol0()
                                took = true
                            }
                        }
                    }
                    if !took {
                        let (bs, bc) = ga_norm((salp1a + salp1b) / 2.0f64, (calp1a + calp1b) / 2.0f64)
                        salp1 = bs
                        calp1 = bc
                        tripn = false
                        tripb = ga_abs(salp1a - salp1) + (calp1a - calp1) < ga_tol0() || ga_abs(salp1 - salp1b) + (calp1 - calp1b) < ga_tol0()
                    }
                    numit = numit + 1usize
                }
            }
            salp2 = o.salp2
            calp2 = o.calp2
            sig12 = o.sig12
            let (ls, lm, l0) = ga_lengths(g, o.eps, sig12, o.ssig1, o.csig1, dn1, o.ssig2, o.csig2, dn2, true, false, ca[..])
            s12x = ls * g.b
            if area {
                let sdomg12 = math.sin[f64](o.domg12)
                let cdomg12 = math.cos[f64](o.domg12)
                somg12 = slam12 * cdomg12 - clam12 * sdomg12
                comg12 = clam12 * cdomg12 + slam12 * sdomg12
            }
        }
    }
    o.s12 = 0.0f64 + s12x
    var s12area = 0.0f64
    if area {
        let salp0 = salp1 * cbet1
        let calp0 = ga_hypot(calp1, salp1 * sbet1)
        var alp12 = 0.0f64
        if calp0 != 0.0f64 && salp0 != 0.0f64 {
            let k2 = calp0 * calp0 * g.ep2
            let eps = k2 / (2.0f64 * (1.0f64 + math.sqrt[f64](1.0f64 + k2)) + k2)
            let a4 = g.a * g.a * calp0 * salp0 * g.e2
            let (ns1, nc1) = ga_norm(sbet1, calp1 * cbet1)
            let (ns2, nc2) = ga_norm(sbet2, calp2 * cbet2)
            var c4: [6]f64 = zero
            ga_c4f(g, eps, c4[..])
            let b41 = ga_sincosseries(false, ns1, nc1, c4[..], 6usize)
            let b42 = ga_sincosseries(false, ns2, nc2, c4[..], 6usize)
            s12area = a4 * (b42 - b41)
        }
        if !meridian && somg12 == 2.0f64 {
            somg12 = math.sin[f64](omg12)
            comg12 = math.cos[f64](omg12)
        }
        if !meridian && comg12 > 0.0f64 - 0.7071f64 && sbet2 - sbet1 < 1.75f64 {
            let domg12 = 1.0f64 + comg12
            let dbet1 = 1.0f64 + cbet1
            let dbet2 = 1.0f64 + cbet2
            alp12 = 2.0f64 * math.atan2[f64](somg12 * (sbet1 * dbet2 + sbet2 * dbet1), domg12 * (sbet1 * sbet2 + dbet1 * dbet2))
        } else {
            var salp12 = salp2 * calp1 - calp2 * salp1
            var calp12 = calp2 * calp1 + salp2 * salp1
            if salp12 == 0.0f64 && calp12 < 0.0f64 {
                salp12 = tiny * calp1
                calp12 = 0.0f64 - 1.0f64
            }
            alp12 = math.atan2[f64](salp12, calp12)
        }
        s12area = s12area + g.c2 * alp12
        s12area = s12area * swapp * lonsign * latsign
        s12area = s12area + 0.0f64
    }
    o.area12 = s12area
    if swapp < 0.0f64 {
        let ts = salp1
        salp1 = salp2
        salp2 = ts
        let tc = calp1
        calp1 = calp2
        calp2 = tc
    }
    o.salp1 = salp1 * swapp * lonsign
    o.calp1 = calp1 * swapp * latsign
    o.salp2 = salp2 * swapp * lonsign
    o.calp2 = calp2 * swapp * latsign
}

// the direct problem for a distance: fills o.lat2, o.lon2 and o.azi2
fn ga_direct(g: *const Geod, lat1in: f64, lon1: f64, azi1in: f64, s12: f64, o: *Sol) {
    let tiny = g.tiny
    let azi1 = ga_angnormalize(azi1in)
    let (salp1, calp1) = ga_sincosd(ga_round(azi1))
    let lat1 = ga_latfix(lat1in)
    let (sb1, cb1) = ga_sincosd(ga_round(lat1))
    let (nsb1, ncb1) = ga_norm(sb1 * g.f1, cb1)
    let sbet1 = nsb1
    let cbet1 = ga_fmax(tiny, ncb1)
    let salp0 = salp1 * cbet1
    let calp0 = ga_hypot(calp1, salp1 * sbet1)
    let somg1 = salp0 * sbet1
    var csig1 = 1.0f64
    if sbet1 != 0.0f64 || calp1 != 0.0f64 { csig1 = cbet1 * calp1 }
    let comg1 = csig1
    let (ssig1, ncsig1) = ga_norm(sbet1, csig1)
    csig1 = ncsig1
    let k2 = calp0 * calp0 * g.ep2
    let eps = k2 / (2.0f64 * (1.0f64 + math.sqrt[f64](1.0f64 + k2)) + k2)
    var c1a: [7]f64 = zero
    var c1pa: [7]f64 = zero
    var c3a: [6]f64 = zero
    let a1m1 = ga_a1m1f(eps)
    ga_c1f(eps, c1a[..])
    let b11 = ga_sincosseries(true, ssig1, csig1, c1a[..], 6usize)
    let sb11 = math.sin[f64](b11)
    let cb11 = math.cos[f64](b11)
    let stau1 = ssig1 * cb11 + csig1 * sb11
    let ctau1 = csig1 * cb11 - ssig1 * sb11
    ga_c1pf(eps, c1pa[..])
    ga_c3f(g, eps, c3a[..])
    let a3c = (0.0f64 - g.f) * salp0 * ga_a3f(g, eps)
    let b31 = ga_sincosseries(true, ssig1, csig1, c3a[..], 5usize)
    let tau12 = s12 / (g.b * (1.0f64 + a1m1))
    let st = math.sin[f64](tau12)
    let ct = math.cos[f64](tau12)
    var b12 = 0.0f64 - ga_sincosseries(true, stau1 * ct + ctau1 * st, ctau1 * ct - stau1 * st, c1pa[..], 6usize)
    var sig12 = tau12 - (b12 - b11)
    var ssig12 = math.sin[f64](sig12)
    var csig12 = math.cos[f64](sig12)
    if ga_abs(g.f) > 0.01f64 {
        let ssig2a = ssig1 * csig12 + csig1 * ssig12
        let csig2a = csig1 * csig12 - ssig1 * ssig12
        b12 = ga_sincosseries(true, ssig2a, csig2a, c1a[..], 6usize)
        let serr = (1.0f64 + a1m1) * (sig12 + (b12 - b11)) - s12 / g.b
        sig12 = sig12 - serr / math.sqrt[f64](1.0f64 + k2 * ssig2a * ssig2a)
        ssig12 = math.sin[f64](sig12)
        csig12 = math.cos[f64](sig12)
    }
    let ssig2 = ssig1 * csig12 + csig1 * ssig12
    var csig2 = csig1 * csig12 - ssig1 * ssig12
    let sbet2 = calp0 * ssig2
    var cbet2 = ga_hypot(salp0, calp0 * csig2)
    if cbet2 == 0.0f64 {
        cbet2 = tiny
        csig2 = tiny
    }
    let salp2 = salp0
    let calp2 = calp0 * csig2
    let somg2 = salp0 * ssig2
    let comg2 = csig2
    let omg12 = math.atan2[f64](somg2 * comg1 - comg2 * somg1, comg2 * comg1 + somg2 * somg1)
    let lam12 = omg12 + a3c * (sig12 + (ga_sincosseries(true, ssig2, csig2, c3a[..], 5usize) - b31))
    let lon12 = lam12 / ga_degree()
    o.lon2 = ga_angnormalize(ga_angnormalize(lon1) + ga_angnormalize(lon12))
    o.lat2 = ga_atan2d(sbet2, g.f1 * cbet2)
    o.azi2 = ga_atan2d(salp2, calp2)
}

// distGeo for one pair of points
fn dist_geo(lon1: f64, lat1: f64, lon2: f64, lat2: f64, a: f64, f: f64) -> f64 {
    var g: Geod = zero
    ga_init(&g, a, f)
    var o: Sol = zero
    ga_inverse(&g, lat1, lon1, lat2, lon2, false, &o)
    ret o.s12
}

// bearing(p1, p2) on the ellipsoid: the initial azimuth, degrees in (-180, 180]
fn bearing_geo(lon1: f64, lat1: f64, lon2: f64, lat2: f64, a: f64, f: f64) -> f64 {
    var g: Geod = zero
    ga_init(&g, a, f)
    var o: Sol = zero
    ga_inverse(&g, lat1, lon1, lat2, lon2, false, &o)
    ret ga_atan2d(o.salp1, o.calp1)
}

// finalBearing(p1, p2): the azimuth on arrival
fn final_bearing_geo(lon1: f64, lat1: f64, lon2: f64, lat2: f64, a: f64, f: f64) -> f64 {
    var g: Geod = zero
    ga_init(&g, a, f)
    var o: Sol = zero
    ga_inverse(&g, lat1, lon1, lat2, lon2, false, &o)
    ret ga_atan2d(o.salp2, o.calp2)
}

// destPoint(p, b, d): (lon, lat) reached from (lon1, lat1) along bearing b degrees for d metres
fn dest_point_geo(lon1: f64, lat1: f64, b: f64, d: f64, a: f64, f: f64) -> (f64, f64) {
    var g: Geod = zero
    ga_init(&g, a, f)
    var o: Sol = zero
    ga_direct(&g, lat1, lon1, b, d, &o)
    ret (o.lon2, o.lat2)
}

// midPoint(p1, p2): the point half way along the geodesic
fn mid_point_geo(lon1: f64, lat1: f64, lon2: f64, lat2: f64, a: f64, f: f64) -> (f64, f64) {
    var g: Geod = zero
    ga_init(&g, a, f)
    var o: Sol = zero
    ga_inverse(&g, lat1, lon1, lat2, lon2, false, &o)
    let azi1 = ga_atan2d(o.salp1, o.calp1)
    let half = o.s12 / 2.0f64
    ga_direct(&g, lat1, lon1, azi1, half, &o)
    ret (o.lon2, o.lat2)
}

fn acc_add(c: *Acc, y0: f64) {
    let (y, u) = ga_sum(y0, c.t)
    let (s, t) = ga_sum(y, c.s)
    c.s = s
    c.t = t
    if c.s == 0.0f64 {
        c.s = u
    } else {
        c.t = c.t + u
    }
}

fn ga_transit(lon1: f64, lon2: f64) -> i64 {
    let (lon12, e) = ga_angdiff(lon1, lon2)
    let l1 = ga_angnormalize(lon1)
    let l2 = ga_angnormalize(lon2)
    if lon12 > 0.0f64 && ((l1 < 0.0f64 && l2 >= 0.0f64) || (l1 > 0.0f64 && l2 == 0.0f64)) { ret 1i64 }
    if lon12 < 0.0f64 && l1 >= 0.0f64 && l2 < 0.0f64 { ret 0i64 - 1i64 }
    ret 0i64
}

// PolygonArea(geod).Compute(false, true): the signed area (counterclockwise positive) and the perimeter of the ring closed by an edge back to the first vertex
fn polygon_compute(lon: []const f64, lat: []const f64, a: f64, f: f64) -> (f64, f64) {
    let n = lon.len
    if n < 2usize { ret (0.0f64, 0.0f64) }
    var g: Geod = zero
    ga_init(&g, a, f)
    let area0 = 4.0f64 * ga_pi() * g.c2
    var o: Sol = zero
    var asum: Acc = zero
    var psum: Acc = zero
    var crossings = 0i64
    var i = 1usize
    while i < n {
        ga_inverse(&g, lat[i - 1usize], lon[i - 1usize], lat[i], lon[i], true, &o)
        acc_add(&psum, o.s12)
        acc_add(&asum, o.area12)
        crossings = crossings + ga_transit(lon[i - 1usize], lon[i])
        i = i + 1usize
    }
    ga_inverse(&g, lat[n - 1usize], lon[n - 1usize], lat[0usize], lon[0usize], true, &o)
    let (ps, pt) = ga_sum(o.s12, psum.s)
    var perim = ps
    // Accumulator::Sum(y): add y to a copy and read s
    var pc: Acc = zero
    pc.s = psum.s
    pc.t = psum.t
    acc_add(&pc, o.s12)
    perim = pc.s
    acc_add(&asum, o.area12)
    crossings = crossings + ga_transit(lon[n - 1usize], lon[0usize])
    asum.s = ga_remainder(asum.s, area0)
    acc_add(&asum, 0.0f64)
    if crossings % 2i64 != 0i64 {
        if asum.s < 0.0f64 {
            acc_add(&asum, area0 / 2.0f64)
        } else {
            acc_add(&asum, 0.0f64 - area0 / 2.0f64)
        }
    }
    asum.s = 0.0f64 - asum.s
    asum.t = 0.0f64 - asum.t
    if asum.s > area0 / 2.0f64 {
        acc_add(&asum, 0.0f64 - area0)
    } else if asum.s <= 0.0f64 - area0 / 2.0f64 {
        acc_add(&asum, area0)
    }
    ret (0.0f64 + asum.s, perim)
}

// areaPolygon(x): the area in square metres on the ellipsoid
fn area_polygon(lon: []const f64, lat: []const f64, a: f64, f: f64) -> f64 {
    let (ar, pe) = polygon_compute(lon, lat, a, f)
    ret ga_abs(ar)
}

// the geodesic length of the polyline through the vertices, which is what perimeter(x) means to compute
fn perimeter_geodesic(lon: []const f64, lat: []const f64, a: f64, f: f64) -> f64 {
    var g: Geod = zero
    ga_init(&g, a, f)
    var o: Sol = zero
    var total = 0.0f64
    var i = 1usize
    while i < lon.len {
        ga_inverse(&g, lat[i - 1usize], lon[i - 1usize], lat[i], lon[i], false, &o)
        total = total + o.s12
        i = i + 1usize
    }
    ret total
}

// what perimeter(matrix) returns in geosphere 1.6-8: the sum of the absolute coordinates (the distances it computes are dropped)
fn perimeter_matrix(lon: []const f64, lat: []const f64) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < lon.len {
        total = total + ga_abs(lon[i]) + ga_abs(lat[i])
        i = i + 1usize
    }
    ret total
}

fn ga_fmod(x: f64, m: f64) -> f64 { ret x - m * math.floor[f64](x / m) }

// R's all.equal on the first and last vertex
fn ga_closed(lon: []const f64, lat: []const f64) -> bool {
    let n = lon.len
    let dx = ga_abs(lon[0usize] - lon[n - 1usize])
    let dy = ga_abs(lat[0usize] - lat[n - 1usize])
    let xy = (dx + dy) / 2.0f64
    let xn = (ga_abs(lon[0usize]) + ga_abs(lat[0usize])) / 2.0f64
    if xn > 1.5e-8f64 { ret xy / xn < 1.5e-8f64 }
    ret xy < 1.5e-8f64
}

// centroid(x): the centre of a polygon (a ring, closed or not) computed in Mercator coordinates; (lon, lat) in degrees
fn centroid(lon: []const f64, lat: []const f64) -> (f64, f64) {
    let n0 = lon.len
    let tor = ga_pi() / 180.0f64
    var closed = ga_closed(lon, lat)
    var n = n0
    if !closed { n = n0 + 1usize }
    var lo = lon[0usize]
    var hi = lon[0usize]
    var i = 0usize
    while i < n0 {
        if lon[i] < lo { lo = lon[i] }
        if lon[i] > hi { hi = lon[i] }
        i = i + 1usize
    }
    let dif1 = hi - lo
    var rotated = false
    if dif1 > 180.0f64 {
        var lo2 = ga_fmod(lon[0usize], 360.0f64) - 180.0f64
        var hi2 = lo2
        i = 0usize
        while i < n0 {
            let v = ga_fmod(lon[i], 360.0f64) - 180.0f64
            if v < lo2 { lo2 = v }
            if v > hi2 { hi2 = v }
            i = i + 1usize
        }
        if hi2 - lo2 < dif1 { rotated = true }
    }
    var sp = 0.0f64
    var cx = 0.0f64
    var cy = 0.0f64
    i = 0usize
    while i < n {
        var j = i
        if j >= n0 { j = 0usize }
        var k = i + 1usize
        if k >= n { k = 0usize }
        if k >= n0 { k = 0usize }
        var x1 = lon[j]
        var x2 = lon[k]
        if rotated {
            x1 = ga_fmod(x1, 360.0f64) - 180.0f64
            x2 = ga_fmod(x2, 360.0f64) - 180.0f64
        }
        let y1r = lat[j] * tor
        let y2r = lat[k] * tor
        let px1 = x1 * tor
        let px2 = x2 * tor
        let py1 = math.log[f64](math.tan[f64](y1r) + 1.0f64 / math.cos[f64](y1r))
        let py2 = math.log[f64](math.tan[f64](y2r) + 1.0f64 / math.cos[f64](y2r))
        let pp = px1 * py2 - px2 * py1
        sp = sp + pp
        cx = cx + (px1 + px2) * pp
        cy = cy + (py1 + py2) * pp
        i = i + 1usize
    }
    let area6 = 6.0f64 * sp / 2.0f64
    let mx = cx / area6
    let my = cy / area6
    let latd = (ga_pi() / 2.0f64 - 2.0f64 * math.atan[f64](math.exp[f64](0.0f64 - my))) / tor
    var lond = mx / tor
    if rotated {
        lond = lond + 180.0f64
        lond = ga_fmod(lond + 180.0f64, 360.0f64) - 180.0f64
    }
    ret (lond, latd)
}


// bearing(p1, p2, sphere = TRUE) style initial bearing on a sphere in degrees in (-180, 180]; NaN for identical points
fn bearing_sphere(lon1: f64, lat1: f64, lon2: f64, lat2: f64) -> f64 {
    if lon1 == lon2 && lat1 == lat2 { ret ga_nan() }
    let tor = ga_pi() / 180.0f64
    let dlon = lon2 * tor - lon1 * tor
    let y = math.sin[f64](dlon) * math.cos[f64](lat2 * tor)
    let x = math.cos[f64](lat1 * tor) * math.sin[f64](lat2 * tor) - math.sin[f64](lat1 * tor) * math.cos[f64](lat2 * tor) * math.cos[f64](dlon)
    var azm = math.atan2[f64](y, x) / tor
    azm = ga_fmod(azm + 360.0f64, 360.0f64)
    if azm > 180.0f64 { azm = 0.0f64 - (360.0f64 - azm) }
    ret azm
}

// antipode(p): (lon, lat)
fn antipode(lon: f64, lat: f64) -> (f64, f64) {
    ret (ga_fmod(lon + 180.0f64 + 180.0f64, 360.0f64) - 180.0f64, 0.0f64 - lat)
}

// mercator(p, r = r): (x, y)
fn mercator(lon: f64, lat: f64, r: f64) -> (f64, f64) {
    let tor = ga_pi() / 180.0f64
    let la = lat * tor
    ret (lon * tor * r, math.log[f64](math.tan[f64](la) + 1.0f64 / math.cos[f64](la)) * r)
}

// mercator(p, inverse = TRUE, r = r): (lon, lat)
fn mercator_inverse(x: f64, y: f64, r: f64) -> (f64, f64) {
    let tor = ga_pi() / 180.0f64
    let la = ga_pi() / 2.0f64 - 2.0f64 * math.atan[f64](math.exp[f64](0.0f64 - y / r))
    ret ((x / r) / tor, la / tor)
}

fn ga_cosine1(lon1: f64, lat1: f64, lon2: f64, lat2: f64) -> f64 {
    if ga_abs(lon1 - lon2) < 1.4901161193847656e-8f64 && ga_abs(lat1 - lat2) < 1.4901161193847656e-8f64 { ret 0.0f64 }
    let tor = ga_pi() / 180.0f64
    ret math.acos[f64](math.sin[f64](lat1 * tor) * math.sin[f64](lat2 * tor) + math.cos[f64](lat1 * tor) * math.cos[f64](lat2 * tor) * math.cos[f64](lon1 * tor - lon2 * tor))
}

// alongTrackDistance(p1, p2, p3, r): the bearings are the ellipsoidal ones of the package defaults
fn along_track_distance(lon1: f64, lat1: f64, lon2: f64, lat2: f64, lon3: f64, lat3: f64, r: f64) -> f64 {
    let tor = ga_pi() / 180.0f64
    let wa = 6378137.0f64
    let wf = 1.0f64 / 298.257223563f64
    let tc = bearing_geo(lon1, lat1, lon2, lat2, wa, wf) * tor
    let tcp = bearing_geo(lon1, lat1, lon3, lat3, wa, wf) * tor
    let dp = ga_cosine1(lon1, lat1, lon3, lat3)
    let xtr = math.asin[f64](math.sin[f64](tcp - tc) * math.sin[f64](dp))
    var sgn = 0.0f64
    let cc = math.cos[f64](tc - tcp)
    if cc > 0.0f64 { sgn = 1.0f64 }
    if cc < 0.0f64 { sgn = 0.0f64 - 1.0f64 }
    var angle = math.cos[f64](dp) / math.cos[f64](xtr)
    if angle > 1.0f64 { angle = 1.0f64 }
    if angle < 0.0f64 - 1.0f64 { angle = 0.0f64 - 1.0f64 }
    ret ga_abs(sgn * math.acos[f64](angle) * r)
}

// dist2gc(p1, p2, p3, r, sign): cross-track distance of p3 from the great circle p1 p2
fn dist2gc(lon1: f64, lat1: f64, lon2: f64, lat2: f64, lon3: f64, lat3: f64, r: f64, signed: bool) -> f64 {
    let tor = ga_pi() / 180.0f64
    let tc = bearing_geo(lon1, lat1, lon2, lat2, r, 0.0f64) * tor
    let tcp = bearing_geo(lon1, lat1, lon3, lat3, r, 0.0f64) * tor
    let dp = ga_cosine1(lon1, lat1, lon3, lat3)
    let xtr = math.asin[f64](math.sin[f64](tcp - tc) * math.sin[f64](dp)) * r
    if signed { ret xtr }
    ret ga_abs(xtr)
}

// onGreatCircle(p1, p2, p3, tol)
fn on_great_circle(lon1: f64, lat1: f64, lon2: f64, lat2: f64, lon3: f64, lat3: f64, tol: f64) -> bool {
    let tor = ga_pi() / 180.0f64
    let l1 = lon1 * tor
    let a1 = lat1 * tor
    let l2 = lon2 * tor
    let a2 = lat2 * tor
    let l3 = lon3 * tor
    let a3 = lat3 * tor
    if l1 == l2 && l1 == l3 { ret true }
    let newlat = math.atan[f64]((math.sin[f64](a1) * math.cos[f64](a2) * math.sin[f64](l3 - l2) - math.sin[f64](a2) * math.cos[f64](a1) * math.sin[f64](l3 - l1)) / (math.cos[f64](a1) * math.cos[f64](a2) * math.sin[f64](l1 - l2)))
    ret ga_abs(newlat - a3) < tol
}

fn ga_t_c1() -> [18]f64 {
    ret [18]f64{ -1.0f64, 6.0f64, -16.0f64, 32.0f64, -9.0f64, 64.0f64, -128.0f64, 2048.0f64, 9.0f64, -16.0f64, 768.0f64, 3.0f64, -5.0f64, 512.0f64, -7.0f64, 1280.0f64, -7.0f64, 2048.0f64 }
}

fn ga_t_c1p() -> [18]f64 {
    ret [18]f64{ 205.0f64, -432.0f64, 768.0f64, 1536.0f64, 4005.0f64, -4736.0f64, 3840.0f64, 12288.0f64, -225.0f64, 116.0f64, 384.0f64, -7173.0f64, 2695.0f64, 7680.0f64, 3467.0f64, 7680.0f64, 38081.0f64, 61440.0f64 }
}

fn ga_t_c2() -> [18]f64 {
    ret [18]f64{ 1.0f64, 2.0f64, 16.0f64, 32.0f64, 35.0f64, 64.0f64, 384.0f64, 2048.0f64, 15.0f64, 80.0f64, 768.0f64, 7.0f64, 35.0f64, 512.0f64, 63.0f64, 1280.0f64, 77.0f64, 2048.0f64 }
}

fn ga_t_a3() -> [18]f64 {
    ret [18]f64{ -3.0f64, 128.0f64, -2.0f64, -3.0f64, 64.0f64, -1.0f64, -3.0f64, -1.0f64, 16.0f64, 3.0f64, -1.0f64, -2.0f64, 8.0f64, 1.0f64, -1.0f64, 2.0f64, 1.0f64, 1.0f64 }
}

fn ga_t_c3() -> [45]f64 {
    ret [45]f64{ 3.0f64, 128.0f64, 2.0f64, 5.0f64, 128.0f64, -1.0f64, 3.0f64, 3.0f64, 64.0f64, -1.0f64, 0.0f64, 1.0f64, 8.0f64, -1.0f64, 1.0f64, 4.0f64, 5.0f64, 256.0f64, 1.0f64, 3.0f64, 128.0f64, -3.0f64, -2.0f64, 3.0f64, 64.0f64, 1.0f64, -3.0f64, 2.0f64, 32.0f64, 7.0f64, 512.0f64, -10.0f64, 9.0f64, 384.0f64, 5.0f64, -9.0f64, 5.0f64, 192.0f64, 7.0f64, 512.0f64, -14.0f64, 7.0f64, 512.0f64, 21.0f64, 2560.0f64 }
}

fn ga_t_c4() -> [77]f64 {
    ret [77]f64{ 97.0f64, 15015.0f64, 1088.0f64, 156.0f64, 45045.0f64, -224.0f64, -4784.0f64, 1573.0f64, 45045.0f64, -10656.0f64, 14144.0f64, -4576.0f64, -858.0f64, 45045.0f64, 64.0f64, 624.0f64, -4576.0f64, 6864.0f64, -3003.0f64, 15015.0f64, 100.0f64, 208.0f64, 572.0f64, 3432.0f64, -12012.0f64, 30030.0f64, 45045.0f64, 1.0f64, 9009.0f64, -2944.0f64, 468.0f64, 135135.0f64, 5792.0f64, 1040.0f64, -1287.0f64, 135135.0f64, 5952.0f64, -11648.0f64, 9152.0f64, -2574.0f64, 135135.0f64, -64.0f64, -624.0f64, 4576.0f64, -6864.0f64, 3003.0f64, 135135.0f64, 8.0f64, 10725.0f64, 1856.0f64, -936.0f64, 225225.0f64, -8448.0f64, 4992.0f64, -1144.0f64, 225225.0f64, -1440.0f64, 4160.0f64, -4576.0f64, 1716.0f64, 225225.0f64, -136.0f64, 63063.0f64, 1024.0f64, -208.0f64, 105105.0f64, 3584.0f64, -3328.0f64, 1144.0f64, 315315.0f64, -128.0f64, 135135.0f64, -2560.0f64, 832.0f64, 405405.0f64, 128.0f64, 99099.0f64 }
}
