// R laeken: the weighted income statistics of the EU-SILC indicators, `weighted_quantile` (with the package's convention that a
// cumulative weight landing exactly on p averages two neighbours), `weighted_median`, `weighted_mean`, the quintile cut points
// (`inc_quintile`), the Gini coefficient (`gini`), the quintile share ratio (`qsr`), the at-risk-of-poverty threshold, rate and relative
// median gap (`arpt`, `arpr`, `rmpg`). Weights default to one by passing a slice of ones; an optional sort key breaks ties in income.
//
// Not here: the Pareto tail fits, the calibration and the linearisation and bootstrap variance estimates.

use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// the order of x (ties broken by sort when given, then by position), as R's order(x) or order(x, sort)
fn order_of(a: *mem.Arena, x: []const f64, sort: []const f64, has_sort: bool) -> ([]usize, err) {
    let n = x.len
    let (idx, e) = mem.alloc[usize](a, n)
    if e != ok { ret (idx, e) }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = idx[i]
        var j = i
        while j > 0usize && before(x, sort, has_sort, v, idx[j - 1usize]) {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = v
        i += 1usize
    }
    ret (idx, ok)
}

// does observation p sort strictly before q
fn before(x: []const f64, sort: []const f64, has_sort: bool, p: usize, q: usize) -> bool {
    if x[p] < x[q] { ret true }
    if x[p] > x[q] { ret false }
    if has_sort {
        if sort[p] < sort[q] { ret true }
        if sort[p] > sort[q] { ret false }
    }
    ret false
}

fn sum_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    ret s
}

// weightedQuantile on data already sorted increasingly
fn quantile_sorted(x: []const f64, w: []const f64, p: f64) -> f64 {
    let n = x.len
    if p == 0.0f64 { ret x[0usize] }
    if p == 1.0f64 { ret x[n - 1usize] }
    let tot = sum_of(w)
    var cum = 0.0f64
    var i = 0usize
    while i < n {
        cum += w[i]
        let rw = cum / tot
        if rw > p {
            if rw == p { ret (x[i] + x[i + 1usize]) / 2.0f64 }
            ret x[i]
        }
        i += 1usize
    }
    ret x[n - 1usize]
}

// weightedQuantile(x, weights, probs): unsorted input
fn weighted_quantile(a: *mem.Arena, x: []const f64, w: []const f64, p: f64) -> f64 {
    let (ord, e) = order_of(a, x, x, false)
    let (xs, e1) = mem.alloc[f64](a, x.len)
    let (ws, e2) = mem.alloc[f64](a, x.len)
    if e != ok || e1 != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < x.len {
        xs[i] = x[ord[i]]
        ws[i] = w[ord[i]]
        i += 1usize
    }
    ret quantile_sorted(xs, ws, p)
}

fn weighted_median(a: *mem.Arena, x: []const f64, w: []const f64) -> f64 { ret weighted_quantile(a, x, w, 0.5f64) }

fn weighted_mean(x: []const f64, w: []const f64) -> f64 {
    var s = 0.0f64
    var t = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] * w[i]
        t += w[i]
        i += 1usize
    }
    ret s / t
}

// incQuintile(inc, weights, sort, k): the quintile cut points k/5 for k = k1 and k2 of the sorted incomes
fn inc_quintile(a: *mem.Arena, x: []const f64, w: []const f64, sort: []const f64, has_sort: bool, k: f64) -> f64 {
    let (ord, e) = order_of(a, x, sort, has_sort)
    let (xs, e1) = mem.alloc[f64](a, x.len)
    let (ws, e2) = mem.alloc[f64](a, x.len)
    if e != ok || e1 != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < x.len {
        xs[i] = x[ord[i]]
        ws[i] = w[ord[i]]
        i += 1usize
    }
    ret quantile_sorted(xs, ws, math.round[f64](k) / 5.0f64)
}

// giniCoeff
fn gini(a: *mem.Arena, x: []const f64, w: []const f64, sort: []const f64, has_sort: bool) -> f64 {
    let n = x.len
    let (ord, e) = order_of(a, x, sort, has_sort)
    if e != ok { ret nan() }
    var sw = 0.0f64
    var swx = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var cw = 0.0f64
    var i = 0usize
    while i < n {
        let xi = x[ord[i]]
        let wi = w[ord[i]]
        cw += wi
        sw += wi
        swx += wi * xi
        s1 += wi * xi * cw
        s2 += wi * wi * xi
        i += 1usize
    }
    ret 100.0f64 * ((2.0f64 * s1 - s2) / (sw * swx) - 1.0f64)
}

// quintileRatio: the income share of the top (above the 4/5 quantile) over that of the bottom (up to the 1/5 quantile)
fn qsr(a: *mem.Arena, x: []const f64, w: []const f64, sort: []const f64, has_sort: bool) -> f64 {
    let q1 = inc_quintile(a, x, w, sort, has_sort, 1.0f64)
    let q4 = inc_quintile(a, x, w, sort, has_sort, 4.0f64)
    var top = 0.0f64
    var bot = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] > q4 { top += w[i] * x[i] }
        if x[i] <= q1 { bot += w[i] * x[i] }
        i += 1usize
    }
    ret top / bot
}

// arpt(inc, weights, p): p times the weighted median income
fn arpt(a: *mem.Arena, x: []const f64, w: []const f64, p: f64) -> f64 { ret p * weighted_median(a, x, w) }

// arpr: the weighted percentage of incomes below the threshold
fn arpr(x: []const f64, w: []const f64, threshold: f64) -> f64 {
    var s = 0.0f64
    var tot = 0.0f64
    var i = 0usize
    while i < x.len {
        tot += w[i]
        if x[i] < threshold { s += w[i] }
        i += 1usize
    }
    ret s * 100.0f64 / tot
}

// rmpg: the relative median at-risk-of-poverty gap, (threshold - weighted median of the poor) / threshold * 100
fn rmpg(a: *mem.Arena, x: []const f64, w: []const f64, threshold: f64) -> f64 {
    var m = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] < threshold { m += 1usize }
        i += 1usize
    }
    let (xp, e1) = mem.alloc[f64](a, m)
    let (wp, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret nan() }
    var k = 0usize
    i = 0usize
    while i < x.len {
        if x[i] < threshold {
            xp[k] = x[i]
            wp[k] = w[i]
            k += 1usize
        }
        i += 1usize
    }
    let med = weighted_median(a, xp, wp)
    ret (threshold - med) * 100.0f64 / threshold
}
