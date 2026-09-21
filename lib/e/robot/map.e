// 2-d mapping and localisation over caller storage: an occupancy grid in
// log-odds updated by Bresenham ray traversal (`occupancy_update`,
// `occupancy_probability`, `raycast`, `likelihood_field`), point-to-line
// ICP scan matching against model segments (`scan_match`), Monte Carlo
// localisation with a likelihood-field sensor model and low-variance
// resampling (`localize_amcl` and its steps), and Gauss-Newton pose-graph
// optimisation with the first pose fixed (`pose_graph_optimize`).
//
// The grid's origin is the world origin; cell (ix, iy) covers
// [ix * resolution, (ix + 1) * resolution) and lives at `grid[iy * w + ix]`.
// Random-number order in AMCL: per particle three gaussians (x, y, theta noise),
// each two f64 draws by Box-Muller; resampling draws one f64.

use e.algo.rand
use e.math

type Occupancy = struct { grid: []f64, w: usize, h: usize, resolution: f64 }
type Segment = struct { x0: f64, y0: f64, x1: f64, y1: f64 }
// A relative-pose constraint: pose `j` seen from pose `i` as (dx, dy, dth) in `i`'s frame,
// with a diagonal information (`info_xy` on x and y, `info_th` on theta).
type Edge = struct { i: u32, j: u32, dx: f64, dy: f64, dth: f64, info_xy: f64, info_th: f64 }
type Particles = struct { xs: []f64, ys: []f64, ths: []f64, weights: []f64, scratch: []f64, n: usize }
// A motion in the robot frame with the standard deviations of its noise.
type Motion = struct { dx: f64, dy: f64, dth: f64, noise_xy: f64, noise_th: f64 }
// `field[cell]` is the distance to the nearest occupied cell (`likelihood_field`); a beam
// ending off the grid scores as `off_grid` metres away; `sigma` is the field's width.
type Sensor = struct { field: []const f64, max_range: f64, sigma: f64, off_grid: f64 }
error TooSmall
error Invalid

fn two_pi() -> f64 { ret 6.283185307179586f64 }

fn wrap_angle(th: f64) -> f64 {
    var t = th
    while t > 3.141592653589793f64 { t -= two_pi() }
    while t <= 0.0f64 - 3.141592653589793f64 { t += two_pi() }
    ret t
}

fn abs_i64(v: i64) -> i64 {
    if v < 0i64 { ret 0i64 - v }
    ret v
}

// --- occupancy grid ----------------------------------------------------------------------

fn occupancy(grid: []f64, w: usize, h: usize, resolution: f64) -> (Occupancy, err) {
    let o = Occupancy { grid: grid, w: w, h: h, resolution: resolution }
    if grid.len < w * h { ret (o, TooSmall) }
    if resolution <= 0.0f64 { ret (o, Invalid) }
    ret (o, ok)
}

fn cell_x(o: *const Occupancy, x: f64) -> i64 { ret i64(math.floor[f64](x / o.resolution)) }

fn inside(o: *const Occupancy, ix: i64, iy: i64) -> bool { ret ix >= 0i64 && iy >= 0i64 && ix < i64(o.w) && iy < i64(o.h) }

fn bump(o: *Occupancy, ix: i64, iy: i64, delta: f64) {
    if inside(o, ix, iy) { o.grid[usize(iy) * o.w + usize(ix)] += delta }
}

// #1843 One scan into the log-odds grid: every beam walks the cells from the pose to its
// end point by Bresenham adding `l_free`, and a beam shorter than `max_range` adds `l_occ`
// to the cell it ends in. `angles` are relative to `pth`.
fn occupancy_update(o: *Occupancy, px: f64, py: f64, pth: f64, ranges: []const f64, angles: []const f64, max_range: f64, l_occ: f64, l_free: f64) -> err {
    if ranges.len != angles.len { ret Invalid }
    var k = 0usize
    while k < ranges.len {
        let hit = ranges[k] < max_range
        var r = ranges[k]
        if !hit { r = max_range }
        let a = pth + angles[k]
        var x0 = cell_x(o, px)
        var y0 = cell_x(o, py)
        let x1 = cell_x(o, px + r * math.cos[f64](a))
        let y1 = cell_x(o, py + r * math.sin[f64](a))
        let dx = abs_i64(x1 - x0)
        let dy = 0i64 - abs_i64(y1 - y0)
        var sx = 1i64
        if x0 > x1 { sx = 0i64 - 1i64 }
        var sy = 1i64
        if y0 > y1 { sy = 0i64 - 1i64 }
        var e = dx + dy
        while true {
            if x0 == x1 && y0 == y1 { break }
            bump(o, x0, y0, l_free)
            let e2 = 2i64 * e
            if e2 >= dy {
                e += dy
                x0 += sx
            }
            if e2 <= dx {
                e += dx
                y0 += sy
            }
        }
        if hit { bump(o, x1, y1, l_occ) }
        k += 1usize
    }
    ret ok
}

// The probability a cell with log-odds `l` is occupied.
fn occupancy_probability(l: f64) -> f64 { ret 1.0f64 - 1.0f64 / (1.0f64 + math.exp[f64](l)) }

fn occupied(o: *const Occupancy, ix: i64, iy: i64, threshold: f64) -> bool {
    ret inside(o, ix, iy) && o.grid[usize(iy) * o.w + usize(ix)] > threshold
}

// The range along `angle` from (x, y) to the first cell above `threshold`, marching in
// half-cell steps; `max_range` when nothing is hit within it.
// ponytail: sampled march, so a range is quantised to half a cell; a DDA walk would be exact.
fn raycast(o: *const Occupancy, x: f64, y: f64, angle: f64, max_range: f64, threshold: f64) -> f64 {
    let step = o.resolution / 2.0f64
    let c = math.cos[f64](angle)
    let s = math.sin[f64](angle)
    var t = 0.0f64
    while t <= max_range {
        if occupied(o, cell_x(o, x + t * c), cell_x(o, y + t * s), threshold) { ret t }
        t += step
    }
    ret max_range
}

// `field[cell]` becomes the distance between cell centres to the nearest cell above
// `threshold`, or `w + h` cells' worth of metres when there is none.
// ponytail: O(cells * occupied) brute force; a two-pass distance transform is linear.
fn likelihood_field(o: *const Occupancy, threshold: f64, field: []f64) -> err {
    let cells = o.w * o.h
    if field.len < cells { ret TooSmall }
    var c = 0usize
    while c < cells {
        let cx = c % o.w
        let cy = c / o.w
        var best = f64(o.w + o.h) * o.resolution
        var k = 0usize
        while k < cells {
            if o.grid[k] > threshold {
                let dx = f64(k % o.w) - f64(cx)
                let dy = f64(k / o.w) - f64(cy)
                let d = math.sqrt[f64](dx * dx + dy * dy) * o.resolution
                if d < best { best = d }
            }
            k += 1usize
        }
        field[c] = best
        c += 1usize
    }
    ret ok
}

// --- scan matching -----------------------------------------------------------------------

// The point of `s` nearest (x, y).
fn nearest_on(s: Segment, x: f64, y: f64) -> (f64, f64) {
    let dx = s.x1 - s.x0
    let dy = s.y1 - s.y0
    let len2 = dx * dx + dy * dy
    var t = 0.0f64
    if len2 > 0.0f64 {
        t = ((x - s.x0) * dx + (y - s.y0) * dy) / len2
        if t < 0.0f64 { t = 0.0f64 }
        if t > 1.0f64 { t = 1.0f64 }
    }
    ret (s.x0 + t * dx, s.y0 + t * dy)
}

// #1845 Point-to-line ICP: each iteration projects every scan point (robot frame) through
// the pose, pairs it with the nearest point on the nearest segment, and re-solves the rigid
// transform in closed form (theta from atan2 of the cross and dot sums about the centroids,
// then the translation). Answers (x, y, theta, mean squared residual).
fn scan_match(px: []const f64, py: []const f64, lines: []const Segment, x: f64, y: f64, th: f64, iterations: usize) -> (f64, f64, f64, f64) {
    var tx = x
    var ty = y
    var tth = th
    var mse = 0.0f64
    let n = px.len
    if n == 0usize || py.len < n || lines.len == 0usize { ret (tx, ty, tth, mse) }
    var it = 0usize
    while it < iterations {
        let c = math.cos[f64](tth)
        let s = math.sin[f64](tth)
        var cpx = 0.0f64
        var cpy = 0.0f64
        var cqx = 0.0f64
        var cqy = 0.0f64
        var i = 0usize
        while i < n {
            let wx = c * px[i] - s * py[i] + tx
            let wy = s * px[i] + c * py[i] + ty
            let (qx, qy) = target_of(lines, wx, wy)
            cpx += px[i]
            cpy += py[i]
            cqx += qx
            cqy += qy
            i += 1usize
        }
        cpx /= f64(n)
        cpy /= f64(n)
        cqx /= f64(n)
        cqy /= f64(n)
        var dot = 0.0f64
        var cross = 0.0f64
        i = 0usize
        while i < n {
            let wx = c * px[i] - s * py[i] + tx
            let wy = s * px[i] + c * py[i] + ty
            let (qx, qy) = target_of(lines, wx, wy)
            let ax = px[i] - cpx
            let ay = py[i] - cpy
            let bx = qx - cqx
            let by = qy - cqy
            dot += ax * bx + ay * by
            cross += ax * by - ay * bx
            i += 1usize
        }
        tth = math.atan2[f64](cross, dot)
        let c2 = math.cos[f64](tth)
        let s2 = math.sin[f64](tth)
        tx = cqx - (c2 * cpx - s2 * cpy)
        ty = cqy - (s2 * cpx + c2 * cpy)
        mse = 0.0f64
        i = 0usize
        while i < n {
            let wx = c2 * px[i] - s2 * py[i] + tx
            let wy = s2 * px[i] + c2 * py[i] + ty
            let (qx, qy) = target_of(lines, wx, wy)
            mse += (wx - qx) * (wx - qx) + (wy - qy) * (wy - qy)
            i += 1usize
        }
        mse /= f64(n)
        it += 1usize
    }
    ret (tx, ty, tth, mse)
}

fn target_of(lines: []const Segment, wx: f64, wy: f64) -> (f64, f64) {
    var bx = 0.0f64
    var by = 0.0f64
    var best = 0.0f64
    var k = 0usize
    while k < lines.len {
        let (qx, qy) = nearest_on(lines[k], wx, wy)
        let d = (qx - wx) * (qx - wx) + (qy - wy) * (qy - wy)
        if k == 0usize || d < best {
            best = d
            bx = qx
            by = qy
        }
        k += 1usize
    }
    ret (bx, by)
}

// --- Monte Carlo localisation ------------------------------------------------------------

fn particles(xs: []f64, ys: []f64, ths: []f64, weights: []f64, scratch: []f64, n: usize) -> (Particles, err) {
    let s = Particles { xs: xs, ys: ys, ths: ths, weights: weights, scratch: scratch, n: n }
    if xs.len < n || ys.len < n || ths.len < n || weights.len < n || scratch.len < 3usize * n { ret (s, TooSmall) }
    if n == 0usize { ret (s, Invalid) }
    ret (s, ok)
}

// A standard normal by Box-Muller (two draws; the log argument is kept off zero).
fn gaussian(rng: *rand.Pcg64) -> f64 {
    let u1 = 1.0f64 - rand.pcg64_f64(rng)
    let u2 = rand.pcg64_f64(rng)
    ret math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](u1)) * math.cos[f64](two_pi() * u2)
}

// Particles uniform in a box about (x, y, th); draws x, y, theta per particle.
fn particles_init(s: *Particles, rng: *rand.Pcg64, x: f64, y: f64, th: f64, spread_xy: f64, spread_th: f64) {
    var i = 0usize
    while i < s.n {
        s.xs[i] = x + (2.0f64 * rand.pcg64_f64(rng) - 1.0f64) * spread_xy
        s.ys[i] = y + (2.0f64 * rand.pcg64_f64(rng) - 1.0f64) * spread_xy
        s.ths[i] = wrap_angle(th + (2.0f64 * rand.pcg64_f64(rng) - 1.0f64) * spread_th)
        s.weights[i] = 1.0f64 / f64(s.n)
        i += 1usize
    }
}

// Move every particle by `m` in its own frame plus gaussian noise.
fn amcl_predict(s: *Particles, m: *const Motion, rng: *rand.Pcg64) {
    var i = 0usize
    while i < s.n {
        let fx = m.dx + gaussian(rng) * m.noise_xy
        let fy = m.dy + gaussian(rng) * m.noise_xy
        let fth = m.dth + gaussian(rng) * m.noise_th
        let c = math.cos[f64](s.ths[i])
        let sn = math.sin[f64](s.ths[i])
        s.xs[i] += c * fx - sn * fy
        s.ys[i] += sn * fx + c * fy
        s.ths[i] = wrap_angle(s.ths[i] + fth)
        i += 1usize
    }
}

// Weight every particle by the likelihood field: each beam under `max_range` ends somewhere,
// and its distance to the nearest occupied cell scores exp(-d^2 / (2 sigma^2)); the product
// over beams is taken in logs and normalised to sum to one.
fn amcl_weigh(s: *Particles, o: *const Occupancy, sensor: *const Sensor, ranges: []const f64, angles: []const f64) -> err {
    if ranges.len != angles.len || sensor.field.len < o.w * o.h { ret Invalid }
    let denominator = 2.0f64 * sensor.sigma * sensor.sigma
    var top = 0.0f64
    var i = 0usize
    while i < s.n {
        var lw = 0.0f64
        var k = 0usize
        while k < ranges.len {
            if ranges[k] < sensor.max_range {
                let a = s.ths[i] + angles[k]
                let ex = s.xs[i] + ranges[k] * math.cos[f64](a)
                let ey = s.ys[i] + ranges[k] * math.sin[f64](a)
                let ix = cell_x(o, ex)
                let iy = cell_x(o, ey)
                var d = sensor.off_grid
                if inside(o, ix, iy) { d = sensor.field[usize(iy) * o.w + usize(ix)] }
                lw -= d * d / denominator
            }
            k += 1usize
        }
        s.weights[i] = lw
        if i == 0usize || lw > top { top = lw }
        i += 1usize
    }
    var total = 0.0f64
    i = 0usize
    while i < s.n {
        s.weights[i] = math.exp[f64](s.weights[i] - top)
        total += s.weights[i]
        i += 1usize
    }
    i = 0usize
    while i < s.n {
        s.weights[i] /= total
        i += 1usize
    }
    ret ok
}

// Low-variance (systematic) resampling from one draw; weights become uniform.
// ponytail: fixed particle count; KLD adaptation would size `n` per step.
fn amcl_resample(s: *Particles, rng: *rand.Pcg64) {
    let n = s.n
    let r = rand.pcg64_f64(rng) / f64(n)
    var c = s.weights[0usize]
    var i = 0usize
    var m = 0usize
    while m < n {
        let u = r + f64(m) / f64(n)
        while u > c && i + 1usize < n {
            i += 1usize
            c += s.weights[i]
        }
        s.scratch[m] = s.xs[i]
        s.scratch[n + m] = s.ys[i]
        s.scratch[2usize * n + m] = s.ths[i]
        m += 1usize
    }
    m = 0usize
    while m < n {
        s.xs[m] = s.scratch[m]
        s.ys[m] = s.scratch[n + m]
        s.ths[m] = s.scratch[2usize * n + m]
        s.weights[m] = 1.0f64 / f64(n)
        m += 1usize
    }
}

// The weighted mean pose; theta is the circular mean.
fn amcl_mean(s: *const Particles) -> (f64, f64, f64) {
    var mx = 0.0f64
    var my = 0.0f64
    var sc = 0.0f64
    var ss = 0.0f64
    var i = 0usize
    while i < s.n {
        mx += s.weights[i] * s.xs[i]
        my += s.weights[i] * s.ys[i]
        sc += s.weights[i] * math.cos[f64](s.ths[i])
        ss += s.weights[i] * math.sin[f64](s.ths[i])
        i += 1usize
    }
    ret (mx, my, math.atan2[f64](ss, sc))
}

// #1846 One AMCL step: predict, weigh by the scan, resample; answers the mean pose.
fn localize_amcl(s: *Particles, m: *const Motion, o: *const Occupancy, sensor: *const Sensor, ranges: []const f64, angles: []const f64, rng: *rand.Pcg64) -> (f64, f64, f64, err) {
    amcl_predict(s, m, rng)
    let weigh_error = amcl_weigh(s, o, sensor, ranges, angles)
    if weigh_error != ok { ret (0.0f64, 0.0f64, 0.0f64, weigh_error) }
    amcl_resample(s, rng)
    let (mx, my, mth) = amcl_mean(s)
    ret (mx, my, mth, ok)
}

// --- pose graph --------------------------------------------------------------------------

// The error of one edge: t2v(Z^-1 (Xi^-1 Xj)) as (ex, ey, eth).
fn edge_error(xs: []const f64, ys: []const f64, ths: []const f64, e: Edge) -> (f64, f64, f64) {
    let i = usize(e.i)
    let j = usize(e.j)
    let ci = math.cos[f64](ths[i])
    let si = math.sin[f64](ths[i])
    let dx = xs[j] - xs[i]
    let dy = ys[j] - ys[i]
    // Xi^-1 Xj translation in i's frame, minus the measurement, rotated into z's frame.
    let rx = ci * dx + si * dy - e.dx
    let ry = 0.0f64 - si * dx + ci * dy - e.dy
    let cz = math.cos[f64](e.dth)
    let sz = math.sin[f64](e.dth)
    let ex = cz * rx + sz * ry
    let ey = 0.0f64 - sz * rx + cz * ry
    ret (ex, ey, wrap_angle(ths[j] - ths[i] - e.dth))
}

// The weighted squared error over all edges.
fn residual(xs: []const f64, ys: []const f64, ths: []const f64, edges: []const Edge) -> f64 {
    var chi = 0.0f64
    var k = 0usize
    while k < edges.len {
        let (ex, ey, eth) = edge_error(xs, ys, ths, edges[k])
        chi += edges[k].info_xy * (ex * ex + ey * ey) + edges[k].info_th * eth * eth
        k += 1usize
    }
    ret chi
}

// Solve H x = -b in place by Cholesky; `hm` is m x m row-major, `b` becomes x.
fn cholesky_solve(hm: []f64, b: []f64, m: usize) -> err {
    var i = 0usize
    while i < m {
        var j = 0usize
        while j <= i {
            var sum = hm[i * m + j]
            var k = 0usize
            while k < j {
                sum -= hm[i * m + k] * hm[j * m + k]
                k += 1usize
            }
            if i == j {
                if sum <= 0.0f64 { ret Invalid }
                hm[i * m + i] = math.sqrt[f64](sum)
            } else {
                hm[i * m + j] = sum / hm[j * m + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    // Forward: L y = -b, then back: L^T x = y.
    i = 0usize
    while i < m {
        var sum = 0.0f64 - b[i]
        var k = 0usize
        while k < i {
            sum -= hm[i * m + k] * b[k]
            k += 1usize
        }
        b[i] = sum / hm[i * m + i]
        i += 1usize
    }
    i = m
    while i > 0usize {
        i -= 1usize
        var sum = b[i]
        var k = i + 1usize
        while k < m {
            sum -= hm[k * m + i] * b[k]
            k += 1usize
        }
        b[i] = sum / hm[i * m + i]
    }
    ret ok
}

// Add J^T W e to `b` and J^T W J to `hm` for one pose's 3 x 3 Jacobian block at column `col`
// against another's at `col2` (both blocks handed in row-major).
fn accumulate(hm: []f64, b: []f64, m: usize, ja: []const f64, col_a: usize, jb: []const f64, col_b: usize, ex: f64, ey: f64, eth: f64, wxy: f64, wth: f64) {
    var r = 0usize
    while r < 3usize {
        var c = 0usize
        while c < 3usize {
            // (J^T W J)[r][c] = sum_k J[k][r] w_k J[k][c]
            var sum = 0.0f64
            var k = 0usize
            while k < 3usize {
                var wk = wxy
                if k == 2usize { wk = wth }
                sum += ja[k * 3usize + r] * wk * jb[k * 3usize + c]
                k += 1usize
            }
            hm[(col_a + r) * m + col_b + c] += sum
            c += 1usize
        }
        b[col_a + r] += ja[r] * wxy * ex + ja[3usize + r] * wxy * ey + ja[6usize + r] * wth * eth
        r += 1usize
    }
}

// #1847 Gauss-Newton over poses with pose 0 fixed: every iteration linearises each edge
// (analytic Jacobians), assembles the dense normal equations H dx = -b over the 3 (n - 1)
// free coordinates and solves by Cholesky. `scratch` needs m * m + m + 36 doubles for
// m = 3 (n - 1). Answers the residual after the last step.
// ponytail: dense m x m system, so about 30 poses is the comfortable ceiling; a sparse
// (banded or CSC) Cholesky lifts it.
fn pose_graph_optimize(xs: []f64, ys: []f64, ths: []f64, edges: []const Edge, iterations: usize, scratch: []f64) -> (f64, err) {
    let n = xs.len
    if n < 2usize || ys.len < n || ths.len < n { ret (0.0f64, Invalid) }
    let m = 3usize * (n - 1usize)
    if scratch.len < m * m + m + 36usize { ret (0.0f64, TooSmall) }
    var k = 0usize
    while k < edges.len {
        if usize(edges[k].i) >= n || usize(edges[k].j) >= n || edges[k].i == edges[k].j { ret (0.0f64, Invalid) }
        k += 1usize
    }
    let hm = scratch[..m * m]
    let b = scratch[m * m..m * m + m]
    let ja = scratch[m * m + m..m * m + m + 9usize]
    let jb = scratch[m * m + m + 9usize..m * m + m + 18usize]
    var it = 0usize
    while it < iterations {
        var z = 0usize
        while z < m * m {
            hm[z] = 0.0f64
            z += 1usize
        }
        z = 0usize
        while z < m {
            b[z] = 0.0f64
            z += 1usize
        }
        k = 0usize
        while k < edges.len {
            let e = edges[k]
            let i = usize(e.i)
            let j = usize(e.j)
            let (ex, ey, eth) = edge_error(xs, ys, ths, e)
            let ci = math.cos[f64](ths[i])
            let si = math.sin[f64](ths[i])
            let cz = math.cos[f64](e.dth)
            let sz = math.sin[f64](e.dth)
            let dx = xs[j] - xs[i]
            let dy = ys[j] - ys[i]
            // Rz^T Ri^T as a 2 x 2: m00 m01 / m10 m11.
            let m00 = cz * ci + sz * (0.0f64 - si)
            let m01 = cz * si + sz * ci
            let m10 = (0.0f64 - sz) * ci + cz * (0.0f64 - si)
            let m11 = (0.0f64 - sz) * si + cz * ci
            // d(Ri^T dt)/dtheta_i = [-si ci; -ci -si] dt, then Rz^T.
            let gx = (0.0f64 - si) * dx + ci * dy
            let gy = (0.0f64 - ci) * dx - si * dy
            let tx = cz * gx + sz * gy
            let ty = (0.0f64 - sz) * gx + cz * gy
            ja[0usize] = 0.0f64 - m00
            ja[1usize] = 0.0f64 - m01
            ja[2usize] = tx
            ja[3usize] = 0.0f64 - m10
            ja[4usize] = 0.0f64 - m11
            ja[5usize] = ty
            ja[6usize] = 0.0f64
            ja[7usize] = 0.0f64
            ja[8usize] = 0.0f64 - 1.0f64
            jb[0usize] = m00
            jb[1usize] = m01
            jb[2usize] = 0.0f64
            jb[3usize] = m10
            jb[4usize] = m11
            jb[5usize] = 0.0f64
            jb[6usize] = 0.0f64
            jb[7usize] = 0.0f64
            jb[8usize] = 1.0f64
            if i > 0usize {
                accumulate(hm, b, m, ja, 3usize * (i - 1usize), ja, 3usize * (i - 1usize), ex, ey, eth, e.info_xy, e.info_th)
                if j > 0usize { accumulate(hm, b, m, ja, 3usize * (i - 1usize), jb, 3usize * (j - 1usize), 0.0f64, 0.0f64, 0.0f64, e.info_xy, e.info_th) }
            }
            if j > 0usize {
                accumulate(hm, b, m, jb, 3usize * (j - 1usize), jb, 3usize * (j - 1usize), ex, ey, eth, e.info_xy, e.info_th)
                if i > 0usize { accumulate(hm, b, m, jb, 3usize * (j - 1usize), ja, 3usize * (i - 1usize), 0.0f64, 0.0f64, 0.0f64, e.info_xy, e.info_th) }
            }
            k += 1usize
        }
        let solve_error = cholesky_solve(hm, b, m)
        if solve_error != ok { ret (residual(xs, ys, ths, edges), solve_error) }
        var q = 1usize
        while q < n {
            xs[q] += b[3usize * (q - 1usize)]
            ys[q] += b[3usize * (q - 1usize) + 1usize]
            ths[q] = wrap_angle(ths[q] + b[3usize * (q - 1usize) + 2usize])
            q += 1usize
        }
        it += 1usize
    }
    ret (residual(xs, ys, ths, edges), ok)
}
