// Parametric curves and one surface over `f64` points in caller storage: a point is
// `Point` with `z` zero for the plane, so every routine serves 2-d and 3-d alike.
// `bezier` is de Casteljau over `scratch` (the degree is `points.len - 1`), and
// `bezier_split` is the same triangle keeping both edges: `left` and `right` are
// the two halves' control points, each `points.len` long. `bspline` is de Boor
// over a clamped or open knot vector of `points.len + degree + 1` knots for `t`
// in `[knots[degree], knots[points.len]]`, with `t` at the upper end evaluated
// on the last span, which is what `scipy.interpolate.BSpline` answers there.
// `uniform_knots` writes the clamped uniform vector that makes the curve pass
// through its end points. `catmull_rom` walks a chain of at least four points
// as `points.len - 3` segments, `t` in `[0, segments]`, Barry-Goldman with the
// knot spacing `|p_i+1 - p_i|^alpha`: `alpha` 0.5 is centripetal, 0 uniform,
// 1 chordal. `nurbs_surface` evaluates a tensor-product rational surface over a
// row-major `count_u * count_v` control grid with one weight per point.
//
// ponytail: de Boor and the basis functions hold their triangle in a fixed
// `MAX_DEGREE + 1` local, so a degree above 15 answers `Invalid`; a scratch
// parameter would lift it.

use e.math

type Point = struct { x: f64, y: f64, z: f64 }
error Invalid
error TooSmall

const MAX_DEGREE: usize = 15usize

fn point(x: f64, y: f64, z: f64) -> Point { ret Point { x: x, y: y, z: z } }

fn lerp(a: Point, b: Point, t: f64) -> Point {
    let s = 1.0f64 - t
    ret Point { x: s * a.x + t * b.x, y: s * a.y + t * b.y, z: s * a.z + t * b.z }
}

fn distance(a: Point, b: Point) -> f64 {
    let dx = a.x - b.x
    let dy = a.y - b.y
    let dz = a.z - b.z
    ret math.sqrt[f64](dx * dx + dy * dy + dz * dz)
}

// The point at `t` of the Bezier curve with `points` as control polygon.
fn bezier(points: []const Point, scratch: []Point, t: f64) -> (Point, err) {
    let n = points.len
    if n == 0usize { ret (zero, Invalid) }
    if scratch.len < n { ret (zero, TooSmall) }
    var i = 0usize
    while i < n {
        scratch[i] = points[i]
        i += 1usize
    }
    var level = 1usize
    while level < n {
        i = 0usize
        while i + level < n {
            scratch[i] = lerp(scratch[i], scratch[i + 1usize], t)
            i += 1usize
        }
        level += 1usize
    }
    ret (scratch[0usize], ok)
}

// Splits at `t`: `left` receives the control points of `[0, t]` and `right` of
// `[t, 1]`, both in curve order and both `points.len` long.
fn bezier_split(points: []const Point, t: f64, left: []Point, right: []Point) -> err {
    let n = points.len
    if n == 0usize { ret Invalid }
    if left.len < n || right.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        right[i] = points[i]
        i += 1usize
    }
    var level = 1usize
    while level < n {
        left[level - 1usize] = right[0usize]
        i = 0usize
        while i + level < n {
            right[i] = lerp(right[i], right[i + 1usize], t)
            i += 1usize
        }
        level += 1usize
    }
    left[n - 1usize] = right[0usize]
    ret ok
}

// The knot span holding `t`: the largest `k` in `[degree, count - 1]` with `knots[k] <= t`.
fn span_of(knots: []const f64, degree: usize, count: usize, t: f64) -> usize {
    var k = degree
    while k + 1usize < count && knots[k + 1usize] <= t { k += 1usize }
    ret k
}

// The point at `t` of the B-spline of `degree` over `points` and `knots`.
fn bspline(points: []const Point, knots: []const f64, degree: usize, t: f64) -> (Point, err) {
    let n = points.len
    if n == 0usize || degree > MAX_DEGREE || degree >= n || knots.len != n + degree + 1usize { ret (zero, Invalid) }
    if t < knots[degree] || t > knots[n] { ret (zero, Invalid) }
    let k = span_of(knots, degree, n, t)
    var d: [16]Point = zero
    var j = 0usize
    while j <= degree {
        d[j] = points[j + k - degree]
        j += 1usize
    }
    var r = 1usize
    while r <= degree {
        j = degree
        while j >= r {
            let i = j + k - degree
            let lo = knots[i]
            let hi = knots[i + degree - r + 1usize]
            var alpha = 0.0f64
            if hi != lo { alpha = (t - lo) / (hi - lo) }
            d[j] = lerp(d[j - 1usize], d[j], alpha)
            j -= 1usize
        }
        r += 1usize
    }
    ret (d[degree], ok)
}

// Clamped uniform knots for `count` control points: `degree + 1` zeros, the
// interior evenly spaced, `degree + 1` ones; `out` is `count + degree + 1` long.
fn uniform_knots(count: usize, degree: usize, out: []f64) -> err {
    if count == 0usize || degree >= count { ret Invalid }
    let total = count + degree + 1usize
    if out.len < total { ret TooSmall }
    let interior = count - degree
    var i = 0usize
    while i < total {
        if i <= degree {
            out[i] = 0.0f64
        } else if i >= count {
            out[i] = 1.0f64
        } else {
            out[i] = f64(i - degree) / f64(interior)
        }
        i += 1usize
    }
    ret ok
}

fn catmull_rom(points: []const Point, t: f64, alpha: f64) -> (Point, err) {
    if points.len < 4usize { ret (zero, Invalid) }
    let segments = f64(points.len - 3usize)
    if t < 0.0f64 || t > segments { ret (zero, Invalid) }
    var segment = usize(t)
    if segment >= points.len - 3usize { segment = points.len - 4usize }
    let u = t - f64(segment)
    let p0 = points[segment]
    let p1 = points[segment + 1usize]
    let p2 = points[segment + 2usize]
    let p3 = points[segment + 3usize]
    let t0 = 0.0f64
    let t1 = t0 + math.pow[f64](distance(p0, p1), alpha)
    let t2 = t1 + math.pow[f64](distance(p1, p2), alpha)
    let t3 = t2 + math.pow[f64](distance(p2, p3), alpha)
    let s = t1 + u * (t2 - t1)
    let a1 = lerp(p0, p1, ratio(s, t0, t1))
    let a2 = lerp(p1, p2, ratio(s, t1, t2))
    let a3 = lerp(p2, p3, ratio(s, t2, t3))
    let b1 = lerp(a1, a2, ratio(s, t0, t2))
    let b2 = lerp(a2, a3, ratio(s, t1, t3))
    ret (lerp(b1, b2, ratio(s, t1, t2)), ok)
}

fn ratio(s: f64, lo: f64, hi: f64) -> f64 {
    if hi == lo { ret 0.0f64 }
    ret (s - lo) / (hi - lo)
}

// The `degree + 1` non-zero basis functions at `t` on span `k` (Cox-de Boor).
fn basis(knots: []const f64, degree: usize, k: usize, t: f64, out: []f64) {
    var left: [16]f64 = zero
    var right: [16]f64 = zero
    out[0usize] = 1.0f64
    var j = 1usize
    while j <= degree {
        left[j] = t - knots[k + 1usize - j]
        right[j] = knots[k + j] - t
        var saved = 0.0f64
        var r = 0usize
        while r < j {
            let denominator = right[r + 1usize] + left[j - r]
            var term = 0.0f64
            if denominator != 0.0f64 { term = out[r] / denominator }
            out[r] = saved + right[r + 1usize] * term
            saved = left[j - r] * term
            r += 1usize
        }
        out[j] = saved
        j += 1usize
    }
}

// The surface point at `(u, v)`: `grid[i * count_v + j]` with `weights[i * count_v + j]`
// is the control point of row `i` (the u direction) and column `j` (the v direction).
fn nurbs_surface(grid: []const Point, weights: []const f64, count_u: usize, count_v: usize, knots_u: []const f64, knots_v: []const f64, degree_u: usize, degree_v: usize, u: f64, v: f64) -> (Point, err) {
    if count_u == 0usize || count_v == 0usize || degree_u > MAX_DEGREE || degree_v > MAX_DEGREE { ret (zero, Invalid) }
    if degree_u >= count_u || degree_v >= count_v || grid.len < count_u * count_v || weights.len < count_u * count_v { ret (zero, Invalid) }
    if knots_u.len != count_u + degree_u + 1usize || knots_v.len != count_v + degree_v + 1usize { ret (zero, Invalid) }
    if u < knots_u[degree_u] || u > knots_u[count_u] || v < knots_v[degree_v] || v > knots_v[count_v] { ret (zero, Invalid) }
    let ku = span_of(knots_u, degree_u, count_u, u)
    let kv = span_of(knots_v, degree_v, count_v, v)
    var nu: [16]f64 = zero
    var nv: [16]f64 = zero
    basis(knots_u, degree_u, ku, u, nu[..])
    basis(knots_v, degree_v, kv, v, nv[..])
    var x = 0.0f64
    var y = 0.0f64
    var z = 0.0f64
    var w = 0.0f64
    var i = 0usize
    while i <= degree_u {
        let row = ku - degree_u + i
        var j = 0usize
        while j <= degree_v {
            let column = kv - degree_v + j
            let at = row * count_v + column
            let weight = nu[i] * nv[j] * weights[at]
            x += weight * grid[at].x
            y += weight * grid[at].y
            z += weight * grid[at].z
            w += weight
            j += 1usize
        }
        i += 1usize
    }
    if w == 0.0f64 { ret (zero, Invalid) }
    ret (Point { x: x / w, y: y / w, z: z / w }, ok)
}
