// Image filters and segmentation over plain caller-owned grids: a grid is `w*h`
// values row-major, `[]f64` unless a function says `[]u8` (binary or 8-bit) or
// `[]u32` (labels). Nothing allocates; every scratch area is a parameter whose
// required length is stated beside it. Borders reflect the scipy way
// (`d c b a | a b c d`) wherever a border matters.
//
// Smoothing and edges: `gaussian_blur` (separable, radius `int(4*sigma + 0.5)`
// like scipy's `truncate=4`), `sobel` (scipy's 3x3 masks and the magnitude),
// `canny` (blur, Sobel, bilinear non-maximum suppression as scikit-image does it,
// hysteresis over 8-neighbours; the one-pixel border is never an edge), `median`,
// `bilateral` (window radius `ceil(2*sigma_s)`), `guided` (He et al., box means
// over the in-bounds window), `box_mean`. Integral images: `integral_image` /
// `integral_sum` over `f64`, `integral_image_u8` / `integral_sum_u64` exact over
// bytes; the table is `(w+1)*(h+1)` with a zero first row and column.
// `threshold_otsu` is scikit-image's argmax over the 256-bin histogram.
// Morphology with a `(2r+1)` square: `morph_erode`, `morph_dilate`, `morph_open`,
// `morph_close`. Regions: `label_components` (4 or 8, labels numbered by first
// raster appearance like scipy), `flood_fill` and `flood_fill_scanline`
// (4-connected, explicit stack), `distance_transform` (Felzenszwalb-Huttenlocher
// exact squared Euclidean distance to the nearest zero), `max_rectangle` (largest
// all-ones rectangle by the histogram stack), `mean_shift` (flat spatial and
// range kernel, modes merged greedily) and `watershed` (Meyer's priority flood,
// 4-connected, ties by age: scikit-image's ordering). Eikonal solvers with unit
// spacing and the Godunov update: `fast_marching` (binary heap with decrease-key)
// and `fast_sweeping` (Zhao's four orderings per sweep). Pyramids:
// `laplacian_pyramid` and `laplacian_collapse` with the 5-tap [1 4 6 4 1]/16
// kernel, reduce keeping the even samples, expand by zero insertion and doubling;
// level i+1 is `ceil(w/2) x ceil(h/2)`, the last level is the Gaussian residual,
// `pyramid_size` counts the storage.

use e.math

type Rect = struct { x: usize, y: usize, w: usize, h: usize, area: usize }
error TooSmall
error Invalid
error TooLarge

fn inf() -> f64 { ret 100000000000000000000.0f64 }

// Half-sample symmetric reflection of `i` into `[0, n)`.
fn reflect(i: i64, n: usize) -> usize {
    let bound = i64(n)
    var v = i
    while v < 0i64 || v >= bound {
        if v < 0i64 { v = 0i64 - v - 1i64 }
        if v >= bound { v = 2i64 * bound - v - 1i64 }
    }
    ret usize(v)
}

// ---- separable convolution ---------------------------------------------------

fn conv_h(src: []const f64, w: usize, h: usize, r: usize, k: []const f64, dst: []f64) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var acc = 0.0f64
            var j = 0usize
            while j <= 2usize * r {
                acc += k[j] * src[y * w + reflect(i64(x) + i64(j) - i64(r), w)]
                j += 1usize
            }
            dst[y * w + x] = acc
            x += 1usize
        }
        y += 1usize
    }
}

fn conv_v(src: []const f64, w: usize, h: usize, r: usize, k: []const f64, dst: []f64) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var acc = 0.0f64
            var j = 0usize
            while j <= 2usize * r {
                acc += k[j] * src[reflect(i64(y) + i64(j) - i64(r), h) * w + x]
                j += 1usize
            }
            dst[y * w + x] = acc
            x += 1usize
        }
        y += 1usize
    }
}

// Separable Gaussian, radius `int(4*sigma + 0.5)` (at most 64), reflected borders;
// `scratch` holds `w*h`.
fn gaussian_blur(src: []const f64, w: usize, h: usize, sigma: f64, dst: []f64, scratch: []f64) -> err {
    let n = w * h
    if src.len < n || dst.len < n || scratch.len < n { ret TooSmall }
    if !(sigma > 0.0f64) { ret Invalid }
    let r = usize(4.0f64 * sigma + 0.5f64)
    // ponytail: the kernel lives in a local array, so the radius stops at 64 (sigma ~16).
    if r > 64usize { ret TooLarge }
    var kernel: [129]f64 = zero
    var total = 0.0f64
    var j = 0usize
    while j <= 2usize * r {
        let d = f64(j) - f64(r)
        kernel[j] = math.exp[f64]((0.0f64 - 0.5f64) * (d * d) / (sigma * sigma))
        total += kernel[j]
        j += 1usize
    }
    j = 0usize
    while j <= 2usize * r {
        kernel[j] = kernel[j] / total
        j += 1usize
    }
    conv_h(src, w, h, r, kernel[..2usize * r + 1usize], scratch)
    conv_v(scratch, w, h, r, kernel[..2usize * r + 1usize], dst)
    ret ok
}

// scipy's Sobel: `gx` is `[-1 0 1]` along x smoothed by `[1 2 1]` along y, `gy` the
// transpose, `magnitude` their Euclidean length.
fn sobel(src: []const f64, w: usize, h: usize, gx: []f64, gy: []f64, magnitude: []f64) -> err {
    let n = w * h
    if src.len < n || gx.len < n || gy.len < n || magnitude.len < n { ret TooSmall }
    var y = 0usize
    while y < h {
        let ym = reflect(i64(y) - 1i64, h) * w
        let yp = reflect(i64(y) + 1i64, h) * w
        let yc = y * w
        var x = 0usize
        while x < w {
            let xm = reflect(i64(x) - 1i64, w)
            let xp = reflect(i64(x) + 1i64, w)
            let dx = (src[ym + xp] - src[ym + xm]) + 2.0f64 * (src[yc + xp] - src[yc + xm]) + (src[yp + xp] - src[yp + xm])
            let dy = (src[yp + xm] - src[ym + xm]) + 2.0f64 * (src[yp + x] - src[ym + x]) + (src[yp + xp] - src[ym + xp])
            gx[yc + x] = dx
            gy[yc + x] = dy
            magnitude[yc + x] = math.sqrt[f64](dx * dx + dy * dy)
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// Canny edges into `edges` (1 on an edge, 0 off); answers the edge count.
// `scratch` holds `4*w*h`. Magnitudes below `low` are dropped, at or above `high`
// seed the hysteresis, which keeps every 8-connected chain reaching a seed.
fn canny(src: []const f64, w: usize, h: usize, low: f64, high: f64, sigma: f64, edges: []u8, scratch: []f64) -> (usize, err) {
    let n = w * h
    if src.len < n || edges.len < n || scratch.len < 4usize * n { ret (0usize, TooSmall) }
    if w < 3usize || h < 3usize { ret (0usize, Invalid) }
    let blur_error = gaussian_blur(src, w, h, sigma, scratch[..n], scratch[n..2usize * n])
    if blur_error != ok { ret (0usize, blur_error) }
    let gx = scratch[n..2usize * n]
    let gy = scratch[2usize * n..3usize * n]
    let mag = scratch[3usize * n..4usize * n]
    let _ = sobel(scratch[..n], w, h, gx, gy, mag)
    var i = 0usize
    while i < n {
        edges[i] = 0u8
        i += 1usize
    }
    var y = 1usize
    while y + 1usize < h {
        var x = 1usize
        while x + 1usize < w {
            i = y * w + x
            let m = mag[i]
            if m >= low {
                let ax = math.abs[f64](gx[i])
                let ay = math.abs[f64](gy[i])
                var sx = 1i64
                if gx[i] < 0.0f64 { sx = 0i64 - 1i64 }
                var sy = i64(w)
                if gy[i] < 0.0f64 { sy = 0i64 - i64(w) }
                let ii = i64(i)
                let diag_plus = mag[usize(ii + sy + sx)]
                let diag_minus = mag[usize(ii - sy - sx)]
                var mp = 0.0f64
                var mm = 0.0f64
                if ax >= ay {
                    let wt = ay / ax
                    mp = diag_plus * wt + mag[usize(ii + sx)] * (1.0f64 - wt)
                    mm = diag_minus * wt + mag[usize(ii - sx)] * (1.0f64 - wt)
                } else {
                    let wt = ax / ay
                    mp = diag_plus * wt + mag[usize(ii + sy)] * (1.0f64 - wt)
                    mm = diag_minus * wt + mag[usize(ii - sy)] * (1.0f64 - wt)
                }
                if mp <= m && mm <= m {
                    if m >= high { edges[i] = 2u8 } else { edges[i] = 1u8 }
                }
            }
            x += 1usize
        }
        y += 1usize
    }
    // Hysteresis with the stack of pixel indices kept in the blurred image's slot.
    var stack = scratch[..n]
    var count = 0usize
    i = 0usize
    while i < n {
        if edges[i] == 2u8 {
            edges[i] = 3u8
            stack[0usize] = f64(i)
            var sp = 1usize
            while sp > 0usize {
                sp -= 1usize
                let p = usize(stack[sp])
                let px = p % w
                let py = p / w
                var dy = 0usize
                while dy < 3usize {
                    var dx = 0usize
                    while dx < 3usize {
                        if py + dy >= 1usize && py + dy <= h && px + dx >= 1usize && px + dx <= w {
                            let q = (py + dy - 1usize) * w + px + dx - 1usize
                            if edges[q] == 1u8 || edges[q] == 2u8 {
                                edges[q] = 3u8
                                stack[sp] = f64(q)
                                sp += 1usize
                            }
                        }
                        dx += 1usize
                    }
                    dy += 1usize
                }
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        if edges[i] == 3u8 {
            edges[i] = 1u8
            count += 1usize
        } else { edges[i] = 0u8 }
        i += 1usize
    }
    ret (count, ok)
}

// Median of the `(2r+1)^2` reflected window; `scratch` holds `(2r+1)^2`.
fn median(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, scratch: []f64) -> err {
    let n = w * h
    let side = 2usize * radius + 1usize
    if src.len < n || dst.len < n || scratch.len < side * side { ret TooSmall }
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var m = 0usize
            var j = 0usize
            while j < side {
                let row = reflect(i64(y) + i64(j) - i64(radius), h) * w
                var i = 0usize
                while i < side {
                    let v = src[row + reflect(i64(x) + i64(i) - i64(radius), w)]
                    // insertion into the sorted prefix
                    var at_pos = m
                    while at_pos > 0usize && scratch[at_pos - 1usize] > v {
                        scratch[at_pos] = scratch[at_pos - 1usize]
                        at_pos -= 1usize
                    }
                    scratch[at_pos] = v
                    m += 1usize
                    i += 1usize
                }
                j += 1usize
            }
            dst[y * w + x] = scratch[m / 2usize]
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// Bilateral filter: Gaussian weights in space (`sigma_s`) and in value (`sigma_r`)
// over the reflected window of radius `ceil(2*sigma_s)`.
fn bilateral(src: []const f64, w: usize, h: usize, sigma_s: f64, sigma_r: f64, dst: []f64) -> err {
    let n = w * h
    if src.len < n || dst.len < n { ret TooSmall }
    if !(sigma_s > 0.0f64) || !(sigma_r > 0.0f64) { ret Invalid }
    let r = i64(math.ceil[f64](2.0f64 * sigma_s))
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let c = src[y * w + x]
            var acc = 0.0f64
            var wsum = 0.0f64
            var j = 0i64 - r
            while j <= r {
                let row = reflect(i64(y) + j, h) * w
                var i = 0i64 - r
                while i <= r {
                    let v = src[row + reflect(i64(x) + i, w)]
                    let d2 = f64(i * i + j * j)
                    let wt = math.exp[f64]((0.0f64 - 0.5f64) * d2 / (sigma_s * sigma_s)) * math.exp[f64]((0.0f64 - 0.5f64) * (v - c) * (v - c) / (sigma_r * sigma_r))
                    acc += wt * v
                    wsum += wt
                    i += 1i64
                }
                j += 1i64
            }
            dst[y * w + x] = acc / wsum
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// Mean over the in-bounds `(2r+1)` square (the window shrinks at the border);
// `scratch` holds `w*h`.
fn box_mean(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, scratch: []f64) -> err {
    let n = w * h
    if src.len < n || dst.len < n || scratch.len < n { ret TooSmall }
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var lo = 0usize
            if x > radius { lo = x - radius }
            var hi = x + radius
            if hi >= w { hi = w - 1usize }
            var acc = 0.0f64
            var i = lo
            while i <= hi {
                acc += src[y * w + i]
                i += 1usize
            }
            scratch[y * w + x] = acc / f64(hi - lo + 1usize)
            x += 1usize
        }
        y += 1usize
    }
    y = 0usize
    while y < h {
        var lo = 0usize
        if y > radius { lo = y - radius }
        var hi = y + radius
        if hi >= h { hi = h - 1usize }
        var x = 0usize
        while x < w {
            var acc = 0.0f64
            var j = lo
            while j <= hi {
                acc += scratch[j * w + x]
                j += 1usize
            }
            dst[y * w + x] = acc / f64(hi - lo + 1usize)
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// Guided filter (He, Sun, Tang) of `src` steered by `guide`: `dst = mean(a)*guide +
// mean(b)` with `a = cov(guide, src) / (var(guide) + eps)`; `scratch` holds `7*w*h`.
fn guided(src: []const f64, guide: []const f64, w: usize, h: usize, radius: usize, eps: f64, dst: []f64, scratch: []f64) -> err {
    let n = w * h
    if src.len < n || guide.len < n || dst.len < n || scratch.len < 7usize * n { ret TooSmall }
    let mean_i = scratch[..n]
    let mean_p = scratch[n..2usize * n]
    let corr_i = scratch[2usize * n..3usize * n]
    let corr_ip = scratch[3usize * n..4usize * n]
    let a = scratch[4usize * n..5usize * n]
    let b = scratch[5usize * n..6usize * n]
    let tmp = scratch[6usize * n..7usize * n]
    let _ = box_mean(guide, w, h, radius, mean_i, tmp)
    let _ = box_mean(src, w, h, radius, mean_p, tmp)
    var i = 0usize
    while i < n {
        a[i] = guide[i] * guide[i]
        b[i] = guide[i] * src[i]
        i += 1usize
    }
    let _ = box_mean(a, w, h, radius, corr_i, tmp)
    let _ = box_mean(b, w, h, radius, corr_ip, tmp)
    i = 0usize
    while i < n {
        a[i] = (corr_ip[i] - mean_i[i] * mean_p[i]) / ((corr_i[i] - mean_i[i] * mean_i[i]) + eps)
        b[i] = mean_p[i] - a[i] * mean_i[i]
        i += 1usize
    }
    let _ = box_mean(a, w, h, radius, mean_i, tmp)
    let _ = box_mean(b, w, h, radius, mean_p, tmp)
    i = 0usize
    while i < n {
        dst[i] = mean_i[i] * guide[i] + mean_p[i]
        i += 1usize
    }
    ret ok
}

// ---- integral images ----------------------------------------------------------

// Summed-area table of `(w+1)*(h+1)` entries, row 0 and column 0 zero.
fn integral_image(src: []const f64, w: usize, h: usize, out: []f64) -> err {
    let stride = w + 1usize
    if src.len < w * h || out.len < stride * (h + 1usize) { ret TooSmall }
    var x = 0usize
    while x < stride {
        out[x] = 0.0f64
        x += 1usize
    }
    var y = 0usize
    while y < h {
        var row = 0.0f64
        out[(y + 1usize) * stride] = 0.0f64
        x = 0usize
        while x < w {
            row += src[y * w + x]
            out[(y + 1usize) * stride + x + 1usize] = out[y * stride + x + 1usize] + row
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// Sum over the rectangle at (`x`, `y`) of `rw` by `rh` from a table for width `w`.
fn integral_sum(integral: []const f64, w: usize, x: usize, y: usize, rw: usize, rh: usize) -> f64 {
    let s = w + 1usize
    ret integral[(y + rh) * s + x + rw] - integral[y * s + x + rw] - integral[(y + rh) * s + x] + integral[y * s + x]
}

fn integral_image_u8(src: []const u8, w: usize, h: usize, out: []u64) -> err {
    let stride = w + 1usize
    if src.len < w * h || out.len < stride * (h + 1usize) { ret TooSmall }
    var x = 0usize
    while x < stride {
        out[x] = 0u64
        x += 1usize
    }
    var y = 0usize
    while y < h {
        var row = 0u64
        out[(y + 1usize) * stride] = 0u64
        x = 0usize
        while x < w {
            row += u64(src[y * w + x])
            out[(y + 1usize) * stride + x + 1usize] = out[y * stride + x + 1usize] + row
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

fn integral_sum_u64(integral: []const u64, w: usize, x: usize, y: usize, rw: usize, rh: usize) -> u64 {
    let s = w + 1usize
    ret integral[(y + rh) * s + x + rw] + integral[y * s + x] - integral[y * s + x + rw] - integral[(y + rh) * s + x]
}

// Otsu's threshold `t` over the 256-bin histogram: the first `t` in `[0, 254]`
// maximising the between-class variance of `<= t` against `> t` (scikit-image's
// answer; a pixel above `t` is foreground).
fn threshold_otsu(src: []const u8, w: usize, h: usize) -> u8 {
    var hist: [256]u32 = zero
    let n = w * h
    var i = 0usize
    while i < n {
        hist[usize(src[i])] += 1u32
        i += 1usize
    }
    var total_sum = 0.0f64
    i = 0usize
    while i < 256usize {
        total_sum += f64(i) * f64(hist[i])
        i += 1usize
    }
    var w1 = 0.0f64
    var s1 = 0.0f64
    var best = 0.0f64 - 1.0f64
    var best_t = 0usize
    var t = 0usize
    while t < 255usize {
        w1 += f64(hist[t])
        s1 += f64(t) * f64(hist[t])
        let w2 = f64(n) - w1
        let s2 = total_sum - s1
        if w1 > 0.0f64 && w2 > 0.0f64 {
            let d = s1 / w1 - s2 / w2
            let variance = w1 * w2 * d * d
            if variance > best {
                best = variance
                best_t = t
            }
        }
        t += 1usize
    }
    ret u8(best_t & 255usize)
}

// ---- morphology ----------------------------------------------------------------

fn morph_extreme(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, dilate: bool) -> err {
    let n = w * h
    if src.len < n || dst.len < n { ret TooSmall }
    var y = 0usize
    while y < h {
        var y0 = 0usize
        if y > radius { y0 = y - radius }
        var y1 = y + radius
        if y1 >= h { y1 = h - 1usize }
        var x = 0usize
        while x < w {
            var x0 = 0usize
            if x > radius { x0 = x - radius }
            var x1 = x + radius
            if x1 >= w { x1 = w - 1usize }
            var best = src[y * w + x]
            var j = y0
            while j <= y1 {
                var i = x0
                while i <= x1 {
                    let v = src[j * w + i]
                    if dilate {
                        if v > best { best = v }
                    } else {
                        if v < best { best = v }
                    }
                    i += 1usize
                }
                j += 1usize
            }
            dst[y * w + x] = best
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// Minimum over the `(2r+1)` square clipped to the image (the same as reflection).
// ponytail: O(r^2) a pixel; van Herk's running extreme is the upgrade for large r.
fn morph_erode(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64) -> err {
    ret morph_extreme(src, w, h, radius, dst, false)
}

fn morph_dilate(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64) -> err {
    ret morph_extreme(src, w, h, radius, dst, true)
}

// Erosion then dilation; `scratch` holds `w*h`.
fn morph_open(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, scratch: []f64) -> err {
    let e = morph_extreme(src, w, h, radius, scratch, false)
    if e != ok { ret e }
    ret morph_extreme(scratch, w, h, radius, dst, true)
}

fn morph_close(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, scratch: []f64) -> err {
    let e = morph_extreme(src, w, h, radius, scratch, true)
    if e != ok { ret e }
    ret morph_extreme(scratch, w, h, radius, dst, false)
}

// ---- regions -------------------------------------------------------------------

fn uf_find(parent: []u32, a: u32) -> u32 {
    var v = a
    while parent[usize(v)] != v { v = parent[usize(v)] }
    ret v
}

fn uf_union(parent: []u32, a: u32, b: u32) {
    let ra = uf_find(parent, a)
    let rb = uf_find(parent, b)
    if ra < rb { parent[usize(rb)] = ra }
    if rb < ra { parent[usize(ra)] = rb }
}

// Connected components of the nonzero pixels, `connectivity` 4 or 8; labels are
// `1..count` in order of first raster appearance, 0 for background. `parent` holds
// `w*h + 1` union-find slots.
fn label_components(src: []const u8, w: usize, h: usize, connectivity: u32, labels: []u32, parent: []u32) -> (u32, err) {
    let n = w * h
    if src.len < n || labels.len < n || parent.len < n + 1usize { ret (0u32, TooSmall) }
    if connectivity != 4u32 && connectivity != 8u32 { ret (0u32, Invalid) }
    var provisional = 0u32
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let i = y * w + x
            labels[i] = 0u32
            if src[i] != 0u8 {
                var cand: [4]u32 = zero
                var c = 0usize
                if x > 0usize && labels[i - 1usize] != 0u32 {
                    cand[c] = labels[i - 1usize]
                    c += 1usize
                }
                if y > 0usize && labels[i - w] != 0u32 {
                    cand[c] = labels[i - w]
                    c += 1usize
                }
                if connectivity == 8u32 && y > 0usize {
                    if x > 0usize && labels[i - w - 1usize] != 0u32 {
                        cand[c] = labels[i - w - 1usize]
                        c += 1usize
                    }
                    if x + 1usize < w && labels[i - w + 1usize] != 0u32 {
                        cand[c] = labels[i - w + 1usize]
                        c += 1usize
                    }
                }
                if c == 0usize {
                    provisional += 1u32
                    parent[usize(provisional)] = provisional
                    labels[i] = provisional
                } else {
                    var m = cand[0usize]
                    var k = 1usize
                    while k < c {
                        if cand[k] < m { m = cand[k] }
                        k += 1usize
                    }
                    labels[i] = m
                    k = 0usize
                    while k < c {
                        uf_union(parent, cand[k], m)
                        k += 1usize
                    }
                }
            }
            x += 1usize
        }
        y += 1usize
    }
    // Every root is the smallest label of its set, so an ascending pass can replace
    // each slot by its final number before anything above it looks it up.
    var count = 0u32
    var p = 1usize
    while p <= usize(provisional) {
        if parent[p] == u32(p) {
            count += 1u32
            parent[p] = count
        } else { parent[p] = parent[usize(parent[p])] }
        p += 1usize
    }
    var i = 0usize
    while i < n {
        if labels[i] != 0u32 { labels[i] = parent[usize(labels[i])] }
        i += 1usize
    }
    ret (count, ok)
}

// 4-connected fill of the region holding (`x`, `y`) with `new_value`; answers the
// pixel count. `stack` holds `w*h` at most (a pixel is pushed once). `TooSmall`
// leaves a partial fill behind.
fn flood_fill(image: []u8, w: usize, h: usize, x: usize, y: usize, new_value: u8, stack: []u32) -> (usize, err) {
    if image.len < w * h || x >= w || y >= h { ret (0usize, TooSmall) }
    let old = image[y * w + x]
    if old == new_value { ret (0usize, ok) }
    if stack.len == 0usize { ret (0usize, TooSmall) }
    stack[0usize] = u32(y * w + x)
    image[y * w + x] = new_value
    var sp = 1usize
    var filled = 0usize
    while sp > 0usize {
        sp -= 1usize
        let p = usize(stack[sp])
        filled += 1usize
        let px = p % w
        let py = p / w
        var d = 0usize
        while d < 4usize {
            var q = p
            var inside = true
            if d == 0usize { if px > 0usize { q = p - 1usize } else { inside = false } }
            if d == 1usize { if px + 1usize < w { q = p + 1usize } else { inside = false } }
            if d == 2usize { if py > 0usize { q = p - w } else { inside = false } }
            if d == 3usize { if py + 1usize < h { q = p + w } else { inside = false } }
            if inside && image[q] == old {
                if sp >= stack.len { ret (filled, TooSmall) }
                image[q] = new_value
                stack[sp] = u32(q)
                sp += 1usize
            }
            d += 1usize
        }
    }
    ret (filled, ok)
}

// The same fill by horizontal spans: a popped seed extends left and right, and the
// rows above and below push one seed per run of the old value.
fn flood_fill_scanline(image: []u8, w: usize, h: usize, x: usize, y: usize, new_value: u8, stack: []u32) -> (usize, err) {
    if image.len < w * h || x >= w || y >= h { ret (0usize, TooSmall) }
    let old = image[y * w + x]
    if old == new_value { ret (0usize, ok) }
    if stack.len == 0usize { ret (0usize, TooSmall) }
    stack[0usize] = u32(y * w + x)
    var sp = 1usize
    var filled = 0usize
    while sp > 0usize {
        sp -= 1usize
        let p = usize(stack[sp])
        if image[p] == old {
            let px = p % w
            let py = p / w
            var lo = px
            while lo > 0usize && image[py * w + lo - 1usize] == old { lo -= 1usize }
            var hi = px
            while hi + 1usize < w && image[py * w + hi + 1usize] == old { hi += 1usize }
            var i = lo
            while i <= hi {
                image[py * w + i] = new_value
                i += 1usize
            }
            filled += hi - lo + 1usize
            var side = 0usize
            while side < 2usize {
                var row_ok = true
                var ny = py + 1usize
                if side == 0usize { if py > 0usize { ny = py - 1usize } else { row_ok = false } }
                if side == 1usize && ny >= h { row_ok = false }
                if row_ok {
                    var in_run = false
                    i = lo
                    while i <= hi {
                        if image[ny * w + i] == old {
                            if !in_run {
                                if sp >= stack.len { ret (filled, TooSmall) }
                                stack[sp] = u32(ny * w + i)
                                sp += 1usize
                                in_run = true
                            }
                        } else { in_run = false }
                        i += 1usize
                    }
                }
                side += 1usize
            }
        }
    }
    ret (filled, ok)
}

// One-dimensional squared distance transform (lower envelope of parabolas).
fn dt1d(f: []const f64, n: usize, d: []f64, v: []f64, z: []f64) {
    var k = 0usize
    v[0usize] = 0.0f64
    z[0usize] = 0.0f64 - inf()
    z[1usize] = inf()
    var q = 1usize
    while q < n {
        let fq = f[q] + f64(q) * f64(q)
        var s = 0.0f64
        var searching = true
        while searching {
            let vk = v[k]
            s = (fq - (f[usize(vk)] + vk * vk)) / (2.0f64 * f64(q) - 2.0f64 * vk)
            if s <= z[k] { k -= 1usize } else { searching = false }
        }
        k += 1usize
        v[k] = f64(q)
        z[k] = s
        z[k + 1usize] = inf()
        q += 1usize
    }
    k = 0usize
    q = 0usize
    while q < n {
        while z[k + 1usize] < f64(q) { k += 1usize }
        let dq = f64(q) - v[k]
        d[q] = dq * dq + f[usize(v[k])]
        q += 1usize
    }
}

// Exact squared Euclidean distance from every nonzero pixel to the nearest zero
// pixel (Felzenszwalb-Huttenlocher, columns then rows); `scratch` holds
// `4*max(w, h) + 1`. With no zero pixel every answer is `1e20` or above.
fn distance_transform(binary: []const u8, w: usize, h: usize, out: []f64, scratch: []f64) -> err {
    let n = w * h
    var m = w
    if h > m { m = h }
    if binary.len < n || out.len < n || scratch.len < 4usize * m + 1usize { ret TooSmall }
    let f = scratch[..m]
    let d = scratch[m..2usize * m]
    let v = scratch[2usize * m..3usize * m]
    let z = scratch[3usize * m..4usize * m + 1usize]
    var i = 0usize
    while i < n {
        if binary[i] == 0u8 { out[i] = 0.0f64 } else { out[i] = inf() }
        i += 1usize
    }
    var x = 0usize
    while x < w {
        var yy = 0usize
        while yy < h {
            f[yy] = out[yy * w + x]
            yy += 1usize
        }
        dt1d(f, h, d, v, z)
        yy = 0usize
        while yy < h {
            out[yy * w + x] = d[yy]
            yy += 1usize
        }
        x += 1usize
    }
    var y = 0usize
    while y < h {
        x = 0usize
        while x < w {
            f[x] = out[y * w + x]
            x += 1usize
        }
        dt1d(f, w, d, v, z)
        x = 0usize
        while x < w {
            out[y * w + x] = d[x]
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// ---- eikonal -------------------------------------------------------------------

// Godunov's update from the smaller neighbour on each axis at speed `f`.
fn godunov(a: f64, b: f64, f: f64) -> f64 {
    let inv = 1.0f64 / f
    if math.abs[f64](a - b) < inv {
        ret 0.5f64 * (a + b + math.sqrt[f64](2.0f64 * inv * inv - (a - b) * (a - b)))
    }
    if a < b { ret a + inv }
    ret b + inv
}

// The update at (`x`, `y`) from the neighbours `known` admits (every neighbour when
// `known` is empty).
fn eikonal_update(t: []const f64, speed: []const f64, w: usize, h: usize, x: usize, y: usize, known: []const u32) -> f64 {
    let i = y * w + x
    var a = inf()
    var b = inf()
    if x > 0usize && (known.len == 0usize || known[i - 1usize] == 4294967294u32) { a = t[i - 1usize] }
    if x + 1usize < w && (known.len == 0usize || known[i + 1usize] == 4294967294u32) && t[i + 1usize] < a { a = t[i + 1usize] }
    if y > 0usize && (known.len == 0usize || known[i - w] == 4294967294u32) { b = t[i - w] }
    if y + 1usize < h && (known.len == 0usize || known[i + w] == 4294967294u32) && t[i + w] < b { b = t[i + w] }
    ret godunov(a, b, speed[i])
}

fn heap_less(key: []const f64, tie: []const u32, i: u32, j: u32) -> bool {
    if key[usize(i)] < key[usize(j)] { ret true }
    if key[usize(i)] > key[usize(j)] { ret false }
    if tie.len == 0usize { ret false }
    ret tie[usize(i)] < tie[usize(j)]
}

fn heap_swap(heap: []u32, pos: []u32, a: usize, b: usize) {
    let t = heap[a]
    heap[a] = heap[b]
    heap[b] = t
    if pos.len != 0usize {
        pos[usize(heap[a])] = u32(a)
        pos[usize(heap[b])] = u32(b)
    }
}

fn sift_up(key: []const f64, tie: []const u32, heap: []u32, pos: []u32, start: usize) {
    var k = start
    while k > 0usize {
        let p = (k - 1usize) / 2usize
        if heap_less(key, tie, heap[k], heap[p]) {
            heap_swap(heap, pos, k, p)
            k = p
        } else { ret }
    }
}

fn sift_down(key: []const f64, tie: []const u32, heap: []u32, pos: []u32, size: usize, start: usize) {
    var k = start
    var moving = true
    while moving {
        let l = 2usize * k + 1usize
        var m = k
        if l < size && heap_less(key, tie, heap[l], heap[m]) { m = l }
        if l + 1usize < size && heap_less(key, tie, heap[l + 1usize], heap[m]) { m = l + 1usize }
        if m == k { moving = false } else {
            heap_swap(heap, pos, k, m)
            k = m
        }
    }
}

// Fast marching: arrival times `out` from the `sources` (pixel indices at time 0)
// at unit spacing through `speed`; `heap` and `pos` hold `w*h`.
fn fast_marching(speed: []const f64, w: usize, h: usize, sources: []const u32, out: []f64, heap: []u32, pos: []u32) -> err {
    let n = w * h
    if speed.len < n || out.len < n || heap.len < n || pos.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        out[i] = inf()
        pos[i] = 4294967295u32
        i += 1usize
    }
    var size = 0usize
    var no_tie: [0]u32 = zero
    i = 0usize
    while i < sources.len {
        let s = usize(sources[i])
        if s >= n { ret Invalid }
        if pos[s] == 4294967295u32 {
            out[s] = 0.0f64
            pos[s] = u32(size)
            heap[size] = sources[i]
            size += 1usize
            sift_up(out, no_tie[..], heap, pos, usize(pos[s]))
        }
        i += 1usize
    }
    while size > 0usize {
        let cur = heap[0usize]
        size -= 1usize
        if size > 0usize {
            heap[0usize] = heap[size]
            pos[usize(heap[0usize])] = 0u32
            sift_down(out, no_tie[..], heap, pos, size, 0usize)
        }
        pos[usize(cur)] = 4294967294u32
        let cx = usize(cur) % w
        let cy = usize(cur) / w
        var d = 0usize
        while d < 4usize {
            var nx = cx
            var ny = cy
            var inside = true
            if d == 0usize { if cx > 0usize { nx = cx - 1usize } else { inside = false } }
            if d == 1usize { if cx + 1usize < w { nx = cx + 1usize } else { inside = false } }
            if d == 2usize { if cy > 0usize { ny = cy - 1usize } else { inside = false } }
            if d == 3usize { if cy + 1usize < h { ny = cy + 1usize } else { inside = false } }
            if inside {
                let j = ny * w + nx
                if pos[j] != 4294967294u32 {
                    let t = eikonal_update(out, speed, w, h, nx, ny, pos)
                    if t < out[j] {
                        out[j] = t
                        if pos[j] == 4294967295u32 {
                            pos[j] = u32(size)
                            heap[size] = u32(j)
                            size += 1usize
                        }
                        sift_up(out, no_tie[..], heap, pos, usize(pos[j]))
                    }
                }
            }
            d += 1usize
        }
    }
    ret ok
}

// Fast sweeping: `sweeps` rounds of Zhao's four Gauss-Seidel orderings, the same
// discrete solution as `fast_marching` once converged (a handful of sweeps at a
// constant speed, more where the speed varies).
fn fast_sweeping(speed: []const f64, w: usize, h: usize, sources: []const u32, out: []f64, sweeps: usize) -> err {
    let n = w * h
    if speed.len < n || out.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        out[i] = inf()
        i += 1usize
    }
    i = 0usize
    while i < sources.len {
        if usize(sources[i]) >= n { ret Invalid }
        out[usize(sources[i])] = 0.0f64
        i += 1usize
    }
    var no_known: [0]u32 = zero
    var sweep = 0usize
    while sweep < sweeps {
        var ordering = 0usize
        while ordering < 4usize {
            var yy = 0usize
            while yy < h {
                var y = yy
                if ordering >= 2usize { y = h - 1usize - yy }
                var xx = 0usize
                while xx < w {
                    var x = xx
                    if ordering == 1usize || ordering == 2usize { x = w - 1usize - xx }
                    let t = eikonal_update(out, speed, w, h, x, y, no_known[..])
                    if t < out[y * w + x] { out[y * w + x] = t }
                    xx += 1usize
                }
                yy += 1usize
            }
            ordering += 1usize
        }
        sweep += 1usize
    }
    ret ok
}

// ---- pyramids ------------------------------------------------------------------

fn half(n: usize) -> usize { ret (n + 1usize) / 2usize }

fn tap(k: usize) -> f64 {
    if k == 0usize || k == 4usize { ret 0.0625f64 }
    if k == 2usize { ret 0.375f64 }
    ret 0.25f64
}

// Storage for `levels` levels starting at `w` by `h`.
fn pyramid_size(w: usize, h: usize, levels: usize) -> usize {
    var total = 0usize
    var cw = w
    var ch = h
    var l = 0usize
    while l < levels {
        total += cw * ch
        cw = half(cw)
        ch = half(ch)
        l += 1usize
    }
    ret total
}

// 5-tap blur and decimation; `tmp` holds `half(w)*h`.
fn reduce(src: []const f64, w: usize, h: usize, dst: []f64, tmp: []f64) {
    let w2 = half(w)
    let h2 = half(h)
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w2 {
            var acc = 0.0f64
            var k = 0usize
            while k < 5usize {
                acc += tap(k) * src[y * w + reflect(2i64 * i64(x) + i64(k) - 2i64, w)]
                k += 1usize
            }
            tmp[y * w2 + x] = acc
            x += 1usize
        }
        y += 1usize
    }
    y = 0usize
    while y < h2 {
        var x = 0usize
        while x < w2 {
            var acc = 0.0f64
            var k = 0usize
            while k < 5usize {
                acc += tap(k) * tmp[reflect(2i64 * i64(y) + i64(k) - 2i64, h) * w2 + x]
                k += 1usize
            }
            dst[y * w2 + x] = acc
            x += 1usize
        }
        y += 1usize
    }
}

// Sample `i` of the zero-inserted, doubled, reflected upsampling of a line.
fn up_sample(line: []const f64, stride: usize, i: i64, n: usize) -> f64 {
    let r = reflect(i, n)
    if r % 2usize == 0usize { ret 2.0f64 * line[(r / 2usize) * stride] }
    ret 0.0f64
}

// Zero insertion and the 5-tap blur from `w2` by `h2` up to `w` by `h`; `tmp` holds `w*h2`.
fn expand(src: []const f64, w2: usize, h2: usize, w: usize, h: usize, dst: []f64, tmp: []f64) {
    var y = 0usize
    while y < h2 {
        var x = 0usize
        while x < w {
            var acc = 0.0f64
            var k = 0usize
            while k < 5usize {
                acc += tap(k) * up_sample(src[y * w2..(y + 1usize) * w2], 1usize, i64(x) + i64(k) - 2i64, w)
                k += 1usize
            }
            tmp[y * w + x] = acc
            x += 1usize
        }
        y += 1usize
    }
    y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var acc = 0.0f64
            var k = 0usize
            while k < 5usize {
                acc += tap(k) * up_sample(tmp[x..], w, i64(y) + i64(k) - 2i64, h)
                k += 1usize
            }
            dst[y * w + x] = acc
            x += 1usize
        }
        y += 1usize
    }
}

// The Laplacian pyramid of `src`: `levels - 1` band-pass levels then the Gaussian
// residual, packed in `out` (`pyramid_size` long); `scratch` holds `2*w*h`.
fn laplacian_pyramid(src: []const f64, w: usize, h: usize, levels: usize, out: []f64, scratch: []f64) -> err {
    let n = w * h
    if levels == 0usize { ret Invalid }
    if src.len < n || out.len < pyramid_size(w, h, levels) || scratch.len < 2usize * n { ret TooSmall }
    var i = 0usize
    while i < n {
        out[i] = src[i]
        i += 1usize
    }
    var cw = w
    var ch = h
    var offset = 0usize
    var l = 0usize
    while l + 1usize < levels {
        let cn = cw * ch
        let nw = half(cw)
        let nh = half(ch)
        var cur = out[offset..offset + cn]
        var nxt = out[offset + cn..offset + cn + nw * nh]
        reduce(cur, cw, ch, nxt, scratch[..nw * ch])
        expand(nxt, nw, nh, cw, ch, scratch[..cn], scratch[cn..2usize * cn])
        i = 0usize
        while i < cn {
            cur[i] = cur[i] - scratch[i]
            i += 1usize
        }
        offset += cn
        cw = nw
        ch = nh
        l += 1usize
    }
    ret ok
}

// Rebuild the image from its pyramid into `dst` (`w*h`); `scratch` holds `2*w*h`.
fn laplacian_collapse(pyramid: []const f64, w: usize, h: usize, levels: usize, dst: []f64, scratch: []f64) -> err {
    let n = w * h
    if levels == 0usize { ret Invalid }
    if pyramid.len < pyramid_size(w, h, levels) || dst.len < n || scratch.len < 2usize * n { ret TooSmall }
    let top = levels - 1usize
    let tw = level_width(w, top)
    let th = level_width(h, top)
    let top_offset = pyramid_size(w, h, top)
    var i = 0usize
    while i < tw * th {
        scratch[i] = pyramid[top_offset + i]
        i += 1usize
    }
    var l = top
    while l > 0usize {
        l -= 1usize
        let cw = level_width(w, l)
        let ch = level_width(h, l)
        let cn = cw * ch
        let offset = pyramid_size(w, h, l)
        expand(scratch[..half(cw) * half(ch)], half(cw), half(ch), cw, ch, dst, scratch[n..n + cw * half(ch)])
        i = 0usize
        while i < cn {
            dst[i] = dst[i] + pyramid[offset + i]
            i += 1usize
        }
        if l > 0usize {
            i = 0usize
            while i < cn {
                scratch[i] = dst[i]
                i += 1usize
            }
        }
    }
    if levels == 1usize {
        i = 0usize
        while i < n {
            dst[i] = scratch[i]
            i += 1usize
        }
    }
    ret ok
}

fn level_width(n: usize, level: usize) -> usize {
    var v = n
    var l = 0usize
    while l < level {
        v = half(v)
        l += 1usize
    }
    ret v
}

// Largest all-nonzero rectangle by the histogram stack, one row at a time; the
// first of equal areas in raster order wins. `heights` and `stack` hold `w + 1`.
fn max_rectangle(binary: []const u8, w: usize, h: usize, heights: []u32, stack: []u32) -> (Rect, err) {
    if binary.len < w * h || heights.len < w + 1usize || stack.len < w + 1usize { ret (zero, TooSmall) }
    var best = Rect { x: 0usize, y: 0usize, w: 0usize, h: 0usize, area: 0usize }
    var x = 0usize
    while x <= w {
        heights[x] = 0u32
        x += 1usize
    }
    var y = 0usize
    while y < h {
        x = 0usize
        while x < w {
            if binary[y * w + x] != 0u8 { heights[x] += 1u32 } else { heights[x] = 0u32 }
            x += 1usize
        }
        var sp = 0usize
        x = 0usize
        while x <= w {
            let cur = heights[x]
            while sp > 0usize && heights[usize(stack[sp - 1usize])] >= cur {
                sp -= 1usize
                let top = usize(stack[sp])
                var left = 0usize
                if sp > 0usize { left = usize(stack[sp - 1usize]) + 1usize }
                let width = x - left
                let height = usize(heights[top])
                let area = height * width
                if area > best.area {
                    best = Rect { x: left, y: y + 1usize - height, w: width, h: height, area: area }
                }
            }
            stack[sp] = u32(x)
            sp += 1usize
            x += 1usize
        }
        y += 1usize
    }
    ret (best, ok)
}

// Mean-shift filtering: every pixel climbs in (x, y, value) space with the flat
// kernel of spatial radius `hs` and range radius `hr` for at most `iterations`
// steps, `dst` gets the value it reaches, and `modes` collects the distinct
// (x, y, value) triples (a reached point within `hs` and `hr` of an earlier mode
// joins it); answers the mode count, `TooSmall` when `modes` (3 per mode) fills.
fn mean_shift(src: []const f64, w: usize, h: usize, hs: f64, hr: f64, iterations: usize, dst: []f64, modes: []f64) -> (usize, err) {
    let n = w * h
    if src.len < n || dst.len < n { ret (0usize, TooSmall) }
    if !(hs > 0.0f64) || !(hr >= 0.0f64) { ret (0usize, Invalid) }
    let ri = i64(math.ceil[f64](hs))
    var mode_count = 0usize
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var cx = f64(x)
            var cy = f64(y)
            var cv = src[y * w + x]
            var it = 0usize
            var climbing = true
            while climbing && it < iterations {
                var sx = 0.0f64
                var sy = 0.0f64
                var sv = 0.0f64
                var count = 0usize
                var x0 = i64(cx) - ri
                if x0 < 0i64 { x0 = 0i64 }
                var x1 = i64(cx) + ri
                if x1 > i64(w) - 1i64 { x1 = i64(w) - 1i64 }
                var y0 = i64(cy) - ri
                if y0 < 0i64 { y0 = 0i64 }
                var y1 = i64(cy) + ri
                if y1 > i64(h) - 1i64 { y1 = i64(h) - 1i64 }
                var j = y0
                while j <= y1 {
                    var i = x0
                    while i <= x1 {
                        let v = src[usize(j) * w + usize(i)]
                        let ddx = f64(i) - cx
                        let ddy = f64(j) - cy
                        if ddx * ddx + ddy * ddy <= hs * hs && math.abs[f64](v - cv) <= hr {
                            sx += f64(i)
                            sy += f64(j)
                            sv += v
                            count += 1usize
                        }
                        i += 1i64
                    }
                    j += 1i64
                }
                let nx = sx / f64(count)
                let ny = sy / f64(count)
                let nv = sv / f64(count)
                let moved = (nx - cx) * (nx - cx) + (ny - cy) * (ny - cy) + (nv - cv) * (nv - cv)
                cx = nx
                cy = ny
                cv = nv
                if moved < 0.000000000001f64 { climbing = false }
                it += 1usize
            }
            dst[y * w + x] = cv
            var found = false
            var m = 0usize
            while !found && m < mode_count {
                let mx = modes[3usize * m] - cx
                let my = modes[3usize * m + 1usize] - cy
                if mx * mx + my * my <= hs * hs && math.abs[f64](modes[3usize * m + 2usize] - cv) <= hr { found = true }
                m += 1usize
            }
            if !found {
                if 3usize * mode_count + 3usize > modes.len { ret (mode_count, TooSmall) }
                modes[3usize * mode_count] = cx
                modes[3usize * mode_count + 1usize] = cy
                modes[3usize * mode_count + 2usize] = cv
                mode_count += 1usize
            }
            x += 1usize
        }
        y += 1usize
    }
    ret (mode_count, ok)
}

// Meyer's watershed: `markers` (nonzero labels) flood `gradient` in order of
// height, first-come among equal heights, 4-connected in the order up, left,
// right, down; `labels` gets every pixel's basin. `heap` and `age` hold `w*h`.
fn watershed(gradient: []const f64, w: usize, h: usize, markers: []const u32, labels: []u32, heap: []u32, age: []u32) -> err {
    let n = w * h
    if gradient.len < n || markers.len < n || labels.len < n || heap.len < n || age.len < n { ret TooSmall }
    var no_pos: [0]u32 = zero
    var size = 0usize
    var i = 0usize
    while i < n {
        labels[i] = markers[i]
        age[i] = 0u32
        if markers[i] != 0u32 {
            heap[size] = u32(i)
            size += 1usize
            sift_up(gradient, age, heap, no_pos[..], size - 1usize)
        }
        i += 1usize
    }
    var counter = 0u32
    while size > 0usize {
        let cur = usize(heap[0usize])
        size -= 1usize
        if size > 0usize {
            heap[0usize] = heap[size]
            sift_down(gradient, age, heap, no_pos[..], size, 0usize)
        }
        let cx = cur % w
        let cy = cur / w
        var d = 0usize
        while d < 4usize {
            var j = cur
            var inside = true
            if d == 0usize { if cy > 0usize { j = cur - w } else { inside = false } }
            if d == 1usize { if cx > 0usize { j = cur - 1usize } else { inside = false } }
            if d == 2usize { if cx + 1usize < w { j = cur + 1usize } else { inside = false } }
            if d == 3usize { if cy + 1usize < h { j = cur + w } else { inside = false } }
            if inside && labels[j] == 0u32 {
                counter += 1u32
                age[j] = counter
                labels[j] = labels[cur]
                heap[size] = u32(j)
                size += 1usize
                sift_up(gradient, age, heap, no_pos[..], size - 1usize)
            }
            d += 1usize
        }
    }
    ret ok
}
