// R KernSmooth: `dpill` (the direct plug-in bandwidth for local linear regression of Ruppert, Sheather and Wand: the blocked
// quartic fits `cp` and `blkest`, the binned local cubic and linear fits, the diagonals of the smoother `sdiag` and `sstdiag`)
// and `bkde2D` (the bivariate binned kernel density estimate, the FFT convolution done as the direct sum it equals).
//
// Not here: dpih, the other kernels and variable bandwidths.

use e.algo.stat.locpoly as lp
use e.algo.stat.olsfit as ols
use e.algo.stat.urca2 as u2
use e.math
use e.math.dist as dist
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// the weighted local polynomial sums at grid point i from binned data: ss (2 degree + 1), tt (degree + 1) and for sstdg uu
fn local_sums(xc: []const f64, yc: []const f64, m: usize, delta: f64, h: f64, ll: i64, i: usize, ppp: usize, pp: usize, ss: []f64, tt: []f64, uu: []f64) {
    var k = 0usize
    while k < ppp {
        ss[k] = 0.0f64
        uu[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < pp {
        tt[k] = 0.0f64
        k += 1usize
    }
    var j = 0i64 - ll
    while j <= ll {
        let idx = i64(i) + j
        if idx >= 0i64 && idx < i64(m) {
            let c = xc[usize(idx)]
            let yv = yc[usize(idx)]
            if c != 0.0f64 {
                let u = delta * f64(j)
                let z = u / h
                let w = math.exp[f64](0.0f64 - z * z / 2.0f64)
                // the offset (k - j) delta of the Fortran: the data bin minus the grid point
                let off = u
                var fac = 1.0f64
                ss[0usize] += c * w
                uu[0usize] += c * w * w
                var q = 1usize
                while q < ppp {
                    fac = fac * off
                    ss[q] += c * w * fac
                    uu[q] += c * (w * w) * fac
                    q += 1usize
                }
                fac = 1.0f64
                tt[0usize] += yv * w
                q = 1usize
                while q < pp {
                    fac = fac * off
                    tt[q] += yv * w * fac
                    q += 1usize
                }
            }
        }
        j += 1i64
    }
}

// the inverse of the pp by pp local moment matrix (row-major), false when singular
fn smat_inverse(a: *mem.Arena, ss: []const f64, pp: usize, out: []f64) -> bool {
    let (sm, e) = mem.alloc[f64](a, pp * pp)
    if e != ok { ret false }
    var r = 0usize
    while r < pp {
        var s = 0usize
        while s < pp {
            sm[r * pp + s] = ss[r + s]
            s += 1usize
        }
        r += 1usize
    }
    ret u2.inv_small(a, sm, pp, out)
}

// locpoly(xc, yc, drv, degree, bandwidth, range.x, binned = TRUE): the fitted derivative at the m grid points
fn locpoly_binned(a: *mem.Arena, xc: []const f64, yc: []const f64, drv: usize, degree: usize, h: f64, lo: f64, hi: f64, out: []f64) -> bool {
    let m = xc.len
    let pp = degree + 1usize
    let ppp = 2usize * degree + 1usize
    let (ss, e1) = mem.alloc[f64](a, ppp)
    let (tt, e2) = mem.alloc[f64](a, pp)
    let (uu, e3) = mem.alloc[f64](a, ppp)
    let (inv, e4) = mem.alloc[f64](a, pp * pp)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret false }
    let delta = (hi - lo) / f64(m - 1usize)
    let ll = i64(math.floor[f64](4.0f64 * h / delta))
    var fact = 1.0f64
    var q = 2usize
    while q <= drv {
        fact *= f64(q)
        q += 1usize
    }
    var i = 0usize
    while i < m {
        local_sums(xc, yc, m, delta, h, ll, i, ppp, pp, ss, tt, uu)
        if !smat_inverse(a, ss, pp, inv) { ret false }
        var s = 0.0f64
        var c = 0usize
        while c < pp {
            s += inv[drv * pp + c] * tt[c]
            c += 1usize
        }
        out[i] = fact * s
        i += 1usize
    }
    ret true
}

fn sd_diag(a: *mem.Arena, xc: []const f64, h: f64, lo: f64, hi: f64, sdg: []f64, sstd: []f64) -> bool {
    let m = xc.len
    let pp = 2usize
    let ppp = 3usize
    let (ss, e1) = mem.alloc[f64](a, ppp)
    let (tt, e2) = mem.alloc[f64](a, pp)
    let (uu, e3) = mem.alloc[f64](a, ppp)
    let (inv, e4) = mem.alloc[f64](a, pp * pp)
    let (um, e5) = mem.alloc[f64](a, pp * pp)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret false }
    let delta = (hi - lo) / f64(m - 1usize)
    let ll = i64(math.floor[f64](4.0f64 * h / delta))
    var i = 0usize
    while i < m {
        local_sums(xc, xc, m, delta, h, ll, i, ppp, pp, ss, tt, uu)
        if !smat_inverse(a, ss, pp, inv) { ret false }
        sdg[i] = inv[0usize]
        var r = 0usize
        while r < pp {
            var s = 0usize
            while s < pp {
                um[r * pp + s] = uu[r + s]
                s += 1usize
            }
            r += 1usize
        }
        var t = 0.0f64
        r = 0usize
        while r < pp {
            var s = 0usize
            while s < pp {
                t += inv[r] * um[r * pp + s] * inv[s * pp]
                s += 1usize
            }
            r += 1usize
        }
        sstd[i] = t
        i += 1usize
    }
    ret true
}

// the blocked polynomial fits of degree q = 4 over `nval` equal blocks of the sorted data: (rss, th22, th24) as cp and blkest compute them
fn block_fit(a: *mem.Arena, x: []const f64, y: []const f64, nval: usize) -> (f64, f64, f64, bool) {
    let n = x.len
    let qq = 5usize
    let idiv = n / nval
    var rss = 0.0f64
    var th22 = 0.0f64
    var th24 = 0.0f64
    var j = 0usize
    while j < nval {
        let ilow = j * idiv
        var iupp = (j + 1usize) * idiv
        if j + 1usize == nval { iupp = n }
        let nj = iupp - ilow
        let (d, de) = mem.alloc[f64](a, nj * qq)
        if de != ok { ret (0.0f64, 0.0f64, 0.0f64, false) }
        var i = 0usize
        while i < nj {
            d[i] = 1.0f64
            var k = 1usize
            while k < qq {
                d[k * nj + i] = math.pow[f64](x[ilow + i], f64(k))
                k += 1usize
            }
            i += 1usize
        }
        let (o, oe) = ols.fit_tol(a, d, nj, qq, y[ilow..iupp], 1.0e-300f64)
        if oe != ok { ret (0.0f64, 0.0f64, 0.0f64, false) }
        let cf = o.coef
        i = 0usize
        while i < nj {
            let xv = x[ilow + i]
            var fiti = cf[0usize]
            var ddm = 2.0f64 * cf[2usize]
            var ddddm = 24.0f64 * cf[4usize]
            var k = 1usize
            while k < qq {
                fiti = fiti + cf[k] * math.pow[f64](xv, f64(k))
                if k <= 2usize { ddm = ddm + f64((k + 1usize) * (k + 2usize)) * cf[k + 2usize] * math.pow[f64](xv, f64(k)) }
                k += 1usize
            }
            th22 += ddm * ddm
            th24 += ddm * ddddm
            let r = y[ilow + i] - fiti
            rss += r * r
            i += 1usize
        }
        j += 1usize
    }
    ret (rss, th22 / f64(n), th24 / f64(n), true)
}

// dpill(x, y, blockmax, divisor, trim, proptrun, gridsize, range.x = range(x), truncate = TRUE)
// lo is NaN for the default range.x = range(x), which R reads after x has been trimmed
fn dpill(a: *mem.Arena, x0: []const f64, y0: []const f64, blockmax: f64, divisor: f64, trim: f64, proptrun: f64, m: usize, lo0: f64, hi0: f64) -> (f64, err) {
    var lo = lo0
    var hi = hi0
    let n0 = x0.len
    // sorted by x, ties by the original order
    let (ord, oe) = mem.alloc[usize](a, n0)
    if oe != ok { ret (nan(), oe) }
    var i = 0usize
    while i < n0 {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n0 {
        let key = ord[i]
        var j = i
        while j > 0usize && x0[ord[j - 1usize]] > x0[key] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = key
        i += 1usize
    }
    let indlow = usize(math.floor[f64](trim * f64(n0)))
    let indupp = n0 - usize(math.floor[f64](trim * f64(n0)))
    let n = indupp - indlow
    let (x, xe) = mem.alloc[f64](a, n)
    let (y, ye) = mem.alloc[f64](a, n)
    if xe != ok { ret (nan(), xe) }
    if ye != ok { ret (nan(), ye) }
    i = 0usize
    while i < n {
        x[i] = x0[ord[indlow + i]]
        y[i] = y0[ord[indlow + i]]
        i += 1usize
    }
    if lo != lo {
        lo = x[0usize]
        hi = x[n - 1usize]
    }
    if lo != lo {
        lo = x[0usize]
        hi = x[n - 1usize]
    }
    let nf = f64(n)
    let (xc, e1) = mem.alloc[f64](a, m)
    let (yc, e2) = mem.alloc[f64](a, m)
    if e1 != ok { ret (nan(), e1) }
    if e2 != ok { ret (nan(), e2) }
    lp.rlbin(x, y, lo, hi, m, true, xc, yc)
    var nmax = math.floor[f64](nf / divisor)
    if blockmax < nmax { nmax = blockmax }
    if nmax < 1.0f64 { nmax = 1.0f64 }
    let nm = usize(nmax)
    // Mallows' Cp over 1 .. nmax blocks
    let (rssv, e3) = mem.alloc[f64](a, nm)
    if e3 != ok { ret (nan(), e3) }
    var nv = 1usize
    while nv <= nm {
        let (r, t22, t24, bok) = block_fit(a, x, y, nv)
        if !bok { ret (nan(), Singular) }
        rssv[nv - 1usize] = r
        nv += 1usize
    }
    var best = 1usize
    var bv = 0.0f64
    nv = 1usize
    while nv <= nm {
        let cpv = (nf - 5.0f64 * f64(nm)) * rssv[nv - 1usize] / rssv[nm - 1usize] + 2.0f64 * 5.0f64 * f64(nv) - nf
        if nv == 1usize || cpv < bv {
            bv = cpv
            best = nv
        }
        nv += 1usize
    }
    let (rss, th22, th24, bok2) = block_fit(a, x, y, best)
    if !bok2 { ret (nan(), Singular) }
    let sigsq = rss / (nf - 5.0f64 * f64(best))
    let b = hi
    let av = lo
    var gamseh = sigsq * (b - av) / (math.abs[f64](th24) * nf)
    if th24 < 0.0f64 { gamseh = math.pow[f64](3.0f64 * gamseh / (8.0f64 * math.sqrt[f64](3.141592653589793f64)), 1.0f64 / 7.0f64) }
    if th24 > 0.0f64 { gamseh = math.pow[f64](15.0f64 * gamseh / (16.0f64 * math.sqrt[f64](3.141592653589793f64)), 1.0f64 / 7.0f64) }
    let (mdd, e4) = mem.alloc[f64](a, m)
    if e4 != ok { ret (nan(), e4) }
    if !locpoly_binned(a, xc, yc, 2usize, 3usize, gamseh, lo, hi, mdd) { ret (nan(), Singular) }
    let llow = usize(math.floor[f64](proptrun * f64(m)))
    let lupp = m - usize(math.floor[f64](proptrun * f64(m)))
    var th22kn = 0.0f64
    i = llow
    while i < lupp {
        th22kn += mdd[i] * mdd[i] * xc[i]
        i += 1usize
    }
    th22kn = th22kn / nf
    var c3k = 0.5f64 + 2.0f64 * math.sqrt[f64](2.0f64) - (4.0f64 / 3.0f64) * math.sqrt[f64](3.0f64)
    c3k = math.pow[f64](4.0f64 * c3k / math.sqrt[f64](2.0f64 * 3.141592653589793f64), 1.0f64 / 9.0f64)
    let lamseh = c3k * math.pow[f64](sigsq * sigsq * (b - av) / ((th22kn * nf) * (th22kn * nf)), 1.0f64 / 9.0f64)
    let (mest, e5) = mem.alloc[f64](a, m)
    let (sdg, e6) = mem.alloc[f64](a, m)
    let (sstd, e7) = mem.alloc[f64](a, m)
    if e5 != ok || e6 != ok || e7 != ok { ret (nan(), e5) }
    if !locpoly_binned(a, xc, yc, 0usize, 1usize, lamseh, lo, hi, mest) { ret (nan(), Singular) }
    if !sd_diag(a, xc, lamseh, lo, hi, sdg, sstd) { ret (nan(), Singular) }
    var sy2 = 0.0f64
    var smy = 0.0f64
    var sm2 = 0.0f64
    var ssd = 0.0f64
    var sst = 0.0f64
    i = 0usize
    while i < n {
        sy2 += y[i] * y[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        smy += mest[i] * yc[i]
        sm2 += mest[i] * mest[i] * xc[i]
        ssd += sdg[i] * xc[i]
        sst += sstd[i] * xc[i]
        i += 1usize
    }
    let sigsqn = sy2 - 2.0f64 * smy + sm2
    let sigsqd = nf - 2.0f64 * ssd + sst
    let sigsqkn = sigsqn / sigsqd
    ret (math.pow[f64](sigsqkn * (b - av) / (2.0f64 * math.sqrt[f64](3.141592653589793f64) * th22kn * nf), 0.2f64), ok)
}

error Singular

// bkde2D(x, bandwidth, gridsize, range.x, truncate = TRUE): x is n by 2 row-major; fhat is m1 by m2 row-major
fn bkde2d(a: *mem.Arena, x: []const f64, n: usize, h1: f64, h2: f64, m1: usize, m2: usize, r1lo: f64, r1hi: f64, r2lo: f64, r2hi: f64, fhat: []f64) -> err {
    let tau = 3.4f64
    let (gc, e1) = mem.alloc[f64](a, m1 * m2)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < m1 * m2 {
        gc[i] = 0.0f64
        i += 1usize
    }
    let d1 = (r1hi - r1lo) / f64(m1 - 1usize)
    let d2 = (r2hi - r2lo) / f64(m2 - 1usize)
    i = 0usize
    while i < n {
        let lx1 = (x[i * 2usize] - r1lo) / d1 + 1.0f64
        let lx2 = (x[i * 2usize + 1usize] - r2lo) / d2 + 1.0f64
        let li1 = i64(lx1)
        let li2 = i64(lx2)
        let rem1 = lx1 - f64(li1)
        let rem2 = lx2 - f64(li2)
        if li1 >= 1i64 && li2 >= 1i64 && li1 < i64(m1) && li2 < i64(m2) {
            let a1 = usize(li1 - 1i64)
            let a2 = usize(li2 - 1i64)
            gc[a1 * m2 + a2] += (1.0f64 - rem1) * (1.0f64 - rem2)
            gc[(a1 + 1usize) * m2 + a2] += rem1 * (1.0f64 - rem2)
            gc[a1 * m2 + a2 + 1usize] += (1.0f64 - rem1) * rem2
            gc[(a1 + 1usize) * m2 + a2 + 1usize] += rem1 * rem2
        }
        i += 1usize
    }
    var l1 = usize(math.floor[f64](tau * h1 * f64(m1 - 1usize) / (r1hi - r1lo)))
    if l1 > m1 - 1usize { l1 = m1 - 1usize }
    var l2 = usize(math.floor[f64](tau * h2 * f64(m2 - 1usize) / (r2hi - r2lo)))
    if l2 > m2 - 1usize { l2 = m2 - 1usize }
    let (k1, e2) = mem.alloc[f64](a, l1 + 1usize)
    let (k2, e3) = mem.alloc[f64](a, l2 + 1usize)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var id = 0usize
    while id < 2usize {
        var l = l1
        var hh = h1
        var span = r1hi - r1lo
        var mm = m1
        if id == 1usize {
            l = l2
            hh = h2
            span = r2hi - r2lo
            mm = m2
        }
        let fac = span / (hh * f64(mm - 1usize))
        var tot = 0.0f64
        var q = 0usize
        while q <= l {
            let z = dist.dnorm(f64(q) * fac, 0.0f64, 1.0f64, false) / hh
            if id == 0usize { k1[q] = z } else { k2[q] = z }
            if q == 0usize { tot += z } else { tot += 2.0f64 * z }
            q += 1usize
        }
        tot = tot * fac * hh
        q = 0usize
        while q <= l {
            if id == 0usize { k1[q] = k1[q] / tot } else { k2[q] = k2[q] / tot }
            q += 1usize
        }
        id += 1usize
    }
    let nf = f64(n)
    var p = 0usize
    while p < m1 {
        var q = 0usize
        while q < m2 {
            var s = 0.0f64
            var di = 0usize
            while di < m1 {
                var dd1 = 0usize
                if di > p { dd1 = di - p } else { dd1 = p - di }
                if dd1 <= l1 {
                    var dj = 0usize
                    while dj < m2 {
                        var dd2 = 0usize
                        if dj > q { dd2 = dj - q } else { dd2 = q - dj }
                        if dd2 <= l2 { s += k1[dd1] * k2[dd2] / nf * gc[di * m2 + dj] }
                        dj += 1usize
                    }
                }
                di += 1usize
            }
            if s > 0.0f64 { fhat[p * m2 + q] = s } else { fhat[p * m2 + q] = 0.0f64 }
            q += 1usize
        }
        p += 1usize
    }
    ret ok
}
