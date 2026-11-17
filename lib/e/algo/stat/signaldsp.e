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
