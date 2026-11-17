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
