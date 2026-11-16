// R TTR technical indicators on plain numeric vectors: SMA, EMA (with Wilder and ratio), WMA, DEMA,
// RSI, MACD, Bollinger bands, ROC (continuous and discrete), OBV, TR and ATR, as TTR 0.24 computes them.
// NA is NaN and leads the output as TTR pads it.
//
// Also ZLEMA, CCI, stochastics, ADX, SAR and quantmod Delt and periodReturn (on day numbers). Not here: the xts index
// handling and the other quantmod helpers.

use e.math
use e.time
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_na(x: f64) -> bool { ret x != x }

fn filled(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, n)
    if e != ok { ret (r, e) }
    var i = 0usize
    while i < n {
        r[i] = nan()
        i += 1usize
    }
    ret (r, ok)
}

// the first position that is not NA
fn first_valid(x: []const f64) -> usize {
    var i = 0usize
    while i < x.len && is_na(x[i]) { i += 1usize }
    ret i
}

// runMean: NA for the first n - 1 (and after leading NAs), the plain window mean elsewhere
fn sma(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, err) {
    let (r, e) = filled(a, x.len)
    if e != ok { ret (r, e) }
    let s = first_valid(x)
    var i = s + n - 1usize
    while i < x.len {
        var t = 0.0f64
        var k = i + 1usize - n
        while k <= i {
            t += x[k]
            k += 1usize
        }
        r[i] = t / f64(n)
        i += 1usize
    }
    ret (r, ok)
}

// EMA: the mean of the first n valid values seeds it, then x * ratio + previous * (1 - ratio)
fn ema(a: *mem.Arena, x: []const f64, n: usize, wilder: bool, ratio0: f64) -> ([]f64, err) {
    let (r, e) = filled(a, x.len)
    if e != ok { ret (r, e) }
    var ratio = ratio0
    if !(ratio0 > 0.0f64) {
        if wilder { ratio = 1.0f64 / f64(n) } else { ratio = 2.0f64 / (f64(n) + 1.0f64) }
    }
    let s = first_valid(x)
    let beg = s + n - 1usize
    if beg >= x.len { ret (r, ok) }
    var t = 0.0f64
    var k = s
    while k <= beg {
        t += x[k]
        k += 1usize
    }
    r[beg] = t / f64(n)
    var i = beg + 1usize
    while i < x.len {
        r[i] = x[i] * ratio + r[i - 1usize] * (1.0f64 - ratio)
        i += 1usize
    }
    ret (r, ok)
}

// WMA with the weights 1..n
fn wma(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, err) {
    let (r, e) = filled(a, x.len)
    if e != ok { ret (r, e) }
    let s = first_valid(x)
    var wsum = 0.0f64
    var j = 1usize
    while j <= n {
        wsum += f64(j)
        j += 1usize
    }
    var i = s + n - 1usize
    while i < x.len {
        var t = 0.0f64
        j = 0usize
        while j < n {
            t += x[i + 1usize - n + j] * f64(j + 1usize)
            j += 1usize
        }
        r[i] = t / wsum
        i += 1usize
    }
    ret (r, ok)
}

fn dema(a: *mem.Arena, x: []const f64, n: usize, v: f64, wilder: bool) -> ([]f64, err) {
    let (m1, e1) = ema(a, x, n, wilder, 0.0f64)
    if e1 != ok { ret (m1, e1) }
    let (d, e2) = ema(a, m1, n, wilder, 0.0f64)
    if e2 != ok { ret (d, e2) }
    let (r, e3) = filled(a, x.len)
    if e3 != ok { ret (r, e3) }
    var i = 0usize
    while i < x.len {
        r[i] = (1.0f64 + v) * m1[i] - d[i] * v
        i += 1usize
    }
    ret (r, ok)
}

// RSI with the Wilder EMA of the up and down moves
fn rsi(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, err) {
    let (up, e1) = filled(a, x.len)
    if e1 != ok { ret (up, e1) }
    let (dn, e2) = filled(a, x.len)
    if e2 != ok { ret (dn, e2) }
    var i = 1usize
    while i < x.len {
        let d = x[i] - x[i - 1usize]
        if is_na(d) {
            up[i] = nan()
            dn[i] = nan()
        } else if d < 0.0f64 {
            up[i] = 0.0f64
            dn[i] = 0.0f64 - d
        } else {
            up[i] = d
            dn[i] = 0.0f64
        }
        i += 1usize
    }
    let (mu, e3) = ema(a, up, n, true, 0.0f64)
    if e3 != ok { ret (mu, e3) }
    let (md, e4) = ema(a, dn, n, true, 0.0f64)
    if e4 != ok { ret (md, e4) }
    let (r, e5) = filled(a, x.len)
    if e5 != ok { ret (r, e5) }
    i = 0usize
    while i < x.len {
        r[i] = 100.0f64 * mu[i] / (mu[i] + md[i])
        i += 1usize
    }
    ret (r, ok)
}

// MACD (percent form): macd, then its signal EMA
fn macd(a: *mem.Arena, x: []const f64, nfast: usize, nslow: usize, nsig: usize, percent: bool, signal: bool) -> ([]f64, err) {
    let (f, e1) = ema(a, x, nfast, false, 0.0f64)
    if e1 != ok { ret (f, e1) }
    let (s, e2) = ema(a, x, nslow, false, 0.0f64)
    if e2 != ok { ret (s, e2) }
    let (m, e3) = filled(a, x.len)
    if e3 != ok { ret (m, e3) }
    var i = 0usize
    while i < x.len {
        if percent { m[i] = 100.0f64 * (f[i] / s[i] - 1.0f64) } else { m[i] = f[i] - s[i] }
        i += 1usize
    }
    if !signal { ret (m, ok) }
    let (sg, e4) = ema(a, m, nsig, false, 0.0f64)
    ret (sg, e4)
}

// Bollinger bands of a price series: part 0 dn, 1 mavg, 2 up, 3 pctB (population sd)
fn bbands(a: *mem.Arena, x: []const f64, n: usize, sdm: f64, part: u8) -> ([]f64, err) {
    let (mavg, e1) = sma(a, x, n)
    if e1 != ok { ret (mavg, e1) }
    let (r, e2) = filled(a, x.len)
    if e2 != ok { ret (r, e2) }
    var i = n - 1usize
    while i < x.len {
        var t = 0.0f64
        var k = i + 1usize - n
        while k <= i {
            t += (x[k] - mavg[i]) * (x[k] - mavg[i])
            k += 1usize
        }
        let sd = math.sqrt[f64](t / f64(n))
        let up = mavg[i] + sdm * sd
        let dn = mavg[i] - sdm * sd
        if part == 0u8 { r[i] = dn }
        if part == 1u8 { r[i] = mavg[i] }
        if part == 2u8 { r[i] = up }
        if part == 3u8 { r[i] = (x[i] - dn) / (up - dn) }
        i += 1usize
    }
    ret (r, ok)
}

// ROC over n periods: continuous (log difference) or discrete (ratio - 1)
fn roc(a: *mem.Arena, x: []const f64, n: usize, discrete: bool) -> ([]f64, err) {
    let (r, e) = filled(a, x.len)
    if e != ok { ret (r, e) }
    var i = n
    while i < x.len {
        if discrete { r[i] = x[i] / x[i - n] - 1.0f64 } else { r[i] = math.log[f64](x[i]) - math.log[f64](x[i - n]) }
        i += 1usize
    }
    ret (r, ok)
}

fn obv(a: *mem.Arena, price: []const f64, volume: []const f64) -> ([]f64, err) {
    let (r, e) = filled(a, price.len)
    if e != ok { ret (r, e) }
    var cum = volume[0usize]
    r[0usize] = cum
    var i = 1usize
    while i < price.len {
        let ch = math.log[f64](price[i]) - math.log[f64](price[i - 1usize])
        var v = 0.0f64 - volume[i]
        if ch > 0.0f64 { v = volume[i] }
        var ach = ch
        if ach < 0.0f64 { ach = 0.0f64 - ach }
        if ach < 1.4901161193847656e-8f64 { v = 0.0f64 }
        cum += v
        r[i] = cum
        i += 1usize
    }
    ret (r, ok)
}

// true range of high, low, close series
fn tr(a: *mem.Arena, high: []const f64, low: []const f64, close: []const f64) -> ([]f64, err) {
    let (r, e) = filled(a, high.len)
    if e != ok { ret (r, e) }
    var i = 1usize
    while i < high.len {
        var th = high[i]
        if close[i - 1usize] > th { th = close[i - 1usize] }
        var tl = low[i]
        if close[i - 1usize] < tl { tl = close[i - 1usize] }
        r[i] = th - tl
        i += 1usize
    }
    ret (r, ok)
}

fn atr(a: *mem.Arena, high: []const f64, low: []const f64, close: []const f64, n: usize) -> ([]f64, err) {
    let (t, e) = tr(a, high, low, close)
    if e != ok { ret (t, e) }
    let (r, e2) = ema(a, t, n, true, 0.0f64)
    ret (r, e2)
}

// ZLEMA(x, n): the SMA of the first n values seeds it, then ratio * (2 x[i] - x[i - lag]) + (1 - ratio) previous
// with ratio = 2 / (n + 1) and the fractional lag 1 / ratio taken between x[loc] and x[loc + 1]
fn zlema(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, err) {
    let (r, e) = filled(a, x.len)
    if e != ok { ret (r, e) }
    let first = first_valid(x)
    let ratio = 2.0f64 / (f64(n) + 1.0f64)
    var seed = 0.0f64
    var i = first
    while i < first + n {
        seed += x[i] / f64(n)
        i += 1usize
    }
    r[first + n - 1usize] = seed
    let lag = 1.0f64 / ratio
    let wt = lag - math.floor[f64](lag)
    let w1 = 1.0f64 - wt
    let r1 = 1.0f64 - ratio
    i = first + n
    while i < x.len {
        let loc = usize(f64(i) - lag)
        let value = 2.0f64 * x[i] - (w1 * x[loc] + wt * x[loc + 1usize])
        r[i] = ratio * value + r1 * r[i - 1usize]
        i += 1usize
    }
    ret (r, ok)
}

// CCI(HLC, n = 20, c = 0.015): (typical price - SMA) / (c * mean absolute deviation about the current SMA)
fn cci(a: *mem.Arena, high: []const f64, low: []const f64, close: []const f64, n: usize, c: f64) -> ([]f64, err) {
    let m = high.len
    let (tp, e1) = mem.alloc[f64](a, m)
    if e1 != ok { ret (tp, e1) }
    var i = 0usize
    while i < m {
        tp[i] = (high[i] + low[i] + close[i]) / 3.0f64
        i += 1usize
    }
    let (ma, e2) = sma(a, tp, n)
    if e2 != ok { ret (ma, e2) }
    let (r, e3) = filled(a, m)
    if e3 != ok { ret (r, e3) }
    i = n - 1usize
    while i < m {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += math.abs[f64](tp[i - j] - ma[i])
            j += 1usize
        }
        r[i] = (tp[i] - ma[i]) / (c * (s / f64(n)))
        i += 1usize
    }
    ret (r, ok)
}

// stoch(HLC, nFastK, nFastD, nSlowD, SMA, bounded = TRUE, smooth = 1): part 0 fastK, 1 fastD, 2 slowD
fn stoch(a: *mem.Arena, high: []const f64, low: []const f64, close: []const f64, nk: usize, nfd: usize, nsd: usize, part: u8) -> ([]f64, err) {
    let m = high.len
    let (k, e1) = filled(a, m)
    if e1 != ok { ret (k, e1) }
    var i = nk - 1usize
    while i < m {
        var hm = high[i]
        var lm = low[i]
        var j = 1usize
        while j < nk {
            if high[i - j] > hm { hm = high[i - j] }
            if low[i - j] < lm { lm = low[i - j] }
            j += 1usize
        }
        let num = close[i] - lm
        let den = hm - lm
        var v = num / den
        if !(v == v) || v > 1.7976931348623157e308f64 || v < 0.0f64 - 1.7976931348623157e308f64 { v = 0.5f64 }
        k[i] = v
        i += 1usize
    }
    if part == 0u8 { ret (k, ok) }
    let (d, e2) = sma(a, k, nfd)
    if e2 != ok { ret (d, e2) }
    if part == 1u8 { ret (d, ok) }
    let (sd, es) = sma(a, d, nsd)
    ret (sd, es)
}

// wilderSum(x, n) with leading NAs skipped as the C routine does
fn wilder_sum(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, err) {
    let m = x.len
    let (r, e) = filled(a, m)
    if e != ok { ret (r, e) }
    let first = first_valid(x)
    var sum = 0.0f64
    var i = first
    while i < first + n - 1usize {
        sum += x[i]
        i += 1usize
    }
    let beg = first + n - 1usize
    r[beg] = x[beg] + sum * f64(n - 1usize) / f64(n)
    i = beg + 1usize
    while i < m {
        r[i] = x[i] + r[i - 1usize] * f64(n - 1usize) / f64(n)
        i += 1usize
    }
    ret (r, ok)
}

// ADX(HLC, n = 14): part 0 DIp, 1 DIn, 2 DX, 3 ADX
fn adx(a: *mem.Arena, high: []const f64, low: []const f64, close: []const f64, n: usize, part: u8) -> ([]f64, err) {
    let m = high.len
    let (dmp, e1) = filled(a, m)
    let (dmn, e2) = filled(a, m)
    if e1 != ok || e2 != ok { ret (dmp, e1) }
    var i = 1usize
    while i < m {
        let dh = high[i] - high[i - 1usize]
        let dl = 0.0f64 - (low[i] - low[i - 1usize])
        var p = 0.0f64
        var q = 0.0f64
        if !(dh == dl || (dh < 0.0f64 && dl < 0.0f64)) {
            if dh > dl { p = dh } else if dh < dl { q = dl }
        }
        dmp[i] = p
        dmn[i] = q
        i += 1usize
    }
    let (trv, e3) = tr(a, high, low, close)
    if e3 != ok { ret (trv, e3) }
    let (trs, e4) = wilder_sum(a, trv, n)
    if e4 != ok { ret (trs, e4) }
    let (sp, e5) = wilder_sum(a, dmp, n)
    if e5 != ok { ret (sp, e5) }
    let (sn, e6) = wilder_sum(a, dmn, n)
    if e6 != ok { ret (sn, e6) }
    let (dip, e7) = filled(a, m)
    let (din, e8) = filled(a, m)
    let (dx, e9) = filled(a, m)
    if e7 != ok || e8 != ok || e9 != ok { ret (dip, e7) }
    i = 0usize
    while i < m {
        dip[i] = 100.0f64 * sp[i] / trs[i]
        din[i] = 100.0f64 * sn[i] / trs[i]
        dx[i] = 100.0f64 * (math.abs[f64](dip[i] - din[i]) / (dip[i] + din[i]))
        i += 1usize
    }
    if part == 0u8 { ret (dip, ok) }
    if part == 1u8 { ret (din, ok) }
    if part == 2u8 { ret (dx, ok) }
    let (av, ae) = ema(a, dx, n, true, 0.0f64)
    ret (av, ae)
}

// SAR(HL, accel = c(af0, afmax)): Wilder's parabolic stop and reverse; the initial gap is the sample sd of high - low
fn sar(a: *mem.Arena, hi: []const f64, lo: []const f64, af_start: f64, af_max: f64) -> ([]f64, err) {
    let n = hi.len
    let (r, e) = filled(a, n)
    if e != ok { ret (r, e) }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += hi[i] - lo[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (hi[i] - lo[i] - mean) * (hi[i] - lo[i] - mean)
        i += 1usize
    }
    let gap = math.sqrt[f64](ss / f64(n - 1usize))
    var sig0 = 1i64
    var xpt0 = hi[0usize]
    var af0 = af_start
    r[0usize] = lo[0usize] - gap
    i = 1usize
    while i < n {
        let sig1 = sig0
        let xpt1 = xpt0
        let af1 = af0
        let lmin = math.min[f64](lo[i - 1usize], lo[i])
        let lmax = math.max[f64](hi[i - 1usize], hi[i])
        if sig1 == 1i64 {
            if lo[i] > r[i - 1usize] { sig0 = 1i64 } else { sig0 = 0i64 - 1i64 }
            xpt0 = math.max[f64](lmax, xpt1)
        } else {
            if hi[i] < r[i - 1usize] { sig0 = 0i64 - 1i64 } else { sig0 = 1i64 }
            xpt0 = math.min[f64](lmin, xpt1)
        }
        if sig0 == sig1 {
            r[i] = r[i - 1usize] + (xpt1 - r[i - 1usize]) * af1
            if af1 == af_max { af0 = af_max } else { af0 = af_start + af1 }
            if sig0 == 1i64 {
                if !(xpt0 > xpt1) { af0 = af1 }
                r[i] = math.min[f64](r[i], lmin)
            } else {
                if !(xpt0 < xpt1) { af0 = af1 }
                r[i] = math.max[f64](r[i], lmax)
            }
        } else {
            af0 = af_start
            r[i] = xpt0
        }
        i += 1usize
    }
    ret (r, ok)
}

// Delt(x, k = lag, type): x[i] / x[i - k] - 1, or the log of the ratio
fn delt(a: *mem.Arena, x: []const f64, k: usize, log_type: bool) -> ([]f64, err) {
    let (r, e) = filled(a, x.len)
    if e != ok { ret (r, e) }
    var i = k
    while i < x.len {
        if log_type { r[i] = math.log[f64](x[i] / x[i - k]) } else { r[i] = x[i] / x[i - k] - 1.0f64 }
        i += 1usize
    }
    ret (r, ok)
}

// periodReturn(x, period, leading = TRUE) for a single price series on day numbers `days` (1970 epoch):
// period 0 monthly, 1 quarterly, 2 yearly; one return per period from the last price of each period, the first
// against the first price of the series; returns the number of periods
fn period_return(a: *mem.Arena, x: []const f64, days: []const f64, period: u8, log_type: bool, out: []f64) -> usize {
    let n = x.len
    var np = 0usize
    var prev_key = 0i64 - 1i64
    var last_close = 0.0f64
    var i = 0usize
    while i < n {
        let (y, m, _d) = time.civil_from_days(i64(days[i]))
        var key = y * 12i64 + (m - 1i64)
        if period == 1u8 { key = y * 4i64 + (m - 1i64) / 3i64 }
        if period == 2u8 { key = y }
        if key != prev_key && i > 0usize {
            out[np] = last_close
            np += 1usize
        }
        prev_key = key
        last_close = x[i]
        i += 1usize
    }
    out[np] = last_close
    np += 1usize
    // closes of the periods are in out; convert to returns in place
    var p = np
    while p > 1usize {
        p -= 1usize
        if log_type { out[p] = math.log[f64](out[p] / out[p - 1usize]) } else { out[p] = out[p] / out[p - 1usize] - 1.0f64 }
    }
    if log_type { out[0usize] = math.log[f64](out[0usize] / x[0usize]) } else { out[0usize] = out[0usize] / x[0usize] - 1.0f64 }
    ret np
}
