// R ks: the normal-scale bandwidths hns and Hns (derivative order r) and kde at evaluation points with a given bandwidth matrix H, the Gaussian kernel, unbinned.
//
// Not here: the plug-in, smoothed cross-validation and least-squares bandwidths (hpi, Hpi, hscv, hlscv and their matrix forms), binned estimation, kde regions and the rest of the package.

use e.algo.stat.carlmtest as ols
use e.algo.stat.vars as vr
use e.math
use e.mem

fn mean_col(x: []const f64, n: usize, d: usize, j: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[i * d + j]
        i += 1usize
    }
    ret s / f64(n)
}

// the sample covariance of the n by d row-major x into out (d by d)
fn covariance(x: []const f64, n: usize, d: usize, out: []f64) {
    var a = 0usize
    while a < d {
        let ma = mean_col(x, n, d, a)
        var b = 0usize
        while b < d {
            let mb = mean_col(x, n, d, b)
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (x[i * d + a] - ma) * (x[i * d + b] - mb)
                i += 1usize
            }
            out[a * d + b] = s / f64(n - 1usize)
            b += 1usize
        }
        a += 1usize
    }
}

// hns(x, deriv.order = r) for one variable
fn hns(x: []const f64, r: usize) -> f64 {
    let n = f64(x.len)
    var cov: [1]f64 = zero
    covariance(x, x.len, 1usize, cov[0usize..1usize])
    ret math.pow[f64](4.0f64 / (n * (3.0f64 + 2.0f64 * f64(r))), 1.0f64 / (5.0f64 + 2.0f64 * f64(r))) * math.sqrt[f64](cov[0usize])
}

// Hns(x, deriv.order = r) for n by d data into out (d by d)
fn hns_matrix(x: []const f64, n: usize, d: usize, r: usize, out: []f64) {
    covariance(x, n, d, out)
    let df = f64(d)
    let c = math.pow[f64](4.0f64 / (f64(n) * (df + 2.0f64 * f64(r) + 2.0f64)), 2.0f64 / (df + 2.0f64 * f64(r) + 4.0f64))
    var i = 0usize
    while i < d * d {
        out[i] = out[i] * c
        i += 1usize
    }
}

// kde(x, H, eval.points = p, binned = FALSE)$estimate at one point: the mean of N(x_i, H) densities
fn kde_at(a: *mem.Arena, x: []const f64, n: usize, d: usize, h: []const f64, p: []const f64) -> f64 {
    let (hi, e1) = mem.alloc[f64](a, d * d)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    if ols.inverse(a, h, d, hi) != ok { ret 0.0f64 / 0.0f64 }
    let (sc, e2) = mem.alloc[f64](a, d * d)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let det = vr.det_of(h, d, sc)
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var q = 0.0f64
        var u = 0usize
        while u < d {
            var v = 0usize
            while v < d {
                q += (p[u] - x[i * d + u]) * hi[u * d + v] * (p[v] - x[i * d + v])
                v += 1usize
            }
            u += 1usize
        }
        s += math.exp[f64](0.0f64 - 0.5f64 * q)
        i += 1usize
    }
    ret s / f64(n) / (math.pow[f64](2.0f64 * 3.141592653589793238462643383279f64, f64(d) / 2.0f64) * math.sqrt[f64](det))
}
