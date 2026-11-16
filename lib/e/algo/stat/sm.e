// R sm: the normal-reference bandwidth hnorm, sm.density in one and two dimensions with the Gaussian kernel, and sm.regression at evaluation points
// (local constant or local linear, Gaussian kernel), all on unbinned data (sm bins only above 100 observations).
//
// Not here: hcv and h.select by cross-validation, bands and standard errors, sm.ancova, sm.survival and sm.options.

use e.math

fn sd_of(x: []const f64) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / f64(x.len)
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(x.len - 1usize))
}

fn phi(z: f64) -> f64 { ret math.exp[f64](0.0f64 - z * z / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64) }

// hnorm for one variable (ndim 1) or per column of a two-variable data set (ndim 2): sd times (4 / (3 n))^(1/5), or n^(-1/6)
fn hnorm(x: []const f64, ndim: usize) -> f64 {
    let n = f64(x.len)
    if ndim == 2usize { ret sd_of(x) * math.pow[f64](1.0f64 / n, 1.0f64 / 6.0f64) }
    ret sd_of(x) * math.pow[f64](4.0f64 / (3.0f64 * n), 0.2f64)
}

// sm.density(x, h) at p
fn density1(x: []const f64, h: f64, p: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += phi((p - x[i]) / h)
        i += 1usize
    }
    ret s / (f64(x.len) * h)
}

// the two-dimensional product-kernel estimate at (p, q)
fn density2(x: []const f64, y: []const f64, h1: f64, h2: f64, p: f64, q: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += phi((p - x[i]) / h1) * phi((q - y[i]) / h2)
        i += 1usize
    }
    ret s / (f64(x.len) * h1 * h2)
}

// sm.regression(x, y, h, poly.index) at p: 0 the kernel-weighted mean, 1 the local-linear intercept
fn regression(x: []const f64, y: []const f64, h: f64, p: f64, poly: usize) -> f64 {
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var t0 = 0.0f64
    var t1 = 0.0f64
    var i = 0usize
    while i < x.len {
        let w = phi((x[i] - p) / h)
        let d = x[i] - p
        s0 += w
        s1 += w * d
        s2 += w * d * d
        t0 += w * y[i]
        t1 += w * d * y[i]
        i += 1usize
    }
    if poly == 0usize { ret t0 / s0 }
    ret (s2 * t0 - s1 * t1) / (s0 * s2 - s1 * s1)
}
