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
use e.valid
use e.mem

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

// An orthogonal (total-least-squares) 2D line: `point` on the line (the fit
// centroid) with a unit `direction`. Vertical-safe, unlike slope/intercept.
type TlsLine = struct { point: Point, direction: Point }

// Orthogonal distance from `p` to `fit` (exact for unit direction).
fn tls_distance(fit: TlsLine, p: Point) -> f64 {
    let dx = p.x - fit.point.x
    let dy = p.y - fit.point.y
    var cross = dx * fit.direction.y - dy * fit.direction.x
    if cross < 0.0f64 { cross = 0.0f64 - cross }
    ret cross
}

// The principal axis of 2x2 scatter sums about centroid (`mx`, `my`) by
// closed-form eigendecomposition; a cloud with no extent is `Invalid`.
fn tls_axis(sxx: f64, sxy: f64, syy: f64, mx: f64, my: f64) -> (TlsLine, err) {
    if sxx == 0.0f64 && sxy == 0.0f64 && syy == 0.0f64 { ret (zero, Invalid) }
    let trace = sxx + syy
    var disc = trace * trace / 4.0f64 - (sxx * syy - sxy * sxy)
    if disc < 0.0f64 { disc = 0.0f64 }
    let lambda = trace / 2.0f64 + math.sqrt[f64](disc)
    var dx = 0.0f64
    var dy = 0.0f64
    if sxy == 0.0f64 {
        if sxx >= syy {
            dx = 1.0f64
        } else {
            dy = 1.0f64
        }
    } else {
        dx = sxy
        dy = lambda - sxx
    }
    let norm = math.sqrt[f64](dx * dx + dy * dy)
    if !(norm > 0.0f64) { ret (zero, Invalid) }
    ret (TlsLine { point: Point { x: mx, y: my }, direction: Point { x: dx / norm, y: dy / norm } }, ok)
}

// Total-least-squares line through `n` points: centroid plus the principal
// axis of the scatter. Fewer than two points, or a point cloud with no
// extent, is `Invalid`.
fn fit_line_tls(points: []const Point, n: usize) -> (TlsLine, err) {
    if points.len < n { ret (zero, TooSmall) }
    if n < 2usize { ret (zero, Invalid) }
    var mx = 0.0f64
    var my = 0.0f64
    var i = 0usize
    while i < n {
        mx += points[i].x
        my += points[i].y
        i += 1usize
    }
    mx /= f64(n)
    my /= f64(n)
    var sxx = 0.0f64
    var sxy = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < n {
        let ex = points[i].x - mx
        let ey = points[i].y - my
        sxx += ex * ex
        sxy += ex * ey
        syy += ey * ey
        i += 1usize
    }
    let (axis, axis_error) = tls_axis(sxx, sxy, syy, mx, my)
    ret (axis, axis_error)
}

// One outlier-rejection pass: fit, keep the points within `threshold`
// orthogonal distance in `inliers`, refit over the kept set into `fit`.
// Answers the inlier count; a non-positive threshold, or fewer than two
// survivors, is `Invalid`.
fn fit_line_tls_robust(points: []const Point, n: usize, threshold: f64, fit: *TlsLine, inliers: []bool) -> (usize, err) {
    if points.len < n || inliers.len < n { ret (0usize, TooSmall) }
    if n < 2usize || !(threshold > 0.0f64) { ret (0usize, Invalid) }
    let (first, fit_error) = fit_line_tls(points, n)
    if fit_error != ok { ret (0usize, fit_error) }
    var kept = 0usize
    var i = 0usize
    while i < n {
        if tls_distance(first, points[i]) <= threshold {
            inliers[i] = true
            kept += 1usize
        } else {
            inliers[i] = false
        }
        i += 1usize
    }
    if kept < 2usize { ret (0usize, Invalid) }
    var mx = 0.0f64
    var my = 0.0f64
    i = 0usize
    while i < n {
        if inliers[i] {
            mx += points[i].x
            my += points[i].y
        }
        i += 1usize
    }
    mx /= f64(kept)
    my /= f64(kept)
    var sxx = 0.0f64
    var sxy = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < n {
        if inliers[i] {
            let ex = points[i].x - mx
            let ey = points[i].y - my
            sxx += ex * ex
            sxy += ex * ey
            syy += ey * ey
        }
        i += 1usize
    }
    let (refit, refit_error) = tls_axis(sxx, sxy, syy, mx, my)
    if refit_error != ok { ret (0usize, refit_error) }
    fit.point = refit.point
    fit.direction = refit.direction
    ret (kept, ok)
}

// ---- Reading a machine-readable zone (D4809) --------------------------------------------------------------------------
//
// `mrz_read` finds the two 44-character lines of a passport's zone (TD3) in an 8-bit luminance image and reads them
// with glyph templates, checking the result with the ICAO check digits (`valid.mrz_td3`):
//   1. The ink is the pixels under Otsu's threshold (the image is inverted when ink would be the majority).
//   2. Text lines are runs of rows with ink (a gap of one row is a broken stroke); the zone is the last two lines of
//      about the same height (within a third).
//   3. A line's body rows are those holding a quarter of the busiest row's ink, extended by a fifth below the baseline
//      so a Q's tail is inside. Its 44 characters are the column runs when there are exactly 44; otherwise a pitch grid
//      is searched in quarter pixels for the boundaries with the least ink around them.
//   4. Each character's cell is centred on its ink, as wide as the pitch, area-averaged to 10 x 16, quantised to four
//      levels and blurred 3 x 3, and compared with 296 templates (37 symbols, four monospaced sans fonts, two stroke
//      widths; a shift of a column either way costs 40): the best and the second best distinct symbol are kept.
//   5. Digits where a field is numeric and letters where it is alphabetic (O and 0, I and 1, B and 8, S and 5, Z and 2,
//      G and 6), then, when a check digit fails, the second choices of the eight least certain cells are tried in every
//      combination and the one with the fewest changes that satisfies every check digit wins.
// The templates are the shapes of JetBrains Mono, Cascadia Mono and Intel One Mono (SIL OFL); OCR-B itself, the font of
// real documents, was not available to render, so a real passport is not known to read. A line needs a pitch of about
// 17 pixels or more (a cap height of 20); under that the digits and letters blur into each other.

const MRZ_LINE: usize = 44usize
const MRZ_CELL_W: usize = 10usize
const MRZ_CELL_H: usize = 16usize
const MRZ_SYMBOLS: usize = 37usize
const MRZ_VARIANTS: usize = 8usize
const MRZ_CELL: usize = 160usize
error NoZone

type MrzRead = struct { line1: [44]u8, line2: [44]u8, verified: bool, changes: usize }

fn mrz_symbol(i: usize) -> u8 {
    if i == 0usize { ret 60u8 }
    if i <= 10usize { ret u8(47usize + i) }
    ret u8(54usize + i)
}

fn mrz_templates() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x00\x00(\x00\xb8\x01\xf4\x01\xe0\x02@\x07\x00\xe0\x02\x00\xf4\x02\x00\xf8\x00\x00)\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00@/\x00\xae\x0fp\xc0A\x03(4\x80BC(4\x8eB\x93(4\x80B\x03(4\x80\x02\x0b\x1d\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\x00\x1e\x00\xfc\x01\xb0\x1c@\xc2\x01\x00\x1c\x00\xc0\x01\x00\x1c\x00\xc0\x01\x00\x1c\x00\xc0\x01\x00\x1c\x00\xc0\x01\xf4\xff\x03U\x15\x00\x00\x00\x00\x00@/\x00\xae\x0bp\xd0A\x03,\x00\xc0\x02\x00\x1c\x00\xa0\x00\x80\x03\x00\x0d\x00\xb4\x00\xc0\x02\x00\x0e\x00\xf4\xff\x02U\x15\x00\x00\x00\x00\x00\xe0\xff\x01\xa9\x1e\x00\xa0\x00\x80\x03\x00\x0e\x00\xf0\x02\x00\xea\x00\x00,\x00\x80\x02\x01(p\x80\x02\x0b-\xc0\xbf\x00P\x01\x00\x00\x00\x00\x00\x00p\x00\x80\x03\x00\x1c\x00\xe0\x00@\x07\x00(\x00\xd0\xc1\x02\x0b,t\xc0B\xff/P\xd5\x02\x00,\x00\xc0\x02\x00\x14\x00\x00\x00\x00\x00\xf0\xff\x00\xab\x0ap\x00\x00\x07\x00p\x19\x00\xfb\x0b\xf0\xe0\x01\x01,\x00\xc0\x02\x00,\x10\xc0\x01\x0b\x1d\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\x00\x1c\x00\xe0\x00\x00\x07\x004\x00\xc0\x01\x00\xdd\x02\xf0\xfaA\x07,8\x80\x83\x0284\x80B\x0b\x1d\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\xf4\xffC\xab>4\x80B\x03\x1c\x00\xd0\x00\x00\x0a\x00p\x00\x80\x03\x00(\x00\xd0\x01\x00\x0d\x00\xb0\x00@\x07\x00\x14\x00\x00\x00\x00\x00\x00@/\x00\xae\x0fp\xc0A\x03(p\xc0\x01\x1d\x0a\x80?\x00^\x0e0\x80\x81\x02(8\x80B\x07-\xe0\xbf\x00P\x00\x00\x00\x00\x00\x00@/\x00\xae\x0ft\xc0\x81\x03((\x80\x83\x03(\xb4\xd0\x02\xfe\x0f\x00q\x00@\x03\x00(\x00\xd0\x01\x00\x0b\x00\x10\x00\x00\x00\x00\x00\x00\x00\x0f\x00\xf0\x01@+\x00\xa8\x03\x806\x00\x1c\x07\xd0\xb0\x00\x0e\x0a\xa0\xe5\x00\xff\x1fp\xc0A\x03((\x80C\x01\x10\x00\x00\x00\x00\x00\xf4/@\xab\x0ft\xc0A\x07,t\xc0A\x07\x0e\xf4\x7f@[\x1et\x80B\x07(t\x80B\x07-\xf4\xbf\x00U\x01\x00\x00\x00\x00\x00@/\x00\xae\x0fp\xc0A\x07,t\x00@\x07\x00t\x00@\x07\x00t\x00@\x07\x14t\xc0\x02\x0b\x1d\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\xf4\x1f@\xab\x0bt\xd0@\x07\x1ct\xc0B\x07,t\xc0B\x07,t\xc0B\x07,t\xc0A\x07\x0e\xf4\x7f\x00U\x00\x00\x00\x00\x00\x00\xf0\xff\x02\xab\x1ap\x00\x00\x07\x00p\x00\x00\x07\x00\xf0\xff\x00[\x05p\x00\x00\x07\x00p\x00\x00\x07\x00\xf0\xff\x02U\x15\x00\x00\x00\x00\x00\xf0\xff\x02\xab\x1ap\x00\x00\x07\x00p\x00\x00\x07\x00\xf0\xff\x01[\x05p\x00\x00\x07\x00p\x00\x00\x07\x00p\x00\x00\x01\x00\x00\x00\x00\x00\x00@/\x00\xae\x0fp\xc0A\x07,t\x00@\x07\x00tTA\xd7/t\x80B\x07(t\xc0\x02\x0b\x1d\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\xb0\x80\x02\x0b(\xb0\x80\x02\x0b(\xb0\x80\x02\x0b(\xf0\xff\x02[)\xb0\x80\x02\x0b(\xb0\x80\x02\x0b(\xb0\x80\x02\x05\x14\x00\x00\x00\x00\x00\xf0\xff\x01\xfa\x1a\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\xf0\xff\x01U\x05\x00\x00\x00\x00\x00\x00\xfe\x03\x90>\x00\x80\x03\x008\x00\x80\x03\x008\x00\x80\x03\x008\x00\x80\x03\x018p\x80\x02\x0b-\xd0\xbf\x00P\x01\x00\x00\x00\x00\x008\xc0\x82\x03\x1d8\xa0\x80C\x078(\x80\xc3\x01\xf8\x0f\x80\xd7\x018(\x80C\x078\xb0\x80\x03\x0e8\xc0B\x01\x14\x00\x00\x00\x00\x00\xb0\x00\x00\x0b\x00\xb0\x00\x00\x0b\x00\xb0\x00\x00\x0b\x00\xb0\x00\x00\x0b\x00\xb0\x00\x00\x0b\x00\xb0\x00\x00\x0b\x00\xf0\xff\x02U\x15\x00\x00\x00\x00\x00t\xd0B\x0b.\xe4\xa0B\x1a+t\xa6B\xb3)4\x9fB\x93(4\x80B\x03(4\x80B\x03(4\x80\x02\x01\x14\x00\x00\x00\x00\x00\xf0\x80\x02\x1f(\xf0\x82\x02;(p\x87\x02\xa7(\xb0\x8d\x02\xcb)\xb0\xa8\x02K+\xb0\xb0\x02\x0b.\xb0\xd0\x02\x05\x14\x00\x00\x00\x00\x00@/\x00\xae\x0fp\xd0A\x07\x1ct\xc0B\x07,t\xc0B\x07,t\xc0B\x07,t\xc0\x01\x0b\x1e\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\xf4o@\xab\x1et\x80B\x074t@C\x078\xb4\xe5B\xff\x07t\x00@\x07\x00t\x00@\x07\x00t\x00\x00\x01\x00\x00\x00\x00\x00\x00@/\x00\xae\x0fp\xc0A\x03,4\x80B\x03(4\x80B\x03(4\x80B\x03(4\xc0\x02\x0b\x1d\xd0\xbf\x00\x90\x03\x00\xb0\x00\x00\x0e\xf4/@\xab\x0ft\xc0B\x078t\x80C\x07,\xb4\xfa@\xeb\x02t8@G\x07t\xa0@\x07\x1dt\xc0\x02\x01\x14\x00\x00\x00\x00\x00@/\x00\xae\x0fp\xc0A\x07\x18p\x00\x00\x1e\x00\x80/\x00@\x0f\x00\xc0\x01\x01(4\x80B\x0b-\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\xf8\xffC\xfa*\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00P\x00\x00\x00\x00\x00\x00\xb0\x80\x02\x0b(\xb0\x80\x02\x0b(\xb0\x80\x02\x0b(\xb0\x80\x02\x0b(\xb0\x80\x02\x0b(\xa0\x80\x02\x0e-\xc0\xbf\x00P\x01\x00\x00\x00\x00\x00(@\x83\x03(4\x80\x02\x07\x1c\xb0\xd0\x00\x0a\x0d\xd0\xa0\x00\x1d\x07\xc0q\x00h\x03\x80&\x00\xb4\x02\x00\x1f\x00P\x00\x00\x00\x00\x00\x00\x0d\x0e\xc6\xe1p\x1c\x0a\xc7\xb1q\x18[\x83b5hf\x83f&t\xa1B\x1b+\xb4\xb1\x01\x0f\x1f\xf0\xe0\x01\x05\x05\x00\x00\x00\x00\x008\x80C\x07\x1c\xa0\xd0\x00\x1d\x0b\x806\x00\xf4\x01\x00\x0f\x00\xf0\x01@+\x00\\\x07\xd0\xa0\x00\x0b\x1d8\x80B\x01\x10\x00\x00\x00\x00\x00\x1c@\x83\x03(p\xc0\x01\x0a\x0d\xd0\xb1\x00h\x03@+\x00\xf0\x01\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00P\x00\x00\x00\x00\x00\x00\xf4\xffA\xaa\x1e\x00\xd0\x00\x00\x0b\x008\x00\xc0\x01\x00\x0e\x00p\x00@\x03\x00\x1c\x00\xd0\x00\x00\x07\x00\xf4\xff\x02U\x15\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00>\x00\xfd\x02\xf9\x07\xf8\x07\x80\x1f\x00\xf4\x0b\x00\xf9\x07\x00\xf9\x03\x009\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xf5\x82\x07<x\xc0\x83\xa7<x\xdf\x83\xf7<x\xc0\x83\x07<\xb8\xd0C\xaf/\xd0\xbf\x00\xa4\x01\x00\x00\x00\x00\x00\x00/\x00\xfd\x02\xf4/\x80\xd7\x02\x14-\x00\xd0\x02\x00-\x00\xd0\x02\x00-\x00\xd0\x02\x00-@\xea+\xf8\xffG\xaaj\x00\x00\x00\x00\x00\x80/\x00\xff\x0f\xf8\xf5\x82\x07=\x14\xd0\x03\x00.\x00\xf4\x01\xc0\x07\x00.\x00\xf8\x00\xe0\x03@\xaf*\xf8\xffC\xaa*\x00\x00\x00\x00\x00\xf0\xff\x02\xff/P\xf5\x01\xc0\x0b\x00.\x00\xf4\x0b@\xff\x02\x00=\x00\xc0C\x06<\xb4\xc0\x03\xaf/\xd0\xff\x00\xa4\x02\x00\x00\x00\x00\x00\x00\xf4\x00\xc0\x07\x00=\x00\xf0\x01\x80\x0b\x00|\x14\xe0\xd2C\x0f=\xb8\xe5\x83\xff?\xa4\xea\x03\x00=\x00\xd0\x03\x00)\x00\x00\x00\x00\x00\xf4\xffA\xff\x1f\xb4U@\x0b\x00\xb4.@\xff\x0f\xf4\xf5B\x06=\x00\xd0\x03\x00=\xb8\xd0B\xaf\x1f\xd0\xbf\x00\xa4\x01\x00\x00\x00\x00\x00\x00<\x00\xe0\x02@\x0f\x00|\x00\xd0\x03\x00\xfe\x0b\xf4\xff\x82\x0b>|\xc0\xc7\x03|x\xd0C\xaf/\xe0\xbf\x00\xa4\x01\x00\x00\x00\x00\x00\xf8\xff\x87\xff\x7f\xb8\xd5\x87\x07-\x10\xe0\x01\x00\x0f\x00\xb4\x00\xc0\x07\x00<\x00\xe0\x02\x00\x1f\x00\xf4\x00\x80\x0b\x00h\x00\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe5\x82\x07<x\xd0Bo\x1f\xd0\xbf\x00\xaf\x1fx\xd0\xc2\x03<|\xc0\x83\xaf?\xe0\xff\x00\xa4\x02\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf8\xe5\xc3\x07<<\xc0\xc7\x07<\xf8\xe5\x03\xff\x1f\x80\xff\x00\x80\x0b\x00=\x00\xf0\x01@\x0b\x00d\x00\x00\x00\x00\x00\x00\x00\x1f\x00\xf4\x02\x80?\x00\xfc\x07\xc0{\x00m\x0b\xe0\xf5\x00\x1f\x0f\xf0\xffA\xff/\xb8\xe5\x82\x07<<\x80\x87\x02d\x00\x00\x00\x00\x00\xf4/\x80\xff\x0f\xb8\xf5\x82\x0b=\xb8\xd0\x82[/\xf8\xff\x80\xaf/\xb8\xc0\x83\x0b<\xb8\xc0\x83\xaf/\xf8\xff@\xaa\x02\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe5\x82\x0b=\xb8@\x81\x0b\x00\xb8\x00\x80\x0b\x00\xb8\x00\x80\x0b(\xb8\xd0C\xaf/\xd0\xbf\x00\xa4\x01\x00\x00\x00\x00\x00\xf4\x1f\x80\xff\x0b\xb8\xf5\x82\x0b-\xb8\xd0\x83\x0b=\xb8\xd0\x83\x0b=\xb8\xd0\x83\x0b=\xb8\xd0\x82\xaf\x1f\xf8\xbf@\xaa\x01\x00\x00\x00\x00\x00\xf4\xffC\xff?\xb4UA\x0b\x00\xb4\x00@[\x05\xf4\xffA\xaf\x1a\xb4\x00@\x0b\x00\xb4\x00@\xaf*\xf4\xffC\xaa*\x00\x00\x00\x00\x00\xf4\xffC\xff?\xb4UA\x0b\x00\xb4\x00@[\x15\xf4\xffB\xaf\x1a\xb4\x00@\x0b\x00\xb4\x00@\x0b\x00\xb4\x00@\x06\x00\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe5\x82\x0b=\xb8@\x81\x0b\x00\xb8\xa9\x82\xeb?\xb8\xd4\x83\x0b<\xb8\xd0C\xaf/\xd0\xbf\x00\xa4\x01\x00\x00\x00\x00\x00\xb0\xc0C\x0f<\xf4\xc0C\x0f<\xf4\xc0C_=\xf4\xffC\xaf>\xf4\xc0C\x0f<\xf4\xc0C\x0f<\xf4\xc0\x03\x0a(\x00\x00\x00\x00\x00\xf4\xffA\xff/Po\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f@\xfa\x1a\xf4\xffB\xaa\x1a\x00\x00\x00\x00\x00\x00\xff\x03\xf0\x7f\x00\xd5\x07\x00|\x00\xc0\x07\x00|\x00\xc0\x07\x00|\x00\xc0G\x06|\xb8\xc0\x03\xaf/\xd0\xff\x00\xa4\x02\x00\x00\x00\x00\x008\xc0\xc3\x07.|\xf0\xc1\x87\x0b||\xc0\xeb\x03\xfc\x1f\xc0\xfb\x02|<\xc0\x87\x0b|\xf4\xc0\x07.|\xd0\x83\x02h\x00\x00\x00\x00\x00\xb0\x00@\x0f\x00\xf4\x00@\x0f\x00\xf4\x00@\x0f\x00\xf4\x00@\x0f\x00\xf4\x00@\x0f\x00\xf4\x00@\xaf*\xf4\xff\x03\xaa*\x00\x00\x00\x00\x00\xb8\xd0\x83\x0f>\xf8\xf1\x83o?\xf8\xfb\x83\xff?\xb8\xef\x83\xf7=x\xc0\x83\x07<x\xc0\x83\x07<x\xc0C\x06(\x00\x00\x00\x00\x00\xf0\x81C/<\xf4\xc3C\x7f<\xf4\xcbC\xff<\xf4\xdeC\xdf>\xf4\xfcC\x8f?\xf4\xf4C\x0f?\xf4\xe0\x03\x0a)\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xf5\x82\x0b-\xb8\xd0\x83\x0b=\xb8\xd0\x83\x0b=\xb8\xd0\x83\x0b=\xb8\xd0B\xaf\x1f\xd0\xbf\x00\xa4\x01\x00\x00\x00\x00\x00\xf4o\x80\xff\x1f\xb8\xe5\x83\x0bx\xb8\x80\x87\x0b|\xf8\xfa\x83\xff\x0f\xb8\x15\x80\x0b\x00\xb8\x00\x80\x0b\x00\xb8\x00@\x06\x00\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xf5\x82\x07=x\xc0\x83\x07<x\xc0\x83\x07<x\xc0\x83\x07<\xb8\xd0C\xaf/\xd0\xbf\x00\xe4\x0b\x00\xf4\x00\x00.\xf4/\x80\xff\x1f\xb8\xe5\x83\x0b|\xb8\xc0\x87\x0b=\xf8\xff\x82\xff\x07\xb8|\x80\x8b\x0b\xb8\xf0\x81\x0b.\xb8\xd0C\x06h\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe5\x82\x0b<\xb4\x00@o\x00\xd0\xbf\x00\xa0/\x00\xd0C\x02<x\xc0C\xaf/\xe0\xff\x00\xa4\x02\x00\x00\x00\x00\x00\xfc\xff\xc7\xff\x7fTo\x01\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xa0\x00\x00\x00\x00\x00\x00\xb0\xc0C\x0f<\xf4\xc0C\x0f<\xf4\xc0C\x0f<\xf4\xc0C\x0f<\xf4\xc0C\x0f<\xf0\xc0\x03\xbf/\xc0\xff\x00\xa4\x06\x00\x00\x00\x00\x00<\x80\xc7\x03|x\xc0C\x0b-\xb4\xe0\x01\x0f\x1e\xe0\xf1\x00n\x0b\xd0\xb6\x00\xbc\x07\xc0?\x00\xf8\x03@/\x00\xa0\x01\x00\x00\x00\x00\x00\x1f\x0e\xeb\xf2\xb5-_\xdb\xf6\xb6mo\xc7\xf7z\xbc\xbb\xc7\xbb;\xf8\xf6\x83o?\xf8\xf6B\x1f/\xf4\xf1B\x0a\x1a\x00\x00\x00\x00\x00<\x80\x87\x0b=\xf4\xe0\x01n\x0f\xc0{\x00\xf8\x03@\x1f\x00\xf4\x02\x80?\x00\xbd\x0b\xf0\xf1\x81\x0b.|\xc0\x97\x02d\x00\x00\x00\x00\x00-@\xcb\x03|\xb8\xd0\x03\x0f\x1e\xe0\xf1\x00\xbd\x0b\xc0?\x00\xf4\x02\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xa0\x00\x00\x00\x00\x00\x00\xf4\xff\x82\xff/P\xf5\x02@\x0f\x00x\x00\xd0\x03\x00\x1f\x00\xf4\x00\xc0\x07\x00=\x00\xf0\x01\x80\xaf*\xf8\xffC\xaa*\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00)\x00\xf9\x01\xf8\x02\xf4\x06@\x0b\x00\xf4\x07\x00\xf9\x06\x00\xf8\x02\x00-\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe1\x82\x07,x\xc0\x83G<x\xcf\x83\x97<x\xc0\x83\x07<t\xc0Bo/\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00@\x1f\x00\xfd\x01\xf4\x1e\x80\xe7\x01\x04\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e@\xe5\x16\xf8\xffCU\x15\x00\x00\x00\x00\x00\x80/\x00\xff\x0f\xb4\xe0\x81\x07-\x14\xd0\x02\x00\x1d\x00\xf0\x00\xc0\x07\x00\x1e\x00\xb8\x00\xd0\x02@o\x15\xf4\xff\x03U\x15\x00\x00\x00\x00\x00\xf0\xff\x02\xff/\x00\xe0\x01\x80\x0b\x00.\x00\xf0\x07\x00\xff\x01\x00=\x00\xc0\x03\x05<\xb4\xc0\x03o.\xd0\xff\x00P\x01\x00\x00\x00\x00\x00\x00\xb4\x00\xc0\x07\x00-\x00\xf0\x01\x80\x0b\x00<\x00\xe0\xd1B\x0b-\xb4\xd0B\xff/\xf4\xff\x02\x00-\x00\xd0\x02\x00\x14\x00\x00\x00\x00\x00\xf0\xff\x02\xff/\xf0\x00\x00\x0f\x00\xf0h\x00\xef\x1f\xf0\xe6\x03\x05<\x00\xc0\x03\x00<\xb0\xc0\x03o.\xc0\xff\x00P\x01\x00\x00\x00\x00\x00\x00-\x00\xe0\x01\x00\x0b\x00x\x00\xd0\x02\x00\xde\x07\xf4\xfa\x81\x0b=x\xc0\x83\x07<x\xc0Co/\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\xf8\xff\x87\xff\x7fx\xc0\x83\x07-\x14\xe0\x01\x00\x0f\x00\xb4\x00\xc0\x07\x00-\x00\xe0\x02\x00\x0f\x00\xf4\x00\x80\x07\x00\x14\x00\x00\x00\x00\x00\x00@/\x00\xff\x0f\xf4\xe1\x82\x07-\xb4\xd0\x02\x1e\x0f\xc0\x7f\x00\xae\x0ft\xd0\x82\x07<x\xc0\x83_.\xe0\xbf\x00P\x01\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe1\x82\x07<x\xc0\x83\x07<\xf4\xe5\x02\xfe\x1f@\xb5\x00\x80\x07\x00<\x00\xe0\x01@\x0f\x00T\x00\x00\x00\x00\x00\x00@\x1f\x00\xf4\x02\x80?\x00\xbc\x03\xc0v\x00m\x0b\xe0\xb1\x00\x0e\x0f\xf0\xe5A\xff\x1f\xb4\xe5\x82\x07<<\xc0C\x01\x14\x00\x00\x00\x00\x00\xf4/@\xff\x1f\xb4\xe0B\x0b-\xb4\xd0B[\x0f\xf4\xbf@[/\xb4\xc0C\x0b<\xb4\xc0C[.\xf4\xbf\x00U\x01\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe1B\x0b=x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\x07\x14\xb4\xd0Bo/\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\xf4/@\xff\x0f\xb4\xe0A\x0b-\xb4\xc0C\x0b<\xb4\xc0C\x0b<\xb4\xc0C\x0b<\xb4\xd0B[\x1f\xf4\xbf\x00U\x00\x00\x00\x00\x00\x00\xf4\xffB\xff/\xb4\x00@\x0b\x00\xb4\x00@[\x05\xf4\xffA[\x05\xb4\x00@\x0b\x00\xb4\x00@[\x15\xf4\xff\x02U\x15\x00\x00\x00\x00\x00\xf4\xffC\xff?\xb4\x00@\x0b\x00\xb4\x00@\x0b\x00\xf4\xffA\xaf\x1a\xb4\x00@\x0b\x00\xb4\x00@\x0b\x00\xb4\x00\x00\x05\x00\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe1B\x0b<x\x00\x80\x07\x00x\xa8\x82\xc7?x\xc0\x83\x07<\xb4\xd0Bo/\xd0\xbf\x00P\x00\x00\x00\x00\x00\x00\xb4\xd0B\x0b-\xb4\xd0B\x0b-\xb4\xd0B[.\xf4\xffB[.\xb4\xd0B\x0b-\xb4\xd0B\x0b-\xb4\xd0\x02\x05\x14\x00\x00\x00\x00\x00\xf0\xff\x02\xff/\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe5\x16\xf0\xff\x02U\x15\x00\x00\x00\x00\x00\x00\xff\x03\xf0?\x00\xc0\x03\x00<\x00\xc0\x03\x00<\x00\xc0\x03\x00<\x00\xc0C\x06<\xb4\xc0\x03o.\xd0\xbf\x00P\x01\x00\x00\x00\x00\x00x\xd0\x82\x07\x1ex\xf0\x80\x87\x0bx<\x80\xeb\x02\xf8/\x80\xeb\x02x<\x80\x87\x0bx\xf4\x80\x07\x1fx\xd0B\x01\x14\x00\x00\x00\x00\x00\xb4\x00@\x0b\x00\xb4\x00@\x0b\x00\xb4\x00@\x0b\x00\xb4\x00@\x0b\x00\xb4\x00@\x0b\x00\xb4\x00@[\x15\xf4\xff\x02U\x15\x00\x00\x00\x00\x00\xb8\xd0\x83\x0f>\xf8\xf0\x83_;\xb8\xa6\x83\xb7:8\x9f\x83\xa388\xc0\x83\x03<8\xc0\x83\x03<8\xc0C\x01\x14\x00\x00\x00\x00\x00\xf4\x81C/8\xf4\x83C\x7f8\xb4\x8bC\xab8\xb4\x8dC\xcb9\xb4\xa8C\x8b;\xb4\xf4C\x0b?\xb4\xe0\x03\x05\x14\x00\x00\x00\x00\x00@n\x00\xfd\x1f\xf0\xe2\x02\x0f<\xb4\xc0C\x0b<\xb4\xc0C\x0b<\xb4\xc0C\x0b<\xf0\xc0\x03o.\xc0\xff\x00P\x01\x00\x00\x00\x00\x00\xf8/\x80\xff\x0fx\xe0\x82\x07=x\xc0\x83\x07-\xb8\xfa\x81\xff\x07x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00@\x01\x00\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe1\x81\x0b-x\xc0\x83\x07<x\xc0\x83\x07<x\xc0\x83\x07<\xb4\xd0Bo/\xd0\xbf\x00\x90\x07\x00\xb4\x00\x00\x1e\xf8/\x80\xff\x0fx\xf0\x81\x07-x\xd0\x82\x07\x1e\xb8\xfa\x80\xff\x07x,\x80\xc7\x07x\xb4\x80\x07\x0fx\xe0B\x01\x14\x00\x00\x00\x00\x00@/\x00\xfe\x0f\xf4\xe1B\x0b\x19\xb4\x00\x00/\x00\xe0\x7f\x00\xa4\x1f\x00\xd0B\x01<x\xc0C_.\xe0\xbf\x00P\x01\x00\x00\x00\x00\x00\xfc\xff\xc7\xff\x7f\x00\x0f\x00\xf0\x00\x00\x0f\x00\xf0\x00\x00\x0f\x00\xf0\x00\x00\x0f\x00\xf0\x00\x00\x0f\x00\xf0\x00\x00\x0f\x00P\x00\x00\x00\x00\x00\x00\xf4\xc0C\x0f<\xf4\xc0C\x0f<\xf4\xc0C\x0f<\xf4\xc0C\x0f<\xf4\xc0C\x0f<\xf0\xc0\x03o.\xc0\xff\x00P\x01\x00\x00\x00\x00\x00<\x80\x87\x07<x\xc0B\x0b-\xf0\xe0\x01\x0f\x0e\xe0\xf1\x00\x1d\x0b\xd0v\x00|\x07\x80;\x00\xf8\x03@/\x00P\x00\x00\x00\x00\x00\x00\x1d\x0e\xdb\xe1\xb0\x1d_\xc7\xb2u,[\xc7\xa65l\xa6\x83g:\xb8\xa6\x83[+\xb4\xb1B\x1f/\xf4\xf0\x02\x05\x05\x00\x00\x00\x00\x00x\xc0C\x0b-\xf0\xe0\x00n\x0b\xc0{\x00\xf4\x02\x00\x1f\x00\xf4\x02\x80?\x00\xad\x0b\xe0\xf1@\x0f\x1ex\xd0C\x01\x14\x00\x00\x00\x00\x00x@K\x0bx\xf0\xc0\x03\x1e-\xd0\xf3\x00x\x0b@\x7f\x00\xf0\x03\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00P\x00\x00\x00\x00\x00\x00\xf4\xffA\xff\x1f\x00\xf0\x01@\x0f\x00|\x00\xd0\x02\x00\x1f\x00\xb4\x00\xc0\x07\x00-\x00\xe0\x01@_\x15\xf4\xff\x02U\x15\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00>\x00\xfe\x03\xfd\x1b\xf8\x1b\x80/\x00\xf8\x0b\x00\xfe\x1b\x00\xfd\x03\x00=\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x80/\x00\xff\x1f\xf8\xfb\xc3\x0b>\xbc\xd0\xc7\xab}\xfc\xff\xc7\xfb~\xbc\xd0\xc7\x0b}\xf8\xe1C\xff/\xe0\xff\x00\xa4\x01\x00\x00\x00\x00\x00@/\x00\xfe\x02\xf8/\xc0\xfb\x02\x1c/@\xf0\x02\x00/\x00\xf0\x02\x00/\x00\xf0\x02\x00/\xc0\xff\x7f\xfc\xff\x87\xaa*\x00\x00\x00\x00\x00\x80/\x00\xff\x0f\xf8\xfb\xc2\x0b>|\xe0\x03\x00?\x00\xf8\x02\xe0\x0b@?\x00\xfd\x01\xf0\x07\x80\xff\x7f\xf8\xffG\xaa*\x00\x00\x00\x00\x00\xf0\xffC\xff?\xa0\xfa\x03\xc0\x0f\x00>\x00\xf4\x0b@\xff\x03P~\x00\xd0G\x0a}\xf8\xe1G\xff?\xd0\xff\x00\xa4\x06\x00\x00\x00\x00\x00\x00\xf4\x01\xc0\x0f\x00~\x00\xf4\x02\x80\x0f\x00\xbd\x14\xf0\xe3\x83\x1f>\xf8\xe5\x83\xff?\xf8\xff\x03\x00>\x00\xe0\x03\x00)\x00\x00\x00\x00\x00\xf0\xffC\xff?\xf4\xaaB\x1f\x00\xf4\xbe@\xff/\xf4\xfb\x07\x0a}\x00\xd0\x07\x05}\xf4\xe2\x07\xff?\xd0\xff\x01\xa4\x06\x00\x00\x00\x00\x00\x00}\x00\xf0\x03\x80\x1f\x00\xbc\x00\xe0\x03\x00\xff\x0b\xf8\xff\xc2\x0f~\xbc\xd0\xc7\x0b}\xfc\xe1\x87\xff/\xe0\xff\x00\xa4\x01\x00\x00\x00\x00\x00\xfc\xff\xc7\xff\xbf\xfc\xea\xcb\x0b>\xbc\xf0\x02@\x1f\x00\xf8\x00\xd0\x0b\x00~\x00\xf0\x03@\x1f\x00\xfc\x00\xc0\x0b\x00i\x00\x00\x00\x00\x00\x00\x80/\x00\xff\x1f\xf8\xfb\xc3\x0b>\xb8\xe0C\xaf/\xe0\xbf@\xff/\xf8\xe0\xc3\x0b}\xfc\xe1\x87\xff?\xe0\xff\x00\xa4\x06\x00\x00\x00\x00\x00@/\x00\xff\x1f\xf8\xfb\xc3\x0b}|\xd0\xc7\x0b}\xfc\xfaC\xff/\x80\xff\x00\xc0\x0b\x00~\x00\xf4\x02\x80\x0f\x00\xa8\x00\x00\x00\x00\x00\x00@/\x00\xf8\x03\xc0\x7f\x00\xfd\x07\xd0\xbf\x00\xbe\x0f\xf0\xf6\x00_\x1f\xf4\xff\x82\xff/\xf8\xfa\xc3\x0b}}\xc0\x9b\x06h\x00\x00\x00\x00\x00\xf8/\x80\xff\x1f\xf8\xfa\x83\x0f>\xf8\xe0\x83\xaf/\xf8\xff\x81\xaf?\xf8\xd0\x87\x0f}\xf8\xe0\x87\xff?\xf8\xff@\xaa\x06\x00\x00\x00\x00\x00@/\x00\xff\x1f\xf8\xfb\x83\x0f~\xbc@\xc1\x0b\x00\xbc\x00\xc0\x0b\x00\xbc\x00\xc0\x0bi\xf8\xe1C\xff/\xe0\xff\x00\xa4\x02\x00\x00\x00\x00\x00\xf8/\x80\xff\x0f\xf8\xfa\x83\x0f>\xf8\xd0\x87\x0f}\xf8\xd0\x87\x0f}\xf8\xd0\x87\x0f}\xf8\xf0\x83\xff/\xf8\xbf@\xaa\x01\x00\x00\x00\x00\x00\xf4\xff\x83\xff?\xf8\xaa\x82\x0f\x00\xf8\x00\x80\xaf\x1a\xf8\xff\x82\xaf\x1a\xf8\x00\x80\x0f\x00\xf8\x00\x80\xff?\xf8\xffC\xaa*\x00\x00\x00\x00\x00\xf8\xff\x83\xff\x7f\xf8\xaa\x86\x0f\x00\xf8\x00\x80_\x15\xf8\xff\x82\xff/\xf8\x00\x80\x0f\x00\xf8\x00\x80\x0f\x00\xf8\x00@\x0a\x00\x00\x00\x00\x00\x00@/\x00\xff\x1f\xf8\xfb\x83\x0f~\xbc@\xc1\x0b\x00\xbc\xfd\xc7\xdb\x7f\xbc\xe4\xc7\x0b}\xf8\xe1C\xff/\xe0\xff\x00\xa4\x02\x00\x00\x00\x00\x00\xb8\xe0\x83\x0f>\xf8\xe0\x83\x0f>\xf8\xe0\x83\xaf?\xf8\xff\x83\xaf?\xf8\xe0\x83\x0f>\xf8\xe0\x83\x0f>\xf8\xe0C\x0a)\x00\x00\x00\x00\x00\xf0\xffC\xff?\xa4\xbf\x02\xf0\x02\x00/\x00\xf0\x02\x00/\x00\xf0\x02\x00/\x00\xf0\x02\x00/@\xff?\xf4\xff\x03\xaa*\x00\x00\x00\x00\x00@\xff\x07\xf4\x7f@\xea\x07\x00}\x00\xd0\x07\x00}\x00\xd0\x07\x00}\x00\xd0\x87\x0b}\xf8\xe1G\xff?\xd0\xff\x00\xa4\x06\x00\x00\x00\x00\x00|\xd0\xc7\x0b?\xbc\xf4\xc1\xcb\x0f\xbc\xbd\xc0\xff\x07\xfc?\xc0\xff\x07\xbc}\xc0\xcb\x0f\xbc\xf8\xc1\x0b/\xbc\xe0\x83\x06i\x00\x00\x00\x00\x00\xf8\x00\x80\x0f\x00\xf8\x00\x80\x0f\x00\xf8\x00\x80\x0f\x00\xf8\x00\x80\x0f\x00\xf8\x00\x80\x0f\x00\xf8\x00\x80\xff?\xf8\xffC\xaa*\x00\x00\x00\x00\x00\xfc\xe0\xc7\x1f\x7f\xfc\xf5\xc7\xaf\x7f\xfc\xfb\xc7\xff\x7f\xfc\xef\xc7\xf7}|\xd0\xc7\x07}|\xd0\xc7\x07}|\xd0\x87\x06h\x00\x00\x00\x00\x00\xf4\xc2\x87?|\xf8\xc7\x87\xbf|\xf8\xcb\x87\xff}\xf8\xee\x87\xdf\x7f\xf8\xfc\x87\xcf\x7f\xf8\xf8\x87O\x7f\xf8\xf0G\x0ai\x00\x00\x00\x00\x00@n\x00\xfe\x1f\xf4\xfbC\x1f}\xf8\xd0\x87\x0f}\xf8\xd0\x87\x0f}\xf8\xd0\x87\x0f}\xf4\xe2\x07\xff?\xd0\xff\x01\xa4\x06\x00\x00\x00\x00\x00\xfc/\xc0\xff\x1f\xfc\xfa\xc3\x0b~\xbc\xd0\xc7\x0b~\xfc\xff\xc3\xff\x0b\xbc\x15\xc0\x0b\x00\xbc\x00\xc0\x0b\x00\xbc\x00\x80\x06\x00\x00\x00\x00\x00\x00\x80/\x00\xff\x1f\xf8\xfb\xc3\x0f>\xbc\xd0\xc7\x0b}\xbc\xd0\xc7\x0b}\xbc\xd0\xc7\x0b}\xf8\xe1C\xff/\xe0\xff\x00\xe4\x0b\x00\xf8\x01\x00?\xfc/\xc0\xff\x0f\xfc\xfe\xc2\x0b>\xbc\xe0\xc3K?\xfc\xff\xc2\xff\x0b\xbc~\xc0\xdb\x0b\xbc\xf8\xc0K/\xbc\xf0\x83\x06)\x00\x00\x00\x00\x00@/\x00\xff\x1f\xf8\xfb\x83\x0f>\xf8\x00\x80\xaf\x01\xf0\xbf\x00\xf8?\x00\xe0\x83\x06}\xfc\xe1\x87\xff?\xe0\xff\x00\xa4\x02\x00\x00\x00\x00\x00\xfd\xff\xd7\xff\xbf\xa9\xbf\x06\xf4\x01@\x1f\x00\xf4\x01@\x1f\x00\xf4\x01@\x1f\x00\xf4\x01@\x1f\x00\xf4\x01@\x1f\x00\xa0\x01\x00\x00\x00\x00\x00\xf4\xc0\x87\x1f}\xf8\xd1\x87\x1f}\xf8\xd1\x87\x1f}\xf8\xd1\x87\x1f}\xf8\xd1\x87\x1f}\xf4\xe2\x07\xff?\xd0\xff\x01\xa4\x06\x00\x00\x00\x00\x00}\xc0\xdb\x07\xbd\xbc\xd0\x87\x0f>\xf4\xe0B\x1f/\xf0\xf6\x01n\x0f\xe0\xbb\x00\xfd\x0b\xc0\x7f\x00\xfc\x03\x80?\x00\xa4\x01\x00\x00\x00\x00\x00/_\xff\xf2\xf5o\xaf\xdb\xf7\xba}\xaf\xdb\xfb\xba\xbd\xff\xc7\xbf\x7f\xfc\xfb\xc7\xaf?\xf8\xf6\x83o?\xf8\xf5B\x1a\x1a\x00\x00\x00\x00\x00}\xc0\xcb\x0f~\xf4\xf5\x02\xbf\x0f\xd0\xbf\x00\xfc\x07@/\x00\xf8\x03\xc0\x7f\x00\xfe\x0f\xf4\xf6\x82\x0f?\xbd\xd0\x97\x06h\x00\x00\x00\x00\x00?\x80\xdb\x0b\xbd\xf8\xe0C\x1f/\xf0\xf6\x01\xfe\x0f\xc0\x7f\x00\xf8\x03@/\x00\xf4\x01@\x1f\x00\xf4\x01@\x1f\x00\xa0\x01\x00\x00\x00\x00\x00\xf8\xff\x82\xff/\xa4\xfa\x02\x80\x1f\x00\xbc\x00\xe0\x07@/\x00\xfc\x01\xd0\x0b\x00~\x00\xf4\x02\x80\xff?\xf8\xffC\xaa*\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x05\x00}@\xfe\x02\xfe\x01\xb8\x01\x80\x1f\x00\xe0/\x00\xa0/\x00\x90\x07\x00P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80/\x00\xfd\x0b\xf0\xe0A\x07,8\x80\x83S88\x9f\x83\xf398\x85\x83\x038t\xc0\x02\x0f\x1e\xd0\xbf\x00\xa4\x02\x00\x00\x00\x00\x00@\x1f\x00\xff\x01\xb4\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe5\x16\xf4\xffC\xaa*\x00\x00\x00\x00\x00\x80/\x00\xff\x0bx\xe0\x01\x00,\x00\xc0\x02\x00\x1c\x00\xe0\x01\x00\x0b\x00x\x00\xe0\x02\x80\x07@\x1f\x00\xf4\xffC\xaa*\x00\x00\x00\x00\x00@\x7f\x00\xfe\x1f\xb0\xd1\x03\x008\x00\xc0\x02\x00\x0e@\x7f\x00\x90\x0f\x00\xc0\x02\x008\x00\x80\x03\x01=\xf0\xff\x00\xa9\x06\x00\x00\x00\x00\x00\x00\xd0\x01\x0e\x1d\xe0\xd0\x01\x0b\x1d\xb0\xd0A\x07\x1dt\xd0\x81\x03\x1d8\xd0\xc1\xabn\xfc\xff\x07\x00\x1d\x00\xd0\x01\x00\x19\x00\x00\x00\x00\x00\xe0\xff\x02\xfe/\xb0\x00\x00\x0b\x00\xb0\x14\x00\xff\x0b\xb0\xea\x02\x008\x00@C\x01t8\x80C\x0b=\xe0\xff\x00\xa4\x06\x00\x00\x00\x00\x00\x00\xe4\x01\xe0\x1f\xc0[\x00\x1e\x00\xb0\x00@\xe7\x0b\xb8\xfb\x82\x0788@\x83\x03t8\x80C\x0b=\xe0\xff\x00\xa4\x06\x00\x00\x00\x00\x00\xf8\xff\xcb\xff\x7fh\x95\x83\x02,(\xd0\x01\x00\x0d\x00\xe0\x00\x00\x0b\x00t\x00\xc0\x03\x00-\x00\xe0\x02\x00\x0e\x00\xa0\x00\x00\x00\x00\x00\x00\x80o\x00\xfe\x0f\xb4\xd0B\x07(t\xc0\x02^\x0e\x80\x7f\x00Z\x1e4\x80\x82\x0388\x80\x83\x0b=\xe0\xff\x01\xa4\x06\x00\x00\x00\x00\x00\x80o\x00\xfe\x0f\xb4\xd0\x82\x0388\x80\x83\x038\xb8\xd0\x03\xff:\xd0\x8b\x03\x00-\x00\xe0\x00\xe5\x0b\xe0\x1f\x00\x19\x00\x00\x00\x00\x00\x00\x00/\x00\xf4\x02\x80:\x00l\x07\xc0\xb1\x00\x0d\x0a\xe0\xe0\x00\x0a\x1d\xb0\xe5A\xff/t\x95\x83\x024,@\x97\x01`\x00\x00\x00\x00\x00\xf8/\x80\xff\x0bh\xe5\x81\x02\x1d(\xd0\x81V\x0a\xf8/\x80V\x0e(\x80\x82\x024(@\x83V=\xf8\xffA\xaa\x06\x00\x00\x00\x00\x00\x00\xbe\x01\xfc?\xf0AC\x07\x008\x00\xc0\x02\x00,\x00\xc0\x02\x00,\x00\x80\x03\x00t\x00\x00\x1f\x10\xc0\xff\x07\x90\x1a\x00\x00\x00\x00\x00\xfc\x1b\xc0\xff\x07l\xf5\xc1\x02,,\x80\xc3\x028,@\xc7\x02t,@\xc3\x028,\xc0\xc2V\x1f\xfc\x7f\x80j\x01\x00\x00\x00\x00\x00\xf8\xff\x83\xff?hU\x81\x02\x00(\x00\x80\x02\x00\xf8\xbf\x80\xff\x0b(\x00\x80\x02\x00(\x00\x80V\x15\xf8\xffC\xaa*\x00\x00\x00\x00\x00\xf8\xff\x83\xff?xU\x81\x03\x008\x00\x80\x03\x00\xb8j\x80\xff\x0bxU\x80\x03\x008\x00\x80\x03\x008\x00@\x02\x00\x00\x00\x00\x00\x00@\xbe\x00\xfd?\xf4A\x83\x03\x00,\x00\xc0\x02\x00,P\xc1\xc2\x7f,\xfc\xc7\x02t8@G\x1ft\xd0\xff\x07\xa4\x1a\x00\x00\x00\x00\x008\x80\x83\x0388\x80\x83\x0388\x80\x83\x038\xf8\xff\x83\xff?8\x80\x83\x0388\x80\x83\x0388\x80C\x02$\x00\x00\x00\x00\x00\xf4\xffB\xff/P^\x01\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe5\x15\xf4\xffB\xaa\x1a\x00\x00\x00\x00\x00\x00\xfe\x07\xe0\x7f\x00\x94\x07\x00t\x00@\x07\x00t\x00@\x07\x00t\x00@G\x02t8@C\x0b=\xe0\xff\x00\xa4\x06\x00\x00\x00\x00\x00(\x80\x83\x02((\xc0\x82\x02\x1c(\xe0\x80B\x0b(=\x80\xff\x02\xf8>\x80F\x0b(\xe0\x80\x02\x1d(\xc0B\x01$\x00\x00\x00\x00\x00(\x00\x80\x02\x00(\x00\x80\x02\x00(\x00\x80\x02\x00(\x00\x80\x02\x00(\x00\x80\x02\x00(\x00\x80V\x15\xf8\xffC\xaa*\x00\x00\x00\x00\x00\xb8\xd0\x83\x0f>\xf8\xe1\x83\x1b7\xb8v\x83g68_\x83\xf358E\x83\x0348@\x83\x0348@C\x02$\x00\x00\x00\x00\x00\xb8\x80\x83\x0b8\xf8\x81\x83\x1b8\xb8\x83\x83s88\x8a\x83\xd398\x9c\x83\x83;8\xb4\x83\x03?8\xd0C\x02(\x00\x00\x00\x00\x00\x80/\x00\xfe\x0f\xb4\xd0\x82\x038,@\xc7\x02t,@\xc7\x02t,@\xc7\x02t8\x80C\x0b-\xe0\xff\x00\xa4\x02\x00\x00\x00\x00\x00\xf8/\x80\xff\x0fh\xe5\x82\x028(\x80\x83\x028(\xc0\x83V\x1e\xf8\xbf\x80\xab\x01(\x00\x80\x02\x00(\x00@\x01\x00\x00\x00\x00\x00\x00\x80/\x00\xfe\x0f\xb4\xd0\x82\x038,@\xc7\x02t,@\xc7\x02t,@\xc7\x02t8\x80C\x0b-\xe0\xff\x00\xf4\x02\x00\x0e\x00\xe0\x02\xfc/\xc0\xff\x0fl\xe5\xc2\x02,,\x80\xc3\x02,\xbc\xea\xc1\xff\x0bl=\xc0B\x0b,\xe0\xc0\x02\x1d,\xc0\x82\x01(\x00\x00\x00\x00\x00\x80o\x00\xfe\x1f\xb4\x90A\x07\x00t\x00\x00/\x00\xd0/\x00\xe0\x0b\x00\xe4\x01\x00<\x00\x80C\x05-\xf8\xff\x00\xa9\x06\x00\x00\x00\x00\x00\xfc\xff\xc7\xff\x7fT^\x01\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\x90\x00\x00\x00\x00\x00\x008\x80\x83\x0388\x80\x83\x0388\x80\x83\x0388\x80\x83\x0388\x80\x83\x0384\x80C[-\xe0\xff\x00\xa4\x02\x00\x00\x00\x00\x00\x1d\x00\xcb\x02t8@\x87\x038t\xc0\x02\x07\x1c\xb0\xd0\x01\x0e\x0e\xd0\xa0\x00\x1d\x0b\xc0v\x00\xa8\x03@/\x00\xa4\x01\x00\x00\x00\x00\x00\x0d\x00\xda\x01\xb0\x1d\x00\xdbQ\xb0\x1c\x1f\xc7\xf2q,[\x87fvhf\x83g6\xb8\xb1C\x1b;\xf4\xf1B\x1a\x1a\x00\x00\x00\x00\x00,@G\x03(\xb0\xd0\x01\x0d\x0a\xc0v\x00\xf4\x02\x00\x1f\x00\xf0\x01@/\x00l\x07\xd0\xa0\x00\x0b\x1d4\x80\x82\x02d\x00\x00\x00\x00\x00\x1d\x00\xcb\x02t8\x80\x03\x07\x1c\xe0\xe0\x00\x1c\x07\x80:\x00\xf4\x02\x00\x1f\x00\xe0\x00\x00\x0e\x00\xe0\x00\x00\x0e\x00\x90\x00\x00\x00\x00\x00\x00\xf4\xffC\xff?P\xe5\x02\x00\x0e\x00\xb4\x00\xc0\x03\x00\x1e\x00\xb0\x00\x80\x07\x00-\x00\xe0\x00@[\x15\xf4\xffC\xaa*\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0a@\xbe\x80\xffG\xff\x07\xfc\x06\xc0\xbf\x01\xe0\xff\x01\xa0\xbf\x00\xd0\x0b\x00P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80/\x00\xfe\x0f\xf4\xfa\x82\x0b=|\xc0\xc7\xe7|\xbc\xef\xc7\xfb~|\xc5\xc7\x0b|\xb8\xd0C\xbf/\xd0\xbf\x00P\x01\x00\x00\x00\x00\x00@/@\xff\x02\xf8/@\xf6\x02\x00/\x00\xf0\x02\x00/\x00\xf0\x02\x00/\x00\xf0\x02\x00/\x80\xff\x7f\xf8\xffGU\x15\x00\x00\x00\x00\x00\x80/\x80\xff\x1f\xfc\xfaB\x03>\x00\xd0\x03\x00-\x00\xf0\x02\x80\x0f\x00~\x00\xf8\x02\xf0\x0b\x80\xbfj\xf8\xffGU\x15\x00\x00\x00\x00\x00@\x7f\x00\xff/\xf4\xe6\x03\x06|\x00\xd0\x03\x90\x1f\xc0\xff\x00\xa4?\x00\xc0\x07\x00|\x00\xc0G\xaf?\xf4\xff\x01T\x01\x00\x00\x00\x00\x00\x00\xd0\x02\x1f.\xf0\xe1B\x0f.\xf4\xe0\x82\x0b.\xb8\xe0\xc2\x07.\xbc\xe5\xd6\xff\xbf\xfd\xff\x0b\x00.\x00\xe0\x02\x00\x14\x00\x00\x00\x00\x00\xf0\xff\x02\xff?\xf4UA\x0f\x00\xf4i@\xff\x1f\xf4\xff\x03\x01|\x00\x80\xcb\x07\xb8\xb8\xc0\x87\xaf?\xe0\xff\x01P\x01\x00\x00\x00\x00\x00\x00\xe4\x01\xf4/\xd0\xff\x01\x7f\x00\xf8\x15\x80\xfb\x0f\xfc\xff\xc3\x1f}|\x80\xcb\x07\xb8\xb8\xc0\x87\xaf?\xe0\xff\x01P\x01\x00\x00\x00\x00\x00\xfd\xff\xdf\xff\xbf\xfd\xff\xc7\x03=<\xe0B\x01\x1e\x00\xf4\x01\x80\x0f\x00\xbc\x00\xd0\x07\x00>\x00\xf0\x02@\x1f\x00P\x00\x00\x00\x00\x00\x00\x80o\x00\xff/\xf8\xf6\x83\x0b=\xb8\xd0\x03\xff\x1f\xe0\xff\x80\xaf?|\xc0\xc7\x07||\xc0\x87\xaf?\xe0\xff\x01P\x01\x00\x00\x00\x00\x00\x80o\x00\xff/\xf8\xf6\xc3\x07||\xc0\xc7\x07|\xfc\xe5G\xff\x7f\xd0\xdb\x03\x00/\x00\xfdA\xff\x0b\xf0\x1b\x00\x05\x00\x00\x00\x00\x00\x00@/\x00\xf8\x03\xc0\x7f\x00\xfd\x0b\xd0\xf6\x00\x1e\x0f\xf0\xf1A_.\xf4\xff\x82\xff?\xbc\xd5\xd7\x03\xb8.@_\x01P\x00\x00\x00\x00\x00\xfc/\xc0\xff\x0f\xfc\xff\xc1\x03.<\xe0\xc2\xff\x0f\xfc\xbf\xc0\xab?<\xc0\xc7\x03\xb8<\xc0\xc7\xff\x7f\xfc\xffAU\x01\x00\x00\x00\x00\x00\x00\xbe\x01\xfe\xbf\xf4\xdb\x8b\x0f |\x00\xd0\x03\x00=\x00\xd0\x03\x00=\x00\xc0\x0b\x00\xf8\x01@\xffz\xd0\xff\x0b@\x05\x00\x00\x00\x00\x00\xfd\x1b\xd0\xff\x0b\xfd\xff\xd1\x03?=\xc0\xd7\x03|=\x80\xdb\x03\xb8=\xc0\xd7\x03}=\xe4\xd3\xff\x1f\xfd\x7f@U\x00\x00\x00\x00\x00\x00\xf8\xff\xc7\xff\xbf\xf8\xff\x87\x07\x00x\x00\x80[\x05\xfc\xff\xc1\xff\x1fx\x00\x80\x07\x00x\x00\x80\xff\x7f\xfc\xffKU\x15\x00\x00\x00\x00\x00\xfc\xff\xc7\xff\x7f\xfc\xff\xc3\x07\x00|\x00\xc0\x07\x00\xfc\xff\xc0\xff\x0f\xbcU\xc0\x07\x00|\x00\xc0\x07\x00|\x00@\x01\x00\x00\x00\x00\x00\x00@\xbe\x01\xfe\x7f\xf4\xe7\xc7\x0f$}\x00\xd0\x03\x00=\xa4\xd6\xd3\xbf=\xfc\xdb\x07\xb8\xf8\x80K\xbf\xbe\xd0\xff\x0bP\x05\x00\x00\x00\x00\x00x\xc0\xc7\x07||\xc0\xc7\x07||\xc0\xc7[}\xfc\xff\xc7\xff\x7f|\xc0\xc7\x07||\xc0\xc7\x07||\xc0G\x01\x14\x00\x00\x00\x00\x00\xf8\xff\x83\xff?\xf4\xff\x02\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x80\xff?\xf8\xffCU\x15\x00\x00\x00\x00\x00\x00\xfe\x0b\xf0\xbf\x00\xfd\x0b\x00\xb8\x00\x80\x0b\x00\xb8\x00\x80\x0b\x00\xb8\x14\x80\xcb\x07\xb8\xb8\xc0G\xbf?\xe0\xff\x01P\x01\x00\x00\x00\x00\x00<\xc0\xc3\x03|<\xd0\xc3\x03=<\xf0\xc2\x83\x0f|\xbf\xc0\xff\x07\xfc\xbf\xc0\x87\x0f<\xf0\xc1\x03><\xc0K\x01T\x00\x00\x00\x00\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\xff\x7f\xfc\xffKU\x15\x00\x00\x00\x00\x00\xfc\xe0\xc7\x1f\x7f\xfc\xf1\xc7o\x7f\xfc\xfb\xc7\xff{\xbc\xaf\xc7\xfbz|\x85\xc7\x07x|\x80\xc7\x07x|\x80G\x01\x14\x00\x00\x00\x00\x00\xb8\xc0\xc3\x0f|\xfc\xc1\xc7?|\xfc\xc7\xc7\xfb|\xbc\xdf\xc7\xe7~|\xfd\xc7\xc7\x7f|\xf4\xc7\x07\x7f|\xe0G\x01\x14\x00\x00\x00\x00\x00\x80o\x00\xff\x1f\xf8\xf6\xc3\x0b}=\x80\xdb\x03\xb8=\x80\xdb\x03\xb8=\x80\xdb\x07\xbc\xbc\xd0\x87\xaf?\xe0\xff\x00P\x01\x00\x00\x00\x00\x00\xfc/\xc0\xff\x1f\xfc\xff\xc3\x03}<\xc0\xc7\x03|<\xd0\xc7\xff/\xfc\xff\xc0\xab\x01<\x00\xc0\x03\x00<\x00@\x01\x00\x00\x00\x00\x00\x00\x80o\x00\xff\x1f\xf8\xf6\xc3\x0b}=\x80\xdb\x03\xb8=\x80\xdb\x03\xb8=\x80\xdb\x07\xbc\xbc\xd0\x87\xaf?\xe0\xff\x00\xf0\x01\x00/\x00\xe0?\xfd/\xd0\xff\x1f\xfd\xff\xd2\x03==\xc0\xd3\x03=\xfd\xff\xd2\xff\x0f}\xbd\xd0\x83\x0f=\xf0\xd1\x03>=\xd0G\x01\x14\x00\x00\x00\x00\x00\x80o\x00\xff/\xf4\xf6\x83\x0b\x18\xf8\x00@\x7f\x00\xe0\x7f\x00\xe4/\x00\xe4\x03\x00|\x04\xc0\xc7\xaf?\xf8\xff\x01T\x01\x00\x00\x00\x00\x00\xfd\xff\xdb\xff\xbf\xfd\xff\x07\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00P\x00\x00\x00\x00\x00\x00x\xc0\xc7\x07||\xc0\xc7\x07||\xc0\xc7\x07||\xc0\xc7\x07||\xc0\xc7\x07|\xb8\xd0C\xff/\xe0\xff\x00P\x01\x00\x00\x00\x00\x00/@\xef\x03\xb8=\x80\xcb\x07|\xb8\xd0C\x0b-\xf4\xe0\x02\x1f\x1f\xe0\xf6\x00\xad\x0b\xc0\xbf\x00\xfc\x07\x80?\x00P\x01\x00\x00\x00\x00\x00\x1f\x00\xff\x02\xf4/@\xff\xa2\xf5mo\xdb\xf7\xb6}\xaf\xcb\xfb\xbb\xbc\xbf\xc7\xbf\x7f\xfc\xf6\x87o?\xf8\xf6C\x05\x15\x00\x00\x00\x00\x00=\x80\xcb\x07|\xf4\xd0\x02\x1f\x1f\xd0\xbb\x00\xf8\x07@/\x00\xf8\x03\xc0\x7f\x00\xbe\x0f\xf0\xf1\x81\x0f>}\xc0[\x01T\x00\x00\x00\x00\x00/\x00\xef\x03\xb8|\xc0\x87\x0f=\xf0\xf1\x01m\x0f\xc0\xbf\x00\xf8\x03@/\x00\xf0\x01\x00\x1f\x00\xf0\x01\x00\x1f\x00P\x00\x00\x00\x00\x00\x00\xf8\xff\x83\xff\x7f\xf4\xff\x03\x00/\x00\xf8\x00\xd0\x07\x00?\x00\xf8\x01\xd0\x07\x00.\x00\xf4\x00\xc0\xff\x7f\xf8\xffGU\x15\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02@.\x00n\x00}\x00x\x00@\x0b\x00\xd0\x07\x00\xd0\x0b\x00\xd0\x03\x00 \x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80?\x00m\x0a\xa0\xc0A\x03(4\xc0\x83\x02:(\\\x83r4\xa8AC\x0740\x80\x02\x0a\x1c\xd0\xba\x00\xe4\x01\x00\x00\x00\x00\x00\x00\x1d\x00\xf8\x01\xe0\x1f\x00\xc7\x01\x00\x1c\x00\xc0\x01\x00\x1c\x00\xc0\x01\x00\x1c\x00\xc0\x01\x00\x1c\x00\xc0\x01\xa0\xae\x01U\x15\x00\x00\x00\x00\x00\x80\xbf\x00m\x0ep\xc0\x02\x02(\x00\x80\x02\x00\x1c\x00\xb0\x00\x80\x02\x00\x0d\x00p\x00\x80\x01\x00\x09\x00\xf4\xaa\x02U\x15\x00\x00\x00\x00\x00\xf4\xff\x01U\x0e\x00\xa0\x00\x80\x03\x00\x0d\x00`\x00\x80\xbf\x00\x00\x1d\x00\x80\x02\x008\x00\x80\x02\x00\x1e\xa0\x7f\x00[\x00\x00\x00\x00\x00\x00\x00x\x00\xd0\x07\x00v\x004\x07\x80q\x00\x09\x07pp@\x02\x07\x18p\xc0\xff\x7f\x00p\x00\x00\x07\x00p\x00\x00\x01\x00\x00\x00\x00\x00\xe0\xff\x01Z\x05\xa0\x00\x00\x06\x00p\x00\x00\xe7\x07\xf0\xe6\x01\x01(\x00\x80\x03\x008\x00\xc0\x02@\x0e\xe4o\x00\x15\x00\x00\x00\x00\x00\x00\x00t\x00\xc0\x02\x00\x0a\x008\x00\xd0\x00\x00\xee\x02\xb4\xe5A\x03(4@C\x0344\x80\x02\x07\x1c\xd0\xfa\x00\xe4\x01\x00\x00\x00\x00\x00\xf8\xff\x83\xff/\x00\x80\x02\x00\x1d\x00\xa0\x00\x00\x07\x004\x00\x80\x02\x00\x1c\x00\xe0\x00\x00\x07\x004\x00\x80\x02\x00\x04\x00\x00\x00\x00\x00\x00\x80\x7f\x00]\x0ep\xc0\x01\x07(p\x80\x01\x0a\x0c\x80{\x00m\x0ap\x80A\x0344@C\x07(\xe0\xea\x01\xe4\x02\x00\x00\x00\x00\x00\x80\x7f\x00]\x0ep\xc0A\x0384@C\x034p\x80\x03m.\x80\xef\x01\x00\x0b\x008\x00\xd0\x01@\x0b\x00\x14\x00\x00\x00\x00\x00\x00\x00\x0e\x00\xf0\x01\x00+\x00t\x03\x802\x00\x1c\x07\xd0\xa0\x00\x0d\x0d\xa0\xd0\x00\xff\x1f4\x80B\x034(@G\x00\x10\x00\x00\x00\x00\x00\xf4/@W\x0f4\xc0A\x03\x1c4\xc0A\x03\x09\xb4.@\x97\x0b4\xc0A\x0344@C\x03(\xb4\xfa\x01U\x01\x00\x00\x00\x00\x00@\xbf\x00l-\xa0\x00B\x07\x004\x00\x80\x02\x00(\x00\x80\x02\x00(\x00\x80\x03\x00t\x00\x00\x0b0\xd0\xea\x02\xe0\x06\x00\x00\x00\x00\x00\xf8\x07\x80\xfb\x028\xb4\x80\x03\x1d8\x80\x82\x0388@\x83\x0348\x80\x82\x03,8\xd0\x80C\x07\xf8/@\x15\x00\x00\x00\x00\x00\x00\xf4\xffBW\x154\x00@\x03\x004\x00@\x03\x00\xb4j@W\x054\x00@\x03\x004\x00@\x03\x00\xb4\xaa\x01U\x15\x00\x00\x00\x00\x00\xf4\xffBW\x154\x00@\x03\x004\x00@\x03\x004\x00@\xff\x0ftU@\x03\x004\x00@\x03\x004\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\xfe\x01|\x05\xe0\x00@\x07\x008\x00\x80\x02\x00(\xa4\x82B9(@\x83\x034t@\x03\x0a4\xd0\xab\x03\xd0\x1b\x00\x00\x00\x00\x00t\x80B\x07(t\x80B\x07(t\x80B\x07(\xf4\xffB[)t\x80B\x07(t\x80B\x07(t\x80\x02\x01\x14\x00\x00\x00\x00\x00\xe0\xff\x00\xe4\x01\x00\x0d\x00\xd0\x00\x00\x0d\x00\xd0\x00\x00\x0d\x00\xd0\x00\x00\x0d\x00\xd0\x00\x00\x0d\x00\xd0\x00\x90n\x00U\x05\x00\x00\x00\x00\x00\x00@\x03\x004\x00@\x03\x004\x00@\x03\x004\x00@\x03\x004\x00@\x03\x0140\x80\x03\x0b(\xd0\xeb\x01\xd0\x06\x00\x00\x00\x00\x00(\xc0\x81\x02\x0e(t\x80\xc2\x02(\x0a\x806\x00\xf8\x01\x80.\x00h\x07\x80\xe2\x01((\x80\x02\x07(\xd0A\x01\x14\x00\x00\x00\x00\x004\x00@\x03\x004\x00@\x03\x004\x00@\x03\x004\x00@\x03\x004\x00@\x03\x004\x00@\x03\x00\xb4\xaa\x01U\x15\x00\x00\x00\x00\x00t\xc0B\x0b,\xf4\xd0B\x1b:tqCg6$[C\xe24(I\x83\x824(@\x83\x024(@C\x01\x10\x00\x00\x00\x00\x00\xb4\x80B\x0f(\xf4\x81B+(4\x83Bs(4\x8aB\xc3(4\x98BC+4\xf0B\x03.4\xd0\x02\x01\x14\x00\x00\x00\x00\x00\x80\x7f\x00m\x0ep\xc0A\x038(@\x83\x02t(@\x87\x02t(@\x87\x0344\x80\x02\x07\x1c\xd0\xfa\x00\xe4\x01\x00\x00\x00\x00\x00\xf4/@\x97\x0f4\xc0B\x0344@C\x0344\xc0B\x97\x0f\xf4/@\x03\x004\x00@\x03\x004\x00\x00\x01\x00\x00\x00\x00\x00\x00\xc0/\x00^\x0b4\xd0\x80\x02,\x1c\x80\xc2\x018\x1c\x80\xc3\x018\x1c\x80\xc2\xd2((\xd8AC\x0f\xe0\xba\x00\xb4\x0d\x00\x80\x02\x00p\xf8/\x80\x96\x07(\xd0\x80\x02\x1c(\xc0\x81\x02\x0d(\xb9\x80\xbf\x00\xa8\x03\x80\xd2\x01((\x80\x02\x07(\xd0A\x01\x14\x00\x00\x00\x00\x00\x80\xff\x01]\x19p\x00\x00\x07\x00p\x00\x00\x1e\x00\x80o\x00\x80\x0f\x00\xc0\x02\x008\x00@\x03\x00(\xf4\xea\x01\xf4\x02\x00\x00\x00\x00\x00\xfc\xffG\xe5\x15\x00\x0d\x00\xd0\x00\x00\x0d\x00\xd0\x00\x00\x0d\x00\xd0\x00\x00\x0d\x00\xd0\x00\x00\x0d\x00\xd0\x00\x00\x0d\x00@\x00\x00\x00\x00\x00\x004@C\x0344@C\x0344@C\x0344@C\x0344@C\x0344\x80\x02\x07\x1c\xe0\xfa\x00\xe4\x02\x00\x00\x00\x00\x00\x1c\x00\x87\x0204@C\x07(p\xc0\x01\x0a\x0c\xd0\xd0\x00\x1c\x0a\xc0q\x00h\x03@'\x00\xf0\x02\x00\x1f\x00P\x00\x00\x00\x00\x00\x00\x1c\x00\x87\x02p(\x00\x87\x824$IC\xd344^\x02\xa3)0\xa6\x02k\x1a\xa0\xb1\x01\x1e\x1e\xe0\xe0\x00\x05\x04\x00\x00\x00\x00\x004\x80\x02\x07\x1c\xa0\xd0\x00\x1c\x0b\x806\x00\xf0\x01\x00\x0e\x00\xf0\x01@+\x00,\x07\xd0\xa0\x00\x06\x1c4\x80C\x01\x10\x00\x00\x00\x00\x00(\x00G\x03(p\xc0\x01\x0e\x0d\xc0q\x00h\x03\x00/\x00\xe0\x00\x00\x0d\x00\xd0\x00\x00\x0d\x00\xd0\x00\x00\x0d\x00@\x00\x00\x00\x00\x00\x00\xf4\xffC\xff/\x00\xc0\x01\x00\x0b\x004\x00\x80\x02\x00\x0d\x00p\x00@\x03\x00,\x00\xa0\x00\x00\x07\x00\xf8\xffCU\x15\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00@\x07@\x7f@\xfeA\xfe\x01\xfc\x01\xc0/\x00\xe4\x1f\x00\xe4\x1f\x00\xf4\x07\x00t\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80\x7f\x00\xfd\x0f\xf0\xe5B\x0b<x\xd0\xc7C\x7f<\xbe\xc7\xbbx\xfc\x83\x87\x0fx\xb4\xc0C_.\xd0\xff\x00\xf8\x06\x00\x00\x00\x00\x00\x00-\x00\xf8\x02\xf0/@\xef\x02 -\x00\xd0\x02\x00-\x00\xd0\x02\x00-\x00\xd0\x02\x00-\x00\xe5\x16\xf4\xff\x03\xaa*\x00\x00\x00\x00\x00\x80\xbf\x00\xfe\x1f\xf8\xe5C\x03<\x10\xc0\x03\x00-\x00\xf4\x00\xc0\x07\x00.\x00\xf8\x00\xd0\x03@o\x15\xf8\xffG\xaaj\x00\x00\x00\x00\x00\xf8\xff\x82\xff/T\xf9\x01\x80\x07\x00.\x00\xf4\x01\xc0\xff\x01T>\x00\xc0\x03\x00|\x00\xc0\x03\xa5/\xf8\xbf@\xab\x01\x00\x00\x00\x00\x00\x00\xbc\x00\xd0\x0b\x00\xbf\x00\xb4\x0b\xd0\xb7\x00^\x0b\xb4\xb4\x80C\x0b}\xb9\xd5\xff\xbfU\xb9\x05@\x0b\x00\xb4\x00@\x06\x00\x00\x00\x00\x00\xf0\xff\x02\xff/\xf0U\x01\x0b\x00\xb4\x14@\xff\x0b\xf4\xfb\x02\x0b<\x00\xc0\x07\x00|\x00\xd0C\xe9/\xf8\x7f@j\x00\x00\x00\x00\x00\x00\x00\xf8\x00\xd0\x07@/\x00\xbc\x00\xe0\x17\x00\xff\x0b\xf8\xfa\x82\x07<x\xc0\x87\x07xx\xc0C_>\xe0\xff\x00\xf8\x06\x00\x00\x00\x00\x00\xfc\xff\xc3\xff\x7f\xa8\xea\x03\x00-\x00\xf0\x01@\x0b\x00x\x00\xc0\x03\x00-\x00\xf0\x01@\x0b\x00\xbc\x00\xd0\x03\x00)\x00\x00\x00\x00\x00\x00\x80\x7f\x00\xfe\x0f\xf4\xe5B\x0b<\xb4\xc0\x03\x1f\x1e\xd0\xbf\x00\xfe\x1f\xb4\xd0\x82\x07xx\x80\x87_=\xf0\xff\x01\xf8\x06\x00\x00\x00\x00\x00\x80\x7f\x00\xfe\x0f\xf4\xe5\x83\x07<x\x80\x87\x07x\xf8\xd1\x07\xff?\xd0\xff\x02\x90\x1f\x00|\x00\xf0\x02\x80\x0b\x00)\x00\x00\x00\x00\x00\x00\x00\x1f\x00\xf0\x02@?\x00\xf8\x07\xc0\xbb\x00m\x0b\xe0\xf2\x00\x1e\x1e\xf0\xe6A\xff/\xb8\xd5\xc3\x07x=@\x9b\x01d\x00\x00\x00\x00\x00\xf8o\x80\xff\x0f\xb8\xf5\x82\x07-x\xd0\x82G\x1f\xf8\xbf\x80\xff\x1fx\xe0\x83\x07xx\x80\x87[~\xf8\xffA\xaa\x06\x00\x00\x00\x00\x00@\xbf\x00\xfd?\xf0\xd6G\x0b\x10|\x00\xc0\x03\x00<\x00\xc0\x03\x00<\x00\xc0\x07\x00\xb8\x00Bo\xb9\xd0\xff\x02\xe4\x0a\x00\x00\x00\x00\x00\xf8\x07\xc0\xff\x03\xbc\xfe\xc0\x07.|\xd0\xc3\x07||\x80\xc7\x07x|\xc0\xc3\x07=|\xe0\xc1\xeb\x0f\xfc/\x80j\x00\x00\x00\x00\x00\x00\xf8\xff\x82\xff?\xb8U\x81\x07\x00x\x00\x80\x07\x00\xf8\xff\x80\xff\x0fx\x00\x80\x07\x00x\x00\x80[\x15\xf8\xffC\xaa*\x00\x00\x00\x00\x00\xf8\xff\x82\xff?\xb8U\x81\x07\x00x\x00\x80\x07\x00\xb8U\x80\xff\x1f\xf8\xff\x81\x07\x00x\x00\x80\x07\x00x\x00@\x06\x00\x00\x00\x00\x00\x00\x00\xfe\x02\xfc/\xf0VA\x0b\x00|\x00\xc0\x03\x00<\xfc\xc7\xc3\x7f<\x80\xc7\x07x\xb8\x80Goy\xd0\xff\x07\xe4+\x00\x00\x00\x00\x00t\xc0\x83\x0b<\xb8\xc0\x83\x0b<\xb8\xc0\x83[=\xf8\xff\x83\xff?\xb8\xc0\x83\x0b<\xb8\xc0\x83\x0b<\xb8\xc0C\x06(\x00\x00\x00\x00\x00\xe0\xff\x01\xfe\x1f@.\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe4\x02\xe0\xff\x01\xaa\x1a\x00\x00\x00\x00\x00\x00\x80\x03\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\x07\x02xx\xc0Go=\xd0\xff\x01\xe4\x0b\x00\x00\x00\x00\x00,\xc0\xc7\x03.<\xf8\xc0\xd3\x03|\x1f\xc0{\x00\xfc\x02\xc0?\x00\xbc\x0b\xc0\xf3\x02<}\xc0\x83\x1f<\xe0\x83\x02h\x00\x00\x00\x00\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80\x07\x00x\x00\x80[\x15\xf8\xffC\xaa*\x00\x00\x00\x00\x00\xb4\xc0\x83\x0f=\xf8\xe1\x83\x1f?\xf8\xf7\x87\xbb{x\xaf\x87\xf3y<\x9e\xc7\xd3x<\x84\xc7\x03x<@\x87\x02d\x00\x00\x00\x00\x00\xb4\x80\x83\x0f<\xf8\xc2\x83?<\xf8\xc7\x83\xbb<x\xdf\x83\xd7=x\xec\x83\x87?x\xf4\x83\x07?x\xe0C\x06)\x00\x00\x00\x00\x00\x80\x7f\x00\xfe\x0f\xf4\xe5\x82\x07<|\x80\xc7\x03\xb8<\x80\xcb\x03\xb8<\x80\xcb\x07xx\xc0C_.\xe0\xff\x00\xf8\x06\x00\x00\x00\x00\x00\xf8o\x80\xff\x0f\xb8\xe9\x83\x07xx\x80\x87\x07xx\xd4\x83\xff\x1f\xf8\xbf\x80[\x00x\x00\x80\x07\x00x\x00@\x02\x00\x00\x00\x00\x00\x00\xc0/\x00\xff\x0b\xf8\xf5\xc1\x03-=\xc0\xd3\x02|-\xc0\xd7\x02|-\xc8\xd3\xe3=<\xfc\x82\xdb\x1f\xf0\xff\x00\xf9>\x00\x80\x07\x00\xf4\xfc/\xc0\xff\x0b|\xf9\xc1\x03-<\xd0\xc2\x03\x1e|\xfe\xc0\xff\x02\xfc\x0b\xc0\xf7\x02<|\xc0C\x0f<\xe0\x82\x02h\x00\x00\x00\x00\x00\x80\xff\x02\xfe?\xf4\x95A\x0b\x00\xf4\x00\x00\x7f\x00\xd0\xbf\x00\xe0/\x00\xe0\x03\x00|\x00\x80\x87Z=\xf8\xffA\xf9\x06\x00\x00\x00\x00\x00\xfd\xff\xdb\xff\xbfTo\x05\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\x90\x01\x00\x00\x00\x00\x00x\x80\x83\x07xx\x80\x87\x07xx\x80\x87\x07xx\x80\x87\x07xx\x80\x87\x07xx\xc0C_>\xe0\xff\x01\xf8\x06\x00\x00\x00\x00\x00-\x00\xdb\x03\xb4|\x80\x87\x07<\xb4\xd0\x02\x0f\x1d\xe0\xe1\x01-\x0f\xd0\xb6\x00\xbc\x07\x80?\x00\xf4\x03\x00/\x00\xa0\x01\x00\x00\x00\x00\x00-\x00\xdb\x02\xb4<D\xcb\xd3t<\x8e\x87\xe7yx\xafC\xfb>\xf4\xffC\xbf/\xf0\xf6\x02//\xf0\xf1\x01\x0a\x19\x00\x00\x00\x00\x00<\x80\x87\x0b<\xf0\xe1\x02.\x0f\xc0\xbb\x00\xf4\x03\x00/\x00\xf4\x02\x80?\x00\xbd\x0b\xe0\xf1A\x0f>x\xc0\x97\x02d\x00\x00\x00\x00\x00-@\xcb\x07x\xf4\xd0\x03\x1f\x1e\xd0\xf6\x00\xfc\x07@?\x00\xf0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\xe0\x01\x00\x1e\x00\x90\x01\x00\x00\x00\x00\x00\xf8\xff\x83\xff\x7f\xa4\xfa\x03\x00\x0f\x00\xb8\x00\xc0\x03\x00/\x00\xf4\x00\x80\x07\x00=\x00\xf0\x01\x80\xaf*\xfc\xff\x87\xaaj\x00\x00\x00\x00\x00" }

// The gap-free ink bitmap: 1 where a pixel is darker than Otsu's threshold (or lighter when that is the minority).
fn mrz_ink(a: *mem.Arena, luma: []const u8, w: usize, h: usize) -> ([]u8, err) {
    let (ink, ink_error) = mem.alloc[u8](a, w * h + 1usize)
    if ink_error != ok { ret (zero, ink_error) }
    var hist: [256]u32 = zero
    var i = 0usize
    while i < w * h {
        hist[usize(luma[i])] += 1u32
        i += 1usize
    }
    let total = f64(w * h)
    var all = 0.0f64
    var t = 0usize
    while t < 256usize {
        all += f64(t) * f64(hist[t])
        t += 1usize
    }
    var wb = 0.0f64
    var sb = 0.0f64
    var best = 0.0f64 - 1.0f64
    var thr = 128usize
    t = 0usize
    while t < 256usize {
        wb += f64(hist[t])
        if wb != 0.0f64 {
            let wf = total - wb
            if wf == 0.0f64 { t = 256usize } else {
                sb += f64(t) * f64(hist[t])
                let num = sb * wf - (all - sb) * wb
                let between = num * num / (wb * wf)
                if between > best {
                    best = between
                    thr = t
                }
            }
        }
        t += 1usize
    }
    var dark = 0usize
    i = 0usize
    while i < w * h {
        if usize(luma[i]) < thr {
            ink[i] = 1u8
            dark += 1usize
        } else {
            ink[i] = 0u8
        }
        i += 1usize
    }
    if dark * 2usize > w * h {
        i = 0usize
        while i < w * h {
            ink[i] = 1u8 - ink[i]
            i += 1usize
        }
    }
    ret (ink, ok)
}

// Area-average the box [x0, x1) x [y0, y1) of the ink bitmap to 10 x 16 coverage 0..255 into `out`, then quantise to
// four levels and blur 3 x 3 (edge cells repeated): the form a template has. Columns and rows outside the image count
// as no ink and the box keeps its size.
fn mrz_cell(ink: []const u8, w: usize, h: usize, x0: i64, x1: i64, y0: i64, y1: i64, out: []u8) {
    var raw: [160]u8 = zero
    let bw = x1 - x0
    let bh = y1 - y0
    var j = 0usize
    while j < MRZ_CELL_H {
        let ya = y0 + i64(j) * bh / i64(MRZ_CELL_H)
        var yb = y0 + i64(j + 1usize) * bh / i64(MRZ_CELL_H)
        if yb < ya + 1i64 { yb = ya + 1i64 }
        var i = 0usize
        while i < MRZ_CELL_W {
            let xa = x0 + i64(i) * bw / i64(MRZ_CELL_W)
            var xb = x0 + i64(i + 1usize) * bw / i64(MRZ_CELL_W)
            if xb < xa + 1i64 { xb = xa + 1i64 }
            var sum = 0i64
            var y = ya
            while y < yb {
                if y >= 0i64 && y < i64(h) {
                    var x = xa
                    while x < xb {
                        if x >= 0i64 && x < i64(w) { sum += i64(ink[usize(y) * w + usize(x)]) }
                        x += 1i64
                    }
                }
                y += 1i64
            }
            let area = (yb - ya) * (xb - xa)
            let coverage = sum * 255i64 / area
            // Four levels, back to 0..255 in steps of 85.
            let level = (coverage * 3i64 + 127i64) / 255i64
            raw[j * MRZ_CELL_W + i] = u8(level * 85i64)
            i += 1usize
        }
        j += 1usize
    }
    mrz_blur(raw[0usize..160usize], out)
}

fn mrz_blur(src: []const u8, out: []u8) {
    var j = 0usize
    while j < MRZ_CELL_H {
        var i = 0usize
        while i < MRZ_CELL_W {
            var sum = 0usize
            var dj = 0usize
            while dj < 3usize {
                var di = 0usize
                while di < 3usize {
                    var jj = j + dj
                    var ii = i + di
                    // Index jj - 1, clamped.
                    if jj == 0usize { jj = 1usize }
                    if jj > MRZ_CELL_H { jj = MRZ_CELL_H }
                    if ii == 0usize { ii = 1usize }
                    if ii > MRZ_CELL_W { ii = MRZ_CELL_W }
                    var weight = 1usize
                    if dj == 1usize { weight = weight * 2usize }
                    if di == 1usize { weight = weight * 2usize }
                    sum += weight * usize(src[(jj - 1usize) * MRZ_CELL_W + (ii - 1usize)])
                    di += 1usize
                }
                dj += 1usize
            }
            out[j * MRZ_CELL_W + i] = u8(sum / 16usize)
            i += 1usize
        }
        j += 1usize
    }
}

// The templates unpacked (two bits a value, four to a byte) and blurred: 296 cells of 160 bytes.
fn mrz_load(a: *mem.Arena) -> ([]u8, err) {
    let packed = mrz_templates()
    let count = MRZ_VARIANTS * MRZ_SYMBOLS
    let (cells, cells_error) = mem.alloc[u8](a, count * MRZ_CELL)
    if cells_error != ok { ret (zero, cells_error) }
    var raw: [160]u8 = zero
    var t = 0usize
    while t < count {
        var k = 0usize
        while k < MRZ_CELL {
            let byte = packed[t * 40usize + k / 4usize]
            raw[k] = ((byte >> u32((k % 4usize) * 2usize)) & 3u8) * 85u8
            k += 1usize
        }
        mrz_blur(raw[0usize..160usize], cells[t * MRZ_CELL..(t + 1usize) * MRZ_CELL])
        t += 1usize
    }
    ret (cells, ok)
}

// The best and second-best distinct symbol of `cell` (indexes into the symbol table) and their distances.
type MrzGuess = struct { first: usize, first_d: u32, second: usize, second_d: u32 }

fn mrz_classify(cell: []const u8, templates: []const u8) -> MrzGuess {
    var best_of: [37]u32 = zero
    var s = 0usize
    while s < MRZ_SYMBOLS {
        best_of[s] = 4294967295u32
        s += 1usize
    }
    var t = 0usize
    while t < MRZ_VARIANTS * MRZ_SYMBOLS {
        let symbol = t % MRZ_SYMBOLS
        let base = t * MRZ_CELL
        var d = 4294967295u32
        var dx = 0usize
        while dx < 3usize {
            // dx 0: one column left, 1: none, 2: one right.
            var sum = 0u32
            var j = 0usize
            while j < MRZ_CELL_H {
                var i = 0usize
                while i < MRZ_CELL_W {
                    var value = 0i32
                    if dx == 1usize {
                        value = i32(cell[j * MRZ_CELL_W + i])
                    } else if dx == 2usize {
                        if i >= 1usize { value = i32(cell[j * MRZ_CELL_W + i - 1usize]) }
                    } else {
                        if i + 1usize < MRZ_CELL_W { value = i32(cell[j * MRZ_CELL_W + i + 1usize]) }
                    }
                    let diff = value - i32(templates[base + j * MRZ_CELL_W + i])
                    sum += u32(diff * diff)
                    i += 1usize
                }
                j += 1usize
            }
            var scored = sum / 16u32
            if dx != 1usize { scored += 40u32 }
            if scored < d { d = scored }
            dx += 1usize
        }
        if d < best_of[symbol] { best_of[symbol] = d }
        t += 1usize
    }
    var guess = MrzGuess { first: 0usize, first_d: 4294967295u32, second: 0usize, second_d: 4294967295u32 }
    s = 0usize
    while s < MRZ_SYMBOLS {
        if best_of[s] < guess.first_d {
            guess.second = guess.first
            guess.second_d = guess.first_d
            guess.first = s
            guess.first_d = best_of[s]
        } else if best_of[s] < guess.second_d {
            guess.second = s
            guess.second_d = best_of[s]
        }
        s += 1usize
    }
    ret guess
}

fn mrz_to_digit(c: u8) -> u8 {
    if c == 79u8 || c == 68u8 || c == 81u8 { ret 48u8 }
    if c == 73u8 || c == 76u8 { ret 49u8 }
    if c == 66u8 { ret 56u8 }
    if c == 83u8 { ret 53u8 }
    if c == 90u8 { ret 50u8 }
    if c == 71u8 { ret 54u8 }
    ret c
}

fn mrz_to_letter(c: u8) -> u8 {
    if c == 48u8 { ret 79u8 }
    if c == 49u8 { ret 73u8 }
    if c == 56u8 { ret 66u8 }
    if c == 53u8 { ret 83u8 }
    if c == 50u8 { ret 90u8 }
    if c == 54u8 { ret 71u8 }
    ret c
}

// Digits for the numeric fields of line 2 and letters for the alphabetic ones, in place.
fn mrz_context(line1: []u8, line2: []u8) {
    var i = 0usize
    while i < 44usize {
        line1[i] = mrz_to_letter(line1[i])
        i += 1usize
    }
    // Line 2: 0..9 document number (alnum), 9 check, 10..13 nationality, 13..19 birth, 19 check, 20 sex,
    // 21..27 expiry, 27 check, 28..42 personal number (alnum), 42 and 43 check digits.
    line2[9usize] = mrz_to_digit(line2[9usize])
    i = 10usize
    while i < 13usize {
        line2[i] = mrz_to_letter(line2[i])
        i += 1usize
    }
    i = 13usize
    while i < 20usize {
        line2[i] = mrz_to_digit(line2[i])
        i += 1usize
    }
    line2[20usize] = mrz_to_letter(line2[20usize])
    i = 21usize
    while i < 28usize {
        line2[i] = mrz_to_digit(line2[i])
        i += 1usize
    }
    line2[42usize] = mrz_to_digit(line2[42usize])
    line2[43usize] = mrz_to_digit(line2[43usize])
}

// The 44 cell boxes (left, right) of the line in rows [y0, y1): the ink runs when there are exactly 44, else the best
// grid. Returns false when the line holds no ink.
fn mrz_boxes(a: *mem.Arena, ink: []const u8, w: usize, y0: usize, y1: usize, left: []i64, right: []i64) -> bool {
    let (cols, cols_error) = mem.alloc[u32](a, w + 1usize)
    if cols_error != ok { ret false }
    var x = 0usize
    while x < w {
        var c = 0u32
        var y = y0
        while y < y1 {
            c += u32(ink[y * w + x])
            y += 1usize
        }
        cols[x] = c
        x += 1usize
    }
    var first = w
    var last = 0usize
    var runs = 0usize
    var inside = false
    x = 0usize
    while x < w {
        if cols[x] > 0u32 {
            if x < first { first = x }
            last = x
            if !inside {
                inside = true
                runs += 1usize
            }
        } else {
            inside = false
        }
        x += 1usize
    }
    if first >= w { ret false }
    let span = last - first + 1usize
    let n = MRZ_LINE
    let pitch4 = 16usize * span / (4usize * n - 1usize)
    if runs == n {
        let half = i64((pitch4 + 2usize) / 4usize)
        var k = 0usize
        var begin = 0usize
        inside = false
        x = 0usize
        while x <= w && k < n {
            var here = false
            if x < w && cols[x] > 0u32 { here = true }
            if here && !inside {
                begin = x
                inside = true
            }
            if !here && inside {
                inside = false
                let c2 = i64(begin) + i64(x)
                let xa = (c2 - half + 4096i64) / 2i64 - 2048i64
                left[k] = xa
                right[k] = xa + half
                k += 1usize
            }
            x += 1usize
        }
        ret true
    }
    var best_cost = 4294967295u32
    var best_p4 = 0usize
    var best_phase4 = 0i64
    var p4 = span * 4usize / n
    let p4_max = span * 40usize / (n * 10usize - 6usize) + 1usize
    while p4 <= p4_max {
        var window = 18usize * p4 / 400usize
        if window < 1usize { window = 1usize }
        var phase4 = i64(first * 4usize) - i64(45usize * p4 / 100usize)
        while phase4 <= i64(first * 4usize) + 1i64 {
            var cost = 0u32
            var k = 1usize
            while k < n {
                let xb = (phase4 + i64(k * p4) + 2i64 + 8192i64) / 4i64 - 2048i64
                if xb >= 0i64 && xb < i64(w) {
                    var lo = xb - i64(window)
                    if lo < 0i64 { lo = 0i64 }
                    var hi = xb + i64(window)
                    if hi >= i64(w) { hi = i64(w) - 1i64 }
                    var xx = lo
                    while xx <= hi {
                        cost += cols[usize(xx)]
                        xx += 1i64
                    }
                }
                k += 1usize
            }
            if cost < best_cost {
                best_cost = cost
                best_p4 = p4
                best_phase4 = phase4
            }
            phase4 += 1i64
        }
        p4 += 1usize
    }
    let half = i64((best_p4 + 2usize) / 4usize)
    var k = 0usize
    while k < n {
        let xa = (best_phase4 + i64(k * best_p4) + 2i64 + 8192i64) / 4i64 - 2048i64
        let xb = (best_phase4 + i64((k + 1usize) * best_p4) + 2i64 + 8192i64) / 4i64 - 2048i64
        var lo = xa
        if lo < 0i64 { lo = 0i64 }
        var hi = xb
        if hi < 0i64 { hi = 0i64 }
        var a_ink = 0i64 - 1i64
        var b_ink = 0i64 - 1i64
        var xx = lo
        while xx < hi && xx < i64(w) {
            if cols[usize(xx)] > 0u32 {
                if a_ink < 0i64 { a_ink = xx - lo }
                b_ink = xx - lo
            }
            xx += 1i64
        }
        if a_ink >= 0i64 {
            let c2 = 2i64 * lo + a_ink + b_ink + 1i64
            let xa2 = (c2 - half + 4096i64) / 2i64 - 2048i64
            left[k] = xa2
            right[k] = xa2 + half
        } else {
            left[k] = xa
            right[k] = xb
        }
        k += 1usize
    }
    ret true
}

// The two lines of the zone in the luminance image `luma` (`w` x `h`): the characters as read, `verified` when
// `valid.mrz_td3` accepts them (after context and at most eight second choices; `changes` counts those), else the best
// reading with `verified` false. `NoZone` when there are not two lines of the same height or a line is not 44 wide.
fn mrz_read(a: *mem.Arena, luma: []const u8, w: usize, h: usize) -> (MrzRead, err) {
    if w < 64usize || h < 16usize || luma.len < w * h { ret (zero, Invalid) }
    let (ink, ink_error) = mrz_ink(a, luma, w, h)
    if ink_error != ok { ret (zero, ink_error) }
    let (templates, templates_error) = mrz_load(a)
    if templates_error != ok { ret (zero, templates_error) }
    // Text lines.
    var starts: [64]usize = zero
    var ends: [64]usize = zero
    var count = 0usize
    var inside = false
    var begin = 0usize
    var y = 0usize
    while y <= h {
        var any = false
        if y < h {
            var x = 0usize
            while x < w && !any {
                if ink[y * w + x] != 0u8 { any = true }
                x += 1usize
            }
        }
        if any && !inside {
            inside = true
            begin = y
        }
        if !any && inside {
            inside = false
            if count > 0usize && begin - ends[count - 1usize] < 2usize {
                ends[count - 1usize] = y
            } else if count < 64usize {
                starts[count] = begin
                ends[count] = y
                count += 1usize
            }
        }
        y += 1usize
    }
    // Only lines at least six rows tall; the last two of about the same height.
    var kept = 0usize
    var s2: [64]usize = zero
    var e2: [64]usize = zero
    var src = 0usize
    while src < count {
        if ends[src] - starts[src] >= 6usize {
            s2[kept] = starts[src]
            e2[kept] = ends[src]
            kept += 1usize
        }
        src += 1usize
    }
    var pick_a = 99usize
    var pick_b = 99usize
    var i = kept
    while i > 1usize && pick_b == 99usize {
        i -= 1usize
        let h2 = e2[i] - s2[i]
        let h1 = e2[i - 1usize] - s2[i - 1usize]
        var dh = h1 - h2
        if h2 > h1 { dh = h2 - h1 }
        var tall = h1
        if h2 > h1 { tall = h2 }
        if dh * 3usize <= tall {
            pick_a = i - 1usize
            pick_b = i
        }
    }
    if pick_b == 99usize { ret (zero, NoZone) }
    var chars: [88]u8 = zero
    var second: [88]u8 = zero
    var margin: [88]u32 = zero
    var line = 0usize
    while line < 2usize {
        var ya = s2[pick_a]
        var yb = e2[pick_a]
        if line == 1usize {
            ya = s2[pick_b]
            yb = e2[pick_b]
        }
        // Body rows: those holding a quarter of the busiest row's ink.
        var busiest = 0u32
        var r = ya
        while r < yb {
            var c = 0u32
            var x = 0usize
            while x < w {
                c += u32(ink[r * w + x])
                x += 1usize
            }
            if c > busiest { busiest = c }
            r += 1usize
        }
        var b0 = yb
        var b1 = ya
        r = ya
        while r < yb {
            var c = 0u32
            var x = 0usize
            while x < w {
                c += u32(ink[r * w + x])
                x += 1usize
            }
            if c * 4u32 >= busiest {
                if r < b0 { b0 = r }
                b1 = r + 1usize
            }
            r += 1usize
        }
        b1 = b1 + (b1 - b0) / 5usize
        var left: [44]i64 = zero
        var right: [44]i64 = zero
        if !mrz_boxes(a, ink, w, b0, b1, left[0usize..44usize], right[0usize..44usize]) { ret (zero, NoZone) }
        var cell: [160]u8 = zero
        var k = 0usize
        while k < 44usize {
            mrz_cell(ink, w, h, left[k], right[k], i64(b0), i64(b1), cell[0usize..160usize])
            let guess = mrz_classify(cell[0usize..160usize], templates)
            chars[line * 44usize + k] = mrz_symbol(guess.first)
            second[line * 44usize + k] = mrz_symbol(guess.second)
            margin[line * 44usize + k] = guess.second_d - guess.first_d
            k += 1usize
        }
        line += 1usize
    }
    var result: MrzRead = zero
    var l1: [44]u8 = zero
    var l2: [44]u8 = zero
    var copy = 0usize
    while copy < 44usize {
        l1[copy] = chars[copy]
        l2[copy] = chars[44usize + copy]
        copy += 1usize
    }
    mrz_context(l1[0usize..44usize], l2[0usize..44usize])
    result.line1 = l1
    result.line2 = l2
    if valid.mrz_td3(l1[0usize..44usize], l2[0usize..44usize]) {
        result.verified = true
        ret (result, ok)
    }
    // The eight least certain cells (smallest margin), tried with their second choices in every combination; the
    // fewest changes that satisfy every check digit.
    var pick_line: [8]usize = zero
    var pick_pos: [8]usize = zero
    var pick_margin: [8]u32 = zero
    var picked = 0usize
    while picked < 8usize {
        var best_margin = 4294967295u32
        var best_l = 0usize
        var best_k = 0usize
        var found = false
        var ll = 0usize
        while ll < 2usize {
            var kk = 0usize
            while kk < 44usize {
                var taken = false
                var q = 0usize
                while q < picked {
                    if pick_line[q] == ll && pick_pos[q] == kk { taken = true }
                    q += 1usize
                }
                if !taken && margin[ll * 44usize + kk] < best_margin {
                    best_margin = margin[ll * 44usize + kk]
                    best_l = ll
                    best_k = kk
                    found = true
                }
                kk += 1usize
            }
            ll += 1usize
        }
        if found {
            pick_line[picked] = best_l
            pick_pos[picked] = best_k
            pick_margin[picked] = best_margin
            picked += 1usize
        } else {
            picked = 8usize
        }
    }
    var best_changes = 99usize
    var mask = 1usize
    while mask < 256usize {
        var t1: [44]u8 = zero
        var t2: [44]u8 = zero
        var cp = 0usize
        while cp < 44usize {
            t1[cp] = chars[cp]
            t2[cp] = chars[44usize + cp]
            cp += 1usize
        }
        var changes = 0usize
        var bit = 0usize
        while bit < 8usize {
            if ((mask >> u32(bit)) & 1usize) == 1usize {
                if pick_line[bit] == 0usize { t1[pick_pos[bit]] = second[pick_pos[bit]] } else { t2[pick_pos[bit]] = second[44usize + pick_pos[bit]] }
                changes += 1usize
            }
            bit += 1usize
        }
        if changes < best_changes {
            mrz_context(t1[0usize..44usize], t2[0usize..44usize])
            if valid.mrz_td3(t1[0usize..44usize], t2[0usize..44usize]) {
                best_changes = changes
                result.line1 = t1
                result.line2 = t2
                result.verified = true
                result.changes = changes
            }
        }
        mask += 1usize
    }
    ret (result, ok)
}
