// R coda: the autocorrelations of acf, the Yule-Walker autoregression of ar(aic = TRUE) behind spectrum0.ar, and effectiveSize for one chain.
//
// Not here: the multiple-chain diagnostics (gelman.diag, geweke.diag, heidel.diag, raftery.diag), HPDinterval and cramer.test.

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
    let niter = niter0 - half
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
