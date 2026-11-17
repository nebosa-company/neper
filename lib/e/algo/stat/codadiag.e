// R coda, the rest of the diagnostics: heidel.diag, the multivariate potential scale reduction factor of gelman.diag, coda's pcramer, and the cross-correlations of autocorr and crosscorr.
//
// Not here: cramer.test (a different package, cramer), plots.

use e.algo.stat.codapkg as cd
use e.algo.stat.gslfns as gs
use e.math
use e.mem

// spectrum0.ar(x): (spec, order); a series that fits a straight line to within all.equal's tolerance gives (0, 0)
fn spec0(a: *mem.Arena, x: []const f64) -> (f64, usize, err) {
    let n = x.len
    let nf = f64(n)
    var zm = 0.0f64
    var xm = 0.0f64
    var i = 0usize
    while i < n {
        zm += f64(i + 1usize)
        xm += x[i]
        i += 1usize
    }
    zm = zm / nf
    xm = xm / nf
    var szz = 0.0f64
    var szx = 0.0f64
    i = 0usize
    while i < n {
        let dz = f64(i + 1usize) - zm
        szz += dz * dz
        szx += dz * (x[i] - xm)
        i += 1usize
    }
    let slope = szx / szz
    var rm = 0.0f64
    i = 0usize
    while i < n {
        rm += x[i] - xm - slope * (f64(i + 1usize) - zm)
        i += 1usize
    }
    rm = rm / nf
    var rs = 0.0f64
    i = 0usize
    while i < n {
        let r = x[i] - xm - slope * (f64(i + 1usize) - zm) - rm
        rs += r * r
        i += 1usize
    }
    if math.sqrt[f64](rs / (nf - 1.0f64)) < 1.5e-8f64 { ret (0.0f64, 0usize, ok) }
    let (ord, sm, vp, e) = cd.ar_yw(a, x)
    if e != ok { ret (0.0f64 / 0.0f64, 0usize, e) }
    ret (vp / ((1.0f64 - sm) * (1.0f64 - sm)), ord, ok)
}

// coda's pcramer(q, eps = 1e-5): the Cramer-von Mises limiting distribution, four terms with K_1/4
fn pcramer(q: f64) -> f64 {
    let pi = 3.141592653589793238462643383279f64
    let lim = 0.0f64 - math.log[f64](0.00001f64)
    var tot = 0.0f64
    var k = 0usize
    while k < 4usize {
        let kf = f64(k)
        var g = math.sqrt[f64](pi)
        var gk = 1.0f64
        if k == 1usize { g = math.sqrt[f64](pi) / 2.0f64 }
        if k == 2usize {
            g = 3.0f64 * math.sqrt[f64](pi) / 4.0f64
            gk = 2.0f64
        }
        if k == 3usize {
            g = 15.0f64 * math.sqrt[f64](pi) / 8.0f64
            gk = 6.0f64
        }
        let z = g * math.sqrt[f64](4.0f64 * kf + 1.0f64) / (gk * math.pow[f64](pi, 1.5f64) * math.sqrt[f64](q))
        let u = (4.0f64 * kf + 1.0f64) * (4.0f64 * kf + 1.0f64) / (16.0f64 * q)
        if !(u > lim) { tot += z * math.exp[f64](0.0f64 - u) * gs.bessel_knu(0.25f64, u) }
        k += 1usize
    }
    ret tot
}

// window(x, start = s) on a thin-1 series whose current first time is cur: the first time at or after s (a time within 1e-5 relative of s counts as s)
fn window_start(cur: f64, s: f64) -> f64 {
    var t = math.ceil[f64](s)
    let r = math.round[f64](s)
    if math.abs[f64](r - s) <= math.abs[f64](s) * 0.00001f64 { t = r }
    if t < cur { t = cur }
    ret t
}

// heidel.diag(x, eps, pvalue) for one series into out: (stest, start, pvalue, htest, mean, halfwidth); start, htest, mean and halfwidth are NaN where the stationarity test fails
fn heidel(a: *mem.Arena, x: []const f64, eps: f64, pvalue: f64, out: []f64) -> err {
    let nan = 0.0f64 / 0.0f64
    let n = x.len
    let nf = f64(n)
    let by = nf / 10.0f64
    let to = nf / 2.0f64
    let t0 = window_start(1.0f64, to)
    let (s0, o0, e0) = spec0(a, x[usize(t0) - 1usize..n])
    if e0 != ok { ret e0 }
    let cnt = usize(math.floor[f64]((to - 1.0f64) / by + 0.0000000001f64))
    var cur = 1.0f64
    var converged = false
    var ii = 0.0f64
    var k = 0usize
    while k <= cnt {
        var sv = 1.0f64 + f64(k) * by
        if sv > to { sv = to }
        cur = window_start(cur, sv)
        let y = x[usize(cur) - 1usize..n]
        let m = y.len
        let yb = cd.mean_of(y)
        var cs = 0.0f64
        var tot = 0.0f64
        var i = 0usize
        while i < m {
            cs += y[i]
            let b = cs - yb * f64(i + 1usize)
            tot += b * b / (f64(m) * s0)
            i += 1usize
        }
        ii = tot / f64(m)
        converged = ii == ii && pcramer(ii) < 1.0f64 - pvalue
        if converged { break }
        k += 1usize
    }
    let y = x[usize(cur) - 1usize..n]
    let ybar = cd.mean_of(y)
    let (sci, oc, ec) = spec0(a, y)
    if ec != ok { ret ec }
    let hw = 1.96f64 * math.sqrt[f64](sci / f64(y.len))
    out[2usize] = 1.0f64 - pcramer(ii)
    if !converged || ii != ii || hw != hw {
        out[0usize] = 0.0f64
        out[1usize] = nan
        out[3usize] = nan
        out[4usize] = nan
        out[5usize] = nan
        ret ok
    }
    out[0usize] = 1.0f64
    out[1usize] = cur
    if math.abs[f64](hw / ybar) <= eps { out[3usize] = 1.0f64 } else { out[3usize] = 0.0f64 }
    out[4usize] = ybar
    out[5usize] = hw
    ret ok
}

// the largest eigenvalue of the symmetric p by p matrix m (row-major, overwritten) by cyclic Jacobi rotations
fn max_eigen(m: []f64, p: usize) -> f64 {
    var sweep = 0usize
    while sweep < 100usize {
        var off = 0.0f64
        var i = 0usize
        while i < p {
            var j = i + 1usize
            while j < p {
                off += m[i * p + j] * m[i * p + j]
                j += 1usize
            }
            i += 1usize
        }
        if off < 1.0e-60f64 { break }
        i = 0usize
        while i < p {
            var j = i + 1usize
            while j < p {
                let apq = m[i * p + j]
                if apq != 0.0f64 {
                    let th = (m[j * p + j] - m[i * p + i]) / (2.0f64 * apq)
                    var t = 1.0f64 / (math.abs[f64](th) + math.sqrt[f64](th * th + 1.0f64))
                    if th < 0.0f64 { t = 0.0f64 - t }
                    let c = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let s = t * c
                    var r = 0usize
                    while r < p {
                        let arp = m[r * p + i]
                        let arq = m[r * p + j]
                        m[r * p + i] = c * arp - s * arq
                        m[r * p + j] = s * arp + c * arq
                        r += 1usize
                    }
                    r = 0usize
                    while r < p {
                        let apr = m[i * p + r]
                        let aqr = m[j * p + r]
                        m[i * p + r] = c * apr - s * aqr
                        m[j * p + r] = s * apr + c * aqr
                        r += 1usize
                    }
                }
                j += 1usize
            }
            i += 1usize
        }
        sweep += 1usize
    }
    var best = m[0usize]
    var d = 1usize
    while d < p {
        if m[d * p + d] > best { best = m[d * p + d] }
        d += 1usize
    }
    ret best
}

// gelman.diag(...)$mpsrf for nchain chains of niter0 draws of nvar variables (data[(c * niter0 + t) * nvar + v]); autoburnin drops the first ceil(niter0 / 2) draws
fn gelman_mpsrf(a: *mem.Arena, data: []const f64, nchain: usize, niter0: usize, nvar: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let drop = niter0 - niter0 / 2usize
    let niter = niter0 - drop
    let p = nvar
    let (w, e1) = mem.alloc[f64](a, p * p)
    let (bm, e2) = mem.alloc[f64](a, p * p)
    let (xb, e3) = mem.alloc[f64](a, p * nchain)
    let (col, e4) = mem.alloc[f64](a, niter)
    let (col2, e5) = mem.alloc[f64](a, niter)
    let (mt, e6) = mem.alloc[f64](a, p * p)
    let (lc, e7) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    var i = 0usize
    while i < p * p {
        w[i] = 0.0f64
        lc[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < nchain {
        var u = 0usize
        while u < p {
            var t = 0usize
            while t < niter {
                col[t] = data[(c * niter0 + drop + t) * p + u]
                t += 1usize
            }
            xb[u * nchain + c] = cd.mean_of(col)
            var v = 0usize
            while v < p {
                t = 0usize
                while t < niter {
                    col2[t] = data[(c * niter0 + drop + t) * p + v]
                    t += 1usize
                }
                w[u * p + v] += cd.cov_of(col, col2) / f64(nchain)
                v += 1usize
            }
            u += 1usize
        }
        c += 1usize
    }
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            bm[u * p + v] = f64(niter) * cd.cov_of(xb[u * nchain..(u + 1usize) * nchain], xb[v * nchain..(v + 1usize) * nchain])
            v += 1usize
        }
        u += 1usize
    }
    // L with w = L L^T
    i = 0usize
    while i < p {
        var j = 0usize
        while j <= i {
            var s = w[i * p + j]
            var k = 0usize
            while k < j {
                s -= lc[i * p + k] * lc[j * p + k]
                k += 1usize
            }
            if i == j { lc[i * p + i] = math.sqrt[f64](s) } else { lc[i * p + j] = s / lc[j * p + j] }
            j += 1usize
        }
        i += 1usize
    }
    // mt = L^-1 B, then bm = mt L^-T
    var j = 0usize
    while j < p {
        i = 0usize
        while i < p {
            var s = bm[i * p + j]
            var k = 0usize
            while k < i {
                s -= lc[i * p + k] * mt[k * p + j]
                k += 1usize
            }
            mt[i * p + j] = s / lc[i * p + i]
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < p {
        j = 0usize
        while j < p {
            var s = mt[i * p + j]
            var k = 0usize
            while k < j {
                s -= lc[j * p + k] * bm[i * p + k]
                k += 1usize
            }
            bm[i * p + j] = s / lc[j * p + j]
            j += 1usize
        }
        i += 1usize
    }
    let emax = max_eigen(bm, p)
    let nn = f64(niter)
    ret math.sqrt[f64]((1.0f64 - 1.0f64 / nn) + (1.0f64 + 1.0f64 / f64(p)) * emax / nn)
}

// autocorr()'s multivariate acf: the lag-k correlation of series u (at t + k) with series v (at t), data row-major n by nvar; crosscorr is lag 0
fn acf_cross(data: []const f64, n: usize, nvar: usize, u: usize, v: usize, k: usize) -> f64 {
    var mu = 0.0f64
    var mv = 0.0f64
    var t = 0usize
    while t < n {
        mu += data[t * nvar + u]
        mv += data[t * nvar + v]
        t += 1usize
    }
    mu = mu / f64(n)
    mv = mv / f64(n)
    var s = 0.0f64
    var suu = 0.0f64
    var svv = 0.0f64
    t = 0usize
    while t < n {
        let du = data[t * nvar + u] - mu
        let dv = data[t * nvar + v] - mv
        suu += du * du
        svv += dv * dv
        if t + k < n { s += (data[(t + k) * nvar + u] - mu) * dv }
        t += 1usize
    }
    ret s / math.sqrt[f64](suu * svv)
}
