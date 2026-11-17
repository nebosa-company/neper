// R signal, the rest of the package: the general filter designs (butter, cheby1, cheby2 and ellip, every band type, digital or analog) through the same Zpg, sftrans and bilinear steps the package takes, the window functions, remez (the Parks-McClellan C routine line for line), fir1 and fir2 with any window, freqz, freqs, grpdelay, impz, the spectrogram, resample, decimate, interp, interp1, pchip, sgolay and sgolayfilt, unwrap, levinson, the order estimators and kaiserord.
//
// Not in the package, so not here: bessel, tf2zp, zp2tf, tf2sos, sos2tf (the package's roots, poly and Zpg cover the first two).

use e.math
use e.mem
use e.algo.stat.signalpkg as sg
use e.algo.stat.pracma as pk
use e.algo.stat.splinepkg as spl

error BadSpec

const CAP: usize = 160usize

fn pi_value() -> f64 { ret 3.141592653589793238462643383279f64 }

fn cmul(ar: f64, ai: f64, br: f64, bi: f64) -> (f64, f64) { ret (ar * br - ai * bi, ar * bi + ai * br) }

fn cdiv(ar: f64, ai: f64, br: f64, bi: f64) -> (f64, f64) {
    let d = br * br + bi * bi
    ret ((ar * br + ai * bi) / d, (ai * br - ar * bi) / d)
}

// the principal square root
fn csqrt(re: f64, im: f64) -> (f64, f64) {
    if im == 0.0f64 {
        if re >= 0.0f64 { ret (math.sqrt[f64](re), 0.0f64) }
        ret (0.0f64, math.sqrt[f64](0.0f64 - re))
    }
    let m = math.sqrt[f64](re * re + im * im)
    let t = math.sqrt[f64]((m + math.abs[f64](re)) / 2.0f64)
    if re >= 0.0f64 { ret (t, im / (2.0f64 * t)) }
    var s = math.abs[f64](im) / (2.0f64 * t)
    var u = t
    if im < 0.0f64 { u = 0.0f64 - t }
    ret (s, u)
}

// the product of the complex entries
fn cprod(re: []const f64, im: []const f64, n: usize) -> (f64, f64) {
    var pr = 1.0f64
    var pi2 = 0.0f64
    var i = 0usize
    while i < n {
        let (x, y) = cmul(pr, pi2, re[i], im[i])
        pr = x
        pi2 = y
        i += 1usize
    }
    ret (pr, pi2)
}

// poly(roots): the monic polynomial, highest power first, n + 1 entries
fn poly_roots_cx(re: []const f64, im: []const f64, n: usize, outr: []f64, outi: []f64) {
    var cr: [CAP]f64 = zero
    var ci: [CAP]f64 = zero
    cr[0usize] = 1.0f64
    var j = 1usize
    while j <= n {
        // y[2:(j+1)] = y[2:(j+1)] - v[j] * y[1:j]
        var k = j
        while k >= 1usize {
            let (tr, ti) = cmul(re[j - 1usize], im[j - 1usize], cr[k - 1usize], ci[k - 1usize])
            cr[k] = cr[k] - tr
            ci[k] = ci[k] - ti
            k -= 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i <= n {
        outr[i] = cr[i]
        outi[i] = ci[i]
        i += 1usize
    }
}

// R's optimize (Brent_fmin) of |K(kl) / K(1 - kl) - target| on [ax, bx]
fn ellipke_pair(m1: f64, m2: f64) -> (f64, f64) {
    var a1 = 1.0f64
    var a2 = 1.0f64
    var b1 = math.sqrt[f64](1.0f64 - m1)
    var b2 = math.sqrt[f64](1.0f64 - m2)
    var c1 = math.sqrt[f64](m1)
    var c2 = math.sqrt[f64](m2)
    var n = 2usize
    while n <= 16usize {
        let t1 = (a1 + b1) / 2.0f64
        c1 = (a1 - b1) / 2.0f64
        b1 = math.sqrt[f64](a1 * b1)
        a1 = t1
        let t2 = (a2 + b2) / 2.0f64
        c2 = (a2 - b2) / 2.0f64
        b2 = math.sqrt[f64](a2 * b2)
        a2 = t2
        if c1 / a1 < 2.220446049250313e-16f64 && c2 / a2 < 2.220446049250313e-16f64 { break }
        n += 1usize
    }
    ret (0.5f64 * pi_value() / a1, 0.5f64 * pi_value() / a2)
}

fn ws_objective(kl: f64, target_ratio: f64) -> f64 {
    let (ql, q) = ellipke_pair(kl, 1.0f64 - kl)
    ret math.abs[f64](ql / q - target_ratio)
}

fn ellip_ws(n: usize, rp: f64, rs: f64) -> f64 {
    let kl0 = (math.pow[f64](10.0f64, 0.1f64 * rp) - 1.0f64) / (math.pow[f64](10.0f64, 0.1f64 * rs) - 1.0f64)
    let k0 = 1.0f64 - kl0
    let (ql0, q0) = ellipke_pair(kl0, k0)
    let x = f64(n) * ql0 / q0
    let eps2 = 2.220446049250313e-16f64
    let ax = eps2
    let bx = 1.0f64 - eps2
    let tol = math.sqrt[f64](math.sqrt[f64](eps2))
    let c = (3.0f64 - math.sqrt[f64](5.0f64)) * 0.5f64
    let eps = math.sqrt[f64](eps2)
    var a = ax
    var b = bx
    var v = a + c * (b - a)
    var w = v
    var xx = v
    var d = 0.0f64
    var e = 0.0f64
    var fx = ws_objective(xx, x)
    var fv = fx
    var fw = fx
    let tol3 = tol / 3.0f64
    var guard = 0usize
    while guard < 1000usize {
        guard += 1usize
        let xm = (a + b) * 0.5f64
        let tol1 = eps * math.abs[f64](xx) + tol3
        let t2 = tol1 * 2.0f64
        if math.abs[f64](xx - xm) <= t2 - (b - a) * 0.5f64 { break }
        var p = 0.0f64
        var q = 0.0f64
        var r = 0.0f64
        if math.abs[f64](e) > tol1 {
            r = (xx - w) * (fx - fv)
            q = (xx - v) * (fx - fw)
            p = (xx - v) * q - (xx - w) * r
            q = (q - r) * 2.0f64
            if q > 0.0f64 { p = 0.0f64 - p } else { q = 0.0f64 - q }
            r = e
            e = d
        }
        var u = 0.0f64
        if math.abs[f64](p) >= math.abs[f64](q * 0.5f64 * r) || p <= q * (a - xx) || p >= q * (b - xx) {
            if xx < xm { e = b - xx } else { e = a - xx }
            d = c * e
        } else {
            d = p / q
            u = xx + d
            if u - a < t2 || b - u < t2 {
                d = tol1
                if xx >= xm { d = 0.0f64 - d }
            }
        }
        if math.abs[f64](d) >= tol1 {
            u = xx + d
        } else if d > 0.0f64 {
            u = xx + tol1
        } else {
            u = xx - tol1
        }
        let fu = ws_objective(u, x)
        if fu <= fx {
            if u < xx { b = xx } else { a = xx }
            v = w
            w = xx
            xx = u
            fv = fw
            fw = fx
            fx = fu
        } else {
            if u < xx { a = u } else { b = u }
            if fu <= fw || w == xx {
                v = w
                fv = fw
                w = u
                fw = fu
            } else if fu <= fv || v == xx || v == w {
                v = u
                fv = fu
            }
        }
    }
    ret math.sqrt[f64](1.0f64 / xx)
}

// ncauer(rp, rs, n): the elliptic analog prototype; zeros into zr/zi, poles into pre/pim; returns (zero count, gain)
fn ncauer(rp: f64, rs: f64, n: usize, zr: []f64, zi: []f64, pre: []f64, pim: []f64) -> (usize, f64) {
    let ws = ellip_ws(n, rp, rs)
    let wp = 1.0f64
    let k = wp / ws
    let k1 = math.sqrt[f64](1.0f64 - k * k)
    let q0 = 0.5f64 * ((1.0f64 - math.sqrt[f64](k1)) / (1.0f64 + math.sqrt[f64](k1)))
    let q = q0 + 2.0f64 * math.pow[f64](q0, 5.0f64) + 15.0f64 * math.pow[f64](q0, 9.0f64) + 150.0f64 * math.pow[f64](q0, 13.0f64)
    let l = (1.0f64 / (2.0f64 * f64(n))) * math.log[f64]((math.pow[f64](10.0f64, 0.05f64 * rp) + 1.0f64) / (math.pow[f64](10.0f64, 0.05f64 * rp) - 1.0f64))
    var sig01 = 0.0f64
    var sig02 = 0.0f64
    var m = 0usize
    var sgn = 1.0f64
    while m <= 30usize {
        sig01 = sig01 + sgn * math.pow[f64](q, f64(m * (m + 1usize))) * sinh_value(f64(2usize * m + 1usize) * l)
        sgn = 0.0f64 - sgn
        m += 1usize
    }
    m = 1usize
    sgn = -1.0f64
    while m <= 30usize {
        sig02 = sig02 + sgn * math.pow[f64](q, f64(m * m)) * cosh_value(2.0f64 * f64(m) * l)
        sgn = 0.0f64 - sgn
        m += 1usize
    }
    let sig0 = math.abs[f64]((2.0f64 * math.pow[f64](q, 0.25f64) * sig01) / (1.0f64 + 2.0f64 * sig02))
    let w = math.sqrt[f64]((1.0f64 + k * sig0 * sig0) * (1.0f64 + sig0 * sig0 / k))
    let odd = n % 2usize
    let r = (n - odd) / 2usize
    var wi: [CAP]f64 = zero
    var ii = 1usize
    while ii <= r {
        let mu = f64(ii) - (1.0f64 - f64(odd)) / 2.0f64
        var soma1 = 0.0f64
        m = 0usize
        sgn = 1.0f64
        while m <= 30usize {
            soma1 = soma1 + 2.0f64 * math.pow[f64](q, 0.25f64) * (sgn * math.pow[f64](q, f64(m * (m + 1usize))) * math.sin[f64](f64(2usize * m + 1usize) * pi_value() * mu / f64(n)))
            sgn = 0.0f64 - sgn
            m += 1usize
        }
        var soma2 = 0.0f64
        m = 1usize
        sgn = -1.0f64
        while m <= 30usize {
            soma2 = soma2 + 2.0f64 * (sgn * math.pow[f64](q, f64(m * m)) * math.cos[f64](2.0f64 * f64(m) * pi_value() * mu / f64(n)))
            sgn = 0.0f64 - sgn
            m += 1usize
        }
        wi[ii - 1usize] = soma1 / (1.0f64 + soma2)
        ii += 1usize
    }
    var t0 = 1.0f64
    var bprod = 1.0f64
    var i = 0usize
    let rt = math.sqrt[f64](ws)
    var vi: [CAP]f64 = zero
    while i < r {
        let wv = wi[i]
        vi[i] = math.sqrt[f64]((1.0f64 - (k * (wv * wv))) * (1.0f64 - (wv * wv) / k))
        let a0i = 1.0f64 / (wv * wv)
        let b0i = ((sig0 * vi[i]) * (sig0 * vi[i]) + (w * wv) * (w * wv)) / ((1.0f64 + sig0 * sig0 * wv * wv) * (1.0f64 + sig0 * sig0 * wv * wv))
        bprod = bprod * (b0i / a0i)
        i += 1usize
    }
    if odd == 1usize { t0 = sig0 * bprod * rt } else { t0 = math.pow[f64](10.0f64, -0.05f64 * rp) * bprod }
    i = 0usize
    while i < r {
        let sq = 1.0f64 / wi[i]
        zr[i] = 0.0f64
        zi[i] = rt * sq
        zr[r + i] = 0.0f64
        zi[r + i] = 0.0f64 - rt * sq
        let den = 2.0f64 * (1.0f64 + sig0 * sig0 * wi[i] * wi[i])
        let pr0 = (-2.0f64 * sig0 * vi[i]) / den
        let pi0 = (2.0f64 * wi[i] * w) / den
        pre[i] = rt * pr0
        pim[i] = rt * pi0
        pre[r + i] = rt * pr0
        pim[r + i] = 0.0f64 - rt * pi0
        i += 1usize
    }
    if odd == 1usize {
        pre[2usize * r] = rt * (0.0f64 - sig0)
        pim[2usize * r] = 0.0f64
    }
    ret (2usize * r, t0)
}

fn sinh_value(x: f64) -> f64 { ret (math.exp[f64](x) - math.exp[f64](0.0f64 - x)) / 2.0f64 }

fn cosh_value(x: f64) -> f64 { ret (math.exp[f64](x) + math.exp[f64](0.0f64 - x)) / 2.0f64 }

fn asinh_value(x: f64) -> f64 { ret math.log[f64](x + math.sqrt[f64](x * x + 1.0f64)) }

// the analog low-pass prototype of a family (0 butter, 1 cheby1, 2 cheby2, 3 ellip); returns (zero count, gain), the pole count is n
fn prototype(kind: usize, n: usize, rp: f64, rs: f64, zr: []f64, zi: []f64, pre: []f64, pim: []f64) -> (usize, f64) {
    let nf = f64(n)
    var i = 0usize
    if kind == 0usize {
        i = 1usize
        while i <= n {
            let ang = pi_value() * f64(2usize * i + n - 1usize) / (2.0f64 * nf)
            pre[i - 1usize] = math.cos[f64](ang)
            pim[i - 1usize] = math.sin[f64](ang)
            i += 1usize
        }
        if n % 2usize == 1usize {
            pre[(n + 1usize) / 2usize - 1usize] = -1.0f64
            pim[(n + 1usize) / 2usize - 1usize] = 0.0f64
        }
        ret (0usize, 1.0f64)
    }
    if kind == 1usize {
        let epsilon = math.sqrt[f64](math.pow[f64](10.0f64, rp / 10.0f64) - 1.0f64)
        let v0 = asinh_value(1.0f64 / epsilon) / nf
        i = 0usize
        while i < n {
            let kk = 0.0f64 - (nf - 1.0f64) + 2.0f64 * f64(i)
            let ang = pi_value() * kk / (2.0f64 * nf)
            pre[i] = 0.0f64 - sinh_value(v0) * math.cos[f64](ang)
            pim[i] = cosh_value(v0) * math.sin[f64](ang)
            i += 1usize
        }
        var gr = 1.0f64
        var gi = 0.0f64
        i = 0usize
        while i < n {
            let (x, y) = cmul(gr, gi, 0.0f64 - pre[i], 0.0f64 - pim[i])
            gr = x
            gi = y
            i += 1usize
        }
        if n % 2usize == 0usize { gr = gr / math.pow[f64](10.0f64, rp / 20.0f64) }
        ret (0usize, gr)
    }
    if kind == 2usize {
        let lambda = math.pow[f64](10.0f64, rs / 20.0f64)
        let phi = math.log[f64](lambda + math.sqrt[f64](lambda * lambda - 1.0f64)) / nf
        var nz = 0usize
        i = 1usize
        while i <= n {
            let theta = pi_value() * (f64(i) - 0.5f64) / nf
            let alpha = 0.0f64 - sinh_value(phi) * math.sin[f64](theta)
            let beta = cosh_value(phi) * math.cos[f64](theta)
            let den = alpha * alpha + beta * beta
            pre[i - 1usize] = alpha / den
            pim[i - 1usize] = (0.0f64 - beta) / den
            var skip = false
            if n % 2usize == 1usize && i == (n + 1usize) / 2usize { skip = true }
            if !skip {
                zr[nz] = 0.0f64
                zi[nz] = 1.0f64 / math.cos[f64](theta)
                nz += 1usize
            }
            i += 1usize
        }
        let (pp_r, pp_i) = cprod(pre, pim, n)
        let (zp_r, zp_i) = cprod(zr, zi, nz)
        let (qr, qi) = cdiv(pp_r, pp_i, zp_r, zp_i)
        let _ = qi
        ret (nz, math.abs[f64](qr))
    }
    let (ncount, ngain) = ncauer(rp, rs, n, zr, zi, pre, pim)
    ret (ncount, ngain)
}


// the complex entries scaled and split by the band transform: b + s and b - s for each b, s = sqrt(b^2 - fhfl); count entries per half
fn split_pairs(br: []const f64, bi: []const f64, n: usize, fhfl: f64, outr: []f64, outi: []f64, at: usize) {
    var i = 0usize
    while i < n {
        let (b2r, b2i) = cmul(br[i], bi[i], br[i], bi[i])
        let (sr, si) = csqrt(b2r - fhfl, b2i)
        outr[at + i] = br[i] + sr
        outi[at + i] = bi[i] + si
        outr[at + n + i] = br[i] - sr
        outi[at + n + i] = bi[i] - si
        i += 1usize
    }
}

// sftrans: Sz, Sp, Sg to the band type by W (one cut-off fl, or the pair fl, fh); returns (zero count, pole count, gain)
fn sftrans_zpg(zr: []f64, zi: []f64, nz: usize, pre: []f64, pim: []f64, np: usize, gain: f64, fl: f64, fh: f64, two: bool, stop: bool) -> (usize, usize, f64) {
    var tr: [CAP]f64 = zero
    var ti: [CAP]f64 = zero
    var g = gain
    let z = nz
    let p = np
    var i = 0usize
    if two {
        let fhfl = fh * fl
        let bw = fh - fl
        if stop {
            let (n1, n2) = cprod_neg(zr, zi, nz)
            let (d1, d2) = cprod_neg(pre, pim, np)
            let (qr, qi) = cdiv(n1, n2, d1, d2)
            let _ = qi
            g = g * qr
            i = 0usize
            while i < p {
                let (xr, xi) = cdiv(bw / 2.0f64, 0.0f64, pre[i], pim[i])
                tr[i] = xr
                ti[i] = xi
                i += 1usize
            }
            var npr: [CAP]f64 = zero
            var npi: [CAP]f64 = zero
            split_pairs(tr[0usize..p], ti[0usize..p], p, fhfl, npr[0usize..CAP], npi[0usize..CAP], 0usize)
            let e1r = 0.0f64
            let e1i = math.sqrt[f64](fhfl)
            var nzr: [CAP]f64 = zero
            var nzi: [CAP]f64 = zero
            var nzo = 0usize
            if z == 0usize {
                var k = 1usize
                while k <= 2usize * p {
                    nzr[k - 1usize] = e1r
                    if k % 2usize == 1usize { nzi[k - 1usize] = 0.0f64 - e1i } else { nzi[k - 1usize] = e1i }
                    k += 1usize
                }
                nzo = 2usize * p
            } else {
                i = 0usize
                while i < z {
                    let (xr, xi) = cdiv(bw / 2.0f64, 0.0f64, zr[i], zi[i])
                    tr[i] = xr
                    ti[i] = xi
                    i += 1usize
                }
                split_pairs(tr[0usize..z], ti[0usize..z], z, fhfl, nzr[0usize..CAP], nzi[0usize..CAP], 0usize)
                nzo = 2usize * z
                if p > z {
                    var e0 = e1i
                    if (p - z) % 2usize == 1usize { e0 = 0.0f64 - e1i }
                    nzr[nzo] = 0.0f64
                    nzi[nzo] = e0
                    nzr[nzo + 1usize] = 0.0f64
                    nzi[nzo + 1usize] = e1i
                    nzo += 2usize
                }
            }
            i = 0usize
            while i < 2usize * p {
                pre[i] = npr[i]
                pim[i] = npi[i]
                i += 1usize
            }
            i = 0usize
            while i < nzo {
                zr[i] = nzr[i]
                zi[i] = nzi[i]
                i += 1usize
            }
            ret (nzo, 2usize * p, g)
        }
        g = g * math.pow[f64](1.0f64 / bw, f64(z) - f64(p))
        i = 0usize
        while i < p {
            tr[i] = pre[i] * bw / 2.0f64
            ti[i] = pim[i] * bw / 2.0f64
            i += 1usize
        }
        var npr: [CAP]f64 = zero
        var npi: [CAP]f64 = zero
        split_pairs(tr[0usize..p], ti[0usize..p], p, fhfl, npr[0usize..CAP], npi[0usize..CAP], 0usize)
        var nzr: [CAP]f64 = zero
        var nzi: [CAP]f64 = zero
        var nzo = 0usize
        if z == 0usize {
            nzo = p
        } else {
            i = 0usize
            while i < z {
                tr[i] = zr[i] * bw / 2.0f64
                ti[i] = zi[i] * bw / 2.0f64
                i += 1usize
            }
            split_pairs(tr[0usize..z], ti[0usize..z], z, fhfl, nzr[0usize..CAP], nzi[0usize..CAP], 0usize)
            nzo = 2usize * z
            if p > z { nzo += p - z }
        }
        i = 0usize
        while i < 2usize * p {
            pre[i] = npr[i]
            pim[i] = npi[i]
            i += 1usize
        }
        i = 0usize
        while i < nzo {
            zr[i] = nzr[i]
            zi[i] = nzi[i]
            i += 1usize
        }
        ret (nzo, 2usize * p, g)
    }
    let fc = fl
    if stop {
        let (n1, n2) = cprod_neg(zr, zi, nz)
        let (d1, d2) = cprod_neg(pre, pim, np)
        let (qr, qi) = cdiv(n1, n2, d1, d2)
        let _ = qi
        g = g * qr
        i = 0usize
        while i < p {
            let (xr, xi) = cdiv(fc, 0.0f64, pre[i], pim[i])
            pre[i] = xr
            pim[i] = xi
            i += 1usize
        }
        if z == 0usize {
            i = 0usize
            while i < p {
                zr[i] = 0.0f64
                zi[i] = 0.0f64
                i += 1usize
            }
            ret (p, p, g)
        }
        i = 0usize
        while i < z {
            let (xr, xi) = cdiv(fc, 0.0f64, zr[i], zi[i])
            zr[i] = xr
            zi[i] = xi
            i += 1usize
        }
        i = z
        while i < p {
            zr[i] = 0.0f64
            zi[i] = 0.0f64
            i += 1usize
        }
        var nzo = z
        if p > z { nzo = p }
        ret (nzo, p, g)
    }
    g = g * math.pow[f64](1.0f64 / fc, f64(z) - f64(p))
    i = 0usize
    while i < p {
        pre[i] = fc * pre[i]
        pim[i] = fc * pim[i]
        i += 1usize
    }
    i = 0usize
    while i < z {
        zr[i] = fc * zr[i]
        zi[i] = fc * zi[i]
        i += 1usize
    }
    ret (z, p, g)
}

// the product of the negated entries
fn cprod_neg(re: []const f64, im: []const f64, n: usize) -> (f64, f64) {
    var pr = 1.0f64
    var pi2 = 0.0f64
    var i = 0usize
    while i < n {
        let (x, y) = cmul(pr, pi2, 0.0f64 - re[i], 0.0f64 - im[i])
        pr = x
        pi2 = y
        i += 1usize
    }
    ret (pr, pi2)
}

// bilinear(Sz, Sp, Sg, T) in place; returns (zero count, gain)
fn bilinear_zpg(zr: []f64, zi: []f64, nz: usize, pre: []f64, pim: []f64, np: usize, gain: f64, tt: f64) -> (usize, f64) {
    var ar: [CAP]f64 = zero
    var ai: [CAP]f64 = zero
    var i = 0usize
    while i < nz {
        let (xr, xi) = cdiv((2.0f64 - zr[i] * tt), 0.0f64 - zi[i] * tt, tt, 0.0f64)
        ar[i] = xr
        ai[i] = xi
        i += 1usize
    }
    var br: [CAP]f64 = zero
    var bi: [CAP]f64 = zero
    i = 0usize
    while i < np {
        let (xr, xi) = cdiv((2.0f64 - pre[i] * tt), 0.0f64 - pim[i] * tt, tt, 0.0f64)
        br[i] = xr
        bi[i] = xi
        i += 1usize
    }
    let (n1, n2) = cprod(ar[0usize..CAP], ai[0usize..CAP], nz)
    let (d1, d2) = cprod(br[0usize..CAP], bi[0usize..CAP], np)
    let (qr, qi) = cdiv(n1, n2, d1, d2)
    let _ = qi
    let zg = gain * qr
    i = 0usize
    while i < np {
        let (xr, xi) = cdiv(2.0f64 + pre[i] * tt, pim[i] * tt, 2.0f64 - pre[i] * tt, 0.0f64 - pim[i] * tt)
        pre[i] = xr
        pim[i] = xi
        i += 1usize
    }
    i = 0usize
    while i < nz {
        let (xr, xi) = cdiv(2.0f64 + zr[i] * tt, zi[i] * tt, 2.0f64 - zr[i] * tt, 0.0f64 - zi[i] * tt)
        zr[i] = xr
        zi[i] = xi
        i += 1usize
    }
    var nzo = nz
    while nzo < np {
        zr[nzo] = -1.0f64
        zi[nzo] = 0.0f64
        nzo += 1usize
    }
    ret (nzo, zg)
}

// butter (kind 0), cheby1 (1), cheby2 (2) and ellip (3) of order n; ty is 0 low, 1 high, 2 stop, 3 pass (w holds one cut-off for the first two, two for the others); digital false gives the analog filter; b and aa get nb and na entries (n + 1 for one cut-off, 2 n + 1 for two); rp and rs are the dB ripples that the family uses
fn design(kind: usize, n: usize, rp: f64, rs: f64, w: []const f64, ty: usize, digital: bool, b: []f64, aa: []f64) -> err {
    if n == 0usize || n > 30usize { ret BadSpec }
    var z0 = 0usize
    while z0 < b.len {
        b[z0] = 0.0f64
        z0 += 1usize
    }
    z0 = 0usize
    while z0 < aa.len {
        aa[z0] = 0.0f64
        z0 += 1usize
    }
    let stop = ty == 1usize || ty == 2usize
    let two = ty >= 2usize
    var wv: [2]f64 = zero
    wv[0usize] = w[0usize]
    if two { wv[1usize] = w[1usize] }
    let tt = 2.0f64
    if digital {
        wv[0usize] = 2.0f64 / tt * math.tan[f64](pi_value() * wv[0usize] / tt)
        if two { wv[1usize] = 2.0f64 / tt * math.tan[f64](pi_value() * wv[1usize] / tt) }
    }
    var zr: [CAP]f64 = zero
    var zi: [CAP]f64 = zero
    var pre: [CAP]f64 = zero
    var pim: [CAP]f64 = zero
    let (nz0, g0) = prototype(kind, n, rp, rs, zr[0usize..CAP], zi[0usize..CAP], pre[0usize..CAP], pim[0usize..CAP])
    let (nz1, np1, g1) = sftrans_zpg(zr[0usize..CAP], zi[0usize..CAP], nz0, pre[0usize..CAP], pim[0usize..CAP], n, g0, wv[0usize], wv[1usize], two, stop)
    var nz2 = nz1
    var g2 = g1
    if digital {
        let (c, gz) = bilinear_zpg(zr[0usize..CAP], zi[0usize..CAP], nz1, pre[0usize..CAP], pim[0usize..CAP], np1, g1, tt)
        nz2 = c
        g2 = gz
    }
    var cr: [CAP]f64 = zero
    var ci: [CAP]f64 = zero
    poly_roots_cx(zr[0usize..CAP], zi[0usize..CAP], nz2, cr[0usize..CAP], ci[0usize..CAP])
    var i = 0usize
    while i <= nz2 {
        b[i] = g2 * cr[i]
        i += 1usize
    }
    poly_roots_cx(pre[0usize..CAP], pim[0usize..CAP], np1, cr[0usize..CAP], ci[0usize..CAP])
    i = 0usize
    while i <= np1 {
        aa[i] = cr[i]
        i += 1usize
    }
    ret ok
}

// the discrete Fourier transform of any length, unscaled (the inverse flips the sign of the exponent); radix 2 with exact twiddles for a power of two, the direct sum otherwise
fn dft(a: *mem.Arena, re: []f64, im: []f64, inverse: bool) -> err {
    let n = re.len
    if n <= 1usize { ret ok }
    let (tc, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    let (ts, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    var sgn = -1.0f64
    if inverse { sgn = 1.0f64 }
    var k = 0usize
    while k < n {
        let ang = 2.0f64 * pi_value() * f64(k) / f64(n)
        tc[k] = math.cos[f64](ang)
        ts[k] = sgn * math.sin[f64](ang)
        k += 1usize
    }
    if (n & (n - 1usize)) == 0usize {
        var j = 0usize
        var i = 0usize
        while i < n {
            if i < j {
                let tr = re[i]
                let ti = im[i]
                re[i] = re[j]
                im[i] = im[j]
                re[j] = tr
                im[j] = ti
            }
            var m = n / 2usize
            while m >= 1usize && j >= m {
                j -= m
                m = m / 2usize
            }
            j += m
            i += 1usize
        }
        var len = 2usize
        while len <= n {
            let step = n / len
            var start = 0usize
            while start < n {
                var h = 0usize
                while h < len / 2usize {
                    let p = start + h
                    let q = p + len / 2usize
                    let wr = tc[h * step]
                    let wi = ts[h * step]
                    let xr = re[q] * wr - im[q] * wi
                    let xi = re[q] * wi + im[q] * wr
                    re[q] = re[p] - xr
                    im[q] = im[p] - xi
                    re[p] = re[p] + xr
                    im[p] = im[p] + xi
                    h += 1usize
                }
                start += len
            }
            len = len * 2usize
        }
        ret ok
    }
    let (tmp_re, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret e3 }
    let (oi, e4) = mem.alloc[f64](a, n)
    if e4 != ok { ret e4 }
    k = 0usize
    while k < n {
        var sr = 0.0f64
        var si = 0.0f64
        var j = 0usize
        while j < n {
            let t = (j * k) % n
            sr += re[j] * tc[t] - im[j] * ts[t]
            si += re[j] * ts[t] + im[j] * tc[t]
            j += 1usize
        }
        tmp_re[k] = sr
        oi[k] = si
        k += 1usize
    }
    k = 0usize
    while k < n {
        re[k] = tmp_re[k]
        im[k] = oi[k]
        k += 1usize
    }
    ret ok
}

// besselI(x, 0) by the power series (x >= 0)
fn bessel_i0(x: f64) -> f64 {
    let q = x * x / 4.0f64
    var term = 1.0f64
    var s = 1.0f64
    var k = 1usize
    while k < 500usize {
        term = term * q / (f64(k) * f64(k))
        s += term
        if term < 1.0e-18f64 * s { break }
        k += 1usize
    }
    ret s
}

fn sinc_value(x: f64) -> f64 {
    if x == 0.0f64 { ret 1.0f64 }
    ret math.sin[f64](pi_value() * x) / (pi_value() * x)
}

// window functions of n points into out (kind 0 hamming, 1 hanning, 2 blackman, 3 bartlett, 4 boxcar, 5 triang, 6 kaiser with par = beta, 7 chebwin with par = at, 8 gausswin with par = w, 9 flattopwin symmetric, 10 flattopwin periodic)
fn window(a: *mem.Arena, kind: usize, n: usize, par: f64, out: []f64) -> err {
    if n == 0usize { ret BadSpec }
    let nf = f64(n)
    var i = 0usize
    if n == 1usize && kind <= 6usize {
        out[0usize] = 1.0f64
        ret ok
    }
    let m = nf - 1.0f64
    if kind == 0usize {
        while i < n {
            out[i] = 0.54f64 - 0.46f64 * math.cos[f64](2.0f64 * pi_value() * f64(i) / m)
            i += 1usize
        }
    } else if kind == 1usize {
        while i < n {
            out[i] = 0.5f64 - 0.5f64 * math.cos[f64](2.0f64 * pi_value() * f64(i) / m)
            i += 1usize
        }
    } else if kind == 2usize {
        while i < n {
            let k = f64(i) / m
            out[i] = 0.42f64 - 0.5f64 * math.cos[f64](2.0f64 * pi_value() * k) + 0.08f64 * math.cos[f64](4.0f64 * pi_value() * k)
            i += 1usize
        }
    } else if kind == 3usize {
        let mm = math.floor[f64](m / 2.0f64)
        while i < n {
            if f64(i) <= mm { out[i] = 2.0f64 * f64(i) / m } else { out[i] = 2.0f64 - 2.0f64 * f64(i) / m }
            i += 1usize
        }
    } else if kind == 4usize {
        while i < n {
            out[i] = 1.0f64
            i += 1usize
        }
    } else if kind == 5usize {
        var odd = 0.0f64
        if n % 2usize == 1usize { odd = 1.0f64 }
        while i < n {
            out[i] = 1.0f64 - math.abs[f64]((0.0f64 - m + 2.0f64 * f64(i)) / (nf + odd))
            i += 1usize
        }
    } else if kind == 6usize {
        while i < n {
            let kk = 2.0f64 * par / m * math.sqrt[f64](f64(i) * (m - f64(i)))
            out[i] = bessel_i0(kk) / bessel_i0(par)
            i += 1usize
        }
    } else if kind == 8usize {
        while i < n {
            let t = par / nf * (0.0f64 - m + 2.0f64 * f64(i))
            out[i] = math.exp[f64](-0.5f64 * (t * t))
            i += 1usize
        }
    } else if kind == 9usize || kind == 10usize {
        var div = m
        if kind == 10usize { div = nf }
        while i < n {
            let x = 2.0f64 * pi_value() * f64(i) / div
            out[i] = (1.0f64 - 1.93f64 * math.cos[f64](x) + 1.29f64 * math.cos[f64](2.0f64 * x) - 0.388f64 * math.cos[f64](3.0f64 * x) + 0.0322f64 * math.cos[f64](4.0f64 * x)) / 4.6402f64
            i += 1usize
        }
    } else if kind == 7usize {
        if n == 1usize {
            out[0usize] = 1.0f64
            ret ok
        }
        let gamma = math.pow[f64](10.0f64, 0.0f64 - par / 20.0f64)
        let acosh_arg = 1.0f64 / gamma
        let beta = cosh_value(1.0f64 / (nf - 1.0f64) * math.log[f64](acosh_arg + math.sqrt[f64](acosh_arg * acosh_arg - 1.0f64)))
        let (pr0, e1) = mem.alloc[f64](a, n)
        if e1 != ok { ret e1 }
        let (pi0, e2) = mem.alloc[f64](a, n)
        if e2 != ok { ret e2 }
        i = 0usize
        let order = nf - 1.0f64
        while i < n {
            let x = beta * math.cos[f64](pi_value() * f64(i) / nf)
            var t = 0.0f64
            if x <= 1.0f64 {
                if x >= -1.0f64 {
                    t = math.cos[f64](order * math.acos[f64](x))
                } else {
                    var sign_v = 1.0f64
                    if (n - 1usize) % 2usize == 1usize { sign_v = -1.0f64 }
                    let y = 0.0f64 - x
                    t = sign_v * cosh_value(order * math.log[f64](y + math.sqrt[f64](y * y - 1.0f64)))
                }
            } else {
                t = cosh_value(order * math.log[f64](x + math.sqrt[f64](x * x - 1.0f64)))
            }
            pr0[i] = t
            pi0[i] = 0.0f64
            i += 1usize
        }
        if n % 2usize == 1usize {
            let e3 = dft(a, pr0, pi0, false)
            if e3 != ok { ret e3 }
            let mm = (n + 1usize) / 2usize
            // w = c(w[M:2], w) with w = w[1:M] / w[1]
            i = 0usize
            while i < mm {
                let v = pr0[i] / pr0[0usize]
                out[mm - 1usize + i] = v
                out[mm - 1usize - i] = v
                i += 1usize
            }
        } else {
            i = 0usize
            while i < n {
                let ang = pi_value() / nf * f64(i)
                let (xr, xi) = cmul(pr0[i], 0.0f64, math.cos[f64](ang), math.sin[f64](ang))
                pr0[i] = xr
                pi0[i] = xi
                i += 1usize
            }
            let e3 = dft(a, pr0, pi0, false)
            if e3 != ok { ret e3 }
            let mm = n / 2usize + 1usize
            // w = w / w[2]; w = c(w[M:2], w[2:M])
            i = 2usize
            while i <= mm {
                let v = pr0[i - 1usize] / pr0[1usize]
                out[mm - i] = v
                out[mm + i - 3usize] = v
                i += 1usize
            }
        }
    } else {
        ret BadSpec
    }
    ret ok
}

// polyval(coef, z) for a real polynomial, highest power first, at the complex point (zr, zi)
fn polyval_at(coef: []const f64, zr: f64, zi: f64) -> (f64, f64) {
    var sr = 0.0f64
    var si = 0.0f64
    var i = 0usize
    while i < coef.len {
        let (xr, xi) = cmul(sr, si, zr, zi)
        sr = xr + coef[i]
        si = xi
        i += 1usize
    }
    ret (sr, si)
}

// conv(x, y) of two real vectors: x.len + y.len - 1 entries
fn conv(x: []const f64, y: []const f64, out: []f64) {
    let n = x.len + y.len - 1usize
    var k = 0usize
    while k < n {
        out[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < x.len {
        var j = 0usize
        while j < y.len {
            out[i + j] += x[i] * y[j]
            j += 1usize
        }
        i += 1usize
    }
}

// fftfilt(b, x): the convolution cut to the length of x, rounded when both inputs are whole numbers
fn fftfilt(b: []const f64, x: []const f64, out: []f64) {
    var i = 0usize
    while i < x.len {
        var s = 0.0f64
        var j = 0usize
        while j < b.len && j <= i {
            s += b[j] * x[i - j]
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
    var whole = true
    i = 0usize
    while i < b.len {
        if b[i] != math.round[f64](b[i]) { whole = false }
        i += 1usize
    }
    i = 0usize
    while i < x.len {
        if x[i] != math.round[f64](x[i]) { whole = false }
        i += 1usize
    }
    if whole {
        i = 0usize
        while i < x.len {
            out[i] = math.round[f64](out[i])
            i += 1usize
        }
    }
}

// freqz(b, a, w): the response at each w (radians per sample): hr and hi get w.len entries
fn freqz_points(b: []const f64, aa: []const f64, w: []const f64, hr: []f64, hi: []f64) {
    var i = 0usize
    while i < w.len {
        var br = 0.0f64
        var bi = 0.0f64
        var k = 0usize
        while k < b.len {
            let ang = w[i] * f64(k)
            br += b[k] * math.cos[f64](ang)
            bi -= b[k] * math.sin[f64](ang)
            k += 1usize
        }
        var ar = 0.0f64
        var ai = 0.0f64
        k = 0usize
        while k < aa.len {
            let ang = w[i] * f64(k)
            ar += aa[k] * math.cos[f64](ang)
            ai -= aa[k] * math.sin[f64](ang)
            k += 1usize
        }
        let (xr, xi) = cdiv(br, bi, ar, ai)
        hr[i] = xr
        hi[i] = xi
        i += 1usize
    }
}

// freqz(b, a, n, region) on the n-point grid: whole is the circle (w = 2 pi k / n), otherwise the half circle (w = pi k / n)
fn freqz_grid(b: []const f64, aa: []const f64, n: usize, whole: bool, hr: []f64, hi: []f64) {
    var i = 0usize
    var denom = 2usize * n
    if whole { denom = n }
    while i < n {
        var br = 0.0f64
        var bi = 0.0f64
        var k = 0usize
        while k < b.len {
            let ang = 2.0f64 * pi_value() * f64((i * k) % denom) / f64(denom)
            br += b[k] * math.cos[f64](ang)
            bi -= b[k] * math.sin[f64](ang)
            k += 1usize
        }
        var ar = 0.0f64
        var ai = 0.0f64
        k = 0usize
        while k < aa.len {
            let ang = 2.0f64 * pi_value() * f64((i * k) % denom) / f64(denom)
            ar += aa[k] * math.cos[f64](ang)
            ai -= aa[k] * math.sin[f64](ang)
            k += 1usize
        }
        let (xr, xi) = cdiv(br, bi, ar, ai)
        hr[i] = xr
        hi[i] = xi
        i += 1usize
    }
}

// freqs(b, a, W): the analog response polyval(b, iW) / polyval(a, iW)
fn freqs_points(b: []const f64, aa: []const f64, w: []const f64, hr: []f64, hi: []f64) {
    var i = 0usize
    while i < w.len {
        let (br, bi) = polyval_at(b, 0.0f64, w[i])
        let (ar, ai) = polyval_at(aa, 0.0f64, w[i])
        let (xr, xi) = cdiv(br, bi, ar, ai)
        hr[i] = xr
        hi[i] = xi
        i += 1usize
    }
}

// grpdelay(b, a, n, whole): gd gets n entries (2 n points of the circle, the first n unless whole, then n points)
fn grpdelay(a: *mem.Arena, b: []const f64, aa: []const f64, n: usize, whole: bool, gd: []f64) -> err {
    var nfft = n
    if !whole { nfft = 2usize * n }
    let oa = aa.len - 1usize
    let ob = b.len - 1usize
    let oc = oa + ob
    let (c, e1) = mem.alloc[f64](a, oc + 1usize)
    if e1 != ok { ret e1 }
    let (ra, e2) = mem.alloc[f64](a, aa.len)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < aa.len {
        ra[i] = aa[aa.len - 1usize - i]
        i += 1usize
    }
    conv(b, ra, c)
    let (nr, e3) = mem.alloc[f64](a, nfft)
    if e3 != ok { ret e3 }
    let (ni, e4) = mem.alloc[f64](a, nfft)
    if e4 != ok { ret e4 }
    let (dr, e5) = mem.alloc[f64](a, nfft)
    if e5 != ok { ret e5 }
    let (di, e6) = mem.alloc[f64](a, nfft)
    if e6 != ok { ret e6 }
    i = 0usize
    while i < nfft {
        nr[i] = 0.0f64
        ni[i] = 0.0f64
        dr[i] = 0.0f64
        di[i] = 0.0f64
        if i <= oc {
            nr[i] = c[i] * f64(i)
            dr[i] = c[i]
        }
        i += 1usize
    }
    let e7 = dft(a, nr, ni, false)
    if e7 != ok { ret e7 }
    let e8 = dft(a, dr, di, false)
    if e8 != ok { ret e8 }
    var keep = nfft
    if !whole { keep = n }
    i = 0usize
    while i < keep {
        var xr = nr[i]
        var xi = ni[i]
        var yr = dr[i]
        var yi = di[i]
        if math.sqrt[f64](yr * yr + yi * yi) < 2.0f64 * 2.220446049250313e-16f64 {
            xr = 0.0f64
            xi = 0.0f64
            yr = 1.0f64
            yi = 0.0f64
        }
        let (qr, qi) = cdiv(xr, xi, yr, yi)
        let _ = qi
        gd[i] = qr - f64(oa)
        i += 1usize
    }
    ret ok
}

// the default length impz picks when n is not given
fn impz_length(a: *mem.Arena, b: []const f64, aa: []const f64) -> usize {
    if aa.len <= 1usize { ret b.len }
    let precision = 1.0e-6f64
    let m = aa.len
    let (cf, e0) = mem.alloc[f64](a, m)
    if e0 != ok { ret 0usize }
    var i = 0usize
    while i < m {
        cf[i] = aa[m - 1usize - i]
        i += 1usize
    }
    let (rr, e1) = mem.alloc[f64](a, m)
    let (ri, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret 0usize }
    let deg = pk.polyroot_c(a, cf, rr, ri)
    if deg < 1i64 { ret b.len }
    let cnt = usize(deg)
    var maxpole = 0.0f64
    i = 0usize
    while i < cnt {
        let ab = math.sqrt[f64](rr[i] * rr[i] + ri[i] * ri[i])
        if ab > maxpole { maxpole = ab }
        i += 1usize
    }
    var n = 0.0f64
    if maxpole > 1.0f64 + precision {
        n = math.floor[f64](6.0f64 / math.log10[f64](maxpole))
    } else if maxpole < 1.0f64 - precision {
        n = math.floor[f64](-6.0f64 / math.log10[f64](maxpole))
    } else {
        n = 30.0f64
        var minarg = 1.0e300f64
        var any_periodic = false
        i = 0usize
        while i < cnt {
            let ab = math.sqrt[f64](rr[i] * rr[i] + ri[i] * ri[i])
            let arg = math.abs[f64](math.atan2[f64](ri[i], rr[i]))
            if ab >= 1.0f64 - precision && arg > 0.0f64 {
                any_periodic = true
                if arg < minarg { minarg = arg }
            }
            i += 1usize
        }
        if any_periodic {
            let np = math.ceil[f64](10.0f64 * pi_value() / minarg)
            if np > n { n = np }
        }
        var maxd = 0.0f64
        i = 0usize
        while i < cnt {
            let ab = math.sqrt[f64](rr[i] * rr[i] + ri[i] * ri[i])
            if ab < 1.0f64 - precision && ab > maxd { maxd = ab }
            i += 1usize
        }
        if maxd > 0.0f64 {
            let nd = math.floor[f64](-3.0f64 / math.log10[f64](maxd))
            if nd > n { n = nd }
        }
    }
    ret usize(n) + b.len
}

// impz(b, a, n): the first n samples of the impulse response
fn impz(b: []const f64, aa: []const f64, n: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < b.len && j <= i {
            s += b[j] * (if_unit(i - j))
            j += 1usize
        }
        j = 1usize
        while j < aa.len && j <= i {
            s -= aa[j] * out[i - j]
            j += 1usize
        }
        out[i] = s / aa[0usize]
        i += 1usize
    }
}

fn if_unit(k: usize) -> f64 {
    if k == 0usize { ret 1.0f64 }
    ret 0.0f64
}

// the filter with initial state: init_x are the n_b - 1 past inputs (oldest first) and init_y the n_a - 1 past outputs (most recent first)
fn filter_init(b: []const f64, aa: []const f64, x: []const f64, init_x: []const f64, init_y: []const f64, out: []f64) {
    let a1 = aa[0usize]
    var i = 0usize
    while i < x.len {
        var s = 0.0f64
        var j = 0usize
        while j < b.len {
            var v = 0.0f64
            if i >= j {
                v = x[i - j]
            } else {
                // c(init.x, x): the past input j - i steps back
                let back = j - i
                if back <= init_x.len { v = init_x[init_x.len - back] }
            }
            s += (b[j] / a1) * v
            j += 1usize
        }
        j = 1usize
        while j < aa.len {
            var v = 0.0f64
            if i >= j {
                v = out[i - j]
            } else {
                let back = j - i
                if back <= init_y.len { v = init_y[back - 1usize] }
            }
            s += (0.0f64 - aa[j] / a1) * v
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
}

// specgram(x, n, Fs, window, overlap): the window count, then S (the first ret_n rows of each column, real parts in sre and imaginary parts in sim, column by column), the frequencies f and the times t
fn specgram(a: *mem.Arena, x: []const f64, n0: usize, fs: f64, win: []const f64, overlap: usize, sre: []f64, sim: []f64, f: []f64, t: []f64) -> (usize, usize, err) {
    var n = n0
    let ws = win.len
    if ws > n { n = ws }
    let step = ws - overlap
    var count = 1usize
    if x.len > ws { count = (x.len - ws - 1usize) / step + 1usize }
    var retn = n / 2usize
    if n % 2usize == 1usize { retn = (n + 1usize) / 2usize }
    let (cr, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (0usize, 0usize, e1) }
    let (ci, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (0usize, 0usize, e2) }
    var c = 0usize
    while c < count {
        let off = c * step
        var i = 0usize
        while i < n {
            cr[i] = 0.0f64
            ci[i] = 0.0f64
            if i < ws { cr[i] = x[off + i] * win[i] }
            i += 1usize
        }
        let e3 = dft(a, cr, ci, false)
        if e3 != ok { ret (0usize, 0usize, e3) }
        i = 0usize
        while i < retn {
            sre[c * retn + i] = cr[i]
            sim[c * retn + i] = ci[i]
            i += 1usize
        }
        t[c] = f64(off + 1usize) / fs
        c += 1usize
    }
    var i = 0usize
    while i < retn {
        f[i] = f64(i) * fs / f64(n)
        i += 1usize
    }
    ret (count, retn, ok)
}

// unwrap(a, tol)
fn unwrap_tol(x: []const f64, tol: f64, out: []f64) {
    var r = 0.0f64
    var i = 0usize
    let t = math.abs[f64](tol)
    while i < x.len {
        if i > 0usize {
            let d = x[i - 1usize] - x[i]
            var p = 0.0f64
            if d > t { p = 2.0f64 * pi_value() }
            if d < 0.0f64 - t { p = 0.0f64 - 2.0f64 * pi_value() }
            r += p
        }
        out[i] = x[i] + r
        i += 1usize
    }
}

// levinson(acf, p): a gets p + 1 entries, ref p; returns v
fn levinson(acf: []const f64, p: usize, aa: []f64, rf: []f64) -> f64 {
    var g = 0.0f64 - acf[1usize] / acf[0usize]
    aa[0usize] = g
    var v = (1.0f64 - g * g) * acf[0usize]
    rf[0usize] = g
    var t = 2usize
    while t <= p {
        var s = 0.0f64
        var j = 1usize
        while j <= t - 1usize {
            s += aa[j - 1usize] * acf[t - j]
            j += 1usize
        }
        g = 0.0f64 - (acf[t] + s) / v
        // a = c(a + g * rev(a), g)
        var tmp: [CAP]f64 = zero
        j = 0usize
        while j < t - 1usize {
            tmp[j] = aa[j] + g * aa[t - 2usize - j]
            j += 1usize
        }
        j = 0usize
        while j < t - 1usize {
            aa[j] = tmp[j]
            j += 1usize
        }
        aa[t - 1usize] = g
        v = v * (1.0f64 - g * g)
        rf[t - 1usize] = g
        t += 1usize
    }
    ret v
}

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

// ---- remez: the Parks-McClellan C routine ----

fn remez_calc_parms(r: usize, ext: []const usize, grid: []const f64, d: []const f64, w: []const f64, ad: []f64, x: []f64, y: []f64) {
    var i = 0usize
    while i <= r {
        x[i] = math.cos[f64](6.2831853071795865f64 * grid[ext[i]])
        i += 1usize
    }
    let ld = (r - 1usize) / 15usize + 1usize
    i = 0usize
    while i <= r {
        var denom = 1.0f64
        let xi = x[i]
        var j = 0usize
        while j < ld {
            var k = j
            while k <= r {
                if k != i { denom *= 2.0f64 * (xi - x[k]) }
                k += ld
            }
            j += 1usize
        }
        if math.abs[f64](denom) < 0.00001f64 { denom = 0.00001f64 }
        ad[i] = 1.0f64 / denom
        i += 1usize
    }
    var numer = 0.0f64
    var denom2 = 0.0f64
    var sign = 1.0f64
    i = 0usize
    while i <= r {
        numer += ad[i] * d[ext[i]]
        denom2 += sign * ad[i] / w[ext[i]]
        sign = 0.0f64 - sign
        i += 1usize
    }
    let delta = numer / denom2
    sign = 1.0f64
    i = 0usize
    while i <= r {
        y[i] = d[ext[i]] - sign * delta / w[ext[i]]
        sign = 0.0f64 - sign
        i += 1usize
    }
}

fn remez_compute_a(freq: f64, r: usize, ad: []const f64, x: []const f64, y: []const f64) -> f64 {
    var denom = 0.0f64
    var numer = 0.0f64
    let xc = math.cos[f64](6.2831853071795865f64 * freq)
    var i = 0usize
    while i <= r {
        var c = xc - x[i]
        if math.abs[f64](c) < 1.0e-7f64 {
            numer = y[i]
            denom = 1.0f64
            break
        }
        c = ad[i] / c
        denom += c
        numer += c * y[i]
        i += 1usize
    }
    ret numer / denom
}

// the extremal search; 0 on success, 2 for too few extremals, 3 for too many
fn remez_search(r: usize, ext: []usize, gridsize: usize, e: []const f64, found: []usize) -> usize {
    var k = 0usize
    if (e[0usize] > 0.0f64 && e[0usize] > e[1usize]) || (e[0usize] < 0.0f64 && e[0usize] < e[1usize]) {
        found[k] = 0usize
        k += 1usize
    }
    var i = 1usize
    while i + 1usize < gridsize {
        if (e[i] >= e[i - 1usize] && e[i] > e[i + 1usize] && e[i] > 0.0f64) || (e[i] <= e[i - 1usize] && e[i] < e[i + 1usize] && e[i] < 0.0f64) {
            if k >= 2usize * r { ret 3usize }
            found[k] = i
            k += 1usize
        }
        i += 1usize
    }
    let j = gridsize - 1usize
    if (e[j] > 0.0f64 && e[j] > e[j - 1usize]) || (e[j] < 0.0f64 && e[j] < e[j - 1usize]) {
        if k >= 2usize * r { ret 3usize }
        found[k] = j
        k += 1usize
    }
    if k < r + 1usize { ret 2usize }
    var extra = k - (r + 1usize)
    while extra > 0usize {
        var up = false
        if e[found[0usize]] > 0.0f64 { up = true }
        var l = 0usize
        var alt = true
        var jj = 1usize
        while jj < k {
            if math.abs[f64](e[found[jj]]) < math.abs[f64](e[found[l]]) { l = jj }
            if up && e[found[jj]] < 0.0f64 {
                up = false
            } else if !up && e[found[jj]] > 0.0f64 {
                up = true
            } else {
                alt = false
                break
            }
            jj += 1usize
        }
        if alt && extra == 1usize {
            if math.abs[f64](e[found[k - 1usize]]) < math.abs[f64](e[found[0usize]]) { l = k - 1usize } else { l = 0usize }
        }
        jj = l
        while jj + 1usize < k {
            found[jj] = found[jj + 1usize]
            jj += 1usize
        }
        k -= 1usize
        extra -= 1usize
    }
    i = 0usize
    while i <= r {
        ext[i] = found[i]
        i += 1usize
    }
    ret 0usize
}

// remez(n, f, a, w, ftype, density): n + 1 coefficients into out; ftype 1 bandpass, 2 differentiator, 3 hilbert; f and amp hold two entries per band, wt one
fn remez(arena: *mem.Arena, n: usize, f: []const f64, amp: []const f64, wt: []const f64, ftype: usize, density: usize, out: []f64) -> err {
    if n < 4usize || f.len % 2usize == 1usize || amp.len != f.len || wt.len * 2usize != f.len || density < 16usize { ret BadSpec }
    let numtaps = n + 1usize
    let numband = f.len / 2usize
    var symmetry = 1usize
    if ftype != 1usize { symmetry = 0usize }
    var r = numtaps / 2usize
    if numtaps % 2usize == 1usize && symmetry == 1usize { r += 1usize }
    var bands: [CAP]f64 = zero
    var i = 0usize
    while i < f.len {
        bands[i] = f[i] / 2.0f64
        i += 1usize
    }
    var gridsize = 0usize
    i = 0usize
    while i < numband {
        gridsize += usize(2.0f64 * f64(r) * f64(density) * (bands[2usize * i + 1usize] - bands[2usize * i]) + 0.5f64)
        i += 1usize
    }
    if symmetry == 0usize { gridsize -= 1usize }
    let room = gridsize + 4usize * numband + 8usize
    let (grid, e1) = mem.alloc[f64](arena, room)
    let (dd, e2) = mem.alloc[f64](arena, room)
    let (ww, e3) = mem.alloc[f64](arena, room)
    let (ee, e4) = mem.alloc[f64](arena, room)
    let (ext, e5) = mem.alloc[usize](arena, r + 2usize)
    let (taps, e6) = mem.alloc[f64](arena, numtaps + 2usize)
    let (xs, e7) = mem.alloc[f64](arena, r + 2usize)
    let (ys, e8) = mem.alloc[f64](arena, r + 2usize)
    let (ad, e9) = mem.alloc[f64](arena, r + 2usize)
    let (found, e10) = mem.alloc[usize](arena, 2usize * r + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Exhausted }
    i = 0usize
    while i < room {
        grid[i] = 0.0f64
        dd[i] = 0.0f64
        ww[i] = 1.0f64
        ee[i] = 0.0f64
        i += 1usize
    }
    // CreateDenseGrid
    let delf = 0.5f64 / (f64(density) * f64(r))
    var grid0 = bands[0usize]
    if symmetry == 0usize && delf > bands[0usize] { grid0 = delf }
    var j = 0usize
    var band = 0usize
    while band < numband {
        var lowf = bands[2usize * band]
        if band == 0usize { lowf = grid0 }
        let highf = bands[2usize * band + 1usize]
        let k = usize((highf - lowf) / delf + 0.5f64)
        var q = 0usize
        while q < k {
            if j >= room { break }
            dd[j] = amp[2usize * band] + f64(q) * (amp[2usize * band + 1usize] - amp[2usize * band]) / (f64(k) - 1.0f64)
            ww[j] = wt[band]
            grid[j] = lowf
            lowf += delf
            j += 1usize
            q += 1usize
        }
        if j > 0usize { grid[j - 1usize] = highf }
        band += 1usize
    }
    if symmetry == 0usize && grid[gridsize - 1usize] > (0.5f64 - delf) && numtaps % 2usize == 1usize {
        grid[gridsize - 1usize] = 0.5f64 - delf
    }
    i = 0usize
    while i <= r {
        ext[i] = i * (gridsize - 1usize) / r
        i += 1usize
    }
    if ftype == 2usize {
        i = 0usize
        while i < gridsize {
            if dd[i] > 0.0001f64 { ww[i] = ww[i] / grid[i] }
            i += 1usize
        }
    }
    let pi_c = 3.1415926535897932f64
    let pi2_c = 6.2831853071795865f64
    if symmetry == 1usize {
        if numtaps % 2usize == 0usize {
            i = 0usize
            while i < gridsize {
                let c = math.cos[f64](pi_c * grid[i])
                dd[i] = dd[i] / c
                ww[i] = ww[i] * c
                i += 1usize
            }
        }
    } else if numtaps % 2usize == 1usize {
        i = 0usize
        while i < gridsize {
            let c = math.sin[f64](pi2_c * grid[i])
            dd[i] = dd[i] / c
            ww[i] = ww[i] * c
            i += 1usize
        }
    } else {
        i = 0usize
        while i < gridsize {
            let c = math.sin[f64](pi_c * grid[i])
            dd[i] = dd[i] / c
            ww[i] = ww[i] * c
            i += 1usize
        }
    }
    var iter = 0usize
    while iter < 40usize {
        remez_calc_parms(r, ext, grid, dd, ww, ad, xs, ys)
        i = 0usize
        while i < gridsize {
            let av = remez_compute_a(grid[i], r, ad, xs, ys)
            ee[i] = ww[i] * (dd[i] - av)
            i += 1usize
        }
        let code = remez_search(r, ext, gridsize, ee, found)
        if code != 0usize { ret BadSpec }
        // isDone
        var mn = math.abs[f64](ee[ext[0usize]])
        var mx = mn
        i = 1usize
        while i <= r {
            let cur = math.abs[f64](ee[ext[i]])
            if cur < mn { mn = cur }
            if cur > mx { mx = cur }
            i += 1usize
        }
        if (mx - mn) / mx < 0.0001f64 { break }
        iter += 1usize
    }
    remez_calc_parms(r, ext, grid, dd, ww, ad, xs, ys)
    i = 0usize
    while i <= numtaps / 2usize {
        var c = 1.0f64
        if symmetry == 1usize {
            if numtaps % 2usize == 0usize { c = math.cos[f64](pi_c * f64(i) / f64(numtaps)) }
        } else if numtaps % 2usize == 1usize {
            c = math.sin[f64](pi2_c * f64(i) / f64(numtaps))
        } else {
            c = math.sin[f64](pi_c * f64(i) / f64(numtaps))
        }
        taps[i] = remez_compute_a(f64(i) / f64(numtaps), r, ad, xs, ys) * c
        i += 1usize
    }
    // FreqSample
    let nn = numtaps
    let mm = (f64(nn) - 1.0f64) / 2.0f64
    let mi = usize(mm)
    var idx = 0usize
    while idx < nn {
        var val = 0.0f64
        let xv = pi2_c * (f64(idx) - mm) / f64(nn)
        if symmetry == 1usize {
            val = taps[0usize]
            var kk = 1usize
            var top = nn / 2usize - 1usize
            if nn % 2usize == 1usize { top = mi }
            while kk <= top {
                val += 2.0f64 * taps[kk] * math.cos[f64](xv * f64(kk))
                kk += 1usize
            }
        } else {
            var top = nn / 2usize - 1usize
            if nn % 2usize == 1usize {
                top = mi
            } else {
                val = taps[nn / 2usize] * math.sin[f64](pi_c * (f64(idx) - mm))
            }
            var kk = 1usize
            while kk <= top {
                val += 2.0f64 * taps[kk] * math.sin[f64](xv * f64(kk))
                kk += 1usize
            }
        }
        out[idx] = val / f64(nn)
        idx += 1usize
    }
    ret ok
}

// ---- fir2 and fir1 with any window ----

// fir2(n, f, m, grid_n, ramp_n, window): n + 1 taps into out
fn fir2(a: *mem.Arena, n: usize, f: []const f64, m: []const f64, grid_n0: usize, ramp_n: f64, win: []const f64, out: []f64) -> err {
    let t = f.len
    var grid_n = grid_n0
    if 2usize * grid_n < n + 1usize {
        var p2 = 1usize
        while p2 < n + 1usize { p2 *= 2usize }
        grid_n = p2
    }
    let gn = f64(grid_n)
    let (fb, e1) = mem.alloc[f64](a, 3usize * t)
    if e1 != ok { ret e1 }
    let (mb, e2) = mem.alloc[f64](a, 3usize * t)
    if e2 != ok { ret e2 }
    let (fx, e3) = mem.alloc[f64](a, 3usize * t)
    if e3 != ok { ret e3 }
    var nf = t
    var i = 0usize
    while i < t {
        fx[i] = f[i]
        i += 1usize
    }
    if ramp_n > 0.0f64 {
        var extra = 0usize
        i = 0usize
        while i + 1usize < t {
            if f[i + 1usize] == f[i] {
                fx[i] = f[i] - ramp_n / gn / 2.0f64
                fx[i + 1usize] = f[i + 1usize] + ramp_n / gn / 2.0f64
                fx[t + extra] = f[i]
                extra += 1usize
            }
            i += 1usize
        }
        nf = t + extra
        i = 0usize
        while i < nf {
            if fx[i] < 0.0f64 { fx[i] = 0.0f64 }
            if fx[i] > 1.0f64 { fx[i] = 1.0f64 }
            i += 1usize
        }
        i = 1usize
        while i < nf {
            let tv = fx[i]
            var q = i
            while q > 0usize && fx[q - 1usize] > tv {
                fx[q] = fx[q - 1usize]
                q -= 1usize
            }
            fx[q] = tv
            i += 1usize
        }
        var w = 0usize
        i = 0usize
        while i < nf {
            if w == 0usize || fx[i] != fx[w - 1usize] {
                fx[w] = fx[i]
                w += 1usize
            }
            i += 1usize
        }
        nf = w
        i = 0usize
        while i < nf {
            mb[i] = sg.approx_ord(f, m, t, fx[i])
            fb[i] = fx[i]
            i += 1usize
        }
    } else {
        i = 0usize
        while i < t {
            fb[i] = f[i]
            mb[i] = m[i]
            i += 1usize
        }
    }
    let (grid, e4) = mem.alloc[f64](a, grid_n + 1usize)
    if e4 != ok { ret e4 }
    i = 0usize
    while i <= grid_n {
        grid[i] = sg.approx_ord(fb, mb, nf, f64(i) / gn)
        i += 1usize
    }
    let odd = n % 2usize == 1usize
    var big = 2usize * grid_n
    if odd { big = 4usize * grid_n }
    let (v, e5) = mem.alloc[f64](a, big)
    if e5 != ok { ret e5 }
    i = 0usize
    while i < big {
        v[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i <= grid_n {
        v[i] = grid[i]
        i += 1usize
    }
    i = 0usize
    while i + 1usize < grid_n {
        v[big - 1usize - i] = grid[i + 1usize]
        i += 1usize
    }
    var k = 0usize
    while k <= n {
        var idx = 0usize
        if !odd {
            let fl = (n + 1usize) / 2usize
            if k < fl { idx = big - fl + k } else { idx = k - fl }
        } else {
            let h2 = (n + 1usize) / 2usize
            if k < h2 { idx = big - n + 2usize * k } else { idx = 2usize * (k - h2) + 1usize }
        }
        var s = 0.0f64
        var j = 0usize
        while j < big {
            s += v[j] * math.cos[f64](2.0f64 * pi_value() * f64((j * idx) % big) / f64(big))
            j += 1usize
        }
        s = s / f64(big)
        if odd { s = 2.0f64 * s }
        out[k] = s * win[k]
        k += 1usize
    }
    ret ok
}

// interp1(x, y, xi, method): linear 0, nearest 1, pchip 2, cubic 3, spline 4; NaN outside the range of x
fn lookup_count(x: []const f64, lo: usize, hi: usize, v: f64) -> usize {
    // the number of x[lo..hi] that are <= v
    var c = 0usize
    var i = lo
    while i < hi {
        if x[i] <= v { c += 1usize }
        i += 1usize
    }
    ret c
}

fn pchst(arg1: f64, arg2: f64) -> f64 {
    if arg1 == 0.0f64 || arg2 == 0.0f64 { ret 0.0f64 }
    var s1 = 1.0f64
    if arg1 < 0.0f64 { s1 = -1.0f64 }
    var s2 = 1.0f64
    if arg2 < 0.0f64 { s2 = -1.0f64 }
    ret s1 * s2
}

// SLATEC DPCHIM: the monotone piecewise cubic Hermite derivatives
fn pchim(n: usize, x: []const f64, f: []const f64, d: []f64) -> err {
    if n < 2usize { ret BadSpec }
    var i = 1usize
    while i < n {
        if x[i] <= x[i - 1usize] { ret BadSpec }
        i += 1usize
    }
    let nless1 = n - 1usize
    var h1 = x[1usize] - x[0usize]
    var del1 = (f[1usize] - f[0usize]) / h1
    var dsave = del1
    if nless1 <= 1usize {
        d[0usize] = del1
        d[n - 1usize] = del1
        ret ok
    }
    var h2 = x[2usize] - x[1usize]
    var del2 = (f[2usize] - f[1usize]) / h2
    var hsum = h1 + h2
    var w1 = (h1 + hsum) / hsum
    var w2 = 0.0f64 - h1 / hsum
    d[0usize] = w1 * del1 + w2 * del2
    if pchst(d[0usize], del1) <= 0.0f64 {
        d[0usize] = 0.0f64
    } else if pchst(del1, del2) < 0.0f64 {
        let dmax = 3.0f64 * del1
        if math.abs[f64](d[0usize]) > math.abs[f64](dmax) { d[0usize] = dmax }
    }
    i = 2usize
    while i <= nless1 {
        if i != 2usize {
            h1 = h2
            h2 = x[i] - x[i - 1usize]
            hsum = h1 + h2
            del1 = del2
            del2 = (f[i] - f[i - 1usize]) / h2
        }
        d[i - 1usize] = 0.0f64
        let zz = pchst(del1, del2)
        if zz < 0.0f64 {
            dsave = del2
        } else if zz > 0.0f64 {
            let hsumt3 = hsum + hsum + hsum
            w1 = (hsum + h1) / hsumt3
            w2 = (hsum + h2) / hsumt3
            var dmax = math.abs[f64](del1)
            if math.abs[f64](del2) > dmax { dmax = math.abs[f64](del2) }
            var dmin = math.abs[f64](del1)
            if math.abs[f64](del2) < dmin { dmin = math.abs[f64](del2) }
            let drat1 = del1 / dmax
            let drat2 = del2 / dmax
            d[i - 1usize] = dmin / (w1 * drat1 + w2 * drat2)
        } else {
            if del2 != 0.0f64 { dsave = del2 }
        }
        i += 1usize
    }
    w1 = 0.0f64 - h2 / hsum
    w2 = (h2 + hsum) / hsum
    d[n - 1usize] = w1 * del1 + w2 * del2
    if pchst(d[n - 1usize], del2) <= 0.0f64 {
        d[n - 1usize] = 0.0f64
    } else if pchst(del1, del2) < 0.0f64 {
        let dmax = 3.0f64 * del2
        if math.abs[f64](d[n - 1usize]) > math.abs[f64](dmax) { d[n - 1usize] = dmax }
    }
    let _ = dsave
    ret ok
}

// pchip(x, y, xi) for increasing x with at least 3 points
fn pchip(a: *mem.Arena, x: []const f64, y: []const f64, xi: []const f64, out: []f64) -> err {
    let n = x.len
    let (b, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    let e2 = pchim(n, x, y, b)
    if e2 != ok { ret e2 }
    var q = 0usize
    while q < xi.len {
        let idx = lookup_count(x, 1usize, n - 1usize, xi[q])
        let h = x[idx + 1usize] - x[idx]
        let dy = y[idx + 1usize] - y[idx]
        let c = (0.0f64 - (b[idx + 1usize] + 2.0f64 * b[idx])) / h + 3.0f64 * dy / (h * h)
        let d = (b[idx] + b[idx + 1usize]) / (h * h) - 2.0f64 * dy / math.pow[f64](h, 3.0f64)
        let dx = xi[q] - x[idx]
        var yi = d
        yi = yi * dx + c
        yi = yi * dx + b[idx]
        yi = yi * dx + y[idx]
        out[q] = yi
        q += 1usize
    }
    ret ok
}

fn interp1(a: *mem.Arena, x: []const f64, y: []const f64, xi: []const f64, method: usize, out: []f64) -> err {
    let nx = x.len
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 0usize
    while i < nx {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    var q = 0usize
    while q < xi.len {
        out[q] = nan_value()
        q += 1usize
    }
    // the points inside the range, in order
    let (pos, e0) = mem.alloc[usize](a, xi.len + 1usize)
    if e0 != ok { ret e0 }
    var cnt = 0usize
    q = 0usize
    while q < xi.len {
        if xi[q] >= lo && xi[q] <= hi {
            pos[cnt] = q
            cnt += 1usize
        }
        q += 1usize
    }
    if cnt == 0usize { ret ok }
    let (sub, e1) = mem.alloc[f64](a, cnt)
    let (res, e2) = mem.alloc[f64](a, cnt)
    if e1 != ok || e2 != ok { ret mem.Exhausted }
    q = 0usize
    while q < cnt {
        sub[q] = xi[pos[q]]
        q += 1usize
    }
    if method == 0usize {
        if nx < 2usize || y.len < 2usize { ret BadSpec }
        q = 0usize
        while q < cnt {
            var idx = 0usize
            if nx > 2usize { idx = lookup_count(x, 1usize, nx - 1usize, sub[q]) }
            let dxv = x[idx + 1usize] - x[idx]
            let s = (sub[q] - x[idx]) / dxv
            res[q] = s * (y[idx + 1usize] - y[idx]) + y[idx]
            q += 1usize
        }
    } else if method == 1usize {
        q = 0usize
        while q < cnt {
            // knots c(x[1], x + c(diff(x) / 2, 0)) with values c(y[1], y)
            let v = sub[q]
            let nk = nx + 1usize
            var lo_i = 0usize
            var hi_i = nk - 1usize
            while lo_i + 1usize < hi_i {
                let mid = (lo_i + hi_i) / 2usize
                var kv = 0.0f64
                if mid == 0usize { kv = x[0usize] } else if mid < nx { kv = x[mid - 1usize] + (x[mid] - x[mid - 1usize]) / 2.0f64 } else { kv = x[nx - 1usize] }
                if v < kv { hi_i = mid } else { lo_i = mid }
            }
            var khi = 0.0f64
            if hi_i == 0usize { khi = x[0usize] } else if hi_i < nx { khi = x[hi_i - 1usize] + (x[hi_i] - x[hi_i - 1usize]) / 2.0f64 } else { khi = x[nx - 1usize] }
            var klo = 0.0f64
            if lo_i == 0usize { klo = x[0usize] } else if lo_i < nx { klo = x[lo_i - 1usize] + (x[lo_i] - x[lo_i - 1usize]) / 2.0f64 } else { klo = x[nx - 1usize] }
            var yhi = y[0usize]
            if hi_i >= 1usize { yhi = y[hi_i - 1usize] }
            var ylo = y[0usize]
            if lo_i >= 1usize { ylo = y[lo_i - 1usize] }
            if v == khi { res[q] = yhi } else if v == klo { res[q] = ylo } else { res[q] = yhi }
            q += 1usize
        }
    } else if method == 2usize {
        let e3 = pchip(a, x, y, sub[0usize..cnt], res)
        if e3 != ok { ret e3 }
    } else if method == 3usize {
        if nx < 4usize || y.len < 4usize { ret BadSpec }
        let m3 = nx - 3usize
        let (ca, e3) = mem.alloc[f64](a, m3)
        let (cb, e4) = mem.alloc[f64](a, m3)
        let (cc, e5) = mem.alloc[f64](a, m3)
        let (cd, e6) = mem.alloc[f64](a, m3)
        let (d1, e7) = mem.alloc[f64](a, nx)
        let (d2, e8) = mem.alloc[f64](a, nx)
        let (d3, e9) = mem.alloc[f64](a, nx)
        if e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Exhausted }
        i = 0usize
        while i + 1usize < nx {
            d1[i] = y[i + 1usize] - y[i]
            i += 1usize
        }
        i = 0usize
        while i + 2usize < nx {
            d2[i] = d1[i + 1usize] - d1[i]
            i += 1usize
        }
        i = 0usize
        while i + 3usize < nx {
            d3[i] = d2[i + 1usize] - d2[i]
            i += 1usize
        }
        i = 0usize
        while i < m3 {
            let dxi = x[i + 1usize] - x[i]
            let dx2 = x[i + 1usize] * x[i + 1usize] - x[i] * x[i]
            let dx3 = math.pow[f64](x[i + 1usize], 3.0f64) - math.pow[f64](x[i], 3.0f64)
            ca[i] = d3[i] / math.pow[f64](dxi, 3.0f64) / 6.0f64
            cb[i] = (d2[i] / (dxi * dxi) - 6.0f64 * ca[i] * x[i + 1usize]) / 2.0f64
            cc[i] = (d1[i] - ca[i] * dx3 - cb[i] * dx2) / dxi
            cd[i] = y[i] - ((ca[i] * x[i] + cb[i]) * x[i] + cc[i]) * x[i]
            i += 1usize
        }
        q = 0usize
        while q < cnt {
            let idx = lookup_count(x, 2usize, nx - 2usize, sub[q])
            res[q] = ((ca[idx] * sub[q] + cb[idx]) * sub[q] + cc[idx]) * sub[q] + cd[idx]
            q += 1usize
        }
    } else {
        let (sb, e3) = mem.alloc[f64](a, nx)
        let (sc, e4) = mem.alloc[f64](a, nx)
        let (sd2, e5) = mem.alloc[f64](a, nx)
        if e3 != ok || e4 != ok || e5 != ok { ret mem.Exhausted }
        spl.fmm_spline(nx, x, y, sb, sc, sd2)
        q = 0usize
        while q < cnt {
            res[q] = spl.spline_eval(nx, x, y, sb, sc, sd2, sub[q])
            q += 1usize
        }
    }
    q = 0usize
    while q < cnt {
        out[pos[q]] = res[q]
        q += 1usize
    }
    ret ok
}

// fir1(n, w, type, window, scale): type 0 low, 1 high, 2 stop, 3 pass, 4 DC-0, 5 DC-1; a window of n + 1 points (resampled when n is raised); returns the number of taps (n + 1, or n + 2 when n was odd for a type that passes at Nyquist); out needs n + 2 entries
fn fir1(a: *mem.Arena, n0: usize, w: []const f64, ty: usize, win0: []const f64, scale: bool, out: []f64) -> (usize, err) {
    var n = n0
    let bands = w.len + 1usize
    let ft = ty == 0usize || ty == 2usize || ty == 5usize
    let (f, e1) = mem.alloc[f64](a, 2usize * bands)
    let (m, e2) = mem.alloc[f64](a, 2usize * bands)
    if e1 != ok || e2 != ok { ret (0usize, mem.Exhausted) }
    var i = 0usize
    while i < 2usize * bands {
        f[i] = 0.0f64
        m[i] = 0.0f64
        i += 1usize
    }
    f[2usize * bands - 1usize] = 1.0f64
    i = 0usize
    while i + 1usize < bands {
        f[2usize * i + 1usize] = w[i]
        f[2usize * i + 2usize] = w[i]
        i += 1usize
    }
    i = 0usize
    while i < bands {
        var mv = 0.0f64
        if ft {
            if (i + 1usize) % 2usize == 1usize { mv = 1.0f64 }
        } else if (i + 2usize) % 2usize == 1usize { mv = 1.0f64 }
        m[2usize * i] = mv
        m[2usize * i + 1usize] = mv
        i += 1usize
    }
    var win = win0
    if n % 2usize == 1usize && m[2usize * bands - 1usize] == 1.0f64 {
        n += 1usize
        let mm = win0.len
        let (nw, e3) = mem.alloc[f64](a, mm + 1usize)
        if e3 != ok { ret (0usize, e3) }
        if mm == 1usize {
            nw[0usize] = win0[0usize]
            nw[1usize] = win0[0usize]
        } else {
            let (xo, e4) = mem.alloc[f64](a, mm)
            let (xn, e5) = mem.alloc[f64](a, mm + 1usize)
            if e4 != ok || e5 != ok { ret (0usize, mem.Exhausted) }
            i = 0usize
            while i < mm {
                xo[i] = f64(i) / f64(mm - 1usize)
                i += 1usize
            }
            i = 0usize
            while i <= mm {
                xn[i] = f64(i) / f64(mm)
                i += 1usize
            }
            var meth = 4usize
            if mm < 4usize { meth = 0usize }
            let e6 = interp1(a, xo, win0, xn, meth, nw)
            if e6 != ok { ret (0usize, e6) }
        }
        win = nw
    }
    let e7 = fir2(a, n, f, m, 512usize, 2.0f64, win, out)
    if e7 != ok { ret (0usize, e7) }
    if scale {
        var wo = 0.0f64
        if m[0usize] == 1.0f64 { wo = (f[1usize] - f[0usize]) / 2.0f64 } else { wo = f[2usize] + (f[3usize] - f[2usize]) / 2.0f64 }
        let (vr, vi) = polyval_at(out[0usize..n + 1usize], math.cos[f64](pi_value() * wo), 0.0f64 - math.sin[f64](pi_value() * wo))
        let renorm = 1.0f64 / math.sqrt[f64](vr * vr + vi * vi)
        i = 0usize
        while i <= n {
            out[i] = renorm * out[i]
            i += 1usize
        }
    }
    ret (n + 1usize, ok)
}

// the helper that applies the window kind to fir1: kind as in window()
fn fir1_kind(a: *mem.Arena, n: usize, w: []const f64, ty: usize, kind: usize, par: f64, out: []f64) -> (usize, err) {
    let (win, e1) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok { ret (0usize, e1) }
    let e2 = window(a, kind, n + 1usize, par, win)
    if e2 != ok { ret (0usize, e2) }
    let (len, e3) = fir1(a, n, w, ty, win, true, out)
    ret (len, e3)
}

// decimate(x, q, n, ftype): ftype 0 iir (filtfilt of a Chebyshev type I of order n, 0.05 dB, cut-off 0.8 / q), 1 fir (fir1(n, 1 / q) through fftfilt); out holds ceiling(len / q) entries
fn decimate(a: *mem.Arena, x: []const f64, q: usize, n: usize, ftype: usize, out: []f64) -> err {
    let (y, e1) = mem.alloc[f64](a, x.len)
    if e1 != ok { ret e1 }
    if ftype == 1usize {
        let (b, e2) = mem.alloc[f64](a, n + 2usize)
        if e2 != ok { ret e2 }
        var cut: [1]f64 = zero
        cut[0usize] = 1.0f64 / f64(q)
        let (len, e3) = fir1_kind(a, n, cut[0usize..1usize], 0usize, 0usize, 0.0f64, b)
        if e3 != ok { ret e3 }
        fftfilt(b[0usize..len], x, y)
    } else {
        let (b, e2) = mem.alloc[f64](a, n + 1usize)
        let (aa, e3) = mem.alloc[f64](a, n + 1usize)
        if e2 != ok || e3 != ok { ret mem.Exhausted }
        var cut: [1]f64 = zero
        cut[0usize] = 0.8f64 / f64(q)
        let e4 = design(1usize, n, 0.05f64, 0.0f64, cut[0usize..1usize], 0usize, true, b, aa)
        if e4 != ok { ret e4 }
        let e5 = sg.filtfilt(a, b, aa, x, y)
        if e5 != ok { ret e5 }
    }
    var i = 0usize
    var k = 0usize
    while i < x.len {
        out[k] = y[i]
        k += 1usize
        i += q
    }
    ret ok
}

// the length of resample(x, p, q, d)
fn resample_length(len: usize, p: usize, q: usize) -> usize {
    let r = f64(p) / f64(q)
    let by = 1.0f64 / r
    let to = f64(len) + 1.0f64 - by
    let del = to - 1.0f64
    var mx = to
    if 1.0f64 > mx { mx = 1.0f64 }
    if math.abs[f64](del) / mx < 100.0f64 * 2.220446049250313e-16f64 { ret 1usize }
    ret usize(math.floor[f64](del / by + 1.0e-10f64)) + 1usize
}

// resample(x, p, q, d)
fn resample(a: *mem.Arena, x: []const f64, p: usize, q: usize, d: usize, out: []f64) -> err {
    let r = f64(p) / f64(q)
    var src = x
    if r < 1.0f64 {
        let (b, e1) = mem.alloc[f64](a, 2usize * d + 3usize)
        if e1 != ok { ret e1 }
        var cut: [1]f64 = zero
        cut[0usize] = r
        let (len, e2) = fir1_kind(a, 2usize * d + 1usize, cut[0usize..1usize], 0usize, 0usize, 0.0f64, b)
        if e2 != ok { ret e2 }
        let (y, e3) = mem.alloc[f64](a, x.len)
        if e3 != ok { ret e3 }
        fftfilt(b[0usize..len], x, y)
        src = y
    }
    let cnt = resample_length(x.len, p, q)
    let by = 1.0f64 / r
    let to = f64(x.len) + 1.0f64 - by
    let (padded, e4) = mem.alloc[f64](a, x.len + 2usize * d)
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < padded.len {
        padded[i] = 0.0f64
        if i >= d && i < d + x.len { padded[i] = src[i - d] }
        i += 1usize
    }
    var k = 0usize
    while k < cnt {
        var tv = 1.0f64 + f64(k) * by
        if cnt > 1usize && tv > to { tv = to }
        let idx = math.trunc[f64](tv)
        let frac = tv - idx
        var s = 0.0f64
        var j = 0usize
        while j <= 2usize * d {
            let ii = f64(j) - f64(d)
            let wv = sinc_value(frac - ii) * (0.5f64 + 0.5f64 * math.cos[f64](pi_value() * (frac - ii) / (f64(d) + 0.5f64)))
            let at = usize(idx + ii + f64(d)) - 1usize
            s += padded[at] * wv
            j += 1usize
        }
        out[k] = s
        k += 1usize
    }
    ret ok
}

// interp(x, q, n, Wc): the interpolated signal of x.len * q samples
fn interp(a: *mem.Arena, x: []const f64, q: usize, n: usize, wc: f64, out: []f64) -> err {
    let total = x.len * q + q * n + 1usize
    let (y, e1) = mem.alloc[f64](a, total)
    let (z, e2) = mem.alloc[f64](a, total)
    let (b, e3) = mem.alloc[f64](a, 2usize * q * n + 3usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Exhausted }
    var i = 0usize
    while i < total {
        y[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < x.len {
        y[i * q] = x[i]
        i += 1usize
    }
    var cut: [1]f64 = zero
    cut[0usize] = wc / f64(q)
    let (len, e4) = fir1_kind(a, 2usize * q * n + 1usize, cut[0usize..1usize], 0usize, 0usize, 0.0f64, b)
    if e4 != ok { ret e4 }
    fftfilt(b[0usize..len], y, z)
    i = 0usize
    while i < x.len * q {
        out[i] = f64(q) * z[i + q * n + 1usize]
        i += 1usize
    }
    ret ok
}

// sgolay(p, n, m, ts): the n x n filter matrix, row by row, into fm
fn sgolay(a: *mem.Arena, p: usize, n: usize, m: usize, ts: f64, fm: []f64) -> err {
    if n % 2usize != 1usize || p >= n { ret BadSpec }
    let q = p + 1usize
    let k = n / 2usize
    let (cq, e1) = mem.alloc[f64](a, n * q)
    let (rr, e2) = mem.alloc[f64](a, q * q)
    let (yy, e3) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Exhausted }
    var row = 0usize
    while row <= k {
        // Ce[i, j] = (i + 1 - (row + 1))^j orthogonalised column by column
        var j = 0usize
        while j < q {
            var i = 0usize
            while i < n {
                let tt = f64(i) - f64(row)
                var v = 1.0f64
                if j == 1usize { v = tt } else if j == 2usize { v = tt * tt } else if j > 2usize { v = math.pow[f64](tt, f64(j)) }
                cq[i * q + j] = v
                i += 1usize
            }
            j += 1usize
        }
        var c = 0usize
        while c < q * q {
            rr[c] = 0.0f64
            c += 1usize
        }
        j = 0usize
        while j < q {
            var pass = 0usize
            while pass < 2usize {
                var l = 0usize
                while l < j {
                    var dot = 0.0f64
                    var i = 0usize
                    while i < n {
                        dot += cq[i * q + l] * cq[i * q + j]
                        i += 1usize
                    }
                    i = 0usize
                    while i < n {
                        cq[i * q + j] = cq[i * q + j] - dot * cq[i * q + l]
                        i += 1usize
                    }
                    rr[l * q + j] += dot
                    l += 1usize
                }
                pass += 1usize
            }
            var nrm = 0.0f64
            var i = 0usize
            while i < n {
                nrm += cq[i * q + j] * cq[i * q + j]
                i += 1usize
            }
            nrm = math.sqrt[f64](nrm)
            rr[j * q + j] = nrm
            i = 0usize
            while i < n {
                cq[i * q + j] = cq[i * q + j] / nrm
                i += 1usize
            }
            j += 1usize
        }
        // R^T y = e_m
        j = 0usize
        while j < q {
            var s = 0.0f64
            if j == m { s = 1.0f64 }
            var l = 0usize
            while l < j {
                s -= rr[l * q + j] * yy[l]
                l += 1usize
            }
            yy[j] = s / rr[j * q + j]
            j += 1usize
        }
        var i = 0usize
        while i < n {
            var s = 0.0f64
            j = 0usize
            while j < q {
                s += yy[j] * cq[i * q + j]
                j += 1usize
            }
            fm[row * n + i] = s
            i += 1usize
        }
        row += 1usize
    }
    var sgn = 1.0f64
    if m % 2usize == 1usize { sgn = -1.0f64 }
    var jj = 1usize
    while jj <= k {
        var c = 0usize
        while c < n {
            fm[(k + jj) * n + c] = sgn * fm[(k - jj) * n + (n - 1usize - c)]
            c += 1usize
        }
        jj += 1usize
    }
    if m > 0usize {
        var fact = 1.0f64
        var t = 1usize
        while t <= m {
            fact = fact * f64(t)
            t += 1usize
        }
        let scale = math.pow[f64](ts, f64(m))
        var c = 0usize
        while c < n * n {
            fm[c] = fm[c] * fact / scale
            c += 1usize
        }
    }
    ret ok
}

// sgolayfilt(x, p, n, m, ts)
fn sgolayfilt(a: *mem.Arena, x: []const f64, p: usize, n: usize, m: usize, ts: f64, out: []f64) -> err {
    let len = x.len
    let (fm, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    let e2 = sgolay(a, p, n, m, ts, fm)
    if e2 != ok { ret e2 }
    let k = n / 2usize
    var i = 0usize
    while i < k {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += fm[i * n + j] * x[j]
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
    // z = filter(F[k + 1, n:1], 1, x), kept from n to len
    i = n - 1usize
    while i < len {
        var s = 0.0f64
        var j = 0usize
        while j < n && j <= i {
            s += fm[k * n + (n - 1usize - j)] * x[i - j]
            j += 1usize
        }
        out[i - k] = s
        i += 1usize
    }
    i = 0usize
    while i < k {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += fm[(k + 1usize + i) * n + j] * x[len - n + j]
            j += 1usize
        }
        out[len - k + i] = s
        i += 1usize
    }
    ret ok
}

// ---- order estimators ----

// buttord(Wp, Ws, Rp, Rs): returns (n, type) with wc holding the cut-off(s); type 0 low, 1 high, 2 stop, 3 pass
fn buttord(wp0: []const f64, ws0: []const f64, rp: f64, rs: f64, wc: []f64) -> (usize, usize) {
    let tt = 2.0f64
    let cnt = wp0.len
    var wp: [2]f64 = zero
    var ws: [2]f64 = zero
    var st: [2]bool = zero
    var i = 0usize
    var any_stop = false
    while i < cnt {
        wp[i] = wp0[i]
        ws[i] = ws0[i]
        if wp[i] > ws[i] {
            st[i] = true
            any_stop = true
            wp[i] = 1.0f64 - wp[i]
            ws[i] = 1.0f64 - ws[i]
        }
        i += 1usize
    }
    var ty = 0usize
    if cnt == 2usize {
        ty = 3usize
        if any_stop { ty = 2usize }
    } else if any_stop {
        ty = 1usize
    }
    let qs = math.log[f64](math.pow[f64](10.0f64, rs / 10.0f64) - 1.0f64)
    let qp = math.log[f64](math.pow[f64](10.0f64, rp / 10.0f64) - 1.0f64)
    var mx = -1.0e300f64
    i = 0usize
    while i < cnt {
        let wsw = (2.0f64 / tt) * math.tan[f64](pi_value() * ws[i] / tt)
        let wpw = (2.0f64 / tt) * math.tan[f64](pi_value() * wp[i] / tt)
        ws[i] = wsw
        wp[i] = wpw
        let v = 0.5f64 * (qs - qp) / math.log[f64](wsw / wpw)
        if v > mx { mx = v }
        i += 1usize
    }
    let n = math.ceil[f64](mx / f64(cnt))
    i = 0usize
    while i < cnt {
        var c = math.exp[f64](math.log[f64](wp[i]) - qp / 2.0f64 / n)
        c = math.atan[f64](tt / 2.0f64 * c) * tt / pi_value()
        if st[i] { c = 1.0f64 - c }
        wc[i] = c
        i += 1usize
    }
    ret (usize(n), ty)
}

// cheb1ord(Wp, Ws, Rp, Rs): (n, type)
fn cheb1ord(wp0: []const f64, ws0: []const f64, rp: f64, rs: f64) -> (usize, usize) {
    let tt = 2.0f64
    let cnt = wp0.len
    var wp: [2]f64 = zero
    var ws: [2]f64 = zero
    var i = 0usize
    while i < cnt {
        ws[i] = (2.0f64 / tt) * math.tan[f64](pi_value() * ws0[i] / tt)
        wp[i] = (2.0f64 / tt) * math.tan[f64](pi_value() * wp0[i] / tt)
        i += 1usize
    }
    var wa = 0.0f64
    var ty = 0usize
    if wp[0usize] < ws[0usize] {
        wa = ws[0usize] / wp[0usize]
        ty = 0usize
    } else if cnt == 1usize {
        ty = 1usize
        wa = wp[0usize] / ws[0usize]
    } else {
        ty = 3usize
        var best = 1.0e300f64
        i = 0usize
        while i < cnt {
            let v = math.abs[f64]((ws[i] * ws[i] - wp[0usize] * wp[1usize]) / (ws[i] * (wp[0usize] - wp[1usize])))
            if v < best { best = v }
            i += 1usize
        }
        wa = best
    }
    wa = math.abs[f64](wa)
    let stop_atten = math.pow[f64](10.0f64, math.abs[f64](rs) / 10.0f64)
    let pass_atten = math.pow[f64](10.0f64, math.abs[f64](rp) / 10.0f64)
    let z = math.sqrt[f64]((stop_atten - 1.0f64) / (pass_atten - 1.0f64))
    let acz = math.log[f64](z + math.sqrt[f64](z * z - 1.0f64))
    let acw = math.log[f64](wa + math.sqrt[f64](wa * wa - 1.0f64))
    ret (usize(math.ceil[f64](acz / acw)), ty)
}

// ellipord(Wp, Ws, Rp, Rs): (n, type)
fn ellipord(wp0: []const f64, ws0: []const f64, rp: f64, rs: f64) -> (f64, usize) {
    let tt = 2.0f64
    var wpw: [2]f64 = zero
    var wsw: [2]f64 = zero
    var i = 0usize
    while i < wp0.len {
        wpw[i] = math.tan[f64](pi_value() * wp0[i] / tt)
        i += 1usize
    }
    i = 0usize
    while i < ws0.len {
        wsw[i] = math.tan[f64](pi_value() * ws0[i] / tt)
        i += 1usize
    }
    var ty = 0usize
    var wpv = 1.0f64
    var wsv = 1.0f64
    if wp0.len == 2usize && ws0.len == 2usize {
        ty = 3usize
        let w02 = wpw[0usize] * wpw[1usize]
        let w3 = w02 / wsw[1usize]
        let w4 = w02 / wsw[0usize]
        if w3 > wsw[0usize] {
            wsv = (wsw[1usize] - w3) / (wpw[1usize] - wpw[0usize])
        } else if w4 < wsw[1usize] {
            wsv = (w4 - wsw[0usize]) / (wpw[1usize] - wpw[0usize])
        } else {
            wsv = (wsw[1usize] - wsw[0usize]) / (wpw[1usize] - wpw[0usize])
        }
    } else if wp0.len == 2usize {
        ty = 3usize
        let w02 = wpw[0usize] * wpw[1usize]
        if wsw[0usize] > wpw[1usize] {
            let w3 = w02 / wsw[0usize]
            wsv = (wsw[0usize] - w3) / (wpw[1usize] - wpw[0usize])
        } else {
            let w4 = w02 / wsw[0usize]
            wsv = (w4 - wsw[0usize]) / (wpw[1usize] - wpw[0usize])
        }
    } else {
        if wpw[0usize] < wsw[0usize] { ty = 0usize } else { ty = 1usize }
        wpv = wpw[0usize]
        wsv = wsw[0usize]
    }
    let k = wpv / wsv
    let k1 = math.sqrt[f64](1.0f64 - k * k)
    let q0 = 0.5f64 * ((1.0f64 - math.sqrt[f64](k1)) / (1.0f64 + math.sqrt[f64](k1)))
    let q = q0 + 2.0f64 * math.pow[f64](q0, 5.0f64) + 15.0f64 * math.pow[f64](q0, 9.0f64) + 150.0f64 * math.pow[f64](q0, 13.0f64)
    let dd = (math.pow[f64](10.0f64, 0.1f64 * rs) - 1.0f64) / (math.pow[f64](10.0f64, 0.1f64 * rp) - 1.0f64)
    ret (math.ceil[f64](math.log10[f64](16.0f64 * dd) / math.log10[f64](1.0f64 / q)), ty)
}

// kaiserord(f, m, dev, Fs): returns (n, type, beta); w gets the cut-off(s)
fn kaiserord(f: []const f64, m: []const f64, dev: f64, fs: f64, w: []f64) -> (usize, usize, f64) {
    let nw = f.len / 2usize
    var i = 0usize
    while i < nw {
        w[i] = (f[2usize * i] + f[2usize * i + 1usize]) / fs
        i += 1usize
    }
    var ty = 0usize
    if nw == 1usize {
        if m[0usize] > m[1usize] { ty = 0usize } else { ty = 1usize }
    } else if nw == 2usize {
        if m[0usize] > m[1usize] { ty = 2usize } else { ty = 3usize }
    } else if m[0usize] > m[1usize] {
        ty = 5usize
    } else {
        ty = 4usize
    }
    let att = -20.0f64 * math.log10[f64](dev)
    var beta = 0.0f64
    if att > 50.0f64 {
        beta = 0.1102f64 * (att - 8.7f64)
    } else if att >= 21.0f64 {
        beta = 0.5842f64 * math.pow[f64](att - 21.0f64, 0.4f64) + 0.07886f64 * (att - 21.0f64)
    }
    var mind = 1.0e300f64
    i = 0usize
    while i < nw {
        let v = f[2usize * i + 1usize] - f[2usize * i]
        if v < mind { mind = v }
        i += 1usize
    }
    let dw = 2.0f64 * pi_value() * mind / fs
    var n = math.ceil[f64]((att - 8.0f64) / (2.285f64 * dw))
    if n < 1.0f64 { n = 1.0f64 }
    var nu = usize(n)
    if (m[0usize] > m[1usize]) == (nw % 2usize == 0usize) && nu % 2usize == 1usize { nu += 1usize }
    ret (nu, ty, beta)
}

// chirp(t, f0, t1, f1, form, phase): form 0 linear, 1 quadratic, 2 logarithmic
fn chirp(t: []const f64, f0: f64, t1: f64, f1: f64, form: usize, phase0: f64, out: []f64) {
    let phase = 2.0f64 * pi_value() * phase0 / 360.0f64
    var i = 0usize
    while i < t.len {
        let tv = t[i]
        if form == 0usize {
            let aa = pi_value() * (f1 - f0) / t1
            let bb = 2.0f64 * pi_value() * f0
            out[i] = math.cos[f64](aa * (tv * tv) + bb * tv + phase)
        } else if form == 1usize {
            let aa = (2.0f64 / 3.0f64 * pi_value() * (f1 - f0) / t1 / t1)
            let bb = 2.0f64 * pi_value() * f0
            out[i] = math.cos[f64](aa * math.pow[f64](tv, 3.0f64) + bb * tv + phase)
        } else {
            let aa = 2.0f64 * pi_value() * t1 / math.log[f64](f1 - f0)
            let bb = 2.0f64 * pi_value() * f0
            let xx = math.pow[f64](f1 - f0, 1.0f64 / t1)
            out[i] = math.cos[f64](aa * math.pow[f64](xx, tv) + bb * tv + phase)
        }
        i += 1usize
    }
}

// spencer(x): the 15-point Spencer filter, NaN at the seven samples at each end
fn spencer(x: []const f64, out: []f64) {
    var c: [15]f64 = zero
    c[0usize] = -3.0f64
    c[1usize] = -6.0f64
    c[2usize] = -5.0f64
    c[3usize] = 3.0f64
    c[4usize] = 21.0f64
    c[5usize] = 46.0f64
    c[6usize] = 67.0f64
    c[7usize] = 74.0f64
    c[8usize] = 67.0f64
    c[9usize] = 46.0f64
    c[10usize] = 21.0f64
    c[11usize] = 3.0f64
    c[12usize] = -5.0f64
    c[13usize] = -6.0f64
    c[14usize] = -3.0f64
    var i = 0usize
    while i < 15usize {
        c[i] = c[i] / 320.0f64
        i += 1usize
    }
    i = 0usize
    while i < x.len {
        out[i] = nan_value()
        if i >= 14usize {
            var s = 0.0f64
            var j = 0usize
            while j < 15usize {
                s += c[j] * x[i - j]
                j += 1usize
            }
            out[i - 7usize] = s
        }
        i += 1usize
    }
}

// roots(x): polyroot(rev(x)) for the polynomial x, highest power first; returns the degree
fn roots(a: *mem.Arena, x: []const f64, re: []f64, im: []f64) -> i64 {
    let (rev, e1) = mem.alloc[f64](a, x.len)
    if e1 != ok { ret 0i64 - 1i64 }
    var i = 0usize
    while i < x.len {
        rev[i] = x[x.len - 1usize - i]
        i += 1usize
    }
    ret pk.polyroot_c(a, rev, re, im)
}

// as.Arma(Zpg): b = Re(gain * poly(zero)), a = Re(poly(pole)); b has nz + 1 entries, aa np + 1
fn zpg_to_arma(zr: []const f64, zi: []const f64, pre: []const f64, pim: []const f64, gain: f64, b: []f64, aa: []f64) {
    var cr: [CAP]f64 = zero
    var ci: [CAP]f64 = zero
    poly_roots_cx(zr, zi, zr.len, cr[0usize..CAP], ci[0usize..CAP])
    var i = 0usize
    while i <= zr.len {
        b[i] = gain * cr[i]
        i += 1usize
    }
    poly_roots_cx(pre, pim, pre.len, cr[0usize..CAP], ci[0usize..CAP])
    i = 0usize
    while i <= pre.len {
        aa[i] = cr[i]
        i += 1usize
    }
}

// filter(b, a, x): the difference equation with zero state
fn filter(b: []const f64, aa: []const f64, x: []const f64, out: []f64) { sg.filter(b, aa, x, out) }

// filtfilt(b, a, x): forward and backward filtering with the package zero padding of 2 * max(length(a), length(b)) samples
fn filtfilt(a: *mem.Arena, b: []const f64, aa: []const f64, x: []const f64, out: []f64) -> err { ret sg.filtfilt(a, b, aa, x, out) }
