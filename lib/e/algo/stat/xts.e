// The period algorithms of R's xts for a series indexed by UTC seconds: `endpoints` (years, quarters,
// months, weeks, days, hours, minutes, seconds, with k), the open, high, low, close and a reducer
// (sum, mean, max, min) over those endpoints (to.period and period.apply), `align_time`,
// `periodicity` and `lag` and `diff`. NA is NaN. A series is an ascending index of seconds and its values.
// Also first and last with period strings, merge by index and the to.period index labels. Not here: time zones other
// than UTC, sub-second units, and indexAt = "firstof" (R builds it in the host local zone).

// merge and join of two series (e.algo.stat.zoo merges by index).

use e.math
use e.mem

error Unsupported

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn floor_div(a: i64, b: i64) -> i64 {
    var q = a / b
    if (a % b != 0i64) && ((a < 0i64) != (b < 0i64)) { q -= 1i64 }
    ret q
}

fn floor_mod(a: i64, b: i64) -> i64 { ret a - floor_div(a, b) * b }

// days since 1970-01-01 to (year, month 0-11, day of year 0-365)
fn civil(days: i64) -> (i64, i64, i64) {
    let z = days + 719468i64
    let era = floor_div(z, 146097i64)
    let doe = z - era * 146097i64
    let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
    var y = yoe + era * 400i64
    let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
    let mp = (5i64 * doy + 2i64) / 153i64
    var m = mp + 3i64
    if mp >= 10i64 { m = mp - 9i64 }
    if m <= 2i64 { y += 1i64 }
    // day of year
    var leap = false
    if (y % 4i64 == 0i64 && y % 100i64 != 0i64) || y % 400i64 == 0i64 { leap = true }
    var cum: [12]i64 = zero
    cum[0usize] = 0i64
    cum[1usize] = 31i64
    cum[2usize] = 59i64
    cum[3usize] = 90i64
    cum[4usize] = 120i64
    cum[5usize] = 151i64
    cum[6usize] = 181i64
    cum[7usize] = 212i64
    cum[8usize] = 243i64
    cum[9usize] = 273i64
    cum[10usize] = 304i64
    cum[11usize] = 334i64
    let d = doy - (153i64 * mp + 2i64) / 5i64 + 1i64
    var yd = cum[usize(m - 1i64)] + d - 1i64
    if leap && m > 2i64 { yd += 1i64 }
    ret (y, m - 1i64, yd)
}

// xts C endpoints: a break after element i where floor(x / by) / k changes
fn c_endpoints(a: *mem.Arena, key: []const i64, by: i64, k: i64) -> ([]usize, err) {
    let n = key.len
    let (ep, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { ret (ep, e) }
    var cnt = 0usize
    ep[cnt] = 0usize
    cnt += 1usize
    var i = 0usize
    while i + 1usize < n {
        let g0 = floor_div(floor_div(key[i], by), k)
        let g1 = floor_div(floor_div(key[i + 1usize], by), k)
        if g0 != g1 {
            ep[cnt] = i + 1usize
            cnt += 1usize
        }
        i += 1usize
    }
    if ep[cnt - 1usize] != n {
        ep[cnt] = n
        cnt += 1usize
    }
    ret (ep[0usize..cnt], ok)
}

fn include_last(a: *mem.Arena, ep: []const usize, k: usize) -> ([]usize, err) {
    let len = ep.len
    let (out, e) = mem.alloc[usize](a, len + 1usize)
    if e != ok { ret (out, e) }
    var cnt = 0usize
    var i = 0usize
    var last = 0usize
    while i < len {
        out[cnt] = ep[i]
        cnt += 1usize
        last = i
        i += k
    }
    if last != len - 1usize {
        out[cnt] = ep[len - 1usize]
        cnt += 1usize
    }
    ret (out[0usize..cnt], ok)
}

// on: 0 years, 1 quarters, 2 months, 3 weeks, 4 days, 5 hours, 6 minutes, 7 seconds. Answers the
// endpoints: 0, then the 1-based position of the last element of each period.
fn endpoints(a: *mem.Arena, idx: []const f64, on: u8, k: i64) -> ([]usize, err) {
    let n = idx.len
    let (key, ke) = mem.alloc[i64](a, n)
    if ke != ok {
        var none: []usize = zero
        ret (none, ke)
    }
    var i = 0usize
    while i < n {
        let t = i64(math.floor[f64](idx[i]))
        let days = floor_div(t, 86400i64)
        let (y, mon, yd) = civil(days)
        if on == 0u8 { key[i] = floor_div(y - 1900i64, k) + 1i64 } else if on == 1u8 { key[i] = (y - 1900i64) * 100i64 + 190000i64 + mon / 3i64 + 1i64 } else if on == 2u8 { key[i] = (y - 1900i64) * 100i64 + 190000i64 + mon } else if on == 4u8 { key[i] = (y - 1900i64) * 1000i64 + 1900000i64 + yd } else { key[i] = t }
        i += 1usize
    }
    if on == 0u8 {
        // diff of year %/% k + 1 changes: group by the key itself
        let (ep, e) = c_endpoints(a, key, 1i64, 1i64)
        ret (ep, e)
    }
    if on == 1u8 || on == 2u8 {
        let (ep, e) = c_endpoints(a, key, 1i64, 1i64)
        if e != ok { ret (ep, e) }
        if k > 1i64 {
            let (ep2, e2) = include_last(a, ep, usize(k))
            ret (ep2, e2)
        }
        ret (ep, e)
    }
    if on == 3u8 {
        i = 0usize
        while i < n {
            key[i] += 3i64 * 86400i64
            i += 1usize
        }
        let (ep, e) = c_endpoints(a, key, 604800i64, k)
        ret (ep, e)
    }
    if on == 4u8 {
        let (ep, e) = c_endpoints(a, key, 1i64, k)
        ret (ep, e)
    }
    var by = 1i64
    if on == 5u8 { by = 3600i64 }
    if on == 6u8 { by = 60i64 }
    let (ep, e) = c_endpoints(a, key, by, k)
    ret (ep, e)
}

// ohlc: part 0 open, 1 high, 2 low, 3 close of each period of `ep`
fn ohlc(a: *mem.Arena, x: []const f64, ep: []const usize, part: u8) -> ([]f64, err) {
    let np = ep.len - 1usize
    let (out, e) = mem.alloc[f64](a, np)
    if e != ok { ret (out, e) }
    var p = 0usize
    while p < np {
        let lo = ep[p]
        let hi = ep[p + 1usize]
        var v = x[lo]
        if part == 3u8 { v = x[hi - 1usize] }
        if part == 1u8 || part == 2u8 {
            var i = lo
            while i < hi {
                if part == 1u8 && x[i] > v { v = x[i] }
                if part == 2u8 && x[i] < v { v = x[i] }
                i += 1usize
            }
        }
        out[p] = v
        p += 1usize
    }
    ret (out, ok)
}

// period.apply with a reducer: 0 sum, 1 mean, 2 max, 3 min
fn period_apply(a: *mem.Arena, x: []const f64, ep: []const usize, kind: u8) -> ([]f64, err) {
    let np = ep.len - 1usize
    let (out, e) = mem.alloc[f64](a, np)
    if e != ok { ret (out, e) }
    var p = 0usize
    while p < np {
        var s = 0.0f64
        var v = x[ep[p]]
        var i = ep[p]
        while i < ep[p + 1usize] {
            s += x[i]
            if kind == 2u8 && x[i] > v { v = x[i] }
            if kind == 3u8 && x[i] < v { v = x[i] }
            i += 1usize
        }
        if kind == 0u8 { v = s }
        if kind == 1u8 { v = s / f64(ep[p + 1usize] - ep[p]) }
        out[p] = v
        p += 1usize
    }
    ret (out, ok)
}

// align.time: the next multiple of n seconds, strictly above the time
fn align_time(t: f64, n: f64) -> f64 {
    let r = t - n * math.floor[f64](t / n)
    ret t + (n - r)
}

fn median_diff(idx: []const f64) -> f64 {
    let n = idx.len - 1usize
    var d: []f64 = zero
    var buf: [4096]f64 = zero
    var m = n
    if m > 4096usize { m = 4096usize }
    var i = 0usize
    while i < m {
        buf[i] = idx[i + 1usize] - idx[i]
        i += 1usize
    }
    // insertion sort
    i = 1usize
    while i < m {
        var j = i
        while j > 0usize && buf[j - 1usize] > buf[j] {
            let t = buf[j]
            buf[j] = buf[j - 1usize]
            buf[j - 1usize] = t
            j -= 1usize
        }
        i += 1usize
    }
    if m % 2usize == 1usize { ret buf[m / 2usize] }
    ret (buf[m / 2usize - 1usize] + buf[m / 2usize]) / 2.0f64
}

// periodicity: (frequency, scale) with scale 0 seconds, 1 minute, 2 hourly, 3 daily, 4 weekly,
// 5 monthly, 6 quarterly, 7 yearly; the frequency is the median step in the unit of its scale.
fn periodicity(idx: []const f64) -> (f64, u8) {
    if idx.len < 2usize { ret (0.0f64, 0u8) }
    let p = median_diff(idx)
    if p < 60.0f64 { ret (p, 0u8) }
    if p < 3600.0f64 { ret (p / 60.0f64, 1u8) }
    if p < 86400.0f64 { ret (p, 2u8) }
    if p == 86400.0f64 { ret (p, 3u8) }
    if p <= 604800.0f64 { ret (p, 4u8) }
    if p <= 2678400.0f64 { ret (p, 5u8) }
    if p <= 7948800.0f64 { ret (p, 6u8) }
    ret (p, 7u8)
}

// lag (kind 0: x shifted by k, NA first) and diff (kind 1: x - lag, NA first)
fn lag_diff(a: *mem.Arena, x: []const f64, kind: u8, k: usize) -> ([]f64, err) {
    let n = x.len
    let (out, e) = mem.alloc[f64](a, n)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < n {
        if i < k {
            out[i] = nan()
        } else if kind == 0u8 {
            out[i] = x[i - k]
        } else {
            out[i] = x[i] - x[i - k]
        }
        i += 1usize
    }
    ret (out, ok)
}

// first(x, "k <unit>") and last(x, "k <unit>") on a daily or coarser series: the 1-based inclusive row range
// (start, end) of the rows kept; unit 3 weeks .. 0 years use endpoints as xts does, unit 4 days is a plain row
// count (the series units are days already); a negative k drops from the front (first) or back (last)
fn first_last(a: *mem.Arena, idx: []const f64, on: u8, k: i64, is_last: bool) -> (usize, usize, err) {
    let n = idx.len
    if on == 4u8 {
        var kk = k
        if kk > i64(n) { kk = i64(n) }
        if kk >= 0i64 {
            if is_last { ret (n - usize(kk) + 1usize, n, ok) }
            ret (1usize, usize(kk), ok)
        }
        let drop = usize(0i64 - kk)
        if drop >= n { ret (1usize, 0usize, ok) }
        if is_last { ret (1usize, n - drop, ok) }
        ret (drop + 1usize, n, ok)
    }
    let (ep, e) = endpoints(a, idx, on, 1i64)
    if e != ok { ret (0usize, 0usize, e) }
    let np = ep.len - 1usize
    var rpf = k
    if rpf > i64(np) { rpf = i64(np) }
    if rpf > 0i64 {
        if is_last { ret (ep[ep.len - 1usize - usize(rpf)] + 1usize, n, ok) }
        ret (1usize, ep[usize(rpf)], ok)
    }
    if rpf < 0i64 {
        let m = usize(0i64 - rpf)
        if is_last {
            // x[1:0] is c(1, 0) in R: a zero endpoint keeps the first row
            let stop = ep[ep.len - 1usize - m]
            if stop == 0usize { ret (1usize, 1usize, ok) }
            ret (1usize, stop, ok)
        }
        ret (ep[m] + 1usize, n, ok)
    }
    ret (1usize, 0usize, ok)
}

// merge(x, y, join): both indices ascending and unique; out receives the merged index, xo and yo the columns (NaN where
// absent); join 0 outer, 1 inner, 2 left, 3 right; answers the number of rows
fn merge2(idx_x: []const f64, x: []const f64, idx_y: []const f64, y: []const f64, join: u8, out: []f64, xo: []f64, yo: []f64) -> usize {
    var i = 0usize
    var j = 0usize
    var r = 0usize
    while i < idx_x.len || j < idx_y.len {
        var take_x = false
        var take_y = false
        if i < idx_x.len && j < idx_y.len {
            if idx_x[i] == idx_y[j] {
                take_x = true
                take_y = true
            } else if idx_x[i] < idx_y[j] {
                take_x = true
            } else {
                take_y = true
            }
        } else if i < idx_x.len {
            take_x = true
        } else {
            take_y = true
        }
        var keep = true
        if join == 1u8 { keep = take_x && take_y }
        if join == 2u8 { keep = take_x }
        if join == 3u8 { keep = take_y }
        if keep {
            if take_x { out[r] = idx_x[i] } else { out[r] = idx_y[j] }
            if take_x { xo[r] = x[i] } else { xo[r] = nan() }
            if take_y { yo[r] = y[j] } else { yo[r] = nan() }
            r += 1usize
        }
        if take_x { i += 1usize }
        if take_y { j += 1usize }
    }
    ret r
}

fn days_from_ymd(y0: i64, m: i64, d: i64) -> i64 {
    var y = y0
    if m <= 2i64 { y -= 1i64 }
    let era = floor_div(y, 400i64)
    let yoe = y - era * 400i64
    var mp = m - 3i64
    if m <= 2i64 { mp = m + 9i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + d - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

// the index of to.period(x, period, indexAt = ...) given the series index (UTC seconds) and the endpoints `ep`:
// mode 0 endof (the last observation of each period), 1 startof (the first), 2 firstof (the first of the month of the
// end index at 00:00 when `period_on` is years, quarters, months or days, else the end index), 3 lastof (the last day of
// that month), 4 yearmon and 5 yearqtr (the zoo values year + (month - 1) / 12 and year + (quarter - 1) / 4 of the end index)
fn period_index(idx: []const f64, ep: []const usize, mode: u8, period_on: u8, out: []f64) -> usize {
    var r = 0usize
    while r + 1usize < ep.len {
        let last = idx[ep[r + 1usize] - 1usize]
        let first = idx[ep[r] + 0usize]
        let secs = i64(math.floor[f64](last))
        let days = floor_div(secs, 86400i64)
        let (y0, mon0, _yd) = civil(days)
        // civil returns the year of the shifted calendar; recover the calendar year and month
        let y = y0
        let m = mon0
        var v = last
        if mode == 1u8 { v = first }
        let coarse = period_on <= 2u8 || period_on == 4u8
        if mode == 2u8 && coarse { v = f64(days_from_ymd(y, m + 1i64, 1i64)) * 86400.0f64 }
        if mode == 3u8 && coarse {
            var ny = y
            var nm = m + 2i64
            if nm > 12i64 {
                nm = 1i64
                ny += 1i64
            }
            v = f64(days_from_ymd(ny, nm, 1i64) - 1i64) * 86400.0f64
        }
        if mode == 4u8 { v = f64(y) + f64(m) / 12.0f64 }
        if mode == 5u8 { v = f64(y) + f64(m / 3i64) / 4.0f64 }
        out[r] = v
        r += 1usize
    }
    ret r
}
