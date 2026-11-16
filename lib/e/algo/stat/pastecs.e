// R pastecs, the closed-form part: `turnpoints` (peaks and pits of a series with runs of equal values collapsed,
// with the probability and information of each turning point under the null of a random series) and `stat_desc`
// (the basic, descriptive and normality-moment statistics of a sample without missing values).
//
// Not here: the Shapiro-Wilk normality test of `stat.desc(norm = TRUE)`, decompose and the tsd family, regul,
// trend.test, the turnogram and the other estimators.

use e.algo.sort
use e.math
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

type Desc = struct { nbr_null: f64, min: f64, max: f64, range: f64, sum: f64, median: f64, mean: f64, se_mean: f64, ci_mean: f64, variance: f64, std_dev: f64, coef_var: f64, skewness: f64, skew_2se: f64, kurtosis: f64, kurt_2se: f64 }

// stat.desc(x, norm = TRUE, p) without the Shapiro-Wilk entries
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
    ret (d, ok)
}
