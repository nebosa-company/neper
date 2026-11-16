// R urca's Phillips-Perron (`ur.pp`), Elliott-Rothenberg-Stock (`ur.ers`, DF-GLS and P-test) and Zivot-Andrews (`ur.za`)
// unit-root tests: the statistic and the critical values of the package.
//
// Not here: ur.sp, ca.jo and ca.po.

use e.algo.stat.olsfit as ols
use e.math
use e.mem
use e.str

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

// a space separated list of numbers
fn numlist(a: *mem.Arena, text: str, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { ret (v, e) }
    var at = 0usize
    var start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 32u8 {
            if i > start && at < n {
                let (x, pe) = str.parse_f64(text[start..i])
                if pe != ok { ret (v, pe) }
                v[at] = x
                at += 1usize
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret (v, ok)
}

type Sp = struct { stat: f64, cval: f64 }

// ur.sp(y, type = tau (0) or rho (1), pol.deg 1 to 4, signif index 0 (1%), 1 (5%), 2 (10%))
fn ur_sp(a: *mem.Arena, y: []const f64, qtype: u8, deg: usize, sig_ix: usize) -> (Sp, err) {
    var out: Sp = zero
    let n = y.len
    let nf = f64(n)
    let lag = usize(math.floor[f64](12.0f64 * math.pow[f64](nf / 100.0f64, 0.25f64)))
    let m = n - 1usize
    let (sh, e1) = mem.alloc[f64](a, n)
    let (yd, ye) = mem.alloc[f64](a, m)
    if e1 != ok { ret (out, e1) }
    if ye != ok { ret (out, ye) }
    var i = 0usize
    while i < m {
        yd[i] = y[i + 1usize] - y[i]
        i += 1usize
    }
    var stat0 = 0.0f64
    if deg == 1usize {
        let yi = (y[n - 1usize] - y[0usize]) / (nf - 1.0f64)
        let phi = y[0usize] - yi
        i = 0usize
        while i < n {
            sh[i] = y[i] - phi - yi * f64(i + 1usize)
            i += 1usize
        }
        let (d, de) = mem.alloc[f64](a, m * 2usize)
        if de != ok { ret (out, de) }
        i = 0usize
        while i < m {
            d[i] = 1.0f64
            d[m + i] = sh[i]
            i += 1usize
        }
        let (o, oe) = ols.fit(a, d, m, 2usize, yd)
        if oe != ok { ret (out, oe) }
        if qtype == 1u8 { stat0 = nf * o.coef[1usize] } else { stat0 = o.tval[1usize] }
    } else {
        // the polynomial of degree deg - 1 in the trend for the differences
        let (d1, d1e) = mem.alloc[f64](a, m * deg)
        if d1e != ok { ret (out, d1e) }
        i = 0usize
        while i < m {
            d1[i] = 1.0f64
            var q = 1usize
            while q < deg {
                d1[q * m + i] = math.pow[f64](f64(i + 2usize), f64(q))
                q += 1usize
            }
            i += 1usize
        }
        let (o1, o1e) = ols.fit(a, d1, m, deg, yd)
        if o1e != ok { ret (out, o1e) }
        sh[0usize] = 0.0f64
        var cs = 0.0f64
        i = 0usize
        while i < m {
            cs += o1.resid[i]
            sh[i + 1usize] = cs
            i += 1usize
        }
        let (d2, d2e) = mem.alloc[f64](a, m * (deg + 1usize))
        if d2e != ok { ret (out, d2e) }
        i = 0usize
        while i < m {
            d2[i] = 1.0f64
            d2[m + i] = sh[i]
            var q = 1usize
            while q < deg {
                d2[(1usize + q) * m + i] = math.pow[f64](f64(i + 2usize), f64(q))
                q += 1usize
            }
            i += 1usize
        }
        let (o2, o2e) = ols.fit(a, d2, m, deg + 1usize, yd)
        if o2e != ok { ret (out, o2e) }
        if qtype == 1u8 { stat0 = nf * o2.coef[1usize] } else { stat0 = o2.tval[1usize] }
    }
    // the correction regression: y[2:n] ~ y[1:(n-1)] + trend .. trend^deg
    let (d3, d3e) = mem.alloc[f64](a, m * (deg + 2usize))
    let (y3, y3e) = mem.alloc[f64](a, m)
    if d3e != ok { ret (out, d3e) }
    if y3e != ok { ret (out, y3e) }
    i = 0usize
    while i < m {
        d3[i] = 1.0f64
        d3[m + i] = y[i]
        var q = 1usize
        while q <= deg {
            d3[(1usize + q) * m + i] = math.pow[f64](f64(i + 2usize), f64(q))
            q += 1usize
        }
        y3[i] = y[i + 1usize]
        i += 1usize
    }
    let (o3, o3e) = ols.fit(a, d3, m, deg + 2usize, y3)
    if o3e != ok { ret (out, o3e) }
    var sig_eps = 0.0f64
    i = 0usize
    while i < m {
        sig_eps += o3.resid[i] * o3.resid[i]
        i += 1usize
    }
    sig_eps = sig_eps / nf
    var acc = 0.0f64
    var l = 1usize
    while l <= lag {
        var cp = 0.0f64
        i = l
        while i < m {
            cp += o3.resid[i] * o3.resid[i - l]
            i += 1usize
        }
        let w = 2.0f64 * f64(lag - l) / f64(lag)
        acc += w * w * cp
        l += 1usize
    }
    let sg = sig_eps + (2.0f64 / nf) * acc
    let omega2 = sig_eps / sg
    if qtype == 1u8 { out.stat = stat0 / omega2 } else { out.stat = stat0 / math.sqrt[f64](omega2) }
    // the critical value table: 7 sample sizes by 3 levels by 4 degrees
    var rng = 6usize
    var bounds: [6]f64 = zero
    bounds[0usize] = 25.0f64
    bounds[1usize] = 50.0f64
    bounds[2usize] = 100.0f64
    bounds[3usize] = 200.0f64
    bounds[4usize] = 500.0f64
    bounds[5usize] = 1000.0f64
    var r = 0usize
    while r < 6usize {
        if bounds[r] >= nf {
            rng = r
            break
        }
        r += 1usize
    }
    var text = "3.9 3.73 3.63 3.61 3.59 3.58 3.56 3.18 3.11 3.06 3.04 3.04 3.02 3.02 2.85 2.8 2.77 2.76 2.76 2.75 2.75 4.52 4.28 4.16 4.12 4.08 4.06 4.06 3.78 3.77 3.65 3.6 3.55 3.55 3.53 3.52 3.41 3.34 3.31 3.28 3.26 3.26 3.26 5.07 4.73 4.59 4.53 4.5 4.49 4.44 4.26 4.08 4.03 3.99 3.96 3.95 3.93 3.89 3.77 3.72 3.69 3.68 3.68 3.67 5.57 5.13 4.99 4.9 4.85 4.83 4.81 4.7 4.47 4.39 4.33 4.31 4.31 4.29 4.3 4.15 4.1 4.06 4.03 4.03 4.01"
    if qtype == 1u8 { text = "20.4 22.8 23.8 24.8 25.3 25.3 25.2 15.7 17.0 17.5 17.9 18.1 18.1 18.1 13.4 14.3 14.6 14.9 15.0 15.0 15.0 24.6 28.4 30.4 31.8 32.4 32.5 32.6 20.1 22.4 23.7 24.2 24.8 24.6 24.7 17.8 19.5 20.4 20.7 21.0 21.1 21.1 28.1 33.1 36.3 38.0 39.1 39.5 39.7 23.8 27.0 29.1 30.1 30.6 30.8 30.6 21.5 24.0 25.4 26.1 26.6 26.7 26.7 31.0 37.4 41.8 44.0 45.3 45.7 45.8 26.9 31.2 34.0 35.2 36.2 36.6 36.4 24.7 28.1 30.2 31.2 31.8 32.0 31.9" }
    let (tb, te) = numlist(a, text, 84usize)
    if te != ok { ret (out, te) }
    out.cval = 0.0f64 - tb[rng + 7usize * sig_ix + 21usize * (deg - 1usize)]
    ret (out, ok)
}

// the inverse of a k x k row-major matrix by Gauss-Jordan with partial pivoting; false when singular
fn inv_small(a: *mem.Arena, x: []const f64, k: usize, out: []f64) -> bool {
    let (w, e) = mem.alloc[f64](a, k * k)
    if e != ok { ret false }
    var i = 0usize
    while i < k * k {
        w[i] = x[i]
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        out[i * k + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < k {
        var pv = c
        var best = math.abs[f64](w[c * k + c])
        var r = c + 1usize
        while r < k {
            if math.abs[f64](w[r * k + c]) > best {
                best = math.abs[f64](w[r * k + c])
                pv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret false }
        if pv != c {
            var j = 0usize
            while j < k {
                let t = w[c * k + j]
                w[c * k + j] = w[pv * k + j]
                w[pv * k + j] = t
                let t2 = out[c * k + j]
                out[c * k + j] = out[pv * k + j]
                out[pv * k + j] = t2
                j += 1usize
            }
        }
        let d = w[c * k + c]
        var j = 0usize
        while j < k {
            w[c * k + j] = w[c * k + j] / d
            out[c * k + j] = out[c * k + j] / d
            j += 1usize
        }
        r = 0usize
        while r < k {
            if r != c {
                let f = w[r * k + c]
                j = 0usize
                while j < k {
                    w[r * k + j] -= f * w[c * k + j]
                    out[r * k + j] -= f * out[c * k + j]
                    j += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    ret true
}

type Po = struct { stat: f64, cval10: f64, cval5: f64, cval1: f64, lag: usize }

// ca.po(z, demean = none (0), constant (1), trend (2), lag = short (0) or long (1), type = Pu (0) or Pz (1)); z is n by m column-major
fn ca_po(a: *mem.Arena, z: []const f64, n0: usize, m: usize, demean: u8, lagsel: u8, qtype: u8) -> (Po, err) {
    var out: Po = zero
    let nobs = n0 - 1usize
    let nf = f64(nobs)
    var lmax = usize(math.floor[f64](4.0f64 * math.pow[f64](nf / 100.0f64, 0.25f64)))
    if lagsel == 1u8 { lmax = usize(math.floor[f64](12.0f64 * math.pow[f64](nf / 100.0f64, 0.25f64))) }
    var nreg = m
    if demean >= 1u8 { nreg += 1usize }
    if demean == 2u8 { nreg += 1usize }
    let (d, de) = mem.alloc[f64](a, nobs * nreg)
    let (res, re) = mem.alloc[f64](a, nobs * m)
    let (yv, ye) = mem.alloc[f64](a, nobs)
    if de != ok { ret (out, de) }
    if re != ok { ret (out, re) }
    if ye != ok { ret (out, ye) }
    var i = 0usize
    while i < nobs {
        var c = 0usize
        if demean >= 1u8 {
            d[i] = 1.0f64
            c = 1usize
        }
        var j = 0usize
        while j < m {
            d[(c + j) * nobs + i] = z[j * n0 + i]
            j += 1usize
        }
        if demean == 2u8 { d[(c + m) * nobs + i] = f64(i + 1usize) }
        i += 1usize
    }
    var j = 0usize
    while j < m {
        i = 0usize
        while i < nobs {
            yv[i] = z[j * n0 + i + 1usize]
            i += 1usize
        }
        let (o, oe) = ols.fit(a, d, nobs, nreg, yv)
        if oe != ok { ret (out, oe) }
        i = 0usize
        while i < nobs {
            res[j * nobs + i] = o.resid[i]
            i += 1usize
        }
        j += 1usize
    }
    let (om, ome) = mem.alloc[f64](a, m * m)
    if ome != ok { ret (out, ome) }
    var p = 0usize
    while p < m {
        var q = 0usize
        while q < m {
            var s0 = 0.0f64
            i = 0usize
            while i < nobs {
                s0 += res[p * nobs + i] * res[q * nobs + i]
                i += 1usize
            }
            var sm = 0.0f64
            var l = 1usize
            while l <= lmax {
                var t1 = 0.0f64
                var t2 = 0.0f64
                i = l
                while i < nobs {
                    t1 += res[p * nobs + i] * res[q * nobs + i - l]
                    t2 += res[p * nobs + i - l] * res[q * nobs + i]
                    i += 1usize
                }
                sm += (1.0f64 - f64(l) / f64(lmax + 1usize)) * (t1 + t2)
                l += 1usize
            }
            om[p * m + q] = s0 / nf + sm / nf
            q += 1usize
        }
        p += 1usize
    }
    let off = m - 2usize
    var cp: []f64 = zero
    if qtype == 1u8 {
        let (mz, mze) = mem.alloc[f64](a, m * m)
        let (mzi, mzie) = mem.alloc[f64](a, m * m)
        if mze != ok { ret (out, mze) }
        if mzie != ok { ret (out, mzie) }
        p = 0usize
        while p < m {
            var q = 0usize
            while q < m {
                var s0 = 0.0f64
                i = 0usize
                while i < nobs {
                    s0 += z[p * n0 + i + 1usize] * z[q * n0 + i + 1usize]
                    i += 1usize
                }
                mz[p * m + q] = s0 / nf
                q += 1usize
            }
            p += 1usize
        }
        if !inv_small(a, mz, m, mzi) { ret (out, Singular) }
        var tr = 0.0f64
        p = 0usize
        while p < m {
            var q = 0usize
            while q < m {
                tr += om[p * m + q] * mzi[q * m + p]
                q += 1usize
            }
            p += 1usize
        }
        out.stat = nf * tr
        let (tb, te) = numlist(a, "33.9267 62.1436 99.2664 143.0775 195.6202 40.8217 71.2751 109.7426 155.8019 210.2910 55.1911 89.6679 131.5716 180.4845 237.7723 47.5877 80.2034 120.3035 168.8572 225.2303 55.2202 89.7619 132.2207 182.0749 241.3316 71.9273 109.4525 153.4504 209.8054 270.5018 71.9586 113.4929 163.1050 219.5098 284.0100 81.3812 124.3933 175.9902 234.2865 301.0949 102.0167 145.8644 201.0905 264.4988 335.9054", 45usize)
        if te != ok { ret (out, te) }
        cp = tb
    } else {
        var nr = m - 1usize
        if demean >= 1u8 { nr += 1usize }
        if demean == 2u8 { nr += 1usize }
        let (d2, d2e) = mem.alloc[f64](a, n0 * nr)
        let (y2, y2e) = mem.alloc[f64](a, n0)
        if d2e != ok { ret (out, d2e) }
        if y2e != ok { ret (out, y2e) }
        i = 0usize
        while i < n0 {
            var c = 0usize
            if demean >= 1u8 {
                d2[i] = 1.0f64
                c = 1usize
            }
            var jj = 1usize
            while jj < m {
                d2[(c + jj - 1usize) * n0 + i] = z[jj * n0 + i]
                jj += 1usize
            }
            if demean == 2u8 { d2[(c + m - 1usize) * n0 + i] = f64(i + 1usize) }
            y2[i] = z[i]
            i += 1usize
        }
        let (o2, o2e) = ols.fit(a, d2, n0, nr, y2)
        if o2e != ok { ret (out, o2e) }
        var ssq = 0.0f64
        i = 0usize
        while i < n0 {
            ssq += o2.resid[i] * o2.resid[i]
            i += 1usize
        }
        let ssqr = ssq / nf
        let k = m - 1usize
        let (o22, o22e) = mem.alloc[f64](a, k * k)
        let (o22i, o22ie) = mem.alloc[f64](a, k * k)
        if o22e != ok { ret (out, o22e) }
        if o22ie != ok { ret (out, o22ie) }
        p = 0usize
        while p < k {
            var q = 0usize
            while q < k {
                o22[p * k + q] = om[(p + 1usize) * m + q + 1usize]
                q += 1usize
            }
            p += 1usize
        }
        if !inv_small(a, o22, k, o22i) { ret (out, Singular) }
        var quad = 0.0f64
        p = 0usize
        while p < k {
            var q = 0usize
            while q < k {
                quad += om[(p + 1usize) * m] * o22i[p * k + q] * om[(q + 1usize) * m]
                q += 1usize
            }
            p += 1usize
        }
        let w112 = om[0usize] - quad
        out.stat = nf * w112 / ssqr
        let (tb, te) = numlist(a, "20.3933 26.7022 33.5359 39.2826 44.3725 25.9711 32.9392 40.1220 46.2691 51.8614 38.3413 46.4097 55.7341 63.2149 69.4939 27.8536 33.6955 39.6949 45.3308 50.3537 33.713 40.5252 46.7281 53.2502 57.7855 48.0021 53.8731 63.4128 71.5214 76.7705 41.2488 46.1061 52.0015 57.3667 61.6155 48.8439 53.8300 60.2384 65.8706 70.7416 65.1714 69.2629 78.3470 84.5480 91.0392", 45usize)
        if te != ok { ret (out, te) }
        cp = tb
    }
    let base = off + 15usize * usize(demean)
    out.cval10 = cp[base]
    out.cval5 = cp[base + 5usize]
    out.cval1 = cp[base + 10usize]
    out.lag = lmax
    ret (out, ok)
}

error Singular
