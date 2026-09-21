// Computer vision over `f64` images of `w * h` pixels (row-major, `y * w + x`)
// and caller storage: `harris_corners` (structure tensor under a Gaussian
// window, 3x3 non-maximum suppression), `hough_lines` (the line accumulator
// over `rho, theta` bins with 3x3 peaks), `homography` (normalised DLT) and
// `fundamental_matrix` (normalised eight-point with the rank-2 projection),
// `ransac` over caller callbacks, `phase_correlate` (2-d FFT, integer
// shift), `optical_flow_lk` (iterative Lucas-Kanade, one level) and
// `optical_flow_farneback` (quadratic expansion, one scale, one step),
// `icp` (point-to-point with brute-force matching and Kabsch), `orb`
// (FAST-9 with Harris ranking, intensity-centroid orientation, rBRIEF over
// the standard 256-pair pattern), `sift` (three octaves of DoG extrema, one
// orientation, the 4x4x8 descriptor), `calibrate_camera` (Zhang's
// closed-form intrinsics from planar views) and `structure_from_motion`
// (essential matrix, four poses, cheirality, linear triangulation).
//
// Reads outside an image replicate its edge. Every 3x3 matrix is nine
// row-major entries; `svd3` is the shared decomposition.

use e.algo.geom3
use e.algo.rand
use e.math
use e.math.fft
use e.math.filter
use e.ml.reduce

type Point = struct { x: f64, y: f64 }
type Keypoint = struct { x: f64, y: f64, angle: f64, response: f64, scale: f64 }
type Line = struct { rho: f64, theta: f64, votes: u32 }
error TooSmall
error Invalid

fn pi() -> f64 { ret 3.141592653589793f64 }

// ---- image helpers -------------------------------------------------------

fn clamp_index(v: i64, n: usize) -> usize {
    if v < 0i64 { ret 0usize }
    if v >= i64(n) { ret n - 1usize }
    ret usize(v)
}

// The pixel at (`x`, `y`) with the edge replicated outside the image.
fn pixel(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64 { ret img[clamp_index(y, h) * w + clamp_index(x, w)] }

// Bilinear interpolation at a real position.
fn bilinear(img: []const f64, w: usize, h: usize, x: f64, y: f64) -> f64 {
    let fx = math.floor[f64](x)
    let fy = math.floor[f64](y)
    let ix = i64(fx)
    let iy = i64(fy)
    let ax = x - fx
    let ay = y - fy
    let v00 = pixel(img, w, h, ix, iy)
    let v10 = pixel(img, w, h, ix + 1i64, iy)
    let v01 = pixel(img, w, h, ix, iy + 1i64)
    let v11 = pixel(img, w, h, ix + 1i64, iy + 1i64)
    ret (v00 * (1.0f64 - ax) + v10 * ax) * (1.0f64 - ay) + (v01 * (1.0f64 - ax) + v11 * ax) * ay
}

fn grad_x(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64 { ret (pixel(img, w, h, x + 1i64, y) - pixel(img, w, h, x - 1i64, y)) * 0.5f64 }
fn grad_y(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64 { ret (pixel(img, w, h, x, y + 1i64) - pixel(img, w, h, x, y - 1i64)) * 0.5f64 }

fn gaussian_radius(sigma: f64) -> usize {
    let r = math.ceil[f64](3.0f64 * sigma)
    if r < 1.0f64 { ret 1usize }
    if r > 63.0f64 { ret 63usize }
    ret usize(i64(r))
}

// Normalised 1-d Gaussian taps of radius `gaussian_radius(sigma)` into `kernel`.
fn gaussian_kernel(sigma: f64, kernel: []f64) -> usize {
    let r = gaussian_radius(sigma)
    var sum = 0.0f64
    var i = 0usize
    while i <= 2usize * r {
        let d = f64(i) - f64(r)
        kernel[i] = math.exp[f64](0.0f64 - d * d / (2.0f64 * sigma * sigma))
        sum += kernel[i]
        i += 1usize
    }
    i = 0usize
    while i <= 2usize * r {
        kernel[i] = kernel[i] / sum
        i += 1usize
    }
    ret r
}

// Separable Gaussian blur of `src` into `dst` (the two may be one image);
// `tmp.len >= w * h`.
fn gaussian_blur(src: []const f64, dst: []f64, w: usize, h: usize, sigma: f64, tmp: []f64) -> err {
    if src.len < w * h || dst.len < w * h || tmp.len < w * h { ret TooSmall }
    var kernel: [128]f64 = zero
    let r = gaussian_kernel(sigma, kernel[..])
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var sum = 0.0f64
            var k = 0usize
            while k <= 2usize * r {
                sum += kernel[k] * pixel(src, w, h, i64(x) + i64(k) - i64(r), i64(y))
                k += 1usize
            }
            tmp[y * w + x] = sum
            x += 1usize
        }
        y += 1usize
    }
    y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var sum = 0.0f64
            var k = 0usize
            while k <= 2usize * r {
                sum += kernel[k] * pixel(tmp, w, h, i64(x), i64(y) + i64(k) - i64(r))
                k += 1usize
            }
            dst[y * w + x] = sum
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// ---- Harris ----------------------------------------------------------------

// Harris corners: the structure tensor of central-difference gradients under
// a Gaussian window of `sigma`, response `det - k trace^2`, kept where it
// exceeds `threshold` and its eight neighbours; in raster order into `out`
// (`x`, `y`, `response`). `scratch.len >= w * h`.
fn harris_corners(img: []const f64, w: usize, h: usize, k: f64, sigma: f64, threshold: f64, out: []Keypoint, scratch: []f64) -> (usize, err) {
    if img.len < w * h || scratch.len < w * h { ret (0usize, TooSmall) }
    var kernel: [128]f64 = zero
    let r = gaussian_kernel(sigma, kernel[..])
    var response = scratch[..w * h]
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var sxx = 0.0f64
            var syy = 0.0f64
            var sxy = 0.0f64
            var v = 0usize
            while v <= 2usize * r {
                var u = 0usize
                while u <= 2usize * r {
                    let px = i64(x) + i64(u) - i64(r)
                    let py = i64(y) + i64(v) - i64(r)
                    let gx = grad_x(img, w, h, px, py)
                    let gy = grad_y(img, w, h, px, py)
                    let weight = kernel[u] * kernel[v]
                    sxx += weight * gx * gx
                    syy += weight * gy * gy
                    sxy += weight * gx * gy
                    u += 1usize
                }
                v += 1usize
            }
            let trace = sxx + syy
            response[y * w + x] = sxx * syy - sxy * sxy - k * trace * trace
            x += 1usize
        }
        y += 1usize
    }
    var count = 0usize
    y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let c = response[y * w + x]
            var best = c > threshold
            var dy = 0i64 - 1i64
            while dy <= 1i64 {
                var dx = 0i64 - 1i64
                while dx <= 1i64 {
                    if (dx != 0i64 || dy != 0i64) && pixel(response, w, h, i64(x) + dx, i64(y) + dy) >= c { best = false }
                    dx += 1i64
                }
                dy += 1i64
            }
            if best {
                if count >= out.len { ret (count, TooSmall) }
                out[count] = Keypoint { x: f64(x), y: f64(y), angle: 0.0f64, response: c, scale: sigma }
                count += 1usize
            }
            x += 1usize
        }
        y += 1usize
    }
    ret (count, ok)
}

// ---- Hough -----------------------------------------------------------------

// Lines through the `true` pixels of `edges`: `theta` takes `theta_bins`
// values from `-pi/2` in steps of `pi/theta_bins`, `rho = x cos + y sin` is
// binned over `[-diag, diag]` with `diag = ceil(hypot(w, h))` into
// `rho_bins` cells (`2 diag + 1` cells make unit steps). Cells of at least
// `threshold` votes that peak in their 3x3 neighbourhood go to `out` in
// raster order; `accumulator.len >= rho_bins * theta_bins`.
fn hough_lines(edges: []const bool, w: usize, h: usize, rho_bins: usize, theta_bins: usize, threshold: u32, accumulator: []u32, out: []Line) -> (usize, err) {
    if edges.len < w * h || accumulator.len < rho_bins * theta_bins { ret (0usize, TooSmall) }
    if rho_bins < 2usize || theta_bins < 1usize || threshold == 0u32 { ret (0usize, Invalid) }
    let diag = math.ceil[f64](math.sqrt[f64](f64(w * w + h * h)))
    let rho_step = 2.0f64 * diag / f64(rho_bins - 1usize)
    let theta_step = pi() / f64(theta_bins)
    var acc = accumulator[..rho_bins * theta_bins]
    var i = 0usize
    while i < acc.len {
        acc[i] = 0u32
        i += 1usize
    }
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            if edges[y * w + x] {
                var t = 0usize
                while t < theta_bins {
                    let theta = 0.0f64 - pi() * 0.5f64 + f64(t) * theta_step
                    let rho = f64(x) * math.cos[f64](theta) + f64(y) * math.sin[f64](theta)
                    let cell = clamp_index(i64(math.round[f64]((rho + diag) / rho_step)), rho_bins)
                    acc[cell * theta_bins + t] += 1u32
                    t += 1usize
                }
            }
            x += 1usize
        }
        y += 1usize
    }
    var count = 0usize
    var cell = 0usize
    while cell < rho_bins {
        var t = 0usize
        while t < theta_bins {
            let v = acc[cell * theta_bins + t]
            var peak = v >= threshold
            var dc = 0i64 - 1i64
            while dc <= 1i64 {
                var dt = 0i64 - 1i64
                while dt <= 1i64 {
                    let nc = i64(cell) + dc
                    let nt = i64(t) + dt
                    if (dc != 0i64 || dt != 0i64) && nc >= 0i64 && nc < i64(rho_bins) && nt >= 0i64 && nt < i64(theta_bins) {
                        let other = acc[usize(nc) * theta_bins + usize(nt)]
                        if dc < 0i64 || (dc == 0i64 && dt < 0i64) {
                            if other >= v { peak = false }
                        } else if other > v { peak = false }
                    }
                    dt += 1i64
                }
                dc += 1i64
            }
            if peak {
                if count >= out.len { ret (count, TooSmall) }
                out[count] = Line { rho: f64(cell) * rho_step - diag, theta: 0.0f64 - pi() * 0.5f64 + f64(t) * theta_step, votes: v }
                count += 1usize
            }
            t += 1usize
        }
        cell += 1usize
    }
    ret (count, ok)
}

// ---- 3x3 algebra -----------------------------------------------------------

fn mul3(a: []const f64, b: []const f64, out: []f64) { filter.mat_mul(a, b, out, 3usize, 3usize, 3usize) }

fn transpose3(a: []const f64, out: []f64) { filter.mat_transpose(a, out, 3usize, 3usize) }

fn det3(m: []const f64) -> f64 {
    ret m[0usize] * (m[4usize] * m[8usize] - m[5usize] * m[7usize]) - m[1usize] * (m[3usize] * m[8usize] - m[5usize] * m[6usize]) + m[2usize] * (m[3usize] * m[7usize] - m[4usize] * m[6usize])
}

// Scales `m` to unit Frobenius norm.
fn normalise_matrix(m: []f64) {
    var sum = 0.0f64
    var i = 0usize
    while i < m.len {
        sum += m[i] * m[i]
        i += 1usize
    }
    let norm = math.sqrt[f64](sum)
    if norm == 0.0f64 { ret }
    i = 0usize
    while i < m.len {
        m[i] = m[i] / norm
        i += 1usize
    }
}

// `m = u diag(s) v^T` for a 3x3 `m`: `v` from the eigenvectors of `m^T m`
// (falling `s`), `u` columns as `m v / s` with the third the cross product,
// both proper rotations. Needs `s[1] > 0`.
fn svd3(m: []const f64, u: []f64, s: []f64, v: []f64) -> err {
    if m.len < 9usize || u.len < 9usize || s.len < 3usize || v.len < 9usize { ret TooSmall }
    var mt: [9]f64 = zero
    var mtm: [9]f64 = zero
    transpose3(m, mt[..])
    mul3(mt[..], m, mtm[..])
    var values: [3]f64 = zero
    var rows: [9]f64 = zero
    let e = reduce.symmetric_eigen(mtm[..], 3usize, values[..], rows[..], 1.0e-30f64, 100u32)
    if e != ok { ret Invalid }
    var i = 0usize
    while i < 3usize {
        var lambda = values[i]
        if lambda < 0.0f64 { lambda = 0.0f64 }
        s[i] = math.sqrt[f64](lambda)
        i += 1usize
    }
    if s[1usize] <= 0.0f64 { ret Invalid }
    // v columns are the eigenvector rows; the third is the cross of the first two.
    v[0usize] = rows[0usize]
    v[3usize] = rows[1usize]
    v[6usize] = rows[2usize]
    v[1usize] = rows[3usize]
    v[4usize] = rows[4usize]
    v[7usize] = rows[5usize]
    v[2usize] = v[3usize] * v[7usize] - v[6usize] * v[4usize]
    v[5usize] = v[6usize] * v[1usize] - v[0usize] * v[7usize]
    v[8usize] = v[0usize] * v[4usize] - v[3usize] * v[1usize]
    var c = 0usize
    while c < 2usize {
        var r = 0usize
        while r < 3usize {
            u[r * 3usize + c] = (m[r * 3usize] * v[c] + m[r * 3usize + 1usize] * v[3usize + c] + m[r * 3usize + 2usize] * v[6usize + c]) / s[c]
            r += 1usize
        }
        c += 1usize
    }
    u[2usize] = u[3usize] * u[7usize] - u[6usize] * u[4usize]
    u[5usize] = u[6usize] * u[1usize] - u[0usize] * u[7usize]
    u[8usize] = u[0usize] * u[4usize] - u[3usize] * u[1usize]
    ret ok
}

// Hartley normalisation: the centroid and the scale that brings the mean
// distance to `sqrt 2`.
fn normalisation(points: []const Point, n: usize) -> (f64, f64, f64) {
    var cx = 0.0f64
    var cy = 0.0f64
    var i = 0usize
    while i < n {
        cx += points[i].x
        cy += points[i].y
        i += 1usize
    }
    cx = cx / f64(n)
    cy = cy / f64(n)
    var mean = 0.0f64
    i = 0usize
    while i < n {
        let dx = points[i].x - cx
        let dy = points[i].y - cy
        mean += math.sqrt[f64](dx * dx + dy * dy)
        i += 1usize
    }
    mean = mean / f64(n)
    var s = 1.0f64
    if mean > 0.0f64 { s = 1.4142135623730951f64 / mean }
    ret (cx, cy, s)
}

// The similarity `T = [[s, 0, -s cx], [0, s, -s cy], [0, 0, 1]]`.
fn similarity(cx: f64, cy: f64, s: f64, out: []f64) {
    out[0usize] = s
    out[1usize] = 0.0f64
    out[2usize] = 0.0f64 - s * cx
    out[3usize] = 0.0f64
    out[4usize] = s
    out[5usize] = 0.0f64 - s * cy
    out[6usize] = 0.0f64
    out[7usize] = 0.0f64
    out[8usize] = 1.0f64
}

// Adds `row row^T` (nine entries) into the 9x9 `ata`.
fn accumulate9(ata: []f64, row: []const f64) {
    var i = 0usize
    while i < 9usize {
        var j = 0usize
        while j < 9usize {
            ata[i * 9usize + j] += row[i] * row[j]
            j += 1usize
        }
        i += 1usize
    }
}

// ponytail: the normal equations square the condition number (residuals ~1e-8 in
// pixels); a direct SVD of A is the upgrade.
// The unit vector minimising `|A x|` given `A^T A` (9x9, destroyed).
fn null_vector9(ata: []f64, out: []f64) -> err {
    var values: [9]f64 = zero
    var vectors: [81]f64 = zero
    let e = reduce.symmetric_eigen(ata, 9usize, values[..], vectors[..], 1.0e-30f64, 100u32)
    if e != ok { ret Invalid }
    var i = 0usize
    while i < 9usize {
        out[i] = vectors[72usize + i]
        i += 1usize
    }
    ret ok
}

// ---- homography and fundamental matrix ----------------------------------

// The 3x3 `H` with `dst ~ H src` over `n >= 4` correspondences by the
// normalised DLT (the least eigenvector of `A^T A`), scaled to `H[8] = 1`.
fn homography(src: []const Point, dst: []const Point, out: []f64) -> err {
    let n = src.len
    if n < 4usize || dst.len < n { ret Invalid }
    if out.len < 9usize { ret TooSmall }
    let (scx, scy, ss) = normalisation(src, n)
    let (dcx, dcy, ds) = normalisation(dst, n)
    var ata: [81]f64 = zero
    var row: [9]f64 = zero
    var i = 0usize
    while i < n {
        let x = (src[i].x - scx) * ss
        let y = (src[i].y - scy) * ss
        let u = (dst[i].x - dcx) * ds
        let v = (dst[i].y - dcy) * ds
        row[0usize] = 0.0f64
        row[1usize] = 0.0f64
        row[2usize] = 0.0f64
        row[3usize] = 0.0f64 - x
        row[4usize] = 0.0f64 - y
        row[5usize] = 0.0f64 - 1.0f64
        row[6usize] = v * x
        row[7usize] = v * y
        row[8usize] = v
        accumulate9(ata[..], row[..])
        row[0usize] = x
        row[1usize] = y
        row[2usize] = 1.0f64
        row[3usize] = 0.0f64
        row[4usize] = 0.0f64
        row[5usize] = 0.0f64
        row[6usize] = 0.0f64 - u * x
        row[7usize] = 0.0f64 - u * y
        row[8usize] = 0.0f64 - u
        accumulate9(ata[..], row[..])
        i += 1usize
    }
    var hn: [9]f64 = zero
    let e = null_vector9(ata[..], hn[..])
    if e != ok { ret e }
    // H = T_dst^-1 H' T_src.
    var t_src: [9]f64 = zero
    var t_dst_inverse: [9]f64 = zero
    similarity(scx, scy, ss, t_src[..])
    similarity(0.0f64 - dcx * ds, 0.0f64 - dcy * ds, 1.0f64 / ds, t_dst_inverse[..])
    var tmp: [9]f64 = zero
    mul3(hn[..], t_src[..], tmp[..])
    mul3(t_dst_inverse[..], tmp[..], out[..9usize])
    if math.abs[f64](out[8usize]) < 1.0e-300f64 { ret Invalid }
    let scale_factor = 1.0f64 / out[8usize]
    i = 0usize
    while i < 9usize {
        out[i] = out[i] * scale_factor
        i += 1usize
    }
    ret ok
}

// Applies `H` to `p` (projective division).
fn apply_homography(hm: []const f64, p: Point) -> Point {
    let wv = hm[6usize] * p.x + hm[7usize] * p.y + hm[8usize]
    ret Point { x: (hm[0usize] * p.x + hm[1usize] * p.y + hm[2usize]) / wv, y: (hm[3usize] * p.x + hm[4usize] * p.y + hm[5usize]) / wv }
}

// The 3x3 `F` with `b^T F a = 0` over `n >= 8` correspondences by the
// normalised eight-point algorithm, projected to rank 2 and scaled to unit
// Frobenius norm.
fn fundamental_matrix(a: []const Point, b: []const Point, out: []f64) -> err {
    let n = a.len
    if n < 8usize || b.len < n { ret Invalid }
    if out.len < 9usize { ret TooSmall }
    let (acx, acy, as_) = normalisation(a, n)
    let (bcx, bcy, bs) = normalisation(b, n)
    var ata: [81]f64 = zero
    var row: [9]f64 = zero
    var i = 0usize
    while i < n {
        let x = (a[i].x - acx) * as_
        let y = (a[i].y - acy) * as_
        let u = (b[i].x - bcx) * bs
        let v = (b[i].y - bcy) * bs
        row[0usize] = u * x
        row[1usize] = u * y
        row[2usize] = u
        row[3usize] = v * x
        row[4usize] = v * y
        row[5usize] = v
        row[6usize] = x
        row[7usize] = y
        row[8usize] = 1.0f64
        accumulate9(ata[..], row[..])
        i += 1usize
    }
    var fn_: [9]f64 = zero
    let e = null_vector9(ata[..], fn_[..])
    if e != ok { ret e }
    // F = T_b^T F' T_a.
    var t_a: [9]f64 = zero
    var t_b: [9]f64 = zero
    var t_bt: [9]f64 = zero
    similarity(acx, acy, as_, t_a[..])
    similarity(bcx, bcy, bs, t_b[..])
    transpose3(t_b[..], t_bt[..])
    var tmp: [9]f64 = zero
    var f: [9]f64 = zero
    mul3(fn_[..], t_a[..], tmp[..])
    mul3(t_bt[..], tmp[..], f[..])
    // Rank 2: F (I - v v^T) with v the least right singular vector.
    var ft: [9]f64 = zero
    var ftf: [9]f64 = zero
    transpose3(f[..], ft[..])
    mul3(ft[..], f[..], ftf[..])
    var values: [3]f64 = zero
    var vectors: [9]f64 = zero
    if reduce.symmetric_eigen(ftf[..], 3usize, values[..], vectors[..], 1.0e-30f64, 100u32) != ok { ret Invalid }
    var fv: [3]f64 = zero
    var r = 0usize
    while r < 3usize {
        fv[r] = f[r * 3usize] * vectors[6usize] + f[r * 3usize + 1usize] * vectors[7usize] + f[r * 3usize + 2usize] * vectors[8usize]
        r += 1usize
    }
    r = 0usize
    while r < 3usize {
        var c = 0usize
        while c < 3usize {
            out[r * 3usize + c] = f[r * 3usize + c] - fv[r] * vectors[6usize + c]
            c += 1usize
        }
        r += 1usize
    }
    normalise_matrix(out[..9usize])
    ret ok
}

// `b^T F a` for one correspondence.
fn epipolar_residual(f: []const f64, a: Point, b: Point) -> f64 {
    let l0 = f[0usize] * a.x + f[1usize] * a.y + f[2usize]
    let l1 = f[3usize] * a.x + f[4usize] * a.y + f[5usize]
    let l2 = f[6usize] * a.x + f[7usize] * a.y + f[8usize]
    ret b.x * l0 + b.y * l1 + l2
}

// ---- RANSAC ----------------------------------------------------------------

// Random sample consensus over `n` items: `iterations` times a sample of
// `sample_size` distinct indices is fitted by `fit(ctx, indices)` (false
// rejects the sample) and scored by the count of `residual(ctx, i) <
// threshold`; the best sample is fitted again at the end, so the caller's
// model is the winner's, and `inliers` marks its consensus set. Answers the
// inlier count; `sample.len >= 2 * sample_size`.
fn ransac[Ctx: type](ctx: *Ctx, n: usize, sample_size: usize, iterations: u32, threshold: f64, fit: fn(*Ctx, []const usize) -> bool, residual: fn(*Ctx, usize) -> f64, r: *rand.Pcg64, inliers: []bool, sample: []usize) -> (usize, err) {
    if inliers.len < n || sample.len < 2usize * sample_size { ret (0usize, TooSmall) }
    if sample_size == 0usize || sample_size > n { ret (0usize, Invalid) }
    var current = sample[..sample_size]
    var best = sample[sample_size..2usize * sample_size]
    var best_count = 0usize
    var it = 0u32
    while it < iterations {
        var drawn = 0usize
        while drawn < sample_size {
            let candidate = usize(rand.pcg64_bounded(r, u64(n)))
            var seen = false
            var j = 0usize
            while j < drawn {
                if current[j] == candidate { seen = true }
                j += 1usize
            }
            if !seen {
                current[drawn] = candidate
                drawn += 1usize
            }
        }
        if fit(ctx, current) {
            var count = 0usize
            var i = 0usize
            while i < n {
                if residual(ctx, i) < threshold { count += 1usize }
                i += 1usize
            }
            if count > best_count {
                best_count = count
                i = 0usize
                while i < sample_size {
                    best[i] = current[i]
                    i += 1usize
                }
            }
        }
        it += 1u32
    }
    if best_count == 0usize { ret (0usize, Invalid) }
    let _ = fit(ctx, best)
    var i = 0usize
    while i < n {
        inliers[i] = residual(ctx, i) < threshold
        i += 1usize
    }
    ret (best_count, ok)
}

// ---- phase correlation -----------------------------------------------------

// In-place 2-d transform by rows then columns; `col.len >= 2 * h`.
fn fft2(re: []f64, im: []f64, w: usize, h: usize, inverse: bool, col: []f64) -> err {
    var y = 0usize
    while y < h {
        var e = ok
        if inverse { e = fft.ifft(re[y * w..y * w + w], im[y * w..y * w + w]) } else { e = fft.fft(re[y * w..y * w + w], im[y * w..y * w + w]) }
        if e != ok { ret e }
        y += 1usize
    }
    var cre = col[..h]
    var cim = col[h..2usize * h]
    var x = 0usize
    while x < w {
        y = 0usize
        while y < h {
            cre[y] = re[y * w + x]
            cim[y] = im[y * w + x]
            y += 1usize
        }
        var e = ok
        if inverse { e = fft.ifft(cre, cim) } else { e = fft.fft(cre, cim) }
        if e != ok { ret e }
        y = 0usize
        while y < h {
            re[y * w + x] = cre[y]
            im[y * w + x] = cim[y]
            y += 1usize
        }
        x += 1usize
    }
    ret ok
}

// ponytail: integer shift only; fit a parabola to the peak's neighbours for sub-pixel.
// The integer shift `(dx, dy)` with `b(x, y) ~ a(x - dx, y - dy)` (cyclic)
// by the normalised cross-power spectrum, and the peak's height; `w` and
// `h` are powers of two, `scratch.len >= 4 w h + 2 max(w, h)`.
fn phase_correlate(a: []const f64, b: []const f64, w: usize, h: usize, scratch: []f64) -> (f64, f64, f64, err) {
    let n = w * h
    var longest = w
    if h > longest { longest = h }
    if a.len < n || b.len < n || scratch.len < 4usize * n + 2usize * longest { ret (0.0f64, 0.0f64, 0.0f64, TooSmall) }
    var are = scratch[..n]
    var aim = scratch[n..2usize * n]
    var bre = scratch[2usize * n..3usize * n]
    var bim = scratch[3usize * n..4usize * n]
    var col = scratch[4usize * n..4usize * n + 2usize * longest]
    var i = 0usize
    while i < n {
        are[i] = a[i]
        aim[i] = 0.0f64
        bre[i] = b[i]
        bim[i] = 0.0f64
        i += 1usize
    }
    let ea = fft2(are, aim, w, h, false, col)
    if ea != ok { ret (0.0f64, 0.0f64, 0.0f64, ea) }
    let eb = fft2(bre, bim, w, h, false, col)
    if eb != ok { ret (0.0f64, 0.0f64, 0.0f64, eb) }
    i = 0usize
    while i < n {
        // A conj(B), normalised to unit magnitude.
        let re = are[i] * bre[i] + aim[i] * bim[i]
        let im = aim[i] * bre[i] - are[i] * bim[i]
        let mag = math.sqrt[f64](re * re + im * im)
        if mag > 1.0e-300f64 {
            are[i] = re / mag
            aim[i] = im / mag
        } else {
            are[i] = 0.0f64
            aim[i] = 0.0f64
        }
        i += 1usize
    }
    let ec = fft2(are, aim, w, h, true, col)
    if ec != ok { ret (0.0f64, 0.0f64, 0.0f64, ec) }
    var best = 0usize
    i = 1usize
    while i < n {
        if are[i] > are[best] { best = i }
        i += 1usize
    }
    var px = i64(best % w)
    var py = i64(best / w)
    if px > i64(w / 2usize) { px -= i64(w) }
    if py > i64(h / 2usize) { py -= i64(h) }
    ret (0.0f64 - f64(px), 0.0f64 - f64(py), are[best], ok)
}

// ---- optical flow ----------------------------------------------------------

// Lucas-Kanade at each of `points` between `a` and `b`: gradients of `a`
// over the `(2 window + 1)^2` patch, the temporal difference against `b`
// sampled bilinearly at the current displacement, `iterations` Gauss-Newton
// steps; `out[i]` is the displacement with `b(p + d) ~ a(p)` (zero where
// the patch has no texture).
fn optical_flow_lk(a: []const f64, b: []const f64, w: usize, h: usize, points: []const Point, window: usize, iterations: u32, out: []Point) -> err {
    if a.len < w * h || b.len < w * h { ret TooSmall }
    if out.len < points.len { ret TooSmall }
    var p = 0usize
    while p < points.len {
        let cx = i64(math.round[f64](points[p].x))
        let cy = i64(math.round[f64](points[p].y))
        var gxx = 0.0f64
        var gxy = 0.0f64
        var gyy = 0.0f64
        var v = 0i64 - i64(window)
        while v <= i64(window) {
            var u = 0i64 - i64(window)
            while u <= i64(window) {
                let gx = grad_x(a, w, h, cx + u, cy + v)
                let gy = grad_y(a, w, h, cx + u, cy + v)
                gxx += gx * gx
                gxy += gx * gy
                gyy += gy * gy
                u += 1i64
            }
            v += 1i64
        }
        var dx = 0.0f64
        var dy = 0.0f64
        let det = gxx * gyy - gxy * gxy
        if math.abs[f64](det) > 1.0e-12f64 {
            var it = 0u32
            while it < iterations {
                var bx = 0.0f64
                var by = 0.0f64
                v = 0i64 - i64(window)
                while v <= i64(window) {
                    var u = 0i64 - i64(window)
                    while u <= i64(window) {
                        let gx = grad_x(a, w, h, cx + u, cy + v)
                        let gy = grad_y(a, w, h, cx + u, cy + v)
                        let dt = bilinear(b, w, h, f64(cx + u) + dx, f64(cy + v) + dy) - pixel(a, w, h, cx + u, cy + v)
                        bx += gx * dt
                        by += gy * dt
                        u += 1i64
                    }
                    v += 1i64
                }
                dx -= (gyy * bx - gxy * by) / det
                dy -= (gxx * by - gxy * bx) / det
                it += 1u32
            }
        }
        out[p] = Point { x: dx, y: dy }
        p += 1usize
    }
    ret ok
}

// Quadratic expansion `f ~ c + b.x + x^T A x` of every pixel's
// `(2 window + 1)^2` neighbourhood (uniform weights, least squares); five
// coefficients per pixel into `coeff` as `bx, by, axx, ayy, axy`.
fn poly_expand(img: []const f64, w: usize, h: usize, window: usize, ginv: []const f64, coeff: []f64) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var rhs: [6]f64 = zero
            var v = 0i64 - i64(window)
            while v <= i64(window) {
                var u = 0i64 - i64(window)
                while u <= i64(window) {
                    let f = pixel(img, w, h, i64(x) + u, i64(y) + v)
                    let fu = f64(u)
                    let fv = f64(v)
                    rhs[0usize] += f
                    rhs[1usize] += f * fu
                    rhs[2usize] += f * fv
                    rhs[3usize] += f * fu * fu
                    rhs[4usize] += f * fv * fv
                    rhs[5usize] += f * fu * fv
                    u += 1i64
                }
                v += 1i64
            }
            var k = 1usize
            while k < 6usize {
                var sum = 0.0f64
                var j = 0usize
                while j < 6usize {
                    sum += ginv[k * 6usize + j] * rhs[j]
                    j += 1usize
                }
                coeff[(y * w + x) * 5usize + k - 1usize] = sum
                k += 1usize
            }
            x += 1usize
        }
        y += 1usize
    }
}

// ponytail: one scale, one step, uniform weights; a pyramid with warping is the upgrade.
// Farneback flow at one scale and one step: both images are expanded as
// quadratics over `(2 window + 1)^2` neighbourhoods, then each pixel solves
// `A d = delta b` with `A` and `delta b` averaged over the same window;
// `out[y * w + x]` is `d` with `b(p + d) ~ a(p)`. `scratch.len >= 10 w h`.
fn optical_flow_farneback(a: []const f64, b: []const f64, w: usize, h: usize, window: usize, out: []Point, scratch: []f64) -> err {
    let n = w * h
    if a.len < n || b.len < n || out.len < n || scratch.len < 10usize * n { ret TooSmall }
    if window == 0usize { ret Invalid }
    // The normal matrix of the basis 1, x, y, x^2, y^2, xy over the window.
    var g: [36]f64 = zero
    var v = 0i64 - i64(window)
    while v <= i64(window) {
        var u = 0i64 - i64(window)
        while u <= i64(window) {
            let basis = [6]f64{ 1.0f64, f64(u), f64(v), f64(u) * f64(u), f64(v) * f64(v), f64(u) * f64(v) }
            var i = 0usize
            while i < 6usize {
                var j = 0usize
                while j < 6usize {
                    g[i * 6usize + j] += basis[i] * basis[j]
                    j += 1usize
                }
                i += 1usize
            }
            u += 1i64
        }
        v += 1i64
    }
    var ginv: [36]f64 = zero
    var work: [36]f64 = zero
    if filter.mat_inverse(g[..], ginv[..], 6usize, work[..]) != ok { ret Invalid }
    var ca = scratch[..5usize * n]
    var cb = scratch[5usize * n..10usize * n]
    poly_expand(a, w, h, window, ginv[..], ca)
    poly_expand(b, w, h, window, ginv[..], cb)
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var m00 = 0.0f64
            var m01 = 0.0f64
            var m11 = 0.0f64
            var r0 = 0.0f64
            var r1 = 0.0f64
            v = 0i64 - i64(window)
            while v <= i64(window) {
                var u = 0i64 - i64(window)
                while u <= i64(window) {
                    let q = (clamp_index(i64(y) + v, h) * w + clamp_index(i64(x) + u, w)) * 5usize
                    let axx = (ca[q + 2usize] + cb[q + 2usize]) * 0.5f64
                    let ayy = (ca[q + 3usize] + cb[q + 3usize]) * 0.5f64
                    let axy = (ca[q + 4usize] + cb[q + 4usize]) * 0.25f64
                    let dbx = 0.0f64 - (cb[q] - ca[q]) * 0.5f64
                    let dby = 0.0f64 - (cb[q + 1usize] - ca[q + 1usize]) * 0.5f64
                    m00 += axx * axx + axy * axy
                    m01 += axx * axy + axy * ayy
                    m11 += axy * axy + ayy * ayy
                    r0 += axx * dbx + axy * dby
                    r1 += axy * dbx + ayy * dby
                    u += 1i64
                }
                v += 1i64
            }
            let det = m00 * m11 - m01 * m01
            var dx = 0.0f64
            var dy = 0.0f64
            if math.abs[f64](det) > 1.0e-12f64 {
                dx = (m11 * r0 - m01 * r1) / det
                dy = (m00 * r1 - m01 * r0) / det
            }
            out[y * w + x] = Point { x: dx, y: dy }
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// ---- ICP -------------------------------------------------------------------

// ponytail: O(|p| |q|) matching per round; a k-d tree (e.data.spatial) when clouds grow.
// Iterative closest point: `iterations` rounds of matching every moved `p`
// to its nearest `q` (brute force) and re-solving `q ~ R p + t` by Kabsch.
// `rotation` receives the nine entries of `R`; answers `t` and the mean
// squared distance of the final matching; `matched.len >= p.len`.
fn icp(p: []const geom3.Vec3, q: []const geom3.Vec3, iterations: u32, rotation: []f64, matched: []geom3.Vec3) -> (geom3.Vec3, f64, err) {
    if p.len == 0usize || q.len == 0usize { ret (zero, 0.0f64, Invalid) }
    if rotation.len < 9usize || matched.len < p.len { ret (zero, 0.0f64, TooSmall) }
    var i = 0usize
    while i < 9usize {
        rotation[i] = 0.0f64
        i += 1usize
    }
    rotation[0usize] = 1.0f64
    rotation[4usize] = 1.0f64
    rotation[8usize] = 1.0f64
    var translation = geom3.vec3(0.0f64, 0.0f64, 0.0f64)
    var it = 0u32
    while it < iterations {
        i = 0usize
        while i < p.len {
            let moved = geom3.add(geom3.rotate(rotation, p[i]), translation)
            var best = 0usize
            var best_distance = geom3.dot(geom3.sub(moved, q[0usize]), geom3.sub(moved, q[0usize]))
            var j = 1usize
            while j < q.len {
                let d = geom3.dot(geom3.sub(moved, q[j]), geom3.sub(moved, q[j]))
                if d < best_distance {
                    best_distance = d
                    best = j
                }
                j += 1usize
            }
            matched[i] = q[best]
            i += 1usize
        }
        let (t, e) = geom3.kabsch(p, matched[..p.len], rotation)
        if e != ok { ret (zero, 0.0f64, e) }
        translation = t
        it += 1u32
    }
    var error_sum = 0.0f64
    i = 0usize
    while i < p.len {
        let d = geom3.sub(geom3.add(geom3.rotate(rotation, p[i]), translation), matched[i])
        error_sum += geom3.dot(d, d)
        i += 1usize
    }
    ret (translation, error_sum / f64(p.len), ok)
}

// ---- ORB -------------------------------------------------------------------

// The 256 rBRIEF pairs (`x0 y0 x1 y1` each, offset by 64) from the standard
// `bit_pattern_31_` list.
fn orb_pattern() -> str { ret "H=IEDBG45I8BG4L3B3BLA9AF>6><33583=47JDKI38875G7LGGLF<;=@3B4=7@9EL:L?=F>L:3<8K3L8DGEAE=J=C9FL89:>>K?63L8J9C;=<B=G64:KE4F9E:G?A@D;IKK3DGDLB?DD<4>G8;96DKIL@8A33>8B=>>C:I<7HLJG@IACG;K63:5@JGLA:=:LJ7L<3H843@8<CCGHEGJ9?GA4C6EFB<C63@3E394L3C5H9L<GF6LH7?9:>;@L4E9EC6H399<E=>?9BIE553;3?F@?E=EB<3<L7:7F468<JBL=GLLL93:E<I=DG?LB9F;A3K4E=G>:G8L93954A=LLB:C@<C>3?3AIGAH:A?CLIALF?7?C336EGGJLL;LIFCGKE3FJB4BCCHD:BFL3I4JC8D9I5L<:ALB8F7G<BCC>FCK@C=H8GHIC5;:<6K;J;8=L6E7@H?L:D:F56L8GD>FG>@>L;8;BG:JL7388;3;>H8I3757@A8A>G<IA>A?<K:L547:DCGGLEEJH@<BH7L;3@GBL?BAGEKG7CEF83<8I;I==<9=4FEH@9F:L3F;>A6CJDAH<>>B3B4LL>3@:DAIC:6=;=3?AGEL5D>E93I7;GAHFG8GF9<9A8K983F48BDCIJ;LC:;:GH=I8B4BH5>6C43975@6;E=KH>3?L?8@I354;6>6K=I>3B=CB73<@<F=6<L>9:5<IF=FK3K;EKKLFG;L>?L@G<8=>9A:G34839>:88E:7;?<E3G8JAEE3A@J3ILJ?E8J7?KA37=:B?6AL3A86H5J:B3C:G3L766;96883D:HECLH3<B==E3J4D3E?7I<C@CC74A:ACBD8666IH3LL84:;BBCGJFK8FHH49J:E=7=I?3?E=9=D8>8CDBLLB;CKF7K3C?GLK?LD=@=FD5DLB<BA6:8A3G5A3L53F@K3@?AD3C7>7H:=3:8>E7HJBGC7?:??IEK>K=L8C@CE?D@JC:DE3@6EEHLKHII:G<H46D6IGCLDI9J>G@L>?:@5" }

fn pattern_entry(i: usize) -> i64 { ret i64(orb_pattern()[i]) - 64i64 }

fn fast_offset(i: usize) -> (i64, i64) {
    let xs = [16]i64{ 0i64, 1i64, 2i64, 3i64, 3i64, 3i64, 2i64, 1i64, 0i64, 0i64 - 1i64, 0i64 - 2i64, 0i64 - 3i64, 0i64 - 3i64, 0i64 - 3i64, 0i64 - 2i64, 0i64 - 1i64 }
    let ys = [16]i64{ 0i64 - 3i64, 0i64 - 3i64, 0i64 - 2i64, 0i64 - 1i64, 0i64, 1i64, 2i64, 3i64, 3i64, 3i64, 2i64, 1i64, 0i64, 0i64 - 1i64, 0i64 - 2i64, 0i64 - 3i64 }
    ret (xs[i], ys[i])
}

// FAST-9: nine contiguous pixels of the 16-pixel circle all brighter than
// `centre + threshold` or all darker than `centre - threshold`.
fn fast9(img: []const f64, w: usize, h: usize, x: i64, y: i64, threshold: f64) -> bool {
    let centre = pixel(img, w, h, x, y)
    var bright = 0usize
    var dark = 0usize
    var i = 0usize
    while i < 24usize {
        let (ox, oy) = fast_offset(i % 16usize)
        let v = pixel(img, w, h, x + ox, y + oy)
        if v > centre + threshold { bright += 1usize } else { bright = 0usize }
        if v < centre - threshold { dark += 1usize } else { dark = 0usize }
        if bright >= 9usize || dark >= 9usize { ret true }
        i += 1usize
    }
    ret false
}

// Harris response over the 7x7 block around a pixel, `k = 0.04`.
fn harris7(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64 {
    var sxx = 0.0f64
    var syy = 0.0f64
    var sxy = 0.0f64
    var v = 0i64 - 3i64
    while v <= 3i64 {
        var u = 0i64 - 3i64
        while u <= 3i64 {
            let gx = grad_x(img, w, h, x + u, y + v)
            let gy = grad_y(img, w, h, x + u, y + v)
            sxx += gx * gx
            syy += gy * gy
            sxy += gx * gy
            u += 1i64
        }
        v += 1i64
    }
    let trace = sxx + syy
    ret sxx * syy - sxy * sxy - 0.04f64 * trace * trace
}

// The intensity-centroid orientation over the disc of radius 15.
fn centroid_angle(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64 {
    var m01 = 0.0f64
    var m10 = 0.0f64
    var v = 0i64 - 15i64
    while v <= 15i64 {
        var u = 0i64 - 15i64
        while u <= 15i64 {
            if u * u + v * v <= 225i64 {
                let p = pixel(img, w, h, x + u, y + v)
                m10 += f64(u) * p
                m01 += f64(v) * p
            }
            u += 1i64
        }
        v += 1i64
    }
    ret math.atan2[f64](m01, m10)
}

// The 32-byte rBRIEF descriptor at (`x`, `y`) with the pattern rotated by
// `angle`; bit `i` of byte `k` is `p0 < p1` of pair `8 k + i`.
fn brief(img: []const f64, w: usize, h: usize, x: i64, y: i64, angle: f64, out: []u8) {
    let c = math.cos[f64](angle)
    let s = math.sin[f64](angle)
    var k = 0usize
    while k < 32usize {
        var byte = 0u32
        var i = 0usize
        while i < 8usize {
            let pair = (8usize * k + i) * 4usize
            let x0 = f64(pattern_entry(pair))
            let y0 = f64(pattern_entry(pair + 1usize))
            let x1 = f64(pattern_entry(pair + 2usize))
            let y1 = f64(pattern_entry(pair + 3usize))
            let p0 = pixel(img, w, h, x + i64(math.round[f64](x0 * c - y0 * s)), y + i64(math.round[f64](x0 * s + y0 * c)))
            let p1 = pixel(img, w, h, x + i64(math.round[f64](x1 * c - y1 * s)), y + i64(math.round[f64](x1 * s + y1 * c)))
            if p0 < p1 { byte |= 1u32 << u32(i) }
            i += 1usize
        }
        out[k] = u8(byte & 255u32)
        k += 1usize
    }
}

// ponytail: one scale, no pyramid; recompute over downsampled levels for scale invariance.
// ORB: FAST-9 corners (`threshold` on intensity) at least 22 pixels from
// the border, scored by the 7x7 Harris response and suppressed by their
// 3x3 neighbours, the best `out.len` kept by falling response (`angle` by
// the intensity centroid, `scale` 1) with 32 descriptor bytes each in
// `descriptors`; answers the count.
fn orb(img: []const f64, w: usize, h: usize, threshold: f64, out: []Keypoint, descriptors: []u8) -> (usize, err) {
    if img.len < w * h || descriptors.len < 32usize * out.len { ret (0usize, TooSmall) }
    if w < 45usize || h < 45usize { ret (0usize, Invalid) }
    var count = 0usize
    var y = 22i64
    while y < i64(h) - 22i64 {
        var x = 22i64
        while x < i64(w) - 22i64 {
            if fast9(img, w, h, x, y, threshold) {
                let response = harris7(img, w, h, x, y)
                var best = true
                var dy = 0i64 - 1i64
                while dy <= 1i64 {
                    var dx = 0i64 - 1i64
                    while dx <= 1i64 {
                        if (dx != 0i64 || dy != 0i64) && fast9(img, w, h, x + dx, y + dy, threshold) {
                            let other = harris7(img, w, h, x + dx, y + dy)
                            if dy < 0i64 || (dy == 0i64 && dx < 0i64) {
                                if other >= response { best = false }
                            } else if other > response { best = false }
                        }
                        dx += 1i64
                    }
                    dy += 1i64
                }
                if best && out.len > 0usize && (count < out.len || response > out[count - 1usize].response) {
                    // Insert by falling response, dropping the tail when full.
                    var slot = count
                    if slot == out.len { slot -= 1usize }
                    while slot > 0usize && out[slot - 1usize].response < response {
                        out[slot] = out[slot - 1usize]
                        slot -= 1usize
                    }
                    out[slot] = Keypoint { x: f64(x), y: f64(y), angle: 0.0f64, response: response, scale: 1.0f64 }
                    if count < out.len { count += 1usize }
                }
            }
            x += 1i64
        }
        y += 1i64
    }
    var i = 0usize
    while i < count {
        let kx = i64(out[i].x)
        let ky = i64(out[i].y)
        let angle = centroid_angle(img, w, h, kx, ky)
        out[i].angle = angle
        brief(img, w, h, kx, ky, angle, descriptors[i * 32usize..i * 32usize + 32usize])
        i += 1usize
    }
    ret (count, ok)
}

// The Hamming distance of two 32-byte descriptors.
fn hamming(a: []const u8, b: []const u8) -> u32 {
    var d = 0u32
    var i = 0usize
    while i < 32usize {
        var x = u32(a[i] ^ b[i])
        while x != 0u32 {
            d += 1u32
            x &= x - 1u32
        }
        i += 1usize
    }
    ret d
}

// ---- SIFT ------------------------------------------------------------------

fn sift_sigma(level: usize) -> f64 { ret 1.6f64 * math.pow[f64](2.0f64, f64(level) / 3.0f64) }

fn wrap_angle(a: f64) -> f64 {
    if a < 0.0f64 { ret a + 2.0f64 * pi() }
    ret a
}

// The dominant gradient orientation (radians in `[0, 2 pi)`) around (`x`,
// `y`) in `img`: a 36-bin histogram weighted by a Gaussian of `1.5 sigma`
// over radius `3 * 1.5 sigma`, smoothed once, the peak refined by a parabola.
fn sift_orientation(img: []const f64, w: usize, h: usize, x: i64, y: i64, sigma: f64) -> f64 {
    let sig = 1.5f64 * sigma
    let radius = i64(math.round[f64](3.0f64 * sig))
    var raw: [36]f64 = zero
    var v = 0i64 - radius
    while v <= radius {
        var u = 0i64 - radius
        while u <= radius {
            let dx = pixel(img, w, h, x + u + 1i64, y + v) - pixel(img, w, h, x + u - 1i64, y + v)
            let dy = pixel(img, w, h, x + u, y + v - 1i64) - pixel(img, w, h, x + u, y + v + 1i64)
            let weight = math.exp[f64](0.0f64 - f64(u * u + v * v) / (2.0f64 * sig * sig))
            let magnitude = math.sqrt[f64](dx * dx + dy * dy)
            let ori = wrap_angle(math.atan2[f64](dy, dx))
            var bin = i64(math.round[f64](36.0f64 * ori / (2.0f64 * pi())))
            if bin >= 36i64 { bin -= 36i64 }
            if bin < 0i64 { bin += 36i64 }
            raw[usize(bin)] += weight * magnitude
            u += 1i64
        }
        v += 1i64
    }
    var hist: [36]f64 = zero
    var i = 0usize
    while i < 36usize {
        hist[i] = (raw[(i + 34usize) % 36usize] + raw[(i + 2usize) % 36usize]) / 16.0f64 + (raw[(i + 35usize) % 36usize] + raw[(i + 1usize) % 36usize]) * 4.0f64 / 16.0f64 + raw[i] * 6.0f64 / 16.0f64
        i += 1usize
    }
    var best = 0usize
    i = 1usize
    while i < 36usize {
        if hist[i] > hist[best] { best = i }
        i += 1usize
    }
    let l = hist[(best + 35usize) % 36usize]
    let r = hist[(best + 1usize) % 36usize]
    let c = hist[best]
    var bin = f64(best)
    let denominator = l - 2.0f64 * c + r
    if denominator != 0.0f64 { bin += 0.5f64 * (l - r) / denominator }
    if bin < 0.0f64 { bin += 36.0f64 }
    if bin >= 36.0f64 { bin -= 36.0f64 }
    ret bin * 2.0f64 * pi() / 36.0f64
}

// The 4x4x8 descriptor at (`x`, `y`) of `img` for orientation `ori` and
// scale `sigma` (bins `3 sigma` apart), trilinearly binned, Gaussian
// weighted, normalised, clipped at 0.2 and renormalised; 128 entries.
fn sift_descriptor(img: []const f64, w: usize, h: usize, x: i64, y: i64, ori: f64, sigma: f64, out: []f64) {
    let hist_width = 3.0f64 * sigma
    let cos_t = math.cos[f64](ori) / hist_width
    let sin_t = math.sin[f64](ori) / hist_width
    let bins_per_rad = 8.0f64 / (2.0f64 * pi())
    let exp_scale = 0.0f64 - 1.0f64 / 8.0f64
    let radius = i64(math.round[f64](hist_width * 1.4142135623730951f64 * 2.5f64))
    var hist: [360]f64 = zero
    var i = 0i64 - radius
    while i <= radius {
        var j = 0i64 - radius
        while j <= radius {
            let c_rot = f64(j) * cos_t - f64(i) * sin_t
            let r_rot = f64(j) * sin_t + f64(i) * cos_t
            var rbin = r_rot + 1.5f64
            var cbin = c_rot + 1.5f64
            if rbin > 0.0f64 - 1.0f64 && rbin < 4.0f64 && cbin > 0.0f64 - 1.0f64 && cbin < 4.0f64 {
                let dx = pixel(img, w, h, x + j + 1i64, y + i) - pixel(img, w, h, x + j - 1i64, y + i)
                let dy = pixel(img, w, h, x + j, y + i - 1i64) - pixel(img, w, h, x + j, y + i + 1i64)
                let weight = math.exp[f64]((c_rot * c_rot + r_rot * r_rot) * exp_scale)
                let magnitude = math.sqrt[f64](dx * dx + dy * dy) * weight
                var obin = (wrap_angle(math.atan2[f64](dy, dx)) - ori) * bins_per_rad
                let r0 = math.floor[f64](rbin)
                let c0 = math.floor[f64](cbin)
                let o0f = math.floor[f64](obin)
                rbin -= r0
                cbin -= c0
                obin -= o0f
                var o0 = i64(o0f)
                if o0 < 0i64 { o0 += 8i64 }
                if o0 >= 8i64 { o0 -= 8i64 }
                let v_r1 = magnitude * rbin
                let v_r0 = magnitude - v_r1
                let v_rc11 = v_r1 * cbin
                let v_rc10 = v_r1 - v_rc11
                let v_rc01 = v_r0 * cbin
                let v_rc00 = v_r0 - v_rc01
                let v_rco111 = v_rc11 * obin
                let v_rco110 = v_rc11 - v_rco111
                let v_rco101 = v_rc10 * obin
                let v_rco100 = v_rc10 - v_rco101
                let v_rco011 = v_rc01 * obin
                let v_rco010 = v_rc01 - v_rco011
                let v_rco001 = v_rc00 * obin
                let v_rco000 = v_rc00 - v_rco001
                let idx = usize((i64(r0) + 1i64) * 60i64 + (i64(c0) + 1i64) * 10i64 + o0)
                hist[idx] += v_rco000
                hist[idx + 1usize] += v_rco001
                hist[idx + 10usize] += v_rco010
                hist[idx + 11usize] += v_rco011
                hist[idx + 60usize] += v_rco100
                hist[idx + 61usize] += v_rco101
                hist[idx + 70usize] += v_rco110
                hist[idx + 71usize] += v_rco111
            }
            j += 1i64
        }
        i += 1i64
    }
    var r = 0usize
    while r < 4usize {
        var c = 0usize
        while c < 4usize {
            let idx = ((r + 1usize) * 6usize + c + 1usize) * 10usize
            hist[idx] += hist[idx + 8usize]
            hist[idx + 1usize] += hist[idx + 9usize]
            var k = 0usize
            while k < 8usize {
                out[(r * 4usize + c) * 8usize + k] = hist[idx + k]
                k += 1usize
            }
            c += 1usize
        }
        r += 1usize
    }
    var sum = 0.0f64
    var k = 0usize
    while k < 128usize {
        sum += out[k] * out[k]
        k += 1usize
    }
    let limit = math.sqrt[f64](sum) * 0.2f64
    sum = 0.0f64
    k = 0usize
    while k < 128usize {
        if out[k] > limit { out[k] = limit }
        sum += out[k] * out[k]
        k += 1usize
    }
    var norm = math.sqrt[f64](sum)
    if norm == 0.0f64 { norm = 1.0f64 }
    k = 0usize
    while k < 128usize {
        out[k] = out[k] / norm
        k += 1usize
    }
}

// ponytail: no sub-pixel refinement, no secondary orientations, three octaves;
// add the 3-d quadratic fit and the 80% peaks when matching precision matters.
// Reduced SIFT: three octaves of six Gaussian levels (`sigma = 1.6 * 2^(i/3)`
// from an assumed input blur of 0.5, no upsampling) and five differences;
// extrema of the middle three DoG levels against their 26 neighbours with
// `|DoG| > threshold` and a principal-curvature ratio under 10, at integer
// positions (no sub-pixel refinement), one orientation each. Keypoints hold
// image coordinates, `scale` the absolute sigma and `response` the DoG value;
// `descriptors` receives 128 entries per keypoint. `scratch.len >= 12 w h`.
fn sift(img: []const f64, w: usize, h: usize, threshold: f64, out: []Keypoint, descriptors: []f64, scratch: []f64) -> (usize, err) {
    if img.len < w * h || scratch.len < 12usize * w * h || descriptors.len < 128usize * out.len { ret (0usize, TooSmall) }
    if w < 8usize || h < 8usize { ret (0usize, Invalid) }
    var count = 0usize
    var octave = 0usize
    var ow = w
    var oh = h
    while octave < 3usize {
        let n = ow * oh
        var tmp = scratch[11usize * n..12usize * n]
        if octave == 0usize {
            let base_sigma = math.sqrt[f64](1.6f64 * 1.6f64 - 0.25f64)
            let e = gaussian_blur(img, scratch[..n], ow, oh, base_sigma, tmp)
            if e != ok { ret (count, e) }
        } else {
            // Octave 0 is level 3 of the previous octave, every other pixel.
            let pw = ow * 2usize
            let pn = pw * oh * 2usize
            var yy = 0usize
            while yy < oh {
                var xx = 0usize
                while xx < ow {
                    scratch[yy * ow + xx] = scratch[3usize * pn + (2usize * yy) * pw + 2usize * xx]
                    xx += 1usize
                }
                yy += 1usize
            }
        }
        var level = 1usize
        while level < 6usize {
            let s_prev = sift_sigma(level - 1usize)
            let s_next = sift_sigma(level)
            let e = gaussian_blur(scratch[(level - 1usize) * n..level * n], scratch[level * n..(level + 1usize) * n], ow, oh, math.sqrt[f64](s_next * s_next - s_prev * s_prev), tmp)
            if e != ok { ret (count, e) }
            level += 1usize
        }
        level = 0usize
        while level < 5usize {
            var i = 0usize
            while i < n {
                scratch[(6usize + level) * n + i] = scratch[(level + 1usize) * n + i] - scratch[level * n + i]
                i += 1usize
            }
            level += 1usize
        }
        level = 1usize
        while level < 4usize {
            var dog = scratch[(6usize + level) * n..(7usize + level) * n]
            var y = 1usize
            while y + 1usize < oh {
                var x = 1usize
                while x + 1usize < ow {
                    let d = dog[y * ow + x]
                    if math.abs[f64](d) > threshold {
                        var maximum = true
                        var minimum = true
                        var dl = 0i64 - 1i64
                        while dl <= 1i64 {
                            var dy = 0i64 - 1i64
                            while dy <= 1i64 {
                                var dx = 0i64 - 1i64
                                while dx <= 1i64 {
                                    if dl != 0i64 || dy != 0i64 || dx != 0i64 {
                                        let other = scratch[usize(i64(6usize + level) + dl) * n + usize(i64(y) + dy) * ow + usize(i64(x) + dx)]
                                        if other >= d { maximum = false }
                                        if other <= d { minimum = false }
                                    }
                                    dx += 1i64
                                }
                                dy += 1i64
                            }
                            dl += 1i64
                        }
                        if maximum || minimum {
                            let dxx = dog[y * ow + x + 1usize] + dog[y * ow + x - 1usize] - 2.0f64 * d
                            let dyy = dog[(y + 1usize) * ow + x] + dog[(y - 1usize) * ow + x] - 2.0f64 * d
                            let dxy = (dog[(y + 1usize) * ow + x + 1usize] - dog[(y + 1usize) * ow + x - 1usize] - dog[(y - 1usize) * ow + x + 1usize] + dog[(y - 1usize) * ow + x - 1usize]) * 0.25f64
                            let tr = dxx + dyy
                            let det = dxx * dyy - dxy * dxy
                            if det > 0.0f64 && tr * tr * 10.0f64 < 121.0f64 * det {
                                if count >= out.len { ret (count, TooSmall) }
                                let sigma = sift_sigma(level)
                                let gauss = scratch[level * n..(level + 1usize) * n]
                                let angle = sift_orientation(gauss, ow, oh, i64(x), i64(y), sigma)
                                sift_descriptor(gauss, ow, oh, i64(x), i64(y), angle, sigma, descriptors[count * 128usize..count * 128usize + 128usize])
                                let factor = f64(1usize << u32(octave))
                                out[count] = Keypoint { x: f64(x) * factor, y: f64(y) * factor, angle: angle, response: d, scale: sigma * factor }
                                count += 1usize
                            }
                        }
                    }
                    x += 1usize
                }
                y += 1usize
            }
            level += 1usize
        }
        ow = ow / 2usize
        oh = oh / 2usize
        if ow < 8usize || oh < 8usize { ret (count, ok) }
        octave += 1usize
    }
    ret (count, ok)
}

// ---- camera calibration ----------------------------------------------------

// `v_ij` of Zhang's constraint from the columns `i`, `j` of `H`.
fn zhang_row(hm: []const f64, i: usize, j: usize, out: []f64) {
    let h1i = hm[i]
    let h2i = hm[3usize + i]
    let h3i = hm[6usize + i]
    let h1j = hm[j]
    let h2j = hm[3usize + j]
    let h3j = hm[6usize + j]
    out[0usize] = h1i * h1j
    out[1usize] = h1i * h2j + h2i * h1j
    out[2usize] = h2i * h2j
    out[3usize] = h3i * h1j + h1i * h3j
    out[4usize] = h3i * h2j + h2i * h3j
    out[5usize] = h3i * h3j
}

// Zhang's calibration: the planar `model` points (`m` of them, `z = 0`)
// are seen in `views` images whose `image` points come `m` per view; a
// homography per view constrains the image of the absolute conic, whose
// least eigenvector gives the intrinsics `K` (nine entries: `fx, skew, cx;
// 0, fy, cy; 0, 0, 1`) in closed form. Needs at least three views and no
// distortion.
fn calibrate_camera(model: []const Point, image: []const Point, views: usize, out: []f64) -> err {
    let m = model.len
    if views < 3usize || m < 4usize || image.len < views * m { ret Invalid }
    if out.len < 9usize { ret TooSmall }
    var vtv: [36]f64 = zero
    var hm: [9]f64 = zero
    var v12: [6]f64 = zero
    var v11: [6]f64 = zero
    var v22: [6]f64 = zero
    var view = 0usize
    while view < views {
        let e = homography(model, image[view * m..(view + 1usize) * m], hm[..])
        if e != ok { ret e }
        zhang_row(hm[..], 0usize, 1usize, v12[..])
        zhang_row(hm[..], 0usize, 0usize, v11[..])
        zhang_row(hm[..], 1usize, 1usize, v22[..])
        var i = 0usize
        while i < 6usize {
            v11[i] -= v22[i]
            i += 1usize
        }
        i = 0usize
        while i < 6usize {
            var j = 0usize
            while j < 6usize {
                vtv[i * 6usize + j] += v12[i] * v12[j] + v11[i] * v11[j]
                j += 1usize
            }
            i += 1usize
        }
        view += 1usize
    }
    var values: [6]f64 = zero
    var vectors: [36]f64 = zero
    if reduce.symmetric_eigen(vtv[..], 6usize, values[..], vectors[..], 1.0e-30f64, 100u32) != ok { ret Invalid }
    let b11 = vectors[30usize]
    let b12 = vectors[31usize]
    let b22 = vectors[32usize]
    let b13 = vectors[33usize]
    let b23 = vectors[34usize]
    let b33 = vectors[35usize]
    let denominator = b11 * b22 - b12 * b12
    if denominator == 0.0f64 || b11 == 0.0f64 { ret Invalid }
    let v0 = (b12 * b13 - b11 * b23) / denominator
    let lambda = b33 - (b13 * b13 + v0 * (b12 * b13 - b11 * b23)) / b11
    let alpha_sq = lambda / b11
    let beta_sq = lambda * b11 / denominator
    if alpha_sq <= 0.0f64 || beta_sq <= 0.0f64 { ret Invalid }
    let alpha = math.sqrt[f64](alpha_sq)
    let beta = math.sqrt[f64](beta_sq)
    let gamma = 0.0f64 - b12 * alpha_sq * beta / lambda
    let u0 = gamma * v0 / beta - b13 * alpha_sq / lambda
    out[0usize] = alpha
    out[1usize] = gamma
    out[2usize] = u0
    out[3usize] = 0.0f64
    out[4usize] = beta
    out[5usize] = v0
    out[6usize] = 0.0f64
    out[7usize] = 0.0f64
    out[8usize] = 1.0f64
    ret ok
}

// ---- structure from motion -------------------------------------------------

// Linear triangulation in normalised coordinates of `a` (camera `[I | 0]`)
// and `b` (camera `[R | t]`): the least eigenvector of the 4x4 `A^T A`.
fn triangulate(rotation: []const f64, t: []const f64, a: Point, b: Point) -> (geom3.Vec3, bool) {
    var ata: [16]f64 = zero
    var row: [4]f64 = zero
    var k = 0usize
    while k < 4usize {
        // Rows: a.x P1_2 - P1_0, a.y P1_2 - P1_1, b.x P2_2 - P2_0, b.y P2_2 - P2_1.
        if k == 0usize {
            row[0usize] = 0.0f64 - 1.0f64
            row[1usize] = 0.0f64
            row[2usize] = a.x
            row[3usize] = 0.0f64
        } else if k == 1usize {
            row[0usize] = 0.0f64
            row[1usize] = 0.0f64 - 1.0f64
            row[2usize] = a.y
            row[3usize] = 0.0f64
        } else if k == 2usize {
            row[0usize] = b.x * rotation[6usize] - rotation[0usize]
            row[1usize] = b.x * rotation[7usize] - rotation[1usize]
            row[2usize] = b.x * rotation[8usize] - rotation[2usize]
            row[3usize] = b.x * t[2usize] - t[0usize]
        } else {
            row[0usize] = b.y * rotation[6usize] - rotation[3usize]
            row[1usize] = b.y * rotation[7usize] - rotation[4usize]
            row[2usize] = b.y * rotation[8usize] - rotation[5usize]
            row[3usize] = b.y * t[2usize] - t[1usize]
        }
        var i = 0usize
        while i < 4usize {
            var j = 0usize
            while j < 4usize {
                ata[i * 4usize + j] += row[i] * row[j]
                j += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
    var values: [4]f64 = zero
    var vectors: [16]f64 = zero
    if reduce.symmetric_eigen(ata[..], 4usize, values[..], vectors[..], 1.0e-30f64, 100u32) != ok { ret (zero, false) }
    let wv = vectors[15usize]
    if math.abs[f64](wv) < 1.0e-300f64 { ret (zero, false) }
    ret (geom3.vec3(vectors[12usize] / wv, vectors[13usize] / wv, vectors[14usize] / wv), true)
}

fn to_normalised(kinv: []const f64, p: Point) -> Point {
    ret Point { x: kinv[0usize] * p.x + kinv[1usize] * p.y + kinv[2usize], y: kinv[3usize] * p.x + kinv[4usize] * p.y + kinv[5usize] }
}

// Two-view reconstruction: `b ~ K [R | t] X` for the correspondences `a`,
// `b` (pixels) under the intrinsics `k`. The fundamental matrix gives the
// essential matrix `K^T F K`, whose decomposition offers four poses; the
// one with most points in front of both cameras wins. `rotation` receives
// nine entries, `translation` three (unit length, so the scene is up to
// scale) and `points` the triangulated positions in the first camera's
// frame; `scratch.len >= 2 * a.len` points.
fn structure_from_motion(k: []const f64, a: []const Point, b: []const Point, rotation: []f64, translation: []f64, points: []geom3.Vec3, scratch: []Point) -> err {
    let n = a.len
    if n < 8usize || b.len < n || k.len < 9usize { ret Invalid }
    if rotation.len < 9usize || translation.len < 3usize || points.len < n || scratch.len < 2usize * n { ret TooSmall }
    var f: [9]f64 = zero
    let ef = fundamental_matrix(a, b, f[..])
    if ef != ok { ret ef }
    var kt: [9]f64 = zero
    var tmp: [9]f64 = zero
    var e: [9]f64 = zero
    transpose3(k, kt[..])
    mul3(f[..], k, tmp[..])
    mul3(kt[..], tmp[..], e[..])
    var u: [9]f64 = zero
    var s: [3]f64 = zero
    var v: [9]f64 = zero
    if svd3(e[..], u[..], s[..], v[..]) != ok { ret Invalid }
    var kinv: [9]f64 = zero
    var work: [9]f64 = zero
    if filter.mat_inverse(k, kinv[..], 3usize, work[..]) != ok { ret Invalid }
    var na = scratch[..n]
    var nb = scratch[n..2usize * n]
    var i = 0usize
    while i < n {
        na[i] = to_normalised(kinv[..], a[i])
        nb[i] = to_normalised(kinv[..], b[i])
        i += 1usize
    }
    // R = U W V^T or U W^T V^T, t = +-u3.
    var wm: [9]f64 = zero
    wm[1usize] = 0.0f64 - 1.0f64
    wm[3usize] = 1.0f64
    wm[8usize] = 1.0f64
    var wt: [9]f64 = zero
    transpose3(wm[..], wt[..])
    var vt: [9]f64 = zero
    transpose3(v[..], vt[..])
    var r1: [9]f64 = zero
    var r2: [9]f64 = zero
    mul3(u[..], wm[..], tmp[..])
    mul3(tmp[..], vt[..], r1[..])
    mul3(u[..], wt[..], tmp[..])
    mul3(tmp[..], vt[..], r2[..])
    var best_count = 0usize
    var best_pose = 0usize
    var pose = 0usize
    while pose < 4usize {
        var rc: [9]f64 = zero
        var tc: [3]f64 = zero
        pose_candidate(u[..], r1[..], r2[..], pose, rc[..], tc[..])
        var front = 0usize
        i = 0usize
        while i < n {
            let (x, found) = triangulate(rc[..], tc[..], na[i], nb[i])
            if found && x.z > 0.0f64 {
                let moved = geom3.add(geom3.rotate(rc[..], x), geom3.vec3(tc[0usize], tc[1usize], tc[2usize]))
                if moved.z > 0.0f64 { front += 1usize }
            }
            i += 1usize
        }
        if front > best_count {
            best_count = front
            best_pose = pose
        }
        pose += 1usize
    }
    if best_count == 0usize { ret Invalid }
    pose_candidate(u[..], r1[..], r2[..], best_pose, rotation[..9usize], translation[..3usize])
    i = 0usize
    while i < n {
        let (x, _) = triangulate(rotation[..9usize], translation[..3usize], na[i], nb[i])
        points[i] = x
        i += 1usize
    }
    ret ok
}

fn pose_candidate(u: []const f64, r1: []const f64, r2: []const f64, pose: usize, rotation: []f64, t: []f64) {
    var i = 0usize
    while i < 9usize {
        if pose < 2usize { rotation[i] = r1[i] } else { rotation[i] = r2[i] }
        i += 1usize
    }
    var sign = 1.0f64
    if pose % 2usize == 1usize { sign = 0.0f64 - 1.0f64 }
    t[0usize] = sign * u[2usize]
    t[1usize] = sign * u[5usize]
    t[2usize] = sign * u[8usize]
}
