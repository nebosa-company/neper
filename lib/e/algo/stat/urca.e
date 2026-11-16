// R's urca unit-root tests: `ur_df` (augmented Dickey-Fuller with the model none, drift or trend, fixed
// lags or lag selection by AIC or BIC, its tau and phi statistics and the 1, 5 and 10 percent critical
// values of the tabulated sample size) and `ur_kpss` (level or trend, short, long or given lag).
//
// Not here: ur.pp, ur.ers, ur.za, ur.sp, ca.jo and ca.po.

use e.algo.linalg.decomp as decomp
use e.math
use e.mem

error TooShort

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// the residual sum of squares of y on the columns of x (n rows, column-major, p columns)
fn rss_of(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64) -> (f64, usize, err) {
    if p == 0usize {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += y[i] * y[i]
            i += 1usize
        }
        ret (s, 0usize, ok)
    }
    let (fit, e) = decomp.lm_fit(a, x, n, p, y, 1.0e-7f64)
    if e != ok { ret (0.0f64, 0usize, e) }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += fit.residuals[i] * fit.residuals[i]
        i += 1usize
    }
    ret (s, fit.rank, ok)
}

type DfResult = struct { tau: f64, phi_a: f64, phi_b: f64, lags: usize, n: usize }

// the regressors of the full model in column-major order: z.lag.1, then the intercept and trend when the
// type asks for them, then `nl` differenced lags
fn design(a: *mem.Arena, ylag: []const f64, zlags: []const f64, rows: usize, qtype: u8, nl: usize, tt0: usize) -> ([]f64, usize, err) {
    var ncol = 1usize + nl
    if qtype >= 1u8 { ncol += 1usize }
    if qtype == 2u8 { ncol += 1usize }
    let (x, e) = mem.alloc[f64](a, rows * ncol)
    if e != ok { ret (x, 0usize, e) }
    var c = 0usize
    var i = 0usize
    while i < rows {
        x[i] = ylag[i]
        i += 1usize
    }
    c = 1usize
    if qtype >= 1u8 {
        i = 0usize
        while i < rows {
            x[c * rows + i] = 1.0f64
            i += 1usize
        }
        c += 1usize
    }
    if qtype == 2u8 {
        i = 0usize
        while i < rows {
            x[c * rows + i] = f64(tt0 + i)
            i += 1usize
        }
        c += 1usize
    }
    var l = 0usize
    while l < nl {
        i = 0usize
        while i < rows {
            x[c * rows + i] = zlags[l * rows + i]
            i += 1usize
        }
        c += 1usize
        l += 1usize
    }
    ret (x, ncol, ok)
}

// ur.df(y, type, lags, selectlags); qtype 0 none, 1 drift, 2 trend; select 0 fixed, 1 AIC, 2 BIC
fn ur_df(a: *mem.Arena, y: []const f64, qtype: u8, lags0: usize, select: u8) -> (DfResult, err) {
    var none: DfResult = zero
    let n = y.len - 1usize
    var lags = lags0 + 1usize
    if n < lags + 3usize { ret (none, TooShort) }
    let rows = n - lags + 1usize
    let tt_init = lags
    // z = diff(y); x = embed(z, lags): column l (l = 0 the response z[t], l = 1.. lagged z) of row r is z[lags - 1 - l + r]
    let (z, ze) = mem.alloc[f64](a, n)
    if ze != ok { ret (none, ze) }
    var i = 0usize
    while i < n {
        z[i] = y[i + 1usize] - y[i]
        i += 1usize
    }
    let (zd, zde) = mem.alloc[f64](a, rows)
    let (ylag, yle) = mem.alloc[f64](a, rows)
    let (zl, zle) = mem.alloc[f64](a, rows * lags)
    if zde != ok { ret (none, zde) }
    if yle != ok { ret (none, yle) }
    if zle != ok { ret (none, zle) }
    i = 0usize
    while i < rows {
        zd[i] = z[lags - 1usize + i]
        ylag[i] = y[lags - 1usize + i]
        var l = 1usize
        while l < lags {
            zl[(l - 1usize) * rows + i] = z[lags - 1usize - l + i]
            l += 1usize
        }
        i += 1usize
    }
    var nl = lags - 1usize
    if select != 0u8 && lags > 1usize {
        var best = 1.0e308f64
        var bi = 2usize
        var m = 2usize
        while m <= lags {
            let (xm, nc, de) = design(a, ylag, zl, rows, qtype, m - 1usize, tt_init)
            if de != ok { ret (none, de) }
            let (rss, rk, re) = rss_of(a, xm, rows, nc, zd)
            if re != ok { ret (none, re) }
            let nf = f64(rows)
            var kpen = 2.0f64
            if select == 2u8 { kpen = math.log[f64](nf) }
            let aic = nf * (math.log[f64](2.0f64 * 3.141592653589793f64) + math.log[f64](rss / nf) + 1.0f64) + kpen * f64(rk + 1usize)
            if aic < best {
                best = aic
                bi = m
            }
            m += 1usize
        }
        lags = bi
        nl = lags - 1usize
    }
    let (xf, ncol, de) = design(a, ylag, zl, rows, qtype, nl, tt_init)
    if de != ok { ret (none, de) }
    let (rss_full, rk, re) = rss_of(a, xf, rows, ncol, zd)
    if re != ok { ret (none, re) }
    let nf = f64(rows)
    let sigma2 = rss_full / (nf - f64(rk))
    // tau: the t value of z.lag.1 = b / sqrt(sigma2 / RSS of z.lag.1 on the other columns)
    let (fitf, fe) = decomp.lm_fit(a, xf, rows, ncol, zd, 1.0e-7f64)
    if fe != ok { ret (none, fe) }
    let b1 = fitf.coef[0usize]
    var rss1 = 0.0f64
    if ncol == 1usize {
        i = 0usize
        while i < rows {
            rss1 += ylag[i] * ylag[i]
            i += 1usize
        }
    } else {
        let (xo, oe) = mem.alloc[f64](a, rows * (ncol - 1usize))
        if oe != ok { ret (none, oe) }
        i = 0usize
        while i < rows * (ncol - 1usize) {
            xo[i] = xf[rows + i]
            i += 1usize
        }
        let (r1, rk1, e1) = rss_of(a, xo, rows, ncol - 1usize, ylag)
        if e1 != ok { ret (none, e1) }
        rss1 = r1
    }
    let tau = b1 / math.sqrt[f64](sigma2 / rss1)
    var phi_a = nan()
    var phi_b = nan()
    if qtype >= 1u8 {
        // restricted models: only the differenced lags (no intercept), and for trend also lags + intercept
        let (xr, rr) = mem.alloc[f64](a, rows * (nl + 1usize))
        if rr != ok { ret (none, rr) }
        i = 0usize
        while i < rows * nl {
            xr[i] = zl[i]
            i += 1usize
        }
        let (rss_r, rkr, er) = rss_of(a, xr, rows, nl, zd)
        if er != ok { ret (none, er) }
        var q = 2.0f64
        if qtype == 1u8 { q = 2.0f64 }
        if qtype == 1u8 {
            phi_a = ((rss_r - rss_full) / 2.0f64) / (rss_full / (nf - f64(rk)))
        } else {
            phi_a = ((rss_r - rss_full) / 3.0f64) / (rss_full / (nf - f64(rk)))
            // phi3: the lags and an intercept
            i = 0usize
            while i < rows {
                xr[nl * rows + i] = 1.0f64
                i += 1usize
            }
            let (rss_3, rk3, e3) = rss_of(a, xr, rows, nl + 1usize, zd)
            if e3 != ok { ret (none, e3) }
            phi_b = ((rss_3 - rss_full) / 2.0f64) / (rss_full / (nf - f64(rk)))
        }
    }
    ret (DfResult { tau: tau, phi_a: phi_a, phi_b: phi_b, lags: lags - 1usize, n: n }, ok)
}

fn row_of(n: usize) -> usize {
    if n < 25usize { ret 0usize }
    if n < 50usize { ret 1usize }
    if n < 100usize { ret 2usize }
    if n < 250usize { ret 3usize }
    if n < 500usize { ret 4usize }
    ret 5usize
}

// the critical value of statistic `which` (0 tau, 1 first phi, 2 second phi) at level 0 (1 pct), 1 (5 pct), 2 (10 pct)
fn df_critical(qtype: u8, which: usize, level: usize, n: usize) -> f64 {
    let r = row_of(n)
    var t: [18]f64 = zero
    if qtype == 0u8 {
        t[0usize] = 0.0f64 - 2.66f64
        t[1usize] = 0.0f64 - 1.95f64
        t[2usize] = 0.0f64 - 1.6f64
        t[3usize] = 0.0f64 - 2.62f64
        t[4usize] = 0.0f64 - 1.95f64
        t[5usize] = 0.0f64 - 1.61f64
        t[6usize] = 0.0f64 - 2.6f64
        t[7usize] = 0.0f64 - 1.95f64
        t[8usize] = 0.0f64 - 1.61f64
        t[9usize] = 0.0f64 - 2.58f64
        t[10usize] = 0.0f64 - 1.95f64
        t[11usize] = 0.0f64 - 1.62f64
        t[12usize] = 0.0f64 - 2.58f64
        t[13usize] = 0.0f64 - 1.95f64
        t[14usize] = 0.0f64 - 1.62f64
        t[15usize] = 0.0f64 - 2.58f64
        t[16usize] = 0.0f64 - 1.95f64
        t[17usize] = 0.0f64 - 1.62f64
        ret t[r * 3usize + level]
    }
    if qtype == 1u8 && which == 0usize {
        t[0usize] = 0.0f64 - 3.75f64
        t[1usize] = 0.0f64 - 3.0f64
        t[2usize] = 0.0f64 - 2.63f64
        t[3usize] = 0.0f64 - 3.58f64
        t[4usize] = 0.0f64 - 2.93f64
        t[5usize] = 0.0f64 - 2.6f64
        t[6usize] = 0.0f64 - 3.51f64
        t[7usize] = 0.0f64 - 2.89f64
        t[8usize] = 0.0f64 - 2.58f64
        t[9usize] = 0.0f64 - 3.46f64
        t[10usize] = 0.0f64 - 2.88f64
        t[11usize] = 0.0f64 - 2.57f64
        t[12usize] = 0.0f64 - 3.44f64
        t[13usize] = 0.0f64 - 2.87f64
        t[14usize] = 0.0f64 - 2.57f64
        t[15usize] = 0.0f64 - 3.43f64
        t[16usize] = 0.0f64 - 2.86f64
        t[17usize] = 0.0f64 - 2.57f64
        ret t[r * 3usize + level]
    }
    if qtype == 1u8 {
        t[0usize] = 7.88f64
        t[1usize] = 5.18f64
        t[2usize] = 4.12f64
        t[3usize] = 7.06f64
        t[4usize] = 4.86f64
        t[5usize] = 3.94f64
        t[6usize] = 6.7f64
        t[7usize] = 4.71f64
        t[8usize] = 3.86f64
        t[9usize] = 6.52f64
        t[10usize] = 4.63f64
        t[11usize] = 3.81f64
        t[12usize] = 6.47f64
        t[13usize] = 4.61f64
        t[14usize] = 3.79f64
        t[15usize] = 6.43f64
        t[16usize] = 4.59f64
        t[17usize] = 3.78f64
        ret t[r * 3usize + level]
    }
    if which == 0usize {
        t[0usize] = 0.0f64 - 4.38f64
        t[1usize] = 0.0f64 - 3.6f64
        t[2usize] = 0.0f64 - 3.24f64
        t[3usize] = 0.0f64 - 4.15f64
        t[4usize] = 0.0f64 - 3.5f64
        t[5usize] = 0.0f64 - 3.18f64
        t[6usize] = 0.0f64 - 4.04f64
        t[7usize] = 0.0f64 - 3.45f64
        t[8usize] = 0.0f64 - 3.15f64
        t[9usize] = 0.0f64 - 3.99f64
        t[10usize] = 0.0f64 - 3.43f64
        t[11usize] = 0.0f64 - 3.13f64
        t[12usize] = 0.0f64 - 3.98f64
        t[13usize] = 0.0f64 - 3.42f64
        t[14usize] = 0.0f64 - 3.13f64
        t[15usize] = 0.0f64 - 3.96f64
        t[16usize] = 0.0f64 - 3.41f64
        t[17usize] = 0.0f64 - 3.12f64
        ret t[r * 3usize + level]
    }
    if which == 1usize {
        t[0usize] = 8.21f64
        t[1usize] = 5.68f64
        t[2usize] = 4.67f64
        t[3usize] = 7.02f64
        t[4usize] = 5.13f64
        t[5usize] = 4.31f64
        t[6usize] = 6.5f64
        t[7usize] = 4.88f64
        t[8usize] = 4.16f64
        t[9usize] = 6.22f64
        t[10usize] = 4.75f64
        t[11usize] = 4.07f64
        t[12usize] = 6.15f64
        t[13usize] = 4.71f64
        t[14usize] = 4.05f64
        t[15usize] = 6.09f64
        t[16usize] = 4.68f64
        t[17usize] = 4.03f64
        ret t[r * 3usize + level]
    }
    t[0usize] = 10.61f64
    t[1usize] = 7.24f64
    t[2usize] = 5.91f64
    t[3usize] = 9.31f64
    t[4usize] = 6.73f64
    t[5usize] = 5.61f64
    t[6usize] = 8.73f64
    t[7usize] = 6.49f64
    t[8usize] = 5.47f64
    t[9usize] = 8.43f64
    t[10usize] = 6.49f64
    t[11usize] = 5.47f64
    t[12usize] = 8.34f64
    t[13usize] = 6.3f64
    t[14usize] = 5.36f64
    t[15usize] = 8.27f64
    t[16usize] = 6.25f64
    t[17usize] = 5.34f64
    ret t[r * 3usize + level]
}

// ur.kpss(y, type, lags): qtype 0 mu, 1 tau; lags 0 short, 1 long, 2 nil, 3 use `use_lag`
fn ur_kpss(a: *mem.Arena, y: []const f64, qtype: u8, lags: u8, use_lag: usize) -> (f64, usize, err) {
    let n = y.len
    let nf = f64(n)
    var lmax = 0usize
    if lags == 0u8 { lmax = usize(math.floor[f64](4.0f64 * math.pow[f64](nf / 100.0f64, 0.25f64))) }
    if lags == 1u8 { lmax = usize(math.floor[f64](12.0f64 * math.pow[f64](nf / 100.0f64, 0.25f64))) }
    if lags == 3u8 { lmax = use_lag }
    let (res, re) = mem.alloc[f64](a, n)
    if re != ok { ret (0.0f64, 0usize, re) }
    var i = 0usize
    if qtype == 0u8 {
        var m = 0.0f64
        while i < n {
            m += y[i]
            i += 1usize
        }
        m = m / nf
        i = 0usize
        while i < n {
            res[i] = y[i] - m
            i += 1usize
        }
    } else {
        let (x, xe) = mem.alloc[f64](a, n * 2usize)
        if xe != ok { ret (0.0f64, 0usize, xe) }
        while i < n {
            x[i] = 1.0f64
            x[n + i] = f64(i + 1usize)
            i += 1usize
        }
        let (fit, fe) = decomp.lm_fit(a, x, n, 2usize, y, 1.0e-7f64)
        if fe != ok { ret (0.0f64, 0usize, fe) }
        i = 0usize
        while i < n {
            res[i] = fit.residuals[i]
            i += 1usize
        }
    }
    var s = 0.0f64
    var nom = 0.0f64
    var s2 = 0.0f64
    i = 0usize
    while i < n {
        s += res[i]
        nom += s * s
        s2 += res[i] * res[i]
        i += 1usize
    }
    nom = nom / (nf * nf)
    s2 = s2 / nf
    var den = s2
    if lmax > 0usize {
        var acc = 0.0f64
        var l = 1usize
        while l <= lmax {
            var cv = 0.0f64
            i = l
            while i < n {
                cv += res[i] * res[i - l]
                i += 1usize
            }
            acc += (1.0f64 - f64(l) / f64(lmax + 1usize)) * cv
            l += 1usize
        }
        den = s2 + 2.0f64 / nf * acc
    }
    ret (nom / den, lmax, ok)
}
