// R VIM::kNN for one numeric variable: each missing value takes the median (or mean) of the k nearest rows that have it, by Gower distance on the other columns (absolute difference over the column range, averaged). Columns are row-major, the other columns complete.
//
// VIM::kNN over mixed columns (knn_impute_mixed): a categorical distance column answers 0 or 1, the
// numeric ones keep the range scaling, the distance is their mean (VIM's weights of one), and a
// categorical target takes the most frequent value among the k donors (VIM's catFun = maxCat).
//
// VIM::kNN over several targets in one call (knn_impute_multi): the columns in `variable` are filled in
// that order, so a later target's distances already see the earlier ones' imputed values.
//
// VIM::hotdeck for numeric columns: a single random row order from runif(n) on the seed, then each
// missing value takes the value of the row before it in that order (stepping back while the donor is
// missing too, wrapping within the data), its columns imputed independently.
//
// Not here: missing values in the distance columns (VIM imputes those first and reuses them), ordered and semi-continuous variables, weights, donor conditions, random-forest distances, the weightDist and addRandom options; for a categorical target, maxCat's random tie-break (ties take the lowest code and no oracle case has one); for hotdeck, domain_var, donorcond, ord_var, impNA = FALSE and the give-up-after-50-steps random donor.

use e.algo.rand.r as rng
use e.math
use e.mem

// one row with a missing value has no donor at all, where VIM stops with "No donor available for ..."
error Invalid

// x is n by p row-major; column v has NaN where missing; the filled column goes into out (n values)
fn knn_impute(a: *mem.Arena, x: []const f64, n: usize, p: usize, v: usize, k: usize, use_mean: bool, out: []f64) -> err {
    let (rg, e1) = mem.alloc[f64](a, p)
    let (dist, e2) = mem.alloc[f64](a, n)
    let (cand, e3) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var c = 0usize
    while c < p {
        var lo = 1.0e300f64
        var hi = 0.0f64 - 1.0e300f64
        var i = 0usize
        while i < n {
            let t = x[i * p + c]
            if t == t {
                if t < lo { lo = t }
                if t > hi { hi = t }
            }
            i += 1usize
        }
        rg[c] = hi - lo
        c += 1usize
    }
    var i = 0usize
    while i < n {
        out[i] = x[i * p + v]
        i += 1usize
    }
    i = 0usize
    while i < n {
        if x[i * p + v] != x[i * p + v] {
            var m = 0usize
            var j = 0usize
            while j < n {
                if x[j * p + v] == x[j * p + v] {
                    var s = 0.0f64
                    c = 0usize
                    while c < p {
                        if c != v { s += math.abs[f64](x[i * p + c] - x[j * p + c]) / rg[c] }
                        c += 1usize
                    }
                    dist[j] = s / f64(p - 1usize)
                    // insertion into cand ordered by (distance, index)
                    var q = m
                    while q > 0usize && dist[cand[q - 1usize]] > dist[j] {
                        cand[q] = cand[q - 1usize]
                        q -= 1usize
                    }
                    cand[q] = j
                    m += 1usize
                }
                j += 1usize
            }
            var kk = k
            if m < kk { kk = m }
            var s = 0.0f64
            if use_mean {
                var q = 0usize
                while q < kk {
                    s += x[cand[q] * p + v]
                    q += 1usize
                }
                out[i] = s / f64(kk)
            } else {
                // the median of the kk donor values
                var q = 0usize
                while q < kk {
                    var r = q
                    while r > 0usize && x[cand[r - 1usize] * p + v] > x[cand[r] * p + v] {
                        let t = cand[r]
                        cand[r] = cand[r - 1usize]
                        cand[r - 1usize] = t
                        r -= 1usize
                    }
                    q += 1usize
                }
                if kk % 2usize == 1usize {
                    out[i] = x[cand[kk / 2usize] * p + v]
                } else {
                    out[i] = (x[cand[kk / 2usize - 1usize] * p + v] + x[cand[kk / 2usize] * p + v]) / 2.0f64
                }
            }
        }
        i += 1usize
    }
    ret ok
}

// One kNN pass over the matrix d, filling the missing cells of column v in place (VIM's per-variable
// step). A numeric column is scaled by its range over the whole table (gowerD pools donors and the rows
// to impute, so every row), a categorical column answers 0 for equal and 1 for different, and the
// distance is the mean over the p - 1 distance columns (VIM's default weights are all one). A missing
// distance value is replaced by the largest prepared value of its column plus one (gowerD's "Maximum + 1
// for missing values"), so two missing entries in a column are at distance 0 from each other. The rows
// missing in column v are fixed at entry, so a value filled earlier in this pass is never a donor. The k
// nearest donors in (distance, row order) order give the median or mean of a numeric target, or the most
// frequent code of a categorical one; a tie among the donor codes takes the lowest code, where VIM's
// maxCat samples (no oracle case has a tie). A column with no observed value is left alone, as VIM
// drops it from `variable`.
fn knn_fill_column(a: *mem.Arena, d: []f64, n: usize, p: usize, v: usize, k: usize, use_mean: bool, is_factor: []const bool) -> err {
    let (prep, e0) = mem.alloc[f64](a, n * p)
    let (dist, e2) = mem.alloc[f64](a, n)
    let (cand, e3) = mem.alloc[usize](a, n)
    let (miss, e4) = mem.alloc[bool](a, n)
    if e0 != ok { ret e0 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var observed = 0usize
    if k == 0usize { ret Invalid }
    var i = 0usize
    while i < n {
        miss[i] = !(d[i * p + v] == d[i * p + v])
        if !miss[i] { observed += 1usize }
        i += 1usize
    }
    if observed == 0usize { ret ok }
    var c = 0usize
    while c < p {
        var lo = 1.0e300f64
        var hi = 0.0f64 - 1.0e300f64
        if !is_factor[c] {
            var i2 = 0usize
            while i2 < n {
                let t = d[i2 * p + c]
                if t == t {
                    if t < lo { lo = t }
                    if t > hi { hi = t }
                }
                i2 += 1usize
            }
        }
        // gowerD divides by the range, and replaces a zero or missing range with 1
        var r = hi - lo
        if is_factor[c] || !(r > 0.0f64) { r = 1.0f64 }
        // the prepared value: the scaled double of a numeric column, the code of a categorical one
        var mx = -1.0e300f64
        var i2 = 0usize
        while i2 < n {
            let t = d[i2 * p + c]
            var prep_v = t
            if !is_factor[c] && t == t { prep_v = t / r }
            prep[i2 * p + c] = prep_v
            if prep_v == prep_v && prep_v > mx { mx = prep_v }
            i2 += 1usize
        }
        // maxplus1: the column's largest prepared value + 1, or 1 for a column with no observed value
        var m1 = mx + 1.0f64
        if !(mx > -1.0e300f64) { m1 = 1.0f64 }
        i2 = 0usize
        while i2 < n {
            if !(prep[i2 * p + c] == prep[i2 * p + c]) { prep[i2 * p + c] = m1 }
            i2 += 1usize
        }
        c += 1usize
    }
    let denom = f64(p - 1usize)
    i = 0usize
    while i < n {
        if miss[i] {
            var m = 0usize
            var j = 0usize
            while j < n {
                if !miss[j] {
                    var s = 0.0f64
                    c = 0usize
                    while c < p {
                        if c != v {
                            if is_factor[c] {
                                if prep[i * p + c] != prep[j * p + c] { s += 1.0f64 }
                            } else {
                                s += math.abs[f64](prep[i * p + c] - prep[j * p + c])
                            }
                        }
                        c += 1usize
                    }
                    dist[j] = s / denom
                    var q = m
                    while q > 0usize && dist[cand[q - 1usize]] > dist[j] {
                        cand[q] = cand[q - 1usize]
                        q -= 1usize
                    }
                    cand[q] = j
                    m += 1usize
                }
                j += 1usize
            }
            var kk = k
            if m < kk { kk = m }
            if is_factor[v] {
                // VIM's maxCat: the most frequent donor code, the lowest code on a tie
                var best = cand[0usize]
                var best_count = 0usize
                var q = 0usize
                while q < kk {
                    var count = 0usize
                    var r2 = 0usize
                    while r2 < kk {
                        if d[cand[r2] * p + v] == d[cand[q] * p + v] { count += 1usize }
                        r2 += 1usize
                    }
                    if count > best_count || (count == best_count && d[cand[q] * p + v] < d[best * p + v]) {
                        best = cand[q]
                        best_count = count
                    }
                    q += 1usize
                }
                d[i * p + v] = d[best * p + v]
            } else if use_mean {
                var s = 0.0f64
                var q = 0usize
                while q < kk {
                    s += d[cand[q] * p + v]
                    q += 1usize
                }
                d[i * p + v] = s / f64(kk)
            } else {
                // the median of the kk donor values
                var q = 0usize
                while q < kk {
                    var r2 = q
                    while r2 > 0usize && d[cand[r2 - 1usize] * p + v] > d[cand[r2] * p + v] {
                        let t = cand[r2]
                        cand[r2] = cand[r2 - 1usize]
                        cand[r2 - 1usize] = t
                        r2 -= 1usize
                    }
                    q += 1usize
                }
                if kk % 2usize == 1usize {
                    d[i * p + v] = d[cand[kk / 2usize] * p + v]
                } else {
                    d[i * p + v] = (d[cand[kk / 2usize - 1usize] * p + v] + d[cand[kk / 2usize] * p + v]) / 2.0f64
                }
            }
        }
        i += 1usize
    }
    ret ok
}

// VIM::kNN over mixed numeric and categorical distance columns, one target variable: see knn_fill_column
// for the distance and aggregation rules.
fn knn_impute_mixed(a: *mem.Arena, x: []const f64, n: usize, p: usize, v: usize, k: usize, use_mean: bool, is_factor: []const bool, out: []f64) -> err {
    let (work, e1) = mem.alloc[f64](a, n * p)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n * p {
        work[i] = x[i]
        i += 1usize
    }
    let e = knn_fill_column(a, work, n, p, v, k, use_mean, is_factor)
    if e != ok { ret e }
    i = 0usize
    while i < n {
        out[i] = work[i * p + v]
        i += 1usize
    }
    ret ok
}

// VIM::kNN over several target variables in one call: out (n by p) starts as x, and each column in vars
// is filled in order, so a later target's distances already see the values filled for the earlier ones
// (VIM's useImputedDist = TRUE, its default, with columns ordered as `variable` orders them).
fn knn_impute_multi(a: *mem.Arena, x: []const f64, n: usize, p: usize, vars: []const usize, k: usize, use_mean: bool, is_factor: []const bool, out: []f64) -> err {
    if x.len < n * p || out.len < n * p { ret mem.Full }
    var i = 0usize
    while i < n * p {
        out[i] = x[i]
        i += 1usize
    }
    var t = 0usize
    while t < vars.len {
        let e = knn_fill_column(a, out, n, p, vars[t], k, use_mean, is_factor)
        if e != ok { ret e }
        t += 1usize
    }
    ret ok
}

// VIM::hotdeck over every column (variable = NULL, ord_var = NULL, domain_var = NULL, imp_var = FALSE):
// x is n by p row-major with NaN where missing and out receives the filled matrix. The rows are put in
// ascending order of runif(n) from seed (VIM's RandomVariableForImputationWithHotdeck), and a missing
// value takes the value of the row immediately before it in that order; when that row's value is
// missing too the search steps further back, wrapping to the far end, and gives up only past
// min(50, n) steps. Each column is imputed independently on the same shared order, because VIM imputes
// every variable from the same sorted data.
fn hotdeck(a: *mem.Arena, x: []const f64, n: usize, p: usize, seed: i64, out: []f64) -> err {
    if x.len < n * p || out.len < n * p { ret mem.Full }
    let (order, e1) = mem.alloc[usize](a, n)
    let (u, e2) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    var i = 0usize
    while i < n {
        u[i] = rng.runif(&g, 0.0f64, 1.0f64)
        order[i] = i
        i += 1usize
    }
    // stable ascending sort of the row indices by their random value (R's order over the runif column)
    i = 1usize
    while i < n {
        let oi = order[i]
        var q = i
        while q > 0usize && u[order[q - 1usize]] > u[oi] {
            order[q] = order[q - 1usize]
            q -= 1usize
        }
        order[q] = oi
        i += 1usize
    }
    i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            out[i * p + c] = x[i * p + c]
            c += 1usize
        }
        i += 1usize
    }
    var limit = 50usize
    if n < limit { limit = n }
    var at = 0usize
    while at < n {
        let row = order[at]
        var c = 0usize
        while c < p {
            // VIM decides applicability once, from the original data, so a value imputed earlier in
            // this pass is never a donor; step back in 1-based positions, wrapping once, as imputeHD does
            if x[row * p + c] != x[row * p + c] {
                if n < 2usize { ret Invalid }
                let posn = i64(at + 1usize)
                var donor = posn - 1i64
                if donor < 1i64 { donor = posn + 1i64 }
                var found = false
                if donor >= 1i64 && donor <= i64(n) {
                    let d = order[usize(donor - 1i64)]
                    if x[d * p + c] == x[d * p + c] { found = true }
                }
                var add = 2usize
                while !found && add <= limit {
                    donor = posn - i64(add)
                    if donor < 1i64 { donor += i64(n) }
                    if donor >= 1i64 && donor <= i64(n) {
                        let d = order[usize(donor - 1i64)]
                        if x[d * p + c] == x[d * p + c] { found = true }
                    }
                    add += 1usize
                }
                if found { out[row * p + c] = x[order[usize(donor - 1i64)] * p + c] }
            }
            c += 1usize
        }
        at += 1usize
    }
    ret ok
}
