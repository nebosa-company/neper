// R splines2, the B-spline family on explicit knots: `bspline` (and its derivatives), `mspline` (the normalised
// M-splines) and `ispline` (the integrated M-splines, the running sum of the next-order B-splines). The knot
// vector is the internal knots with each boundary knot repeated `degree + 1` times; the right boundary belongs to
// the last interval, as in splines2.
//
// Not here: cSpline, the derivatives of the M- and I-splines, periodic and natural-cubic bases, extrapolation
// beyond the boundary knots, df-based knot placement.

use e.math
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

// one row of the basis at x: kind 0 B-spline (derivative order `deriv`), 1 M-spline, 2 I-spline, 3 the integral of the B-spline from the left boundary (splines2::ibs); `out` receives
// nk + degree + 1 values, the first dropped (shifting the rest left) when not `intercept`; answers the count
fn row(t: []f64, tmp: []f64, knots: []const f64, lo: f64, hi: f64, degree: usize, intercept: bool, kind: u8, deriv: usize, x: f64, out: []f64) -> usize {
    let order = degree + 1usize
    let n = knots.len + order
    if kind == 2u8 || kind == 3u8 {
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
            if kind == 3u8 { s = s * (t[c + order + 1usize] - t[c + 1usize]) / f64(order) }
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

// splines2::naturalSpline row at x (cubic, at least two internal knots): the cubic B-spline row times H, whose columns are the null space of the second derivatives at the boundary knots in the form the package uses: (B1 + B2 + B3) / 3 and t B2 + (1 - t) B3 on the left, the interior B-splines, and s B[K-2] + (1 - s) B[K-1] and the mean of the last three on the right, with t, s from the boundary second derivatives; the first column drops without the intercept
fn nat_row(a: *mem.Arena, t: []f64, tmp: []f64, knots: []const f64, lo: f64, hi: f64, intercept: bool, x: f64, out: []f64) -> usize {
    let kk = knots.len + 4usize
    let (c0, e0) = mem.alloc[f64](a, kk)
    let (c1, e1) = mem.alloc[f64](a, kk)
    let (br, e2) = mem.alloc[f64](a, kk)
    if e0 != ok || e1 != ok || e2 != ok { ret 0usize }
    let g0 = row(t, tmp, knots, lo, hi, 3usize, true, 0u8, 2usize, lo, c0)
    let g1 = row(t, tmp, knots, lo, hi, 3usize, true, 0u8, 2usize, hi, c1)
    let gb = row(t, tmp, knots, lo, hi, 3usize, true, 0u8, 0usize, x, br)
    let tl = c0[2usize] / (c0[2usize] - c0[1usize])
    let sr = c1[kk - 2usize] / (c1[kk - 2usize] - c1[kk - 3usize])
    var o = 0usize
    var col0 = (br[0usize] + br[1usize] + br[2usize]) / 3.0f64
    if intercept {
        out[o] = col0
        o += 1usize
    }
    out[o] = tl * br[1usize] + (1.0f64 - tl) * br[2usize]
    o += 1usize
    var i = 3usize
    while i + 3usize < kk {
        out[o] = br[i]
        o += 1usize
        i += 1usize
    }
    out[o] = sr * br[kk - 3usize] + (1.0f64 - sr) * br[kk - 2usize]
    o += 1usize
    out[o] = (br[kk - 3usize] + br[kk - 2usize] + br[kk - 1usize]) / 3.0f64
    o += 1usize
    ret o
}

// splines2::cSpline row at x: the integral of the I-spline row over [lo, x], by 4-point Gauss-Legendre on each knot interval (exact: the I-splines are piecewise polynomials of degree <= degree); scale divides every column by its value at hi; the first column drops without the intercept. `work` needs width + 2 * width values
fn crow(a: *mem.Arena, t: []f64, tmp: []f64, knots: []const f64, lo: f64, hi: f64, degree: usize, intercept: bool, scale: bool, x: f64, out: []f64) -> usize {
    let width = knots.len + degree + 1usize
    let (acc, e1) = mem.alloc[f64](a, width)
    let (iv, e2) = mem.alloc[f64](a, width)
    let (top, e3) = mem.alloc[f64](a, width)
    let (rv, e4) = mem.alloc[f64](a, width + 2usize)
    if e4 != ok { ret 0usize }
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    var pass = 0usize
    while pass < 2usize {
        var xe = x
        if pass == 1usize { xe = hi }
        var c = 0usize
        while c < width {
            acc[c] = 0.0f64
            c += 1usize
        }
        var a0 = lo
        var seg = 0usize
        while seg <= knots.len && a0 < xe {
            var b0 = hi
            if seg < knots.len { b0 = knots[seg] }
            if b0 > xe { b0 = xe }
            if b0 > a0 {
                var q = 0usize
                while q < 4usize {
                    var nd = 0.0f64
                    var wt = 0.0f64
                    if q == 0usize {
                        nd = 0.0f64 - 0.8611363115940526f64
                        wt = 0.3478548451374538f64
                    } else if q == 1usize {
                        nd = 0.0f64 - 0.3399810435848563f64
                        wt = 0.6521451548625461f64
                    } else if q == 2usize {
                        nd = 0.3399810435848563f64
                        wt = 0.6521451548625461f64
                    } else {
                        nd = 0.8611363115940526f64
                        wt = 0.3478548451374538f64
                    }
                    let u = 0.5f64 * ((b0 - a0) * nd + b0 + a0)
                    let m = row(t, tmp, knots, lo, hi, degree, true, 2u8, 0usize, u, rv)
                    c = 0usize
                    while c < m {
                        acc[c] += wt * rv[c] * (b0 - a0) / 2.0f64
                        c += 1usize
                    }
                    q += 1usize
                }
            }
            a0 = b0
            seg += 1usize
        }
        if pass == 1usize {
            c = 0usize
            while c < width {
                top[c] = acc[c]
                c += 1usize
            }
        } else {
            c = 0usize
            while c < width {
                iv[c] = acc[c]
                c += 1usize
            }
        }
        pass += 1usize
    }
    var o = 0usize
    var c2 = 0usize
    while c2 < width {
        if c2 > 0usize || intercept {
            var v = iv[c2]
            if scale { v = v / top[c2] }
            out[o] = v
            o += 1usize
        }
        c2 += 1usize
    }
    ret o
}

// the unscaled C-spline columns at x (the integrals of the I-splines): C_c = sum over j' >= c + 2 of w_j' sum over m >= j' of B_{m, p+2}(x), w_j' = (t_{j'+p+1} - t_j') / (p + 1), p = degree + 1, on the knot vector with p + 2 boundary repeats; K = nk + degree + 1 values into cout
fn cspline_raw(t: []f64, tmp: []f64, knots: []const f64, lo: f64, hi: f64, degree: usize, x: f64, cout: []f64) {
    let p = degree + 1usize
    extend(t, knots, lo, hi, p + 2usize)
    let kk = knots.len + degree + 1usize
    // B_{m, p+2}(x) for every m with a non-empty index range of the extended vector
    let nb = t.len - (p + 2usize)
    var m = 0usize
    while m < nb {
        tmp[m] = bval(t, m, p + 2usize, x, 0usize, hi)
        m += 1usize
    }
    // suffix sums S_j = sum_{m >= j} B_m
    var j = nb
    while j > 0usize {
        j -= 1usize
        var s = 0.0f64
        var q = j
        while q < nb {
            s += tmp[q]
            q += 1usize
        }
        tmp[nb + j] = s
    }
    var c = 0usize
    while c < kk {
        var s = 0.0f64
        var jp = c + 2usize
        while jp < nb {
            let w = (t[jp + p + 1usize] - t[jp]) / f64(p + 1usize)
            s += w * tmp[nb + jp]
            jp += 1usize
        }
        cout[c] = s
        c += 1usize
    }
}

// splines2::cSpline row at x with scale = TRUE (each column divided by its value at the upper boundary knot) or FALSE; the first column drops without the intercept
fn cspline_row(t: []f64, tmp: []f64, knots: []const f64, lo: f64, hi: f64, degree: usize, intercept: bool, scale: bool, x: f64, cout: []f64, chi: []f64, out: []f64) -> usize {
    let kk = knots.len + degree + 1usize
    cspline_raw(t, tmp, knots, lo, hi, degree, x, cout)
    if scale { cspline_raw(t, tmp, knots, lo, hi, degree, hi, chi) }
    var o = 0usize
    var c = 0usize
    while c < kk {
        if c > 0usize || intercept {
            var v = cout[c]
            if scale { v = v / chi[c] }
            out[o] = v
            o += 1usize
        }
        c += 1usize
    }
    ret o
}

// the periodic B-spline (kind 0) or M-spline (kind 1) row at x on the circle of period hi - lo (splines2 periodic = TRUE): the splines of the knot vector extended by `degree` wrapped knots on each side, folded onto nk + 1 columns with function i going to column (i - degree) mod (nk + 1) (splines2 needs degree not above nk + 1); x = hi counts as lo; the first column drops without the intercept; t needs nk + 2 + 2 degree entries
fn periodic_row(t: []f64, knots: []const f64, lo: f64, hi: f64, degree: usize, intercept: bool, kind: u8, deriv: usize, x: f64, out: []f64) -> usize {
    let nk = knots.len
    let m = nk + 1usize
    let per = hi - lo
    let order = degree + 1usize
    // u[0] = lo, u[1..nk] the knots, u[nk + 1] = hi; t[i] = u[i - degree] extended periodically
    var i = 0usize
    while i < nk + 2usize + 2usize * degree {
        var pos = i64(i) - i64(degree)
        var shift = 0i64
        while pos < 0i64 {
            pos += i64(m)
            shift -= 1i64
        }
        while pos > i64(m) {
            pos -= i64(m)
            shift += 1i64
        }
        var u = lo
        if pos == i64(m) { u = hi } else if pos > 0i64 { u = knots[usize(pos) - 1usize] }
        t[i] = u + f64(shift) * per
        i += 1usize
    }
    var xm = x
    if x >= hi { xm = lo }
    var c = 0usize
    while c < m {
        out[c] = 0.0f64
        c += 1usize
    }
    let nf = nk + 1usize + degree
    var f = 0usize
    while f < nf {
        var v = bval(t, f, order, xm, deriv, hi + per + 1.0f64)
        if kind == 1u8 {
            let w = t[f + order] - t[f]
            if w > 0.0f64 { v = v * f64(order) / w } else { v = 0.0f64 }
        }
        out[(f + m * (degree / m + 1usize) - degree) % m] += v
        f += 1usize
    }
    if !intercept {
        c = 1usize
        while c < m {
            out[c - 1usize] = out[c]
            c += 1usize
        }
        ret m - 1usize
    }
    ret m
}

fn bern_choose(n: usize, k: usize) -> f64 {
    var r = 1.0f64
    var i = 1usize
    while i <= k {
        r = r * f64(n - k + i) / f64(i)
        i += 1usize
    }
    ret r
}

// b_{i,n}(u) = C(n, i) u^i (1 - u)^(n - i); zero outside 0 <= i <= n
fn bern_val(n: usize, i: i64, u: f64) -> f64 {
    if i < 0i64 || usize(i) > n { ret 0.0f64 }
    ret bern_choose(n, usize(i)) * math.pow[f64](u, f64(i)) * math.pow[f64](1.0f64 - u, f64(n) - f64(i))
}

// splines2::bernsteinPoly row at x on [lo, hi]: degree + 1 columns, the first dropped without the intercept; deriv is the derivative order (at most degree); answers the count
fn bern_row(degree: usize, intercept: bool, lo: f64, hi: f64, deriv: usize, x: f64, out: []f64) -> usize {
    let u = (x - lo) / (hi - lo)
    var o = 0usize
    var i = 0usize
    while i <= degree {
        if i > 0usize || intercept {
            var v = 0.0f64
            if deriv == 0usize {
                v = bern_val(degree, i64(i), u)
            } else if deriv <= degree {
                var ff = 1.0f64
                var q = 0usize
                while q < deriv {
                    ff = ff * f64(degree - q)
                    q += 1usize
                }
                var j = 0usize
                while j <= deriv {
                    var sg = 1.0f64
                    if (deriv - j) % 2usize == 1usize { sg = 0.0f64 - 1.0f64 }
                    v += sg * bern_choose(deriv, j) * bern_val(degree - deriv, i64(i) - i64(j), u)
                    j += 1usize
                }
                v = v * ff / math.pow[f64](hi - lo, f64(deriv))
            }
            out[o] = v
            o += 1usize
        }
        i += 1usize
    }
    ret o
}

// splines2::nsk row at x: the natural basis (`nat_row` with the intercept) times the inverse of its values at the boundary and internal knots, so each column is the cardinal natural spline that is one at its own knot and zero at the others; the first column drops without the intercept
fn nsk_row(a: *mem.Arena, t: []f64, tmp: []f64, knots: []const f64, lo: f64, hi: f64, intercept: bool, x: f64, out: []f64) -> usize {
    let kn = knots.len + 2usize
    let (m, e0) = mem.alloc[f64](a, kn * kn)
    let (rhs, e1) = mem.alloc[f64](a, kn)
    let (nrow, e2) = mem.alloc[f64](a, kn + 4usize)
    if e0 != ok || e1 != ok || e2 != ok { ret 0usize }
    // M^T r = N(x): column j of M^T is the basis at knot j, stored row-major as mt[c * kn + j]
    var j = 0usize
    while j < kn {
        var kx = lo
        if j == kn - 1usize { kx = hi } else if j > 0usize { kx = knots[j - 1usize] }
        let c = nat_row(a, t, tmp, knots, lo, hi, true, kx, nrow)
        if c != kn { ret 0usize }
        var i = 0usize
        while i < kn {
            m[i * kn + j] = nrow[i]
            i += 1usize
        }
        j += 1usize
    }
    let c2 = nat_row(a, t, tmp, knots, lo, hi, true, x, nrow)
    if c2 != kn { ret 0usize }
    var i = 0usize
    while i < kn {
        rhs[i] = nrow[i]
        i += 1usize
    }
    // Gaussian elimination with partial pivoting on m r = rhs
    var col = 0usize
    while col < kn {
        var piv = col
        var best = math.abs[f64](m[col * kn + col])
        var r = col + 1usize
        while r < kn {
            let v = math.abs[f64](m[r * kn + col])
            if v > best {
                best = v
                piv = r
            }
            r += 1usize
        }
        if piv != col {
            var q = 0usize
            while q < kn {
                let tv = m[col * kn + q]
                m[col * kn + q] = m[piv * kn + q]
                m[piv * kn + q] = tv
                q += 1usize
            }
            let tr = rhs[col]
            rhs[col] = rhs[piv]
            rhs[piv] = tr
        }
        r = col + 1usize
        while r < kn {
            let f = m[r * kn + col] / m[col * kn + col]
            var q = col
            while q < kn {
                m[r * kn + q] = m[r * kn + q] - f * m[col * kn + q]
                q += 1usize
            }
            rhs[r] = rhs[r] - f * rhs[col]
            r += 1usize
        }
        col += 1usize
    }
    var sol_i = kn
    while sol_i > 0usize {
        sol_i -= 1usize
        var s = rhs[sol_i]
        var q = sol_i + 1usize
        while q < kn {
            s -= m[sol_i * kn + q] * rhs[q]
            q += 1usize
        }
        rhs[sol_i] = s / m[sol_i * kn + sol_i]
    }
    var o = 0usize
    var cidx = 0usize
    while cidx < kn {
        if cidx > 0usize || intercept {
            out[o] = rhs[cidx]
            o += 1usize
        }
        cidx += 1usize
    }
    ret o
}
