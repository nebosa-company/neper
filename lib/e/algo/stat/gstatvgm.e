// R gstat, the variogram model catalogue and the sample variograms of its C code (vario_fn.c, vario.c, direct.c, sem.c): every one-parameter and two-parameter
// family, nested structures with 2D anisotropy, directional and omnidirectional empirical variograms, variogram clouds, cross variograms and the pseudo cross
// variogram of data that do not share locations.
//
// A model is a flat array of six numbers per structure: type (the gstat code, 1 Nug, 2 Exp, 3 Sph, 4 Gau, 5 Exc, 6 Mat, 7 Ste, 8 Cir, 9 Lin, 10 Bes, 11 Pen,
// 12 Per, 13 Wav, 14 Hol, 15 Log, 16 Pow, 17 Spl, 19 Err, 20 Int), partial sill, range, kappa, anisotropy angle (degrees clockwise from north) and anisotropy ratio.
//
// Not here: 3D anisotropy, the Legendre model, covariance tables, cross covariograms, variogram maps and grid data.

use e.algo.stat.carlmtest as ols
use e.algo.stat.gslfns as gs
use e.math
use e.math.nmath as nm
use e.mem

fn gpi() -> f64 { ret 3.14159265359f64 }

// the unit semivariance fnct(h, range, kappa) of one structure; the model codes are gstat's
fn unit_gamma(t: usize, h: f64, r: f64, kappa: f64) -> f64 {
    if t == 1usize || t == 19usize {
        if h == 0.0f64 { ret 0.0f64 }
        ret 1.0f64
    }
    if t == 20usize { ret 1.0f64 }
    if t == 9usize {
        if h == 0.0f64 { ret 0.0f64 }
        if r == 0.0f64 { ret h }
        if h >= r { ret 1.0f64 }
        ret h / r
    }
    if t == 3usize {
        if h == 0.0f64 { ret 0.0f64 }
        if h >= r { ret 1.0f64 }
        let hr = h / r
        ret hr * (1.5f64 - 0.5f64 * hr * hr)
    }
    if t == 2usize {
        if h == 0.0f64 { ret 0.0f64 }
        ret 1.0f64 - math.exp[f64](0.0f64 - h / r)
    }
    if t == 4usize {
        if h == 0.0f64 { ret 0.0f64 }
        let hr = h / r
        ret 1.0f64 - math.exp[f64](0.0f64 - hr * hr)
    }
    if t == 5usize {
        if h == 0.0f64 { ret 0.0f64 }
        ret 1.0f64 - math.exp[f64](0.0f64 - math.pow[f64](h / r, kappa))
    }
    if t == 8usize {
        if h == 0.0f64 { ret 0.0f64 }
        if h >= r { ret 1.0f64 }
        let hr = h / r
        ret (2.0f64 / gpi()) * (hr * math.sqrt[f64](1.0f64 - hr * hr) + math.asin[f64](hr))
    }
    if t == 10usize {
        let hr = h / r
        if hr < 0.001f64 { ret 0.0f64 }
        ret 1.0f64 - hr * gs.bessel_knu(1.0f64, hr)
    }
    if t == 11usize {
        if h == 0.0f64 { ret 0.0f64 }
        if h >= r { ret 1.0f64 }
        let hr = h / r
        let h2 = hr * hr
        ret hr * ((15.0f64 / 8.0f64) + h2 * ((-5.0f64 / 4.0f64) + h2 * (3.0f64 / 8.0f64)))
    }
    if t == 12usize {
        if h == 0.0f64 { ret 0.0f64 }
        ret 1.0f64 - math.cos[f64](2.0f64 * gpi() * h / r)
    }
    if t == 13usize {
        if h == 0.0f64 { ret 0.0f64 }
        ret 1.0f64 - r * math.sin[f64](gpi() * h / r) / (gpi() * h)
    }
    if t == 14usize {
        if h == 0.0f64 { ret 0.0f64 }
        ret 1.0f64 - math.sin[f64](h / r) / (h / r)
    }
    if t == 15usize {
        if h == 0.0f64 { ret 0.0f64 }
        ret math.log[f64](h + r)
    }
    if t == 16usize {
        if h == 0.0f64 { ret 0.0f64 }
        ret math.pow[f64](h, r)
    }
    if t == 17usize {
        if h == 0.0f64 { ret 0.0f64 }
        ret h * h * math.log[f64](h)
    }
    if t == 6usize {
        if h == 0.0f64 { ret 0.0f64 }
        if h > 600.0f64 * r { ret 1.0f64 }
        let hr = h / r
        let ans = (math.pow[f64](2.0f64, 0.0f64 - (kappa - 1.0f64)) / nm.gammafn(kappa)) * math.pow[f64](hr, kappa) * gs.bessel_knu(kappa, hr)
        ret 1.0f64 - ans
    }
    // 7: Stein's parameterisation of the Matern model
    if h == 0.0f64 { ret 0.0f64 }
    let hh = h / r
    let bes = gs.bessel_knu(kappa, 2.0f64 * math.sqrt[f64](kappa) * hh)
    if bes != bes || bes > 1.0e300f64 { ret 0.0f64 }
    if bes == 0.0f64 { ret 1.0f64 }
    let mult = math.pow[f64](2.0f64, 1.0f64 - kappa) / nm.gammafn(kappa) * math.pow[f64](2.0f64 * math.sqrt[f64](kappa) * hh, kappa)
    if mult != mult || mult > 1.0e300f64 { ret 1.0f64 }
    ret 1.0f64 - bes * mult
}

// the transformed distance of the lag (dx, dy) under the structure's 2D anisotropy (angle clockwise from north, ratio minor:major)
fn aniso_norm(ang: f64, ratio: f64, dx: f64, dy: f64) -> f64 {
    if dx == 0.0f64 && dy == 0.0f64 { ret 0.0f64 }
    if ang == 0.0f64 && ratio == 1.0f64 { ret math.sqrt[f64](dx * dx + dy * dy) }
    var alpha = 0.0f64
    if ang < 270.0f64 { alpha = (90.0f64 - ang) * gpi() / 180.0f64 }
    if ang >= 270.0f64 { alpha = (450.0f64 - ang) * gpi() / 180.0f64 }
    var rt = ratio
    if rt < 1.0e-30f64 { rt = 1.0e-30f64 }
    let f1 = 1.0f64 / rt
    let sa = math.sin[f64](alpha)
    let ca = math.cos[f64](alpha)
    let u0 = ca * dx + sa * dy
    let u1 = f1 * (0.0f64 - sa * dx + ca * dy)
    ret math.sqrt[f64](u0 * u0 + u1 * u1)
}

// the semivariance of a nested model (nm structures, six numbers each) at the lag (dx, dy)
fn model_gamma(ms: []const f64, nst: usize, dx: f64, dy: f64) -> f64 {
    var s = 0.0f64
    var iso = true
    var maxr = 2.2250738585072014e-308f64
    var k = 0usize
    while k < nst {
        let b = 6usize * k
        let t = usize(ms[b])
        if ms[b + 5usize] != 1.0f64 { iso = false }
        let inf = t == 2usize || t == 4usize || t == 5usize || t == 6usize || t == 7usize || t == 10usize || t == 12usize || t == 13usize || t == 14usize || t == 15usize || t == 16usize || (t == 9usize && ms[b + 2usize] == 0.0f64)
        if ms[b + 2usize] > maxr { maxr = ms[b + 2usize] }
        if inf { maxr = 1.7976931348623157e308f64 }
        k += 1usize
    }
    if iso {
        let d = math.sqrt[f64](dx * dx + dy * dy)
        if d > maxr {
            k = 0usize
            while k < nst {
                s += ms[6usize * k + 1usize]
                k += 1usize
            }
            ret s
        }
    }
    k = 0usize
    while k < nst {
        let b = 6usize * k
        let h = aniso_norm(ms[b + 4usize], ms[b + 5usize], dx, dy)
        s += ms[b + 1usize] * unit_gamma(usize(ms[b]), h, ms[b + 2usize], ms[b + 3usize])
        k += 1usize
    }
    ret s
}

// the covariance sum(sill) - gamma of a nested model at the lag (gstat's get_covariance, each structure's sill times one minus its unit semivariance)
fn model_cov(ms: []const f64, nst: usize, dx: f64, dy: f64) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < nst {
        let b = 6usize * k
        let h = aniso_norm(ms[b + 4usize], ms[b + 5usize], dx, dy)
        s += ms[b + 1usize] * (1.0f64 - unit_gamma(usize(ms[b]), h, ms[b + 2usize], ms[b + 3usize]))
        k += 1usize
    }
    ret s
}

// gstat's direction filter on a lag: the distance, or -1 when the lag lies outside the tolerance section around alpha (degrees clockwise from north)
fn valid_direction(px: f64, py: f64, alpha: f64, tol: f64, symmetric: bool) -> f64 {
    let dist = math.sqrt[f64](px * px + py * py)
    if tol >= 90.0f64 { ret dist }
    if px != 0.0f64 || py != 0.0f64 {
        let a = alpha * gpi() / 180.0f64
        let ct = math.cos[f64](tol * gpi() / 180.0f64)
        let ip = (px * math.sin[f64](a) + py * math.cos[f64](a)) / dist
        if symmetric {
            if math.abs[f64](ip) < ct { ret 0.0f64 - 1.0f64 }
        }
        if !symmetric {
            if ip < ct { ret 0.0f64 - 1.0f64 }
        }
    }
    ret dist
}

fn bin_index(d: f64, width: f64, nest: usize, special: bool) -> usize {
    if d == 0.0f64 && special { ret nest - 1usize }
    let fr = d / width
    if d > 0.0f64 && fr == math.floor[f64](fr) { ret usize(fr) - 1usize }
    ret usize(math.floor[f64](fr))
}

// the number of estimates (bins plus the zero slot) of a binned variogram, or the capacity a cloud needs
fn ev_capacity(na: usize, nb: usize, cutoff: f64, width: f64, cloud: bool) -> usize {
    if cloud { ret na * nb + 1usize }
    ret usize(math.floor[f64](cutoff / width)) + 2usize
}

// the sample variogram. kind 3 is the direct semivariogram by Cressie's estimator, 4 the pairwise relative semivariogram, 5 the covariogram (zero-lag slot last, as for kind 2); kind 0 the direct semivariogram of (xa, za); 1 the cross variogram of two variables at the same locations xa; 2 the pseudo cross variogram of
// (xa, za) and (xb, zb) at different locations. Returns the number of estimates written to np, dist and gamma: in a cloud the pairs in loop order, otherwise every bin
// (empty ones with np = 0), and for kind 2 the zero-distance slot as the last bin.
fn emp_variogram(kind: usize, xa: []const f64, za: []const f64, na: usize, xb: []const f64, zb: []const f64, nb: usize, cutoff: f64, width: f64, alpha: f64, tol: f64, cloud: bool, onp: []f64, odist: []f64, ogam: []f64) -> usize {
    var nest = 0usize
    if !cloud {
        nest = usize(math.floor[f64](cutoff / width)) + 2usize
        var q = 0usize
        while q < nest {
            onp[q] = 0.0f64
            odist[q] = 0.0f64
            ogam[q] = 0.0f64
            q += 1usize
        }
    }
    let special = kind == 2usize || kind == 5usize
    var count = 0usize
    var i = 0usize
    while i < na {
        var j = 0usize
        var jend = nb
        if kind == 0usize || kind == 3usize || kind == 4usize { jend = i }
        if kind == 5usize { jend = i + 1usize }
        while j < jend {
            if kind == 1usize && i == j {
                j += 1usize
                continue
            }
            var px = 0.0f64
            var py = 0.0f64
            if kind == 0usize || kind == 1usize || kind >= 3usize {
                px = xa[2usize * i] - xa[2usize * j]
                py = xa[2usize * i + 1usize] - xa[2usize * j + 1usize]
            }
            if kind == 2usize {
                px = xa[2usize * i] - xb[2usize * j]
                py = xa[2usize * i + 1usize] - xb[2usize * j + 1usize]
            }
            let d = valid_direction(px, py, alpha, tol, kind != 2usize)
            if d >= 0.0f64 && d <= cutoff {
                var g = 0.0f64
                if kind == 0usize { g = (za[i] - za[j]) * (za[i] - za[j]) }
                if kind == 3usize { g = math.sqrt[f64](math.abs[f64](za[i] - za[j])) }
                if kind == 4usize {
                    let gm = 2.0f64 * (za[i] - za[j]) / (za[i] + za[j])
                    g = gm * gm
                }
                if kind == 5usize { g = za[i] * za[j] }
                if kind == 1usize { g = (za[i] - za[j]) * (zb[i] - zb[j]) }
                if kind == 2usize { g = (za[i] - zb[j]) * (za[i] - zb[j]) }
                if cloud {
                    onp[count] = 1.0f64
                    odist[count] = d
                    ogam[count] = g / 2.0f64
                    if kind == 5usize { ogam[count] = g }
                    count += 1usize
                }
                if !cloud {
                    let ix = bin_index(d, width, nest, special)
                    onp[ix] += 1.0f64
                    odist[ix] += d
                    ogam[ix] += g
                }
            }
            j += 1usize
        }
        i += 1usize
    }
    if cloud { ret count }
    var q = 0usize
    while q < nest {
        if onp[q] > 0.0f64 {
            odist[q] = odist[q] / onp[q]
            if kind == 3usize { ogam[q] = 0.5f64 * math.pow[f64](ogam[q] / onp[q], 4.0f64) / (0.457f64 + 0.494f64 / onp[q]) }
            if kind == 5usize { ogam[q] = ogam[q] / onp[q] }
            if kind != 3usize && kind != 5usize { ogam[q] = ogam[q] / (2.0f64 * onp[q]) }
        }
        q += 1usize
    }
    ret nest
}

// the default cutoff of variogram(): 0.33333 of the diagonal of the bounding box of the locations
fn default_cutoff(xa: []const f64, na: usize) -> f64 {
    var x0 = xa[0usize]
    var x1 = xa[0usize]
    var y0 = xa[1usize]
    var y1 = xa[1usize]
    var i = 1usize
    while i < na {
        if xa[2usize * i] < x0 { x0 = xa[2usize * i] }
        if xa[2usize * i] > x1 { x1 = xa[2usize * i] }
        if xa[2usize * i + 1usize] < y0 { y0 = xa[2usize * i + 1usize] }
        if xa[2usize * i + 1usize] > y1 { y1 = xa[2usize * i + 1usize] }
        i += 1usize
    }
    let d = math.sqrt[f64]((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
    if d == 0.0f64 { ret 1.0f64 }
    ret d * 0.33333f64
}

// the OLS residuals of z on the drift basis (1) for nd 1 or (1, x, y) for nd 3 at the locations xy: gstat's make_residuals_lm, applied to every variable before a sample variogram
fn trend_residuals(a: *mem.Arena, xy: []const f64, z: []const f64, n: usize, nd: usize, out: []f64) -> err {
    let (xtx, e1) = mem.alloc[f64](a, nd * nd)
    if e1 != ok { ret e1 }
    let (inv, e2) = mem.alloc[f64](a, nd * nd)
    if e2 != ok { ret e2 }
    let (xty, e3) = mem.alloc[f64](a, nd)
    if e3 != ok { ret e3 }
    var p = 0usize
    while p < nd * nd {
        xtx[p] = 0.0f64
        p += 1usize
    }
    p = 0usize
    while p < nd {
        xty[p] = 0.0f64
        p += 1usize
    }
    var i = 0usize
    while i < n {
        var r = 0usize
        while r < nd {
            var fr = 1.0f64
            if r == 1usize { fr = xy[2usize * i] }
            if r == 2usize { fr = xy[2usize * i + 1usize] }
            xty[r] += fr * z[i]
            var s = 0usize
            while s < nd {
                var fs = 1.0f64
                if s == 1usize { fs = xy[2usize * i] }
                if s == 2usize { fs = xy[2usize * i + 1usize] }
                xtx[r * nd + s] += fr * fs
                s += 1usize
            }
            r += 1usize
        }
        i += 1usize
    }
    if ols.inverse(a, xtx, nd, inv) != ok { ret e1 }
    i = 0usize
    while i < n {
        var fit = 0.0f64
        var r = 0usize
        while r < nd {
            var fr = 1.0f64
            if r == 1usize { fr = xy[2usize * i] }
            if r == 2usize { fr = xy[2usize * i + 1usize] }
            var b = 0.0f64
            var s = 0usize
            while s < nd {
                b += inv[r * nd + s] * xty[s]
                s += 1usize
            }
            fit += fr * b
            r += 1usize
        }
        out[i] = z[i] - fit
        i += 1usize
    }
    ret ok
}
