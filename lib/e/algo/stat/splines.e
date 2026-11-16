// R splines2, the B-spline family on explicit knots: `bspline` (and its derivatives), `mspline` (the normalised
// M-splines) and `ispline` (the integrated M-splines, the running sum of the next-order B-splines). The knot
// vector is the internal knots with each boundary knot repeated `degree + 1` times; the right boundary belongs to
// the last interval, as in splines2.
//
// Not here: cSpline, the derivatives of the M- and I-splines, periodic and natural-cubic bases, extrapolation
// beyond the boundary knots, df-based knot placement.

use e.mem

// b_{i,k}(x), or its d-th derivative, on the extended knot vector t (k is the order); 0 / 0 counts as 0
fn bval(t: []const f64, i: usize, k: usize, x: f64, d: usize, hi: f64) -> f64 {
    if k == 1usize {
        if d > 0usize { ret 0.0f64 }
        let l = t[i]
        let r = t[i + 1usize]
        if r > l && ((x >= l && x < r) || (x == hi && r == hi)) { ret 1.0f64 }
        ret 0.0f64
    }
    let d1 = t[i + k - 1usize] - t[i]
    let d2 = t[i + k] - t[i + 1usize]
    if d > 0usize {
        var s = 0.0f64
        if d1 > 0.0f64 { s += bval(t, i, k - 1usize, x, d - 1usize, hi) / d1 }
        if d2 > 0.0f64 { s -= bval(t, i + 1usize, k - 1usize, x, d - 1usize, hi) / d2 }
        ret f64(k - 1usize) * s
    }
    var v = 0.0f64
    if d1 > 0.0f64 { v += (x - t[i]) / d1 * bval(t, i, k - 1usize, x, 0usize, hi) }
    if d2 > 0.0f64 { v += (t[i + k] - x) / d2 * bval(t, i + 1usize, k - 1usize, x, 0usize, hi) }
    ret v
}

// the extended knot vector: lo repeated `reps` times, the internal knots, hi repeated `reps` times; t.len = nk + 2 reps
fn extend(t: []f64, knots: []const f64, lo: f64, hi: f64, reps: usize) {
    var i = 0usize
    while i < reps {
        t[i] = lo
        i += 1usize
    }
    i = 0usize
    while i < knots.len {
        t[reps + i] = knots[i]
        i += 1usize
    }
    i = 0usize
    while i < reps {
        t[reps + knots.len + i] = hi
        i += 1usize
    }
}

// one row of the basis at x: kind 0 B-spline (derivative order `deriv`), 1 M-spline, 2 I-spline; `out` receives
// nk + degree + 1 values, the first dropped (shifting the rest left) when not `intercept`; answers the count
fn row(t: []f64, tmp: []f64, knots: []const f64, lo: f64, hi: f64, degree: usize, intercept: bool, kind: u8, deriv: usize, x: f64, out: []f64) -> usize {
    let order = degree + 1usize
    let n = knots.len + order
    if kind == 2u8 {
        extend(t, knots, lo, hi, order + 1usize)
        var j = 0usize
        while j < n + 1usize {
            tmp[j] = bval(t, j, order + 1usize, x, 0usize, hi)
            j += 1usize
        }
        var c = 0usize
        while c < n {
            var s = 0.0f64
            var i = c + 1usize
            while i < n + 1usize {
                s += tmp[i]
                i += 1usize
            }
            tmp[n + 1usize + c] = s
            c += 1usize
        }
        var o = 0usize
        c = 0usize
        while c < n {
            if c > 0usize || intercept {
                out[o] = tmp[n + 1usize + c]
                o += 1usize
            }
            c += 1usize
        }
        ret o
    }
    extend(t, knots, lo, hi, order)
    var o = 0usize
    var c = 0usize
    while c < n {
        var v = bval(t, c, order, x, deriv, hi)
        if kind == 1u8 {
            let w = t[c + order] - t[c]
            if w > 0.0f64 { v = v * f64(order) / w } else { v = 0.0f64 }
        }
        if c > 0usize || intercept {
            out[o] = v
            o += 1usize
        }
        c += 1usize
    }
    ret o
}
