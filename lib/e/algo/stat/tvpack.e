// R mvtnorm's TVPACK trivariate (`tvtlr` of tvpack.f, Genz): P(X1 < h1, X2 < h2, X3 < h3) for a normal (nu < 1) or a
// central t by Plackett's formula with adaptive Gauss-Kronrod integration from (0,0,1) to (0,0,r23) to R. The univariate
// and bivariate pieces are mvt.e's (R's pt is the closed forms there). Fortran's 1-based arrays are kept in `adonet`.

use e.algo.stat.mvt as mvt
use e.math

type Ctx = struct { nu: i64, h1: f64, h2: f64, h3: f64, r23: f64, rua: f64, rub: f64, ar: f64, ruc: f64 }

// BVTL of tvpack.f: the bivariate lower tail with the special cases
fn bvtl(nu: i64, dh: f64, dk: f64, r: f64) -> f64 {
    if nu <= 0i64 { ret mvt.mvbvu(0.0f64 - dh, 0.0f64 - dk, r) }
    if 1.0f64 - r <= 1.0e-15f64 {
        var m = dh
        if dk < dh { m = dk }
        ret mvt.mvstdt(nu, m)
    }
    if r + 1.0f64 <= 1.0e-15f64 {
        if dh > 0.0f64 - dk { ret mvt.mvstdt(nu, dh) - mvt.mvstdt(nu, 0.0f64 - dk) }
        ret 0.0f64
    }
    ret mvt.mvbvtl(nu, dh, dk, r)
}

// sin(x) and cos(x)^2, by series near pi/2
fn sincs(x: f64) -> (f64, f64) {
    let pt = 1.57079632679489661923132169163975f64
    var ax = x
    if ax < 0.0f64 { ax = 0.0f64 - ax }
    let ee = (pt - ax) * (pt - ax)
    if ee < 5.0e-5f64 {
        var sx = 1.0f64 - ee * (1.0f64 - ee / 12.0f64) / 2.0f64
        if x < 0.0f64 { sx = 0.0f64 - sx }
        ret (sx, ee * (1.0f64 - ee * (1.0f64 - 2.0f64 * ee / 15.0f64) / 3.0f64))
    }
    let sx = math.sin[f64](x)
    ret (sx, 1.0f64 - sx * sx)
}

// Plackett's integrand piece
fn pntgnd(nu: i64, ba: f64, bb: f64, bc: f64, ra: f64, rb: f64, r: f64, rr: f64) -> f64 {
    let d = ra - rb
    let dt = rr * (rr - d * d - 2.0f64 * ra * rb * (1.0f64 - r))
    if dt > 0.0f64 {
        let bt = (bc * rr + ba * (r * rb - ra) + bb * (r * ra - rb)) / math.sqrt[f64](dt)
        let e = ba - r * bb
        var ft = e * e / rr + bb * bb
        if nu < 1i64 {
            if bt > 0.0f64 - 10.0f64 && ft < 100.0f64 {
                var v = math.exp[f64](0.0f64 - ft / 2.0f64)
                if bt < 10.0f64 { v = v * mvt.mvphi(bt) }
                ret v
            }
            ret 0.0f64
        }
        ft = math.sqrt[f64](1.0f64 + ft / f64(nu))
        var p = 1.0f64
        var i = 0i64
        while i < nu {
            p = p * ft
            i += 1i64
        }
        ret mvt.mvstdt(nu, bt / ft) / p
    }
    ret 0.0f64
}

fn tvtmfn(c: *const Ctx, x: f64) -> f64 {
    var v = 0.0f64
    let (r12, rr2) = sincs(c.rua * x)
    let (r13, rr3) = sincs(c.rub * x)
    if math.abs[f64](c.rua) > 0.0f64 { v = v + c.rua * pntgnd(c.nu, c.h1, c.h2, c.h3, r13, c.r23, r12, rr2) }
    if math.abs[f64](c.rub) > 0.0f64 { v = v + c.rub * pntgnd(c.nu, c.h1, c.h3, c.h2, r12, c.r23, r13, rr3) }
    if c.nu > 0i64 {
        let (r, rr) = sincs(c.ar + c.ruc * x)
        v = v - c.ruc * pntgnd(c.nu, c.h2, c.h3, c.h1, 0.0f64, 0.0f64, r, rr)
    }
    ret v
}

// the 23-point Gauss-Kronrod rule on (a, b): the integral and its error estimate
fn krnrdt(c: *const Ctx, a: f64, b: f64) -> (f64, f64) {
    var wg: [6]f64 = zero
    var xgk: [12]f64 = zero
    var wgk: [12]f64 = zero
    wg[0usize] = 0.2729250867779007f64
    wg[1usize] = 0.5566856711617449e-01f64
    wg[2usize] = 0.1255803694649048f64
    wg[3usize] = 0.1862902109277352f64
    wg[4usize] = 0.2331937645919914f64
    wg[5usize] = 0.2628045445102478f64
    xgk[1usize] = 0.9963696138895427f64
    xgk[2usize] = 0.9782286581460570f64
    xgk[3usize] = 0.9416771085780681f64
    xgk[4usize] = 0.8870625997680953f64
    xgk[5usize] = 0.8160574566562211f64
    xgk[6usize] = 0.7301520055740492f64
    xgk[7usize] = 0.6305995201619651f64
    xgk[8usize] = 0.5190961292068118f64
    xgk[9usize] = 0.3979441409523776f64
    xgk[10usize] = 0.2695431559523450f64
    xgk[11usize] = 0.1361130007993617f64
    wgk[0usize] = 0.1365777947111183f64
    wgk[1usize] = 0.9765441045961290e-02f64
    wgk[2usize] = 0.2715655468210443e-01f64
    wgk[3usize] = 0.4582937856442671e-01f64
    wgk[4usize] = 0.6309742475037484e-01f64
    wgk[5usize] = 0.7866457193222764e-01f64
    wgk[6usize] = 0.9295309859690074e-01f64
    wgk[7usize] = 0.1058720744813894f64
    wgk[8usize] = 0.1167395024610472f64
    wgk[9usize] = 0.1251587991003195f64
    wgk[10usize] = 0.1312806842298057f64
    wgk[11usize] = 0.1351935727998845f64
    let wid = (b - a) / 2.0f64
    let cen = (b + a) / 2.0f64
    var fc = tvtmfn(c, cen)
    var resg = fc * wg[0usize]
    var resk = fc * wgk[0usize]
    var j = 1usize
    while j <= 11usize {
        let t = wid * xgk[j]
        fc = tvtmfn(c, cen - t) + tvtmfn(c, cen + t)
        resk = resk + wgk[j] * fc
        if j % 2usize == 0usize { resg = resg + wg[j / 2usize] * fc }
        j += 1usize
    }
    let d = wid * (resk - resg)
    var e = d
    if d < 0.0f64 { e = 0.0f64 - d }
    ret (wid * resk, e)
}

// one-dimensional globally adaptive integration of tvtmfn over (a, b)
fn adonet(c: *const Ctx, a: f64, b: f64, tol: f64) -> f64 {
    var ei: [101]f64 = zero
    var ai: [101]f64 = zero
    var bi: [101]f64 = zero
    var fi: [101]f64 = zero
    var fin = 0.0f64
    var esum = 1.0f64
    var ip = 1usize
    var im = 1usize
    ai[1usize] = a
    bi[1usize] = b
    while 4.0f64 * esum > tol && im < 100usize {
        im += 1usize
        bi[im] = bi[ip]
        ai[im] = (ai[ip] + bi[ip]) / 2.0f64
        bi[ip] = ai[im]
        let (f1, e1) = krnrdt(c, ai[ip], bi[ip])
        fi[ip] = f1
        ei[ip] = e1
        let (f2, e2) = krnrdt(c, ai[im], bi[im])
        fi[im] = f2
        ei[im] = e2
        esum = 0.0f64
        fin = 0.0f64
        var i = 1usize
        while i <= im {
            if ei[i] > ei[ip] { ip = i }
            fin = fin + fi[i]
            esum = esum + ei[i] * ei[i]
            i += 1usize
        }
        esum = math.sqrt[f64](esum)
    }
    ret fin
}

// tvtlr(nu, h, r, eps): `h` the upper limits, `r` = (r21, r31, r32)
fn tvtl(nu: i64, h: []const f64, r: []const f64, epsi: f64) -> f64 {
    let pt = 1.57079632679489661923132169163975f64
    var eps = epsi
    if eps < 1.0e-14f64 { eps = 1.0e-14f64 }
    var c: Ctx = zero
    c.nu = nu
    var h1 = h[0usize]
    var h2 = h[1usize]
    var h3 = h[2usize]
    var r12 = r[0usize]
    var r13 = r[1usize]
    var r23 = r[2usize]
    if math.abs[f64](r12) > math.abs[f64](r13) {
        h2 = h[2usize]
        h3 = h[1usize]
        r12 = r[1usize]
        r13 = r[0usize]
    }
    if math.abs[f64](r13) > math.abs[f64](r23) {
        h1 = h2
        h2 = h[0usize]
        r23 = r13
        r13 = r[2usize]
    }
    var tvt = 0.0f64
    if math.abs[f64](h1) + math.abs[f64](h2) + math.abs[f64](h3) < eps {
        tvt = (1.0f64 + (math.asin[f64](r12) + math.asin[f64](r13) + math.asin[f64](r23)) / pt) / 8.0f64
    } else if nu < 1i64 && math.abs[f64](r12) + math.abs[f64](r13) < eps {
        tvt = mvt.mvphi(h1) * bvtl(nu, h2, h3, r23)
    } else if nu < 1i64 && math.abs[f64](r13) + math.abs[f64](r23) < eps {
        tvt = mvt.mvphi(h3) * bvtl(nu, h1, h2, r12)
    } else if nu < 1i64 && math.abs[f64](r12) + math.abs[f64](r23) < eps {
        tvt = mvt.mvphi(h2) * bvtl(nu, h1, h3, r13)
    } else if 1.0f64 - r23 < eps {
        var m = h2
        if h3 < h2 { m = h3 }
        tvt = bvtl(nu, h1, m, r12)
    } else if r23 + 1.0f64 < eps {
        if h2 > 0.0f64 - h3 { tvt = bvtl(nu, h1, h2, r12) - bvtl(nu, h1, 0.0f64 - h3, r12) }
    } else {
        if nu < 1i64 {
            tvt = bvtl(nu, h2, h3, r23) * mvt.mvphi(h1)
        } else if r23 >= 0.0f64 {
            var m = h2
            if h3 < h2 { m = h3 }
            tvt = bvtl(nu, h1, m, 0.0f64)
        } else if h2 > 0.0f64 - h3 {
            tvt = bvtl(nu, h1, h2, 0.0f64) - bvtl(nu, h1, 0.0f64 - h3, 0.0f64)
        }
        c.h1 = h1
        c.h2 = h2
        c.h3 = h3
        c.r23 = r23
        c.rua = math.asin[f64](r12)
        c.rub = math.asin[f64](r13)
        c.ar = math.asin[f64](r23)
        c.ruc = pt - c.ar
        if c.ar < 0.0f64 { c.ruc = 0.0f64 - pt - c.ar }
        tvt = tvt + adonet(&c, 0.0f64, 1.0f64, eps) / (4.0f64 * pt)
    }
    if tvt < 0.0f64 { tvt = 0.0f64 }
    if tvt > 1.0f64 { tvt = 1.0f64 }
    ret tvt
}
