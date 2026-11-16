// R corpcor for unweighted data (w = 1 / n): the shrinkage intensities `lambda_cor` (estimate.lambda) and
// `lambda_var` (estimate.lambda.var), `var_shrink`, `cor_shrink` and `cov_shrink` (the tgt is the
// identity for correlations and the median for variances), and `pseudoinverse` by the SVD.
//
// Not here: sample weights, power shrinkage with alpha other than 1, pcor.shrink and the pcaPP functions.

use e.algo.linalg.decomp as decomp
use e.algo.sort
use e.math
use e.mem

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn median_of(a: *mem.Arena, v: []const f64) -> f64 {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    let n = v.len
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

// the centred data and the per-column variance (divisor n - 1)
fn centre(a: *mem.Arena, x: []const f64, n: usize, p: usize) -> ([]f64, []f64, err) {
    var none: []f64 = zero
    let (xc, e1) = mem.alloc[f64](a, n * p)
    if e1 != ok { ret (none, none, e1) }
    let (v, e2) = mem.alloc[f64](a, p)
    if e2 != ok { ret (none, none, e2) }
    var j = 0usize
    while j < p {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += x[i * p + j]
            i += 1usize
        }
        m = m / f64(n)
        var s = 0.0f64
        i = 0usize
        while i < n {
            xc[i * p + j] = x[i * p + j] - m
            s += xc[i * p + j] * xc[i * p + j]
            i += 1usize
        }
        v[j] = s / f64(n - 1usize)
        j += 1usize
    }
    ret (xc, v, ok)
}

// estimate.lambda.var
fn lambda_var(a: *mem.Arena, x: []const f64, n: usize, p: usize) -> (f64, err) {
    let (xc, v, e) = centre(a, x, n, p)
    if e != ok { ret (0.0f64, e) }
    let nf = f64(n)
    let w = 1.0f64 / nf
    let w2 = w * w * nf
    let h1 = 1.0f64 / (1.0f64 - w2)
    let h1w2 = w2 / (1.0f64 - w2)
    let (vv, e2) = mem.alloc[f64](a, p)
    if e2 != ok { ret (0.0f64, e2) }
    var j = 0usize
    while j < p {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += w * xc[i * p + j] * xc[i * p + j]
            i += 1usize
        }
        vv[j] = h1 * s
        j += 1usize
    }
    let tgt = median_of(a, vv)
    var numerator = 0.0f64
    var denominator = 0.0f64
    j = 0usize
    while j < p {
        var q1 = 0.0f64
        var q4 = 0.0f64
        var i = 0usize
        while i < n {
            let z = xc[i * p + j] * xc[i * p + j]
            q1 += w * z
            q4 += w * z * z
            i += 1usize
        }
        numerator += q4 - q1 * q1
        denominator += (q1 - tgt / h1) * (q1 - tgt / h1)
        j += 1usize
    }
    if denominator == 0.0f64 { ret (1.0f64, ok) }
    var l = numerator / denominator * h1w2
    if l > 1.0f64 { l = 1.0f64 }
    if l < 0.0f64 { l = 0.0f64 }
    ret (l, ok)
}

// the standardised data (centred, divided by the sample standard deviation)
fn standardise(a: *mem.Arena, x: []const f64, n: usize, p: usize) -> ([]f64, err) {
    let (xc, v, e) = centre(a, x, n, p)
    if e != ok { ret (xc, e) }
    var j = 0usize
    while j < p {
        let sd = math.sqrt[f64](v[j])
        var i = 0usize
        while i < n {
            if sd == 0.0f64 { xc[i * p + j] = 0.0f64 } else { xc[i * p + j] = xc[i * p + j] / sd }
            i += 1usize
        }
        j += 1usize
    }
    ret (xc, ok)
}

// estimate.lambda for the correlation matrix
fn lambda_cor(a: *mem.Arena, x: []const f64, n: usize, p: usize) -> (f64, err) {
    if p == 1usize { ret (1.0f64, ok) }
    let (xs, e) = standardise(a, x, n, p)
    if e != ok { ret (0.0f64, e) }
    let nf = f64(n)
    let w = 1.0f64 / nf
    let w2 = w * w * nf
    let h1w2 = w2 / (1.0f64 - w2)
    // xsw = xs * sqrt(w); sE2R = sum(xsw * (xsw (xsw' xsw))) - sum(colSums(xsw^2)^2)
    let sw = math.sqrt[f64](w)
    let (g, ge) = mem.alloc[f64](a, p * p)
    if ge != ok { ret (0.0f64, ge) }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var r = 0usize
            while r < n {
                s += xs[r * p + i] * sw * xs[r * p + j] * sw
                r += 1usize
            }
            g[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    var se2r = 0.0f64
    var r = 0usize
    while r < n {
        var c = 0usize
        while c < p {
            var t = 0.0f64
            var k = 0usize
            while k < p {
                t += xs[r * p + k] * sw * g[k * p + c]
                k += 1usize
            }
            se2r += xs[r * p + c] * sw * t
            c += 1usize
        }
        r += 1usize
    }
    var cs2 = 0.0f64
    var c = 0usize
    while c < p {
        var s = 0.0f64
        r = 0usize
        while r < n {
            s += xs[r * p + c] * sw * xs[r * p + c] * sw
            r += 1usize
        }
        cs2 += s * s
        c += 1usize
    }
    se2r = se2r - cs2
    var ser2 = 0.0f64
    r = 0usize
    while r < n {
        var a1 = 0usize
        while a1 < p {
            var b1 = a1 + 1usize
            while b1 < p {
                ser2 += 2.0f64 * (xs[r * p + a1] * xs[r * p + a1] * sw) * (xs[r * p + b1] * xs[r * p + b1] * sw)
                b1 += 1usize
            }
            a1 += 1usize
        }
        r += 1usize
    }
    if se2r == 0.0f64 { ret (1.0f64, ok) }
    var l = (ser2 - se2r) / se2r * h1w2
    if l > 1.0f64 { l = 1.0f64 }
    if l < 0.0f64 { l = 0.0f64 }
    ret (l, ok)
}

// var.shrink: the shrunk variances; lambda < 0 asks for the estimate
fn var_shrink(a: *mem.Arena, x: []const f64, n: usize, p: usize, lam: f64) -> ([]f64, f64, err) {
    var none: []f64 = zero
    var l = lam
    if l < 0.0f64 {
        let (le, e) = lambda_var(a, x, n, p)
        if e != ok { ret (none, 0.0f64, e) }
        l = le
    }
    if l > 1.0f64 { l = 1.0f64 }
    let (xc, v, e2) = centre(a, x, n, p)
    if e2 != ok { ret (none, 0.0f64, e2) }
    let tgt = median_of(a, v)
    let (vs, e3) = mem.alloc[f64](a, p)
    if e3 != ok { ret (none, 0.0f64, e3) }
    var j = 0usize
    while j < p {
        vs[j] = l * tgt + (1.0f64 - l) * v[j]
        j += 1usize
    }
    ret (vs, l, ok)
}

// cor.shrink: p x p row-major; lambda < 0 asks for the estimate
fn cor_shrink(a: *mem.Arena, x: []const f64, n: usize, p: usize, lam: f64) -> ([]f64, f64, err) {
    var none: []f64 = zero
    var l = lam
    if l < 0.0f64 {
        let (le, e) = lambda_cor(a, x, n, p)
        if e != ok { ret (none, 0.0f64, e) }
        l = le
    }
    if l > 1.0f64 { l = 1.0f64 }
    let (r, re) = mem.alloc[f64](a, p * p)
    if re != ok { ret (none, 0.0f64, re) }
    let (xs, e2) = standardise(a, x, n, p)
    if e2 != ok { ret (none, 0.0f64, e2) }
    let nf = f64(n)
    let w2 = 1.0f64 / nf
    let h1 = 1.0f64 / (1.0f64 - w2)
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            if i == j || l == 1.0f64 {
                if i == j { r[i * p + j] = 1.0f64 } else { r[i * p + j] = 0.0f64 }
            } else {
                var s = 0.0f64
                var k = 0usize
                while k < n {
                    s += xs[k * p + i] * xs[k * p + j] / nf
                    k += 1usize
                }
                r[i * p + j] = (1.0f64 - l) * h1 * s
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (r, l, ok)
}

// cov.shrink = D R D with the shrunk variances and the shrunk correlations
fn cov_shrink(a: *mem.Arena, x: []const f64, n: usize, p: usize, lam: f64, lamv: f64) -> ([]f64, err) {
    var none: []f64 = zero
    let (vs, lv, e1) = var_shrink(a, x, n, p, lamv)
    if e1 != ok { ret (none, e1) }
    let (r, lc, e2) = cor_shrink(a, x, n, p, lam)
    if e2 != ok { ret (none, e2) }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            r[i * p + j] = r[i * p + j] * math.sqrt[f64](vs[i]) * math.sqrt[f64](vs[j])
            j += 1usize
        }
        i += 1usize
    }
    ret (r, ok)
}

// pseudoinverse of an m x n row-major matrix (n x m answer) with the default tolerance
fn pseudoinverse(a: *mem.Arena, x: []const f64, m: usize, n: usize) -> ([]f64, err) {
    var none: []f64 = zero
    // decomp reads column-major; hand it the matrix as columns of x^T, i.e. x row-major is t(X) there
    let (sv, e) = decomp.svd(a, x, n, m)
    if e != ok { ret (none, e) }
    var dmax = 0.0f64
    var t = 0usize
    while t < sv.k {
        if sv.d[t] > dmax { dmax = sv.d[t] }
        t += 1usize
    }
    var big = m
    if n > big { big = n }
    let tol = f64(big) * dmax * 2.220446049250313e-16f64
    let (out, oe) = mem.alloc[f64](a, n * m)
    if oe != ok { ret (none, oe) }
    // t(X) = U D V' (U n x k, V m x k, column-major arrays); X^+ = (t(X)^+)' = U D^-1 V'  as n x m
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < m {
            var s = 0.0f64
            t = 0usize
            while t < sv.k {
                if sv.d[t] > tol { s += sv.u[t * n + i] * (1.0f64 / sv.d[t]) * sv.v[t * m + j] }
                t += 1usize
            }
            out[i * m + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// pcor.shrink: the partial correlations -cov2cor(pseudoinverse(cor.shrink(x))), p x p row-major
fn pcor_shrink(a: *mem.Arena, x: []const f64, n: usize, p: usize, lam: f64) -> ([]f64, err) {
    var none: []f64 = zero
    let (r, l, e1) = cor_shrink(a, x, n, p, lam)
    if e1 != ok { ret (none, e1) }
    let (inv, e2) = pseudoinverse(a, r, p, p)
    if e2 != ok { ret (none, e2) }
    let (out, e3) = mem.alloc[f64](a, p * p)
    if e3 != ok { ret (none, e3) }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            if i == j {
                out[i * p + j] = 1.0f64
            } else {
                out[i * p + j] = 0.0f64 - inv[i * p + j] / math.sqrt[f64](inv[i * p + i] * inv[j * p + j])
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}
