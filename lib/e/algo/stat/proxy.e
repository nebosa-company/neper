// The measures of R's proxy for two vectors, each as proxy computes it natively: a similarity for the
// binary and the angular families, a distance for the metric ones (proxy::simil and proxy::dist convert
// the other way with 1 - s or its own rule). Binary measures read a value as present when it is not 0
// and use the counts a (both), b (x only), c (y only), d (neither). Quirks of the R code are kept: the
// Wave-Hedges and Soergel measures take min and max of the whole pair of vectors, not per element.
//
// proxy::dist(m) passes the later row first, so an asymmetric measure (Fager, Kullback-Leibler) takes
// (row 2, row 1): the caller of a matrix pair does the same.
//
// Also here: the nominal family (nominal) and the Mahalanobis distance for a given covariance.
//
// Not here: Gower, Levenshtein and the matrix interface (the caller loops over pairs).

use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn sqrt_of(x: f64) -> f64 { ret math.sqrt[f64](x) }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn dot(x: []const f64, y: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] * y[i]
        i += 1usize
    }
    ret s
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

fn min2(x: []const f64, y: []const f64) -> f64 {
    var m = x[0usize]
    var i = 0usize
    while i < x.len {
        if x[i] < m { m = x[i] }
        if y[i] < m { m = y[i] }
        i += 1usize
    }
    ret m
}

fn max2(x: []const f64, y: []const f64) -> f64 {
    var m = x[0usize]
    var i = 0usize
    while i < x.len {
        if x[i] > m { m = x[i] }
        if y[i] > m { m = y[i] }
        i += 1usize
    }
    ret m
}

// binary measures: id 0 Jaccard, 1 Kulczynski1, 2 Kulczynski2, 3 Mountford, 4 Fager, 5 Russel, 6 simple
// matching, 7 Hamman, 8 Faith, 9 Tanimoto, 10 Dice, 11 Phi, 12 Stiles, 13 Michael, 14 Mozley, 15 Yule,
// 16 Yule2, 17 Ochiai, 18 Simpson, 19 Braun-Blanquet
fn binary_measure(id: u8, x: []const f64, y: []const f64) -> f64 {
    var a = 0.0f64
    var b = 0.0f64
    var c = 0.0f64
    var d = 0.0f64
    var i = 0usize
    while i < x.len {
        let px = x[i] != 0.0f64
        let py = y[i] != 0.0f64
        if px && py { a += 1.0f64 } else if px { b += 1.0f64 } else if py { c += 1.0f64 } else { d += 1.0f64 }
        i += 1usize
    }
    let n = a + b + c + d
    if id == 0u8 {
        if a + b + c == 0.0f64 { ret 1.0f64 }
        ret a / (a + b + c)
    }
    if id == 1u8 { ret a / (b + c) }
    if id == 2u8 { ret (a / (a + b) + a / (a + c)) / 2.0f64 }
    if id == 3u8 { ret 2.0f64 * a / (a * (b + c) + 2.0f64 * b * c) }
    if id == 4u8 { ret a / (sqrt_of(a + b) * sqrt_of(a + c)) - sqrt_of(a + c) / 2.0f64 }
    if id == 5u8 { ret a / n }
    if id == 6u8 { ret (a + d) / n }
    if id == 7u8 { ret (a + d - b - c) / n }
    if id == 8u8 { ret (a + d / 2.0f64) / n }
    if id == 9u8 { ret (a + d) / (a + 2.0f64 * (b + c) + d) }
    if id == 10u8 { ret 2.0f64 * a / (2.0f64 * a + b + c) }
    if id == 11u8 { ret (a * d - b * c) / (sqrt_of(a + b) * sqrt_of(c + d) * sqrt_of(a + c) * sqrt_of(b + d)) }
    if id == 12u8 {
        ret math.log[f64](n) + 2.0f64 * math.log[f64](abs_of(a * d - b * c) - 0.5f64 * n) - math.log[f64](a + b) - math.log[f64](c + d) - math.log[f64](a + c) - math.log[f64](b + d)
    }
    if id == 13u8 { ret 4.0f64 * (a * d - b * c) / ((a + d) * (a + d) + (b + c) * (b + c)) }
    if id == 14u8 { ret a * n / ((a + b) * (a + c)) }
    if id == 15u8 { ret (a * d - b * c) / (a * d + b * c) }
    if id == 16u8 { ret (sqrt_of(a * d) - sqrt_of(b * c)) / (sqrt_of(a * d) + sqrt_of(b * c)) }
    if id == 17u8 { ret a / sqrt_of((a + b) * (a + c)) }
    if id == 18u8 {
        var m = a + b
        if a + c < m { m = a + c }
        ret a / m
    }
    var m = a + b
    if a + c > m { m = a + c }
    ret a / m
}

fn podani(x: []const f64, y: []const f64) -> f64 {
    let n = x.len
    var a = 0.0f64
    var b = 0.0f64
    var c = 0.0f64
    var d = 0.0f64
    var i = 0usize
    while i + 1usize < n {
        var j = i + 1usize
        while j < n {
            if (x[i] < x[j] && y[i] < y[j]) || (x[i] > x[j] && y[i] > y[j]) { a += 1.0f64 }
            if (x[i] < x[j] && y[i] > y[j]) || (x[i] > x[j] && y[i] < y[j]) { b += 1.0f64 }
            if x[i] == x[j] && y[i] == y[j] && ((x[i] == 0.0f64 && y[i] == 0.0f64) || (x[i] > 0.0f64 && y[i] > 0.0f64)) { c += 1.0f64 }
            var z = 0i64
            if x[i] == 0.0f64 { z += 1i64 }
            if x[j] == 0.0f64 { z += 1i64 }
            if y[i] == 0.0f64 { z += 1i64 }
            if y[j] == 0.0f64 { z += 1i64 }
            if (x[i] == x[j] || y[i] == y[j]) && z > 0i64 && z < 4i64 { d += 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    let nf = f64(n)
    ret 1.0f64 - 2.0f64 * (a - b + c - d) / (nf * (nf - 1.0f64))
}

// numeric measures: id 20 cosine, 21 angular, 22 eJaccard, 23 eDice, 24 correlation, 25 Euclidean,
// 26 Bhattacharyya, 27 Manhattan, 28 supremum, 29 Minkowski (power p), 30 Canberra, 31 Wave-Hedges,
// 32 divergence, 33 Kullback-Leibler, 34 Bray-Curtis, 35 Soergel, 36 Podani, 37 Chord, 38 Geodesic,
// 39 Whittaker, 40 Hellinger, 41 fuzzy Jaccard
fn measure(id: u8, x: []const f64, y: []const f64, p: f64) -> f64 {
    if id < 20u8 { ret binary_measure(id, x, y) }
    let n = x.len
    let xy = dot(x, y)
    let xx = dot(x, x)
    let yy = dot(y, y)
    if id == 20u8 { ret xy / sqrt_of(xx * yy) }
    if id == 21u8 { ret 1.0f64 - math.acos[f64](xy / sqrt_of(xx * yy)) / 3.141592653589793f64 }
    if id == 22u8 { ret xy / (xx + yy - xy) }
    if id == 23u8 { ret 2.0f64 * xy / (xx + yy) }
    if id == 24u8 {
        let mx = sum_of(x) / f64(n)
        let my = sum_of(y) / f64(n)
        var sxy = 0.0f64
        var sxx = 0.0f64
        var syy = 0.0f64
        var i = 0usize
        while i < n {
            sxy += (x[i] - mx) * (y[i] - my)
            sxx += (x[i] - mx) * (x[i] - mx)
            syy += (y[i] - my) * (y[i] - my)
            i += 1usize
        }
        ret sxy / sqrt_of(sxx * syy)
    }
    if id == 36u8 { ret podani(x, y) }
    if id == 37u8 { ret sqrt_of(2.0f64 * (1.0f64 - xy / sqrt_of(xx * yy))) }
    if id == 38u8 { ret math.acos[f64](xy / sqrt_of(xx * yy)) }
    let sx = sum_of(x)
    let sy = sum_of(y)
    var s = 0.0f64
    var smin = 0.0f64
    var smax = 0.0f64
    var used = 0usize
    var i = 0usize
    while i < n {
        let dv = x[i] - y[i]
        if id == 25u8 { s += dv * dv }
        if id == 26u8 {
            let t = sqrt_of(x[i]) - sqrt_of(y[i])
            s += t * t
        }
        if id == 27u8 { s += abs_of(dv) }
        if id == 28u8 && abs_of(dv) > s { s = abs_of(dv) }
        if id == 29u8 { s += math.pow[f64](abs_of(dv), p) }
        if id == 30u8 {
            let sm = abs_of(x[i] + y[i])
            let df = abs_of(dv)
            if sm > 2.2250738585072014e-308f64 || df > 2.2250738585072014e-308f64 {
                s += df / sm
                used += 1usize
            }
        }
        if id == 32u8 {
            let t = dv * dv / ((x[i] + y[i]) * (x[i] + y[i]))
            if t == t { s += t }
        }
        if id == 33u8 {
            let pp = x[i] / sx
            let qq = y[i] / sy
            s += pp * math.log[f64](pp / qq)
        }
        if id == 34u8 { s += abs_of(dv) }
        if id == 35u8 { s += abs_of(dv) }
        if id == 39u8 { s += abs_of(x[i] / sx - y[i] / sy) }
        if id == 40u8 {
            let t = sqrt_of(x[i] / sx) - sqrt_of(y[i] / sy)
            s += t * t
        }
        if id == 41u8 {
            if x[i] > y[i] {
                smax += x[i]
                smin += y[i]
            } else {
                smax += y[i]
                smin += x[i]
            }
        }
        i += 1usize
    }
    if id == 25u8 || id == 26u8 || id == 40u8 { ret sqrt_of(s) }
    if id == 29u8 { ret math.pow[f64](s, 1.0f64 / p) }
    if id == 30u8 && used != n { ret s / (f64(used) / f64(n)) }
    if id == 31u8 { ret 1.0f64 - min2(x, y) / max2(x, y) }
    if id == 34u8 { ret s / (sx + sy) }
    if id == 35u8 { ret s / max2(x, y) }
    if id == 39u8 { ret s / 2.0f64 }
    if id == 41u8 {
        let r = smin / smax
        if r != r { ret 0.0f64 }
        ret 1.0f64 - r
    }
    ret s
}

// --- nominal measures on two categorical vectors (values are integer codes), from their contingency table

// id 0 Chi-squared, 1 Phi-squared, 2 Tschuprow, 3 Cramer, 4 Pearson contingency coefficient
fn nominal(a: *mem.Arena, id: u8, x: []const f64, y: []const f64) -> (f64, err) {
    let n = x.len
    // the distinct values of each, ascending
    var xs: [64]f64 = zero
    var ys: [64]f64 = zero
    var nx = 0usize
    var ny = 0usize
    var i = 0usize
    while i < n {
        var j = 0usize
        var found = false
        while j < nx {
            if xs[j] == x[i] { found = true }
            j += 1usize
        }
        if !found {
            xs[nx] = x[i]
            nx += 1usize
        }
        j = 0usize
        found = false
        while j < ny {
            if ys[j] == y[i] { found = true }
            j += 1usize
        }
        if !found {
            ys[ny] = y[i]
            ny += 1usize
        }
        i += 1usize
    }
    let (tab, te) = mem.alloc[f64](a, nx * ny)
    if te != ok { ret (0.0f64, te) }
    i = 0usize
    while i < nx * ny {
        tab[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var r = 0usize
        while xs[r] != x[i] { r += 1usize }
        var c = 0usize
        while ys[c] != y[i] { c += 1usize }
        tab[r * ny + c] += 1.0f64
        i += 1usize
    }
    let (rs, re) = mem.alloc[f64](a, nx)
    let (cs, ce) = mem.alloc[f64](a, ny)
    if re != ok { ret (0.0f64, re) }
    if ce != ok { ret (0.0f64, ce) }
    var tot = 0.0f64
    var r = 0usize
    while r < nx {
        rs[r] = 0.0f64
        r += 1usize
    }
    var c = 0usize
    while c < ny {
        cs[c] = 0.0f64
        c += 1usize
    }
    r = 0usize
    while r < nx {
        c = 0usize
        while c < ny {
            rs[r] += tab[r * ny + c]
            cs[c] += tab[r * ny + c]
            tot += tab[r * ny + c]
            c += 1usize
        }
        r += 1usize
    }
    var chi = 0.0f64
    r = 0usize
    while r < nx {
        c = 0usize
        while c < ny {
            let ex = rs[r] * cs[c] / tot
            chi += (tab[r * ny + c] - ex) * (tab[r * ny + c] - ex) / ex
            c += 1usize
        }
        r += 1usize
    }
    if id == 0u8 { ret (chi, ok) }
    if id == 1u8 { ret (chi / tot, ok) }
    let p1 = f64(nx) - 1.0f64
    let q1 = f64(ny) - 1.0f64
    if id == 2u8 { ret (math.sqrt[f64](chi / tot / math.sqrt[f64](p1 * q1)), ok) }
    if id == 3u8 {
        var mn = p1
        if q1 < mn { mn = q1 }
        ret (math.sqrt[f64](chi / tot / mn), ok)
    }
    ret (math.sqrt[f64](chi / (tot + chi)), ok)
}

// Mahalanobis distance sqrt((x - y)' S^-1 (x - y)) for a given p x p covariance S (row-major), by Cholesky
fn mahalanobis(a: *mem.Arena, x: []const f64, y: []const f64, cov: []const f64) -> (f64, err) {
    let p = x.len
    let (l, le) = mem.alloc[f64](a, p * p)
    if le != ok { ret (0.0f64, le) }
    var i = 0usize
    while i < p * p {
        l[i] = 0.0f64
        i += 1usize
    }
    var r = 0usize
    while r < p {
        var c = 0usize
        while c <= r {
            var s = cov[r * p + c]
            var k = 0usize
            while k < c {
                s -= l[r * p + k] * l[c * p + k]
                k += 1usize
            }
            if r == c { l[r * p + c] = math.sqrt[f64](s) } else { l[r * p + c] = s / l[c * p + c] }
            c += 1usize
        }
        r += 1usize
    }
    // solve L z = x - y, answer |z|
    var z: [64]f64 = zero
    var q = 0.0f64
    r = 0usize
    while r < p {
        var s = x[r] - y[r]
        var k = 0usize
        while k < r {
            s -= l[r * p + k] * z[k]
            k += 1usize
        }
        z[r] = s / l[r * p + r]
        q += z[r] * z[r]
        r += 1usize
    }
    ret (math.sqrt[f64](q), ok)
}

// Gower distance of two rows over the columns both observed: the mean of |x - y| / range, the ranges taken per column
// over the whole data (NaN is missing); `ranges[k]` is max - min of column k
fn gower(x: []const f64, y: []const f64, ranges: []const f64) -> f64 {
    var s = 0.0f64
    var cnt = 0.0f64
    var k = 0usize
    while k < x.len {
        if x[k] == x[k] && y[k] == y[k] {
            s += abs_of(x[k] - y[k]) / ranges[k]
            cnt += 1.0f64
        }
        k += 1usize
    }
    ret s / cnt
}

// Levenshtein distance as cba::sdists computes it for proxy: insertions and deletions cost 1 and a substitution
// costs 2, so it is |a| + |b| - 2 * (the longest common subsequence)
fn levenshtein(a: *mem.Arena, s: []const u8, t: []const u8) -> (f64, err) {
    let n = s.len
    let m = t.len
    let (prev, e1) = mem.alloc[usize](a, m + 1usize)
    let (cur, e2) = mem.alloc[usize](a, m + 1usize)
    if e1 != ok || e2 != ok { ret (0.0f64, e1) }
    var j = 0usize
    while j <= m {
        prev[j] = 0usize
        j += 1usize
    }
    var i = 1usize
    while i <= n {
        cur[0usize] = 0usize
        j = 1usize
        while j <= m {
            if s[i - 1usize] == t[j - 1usize] {
                cur[j] = prev[j - 1usize] + 1usize
            } else if prev[j] >= cur[j - 1usize] {
                cur[j] = prev[j]
            } else {
                cur[j] = cur[j - 1usize]
            }
            j += 1usize
        }
        j = 0usize
        while j <= m {
            prev[j] = cur[j]
            j += 1usize
        }
        i += 1usize
    }
    ret (f64(n + m) - 2.0f64 * f64(prev[m]), ok)
}
