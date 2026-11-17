// R smooth.spline with a given spar: the penalised cubic B-spline regression of the unique sorted x values (a knot at each when there are fewer than 50),
// with lambda = ratio 256^(3 spar - 1) where ratio is the trace ratio of the design and penalty Gram matrices over the inner basis functions, and predict().
//
// The penalty Gram matrix integrates the products of the second derivatives with the package own quadrature (the quadratic term weighted 0.3330, not 1/3).
//
// Not here: lambda chosen by df or cross-validation, tied x values (the weights are used as given), more than 49 distinct x (the package thins the knots).

use e.math
use e.mem

type SmSpline = struct { knots: []f64, nk: usize, coef: []f64, lo: f64, range: f64, lambda: f64 }

// the values of the q + 1 non-zero B-splines of degree q on the knot span l at x (Piegl and Tiller BasisFuns)
fn basis_funs(t: []const f64, l: usize, x: f64, q: usize, out: []f64) {
    var left: [4]f64 = zero
    var right: [4]f64 = zero
    out[0usize] = 1.0f64
    var j = 1usize
    while j <= q {
        left[j] = x - t[l + 1usize - j]
        right[j] = t[l + j] - x
        var saved = 0.0f64
        var r = 0usize
        while r < j {
            let temp = out[r] / (right[r + 1usize] + left[j - r])
            out[r] = saved + right[r + 1usize] * temp
            saved = left[j - r] * temp
            r += 1usize
        }
        out[j] = saved
        j += 1usize
    }
}

// the d-th derivative at x of the four non-zero cubic B-splines on span l: out[b] for the spline of index l - 3 + b
fn basis_deriv(a: *mem.Arena, t: []const f64, nk: usize, l: usize, x: f64, d: usize, out: []f64) -> err {
    if d == 0usize {
        basis_funs(t, l, x, 3usize, out)
        ret ok
    }
    let (c, e1) = mem.alloc[f64](a, nk + 2usize)
    let (c2, e2) = mem.alloc[f64](a, nk + 2usize)
    if e1 != ok || e2 != ok { ret mem.Full }
    var b = 0usize
    while b < 4usize {
        let bi = l - 3usize + b
        var j = 0usize
        while j < nk + 2usize {
            c[j] = 0.0f64
            j += 1usize
        }
        c[bi] = 1.0f64
        var step = 0usize
        var p = 3usize
        while step < d {
            // c'_j = p (c_j - c_{j-1}) / (t_{j+p} - t_j) for the degree p - 1 splines
            j = 0usize
            while j < nk + 1usize {
                var prev = 0.0f64
                if j > 0usize { prev = c[j - 1usize] }
                let den = t[j + p] - t[j]
                if den > 0.0f64 { c2[j] = f64(p) * (c[j] - prev) / den } else { c2[j] = 0.0f64 }
                j += 1usize
            }
            j = 0usize
            while j < nk + 1usize {
                c[j] = c2[j]
                j += 1usize
            }
            c[nk + 1usize] = 0.0f64
            p -= 1usize
            step += 1usize
        }
        // the derivative is sum_j c_j N_{j, p}: the non-zero ones on span l are j = l - p .. l
        var nv: [4]f64 = zero
        basis_funs(t, l, x, p, nv[0usize..4usize])
        var s = 0.0f64
        var r = 0usize
        while r <= p {
            s += c[l - p + r + 1usize - 1usize] * nv[r]
            r += 1usize
        }
        out[b] = s
        b += 1usize
    }
    ret ok
}

// the knot span of x: the last l with t[l] <= x and t[l] < t[l + 1]
fn find_span(t: []const f64, nk: usize, x: f64) -> usize {
    var l = 3usize
    var s = 3usize
    while s < nk {
        if t[s] < t[s + 1usize] && t[s] <= x { l = s }
        s += 1usize
    }
    ret l
}

// fit: x sorted distinct, y and w (weights) the same length, spar the smoothing parameter
fn fit(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, spar: f64, out: *SmSpline) -> err {
    let nx = x.len
    let nk = nx + 2usize
    let (kn, e1) = mem.alloc[f64](a, nk + 4usize)
    let (xb, e2) = mem.alloc[f64](a, nx)
    if e1 != ok || e2 != ok { ret mem.Full }
    let lo = x[0usize]
    let range = x[nx - 1usize] - x[0usize]
    var i = 0usize
    while i < nx {
        xb[i] = (x[i] - lo) / range
        i += 1usize
    }
    i = 0usize
    while i < 3usize {
        kn[i] = xb[0usize]
        kn[nk + 1usize + i] = xb[nx - 1usize]
        i += 1usize
    }
    i = 0usize
    while i < nx {
        kn[3usize + i] = xb[i]
        i += 1usize
    }
    let (hs, e3) = mem.alloc[f64](a, nk * nk)
    let (sg, e4) = mem.alloc[f64](a, nk * nk)
    let (xwy, e5) = mem.alloc[f64](a, nk)
    if e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    i = 0usize
    while i < nk * nk {
        hs[i] = 0.0f64
        sg[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nk {
        xwy[i] = 0.0f64
        i += 1usize
    }
    var nv: [4]f64 = zero
    i = 0usize
    while i < nx {
        let l = find_span(kn, nk, xb[i])
        basis_funs(kn, l, xb[i], 3usize, nv[0usize..4usize])
        var p = 0usize
        while p < 4usize {
            xwy[l - 3usize + p] += w[i] * y[i] * nv[p]
            var q = 0usize
            while q < 4usize {
                hs[(l - 3usize + p) * nk + (l - 3usize + q)] += w[i] * nv[p] * nv[q]
                q += 1usize
            }
            p += 1usize
        }
        i += 1usize
    }
    // the penalty
    let (y1, e6) = mem.alloc[f64](a, 4usize)
    let (y2, e7) = mem.alloc[f64](a, 4usize)
    if e6 != ok || e7 != ok { ret mem.Full }
    var l = 3usize
    while l < nk {
        let wpt = kn[l + 1usize] - kn[l]
        if wpt > 0.0f64 {
            let fe = basis_deriv(a, kn, nk, l, kn[l], 2usize, y1)
            if fe != ok { ret fe }
            let fe2 = basis_deriv(a, kn, nk, l, kn[l + 1usize], 2usize, y2)
            if fe2 != ok { ret fe2 }
            var p = 0usize
            while p < 4usize {
                y2[p] = y2[p] - y1[p]
                p += 1usize
            }
            p = 0usize
            while p < 4usize {
                var q = 0usize
                while q < 4usize {
                    sg[(l - 3usize + p) * nk + (l - 3usize + q)] += wpt * (y1[p] * y1[q] + (y2[p] * y1[q] + y2[q] * y1[p]) * 0.5f64 + y2[p] * y2[q] * 0.3330f64)
                    q += 1usize
                }
                p += 1usize
            }
        }
        l += 1usize
    }
    var t1 = 0.0f64
    var t2 = 0.0f64
    i = 2usize
    while i <= nk - 4usize {
        t1 += hs[i * nk + i]
        t2 += sg[i * nk + i]
        i += 1usize
    }
    let lambda = t1 / t2 * math.pow[f64](16.0f64, spar * 6.0f64 - 2.0f64)
    // solve (hs + lambda sg) coef = xwy by Cholesky
    let (m, e8) = mem.alloc[f64](a, nk * nk)
    let (cf, e9) = mem.alloc[f64](a, nk)
    if e8 != ok || e9 != ok { ret mem.Full }
    i = 0usize
    while i < nk * nk {
        m[i] = hs[i] + lambda * sg[i]
        i += 1usize
    }
    var j = 0usize
    while j < nk {
        var d = m[j * nk + j]
        var t = 0usize
        while t < j {
            d -= m[t * nk + j] * m[t * nk + j]
            t += 1usize
        }
        if d <= 0.0f64 { ret mem.Full }
        let dj = math.sqrt[f64](d)
        m[j * nk + j] = dj
        var r = j + 1usize
        while r < nk {
            var v = m[j * nk + r]
            t = 0usize
            while t < j {
                v -= m[t * nk + r] * m[t * nk + j]
                t += 1usize
            }
            m[j * nk + r] = v / dj
            r += 1usize
        }
        j += 1usize
    }
    // forward then back substitution with the lower factor stored column-wise in m[col * nk + row]
    i = 0usize
    while i < nk {
        var v = xwy[i]
        var t = 0usize
        while t < i {
            v -= m[t * nk + i] * cf[t]
            t += 1usize
        }
        cf[i] = v / m[i * nk + i]
        i += 1usize
    }
    i = nk
    while i > 0usize {
        i -= 1usize
        var v = cf[i]
        var t = i + 1usize
        while t < nk {
            v -= m[i * nk + t] * cf[t]
            t += 1usize
        }
        cf[i] = v / m[i * nk + i]
    }
    out.knots = kn
    out.nk = nk
    out.coef = cf
    out.lo = lo
    out.range = range
    out.lambda = lambda
    ret ok
}

// predict(fit, x): the fitted value, extending linearly outside the data range from the end value and slope
fn predict(a: *mem.Arena, f: *const SmSpline, x0: f64) -> f64 {
    let xs = (x0 - f.lo) / f.range
    var xe = xs
    if xs < 0.0f64 { xe = 0.0f64 }
    if xs > 1.0f64 { xe = 1.0f64 }
    let l = find_span(f.knots, f.nk, xe)
    var nv: [4]f64 = zero
    var dv: [4]f64 = zero
    basis_funs(f.knots, l, xe, 3usize, nv[0usize..4usize])
    var v = 0.0f64
    var p = 0usize
    while p < 4usize {
        v += f.coef[l - 3usize + p] * nv[p]
        p += 1usize
    }
    if xs >= 0.0f64 && xs <= 1.0f64 { ret v }
    let de = basis_deriv(a, f.knots, f.nk, l, xe, 1usize, dv[0usize..4usize])
    if de != ok { ret 0.0f64 / 0.0f64 }
    var dd = 0.0f64
    p = 0usize
    while p < 4usize {
        dd += f.coef[l - 3usize + p] * dv[p]
        p += 1usize
    }
    ret v + (xs - xe) * dd
}
