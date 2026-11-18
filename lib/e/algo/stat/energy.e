// R energy: distance covariance and correlation of two samples of points (V-statistics with doubly centred Euclidean distance matrices,
// optionally raised to a power in (0, 2)) and the two-sample energy statistic of edist and eqdist.etest.
//
// Not here: the permutation tests' p values (they use R's random permutations), the unbiased and partial distance correlations,
// the multivariate normality and Poisson tests, the energy clustering, and the independence coefficients of the other tests.

use e.math
use e.mem

fn dist_pow(x: []const f64, n: usize, d: usize, i: usize, j: usize, index: f64) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < d {
        let v = x[i * d + k] - x[j * d + k]
        s += v * v
        k += 1usize
    }
    let r = math.sqrt[f64](s)
    if index == 1.0f64 { ret r }
    ret math.pow[f64](r, index)
}

// the doubly centred matrix A of the n points of dimension d, n by n row-major
fn centred(a: *mem.Arena, x: []const f64, n: usize, d: usize, index: f64) -> ([]f64, err) {
    let (m, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret (m, e1) }
    let (rm, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (m, e2) }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            let v = dist_pow(x, n, d, i, j, index)
            m[i * n + j] = v
            s += v
            j += 1usize
        }
        rm[i] = s / f64(n)
        total += s
        i += 1usize
    }
    let gm = total / (f64(n) * f64(n))
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            m[i * n + j] = m[i * n + j] - rm[i] - rm[j] + gm
            j += 1usize
        }
        i += 1usize
    }
    ret (m, ok)
}

// (dCov, dCor): the distance covariance (square root of the V-statistic) and the distance correlation
fn dcov_dcor(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, dx: usize, dy: usize, index: f64) -> (f64, f64, err) {
    let (ax, e1) = centred(a, x, n, dx, index)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    let (ay, e2) = centred(a, y, n, dy, index)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < n * n {
        sxy += ax[i] * ay[i]
        sxx += ax[i] * ax[i]
        syy += ay[i] * ay[i]
        i += 1usize
    }
    let nn = f64(n) * f64(n)
    let vxy = sxy / nn
    let vx = sxx / nn
    let vy = syy / nn
    var dcor = 0.0f64
    if vx * vy > 0.0f64 { dcor = math.sqrt[f64](vxy / math.sqrt[f64](vx * vy)) }
    ret (math.sqrt[f64](vxy), dcor, ok)
}

// the two-sample energy statistic of edist and eqdist.etest: n1 n2 / (n1 + n2) times 2 E|X - Y| - E|X - X'| - E|Y - Y'| (V-statistic means)
fn edist_stat(x: []const f64, n1: usize, y: []const f64, n2: usize, d: usize, index: f64) -> f64 {
    var xy = 0.0f64
    var i = 0usize
    while i < n1 {
        var j = 0usize
        while j < n2 {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                let v = x[i * d + k] - y[j * d + k]
                s += v * v
                k += 1usize
            }
            xy += math.pow[f64](math.sqrt[f64](s), index)
            j += 1usize
        }
        i += 1usize
    }
    var xx = 0.0f64
    i = 0usize
    while i < n1 {
        var j = 0usize
        while j < n1 {
            xx += dist_pow(x, n1, d, i, j, index)
            j += 1usize
        }
        i += 1usize
    }
    var yy = 0.0f64
    i = 0usize
    while i < n2 {
        var j = 0usize
        while j < n2 {
            yy += dist_pow(y, n2, d, i, j, index)
            j += 1usize
        }
        i += 1usize
    }
    let e = 2.0f64 * xy / (f64(n1) * f64(n2)) - xx / (f64(n1) * f64(n1)) - yy / (f64(n2) * f64(n2))
    ret e * f64(n1) * f64(n2) / (f64(n1) + f64(n2))
}

// the U-centred Euclidean distance matrix of the n by n row-major D: A_ij = a_ij - row_i / (n - 2) - col_j / (n - 2) + total / ((n - 1)(n - 2)) for i != j,
// zero on the diagonal (Szekely and Rizzo's bias correction)
fn ucentred(a: *mem.Arena, x: []const f64, n: usize, d: usize) -> ([]f64, err) {
    let (m, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret (m, e1) }
    let (rm, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (m, e2) }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            m[i * n + j] = dist_pow(x, n, d, i, j, 1.0f64)
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += m[i * n + j]
            j += 1usize
        }
        rm[i] = s
        total += s
        i += 1usize
    }
    let nf = f64(n)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if i == j {
                m[i * n + j] = 0.0f64
            } else {
                // the column sum of column j is rm[j] (the distances are symmetric)
                m[i * n + j] = m[i * n + j] - rm[i] / (nf - 2.0f64) - rm[j] / (nf - 2.0f64) + total / ((nf - 1.0f64) * (nf - 2.0f64))
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (m, ok)
}

// the unbiased distance covariance of two U-centred matrices: sum A B / (n (n - 3))
fn dcov_u(ua: []const f64, ub: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n * n {
        s += ua[i] * ub[i]
        i += 1usize
    }
    ret s / (f64(n) * (f64(n) - 3.0f64))
}

// energy::bcdcor(x, y): the bias-corrected distance correlation, dcovU(x, y) / sqrt(dcovU(x, x) dcovU(y, y)); x and y are n by dx and n by dy
// row-major
fn bcdcor(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, dx: usize, dy: usize) -> (f64, err) {
    let (ax, e1) = ucentred(a, x, n, dx)
    if e1 != ok { ret (0.0f64, e1) }
    let (ay, e2) = ucentred(a, y, n, dy)
    if e2 != ok { ret (0.0f64, e2) }
    let sxy = dcov_u(ax, ay, n)
    let sxx = dcov_u(ax, ax, n)
    let syy = dcov_u(ay, ay, n)
    ret (sxy / math.sqrt[f64](sxx * syy), ok)
}
