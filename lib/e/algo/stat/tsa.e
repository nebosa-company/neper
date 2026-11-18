// R TSA: the raw periodogram of a series as TSA::periodogram gives it: the mean is removed, the series is padded with zeros to the next
// length N that has only the factors 2, 3 and 5 (stats::nextn, as spec.pgram does), and the value at the frequency j / N, j = 1 .. floor(N / 2),
// is 2 |F_j|^2 / n for the original length n, halved at the Nyquist frequency 1/2.
//
// detectAO on the fitted pieces (residuals, phi, theta, sigma2). Not here: armasubsets, detectIO, arimax, the cumulative periodogram, the BIC table and
// the diagnostics; the fit itself is not here (the coefficients and residuals are inputs).

use e.math
use e.math.nmath as nm
use e.math.dist as dist
use e.algo.linalg.decomp as decomp
use e.mem

error Malformed

// the smallest N >= n whose prime factors are only 2, 3 and 5
fn nextn(n: usize) -> usize {
    var m = n
    while true {
        var r = m
        while r % 2usize == 0usize { r = r / 2usize }
        while r % 3usize == 0usize { r = r / 3usize }
        while r % 5usize == 0usize { r = r / 5usize }
        if r == 1usize { ret m }
        m += 1usize
    }
    ret m
}

// out needs floor(nextn(n) / 2) entries; the count written is returned
fn periodogram(y: []const f64, out: []f64) -> usize {
    let n = y.len
    let big = nextn(n)
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += y[i]
        i += 1usize
    }
    m = m / f64(n)
    let h = big / 2usize
    var j = 1usize
    while j <= h {
        var re = 0.0f64
        var im = 0.0f64
        i = 0usize
        while i < n {
            let ang = 2.0f64 * 3.141592653589793238462643383279f64 * f64(j) * f64(i) / f64(big)
            re += (y[i] - m) * math.cos[f64](ang)
            im -= (y[i] - m) * math.sin[f64](ang)
            i += 1usize
        }
        var v = 2.0f64 * (re * re + im * im) / f64(n)
        // the package halves the entry whose frequency equals 0.5 exactly; the frequency is built as seq.int(1 / N, by = 1 / N)
        let freq = 1.0f64 / f64(big) + f64(j - 1usize) * (1.0f64 / f64(big))
        if freq == 0.5f64 { v = v / 2.0f64 }
        out[j - 1usize] = v
        j += 1usize
    }
    ret h
}

// the autocorrelation of x at lags 0 .. lag (R's acf: the mean removed, divided by n at every lag)
fn acf_upto(x: []const f64, lag: usize, out: []f64) {
    let n = x.len
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += x[i]
        i += 1usize
    }
    m = m / f64(n)
    var k = 0usize
    while k <= lag {
        var s = 0.0f64
        i = 0usize
        while i + k < n {
            s += (x[i + k] - m) * (x[i] - m)
            i += 1usize
        }
        out[k] = s / f64(n)
        k += 1usize
    }
    k = 1usize
    while k <= lag {
        out[k] = out[k] / out[0usize]
        k += 1usize
    }
    out[0usize] = 1.0f64
}

// McLeod.Li.test(y = x): the Ljung-Box p value of the squared series at lags 1 .. gof, from the autocorrelations at lags 1 .. lag (TSA masks acf with
// a version that drops lag 0), each divided by n - k
fn mcleod_li(a: *mem.Arena, x: []const f64, gof: usize, out: []f64) -> err {
    let n = x.len
    let (sq, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        sq[i] = x[i] * x[i]
        i += 1usize
    }
    let (r, e2) = mem.alloc[f64](a, gof + 1usize)
    if e2 != ok { ret e2 }
    var lag = 1usize
    while lag <= gof {
        acf_upto(sq, lag, r)
        var s = 0.0f64
        var k = 1usize
        while k <= lag {
            s += r[k] * r[k] / (f64(n) - f64(k))
            k += 1usize
        }
        let stat = f64(n) * (f64(n) + 2.0f64) * s
        out[lag - 1usize] = 1.0f64 - nm.pchisq(stat, f64(lag), true, false)
        lag += 1usize
    }
    ret ok
}

// eacf(z, ar.max, ma.max)$eacf: the extended sample autocorrelations (ar.max + 1 rows, ma.max + 1 columns, row-major in out) from the iterated ARMA coefficient recursions of Tsay and Tiao,
// the AR(i) coefficients being the least-squares fits without intercept
fn eacf(a: *mem.Arena, z0: []const f64, armax: usize, mamax: usize, out: []f64) -> err {
    let n = z0.len
    let nar = armax
    let nma = mamax + 1usize
    let nrow = nar + nma + 1usize
    var ncol = nrow - 1usize
    let ncol0 = ncol
    let (z, e1) = mem.alloc[f64](a, n)
    let (m1, e2) = mem.alloc[f64](a, nrow * ncol0)
    let (m2, e3) = mem.alloc[f64](a, nrow * ncol0)
    let (acfz, e4) = mem.alloc[f64](a, nar + nma + 4usize)
    let (temp, e5) = mem.alloc[f64](a, n)
    let (ta, e6) = mem.alloc[f64](a, nar + nma + 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += z0[i]
        i += 1usize
    }
    mean = mean / f64(n)
    i = 0usize
    while i < n {
        z[i] = z0[i] - mean
        i += 1usize
    }
    i = 0usize
    while i < nrow * ncol0 {
        m1[i] = 0.0f64
        m2[i] = 0.0f64
        i += 1usize
    }
    acf_upto(z, nar + nma + 2usize, acfz)
    // ar.ols(z, order.max = i, aic = FALSE, demean = FALSE, intercept = FALSE)$ar for i = 1 .. ncol0
    var ord = 1usize
    while ord <= ncol0 {
        let rows = n - ord
        let (xd, ex) = mem.alloc[f64](a, rows * ord)
        let (yd, ey) = mem.alloc[f64](a, rows)
        if ex != ok || ey != ok { ret mem.Full }
        var t = 0usize
        while t < rows {
            yd[t] = z[ord + t]
            var j = 1usize
            while j <= ord {
                xd[(j - 1usize) * rows + t] = z[ord + t - j]
                j += 1usize
            }
            t += 1usize
        }
        let (f, fe) = decomp.lm_fit(a, xd, rows, ord, yd, 1.0e-7f64)
        if fe != ok { ret fe }
        var j = 0usize
        while j < ord {
            m1[(ord - 1usize) * nrow + j] = f.coef[j]
            j += 1usize
        }
        ord += 1usize
    }
    var it = 1usize
    while it <= nma {
        // reupm(m1, nrow, ncol): ncol - 1 columns
        var k = 0usize
        while k + 1usize < ncol {
            let i1 = k + 1usize
            var r = 0usize
            while r < nrow {
                var work = 0.0f64 - 1.0f64
                if r > 0usize { work = m1[k * nrow + r - 1usize] }
                m2[k * nrow + r] = m1[i1 * nrow + r] - work * m1[i1 * nrow + i1] / m1[k * nrow + k]
                r += 1usize
            }
            m2[k * nrow + i1] = 0.0f64
            k += 1usize
        }
        ncol = ncol - 1usize
        // ceascf: the lag-it autocorrelation of z and of its residuals after each of the AR(i) filters
        if it <= mamax + 1usize && it - 1usize <= mamax {
            out[it - 1usize] = acfz[it]
        }
        var arow = 1usize
        while arow <= nar {
            var tt = arow
            while tt < n {
                var v = z[tt]
                var j = 1usize
                while j <= arow {
                    v -= m2[(arow - 1usize) * nrow + (j - 1usize)] * z[tt - j]
                    j += 1usize
                }
                temp[tt - arow] = v
                tt += 1usize
            }
            acf_upto(temp[0usize..n - arow], it, ta)
            if it - 1usize <= mamax { out[arow * (mamax + 1usize) + it - 1usize] = ta[it] }
            arow += 1usize
        }
        // m1 = m2
        i = 0usize
        while i < nrow * ncol0 {
            m1[i] = m2[i]
            i += 1usize
        }
        it += 1usize
    }
    ret ok
}

// ---- detectAO (TSA): the additive outliers of an ARMA fit from its residuals and coefficients. piwt holds the first n MA(inf) weights of the model
// ARMAtoMA(ar = -theta, ma = -phi) (phi and theta as TSA's object$mod$phi and object$mod$theta), omega_m is the convolution of piwt with the
// reversed residuals (zero before the start), rho2_m = 1 / sum_{k < m} piwt_k^2, lambda_m = omega_m rho2_m / sigma / sqrt(rho2_m), and the
// outliers are the values of rev(lambda) with |lambda| above qnorm(1 - alpha / (2 n)). sigma is sqrt(pi / 2) mean |resid| when robust, else sqrt(sigma2).
// ind_out gets the 1-based positions in rev(lambda) and lam_out their values; the count is returned.
fn detect_ao(a: *mem.Arena, resid: []const f64, n: usize, phi: []const f64, theta: []const f64, sigma2: f64, robust: bool, alpha: f64,
             ind_out: []usize, lam_out: []f64) -> (usize, err) {
    let (ar, e1) = mem.alloc[f64](a, theta.len)
    let (ma, e2) = mem.alloc[f64](a, phi.len)
    let (psi, e3) = mem.alloc[f64](a, n)
    let (rho2, e4) = mem.alloc[f64](a, n)
    let (lam, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0usize, Malformed) }
    var i = 0usize
    while i < theta.len {
        ar[i] = 0.0f64 - theta[i]
        i += 1usize
    }
    i = 0usize
    while i < phi.len {
        ma[i] = 0.0f64 - phi[i]
        i += 1usize
    }
    // psi_0 = 1, psi_j = ma_j + sum_{i <= min(j, p)} ar_i psi_{j - i} (ma_j = 0 past q)
    psi[0usize] = 1.0f64
    var j = 1usize
    while j < n {
        var v = 0.0f64
        if j <= ma.len { v = ma[j - 1usize] }
        var k = 1usize
        while k <= j && k <= ar.len {
            v += ar[k - 1usize] * psi[j - k]
            k += 1usize
        }
        psi[j] = v
        j += 1usize
    }
    var cs = 0.0f64
    var sabs = 0.0f64
    i = 0usize
    while i < n {
        cs += psi[i] * psi[i]
        rho2[i] = 1.0f64 / cs
        sabs += math.abs[f64](resid[i])
        i += 1usize
    }
    var sigma = math.sqrt[f64](sigma2)
    if robust { sigma = math.sqrt[f64](3.141592653589793f64 / 2.0f64) * sabs / f64(n) }
    // omega_m for m = 1..n: sum_{k < n} psi_k g(n - 1 + m - k) with g(s) = resid[2n - 1 - s] for s >= n, else 0
    var m = 1usize
    while m <= n {
        var om = 0.0f64
        var k = 0usize
        while k < n {
            let s = n - 1usize + m - k
            if s >= n { om += psi[k] * resid[2usize * n - 1usize - s] }
            k += 1usize
        }
        lam[m - 1usize] = om * rho2[m - 1usize] / sigma / math.sqrt[f64](rho2[m - 1usize])
        m += 1usize
    }
    let cutoff = dist.qnorm(1.0f64 - alpha / 2.0f64 / f64(n), 0.0f64, 1.0f64, true, false)
    var count = 0usize
    var p = 0usize
    while p < n {
        let v = lam[n - 1usize - p]
        if math.abs[f64](v) > cutoff {
            if count >= ind_out.len { ret (count, Malformed) }
            ind_out[count] = p + 1usize
            lam_out[count] = v
            count += 1usize
        }
        p += 1usize
    }
    ret (count, ok)
}
