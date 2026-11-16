// R urca's Phillips-Perron (`ur.pp`), Elliott-Rothenberg-Stock (`ur.ers`, DF-GLS and P-test) and Zivot-Andrews (`ur.za`)
// unit-root tests: the statistic and the critical values of the package.
//
// Not here: ur.sp, ca.jo and ca.po.

use e.algo.stat.olsfit as ols
use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

type Pp = struct { stat: f64, cval1: f64, cval5: f64, cval10: f64, lag: usize }

// ur.pp(x, type = Z-alpha (0) or Z-tau (1), model = constant (0) or trend (1), lags: lmax given, -1 short, -2 long)
fn ur_pp(a: *mem.Arena, x: []const f64, qtype: u8, model: u8, lagsel: i64) -> (Pp, err) {
    var out: Pp = zero
    let n0 = x.len
    let n = n0 - 1usize
    let nf = f64(n)
    var lmax = usize(math.floor[f64](4.0f64 * math.pow[f64](nf / 100.0f64, 0.25f64)))
    if lagsel >= 0i64 { lmax = usize(lagsel) }
    if lagsel == 0i64 - 2i64 { lmax = usize(math.floor[f64](12.0f64 * math.pow[f64](nf / 100.0f64, 0.25f64))) }
    let yy = x[1usize..n0]
    let yl = x[0usize..n]
    var np = 2usize
    if model == 1u8 { np = 3usize }
    let (d, de) = mem.alloc[f64](a, n * np)
    if de != ok { ret (out, de) }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        d[n + i] = yl[i]
        if model == 1u8 { d[2usize * n + i] = f64(i + 1usize) - nf / 2.0f64 }
        i += 1usize
    }
    let (o, oe) = ols.fit(a, d, n, np, yy)
    if oe != ok { ret (out, oe) }
    let res = o.resid
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += res[i] * res[i]
        i += 1usize
    }
    s = s / nf
    var ym = 0.0f64
    var sy = 0.0f64
    var syy = 0.0f64
    var sty = 0.0f64
    i = 0usize
    while i < n {
        sy += yy[i]
        syy += yy[i] * yy[i]
        sty += f64(i + 1usize) * yy[i]
        i += 1usize
    }
    ym = sy / nf
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (yy[i] - ym) * (yy[i] - ym)
        i += 1usize
    }
    let myybar = ss / (nf * nf)
    let myy = syy / (nf * nf)
    let my = math.pow[f64](nf, 0.0f64 - 1.5f64) * sy
    let mty = math.pow[f64](nf, 0.0f64 - 2.5f64) * sty
    var acc = 0.0f64
    var l = 1usize
    while l <= lmax {
        var cp = 0.0f64
        i = l
        while i < n {
            cp += res[i] * res[i - l]
            i += 1usize
        }
        acc += (1.0f64 - f64(l) / f64(lmax + 1usize)) * cp
        l += 1usize
    }
    let sig = s + (2.0f64 / nf) * acc
    let lambda = 0.5f64 * (sig - s)
    let lambdap = lambda / sig
    let n2 = nf * nf
    var mm = 0.0f64
    if model == 1u8 {
        mm = (1.0f64 - 1.0f64 / n2) * myy - 12.0f64 * mty * mty + 12.0f64 * (1.0f64 + 1.0f64 / nf) * mty * my - (4.0f64 + 6.0f64 / nf + 2.0f64 / n2) * my * my
        out.cval1 = 0.0f64 - 3.9638f64 - 8.353f64 / nf - 47.44f64 / n2
        out.cval5 = 0.0f64 - 3.4126f64 - 4.039f64 / nf - 17.83f64 / n2
        out.cval10 = 0.0f64 - 3.1279f64 - 2.418f64 / nf - 7.58f64 / n2
    } else {
        out.cval1 = 0.0f64 - 3.4335f64 - 5.999f64 / nf - 29.25f64 / n2
        out.cval5 = 0.0f64 - 2.8621f64 - 2.738f64 / nf - 8.36f64 / n2
        out.cval10 = 0.0f64 - 2.5671f64 - 1.438f64 / nf - 4.48f64 / n2
    }
    let alpha = o.coef[1usize]
    if qtype == 1u8 {
        let tstat = (alpha - 1.0f64) / o.se[1usize]
        if model == 1u8 { out.stat = math.sqrt[f64](s / sig) * tstat - lambdap * math.sqrt[f64](sig) / math.sqrt[f64](mm) } else { out.stat = math.sqrt[f64](s / sig) * tstat - lambdap * math.sqrt[f64](sig) / math.sqrt[f64](myybar) }
    } else {
        if model == 1u8 { out.stat = nf * (alpha - 1.0f64) - lambda / mm } else { out.stat = nf * (alpha - 1.0f64) - lambda / myybar }
        out.cval1 = nan()
        out.cval5 = nan()
        out.cval10 = nan()
    }
    out.lag = lmax
    ret (out, ok)
}

type Ers = struct { stat: f64, cval1: f64, cval5: f64, cval10: f64, lag: usize }

// the regression of diff(z) on z lagged and `nd` lagged differences (rows nd + 1 .. n - 1 of the differenced series), with an intercept
// when `icpt`; answers the fit
fn lag_reg(a: *mem.Arena, z: []const f64, n: usize, nd: usize, icpt: bool) -> (ols.Ols, usize, err) {
    var none: ols.Ols = zero
    let rows = n - 1usize - nd
    var np = 1usize + nd
    if icpt { np += 1usize }
    let (d, de) = mem.alloc[f64](a, rows * np)
    let (y, ye) = mem.alloc[f64](a, rows)
    if de != ok { ret (none, np, de) }
    if ye != ok { ret (none, np, ye) }
    var i = 0usize
    while i < rows {
        // differenced series index t = nd + i (0-based) is z[t + 1] - z[t]
        let t = nd + i
        y[i] = z[t + 1usize] - z[t]
        var c = 0usize
        if icpt {
            d[i] = 1.0f64
            c = 1usize
        }
        d[c * rows + i] = z[t]
        var q = 1usize
        while q <= nd {
            d[(c + q) * rows + i] = z[t - q + 1usize] - z[t - q]
            q += 1usize
        }
        i += 1usize
    }
    let (o, oe) = ols.fit(a, d, rows, np, y)
    ret (o, np, oe)
}

// ur.ers(y, type = DF-GLS (0) or P-test (1), model = constant (0) or trend (1), lag.max)
fn ur_ers(a: *mem.Arena, y: []const f64, qtype: u8, model: u8, lag_max: usize) -> (Ers, err) {
    var out: Ers = zero
    let nobs = y.len
    let nf = f64(nobs)
    var lm = lag_max + 1usize
    var rowsel = 0usize
    if nobs >= 50usize { rowsel = 1usize }
    if nobs >= 100usize { rowsel = 2usize }
    if nobs > 200usize { rowsel = 3usize }
    // the GLS detrending
    var ahat = 1.0f64 - 7.0f64 / nf
    if model == 1u8 { ahat = 1.0f64 - 13.5f64 / nf }
    let (ya, e1) = mem.alloc[f64](a, nobs)
    let (yd, e2) = mem.alloc[f64](a, nobs)
    let (za, e3) = mem.alloc[f64](a, nobs * 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret (out, e1) }
    ya[0usize] = y[0usize]
    za[0usize] = 1.0f64
    za[nobs] = 1.0f64
    var i = 1usize
    while i < nobs {
        ya[i] = y[i] - ahat * y[i - 1usize]
        za[i] = 1.0f64 - ahat
        za[nobs + i] = f64(i + 1usize) - ahat * f64(i)
        i += 1usize
    }
    var np = 1usize
    if model == 1u8 { np = 2usize }
    let (zc, zce) = mem.alloc[f64](a, nobs * np)
    if zce != ok { ret (out, zce) }
    i = 0usize
    while i < nobs {
        zc[i] = za[i]
        if np == 2usize { zc[nobs + i] = za[nobs + i] }
        i += 1usize
    }
    let (yr, yre) = ols.fit(a, zc, nobs, np, ya)
    if yre != ok { ret (out, yre) }
    i = 0usize
    while i < nobs {
        yd[i] = y[i] - yr.coef[0usize]
        if np == 2usize { yd[i] = yd[i] - yr.coef[1usize] * f64(i + 1usize) }
        i += 1usize
    }
    if qtype == 1u8 {
        var ssig = 0.0f64
        i = 0usize
        while i < nobs {
            ssig += yr.resid[i] * yr.resid[i]
            i += 1usize
        }
        // the null residuals: diff(y) with a leading zero, centred for the trend model
        var sn = 0.0f64
        var mean_null = 0.0f64
        if model == 1u8 {
            var t = 1usize
            while t < nobs {
                mean_null += y[t] - y[t - 1usize]
                t += 1usize
            }
            mean_null = mean_null / nf
        }
        sn = (mean_null) * (mean_null)
        var t = 1usize
        while t < nobs {
            let dv = y[t] - y[t - 1usize] - mean_null
            sn += dv * dv
            t += 1usize
        }
        var what_sq = 0.0f64
        if lm > 1usize {
            var best = 0usize
            var bv = 0.0f64
            var q = 2usize
            while q <= lm {
                let (o, np2, oe) = lag_reg(a, y, nobs, q - 1usize, true)
                if oe != ok { ret (out, oe) }
                let b = ols.bic(&o)
                if q == 2usize || b < bv {
                    bv = b
                    best = q
                }
                q += 1usize
            }
            let (o, np2, oe) = lag_reg(a, y, nobs, best - 1usize, true)
            if oe != ok { ret (out, oe) }
            var sumlc = 0.0f64
            var c = 2usize
            while c < np2 {
                sumlc += o.coef[c]
                c += 1usize
            }
            lm = best - 1usize
            what_sq = o.sigma2 / ((1.0f64 - sumlc) * (1.0f64 - sumlc))
        } else {
            let (o, np2, oe) = lag_reg(a, y, nobs, 0usize, true)
            if oe != ok { ret (out, oe) }
            lm = 0usize
            what_sq = o.sigma2
        }
        out.stat = (ssig - ahat * sn) / what_sq
        out.lag = lm
        // the table of the critical values, [4 sizes][3 levels][2 models], column-major as R fills it
        var tbl: [24]f64 = zero
        tbl[0usize] = 1.87f64
        tbl[1usize] = 1.95f64
        tbl[2usize] = 1.91f64
        tbl[3usize] = 1.99f64
        tbl[4usize] = 2.97f64
        tbl[5usize] = 3.11f64
        tbl[6usize] = 3.17f64
        tbl[7usize] = 3.26f64
        tbl[8usize] = 3.91f64
        tbl[9usize] = 4.17f64
        tbl[10usize] = 4.33f64
        tbl[11usize] = 4.48f64
        tbl[12usize] = 4.22f64
        tbl[13usize] = 4.26f64
        tbl[14usize] = 4.05f64
        tbl[15usize] = 3.96f64
        tbl[16usize] = 5.72f64
        tbl[17usize] = 5.64f64
        tbl[18usize] = 5.66f64
        tbl[19usize] = 5.62f64
        tbl[20usize] = 6.77f64
        tbl[21usize] = 6.79f64
        tbl[22usize] = 6.86f64
        tbl[23usize] = 6.89f64
        let off = 12usize * usize(model)
        out.cval1 = tbl[off + rowsel]
        out.cval5 = tbl[off + 4usize + rowsel]
        out.cval10 = tbl[off + 8usize + rowsel]
    } else {
        if model == 0u8 {
            out.cval1 = round2(0.0f64 - 2.5658f64 - 1.960f64 / nf - 10.04f64 / (nf * nf))
            out.cval5 = round2(0.0f64 - 1.9393f64 - 0.398f64 / nf)
            out.cval10 = round2(0.0f64 - 1.6156f64 - 0.181f64 / nf)
        } else {
            var tb: [12]f64 = zero
            tb[0usize] = 3.77f64
            tb[1usize] = 3.58f64
            tb[2usize] = 3.46f64
            tb[3usize] = 3.48f64
            tb[4usize] = 3.19f64
            tb[5usize] = 3.03f64
            tb[6usize] = 2.93f64
            tb[7usize] = 2.89f64
            tb[8usize] = 2.89f64
            tb[9usize] = 2.74f64
            tb[10usize] = 2.64f64
            tb[11usize] = 2.57f64
            out.cval1 = 0.0f64 - tb[rowsel]
            out.cval5 = 0.0f64 - tb[4usize + rowsel]
            out.cval10 = 0.0f64 - tb[8usize + rowsel]
        }
        // the regression without an intercept on the detrended series
        let (o, np2, oe) = lag_reg(a, yd, nobs, lm - 1usize, false)
        if oe != ok { ret (out, oe) }
        out.stat = o.tval[0usize]
        out.lag = lm - 1usize
    }
    ret (out, ok)
}

// R's round(x, 2)
fn round2(x: f64) -> f64 {
    let v = x * 100.0f64
    var r = math.floor[f64](v + 0.5f64)
    let d = v - math.floor[f64](v)
    if d == 0.5f64 {
        // half to even
        let fl = math.floor[f64](v)
        if fl - 2.0f64 * math.floor[f64](fl / 2.0f64) == 0.0f64 { r = fl } else { r = fl + 1.0f64 }
    }
    ret r / 100.0f64
}

type Za = struct { stat: f64, bpoint: usize, cval1: f64, cval5: f64, cval10: f64 }

// ur.za(y, model = intercept (0), trend (1) or both (2), lag)
fn ur_za(a: *mem.Arena, y: []const f64, model: u8, lag: usize) -> (Za, err) {
    var out: Za = zero
    let n = y.len
    // the rows with no NA: lag + 2 .. n (1-based)
    let first = lag + 1usize
    let rows = n - first
    var best = 0.0f64
    var bz = 0usize
    var z = 1usize
    while z <= n - 1usize {
        var np = 3usize + lag
        if model == 2u8 { np += 2usize } else { np += 1usize }
        let (d, de) = mem.alloc[f64](a, rows * np)
        let (yv, ye) = mem.alloc[f64](a, rows)
        if de != ok { ret (out, de) }
        if ye != ok { ret (out, ye) }
        var i = 0usize
        while i < rows {
            let t = first + i
            yv[i] = y[t]
            d[i] = 1.0f64
            d[rows + i] = y[t - 1usize]
            d[2usize * rows + i] = f64(t + 1usize)
            var q = 1usize
            while q <= lag {
                d[(2usize + q) * rows + i] = y[t - q] - y[t - q - 1usize]
                q += 1usize
            }
            let c0 = 3usize + lag
            // du: 0 for the first z observations (1-based), 1 after; dt: 0, then 1 .. n - z
            let pos = t + 1usize
            var du = 0.0f64
            var dt = 0.0f64
            if pos > z {
                du = 1.0f64
                dt = f64(pos - z)
            }
            if model == 0u8 { d[c0 * rows + i] = du }
            if model == 1u8 { d[c0 * rows + i] = dt }
            if model == 2u8 {
                d[c0 * rows + i] = du
                d[(c0 + 1usize) * rows + i] = dt
            }
            i += 1usize
        }
        let (o, oe) = ols.fit(a, d, rows, np, yv)
        if oe != ok { ret (out, oe) }
        let st = (o.coef[1usize] - 1.0f64) / o.se[1usize]
        if st == st && (bz == 0usize || st < best) {
            best = st
            bz = z
        }
        z += 1usize
    }
    out.stat = best
    out.bpoint = bz
    if model == 0u8 {
        out.cval1 = 0.0f64 - 5.34f64
        out.cval5 = 0.0f64 - 4.8f64
        out.cval10 = 0.0f64 - 4.58f64
    } else if model == 1u8 {
        out.cval1 = 0.0f64 - 4.93f64
        out.cval5 = 0.0f64 - 4.42f64
        out.cval10 = 0.0f64 - 4.11f64
    } else {
        out.cval1 = 0.0f64 - 5.57f64
        out.cval5 = 0.0f64 - 5.08f64
        out.cval10 = 0.0f64 - 4.82f64
    }
    ret (out, ok)
}
