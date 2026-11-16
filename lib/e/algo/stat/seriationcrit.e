// R seriation, the criteria that score a permutation of a dissimilarity matrix or a data matrix: path length, lazy
// path length, least squares, inertia, anti-Robinson events and deviations, the gradient measures, banded
// anti-Robinson form, relative generalised anti-Robinson events, the measure of effectiveness and the Moore and von
// Neumann stress. Dissimilarities are a full symmetric n by n row-major matrix d; an order is a permutation of 0..n-1.
//
// Not here: the seriation methods themselves (TSP, GW, OLO, ARSA and the rest), the QAP-based 2SUM and the
// rank-correlation criteria.

use e.math

// the sum of the dissimilarities of consecutive objects (an open path)
fn path_length(d: []const f64, n: usize, o: []const usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i + 1usize < n {
        s += d[o[i] * n + o[i + 1usize]]
        i += 1usize
    }
    ret s
}

// sum (n - i) d(o[i], o[i + 1]) over the open path, i from 1
fn lazy_path_length(d: []const f64, n: usize, o: []const usize) -> f64 {
    var s = 0.0f64
    var i = 1usize
    while i < n {
        s += f64(n - i) * d[o[i - 1usize] * n + o[i]]
        i += 1usize
    }
    ret s
}

// 2 sum_{j < i} (d(o[i], o[j]) - |i - j|)^2
fn least_squares(d: []const f64, n: usize, o: []const usize) -> f64 {
    var s = 0.0f64
    var i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            let x = d[o[i] * n + o[j]] - f64(i - j)
            s += x * x
            j += 1usize
        }
        i += 1usize
    }
    ret 2.0f64 * s
}

// 2 sum_{j < i} d(o[i], o[j]) |i - j|^2
fn inertia(d: []const f64, n: usize, o: []const usize) -> f64 {
    var s = 0.0f64
    var i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            let x = f64(i - j)
            s += d[o[i] * n + o[j]] * x * x
            j += 1usize
        }
        i += 1usize
    }
    ret 2.0f64 * s
}

// anti-Robinson events (which = 1, a count) or their summed absolute deviations (which = 2)
fn anti_robinson(d: []const f64, n: usize, o: []const usize, which: usize) -> f64 {
    var s = 0.0f64
    var i = 2usize
    while i < n {
        var k = 1usize
        while k < i {
            let dik = d[o[i] * n + o[k]]
            var j = 0usize
            while j < k {
                let dij = d[o[i] * n + o[j]]
                if dij < dik {
                    if which == 1usize { s += 1.0f64 } else { s += math.abs[f64](dij - dik) }
                }
                j += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i + 2usize < n {
        var j = i + 1usize
        while j + 1usize < n {
            let dij = d[o[i] * n + o[j]]
            var k = j + 1usize
            while k < n {
                let dik = d[o[i] * n + o[k]]
                if dij > dik {
                    if which == 1usize { s += 1.0f64 } else { s += math.abs[f64](dij - dik) }
                }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// the gradient measure: raw (which = 1, signs) or weighted (which = 2, differences)
fn gradient(d: []const f64, n: usize, o: []const usize, which: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i + 2usize < n {
        var k = i + 1usize
        while k + 1usize < n {
            let dik = d[o[i] * n + o[k]]
            var j = k + 1usize
            while j < n {
                let dij = d[o[i] * n + o[j]]
                let dkj = d[o[k] * n + o[j]]
                let a1 = dij - dik
                let a2 = dij - dkj
                if which > 1usize {
                    s += a1
                    s += a2
                } else {
                    if a1 > 0.0f64 { s += 1.0f64 } else if a1 < 0.0f64 { s -= 1.0f64 }
                    if a2 > 0.0f64 { s += 1.0f64 } else if a2 < 0.0f64 { s -= 1.0f64 }
                }
                j += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    ret s
}

// banded anti-Robinson form: sum over i < j <= i + b of (b + 1 - (j - i)) d
fn bar(d: []const f64, n: usize, o: []const usize, b: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i + 1usize < n {
        var j = i + 1usize
        while j < n && j <= i + b {
            s += f64(b + 1usize - (j - i)) * d[o[i] * n + o[j]]
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// relative (or, when `relative` is false, the count of) generalised anti-Robinson events within a window of w
fn rgar(d: []const f64, n: usize, o: []const usize, w: usize, relative: bool) -> f64 {
    var ar = 0usize
    var total = 0usize
    var i = 3i64
    let ni = i64(n)
    let wi = i64(w)
    while i <= ni {
        var k = i - wi + 1i64
        if k < 2i64 { k = 2i64 }
        while k < i {
            let dik = d[o[usize(i - 1i64)] * n + o[usize(k - 1i64)]]
            var j = i - wi
            if j < 1i64 { j = 1i64 }
            while j < k {
                let dij = d[o[usize(i - 1i64)] * n + o[usize(j - 1i64)]]
                total += 1usize
                if dij < dik { ar += 1usize }
                j += 1i64
            }
            k += 1i64
        }
        i += 1i64
    }
    var ii = 1usize
    while ii + 2usize <= n {
        var jmax = ii + w - 1usize
        if jmax > n - 1usize { jmax = n - 1usize }
        var j = ii + 1usize
        while j <= jmax {
            let dij = d[o[ii - 1usize] * n + o[j - 1usize]]
            var kmax = ii + w
            if kmax > n { kmax = n }
            var k = j + 1usize
            while k <= kmax {
                let dik = d[o[ii - 1usize] * n + o[k - 1usize]]
                total += 1usize
                if dij > dik { ar += 1usize }
                k += 1usize
            }
            j += 1usize
        }
        ii += 1usize
    }
    if relative { ret f64(ar) / f64(total) }
    ret f64(ar)
}

// the measure of effectiveness of the nr by nc nonnegative matrix x (row-major) under the row and column orders
fn measure_of_effectiveness(x: []const f64, nr: usize, nc: usize, ro: []const usize, co: []const usize) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < nr {
        var j = 0usize
        while j < nc {
            let ii = ro[i]
            let jj = co[j]
            var s = 0.0f64
            if i > 0usize { s += x[ro[i - 1usize] * nc + jj] }
            if i + 1usize < nr { s += x[ro[i + 1usize] * nc + jj] }
            if j > 0usize { s += x[ii * nc + co[j - 1usize]] }
            if j + 1usize < nc { s += x[ii * nc + co[j + 1usize]] }
            m += x[ii * nc + jj] * s
            j += 1usize
        }
        i += 1usize
    }
    ret 0.5f64 * m
}

fn sq(v: f64) -> f64 { ret v * v }

// the Moore (neumann = false) or von Neumann stress: twice the sum of squared differences between each cell and its neighbours, each pair counted once
fn stress(x: []const f64, nc0: usize, ro: []const usize, co: []const usize, neumann: bool) -> f64 {
    let nr = ro.len
    let nc = co.len
    var z = 0.0f64
    var l = ro[0usize]
    var i = 0usize
    while i + 1usize < nr {
        let ll = ro[i + 1usize]
        var k = co[0usize]
        var j = 0usize
        while j + 1usize < nc {
            let kk = co[j + 1usize]
            let v = x[l * nc0 + k]
            z += sq(v - x[ll * nc0 + k])
            if !neumann {
                z += sq(v - x[ll * nc0 + kk])
                z += sq(x[ll * nc0 + k] - x[l * nc0 + kk])
            }
            z += sq(v - x[l * nc0 + kk])
            k = kk
            j += 1usize
        }
        z += sq(x[l * nc0 + k] - x[ll * nc0 + k])
        l = ll
        i += 1usize
    }
    var k = co[0usize]
    var j = 0usize
    while j + 1usize < nc {
        let kk = co[j + 1usize]
        z += sq(x[l * nc0 + k] - x[l * nc0 + kk])
        k = kk
        j += 1usize
    }
    ret 2.0f64 * z
}
