// R coda: the autocorrelations of acf, the Yule-Walker autoregression of ar(aic = TRUE) behind spectrum0.ar, and effectiveSize for one chain.
//
// Not here: the multiple-chain diagnostics (gelman.diag, geweke.diag, heidel.diag, raftery.diag), HPDinterval and cramer.test.

use e.algo.stat.gslfns as gs
use e.algo.stat.mass as ms
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem

// the biased autocovariances c_0 .. c_m of the series about its mean (acf's estimator: divided by n)
fn autocov(x: []const f64, m: usize, c: []f64) {
    let n = x.len
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var k = 0usize
    while k <= m {
        var s = 0.0f64
        i = 0usize
        while i + k < n {
            s += (x[i] - mean) * (x[i + k] - mean)
            i += 1usize
        }
        c[k] = s / f64(n)
        k += 1usize
    }
}

// acf(x, lag.max = m)$acf[k + 1] for k = 0 .. m into out
fn acf(x: []const f64, m: usize, out: []f64) {
    autocov(x, m, out)
    let c0 = out[0usize]
    var k = 0usize
    while k <= m {
        out[k] = out[k] / c0
        k += 1usize
    }
}

// ar(x, aic = TRUE) by Yule-Walker (demeaned): the selected order, the sum of its coefficients and var.pred; returns the order
fn ar_yw(a: *mem.Arena, x: []const f64) -> (usize, f64, f64, err) {
    let n = x.len
    var om = usize(math.floor[f64](10.0f64 * math.log10[f64](f64(n))))
    if om > n - 1usize { om = n - 1usize }
    let (c, e1) = mem.alloc[f64](a, om + 1usize)
    let (vars, e2) = mem.alloc[f64](a, om + 1usize)
    let (phi, e3) = mem.alloc[f64](a, (om + 1usize) * (om + 1usize))
    if e1 != ok { ret (0usize, 0.0f64, 0.0f64, e1) }
    if e2 != ok { ret (0usize, 0.0f64, 0.0f64, e2) }
    if e3 != ok { ret (0usize, 0.0f64, 0.0f64, e3) }
    autocov(x, om, c)
    vars[0usize] = c[0usize]
    var k = 1usize
    while k <= om {
        var num = c[k]
        var j = 1usize
        while j < k {
            num -= phi[(k - 1usize) * (om + 1usize) + j] * c[k - j]
            j += 1usize
        }
        let pk = num / vars[k - 1usize]
        phi[k * (om + 1usize) + k] = pk
        j = 1usize
        while j < k {
            phi[k * (om + 1usize) + j] = phi[(k - 1usize) * (om + 1usize) + j] - pk * phi[(k - 1usize) * (om + 1usize) + k - j]
            j += 1usize
        }
        vars[k] = vars[k - 1usize] * (1.0f64 - pk * pk)
        k += 1usize
    }
    var best = 0usize
    var bv = f64(n) * math.log[f64](vars[0usize])
    k = 1usize
    while k <= om {
        let v = f64(n) * math.log[f64](vars[k]) + 2.0f64 * f64(k)
        if v < bv {
            bv = v
            best = k
        }
        k += 1usize
    }
    var sum = 0.0f64
    var j = 1usize
    while j <= best {
        sum += phi[best * (om + 1usize) + j]
        j += 1usize
    }
    let vp = vars[best] * f64(n) / f64(n - (best + 1usize))
    ret (best, sum, vp, ok)
}

// effectiveSize(x) for one chain: n var(x) / spectrum0.ar(x)$spec, 0 for a series that is a straight line
fn effective_size(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (x[i] - mean) * (x[i] - mean)
        i += 1usize
    }
    let v = ss / f64(n - 1usize)
    let (ord, sm, vp, e) = ar_yw(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let spec = vp / ((1.0f64 - sm) * (1.0f64 - sm))
    if spec == 0.0f64 { ret 0.0f64 }
    ret f64(n) * v / spec
}

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    ret s / f64(x.len)
}

// geweke.diag(x, frac1, frac2)$z for one series: the first frac1 and the last frac2 of the run (R's window rounding), spectral variances from spectrum0.ar
fn geweke_z(a: *mem.Arena, x: []const f64, frac1: f64, frac2: f64) -> f64 {
    let n = x.len
    let nm1 = f64(n - 1usize)
    let end1 = usize(math.ceil[f64](1.0f64 + frac1 * nm1))
    let start2 = usize(math.floor[f64](f64(n) - frac2 * nm1))
    let y1 = x[0usize..end1]
    let y2 = x[start2 - 1usize..n]
    let (o1, s1, v1, e1) = ar_yw(a, y1)
    let (o2, s2, v2, e2) = ar_yw(a, y2)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    let sp1 = v1 / ((1.0f64 - s1) * (1.0f64 - s1)) / f64(y1.len)
    let sp2 = v2 / ((1.0f64 - s2) * (1.0f64 - s2)) / f64(y2.len)
    ret (mean_of(y1) - mean_of(y2)) / math.sqrt[f64](sp1 + sp2)
}

fn var_of(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / f64(x.len - 1usize)
}

fn cov_of(x: []const f64, y: []const f64) -> f64 {
    let mx = mean_of(x)
    let my = mean_of(y)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - mx) * (y[i] - my)
        i += 1usize
    }
    ret s / f64(x.len - 1usize)
}

// gelman.diag(chains, confidence, autoburnin = TRUE) for one variable: chains is nchain by niter row-major, niter even; the first half is dropped; returns the point estimate and upper bound of the potential scale reduction factor
fn gelman_psrf(a: *mem.Arena, chains: []const f64, nchain: usize, niter0: usize, confidence: f64) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let half = niter0 - niter0 / 2usize
    let niter = niter0 / 2usize
    let (s2, e1) = mem.alloc[f64](a, nchain)
    let (xb, e2) = mem.alloc[f64](a, nchain)
    let (xb2, e3) = mem.alloc[f64](a, nchain)
    if e1 != ok || e2 != ok || e3 != ok { ret (nan, nan) }
    var c = 0usize
    while c < nchain {
        let ch = chains[c * niter0 + half..(c + 1usize) * niter0]
        s2[c] = var_of(ch)
        xb[c] = mean_of(ch)
        xb2[c] = xb[c] * xb[c]
        c += 1usize
    }
    let nn = f64(niter)
    let nc = f64(nchain)
    let w = mean_of(s2)
    let b = nn * var_of(xb)
    let muhat = mean_of(xb)
    let var_w = var_of(s2) / nc
    let var_b = 2.0f64 * b * b / (nc - 1.0f64)
    let cov_wb = (nn / nc) * (cov_of(s2, xb2) - 2.0f64 * muhat * cov_of(s2, xb))
    let vv = (nn - 1.0f64) * w / nn + (1.0f64 + 1.0f64 / nc) * b / nn
    let var_v = ((nn - 1.0f64) * (nn - 1.0f64) * var_w + (1.0f64 + 1.0f64 / nc) * (1.0f64 + 1.0f64 / nc) * var_b + 2.0f64 * (nn - 1.0f64) * (1.0f64 + 1.0f64 / nc) * cov_wb) / (nn * nn)
    let df_v = 2.0f64 * vv * vv / var_v
    let df_adj = (df_v + 3.0f64) / (df_v + 1.0f64)
    let b_df = nc - 1.0f64
    let w_df = 2.0f64 * w * w / var_w
    let r2_fixed = (nn - 1.0f64) / nn
    let r2_random = (1.0f64 + 1.0f64 / nc) * (1.0f64 / nn) * (b / w)
    let r2_est = r2_fixed + r2_random
    let r2_up = r2_fixed + nb.qf((1.0f64 + confidence) / 2.0f64, b_df, w_df, true, false) * r2_random
    ret (math.sqrt[f64](df_adj * r2_est), math.sqrt[f64](df_adj * r2_up))
}

// HPDinterval(x, prob) for one sample: the shortest interval holding round(n prob) of the sorted draws (R's round: half to even), the first shortest one on ties
fn hpd(a: *mem.Arena, x: []const f64, prob: f64) -> (f64, f64) {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret (0.0f64 / 0.0f64, 0.0f64 / 0.0f64) }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    let r0 = f64(n) * prob
    var gp = math.floor[f64](r0 + 0.5f64)
    if r0 + 0.5f64 == gp && gp - 2.0f64 * math.floor[f64](gp / 2.0f64) != 0.0f64 { gp = gp - 1.0f64 }
    var gap = usize(gp)
    if gap > n - 1usize { gap = n - 1usize }
    if gap < 1usize { gap = 1usize }
    var best = 0usize
    var bw = s[gap] - s[0usize]
    i = 1usize
    while i + gap < n {
        let w = s[i + gap] - s[i]
        if w < bw {
            bw = w
            best = i
        }
        i += 1usize
    }
    ret (s[best], s[best + gap])
}

// raftery.diag(x, q, r, s, converge.eps) for one series (thin 1): (M, N, Nmin, I) where I is signif(iratio, 3); NaN where the series is shorter than Nmin
fn raftery(a: *mem.Arena, x: []const f64, q: f64, r: f64, s: f64, eps: f64) -> (f64, f64, f64, f64, err) {
    let nan = 0.0f64 / 0.0f64
    let n = x.len
    let phi = dist.qnorm(0.5f64 * (1.0f64 + s), 0.0f64, 1.0f64, true, false)
    let nmin = math.ceil[f64](q * (1.0f64 - q) * phi * phi / (r * r))
    if nmin > f64(n) { ret (nan, nan, nmin, nan, ok) }
    let (srt, e0) = mem.alloc[f64](a, n)
    let (dich, e1) = mem.alloc[usize](a, n)
    if e0 != ok { ret (nan, nan, nan, nan, e0) }
    if e1 != ok { ret (nan, nan, nan, nan, e1) }
    var i = 0usize
    while i < n {
        srt[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let t = srt[i]
        var j = i
        while j > 0usize && srt[j - 1usize] > t {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = t
        i += 1usize
    }
    let quant = ms.quant7(srt, q)
    i = 0usize
    while i < n {
        if x[i] <= quant { dich[i] = 1usize } else { dich[i] = 0usize }
        i += 1usize
    }
    var kthin = 0usize
    var bic = 1.0f64
    var nd = 0usize
    var tc: [8]f64 = zero
    var tr: [4]f64 = zero
    while bic >= 0.0f64 {
        kthin += 1usize
        // the thinned series: every kthin-th starting at 1
        nd = (n - 1usize) / kthin + 1usize
        var m = 0usize
        while m < 8usize {
            tc[m] = 0.0f64
            m += 1usize
        }
        m = 0usize
        while m < 4usize {
            tr[m] = 0.0f64
            m += 1usize
        }
        var k = 0usize
        while k + 2usize < nd {
            let a1 = dich[k * kthin]
            let a2 = dich[(k + 1usize) * kthin]
            let a3 = dich[(k + 2usize) * kthin]
            tc[a1 * 4usize + a2 * 2usize + a3] += 1.0f64
            k += 1usize
        }
        var g2 = 0.0f64
        var i1 = 0usize
        while i1 < 2usize {
            var i2 = 0usize
            while i2 < 2usize {
                var i3 = 0usize
                while i3 < 2usize {
                    let cnt = tc[i1 * 4usize + i2 * 2usize + i3]
                    if cnt != 0.0f64 {
                        let rowsum = tc[i1 * 4usize + i2 * 2usize] + tc[i1 * 4usize + i2 * 2usize + 1usize]
                        let colsum = tc[i2 * 2usize + i3] + tc[4usize + i2 * 2usize + i3]
                        let mid = tc[i2 * 2usize] + tc[i2 * 2usize + 1usize] + tc[4usize + i2 * 2usize] + tc[4usize + i2 * 2usize + 1usize]
                        let fitted = rowsum * colsum / mid
                        g2 += cnt * math.log[f64](cnt / fitted) * 2.0f64
                    }
                    i3 += 1usize
                }
                i2 += 1usize
            }
            i1 += 1usize
        }
        bic = g2 - math.log[f64](f64(nd - 2usize)) * 2.0f64
    }
    var k2 = 0usize
    while k2 + 1usize < nd {
        tr[dich[k2 * kthin] * 2usize + dich[(k2 + 1usize) * kthin]] += 1.0f64
        k2 += 1usize
    }
    let alpha = tr[1usize] / (tr[0usize] + tr[1usize])
    let beta = tr[2usize] / (tr[2usize] + tr[3usize])
    var mxab = alpha
    if beta > mxab { mxab = beta }
    let tempburn = math.log[f64](eps * (alpha + beta) / mxab) / math.log[f64](math.abs[f64](1.0f64 - alpha - beta))
    let nburn = math.ceil[f64](tempburn) * f64(kthin)
    let tempprec = ((2.0f64 - alpha - beta) * alpha * beta * phi * phi) / ((alpha + beta) * (alpha + beta) * (alpha + beta) * r * r)
    let nkeep = math.ceil[f64](tempprec) * f64(kthin)
    let iratio = (nburn + nkeep) / nmin
    // signif(iratio, 3)
    let mag = math.pow[f64](10.0f64, 2.0f64 - math.floor[f64](math.log10[f64](math.abs[f64](iratio))))
    ret (nburn, nkeep + nburn, nmin, math.round[f64](iratio * mag) / mag, ok)
}

// spectrum0.ar(x): (spec, order); a series that is a straight line in time has spec 0 and order 0
fn spec0(a: *mem.Arena, x: []const f64) -> (f64, usize, err) {
    let n = x.len
    let zm = (f64(n) + 1.0f64) / 2.0f64
    let xm = mean_of(x)
    var sxz = 0.0f64
    var szz = 0.0f64
    var i = 0usize
    while i < n {
        let dz = f64(i + 1usize) - zm
        sxz += dz * (x[i] - xm)
        szz += dz * dz
        i += 1usize
    }
    let slope = sxz / szz
    var rss = 0.0f64
    i = 0usize
    while i < n {
        let r = x[i] - xm - slope * (f64(i + 1usize) - zm)
        rss += r * r
        i += 1usize
    }
    if math.sqrt[f64](rss / f64(n - 2usize)) < 1.5e-8f64 { ret (0.0f64, 0usize, ok) }
    let (ord, sm, vp, e) = ar_yw(a, x)
    if e != ok { ret (0.0f64, 0usize, e) }
    ret (vp / ((1.0f64 - sm) * (1.0f64 - sm)), ord, ok)
}

// coda:::pcramer(q): the limiting Cramer-von Mises distribution, four terms of the Bessel K_1/4 series
fn pcramer(q: f64) -> f64 {
    let pi = 3.141592653589793238462643383279f64
    let sp = math.sqrt[f64](pi)
    var g1: [4]f64 = zero
    var g2: [4]f64 = zero
    g1[0usize] = sp
    g1[1usize] = sp / 2.0f64
    g1[2usize] = 3.0f64 * sp / 4.0f64
    g1[3usize] = 15.0f64 * sp / 8.0f64
    g2[0usize] = 1.0f64
    g2[1usize] = 1.0f64
    g2[2usize] = 2.0f64
    g2[3usize] = 6.0f64
    var s = 0.0f64
    var k = 0usize
    while k < 4usize {
        let m = 4.0f64 * f64(k) + 1.0f64
        let z = g1[k] * math.sqrt[f64](m) / (g2[k] * math.pow[f64](pi, 1.5f64) * math.sqrt[f64](q))
        let u = m * m / (16.0f64 * q)
        if !(u > 11.512925464970229f64) { s += z * math.exp[f64](0.0f64 - u) * gs.bessel_knu(0.25f64, u) }
        k += 1usize
    }
    ret s
}

// window() start on a unit-thin series: the first time at or after s (within ts.eps), at least cur
fn win_start(s: f64, cur: usize) -> usize {
    var t = usize(math.ceil[f64](s))
    let r = math.round[f64](s)
    if math.abs[f64](r - s) <= s * 1.0e-5f64 { t = usize(r) }
    if t < cur { t = cur }
    ret t
}

// heidel.diag(x, eps, pvalue) for one series into out: stest, start, pvalue, htest, mean, halfwidth (NaN where R gives NA)
fn heidel(a: *mem.Arena, x: []const f64, eps: f64, pv: f64, out: []f64) -> err {
    let nan = 0.0f64 / 0.0f64
    let n = x.len
    let nf = f64(n)
    let t0 = win_start(nf / 2.0f64, 1usize)
    let (s0, o0, e0) = spec0(a, x[t0 - 1usize..n])
    if e0 != ok { ret e0 }
    let by = nf / 10.0f64
    let nn = usize(math.floor[f64]((nf / 2.0f64 - 1.0f64) / by + 1.0e-10f64))
    var cur = 1usize
    var conv = false
    var iv = nan
    var k = 0usize
    while k <= nn {
        var s = 1.0f64 + f64(k) * by
        if s > nf / 2.0f64 { s = nf / 2.0f64 }
        cur = win_start(s, cur)
        let y = x[cur - 1usize..n]
        let m = y.len
        let yb = mean_of(y)
        var cs = 0.0f64
        var tot = 0.0f64
        var i = 0usize
        while i < m {
            cs += y[i]
            let b = cs - yb * f64(i + 1usize)
            tot += b * b / (f64(m) * s0)
            i += 1usize
        }
        iv = tot / f64(m)
        conv = false
        if iv == iv && pcramer(iv) < 1.0f64 - pv { conv = true }
        if conv { break }
        k += 1usize
    }
    let y = x[cur - 1usize..n]
    let (sci, oc, ec) = spec0(a, y)
    if ec != ok { ret ec }
    let yb = mean_of(y)
    let hw = 1.96f64 * math.sqrt[f64](sci / f64(y.len))
    var passed = 0.0f64
    if math.abs[f64](hw / yb) <= eps { passed = 1.0f64 }
    out[0usize] = 0.0f64
    if conv { out[0usize] = 1.0f64 }
    out[2usize] = 1.0f64 - pcramer(iv)
    if !conv || iv != iv || hw != hw {
        out[1usize] = nan
        out[3usize] = nan
        out[4usize] = nan
        out[5usize] = nan
    } else {
        out[1usize] = f64(cur)
        out[3usize] = passed
        out[4usize] = yb
        out[5usize] = hw
    }
    ret ok
}

// the largest eigenvalue of the symmetric p by p matrix m (cyclic Jacobi; m is destroyed)
fn jacobi_max(m: []f64, p: usize) -> f64 {
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
        if off < 1.0e-300f64 { break }
        i = 0usize
        while i < p {
            var j = i + 1usize
            while j < p {
                let apq = m[i * p + j]
                if apq != 0.0f64 {
                    let th = (m[j * p + j] - m[i * p + i]) / (2.0f64 * apq)
                    var t = 1.0f64 / (math.abs[f64](th) + math.sqrt[f64](th * th + 1.0f64))
                    if th < 0.0f64 { t = 0.0f64 - t }
                    let cs = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let sn = t * cs
                    var k = 0usize
                    while k < p {
                        let akp = m[k * p + i]
                        let akq = m[k * p + j]
                        m[k * p + i] = cs * akp - sn * akq
                        m[k * p + j] = sn * akp + cs * akq
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let apk = m[i * p + k]
                        let aqk = m[j * p + k]
                        m[i * p + k] = cs * apk - sn * aqk
                        m[j * p + k] = sn * apk + cs * aqk
                        k += 1usize
                    }
                }
                j += 1usize
            }
            i += 1usize
        }
        sweep += 1usize
    }
    var mx = m[0usize]
    var i2 = 1usize
    while i2 < p {
        if m[i2 * p + i2] > mx { mx = m[i2 * p + i2] }
        i2 += 1usize
    }
    ret mx
}

// solve L X = rhs for lower-triangular L (p by p) with p columns, into x
fn lsolve(lm: []const f64, rhs: []const f64, x: []f64, p: usize) {
    var j = 0usize
    while j < p {
        var r = 0usize
        while r < p {
            var s = rhs[r * p + j]
            var k = 0usize
            while k < r {
                s -= lm[r * p + k] * x[k * p + j]
                k += 1usize
            }
            x[r * p + j] = s / lm[r * p + r]
            r += 1usize
        }
        j += 1usize
    }
}

// gelman.diag multivariate psrf of nchain chains of niter0 draws of nvar variables (chain-major, each chain niter0 rows of nvar), the first half dropped (R keeps floor(niter0 / 2)): sqrt((1 - 1/N) + (1 + 1/p) emax / N)
fn gelman_mpsrf(a: *mem.Arena, d: []const f64, nchain: usize, niter0: usize, nvar: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let drop = niter0 - niter0 / 2usize
    let niter = niter0 - drop
    let p = nvar
    let (w, e1) = mem.alloc[f64](a, p * p)
    let (xb, e2) = mem.alloc[f64](a, p * nchain)
    let (col, e3) = mem.alloc[f64](a, niter * p)
    let (bm, e4) = mem.alloc[f64](a, p * p)
    let (lm, e5) = mem.alloc[f64](a, p * p)
    let (mm, e6) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret nan }
    var i = 0usize
    while i < p * p {
        w[i] = 0.0f64
        lm[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < nchain {
        var u = 0usize
        while u < p {
            var r = 0usize
            while r < niter {
                col[u * niter + r] = d[c * niter0 * p + (drop + r) * p + u]
                r += 1usize
            }
            xb[u * nchain + c] = mean_of(col[u * niter..(u + 1usize) * niter])
            u += 1usize
        }
        u = 0usize
        while u < p {
            var v = 0usize
            while v < p {
                w[u * p + v] += cov_of(col[u * niter..(u + 1usize) * niter], col[v * niter..(v + 1usize) * niter]) / f64(nchain)
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
            bm[u * p + v] = f64(niter) * cov_of(xb[u * nchain..(u + 1usize) * nchain], xb[v * nchain..(v + 1usize) * nchain])
            v += 1usize
        }
        u += 1usize
    }
    var r = 0usize
    while r < p {
        var q = 0usize
        while q <= r {
            var s = w[r * p + q]
            var k = 0usize
            while k < q {
                s -= lm[r * p + k] * lm[q * p + k]
                k += 1usize
            }
            if r == q { lm[r * p + q] = math.sqrt[f64](s) } else { lm[r * p + q] = s / lm[q * p + q] }
            q += 1usize
        }
        r += 1usize
    }
    lsolve(lm, bm, mm, p)
    r = 0usize
    while r < p {
        var q = 0usize
        while q < p {
            bm[r * p + q] = mm[q * p + r]
            q += 1usize
        }
        r += 1usize
    }
    lsolve(lm, bm, mm, p)
    let emax = jacobi_max(mm, p)
    let nn = f64(niter)
    ret math.sqrt[f64]((1.0f64 - 1.0f64 / nn) + (1.0f64 + 1.0f64 / f64(p)) * emax / nn)
}

// cor(x)[u, v] of an n by nvar row-major matrix
fn crosscorr(x: []const f64, n: usize, nvar: usize, u: usize, v: usize) -> f64 {
    ret acf_cross(x, n, nvar, u, v, 0usize)
}

// acf(x)$acf[lag + 1, u, v] of a multivariate series (n by nvar row-major): sum_t (x_u[t + lag] - m_u)(x_v[t] - m_v) / n over sqrt(c_uu(0) c_vv(0)) (the n cancels)
fn acf_cross(x: []const f64, n: usize, nvar: usize, u: usize, v: usize, lag: usize) -> f64 {
    var a1 = 0.0f64
    var b1 = 0.0f64
    var i = 0usize
    while i < n {
        a1 += x[i * nvar + u]
        b1 += x[i * nvar + v]
        i += 1usize
    }
    a1 = a1 / f64(n)
    b1 = b1 / f64(n)
    var s = 0.0f64
    var su = 0.0f64
    var sv = 0.0f64
    i = 0usize
    while i < n {
        let du = x[i * nvar + u] - a1
        let dv = x[i * nvar + v] - b1
        su += du * du
        sv += dv * dv
        if i + lag < n { s += (x[(i + lag) * nvar + u] - a1) * dv }
        i += 1usize
    }
    ret s / math.sqrt[f64](su * sv)
}
