// R package cluster: ellipsoidhull (the minimum volume ellipsoid, spannel.c's sweep iteration plus cov.wt and the volume) and clusGap with pam as the
// clustering function (both reference distributions, scaledPCA through the sign-exact LAPACK dgesdd port), and maxSE.

use e.algo.linalg.lapack_gesdd as gesdd
use e.algo.rand.r as rng
use e.algo.stat.clusterpkg as cp
use e.math
use e.math.special as special
use e.mem

// loc: the centre; cov: the p by p shape matrix (column-major); d2: squared average radius; eps: max(sqdist) - p; it: iterations; ierr: 0 or 2 (collinear);
// conv: converged; sqdist and prob: the final squared distances and weights
type HullFit = struct { loc: []f64, cov: []f64, d2: f64, sqdist: []f64, prob: []f64, eps: f64, it: usize, ierr: usize, conv: bool }

// the sweep operator of cl_sweep() on the (nord + 1) square matrix cov (column-major), for the pivot nel; deter is the running determinant
fn cl_sweep(cov: []f64, nord: usize, ixlo: usize, nel: usize, deter: []f64) {
    let dim1 = nord + 1usize
    let temp = cov[nel + nel * dim1]
    deter[0usize] *= temp
    if deter[0usize] <= 0.0f64 { ret }
    if nord <= 1usize {
        cov[1usize + 1usize * dim1] = 1.0f64 / temp
    } else {
        var i = ixlo
        while i <= nord {
            if i != nel {
                var j = ixlo
                while j <= i {
                    if j != nel {
                        cov[j + i * dim1] = cov[i + j * dim1] - cov[i + nel * dim1] * cov[nel + j * dim1] / temp
                        cov[i + j * dim1] = cov[j + i * dim1]
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        cov[nel + nel * dim1] = 1.0f64
        i = ixlo
        while i <= nord {
            cov[nel + i * dim1] = 0.0f64 - cov[i + nel * dim1] / temp
            cov[i + nel * dim1] = cov[nel + i * dim1]
            i += 1usize
        }
    }
}

// spannel: dat is n by (p + 1) column-major with a leading column of ones (scaled in place); returns the iteration count (maxit when not converged) and ierr
fn spannel(a: *mem.Arena, dat: []f64, ncas: usize, ndep: usize, dstopt: []f64, prob: []f64, eps_tol: f64, maxit: usize) -> (usize, usize, err) {
    let cov_dim1 = ndep + 1usize
    let (cov, e1) = cp.zf(a, cov_dim1 * cov_dim1)
    if e1 != ok { ret (0usize, 0usize, e1) }
    let (varsum, e2) = cp.zf(a, ndep + 1usize)
    if e2 != ok { ret (0usize, 0usize, e2) }
    let (varss, e3) = cp.zf(a, ndep + 1usize)
    if e3 != ok { ret (0usize, 0usize, e3) }
    let (work, e4) = cp.zf(a, ndep + 1usize)
    if e4 != ok { ret (0usize, 0usize, e4) }
    let (deter, e5) = cp.zf(a, 1usize)
    if e5 != ok { ret (0usize, 0usize, e5) }
    var i = 0usize
    var j = 1usize
    while i < ncas {
        j = 1usize
        while j <= ndep {
            let pv = dat[i + j * ncas]
            varsum[j] += pv
            varss[j] += pv * pv
            j += 1usize
        }
        i += 1usize
    }
    j = 1usize
    while j <= ndep {
        let aver = varsum[j] / f64(ncas)
        let scal = math.sqrt[f64](varss[j] / f64(ncas) - aver * aver)
        i = 0usize
        while i < ncas {
            dat[i + j * ncas] = (dat[i + j * ncas] - aver) / scal
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < ncas {
        prob[i] = 1.0f64 / f64(ncas)
        i += 1usize
    }
    let pdim = f64(ndep)
    var it = 0usize
    while it < maxit {
        j = 0usize
        while j <= ndep {
            var k = 0usize
            while k <= j {
                cov[k + j * cov_dim1] = 0.0f64
                k += 1usize
            }
            j += 1usize
        }
        i = 0usize
        while i < ncas {
            j = 0usize
            while j <= ndep {
                work[j] = dat[i + j * ncas]
                let tempo = prob[i] * work[j]
                var k = 0usize
                while k <= j {
                    cov[k + j * cov_dim1] += tempo * work[k]
                    k += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j <= ndep {
            var k = 0usize
            while k <= j {
                cov[j + k * cov_dim1] = cov[k + j * cov_dim1]
                k += 1usize
            }
            j += 1usize
        }
        deter[0usize] = 1.0f64
        i = 0usize
        while i <= ndep {
            cl_sweep(cov, ndep, 0usize, i, deter)
            if deter[0usize] <= 0.0f64 { ret (maxit, 2usize, ok) }
            i += 1usize
        }
        var dmax = 0.0f64
        i = 0usize
        while i < ncas {
            var dist = 0.0f64 - 1.0f64
            j = 0usize
            while j <= ndep {
                var w_j = 0.0f64
                var k = 0usize
                while k <= ndep {
                    w_j -= cov[j + k * cov_dim1] * dat[i + k * ncas]
                    k += 1usize
                }
                dist += w_j * dat[i + j * ncas]
                j += 1usize
            }
            dstopt[i] = dist
            if dmax < dist { dmax = dist }
            i += 1usize
        }
        if dmax <= pdim + eps_tol { ret (it, 0usize, ok) }
        i = 0usize
        while i < ncas {
            prob[i] *= (dstopt[i] / pdim)
            i += 1usize
        }
        it += 1usize
    }
    ret (maxit, 0usize, ok)
}

// cluster::ellipsoidhull of the n by p column-major x (no NaN)
fn ellipsoidhull(a: *mem.Arena, x: []const f64, n: usize, p: usize, tol: f64, maxit: usize) -> (HullFit, err) {
    var fit: HullFit = zero
    let (dat, e1) = cp.zf(a, n * (p + 1usize))
    if e1 != ok { ret (fit, e1) }
    var i = 0usize
    while i < n {
        dat[i] = 1.0f64
        var j = 0usize
        while j < p {
            dat[i + (j + 1usize) * n] = x[i + j * n]
            j += 1usize
        }
        i += 1usize
    }
    let (sqdist, e2) = cp.zf(a, n)
    if e2 != ok { ret (fit, e2) }
    let (prob, e3) = cp.zf(a, n)
    if e3 != ok { ret (fit, e3) }
    let (it, ierr, e4) = spannel(a, dat, n, p, sqdist, prob, tol, maxit)
    if e4 != ok { ret (fit, e4) }
    var sum_w = 0.0f64
    i = 0usize
    while i < n {
        sum_w += prob[i]
        i += 1usize
    }
    // cov.wt(x, prob): weights normalised, centre = weighted mean, covariance of the centred rows scaled by sqrt(wt); times (1 - sum(wt^2)) it is crossprod
    let (wt, e5) = cp.zf(a, n)
    if e5 != ok { ret (fit, e5) }
    var sw2 = 0.0f64
    i = 0usize
    while i < n {
        wt[i] = prob[i] / sum_w
        sw2 += wt[i] * wt[i]
        i += 1usize
    }
    let (loc, e6) = cp.zf(a, p)
    if e6 != ok { ret (fit, e6) }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += wt[i] * x[i + j * n]
            i += 1usize
        }
        loc[j] = s
        j += 1usize
    }
    let (cov, e7) = cp.zf(a, p * p)
    if e7 != ok { ret (fit, e7) }
    j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += (math.sqrt[f64](wt[i]) * (x[i + j * n] - loc[j])) * (math.sqrt[f64](wt[i]) * (x[i + k * n] - loc[k]))
                i += 1usize
            }
            cov[j + k * p] = s
            k += 1usize
        }
        j += 1usize
    }
    var d2 = 0.0f64
    var mx = 0.0f64 - 1.0e300f64
    i = 0usize
    while i < n {
        d2 += sqdist[i] * prob[i]
        if sqdist[i] > mx { mx = sqdist[i] }
        i += 1usize
    }
    fit.loc = loc
    fit.cov = cov
    fit.d2 = d2 / sum_w
    fit.sqdist = sqdist
    fit.prob = prob
    fit.eps = mx - f64(p)
    fit.it = it
    fit.ierr = ierr
    fit.conv = it < maxit && ierr == 0usize
    ret (fit, ok)
}

// log(volume) of an ellipsoid: p/2 * log(pi * d2) + log(det(cov)) / 2 - lgamma(p/2 + 1), the determinant by LU with partial pivoting
fn log_volume(a: *mem.Arena, cov: []const f64, d2: f64, p: usize) -> (f64, err) {
    let (m, e) = cp.zf(a, p * p)
    if e != ok { ret (0.0f64, e) }
    var i = 0usize
    while i < p * p {
        m[i] = cov[i]
        i += 1usize
    }
    var logdet = 0.0f64
    var c = 0usize
    while c < p {
        var piv = c
        var best = math.abs[f64](m[c + c * p])
        var r = c + 1usize
        while r < p {
            if math.abs[f64](m[r + c * p]) > best {
                best = math.abs[f64](m[r + c * p])
                piv = r
            }
            r += 1usize
        }
        if piv != c {
            var k = 0usize
            while k < p {
                let t = m[c + k * p]
                m[c + k * p] = m[piv + k * p]
                m[piv + k * p] = t
                k += 1usize
            }
        }
        let d = m[c + c * p]
        logdet += math.log[f64](math.abs[f64](d))
        r = c + 1usize
        while r < p {
            let f = m[r + c * p] / d
            var k = c + 1usize
            while k < p {
                m[r + k * p] -= f * m[c + k * p]
                k += 1usize
            }
            r += 1usize
        }
        c += 1usize
    }
    let half = f64(p) / 2.0f64
    ret (half * math.log[f64](3.141592653589793f64 * d2) + logdet / 2.0f64 - special.lgamma(half + 1.0f64), ok)
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// clusGap

// columns logW, E.logW, gap, SE.sim of the gap statistic table, kmax rows each, column-major
type GapFit = struct { tab: []f64 }

// the pooled within-cluster dispersion W.k of the rows of x (n by p) for kk clusters (pam, euclidean) with dist^d_power
fn gap_wk(a: *mem.Arena, x: []const f64, n: usize, p: usize, kk: usize, d_power: f64) -> (f64, err) {
    let (clu, e0) = cp.zu(a, n)
    if e0 != ok { ret (0.0f64, e0) }
    var i = 0usize
    if kk > 1usize {
        let (jtmd, e1) = cp.zi(a, p)
        if e1 != ok { ret (0.0f64, e1) }
        let (valmd, e2) = cp.zf(a, p)
        if e2 != ok { ret (0.0f64, e2) }
        let (dys, e3) = cp.zf(a, n * (n - 1usize) / 2usize + 1usize)
        if e3 != ok { ret (0.0f64, e3) }
        if cp.dysta(x, n, p, dys, 1usize, jtmd, valmd) != 0usize { ret (0.0f64, cp.BadArgument) }
        let (given, e4) = cp.zu(a, kk)
        if e4 != ok { ret (0.0f64, e4) }
        let (fit, e5) = cp.pam(a, dys, n, kk, given, false, true, 0usize, false)
        if e5 != ok { ret (0.0f64, e5) }
        i = 0usize
        while i < n {
            clu[i] = fit.clu[i]
            i += 1usize
        }
    } else {
        while i < n {
            clu[i] = 1usize
            i += 1usize
        }
    }
    var total = 0.0f64
    var c = 1usize
    while c <= kk {
        var size = 0usize
        i = 0usize
        while i < n {
            if clu[i] == c { size += 1usize }
            i += 1usize
        }
        var s = 0.0f64
        i = 0usize
        while i < n {
            if clu[i] == c {
                var j = i + 1usize
                while j < n {
                    if clu[j] == c {
                        var d2 = 0.0f64
                        var q = 0usize
                        while q < p {
                            let dv = x[i + q * n] - x[j + q * n]
                            d2 += dv * dv
                            q += 1usize
                        }
                        var dd = math.sqrt[f64](d2)
                        if d_power != 1.0f64 { dd = math.pow[f64](dd, d_power) }
                        s += dd / f64(size)
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        total += s
        c += 1usize
    }
    ret (0.5f64 * total, ok)
}

// cluster::clusGap(x, FUNcluster = pam, K.max, B, d.power, spaceH0); seed rg before the call as set.seed does
fn clus_gap(a: *mem.Arena, x: []const f64, n: usize, p: usize, kmax: usize, b: usize, d_power: f64, pca: bool, rg: *rng.Rng) -> (GapFit, err) {
    var res: GapFit = zero
    let (logw, e1) = cp.zf(a, kmax)
    if e1 != ok { ret (res, e1) }
    var k = 1usize
    while k <= kmax {
        let start = mem.mark(a)
        let (w, e2) = gap_wk(a, x, n, p, k, d_power)
        if e2 != ok { ret (res, e2) }
        mem.reset(a, start)
        logw[k - 1usize] = math.log[f64](w)
        k += 1usize
    }
    let (xs, e3) = cp.zf(a, n * p)
    if e3 != ok { ret (res, e3) }
    let (mx_c, e4) = cp.zf(a, p)
    if e4 != ok { ret (res, e4) }
    var j = 0usize
    while j < p {
        mx_c[j] = cp.col_mean(x, n, j, false)
        var i = 0usize
        while i < n {
            xs[i + j * n] = x[i + j * n] - mx_c[j]
            i += 1usize
        }
        j += 1usize
    }
    let (v, e5) = cp.zf(a, p * p)
    if e5 != ok { ret (res, e5) }
    if pca {
        var kk = n
        if p < n { kk = p }
        let (sv, e6) = cp.zf(a, kk)
        if e6 != ok { ret (res, e6) }
        let (u, e7) = cp.zf(a, n * kk)
        if e7 != ok { ret (res, e7) }
        let (vt, e8) = cp.zf(a, kk * p)
        if e8 != ok { ret (res, e8) }
        let es = gesdd.svd_all(a, xs, n, p, sv, u, vt)
        if es != ok { ret (res, es) }
        // V[l, c] = vt[c, l]
        var l = 0usize
        while l < p {
            var c = 0usize
            while c < p {
                v[l + c * p] = vt[c + l * kk]
                c += 1usize
            }
            l += 1usize
        }
        // xs <- xs %*% V
        let (xv, e9) = cp.zf(a, n * p)
        if e9 != ok { ret (res, e9) }
        var i = 0usize
        while i < n {
            var c = 0usize
            while c < p {
                var s = 0.0f64
                l = 0usize
                while l < p {
                    s += xs[i + l * n] * v[l + c * p]
                    l += 1usize
                }
                xv[i + c * n] = s
                c += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < n * p {
            xs[i] = xv[i]
            i += 1usize
        }
    }
    let (lo, e10) = cp.zf(a, p)
    if e10 != ok { ret (res, e10) }
    let (hi, e11) = cp.zf(a, p)
    if e11 != ok { ret (res, e11) }
    j = 0usize
    while j < p {
        lo[j] = xs[j * n]
        hi[j] = xs[j * n]
        var i = 1usize
        while i < n {
            if xs[i + j * n] < lo[j] { lo[j] = xs[i + j * n] }
            if xs[i + j * n] > hi[j] { hi[j] = xs[i + j * n] }
            i += 1usize
        }
        j += 1usize
    }
    let (logwks, e12) = cp.zf(a, b * kmax)
    if e12 != ok { ret (res, e12) }
    let (z1, e13) = cp.zf(a, n * p)
    if e13 != ok { ret (res, e13) }
    let (z, e14) = cp.zf(a, n * p)
    if e14 != ok { ret (res, e14) }
    var bb = 0usize
    while bb < b {
        j = 0usize
        while j < p {
            var i = 0usize
            while i < n {
                z1[i + j * n] = rng.runif(rg, lo[j], hi[j])
                i += 1usize
            }
            j += 1usize
        }
        var i = 0usize
        while i < n {
            var c = 0usize
            while c < p {
                var s = 0.0f64
                if pca {
                    var l = 0usize
                    while l < p {
                        s += z1[i + l * n] * v[c + l * p]
                        l += 1usize
                    }
                } else {
                    s = z1[i + c * n]
                }
                z[i + c * n] = s + mx_c[c]
                c += 1usize
            }
            i += 1usize
        }
        k = 1usize
        while k <= kmax {
            let start = mem.mark(a)
            let (w, e15) = gap_wk(a, z, n, p, k, d_power)
            if e15 != ok { ret (res, e15) }
            mem.reset(a, start)
            logwks[bb + (k - 1usize) * b] = math.log[f64](w)
            k += 1usize
        }
        bb += 1usize
    }
    let (tab, e16) = cp.zf(a, kmax * 4usize)
    if e16 != ok { ret (res, e16) }
    k = 0usize
    while k < kmax {
        var s = 0.0f64
        bb = 0usize
        while bb < b {
            s += logwks[bb + k * b]
            bb += 1usize
        }
        let mu = s / f64(b)
        var ss = 0.0f64
        bb = 0usize
        while bb < b {
            let dv = logwks[bb + k * b] - mu
            ss += dv * dv
            bb += 1usize
        }
        tab[k] = logw[k]
        tab[kmax + k] = mu
        tab[2usize * kmax + k] = mu - logw[k]
        tab[3usize * kmax + k] = math.sqrt[f64]((1.0f64 + 1.0f64 / f64(b)) * (ss / f64(b - 1usize)))
        k += 1usize
    }
    res.tab = tab
    ret (res, ok)
}

// maxSE: the number of clusters (1-based) chosen from the gap f and its standard error; method 1 firstSEmax, 2 Tibs2001SEmax, 3 globalSEmax, 4 firstmax, 5 globalmax
fn max_se(f: []const f64, se: []const f64, method: usize, se_factor: f64) -> usize {
    let kk = f.len
    if method == 5usize {
        var best = 0usize
        var i = 1usize
        while i < kk {
            if f[i] > f[best] { best = i }
            i += 1usize
        }
        ret best + 1usize
    }
    if method == 2usize {
        var i = 0usize
        while i + 1usize < kk {
            if f[i] >= f[i + 1usize] - se_factor * se[i + 1usize] { ret i + 1usize }
            i += 1usize
        }
        ret kk
    }
    // firstmax, firstSEmax: the first local maximum; globalSEmax: the global maximum
    var nc = kk
    if method == 3usize {
        var best = 0usize
        var i = 1usize
        while i < kk {
            if f[i] > f[best] { best = i }
            i += 1usize
        }
        nc = best + 1usize
    } else {
        var i = 0usize
        while i + 1usize < kk {
            if f[i + 1usize] - f[i] <= 0.0f64 {
                nc = i + 1usize
                break
            }
            i += 1usize
        }
    }
    if method == 4usize { ret nc }
    var i = 0usize
    while i + 1usize < nc {
        if f[i] >= f[nc - 1usize] - se_factor * se[nc - 1usize] { ret i + 1usize }
        i += 1usize
    }
    ret nc
}
