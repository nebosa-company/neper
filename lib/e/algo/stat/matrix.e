// Row and column kernels over column-major matrices, as R's matrixStats computes them: sums,
// means (with the refinement pass), variances and standard deviations, medians, MADs, quantiles
// (type 7), ranks (every ties method but "random"), cumulative sums, lagged differences, order
// statistics, ranges, weighted mean and median, and bin counts. `by_row` picks the margin: true
// computes one answer per row (matrixStats' `row*`), false one per column (`col*`). NA is NaN.
//
// Sums that matrixStats keeps in long double are kept in double-double here (Neumaier's
// compensated sum), so they agree with it to the last bit or one off. `rows` and `cols`
// subsets are `submatrix` first.
//
// Not here: the matrix-of-names output, `rowQuantiles` types other than 7, `rowProds`,
// `rowLogSumExps`, `rowTabulates`, `rowIQRs`, `rowCollapse` and the `var*`/`weighted*` families
// besides the ones named.

use e.math
use e.mem

error Shape
error Missing

type Mat = struct { data: []const f64, nrow: usize, ncol: usize }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_nan(x: f64) -> bool { ret x != x }

fn infinity() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

// The number of answers: rows or columns.
fn count_of(m: Mat, by_row: bool) -> usize {
    if by_row { ret m.nrow }
    ret m.ncol
}

fn length_of(m: Mat, by_row: bool) -> usize {
    if by_row { ret m.ncol }
    ret m.nrow
}

fn at(m: Mat, by_row: bool, i: usize, j: usize) -> f64 {
    if by_row { ret m.data[i + m.nrow * j] }
    ret m.data[j + m.nrow * i]
}

// The values of one row or column, NA removed when `na_rm`; false when an NA is kept in the
// way (not `na_rm`).
fn gather(m: Mat, by_row: bool, i: usize, na_rm: bool, out: []f64) -> (usize, bool) {
    let len = length_of(m, by_row)
    var k = 0usize
    var j = 0usize
    while j < len {
        let v = at(m, by_row, i, j)
        if is_nan(v) {
            if !na_rm { ret (k, false) }
        } else {
            out[k] = v
            k += 1usize
        }
        j += 1usize
    }
    ret (k, true)
}

// Neumaier's sum: the rounded result and the compensation.
type Sum = struct { hi: f64, lo: f64 }

fn sum_add(s: Sum, x: f64) -> Sum {
    let t = s.hi + x
    var c = s.lo
    var ax = x
    if ax < 0.0f64 { ax = 0.0f64 - ax }
    var ah = s.hi
    if ah < 0.0f64 { ah = 0.0f64 - ah }
    if ah >= ax { c = c + ((s.hi - t) + x) } else { c = c + ((x - t) + s.hi) }
    ret Sum { hi: t, lo: c }
}

fn sum_value(s: Sum) -> f64 {
    if s.hi - s.hi != 0.0f64 { ret s.hi }
    ret s.hi + s.lo
}

fn sums(a: *mem.Arena, m: Mat, by_row: bool, na_rm: bool) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, n)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < n {
        var s = Sum { hi: 0.0f64, lo: 0.0f64 }
        var j = 0usize
        var bad = false
        while j < length_of(m, by_row) {
            let v = at(m, by_row, i, j)
            if is_nan(v) {
                if !na_rm { bad = true }
            } else {
                s = sum_add(s, v)
            }
            j += 1usize
        }
        if bad { out[i] = nan() } else { out[i] = sum_value(s) }
        i += 1usize
    }
    ret (out, ok)
}

fn means(a: *mem.Arena, m: Mat, by_row: bool, na_rm: bool, refine: bool) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, n)
    if e != ok { ret (out, e) }
    let len = length_of(m, by_row)
    var i = 0usize
    while i < n {
        var s = Sum { hi: 0.0f64, lo: 0.0f64 }
        var count = 0usize
        var bad = false
        var j = 0usize
        while j < len {
            let v = at(m, by_row, i, j)
            if is_nan(v) {
                if !na_rm { bad = true }
            } else {
                s = sum_add(s, v)
                count += 1usize
            }
            j += 1usize
        }
        if bad {
            out[i] = nan()
        } else {
            var avg = sum_value(s) / f64(count)
            if refine && avg - avg == 0.0f64 {
                var r = Sum { hi: 0.0f64, lo: 0.0f64 }
                j = 0usize
                while j < len {
                    let v = at(m, by_row, i, j)
                    if !is_nan(v) { r = sum_add(r, v - avg) }
                    j += 1usize
                }
                avg = avg + sum_value(r) / f64(count)
            }
            out[i] = avg
        }
        i += 1usize
    }
    ret (out, ok)
}

fn variances(a: *mem.Arena, m: Mat, by_row: bool, na_rm: bool, refine: bool) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, n)
    let (buf, be) = mem.alloc[f64](a, length_of(m, by_row))
    if e != ok { ret (out, e) }
    if be != ok { ret (out, be) }
    var i = 0usize
    while i < n {
        let (kk, ok_row) = gather(m, by_row, i, na_rm, buf)
        if !ok_row || kk <= 1usize {
            out[i] = nan()
        } else {
            var sum = 0.0f64
            var j = 0usize
            while j < kk {
                sum = sum + buf[j]
                j += 1usize
            }
            var mu = sum / f64(kk)
            if refine {
                sum = 0.0f64
                j = 0usize
                while j < kk {
                    sum = sum + (buf[j] - mu)
                    j += 1usize
                }
                mu = mu + sum / f64(kk)
            }
            var sigma2 = 0.0f64
            j = 0usize
            while j < kk {
                var d = buf[j] - mu
                d = d * d
                sigma2 = sigma2 + d
                j += 1usize
            }
            out[i] = sigma2 / f64(kk - 1usize)
        }
        i += 1usize
    }
    ret (out, ok)
}

fn sds(a: *mem.Arena, m: Mat, by_row: bool, na_rm: bool, refine: bool) -> ([]f64, err) {
    let (v, e) = variances(a, m, by_row, na_rm, refine)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < v.len {
        v[i] = math.sqrt[f64](v[i])
        i += 1usize
    }
    ret (v, ok)
}

fn sort_in_place(x: []f64, n: usize) {
    var i = 1usize
    while i < n {
        let v = x[i]
        var j = i
        while j > 0usize && x[j - 1usize] > v {
            x[j] = x[j - 1usize]
            j -= 1usize
        }
        x[j] = v
        i += 1usize
    }
}

fn median_of(x: []f64, n: usize) -> f64 {
    sort_in_place(x, n)
    if n % 2usize == 1usize { ret x[n / 2usize] }
    ret (x[n / 2usize - 1usize] + x[n / 2usize]) / 2.0f64
}

fn medians(a: *mem.Arena, m: Mat, by_row: bool, na_rm: bool) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, n)
    let (buf, be) = mem.alloc[f64](a, length_of(m, by_row))
    if e != ok { ret (out, e) }
    if be != ok { ret (out, be) }
    var i = 0usize
    while i < n {
        let (kk, good) = gather(m, by_row, i, na_rm, buf)
        if !good || kk == 0usize { out[i] = nan() } else { out[i] = median_of(buf, kk) }
        i += 1usize
    }
    ret (out, ok)
}

// rowMads(center = NULL, constant): constant * median(|x - median(x)|).
fn mads(a: *mem.Arena, m: Mat, by_row: bool, na_rm: bool, constant: f64) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, n)
    let (buf, be) = mem.alloc[f64](a, length_of(m, by_row))
    if e != ok { ret (out, e) }
    if be != ok { ret (out, be) }
    var i = 0usize
    while i < n {
        let (kk, good) = gather(m, by_row, i, na_rm, buf)
        if !good || kk == 0usize {
            out[i] = nan()
        } else if kk == 1usize {
            out[i] = 0.0f64
        } else {
            let mu = median_of(buf, kk)
            var j = 0usize
            while j < kk {
                var d = buf[j] - mu
                if d < 0.0f64 { d = 0.0f64 - d }
                buf[j] = d
                j += 1usize
            }
            out[i] = constant * median_of(buf, kk)
        }
        i += 1usize
    }
    ret (out, ok)
}

// quantile type 7 of a sorted vector.
fn quantile7(x: []const f64, n: usize, p: f64) -> f64 {
    let index = 1.0f64 + (f64(n) - 1.0f64) * p
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    let qs = x[usize(lo) - 1usize]
    let xh = x[usize(hi) - 1usize]
    if index > lo && xh != qs {
        let h = index - lo
        ret (1.0f64 - h) * qs + h * xh
    }
    ret qs
}

// rowQuantiles(probs, type = 7): one row of the answer per unit, `probs.len` columns.
fn quantiles(a: *mem.Arena, m: Mat, by_row: bool, na_rm: bool, probs: []const f64) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, n * probs.len)
    let (buf, be) = mem.alloc[f64](a, length_of(m, by_row))
    if e != ok { ret (out, e) }
    if be != ok { ret (out, be) }
    var i = 0usize
    while i < n {
        let (kk, good) = gather(m, by_row, i, na_rm, buf)
        var q = 0usize
        while q < probs.len {
            if !good || kk == 0usize {
                out[i + n * q] = nan()
            } else {
                if q == 0usize { sort_in_place(buf, kk) }
                out[i + n * q] = quantile7(buf, kk, probs[q])
            }
            q += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// ranks(ties): 0 max, 1 average, 2 min, 3 first, 4 last, 5 dense. NA stays NA, the others are
// ranked among themselves.
fn ranks(a: *mem.Arena, m: Mat, by_row: bool, ties: u8) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let len = length_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, n * len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < len {
            let v = at(m, by_row, i, j)
            var rank = nan()
            if !is_nan(v) {
                var less = 0usize
                var equal = 0usize
                var before = 0usize
                var after = 0usize
                var dense = 0usize
                var k = 0usize
                while k < len {
                    let w = at(m, by_row, i, k)
                    if !is_nan(w) {
                        if w < v { less += 1usize }
                        if w == v {
                            equal += 1usize
                            if k < j { before += 1usize }
                            if k > j { after += 1usize }
                        }
                        if w < v {
                            // distinct smaller values, counted once each
                            var first_seen = true
                            var q = 0usize
                            while q < k {
                                if at(m, by_row, i, q) == w { first_seen = false }
                                q += 1usize
                            }
                            if first_seen { dense += 1usize }
                        }
                    }
                    k += 1usize
                }
                if ties == 0u8 { rank = f64(less + equal) }
                if ties == 1u8 { rank = f64(less) + f64(equal + 1usize) / 2.0f64 }
                if ties == 2u8 { rank = f64(less + 1usize) }
                if ties == 3u8 { rank = f64(less + before + 1usize) }
                if ties == 4u8 { rank = f64(less + after + 1usize) }
                if ties == 5u8 { rank = f64(dense + 1usize) }
            }
            out[i + n * j] = rank
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// rowCumsums: the same shape, each unit accumulated along its length; NA stays from there on.
fn cumsums(a: *mem.Arena, m: Mat, by_row: bool) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let len = length_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, n * len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < n {
        var s = Sum { hi: 0.0f64, lo: 0.0f64 }
        var j = 0usize
        var dead = false
        while j < len {
            let v = at(m, by_row, i, j)
            if is_nan(v) { dead = true }
            var r = nan()
            if !dead {
                s = sum_add(s, v)
                r = sum_value(s)
            }
            if by_row { out[i + n * j] = r } else { out[j + len * i] = r }
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// rowDiffs(lag, differences): a matrix of n units by (length - lag * differences) values.
fn diffs(a: *mem.Arena, m: Mat, by_row: bool, lag: usize, differences: usize) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let len = length_of(m, by_row)
    var out_len = 0usize
    if len > lag * differences { out_len = len - lag * differences }
    let (out, e) = mem.alloc[f64](a, n * out_len)
    let (cur, ce) = mem.alloc[f64](a, len)
    if e != ok { ret (out, e) }
    if ce != ok { ret (out, ce) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < len {
            cur[j] = at(m, by_row, i, j)
            j += 1usize
        }
        var width = len
        var d = 0usize
        while d < differences {
            var k = 0usize
            while k + lag < width {
                cur[k] = cur[k + lag] - cur[k]
                k += 1usize
            }
            if width >= lag { width = width - lag } else { width = 0usize }
            d += 1usize
        }
        j = 0usize
        while j < out_len {
            if by_row { out[i + n * j] = cur[j] } else { out[j + out_len * i] = cur[j] }
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// rowOrderStats(which): the `which`-th smallest (1-based) of each unit; no NA allowed.
fn order_stats(a: *mem.Arena, m: Mat, by_row: bool, which: usize) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let len = length_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, n)
    let (buf, be) = mem.alloc[f64](a, len)
    if e != ok { ret (out, e) }
    if be != ok { ret (out, be) }
    if which < 1usize || which > len { ret (out, Shape) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < len {
            let v = at(m, by_row, i, j)
            if is_nan(v) { ret (out, Missing) }
            buf[j] = v
            j += 1usize
        }
        sort_in_place(buf, len)
        out[i] = buf[which - 1usize]
        i += 1usize
    }
    ret (out, ok)
}

// rowRanges: (min, max) per unit, as two vectors back to back.
fn ranges(a: *mem.Arena, m: Mat, by_row: bool, na_rm: bool) -> ([]f64, err) {
    let n = count_of(m, by_row)
    let len = length_of(m, by_row)
    let (out, e) = mem.alloc[f64](a, 2usize * n)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < n {
        var lo = infinity()
        var hi = 0.0f64 - infinity()
        var seen = false
        var bad = false
        var j = 0usize
        while j < len {
            let v = at(m, by_row, i, j)
            if is_nan(v) {
                if !na_rm { bad = true }
            } else {
                seen = true
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
            j += 1usize
        }
        if bad {
            out[i] = nan()
            out[n + i] = nan()
        } else {
            out[i] = lo
            out[n + i] = hi
        }
        i += 1usize
    }
    ret (out, ok)
}

// weightedMean(x, w, na.rm): sum(w x) / sum(w).
fn weighted_mean(x: []const f64, w: []const f64, na_rm: bool) -> f64 {
    var num = Sum { hi: 0.0f64, lo: 0.0f64 }
    var den = Sum { hi: 0.0f64, lo: 0.0f64 }
    var i = 0usize
    while i < x.len {
        var wi = 1.0f64
        if w.len > 0usize { wi = w[i] }
        if is_nan(x[i]) || is_nan(wi) {
            if !na_rm { ret nan() }
        } else {
            num = sum_add(num, wi * x[i])
            den = sum_add(den, wi)
        }
        i += 1usize
    }
    ret sum_value(num) / sum_value(den)
}

// binCounts(x, bx, right): counts of x per bin between consecutive edges, [lo, hi) or (lo, hi]
// throughout; values outside the edges are not counted.
fn bin_counts(a: *mem.Arena, x: []const f64, bx: []const f64, right: bool) -> ([]f64, err) {
    var nbins = 0usize
    if bx.len > 0usize { nbins = bx.len - 1usize }
    let (out, e) = mem.alloc[f64](a, nbins)
    if e != ok { ret (out, e) }
    var b = 0usize
    while b < nbins {
        out[b] = 0.0f64
        b += 1usize
    }
    var i = 0usize
    while i < x.len {
        let v = x[i]
        if !is_nan(v) {
            b = 0usize
            while b < nbins {
                var inside = false
                if right {
                    inside = bx[b] < v && v <= bx[b + 1usize]
                } else {
                    inside = bx[b] <= v && v < bx[b + 1usize]
                }
                if inside {
                    out[b] = out[b] + 1.0f64
                    break
                }
                b += 1usize
            }
        }
        i += 1usize
    }
    ret (out, ok)
}

// weightedMedian(x, w, na.rm, interpolate) with ties = "weighted": matrixStats' algorithm. With
// `interpolate` the cumulative weight is taken at each point's middle and the answer interpolated
// to the level 0.5; without it, the first point past half the weight, and when the weight
// below it is exactly half, the weighted mean of it and its predecessor.
fn weighted_median(a: *mem.Arena, x: []const f64, w: []const f64, na_rm: bool, interpolate: bool) -> f64 {
    let (xs, e1) = mem.alloc[f64](a, x.len)
    let (ws, e2) = mem.alloc[f64](a, x.len)
    if e1 != ok || e2 != ok { ret nan() }
    var n = 0usize
    var total = 0.0f64
    var i = 0usize
    while i < x.len {
        var wi = 1.0f64
        if w.len > 0usize { wi = w[i] }
        if is_nan(wi) || is_nan(x[i]) {
            if !na_rm { ret nan() }
        } else if wi > 0.0f64 {
            xs[n] = x[i]
            ws[n] = wi
            total = total + wi
            n += 1usize
        }
        i += 1usize
    }
    if n == 0usize { ret nan() }
    if n == 1usize { ret xs[0usize] }
    i = 1usize
    while i < n {
        let vx = xs[i]
        let vw = ws[i]
        var j = i
        while j > 0usize && xs[j - 1usize] > vx {
            xs[j] = xs[j - 1usize]
            ws[j] = ws[j - 1usize]
            j -= 1usize
        }
        xs[j] = vx
        ws[j] = vw
        i += 1usize
    }
    let (wcum, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret nan() }
    var half = n + 1usize
    var acc = 0.0f64
    i = 0usize
    while i < n && half == n + 1usize {
        let share = ws[i] / total
        acc = acc + share
        if interpolate {
            wcum[i] = acc - share / 2.0f64
            if wcum[i] >= 0.5f64 { half = i }
        } else {
            wcum[i] = acc
            if acc > 0.5f64 { half = i }
        }
        i += 1usize
    }
    if half == 0usize || half >= n { ret xs[n - 1usize] }
    if interpolate {
        let dx = xs[half] - xs[half - 1usize]
        let big_dy = wcum[half] - wcum[half - 1usize]
        let dy = 0.5f64 - wcum[half]
        ret (dy / big_dy) * dx + xs[half]
    }
    let wlow = wcum[half - 1usize]
    let whigh = 1.0f64 - wlow
    if whigh > 0.5f64 { ret xs[half] }
    ret wlow * xs[half - 1usize] + whigh * xs[half]
}

// A sub-matrix: the given rows and columns (empty selects all), 0-based.
fn submatrix(a: *mem.Arena, m: Mat, rows: []const usize, cols: []const usize) -> (Mat, err) {
    var nr = m.nrow
    if rows.len > 0usize { nr = rows.len }
    var nc = m.ncol
    if cols.len > 0usize { nc = cols.len }
    let (data, e) = mem.alloc[f64](a, nr * nc)
    if e != ok { ret (m, e) }
    var j = 0usize
    while j < nc {
        var cj = j
        if cols.len > 0usize { cj = cols[j] }
        var i = 0usize
        while i < nr {
            var ri = i
            if rows.len > 0usize { ri = rows[i] }
            data[i + nr * j] = m.data[ri + m.nrow * cj]
            i += 1usize
        }
        j += 1usize
    }
    ret (Mat { data: data, nrow: nr, ncol: nc }, ok)
}
