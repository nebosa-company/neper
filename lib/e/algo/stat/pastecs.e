// R pastecs, the closed-form part: `turnpoints` (peaks and pits of a series with runs of equal values collapsed,
// with the probability and information of each turning point under the null of a random series) and `stat_desc`
// (the basic, descriptive and normality-moment statistics of a sample without missing values).
//
// Not here: regul, the turnogram and the other estimators.

use e.algo.sort
use e.algo.stat.ica as ica
use e.algo.stat.test as tst
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem

type Turn = struct { nturns: usize, firstispeak: bool, npeaks: usize, npits: usize, tppos_sum: f64, tppos_w: f64, proba_sum: f64, proba_w: f64, info_sum: f64, info_w: f64 }

fn factorial_gamma(k: f64) -> f64 {
    // gamma(k) for a positive integer k: (k - 1)!
    var v = 1.0f64
    var i = 2.0f64
    while i < k {
        v *= i
        i += 1.0f64
    }
    ret v
}

// turnpoints(x): the series must have at least three distinct consecutive runs, otherwise nturns is 0 and the rest zero
fn turnpoints(a: *mem.Arena, x: []const f64) -> (Turn, err) {
    var res: Turn = zero
    let n = x.len
    let (u, e1) = mem.alloc[f64](a, n)
    let (pos, e2) = mem.alloc[usize](a, n)
    let (peak, e3) = mem.alloc[bool](a, n)
    let (pit, e4) = mem.alloc[bool](a, n)
    let (tp, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (res, e1) }
    var n2 = 0usize
    var i = 0usize
    while i < n {
        if i == 0usize || x[i - 1usize] != x[i] {
            u[n2] = x[i]
            pos[n2] = i + 1usize
            n2 += 1usize
        }
        i += 1usize
    }
    if n2 < 3usize { ret (res, ok) }
    i = 0usize
    while i < n2 {
        peak[i] = false
        pit[i] = false
        i += 1usize
    }
    var j = 1usize
    while j + 1usize < n2 {
        let l = u[j - 1usize]
        let m = u[j]
        let r = u[j + 1usize]
        if m >= l && m >= r { peak[j] = true }
        if m <= l && m <= r { pit[j] = true }
        j += 1usize
    }
    var nt = 0usize
    var first_peak = n2
    i = 0usize
    while i < n2 {
        if peak[i] && first_peak == n2 { first_peak = i }
        if peak[i] || pit[i] {
            tp[nt] = i + 1usize
            nt += 1usize
        }
        i += 1usize
    }
    if nt == 0usize { ret (res, ok) }
    res.nturns = nt
    res.firstispeak = tp[0usize] == first_peak + 1usize
    var k = 0usize
    while k < nt {
        let idx = tp[k] - 1usize
        if peak[idx] { res.npeaks += 1usize }
        if pit[idx] { res.npits += 1usize }
        // pos + exaequos is the position of the last element of the run: the next run's start minus one
        var last = n
        if idx + 1usize < n2 { last = pos[idx + 1usize] - 1usize }
        res.tppos_sum += f64(last)
        res.tppos_w += f64(k + 1usize) * f64(last)
        var inter = 0.0f64
        var p1 = 0.0f64
        if nt < 2usize {
            inter = f64(n2 + 1usize)
            p1 = f64(tp[0usize])
        } else {
            var nextp = n2
            if k + 1usize < nt { nextp = tp[k + 1usize] }
            var prevp = 1usize
            if k > 0usize { prevp = tp[k - 1usize] }
            inter = f64(nextp) - f64(prevp) + 1.0f64
            p1 = f64(tp[k]) - f64(prevp)
        }
        let p2 = inter - p1
        var pm = p1
        if p2 > pm { pm = p2 }
        let proba = 2.0f64 / (inter * factorial_gamma(pm) * factorial_gamma(inter - pm + 1.0f64))
        let info = 0.0f64 - math.log[f64](proba) / math.log[f64](2.0f64)
        res.proba_sum += proba
        res.proba_w += f64(k + 1usize) * proba
        res.info_sum += info
        res.info_w += f64(k + 1usize) * info
        k += 1usize
    }
    ret (res, ok)
}

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

type Desc = struct { nbr_null: f64, min: f64, max: f64, range: f64, sum: f64, median: f64, mean: f64, se_mean: f64, ci_mean: f64, variance: f64, std_dev: f64, coef_var: f64, skewness: f64, skew_2se: f64, kurtosis: f64, kurt_2se: f64, normtest_w: f64, normtest_p: f64 }

// stat.desc(x, norm = TRUE, p), with the Shapiro-Wilk entries (NaN outside 3 to 5000 values)
fn stat_desc(a: *mem.Arena, x: []const f64, p: f64) -> (Desc, err) {
    var d: Desc = zero
    let n = x.len
    let nf = f64(n)
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret (d, e) }
    var i = 0usize
    var sum = 0.0f64
    while i < n {
        s[i] = x[i]
        sum += x[i]
        if x[i] == 0.0f64 { d.nbr_null += 1.0f64 }
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    d.min = s[0usize]
    d.max = s[n - 1usize]
    d.range = d.max - d.min
    d.sum = sum
    if n % 2usize == 1usize { d.median = s[n / 2usize] } else { d.median = (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64 }
    let mean = sum / nf
    d.mean = mean
    var m2 = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    i = 0usize
    while i < n {
        let dv = x[i] - mean
        m2 += dv * dv
        m3 += dv * dv * dv
        m4 += dv * dv * dv * dv
        i += 1usize
    }
    let v = m2 / (nf - 1.0f64)
    d.variance = v
    d.std_dev = math.sqrt[f64](v)
    d.se_mean = d.std_dev / math.sqrt[f64](nf)
    d.ci_mean = nb.qt(0.5f64 + p / 2.0f64, nf - 1.0f64, true, false) * d.se_mean
    d.coef_var = d.std_dev / mean
    let sd3 = d.std_dev * d.std_dev * d.std_dev
    d.skewness = m3 / (nf * sd3)
    d.kurtosis = m4 / (nf * v * v) - 3.0f64
    let se1 = math.sqrt[f64](6.0f64 * nf * (nf - 1.0f64) / (nf - 2.0f64) / (nf + 1.0f64) / (nf + 3.0f64))
    d.skew_2se = d.skewness / (2.0f64 * se1)
    let se2 = math.sqrt[f64](24.0f64 * nf * ((nf - 1.0f64) * (nf - 1.0f64)) / (nf - 3.0f64) / (nf - 2.0f64) / (nf + 3.0f64) / (nf + 5.0f64))
    d.kurt_2se = d.kurtosis / (2.0f64 * se2)
    d.normtest_w = 0.0f64 / 0.0f64
    d.normtest_p = 0.0f64 / 0.0f64
    if n >= 3usize && n <= 5000usize {
        let (sc, e2) = mem.alloc[f64](a, n / 2usize + 1usize)
        if e2 != ok { ret (d, e2) }
        let (sw, e3) = tst.shapiro_wilk(s, sc)
        if e3 == ok {
            d.normtest_w = sw.statistic
            d.normtest_p = sw.p_value
        }
    }
    ret (d, ok)
}

// ---- the tsd decompositions by differencing and by running medians ----

// pastecs::decdiff: lag-`lag` differences of the given order; ends 0 pads the front with NaN, 1 with the mean of the first lag*order values, 2 drops the first lag*order points; answers the length m of `filt` and `resid` (n, or n - lag*order for ends 2); type 0 additive residual x - filtered, 1 multiplicative x / filtered
fn decdiff(a: *mem.Arena, x: []const f64, ty: u8, lag: usize, order: usize, ends: u8, filt: []f64, resid: []f64) -> (usize, err) {
    let n = x.len
    let pad = lag * order
    var len = n
    if ends != 2u8 { len = n + pad }
    let (cur, e1) = mem.alloc[f64](a, len)
    let (nxt, e2) = mem.alloc[f64](a, len)
    if e1 != ok || e2 != ok { ret (0usize, e1) }
    var i = 0usize
    if ends != 2u8 {
        var fillv = 0.0f64 / 0.0f64
        if ends == 1u8 {
            var s = 0.0f64
            while i < pad {
                s += x[i]
                i += 1usize
            }
            fillv = s / f64(pad)
        }
        i = 0usize
        while i < pad {
            cur[i] = fillv
            i += 1usize
        }
        i = 0usize
        while i < n {
            cur[pad + i] = x[i]
            i += 1usize
        }
    } else {
        i = 0usize
        while i < n {
            cur[i] = x[i]
            i += 1usize
        }
    }
    var cl = len
    var d = 0usize
    while d < order {
        i = 0usize
        while i + lag < cl {
            nxt[i] = cur[i + lag] - cur[i]
            i += 1usize
        }
        cl -= lag
        i = 0usize
        while i < cl {
            cur[i] = nxt[i]
            i += 1usize
        }
        d += 1usize
    }
    var off = 0usize
    if ends == 2u8 { off = pad }
    i = 0usize
    while i < cl {
        filt[i] = cur[i]
        if ty == 0u8 { resid[i] = x[off + i] - cur[i] } else { resid[i] = x[off + i] / cur[i] }
        i += 1usize
    }
    ret (cl, ok)
}

// pastecs::decmedian: `times` passes of a running median of 2 order + 1 points; ends 0 leaves NaN where the window runs off the series, 1 takes the median of the points inside
fn decmedian(a: *mem.Arena, x: []const f64, ty: u8, order: usize, times: usize, ends: u8, filt: []f64, resid: []f64) -> err {
    let n = x.len
    let term = 2usize * order + 1usize
    let (cur, e1) = mem.alloc[f64](a, n)
    let (nxt, e2) = mem.alloc[f64](a, n)
    let (win, e3) = mem.alloc[f64](a, term)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    var i = 0usize
    while i < n {
        cur[i] = x[i]
        i += 1usize
    }
    var t = 0usize
    while t < times {
        i = 0usize
        while i < n {
            var cnt = 0usize
            var hasna = false
            var k = 0usize
            while k < term {
                // window k covers original index i + k - order; outside the series it is NA
                var v = 0.0f64 / 0.0f64
                if i + k >= order && i + k - order < n { v = cur[i + k - order] }
                if v != v {
                    hasna = true
                } else {
                    win[cnt] = v
                    cnt += 1usize
                }
                k += 1usize
            }
            if (ends == 0u8 && hasna) || cnt == 0usize {
                nxt[i] = 0.0f64 / 0.0f64
            } else {
                var q = 1usize
                while q < cnt {
                    let key = win[q]
                    var r = q
                    while r > 0usize && win[r - 1usize] > key {
                        win[r] = win[r - 1usize]
                        r -= 1usize
                    }
                    win[r] = key
                    q += 1usize
                }
                if cnt % 2usize == 1usize { nxt[i] = win[cnt / 2usize] } else { nxt[i] = (win[cnt / 2usize - 1usize] + win[cnt / 2usize]) / 2.0f64 }
            }
            i += 1usize
        }
        i = 0usize
        while i < n {
            cur[i] = nxt[i]
            i += 1usize
        }
        t += 1usize
    }
    i = 0usize
    while i < n {
        filt[i] = cur[i]
        if ty == 0u8 { resid[i] = x[i] - cur[i] } else { resid[i] = x[i] / cur[i] }
        i += 1usize
    }
    ret ok
}

// R's stats::filter convolution of z with the normalised weights wt (length k): out[i] = sum_j wt[j] z[i + o - j] with o = k %/% 2 for sides 2 and 0 for sides 1; NaN where an index falls outside the series (wrapped around when circular)
fn conv_filter(z: []const f64, wt: []const f64, sides: usize, circular: bool, out: []f64) {
    let n = z.len
    let k = wt.len
    var o = 0usize
    if sides == 2usize { o = k / 2usize }
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var bad = false
        var j = 0usize
        while j < k {
            let pos = i64(i) + i64(o) - i64(j)
            if pos < 0i64 || pos >= i64(n) {
                if circular {
                    var q = pos % i64(n)
                    if q < 0i64 { q += i64(n) }
                    s += wt[j] * z[usize(q)]
                } else {
                    bad = true
                }
            } else {
                s += wt[j] * z[usize(pos)]
            }
            j += 1usize
        }
        if bad { out[i] = 0.0f64 / 0.0f64 } else { out[i] = s }
        i += 1usize
    }
}

// pastecs::decaverage: `times` passes of a moving average with `weights` (the caller builds the periodic ones), sides 1 or 2, over a series padded as ends says (0 NAs, 1 fill with end means, 2 circular, 3 periodic with period `freq`); type 0 additive, 1 multiplicative
fn decaverage(a: *mem.Arena, x: []const f64, ty: u8, times: usize, sides: usize, ends: u8, weights: []const f64, freq: usize, filt: []f64, resid: []f64) -> err {
    let n = x.len
    let k = weights.len
    let order0 = k / 2usize
    let (wt, e1) = mem.alloc[f64](a, k)
    let (cur, e2) = mem.alloc[f64](a, n)
    let (pad, e3) = mem.alloc[f64](a, n + 2usize * k + 2usize * freq + 4usize)
    let (outp, e4) = mem.alloc[f64](a, n + 2usize * k + 2usize * freq + 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
    var sw = 0.0f64
    var i = 0usize
    while i < k {
        sw += weights[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        wt[i] = weights[i] / sw
        i += 1usize
    }
    i = 0usize
    while i < n {
        cur[i] = x[i]
        i += 1usize
    }
    var t = 0usize
    while t < times {
        var plen = n
        var cut0 = 0usize
        var circ = false
        if ends == 1u8 {
            var od = order0
            if sides == 2usize {
                if od > n { od = n }
                var s1 = 0.0f64
                var s2 = 0.0f64
                i = 0usize
                while i < od {
                    s1 += cur[i]
                    s2 += cur[n - od + i]
                    i += 1usize
                }
                i = 0usize
                while i < od {
                    pad[i] = s1 / f64(od)
                    pad[od + n + i] = s2 / f64(od)
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    pad[od + i] = cur[i]
                    i += 1usize
                }
                plen = n + 2usize * od
                cut0 = od
            } else {
                if 2usize * od > n { od = n / 2usize }
                var s1 = 0.0f64
                i = 0usize
                while i < 2usize * od {
                    s1 += cur[i]
                    i += 1usize
                }
                i = 0usize
                while i < 2usize * od {
                    pad[i] = s1 / f64(2usize * od)
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    pad[2usize * od + i] = cur[i]
                    i += 1usize
                }
                plen = n + 2usize * od
                cut0 = 2usize * od
            }
        } else if ends == 3u8 && n >= 2usize * freq {
            var pos = freq / 2usize
            if sides == 1usize { pos = (freq / 2usize) * 2usize }
            let pos0 = freq - pos
            i = 0usize
            while i < pos {
                pad[i] = cur[pos0 + i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                pad[pos + i] = cur[i]
                i += 1usize
            }
            if sides == 2usize {
                i = 0usize
                while i < pos {
                    pad[pos + n + i] = cur[i + n - freq]
                    i += 1usize
                }
                plen = n + 2usize * pos
            } else {
                plen = n + pos
            }
            cut0 = pos
        } else {
            i = 0usize
            while i < n {
                pad[i] = cur[i]
                i += 1usize
            }
            if ends == 2u8 { circ = true }
        }
        conv_filter(pad[0usize..plen], wt, sides, circ, outp[0usize..plen])
        i = 0usize
        while i < n {
            cur[i] = outp[cut0 + i]
            i += 1usize
        }
        t += 1usize
    }
    i = 0usize
    while i < n {
        filt[i] = cur[i]
        if ty == 0u8 { resid[i] = x[i] - cur[i] } else { resid[i] = x[i] / cur[i] }
        i += 1usize
    }
    ret ok
}

// pastecs::decevf: the series is embedded with `lag` lags, projected onto the principal axes listed in `axes` (1-based, by decreasing variance; the covariance has divisor N as princomp's), rebuilt, and the diagonals of the rebuilt matrix averaged back into a series of the original length; type 0 additive, 1 multiplicative
fn decevf(a: *mem.Arena, x: []const f64, ty: u8, lag: usize, axes: []const usize, filt: []f64, resid: []f64) -> err {
    let n = x.len
    let rows = n - lag + 1usize
    let (xm, e1) = mem.alloc[f64](a, rows * lag)
    let (ctr, e2) = mem.alloc[f64](a, lag)
    let (cov, e3) = mem.alloc[f64](a, lag * lag)
    let (proj, e4) = mem.alloc[f64](a, lag * lag)
    let (acc, e5) = mem.alloc[f64](a, n)
    let (cnt, e6) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    var r = 0usize
    while r < rows {
        var c = 0usize
        while c < lag {
            xm[r * lag + c] = x[r + lag - 1usize - c]
            c += 1usize
        }
        r += 1usize
    }
    var c = 0usize
    while c < lag {
        var s = 0.0f64
        r = 0usize
        while r < rows {
            s += xm[r * lag + c]
            r += 1usize
        }
        ctr[c] = s / f64(rows)
        c += 1usize
    }
    c = 0usize
    while c < lag {
        var d = 0usize
        while d < lag {
            var s = 0.0f64
            r = 0usize
            while r < rows {
                s += (xm[r * lag + c] - ctr[c]) * (xm[r * lag + d] - ctr[d])
                r += 1usize
            }
            cov[c * lag + d] = s / f64(rows)
            d += 1usize
        }
        c += 1usize
    }
    let (vals, vecs, ee) = ica.eigen_sym(a, cov, lag)
    if ee != ok { ret ee }
    // proj = V_s V_s' with the kept columns of V
    c = 0usize
    while c < lag {
        var d = 0usize
        while d < lag {
            var s = 0.0f64
            var q = 0usize
            while q < axes.len {
                let col = axes[q] - 1usize
                s += vecs[c * lag + col] * vecs[d * lag + col]
                q += 1usize
            }
            proj[c * lag + d] = s
            d += 1usize
        }
        c += 1usize
    }
    var t = 0usize
    while t < n {
        acc[t] = 0.0f64
        cnt[t] = 0.0f64
        t += 1usize
    }
    r = 0usize
    while r < rows {
        c = 0usize
        while c < lag {
            var s = ctr[c]
            var d = 0usize
            while d < lag {
                s += (xm[r * lag + d] - ctr[d]) * proj[d * lag + c]
                d += 1usize
            }
            let tt = r + lag - 1usize - c
            acc[tt] += s
            cnt[tt] += 1.0f64
            c += 1usize
        }
        r += 1usize
    }
    t = 0usize
    while t < n {
        filt[t] = acc[t] / cnt[t]
        if ty == 0u8 { resid[t] = x[t] - filt[t] } else { resid[t] = x[t] / filt[t] }
        t += 1usize
    }
    ret ok
}

// ---- trend.test: Spearman's rank correlation of the series with time, as stats::cor.test(method = "spearman") answers it ----

// the average ranks of x
fn average_ranks(a: *mem.Arena, x: []const f64, rk: []f64) -> err {
    let n = x.len
    let (idx, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    // insertion sort of idx by x (stable)
    i = 1usize
    while i < n {
        let key = idx[i]
        var j = i
        while j > 0usize && x[idx[j - 1usize]] > x[key] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = key
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = i
        while j + 1usize < n && x[idx[j + 1usize]] == x[idx[i]] { j += 1usize }
        let r = (f64(i) + f64(j)) / 2.0f64 + 1.0f64
        var k = i
        while k <= j {
            rk[idx[k]] = r
            k += 1usize
        }
        i = j + 1usize
    }
    ret ok
}

// AS 89: Pr[S >= is] (or Pr[S < is] when lower_tail), exact for n <= 9 and by Edgeworth series beyond
fn prho(n: i64, is: f64, lower_tail: bool) -> f64 {
    var pv = 1.0f64
    if lower_tail { pv = 0.0f64 }
    if n <= 1i64 { ret pv }
    if is <= 0.0f64 { ret pv }
    var n3 = f64(n)
    n3 = n3 * (n3 * n3 - 1.0f64) / 3.0f64
    if is > n3 { ret 1.0f64 - pv }
    if n <= 9i64 {
        var l: [9]i64 = zero
        var nfac = 1i64
        var i = 1i64
        while i <= n {
            nfac = nfac * i
            l[usize(i - 1i64)] = i
            i += 1i64
        }
        var ifr = 0i64
        if is == n3 {
            ifr = 1i64
        } else {
            var m = 0i64
            while m < nfac {
                var ise = 0i64
                var q = 0i64
                while q < n {
                    let n1 = q + 1i64 - l[usize(q)]
                    ise += n1 * n1
                    q += 1i64
                }
                if is <= f64(ise) { ifr += 1i64 }
                var n1 = n
                var mt = 0i64
                var going = true
                while going {
                    mt = l[0usize]
                    var r = 1i64
                    while r < n1 {
                        l[usize(r - 1i64)] = l[usize(r)]
                        r += 1i64
                    }
                    n1 -= 1i64
                    l[usize(n1)] = mt
                    going = mt == n1 + 1i64 && n1 > 1i64
                }
                m += 1i64
            }
        }
        if lower_tail { ret f64(nfac - ifr) / f64(nfac) }
        ret f64(ifr) / f64(nfac)
    }
    let c1 = 0.2274f64
    let c2 = 0.2531f64
    let c3 = 0.1745f64
    let c4 = 0.0758f64
    let c5 = 0.1033f64
    let c6 = 0.3932f64
    let c7 = 0.0879f64
    let c8 = 0.0151f64
    let c9 = 0.0072f64
    let c10 = 0.0831f64
    let c11 = 0.0131f64
    let c12 = 4.6e-4f64
    let y0 = f64(n)
    let b = 1.0f64 / y0
    let x = (6.0f64 * (is - 1.0f64) * b / (y0 * y0 - 1.0f64) - 1.0f64) * math.sqrt[f64](y0 - 1.0f64)
    var y = x * x
    let u = x * b * (c1 + b * (c2 + c3 * b) + y * (0.0f64 - c4 + b * (c5 + c6 * b) - y * b * (c7 + c8 * b - y * (c9 - c10 * b + y * b * (c11 - c12 * y)))))
    y = u / math.exp[f64](y / 2.0f64)
    var s = y
    if lower_tail { s = 0.0f64 - y }
    pv = s + dist.pnorm(x, 0.0f64, 1.0f64, lower_tail, false)
    if pv < 0.0f64 { pv = 0.0f64 }
    if pv > 1.0f64 { pv = 1.0f64 }
    ret pv
}

type TrendTest = struct { rho: f64, s: f64, p: f64 }

// pastecs::trend.test(x) for a single series: Spearman's test of x against time (two-sided; exact when n < 1290 and there are no ties)
fn trend_test(a: *mem.Arena, x: []const f64) -> (TrendTest, err) {
    var res: TrendTest = zero
    let n = x.len
    let (rx, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (res, e1) }
    let er = average_ranks(a, x, rx)
    if er != ok { ret (res, er) }
    // the ranks of time are 1..n; Pearson correlation of the two rank vectors
    var mx = 0.0f64
    var i = 0usize
    while i < n {
        mx += rx[i]
        i += 1usize
    }
    mx = mx / f64(n)
    let mt = (f64(n) + 1.0f64) / 2.0f64
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < n {
        let dx = rx[i] - mx
        let dy = f64(i + 1usize) - mt
        sxy += dx * dy
        sxx += dx * dx
        syy += dy * dy
        i += 1usize
    }
    let r = sxy / math.sqrt[f64](sxx * syy)
    let nf = f64(n)
    let q = (nf * nf * nf - nf) * (1.0f64 - r) / 6.0f64
    var ties = false
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            if x[i] == x[j] { ties = true }
            j += 1usize
        }
        i += 1usize
    }
    var p = 0.0f64
    let exact = n < 1290usize && !ties
    let big = (nf * nf * nf - nf) / 6.0f64
    if q > big {
        if exact { p = prho(i64(n), math.round[f64](q), false) } else {
            let den = (nf * (nf * nf - 1.0f64)) / 6.0f64
            let rr = 1.0f64 - q / den
            p = nb.pt(rr / math.sqrt[f64]((1.0f64 - rr * rr) / (nf - 2.0f64)), nf - 2.0f64, true, false)
        }
    } else {
        if exact { p = prho(i64(n), math.round[f64](q) + 2.0f64, true) } else {
            let den = (nf * (nf * nf - 1.0f64)) / 6.0f64
            let rr = 1.0f64 - q / den
            p = nb.pt(rr / math.sqrt[f64]((1.0f64 - rr * rr) / (nf - 2.0f64)), nf - 2.0f64, false, false)
        }
    }
    p = math.min[f64](2.0f64 * p, 1.0f64)
    res.rho = r
    res.s = q
    res.p = p
    ret (res, ok)
}

// ---- regul: regularisation of an irregular series (zero tolerance, no spline) ----

// R's approx at v on the sorted unique abscissas x: method 0 constant (with f), 1 linear; rule 1 gives NaN outside the range, rule 2 the end values
fn approx1(x: []const f64, y: []const f64, v: f64, method: usize, rule: usize, f: f64) -> f64 {
    let n = x.len
    if v < x[0usize] {
        if rule == 1usize { ret 0.0f64 / 0.0f64 }
        ret y[0usize]
    }
    if v > x[n - 1usize] {
        if rule == 1usize { ret 0.0f64 / 0.0f64 }
        ret y[n - 1usize]
    }
    var i = 0usize
    var j = n - 1usize
    while i + 1usize < j {
        let ij = (i + j) / 2usize
        if v < x[ij] { j = ij } else { i = ij }
    }
    if v == x[j] { ret y[j] }
    if v == x[i] { ret y[i] }
    if method == 1usize { ret y[i] + (y[j] - y[i]) * ((v - x[i]) / (x[j] - x[i])) }
    var r = 0.0f64
    if f != 1.0f64 { r += y[i] * (1.0f64 - f) }
    if f != 0.0f64 { r += y[j] * f }
    ret r
}

// pastecs::regul on one series with tol = 0 (x sorted ascending and distinct; an output abscissa equal to an observation takes that observation, and the area method's abscissa is the shifted and unshifted one, so it matches only when the shift leaves it exact): method 0 constant, 1 linear, 2 area; the n values at xmin + i deltat go to `out`
fn regul(x: []const f64, y: []const f64, xmin: f64, n: usize, deltat: f64, method: usize, rule: usize, f: f64, window: f64, out: []f64) -> err {
    let nx = x.len
    var i = 0usize
    if method < 2usize {
        while i < n {
            out[i] = approx1(x, y, f64(i) * deltat + xmin, method, rule, f)
            i += 1usize
        }
    } else {
        let halfwin = window / 2.0f64
        let xmax = f64(n - 1usize) * deltat + xmin
        var xlb = xmin - halfwin - 1.0f64
        if x[0usize] < xlb { xlb = x[0usize] }
        var xub = xmax + halfwin + 1.0f64
        if x[nx - 1usize] > xub { xub = x[nx - 1usize] }
        var shift = 0.0f64
        if xlb <= 0.0f64 { shift = 0.0f64 - xlb + 1.0f64 }
        i = 0usize
        while i < n {
            let xo = f64(i) * deltat + xmin + shift
            let u1 = xo - halfwin
            let u2 = u1 + window
            var s = 0.0f64
            var k = 0usize
            while k < nx {
                var a1 = xlb + shift
                if k > 0usize { a1 = (x[k - 1usize] + shift + x[k] + shift) / 2.0f64 }
                var a2 = xub + shift
                if k + 1usize < nx { a2 = (x[k] + shift + x[k + 1usize] + shift) / 2.0f64 }
                var lo = a1
                if u1 > lo { lo = u1 }
                var hi = a2
                if u2 < hi { hi = u2 }
                var w = hi - lo
                if w < 0.0f64 { w = 0.0f64 }
                s += y[k] * w
                k += 1usize
            }
            out[i] = s / window
            if rule == 1usize && (xo < x[0usize] + shift || xo > x[nx - 1usize] + shift) { out[i] = 0.0f64 / 0.0f64 }
            let xr = xo - shift
            var k2 = 0usize
            while k2 < nx {
                if x[k2] == xr { out[i] = y[k2] }
                k2 += 1usize
            }
            i += 1usize
        }
    }
    ret ok
}

// ---- pgleissberg and pennington ----

// the distribution of the number of turning points of a random permutation of n values, P(K = k) for k = 0..n-2, by counting permutations over the rank of the last element, the sign of the last step and the turns so far
fn gleissberg_pmf(a: *mem.Arena, n: usize, pmf: []f64) -> err {
    var k = 0usize
    while k < n - 1usize {
        pmf[k] = 0.0f64
        k += 1usize
    }
    if n == 3usize {
        pmf[0usize] = 1.0f64 / 3.0f64
        pmf[1usize] = 2.0f64 / 3.0f64
        ret ok
    }
    let nt = n
    let sz = (n + 2usize) * 2usize * nt
    let (cur, e1) = mem.alloc[f64](a, sz)
    let (nxt, e2) = mem.alloc[f64](a, sz)
    if e1 != ok || e2 != ok { ret mem.Full }
    var q = 0usize
    while q < sz {
        cur[q] = 0.0f64
        q += 1usize
    }
    // index (j * 2 + s) * nt + t, j in 1..i
    cur[(1usize * 2usize + 0usize) * nt] = 1.0f64
    cur[(2usize * 2usize + 1usize) * nt] = 1.0f64
    var i = 2usize
    while i < n {
        q = 0usize
        while q < sz {
            nxt[q] = 0.0f64
            q += 1usize
        }
        var j = 1usize
        while j <= i {
            var s = 0usize
            while s < 2usize {
                var t = 0usize
                while t < nt {
                    let v = cur[(j * 2usize + s) * nt + t]
                    if v != 0.0f64 {
                        var jp = 1usize
                        while jp <= i + 1usize {
                            var sn = 0usize
                            if jp > j { sn = 1usize }
                            var tn = t
                            if sn != s { tn += 1usize }
                            nxt[(jp * 2usize + sn) * nt + tn] += v
                            jp += 1usize
                        }
                    }
                    t += 1usize
                }
                s += 1usize
            }
            j += 1usize
        }
        q = 0usize
        while q < sz {
            cur[q] = nxt[q]
            q += 1usize
        }
        i += 1usize
    }
    var fact = 1.0f64
    q = 2usize
    while q <= n {
        fact *= f64(q)
        q += 1usize
    }
    var j = 1usize
    while j <= n {
        var s = 0usize
        while s < 2usize {
            var t = 0usize
            while t + 1usize < n {
                pmf[t] += cur[(j * 2usize + s) * nt + t] / fact
                t += 1usize
            }
            s += 1usize
        }
        j += 1usize
    }
    ret ok
}

// pastecs::pgleissberg for one (n, k): the exact distribution below 50 observations, the normal approximation from 50
fn pgleissberg(a: *mem.Arena, n: usize, k: f64, lower: bool, two_tailed: bool) -> (f64, err) {
    let nf = f64(n)
    if n < 3usize || k < 0.0f64 || k > nf - 2.0f64 { ret (0.0f64, ok) }
    if n >= 50usize {
        let mu = 2.0f64 / 3.0f64 * (nf - 2.0f64)
        let sd = math.sqrt[f64]((16.0f64 * nf - 29.0f64) / 90.0f64)
        let p = dist.pnorm(k, mu, sd, true, false)
        if two_tailed {
            var r = p
            if r > 0.5f64 { r = 1.0f64 - r }
            ret (2.0f64 * r, ok)
        }
        if lower { ret (p, ok) }
        ret (1.0f64 - p, ok)
    }
    let (pmf, e) = mem.alloc[f64](a, n)
    if e != ok { ret (0.0f64, e) }
    let e2 = gleissberg_pmf(a, n, pmf)
    if e2 != ok { ret (0.0f64, e2) }
    // the package's table holds P(K <= c - 1) at the 1-based column c; its lower tail is the complement
    if two_tailed {
        let mu = 2.0f64 / 3.0f64 * (nf - 2.0f64)
        let delta = math.abs[f64](mu - k)
        let c1 = usize(math.floor[f64](mu - delta + 1.0f64))
        let c2 = usize(math.floor[f64](mu + delta + 1.0f64))
        var s1 = 0.0f64
        var s2 = 0.0f64
        var t = 0usize
        while t < n - 1usize {
            if t + 1usize <= c1 { s1 += pmf[t] }
            if t + 1usize <= c2 { s2 += pmf[t] }
            t += 1usize
        }
        ret (s1 + (1.0f64 - s2), ok)
    }
    let kk = usize(k)
    var tab = 0.0f64
    var t = 0usize
    while t <= kk && t < n - 1usize {
        tab += pmf[t]
        t += 1usize
    }
    if lower { ret (1.0f64 - tab, ok) }
    ret (tab, ok)
}

fn gmt(m: f64, t: f64) -> f64 {
    if t == 0.0f64 { ret 1.0f64 }
    var sum = 1.0f64 + t * (m - 1.0f64) / m
    var it = 1.0f64
    var del = 1.0f64
    var go = true
    while go {
        it += 1.0f64
        if !(del > 1.0e-4f64 && it < 20.0f64) {
            go = false
        } else {
            let j = it
            var st = (2.0f64 * j - 1.0f64) * math.log[f64](m - 1.0f64) + j * math.log[f64](t) - j * math.log[f64](m)
            var q = 2.0f64
            // sum(log(c(2:j - 1) * 2 - 1 + m)): the sequence (2:j) - 1 = 1..j-1 times 2, minus 1, plus m
            var qq = 1.0f64
            while qq <= j - 1.0f64 {
                st -= math.log[f64](qq * 2.0f64 - 1.0f64 + m)
                qq += 1.0f64
            }
            qq = 1.0f64
            while qq <= j {
                st -= math.log[f64](qq)
                qq += 1.0f64
            }
            let sum2 = sum + math.exp[f64](st)
            del = math.abs[f64]((sum - sum2) / sum)
            sum = sum2
            q += 0.0f64
        }
    }
    ret sum
}

// pastecs::pennington for a sample with no missing values: calc 0 mean, 1 variance of the mean (the package's "var"), 2 mean.var; the Gmt series stops once its relative change is below 1e-4 or at 19 terms
fn pennington(x: []const f64, calc: usize) -> f64 {
    let n = f64(x.len)
    var m = 0.0f64
    var sl = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] > 0.0f64 {
            m += 1.0f64
            sl += math.log[f64](x[i])
        }
        i += 1usize
    }
    if m == 0.0f64 { ret 0.0f64 }
    let ml = sl / m
    var vl = 0.0f64 / 0.0f64
    if m > 1.0f64 {
        var ss = 0.0f64
        i = 0usize
        while i < x.len {
            if x[i] > 0.0f64 {
                let d = math.log[f64](x[i]) - ml
                ss += d * d
            }
            i += 1usize
        }
        vl = ss / (m - 1.0f64)
    }
    if m == 1.0f64 {
        if calc == 0usize { ret math.exp[f64](ml) / n }
        ret math.exp[f64](ml) * math.exp[f64](ml) / n
    }
    if calc == 0usize { ret m / n * math.exp[f64](ml) * gmt(m, vl / 2.0f64) }
    if calc == 1usize { ret m / n * math.exp[f64](2.0f64 * ml) * (gmt(m, 2.0f64 * vl) - (m - 1.0f64) / (n - 1.0f64) * gmt(m, (m - 2.0f64) / (m - 1.0f64) * vl)) }
    ret m / n * math.exp[f64](2.0f64 * ml) * (m / n * gmt(m, vl / 2.0f64) * gmt(m, vl / 2.0f64) - (m - 1.0f64) / (n - 1.0f64) * gmt(m, (m - 2.0f64) / (m - 1.0f64) * vl))
}

// ---- escouf and local.trend ----

// pastecs::local.trend's cusum: cumsum(x - k)
fn local_trend(x: []const f64, k: f64, out: []f64) {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] - k
        out[i] = s
        i += 1usize
    }
}

// the Pearson correlation of columns a and b of the n by p column-major matrix x (columns indexed from 0)
fn colcor(x: []const f64, n: usize, ca: usize, cb: usize) -> f64 {
    var ma = 0.0f64
    var mb = 0.0f64
    var i = 0usize
    while i < n {
        ma += x[ca * n + i]
        mb += x[cb * n + i]
        i += 1usize
    }
    ma = ma / f64(n)
    mb = mb / f64(n)
    var sab = 0.0f64
    var saa = 0.0f64
    var sbb = 0.0f64
    i = 0usize
    while i < n {
        let da = x[ca * n + i] - ma
        let db = x[cb * n + i] - mb
        sab += da * db
        saa += da * da
        sbb += db * db
        i += 1usize
    }
    ret sab / math.sqrt[f64](saa * sbb)
}

// pastecs::escouf: Escoufier's equivalent vectors on the n by p column-major data; vr (the variables in order, 1-based) and rv (their RV coefficients) receive up to p entries, the count is returned; the loop stops after the first RV above `level`
fn escouf(a: *mem.Arena, x: []const f64, n: usize, p: usize, level: f64, vr: []usize, rv: []f64) -> (usize, err) {
    let (cor, e1) = mem.alloc[f64](a, p * p)
    let (vt, e2) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok { ret (0usize, mem.Full) }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            if i == j { cor[i * p + j] = 1.0f64 } else { cor[i * p + j] = colcor(x, n, i, j) }
            j += 1usize
        }
        vt[i] = i
        i += 1usize
    }
    var ryy = 0.0f64
    i = 0usize
    while i < p * p {
        ryy += cor[i] * cor[i]
        i += 1usize
    }
    var nvt = p
    var cnt = 0usize
    var vrt = 0usize
    i = 1usize
    while i <= p {
        var rvmax = 0.0f64
        var j = 0usize
        while j < nvt {
            // the chosen set: the earlier picks then candidate j
            var sxy = 0.0f64
            var sxx = 0.0f64
            var q = 0usize
            while q < i {
                var cq = vt[j]
                if q < i - 1usize { cq = vr[q] - 1usize }
                var w = 0usize
                while w < p {
                    let c = cor[cq * p + w]
                    sxy += c * c
                    w += 1usize
                }
                var r2 = 0usize
                while r2 < i {
                    var cr = vt[j]
                    if r2 < i - 1usize { cr = vr[r2] - 1usize }
                    var c2 = 1.0f64
                    if cq != cr { c2 = cor[cq * p + cr] }
                    sxx += c2 * c2
                    r2 += 1usize
                }
                q += 1usize
            }
            let rvv = sxy / math.sqrt[f64](ryy * sxx)
            if rvv > rvmax {
                rvmax = rvv
                vrt = vt[j]
            }
            j += 1usize
        }
        vr[cnt] = vrt + 1usize
        rv[cnt] = rvmax
        cnt += 1usize
        var m = 0usize
        j = 0usize
        while j < nvt {
            if vt[j] != vrt {
                vt[m] = vt[j]
                m += 1usize
            }
            j += 1usize
        }
        nvt = m
        if rvmax > level { ret (cnt, ok) }
        i += 1usize
    }
    ret (cnt, ok)
}

// ---- abund and turnogram ----

type Abund = struct { vr: []usize, sort_: []f64, cumsum: []f64, plogind: []f64, pnonull: []f64 }

// pastecs::abund on the q by p column-major abundance table: the variables sorted by f * percent of log individuals + (1 - f) * percent of zeros, with the cumulative difference of the scaled percentages
fn abund(a: *mem.Arena, x: []const f64, q: usize, p: usize, f0: f64) -> (Abund, err) {
    var r: Abund = zero
    let (vr, e1) = mem.alloc[usize](a, p)
    let (srt, e2) = mem.alloc[f64](a, p)
    let (cs, e3) = mem.alloc[f64](a, p)
    let (pli, e4) = mem.alloc[f64](a, p)
    let (pnn, e5) = mem.alloc[f64](a, p)
    let (nz, e6) = mem.alloc[f64](a, p)
    let (ind, e7) = mem.alloc[f64](a, p)
    let (key, e8) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (r, mem.Full) }
    var f = f0
    if f <= 0.0f64 { f = 1.0e-5f64 }
    if f >= 1.0f64 { f = 0.99999f64 }
    var mx = 0.0f64 - 1.0f64 / 0.0f64
    var j = 0usize
    while j < p {
        var nn = 0.0f64
        var s = 0.0f64
        var i = 0usize
        while i < q {
            if x[j * q + i] != 0.0f64 { nn += 1.0f64 }
            s += x[j * q + i]
            i += 1usize
        }
        nz[j] = 100.0f64 - nn / f64(q) * 100.0f64
        var lg = math.log[f64](s)
        if lg - lg != 0.0f64 { lg = 0.0f64 }
        ind[j] = lg
        if lg > mx { mx = lg }
        pnn[j] = nn / f64(q) * 100.0f64
        j += 1usize
    }
    j = 0usize
    while j < p {
        ind[j] = ind[j] / mx * 100.0f64
        key[j] = f * ind[j] + (1.0f64 - f) * nz[j]
        vr[j] = j
        j += 1usize
    }
    // stable order by key
    j = 1usize
    while j < p {
        var m = j
        while m > 0usize && key[vr[m - 1usize]] > key[vr[m]] {
            let t = vr[m - 1usize]
            vr[m - 1usize] = vr[m]
            vr[m] = t
            m -= 1usize
        }
        j += 1usize
    }
    var pmin = 1.0e300f64
    var pmax = 0.0f64 - 1.0e300f64
    var nmin = 1.0e300f64
    var nmax = 0.0f64 - 1.0e300f64
    j = 0usize
    while j < p {
        srt[j] = key[vr[j]]
        pli[j] = ind[vr[j]]
        pnn[j] = pnn[j]
        j += 1usize
    }
    // the percent of non-null values in the sorted order
    let (pn2, e9) = mem.alloc[f64](a, p)
    if e9 != ok { ret (r, mem.Full) }
    j = 0usize
    while j < p {
        pn2[j] = pnn[vr[j]]
        if pli[j] < pmin { pmin = pli[j] }
        if pli[j] > pmax { pmax = pli[j] }
        if pn2[j] < nmin { nmin = pn2[j] }
        if pn2[j] > nmax { nmax = pn2[j] }
        j += 1usize
    }
    var run = 0.0f64
    var cmin = 1.0e300f64
    var cmax = 0.0f64 - 1.0e300f64
    j = 0usize
    while j < p {
        let pi = (pli[j] - pmin) / (pmax - pmin) * 100.0f64
        let pn = (pn2[j] - nmin) / (nmax - nmin) * 100.0f64
        run += pi - pn
        cs[j] = run
        if run < cmin { cmin = run }
        if run > cmax { cmax = run }
        j += 1usize
    }
    j = 0usize
    while j < p {
        cs[j] = (cs[j] - cmin) / (cmax - cmin) * 100.0f64
        vr[j] = vr[j] + 1usize
        j += 1usize
    }
    r.vr = vr
    r.sort_ = srt
    r.cumsum = cs
    r.plogind = pli
    r.pnonull = pn2
    ret (r, ok)
}

type Turnogram = struct { m: usize, interval: []f64, n: []f64, turns: []f64, turns_min: []f64, turns_max: []f64, info: []f64, info_min: []f64, info_max: []f64, level: f64 }

// the mean of the non-missing values of each column of the interval-by-k layout of x[from..] (padded with missing values), as `apply(series, 2, mean, na.rm = TRUE)`
fn stripmeans(x: []const f64, from: usize, interval: usize, out: []f64) -> usize {
    let len = x.len - from
    let k = (len + interval - 1usize) / interval
    var c = 0usize
    while c < k {
        var s = 0.0f64
        var cnt = 0.0f64
        var i = 0usize
        while i < interval {
            let idx = c * interval + i
            if idx < len {
                s += x[from + idx]
                cnt += 1.0f64
            }
            i += 1usize
        }
        out[c] = s / cnt
        c += 1usize
    }
    ret k
}

fn info_of(a: *mem.Arena, n: usize, turns: f64, two: bool) -> (f64, err) {
    let (pg, e) = pgleissberg(a, n, turns, true, two)
    if e != ok { ret (0.0f64, e) }
    var inf = 0.0f64 - math.log2[f64](pg)
    if two && turns > 2.0f64 * (f64(n) - 2.0f64) / 3.0f64 { inf = 0.0f64 - inf }
    ret (inf, ok)
}

// pastecs::turnogram with FUN = mean: simple (complete = false) or complete, one- or two-tailed, for intervals imin to imax by step
fn turnogram(a: *mem.Arena, x: []const f64, imin: f64, imax: f64, step: f64, complete: bool, two: bool) -> (Turnogram, err) {
    var r: Turnogram = zero
    var m = 0usize
    var v = imin
    while v <= imax + 1.0e-10f64 {
        m += 1usize
        v += step
    }
    let (iv, e1) = mem.alloc[f64](a, m)
    let (nv, e2) = mem.alloc[f64](a, m)
    let (tv, e3) = mem.alloc[f64](a, m)
    let (tmn, e4) = mem.alloc[f64](a, m)
    let (tmx, e5) = mem.alloc[f64](a, m)
    let (inf, e6) = mem.alloc[f64](a, m)
    let (imn, e7) = mem.alloc[f64](a, m)
    let (imx, e8) = mem.alloc[f64](a, m)
    let (buf, e9) = mem.alloc[f64](a, x.len + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (r, mem.Full) }
    var i = 0usize
    while i < m {
        let interval = usize(imin + step * f64(i))
        iv[i] = f64(interval)
        if !complete {
            let k = stripmeans(x, 0usize, interval, buf)
            let (tp, te) = turnpoints(a, buf[0usize..k])
            if te != ok { ret (r, te) }
            nv[i] = f64(k)
            tv[i] = f64(tp.nturns)
            let (iff, ie) = info_of(a, k, f64(tp.nturns), two)
            if ie != ok { ret (r, ie) }
            inf[i] = iff
        } else {
            var nmax = 0usize
            var tsum = 0.0f64
            var tlo = 1.0e300f64
            var thi = 0.0f64 - 1.0e300f64
            var isum = 0.0f64
            var ilo = 1.0e300f64
            var ihi = 0.0f64 - 1.0e300f64
            var j = interval
            while j >= 1usize {
                let k = stripmeans(x, j - 1usize, interval, buf)
                let (tp, te) = turnpoints(a, buf[0usize..k])
                if te != ok { ret (r, te) }
                let tn = f64(tp.nturns)
                if k > nmax { nmax = k }
                tsum += tn
                if tn < tlo { tlo = tn }
                if tn > thi { thi = tn }
                let (iff, ie) = info_of(a, k, tn, two)
                if ie != ok { ret (r, ie) }
                isum += iff
                if iff < ilo { ilo = iff }
                if iff > ihi { ihi = iff }
                j -= 1usize
            }
            nv[i] = f64(nmax)
            tv[i] = tsum / f64(interval)
            tmn[i] = tlo
            tmx[i] = thi
            inf[i] = isum / f64(interval)
            imn[i] = ilo
            imx[i] = ihi
        }
        i += 1usize
    }
    var best = 0usize
    i = 1usize
    while i < m {
        if inf[i] > inf[best] { best = i }
        i += 1usize
    }
    r.m = m
    r.interval = iv
    r.n = nv
    r.turns = tv
    r.turns_min = tmn
    r.turns_max = tmx
    r.info = inf
    r.info_min = imn
    r.info_max = imx
    r.level = iv[best]
    ret (r, ok)
}
