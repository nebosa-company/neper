// The text of the Android look: a TrueType outline drawn the way Chromium on Windows draws it (Skia over DirectWrite's
// grey anti-aliasing), measured on the Material Web captures of docs/ui/looks/ref/material and on isolated glyph probes
// (scripts/material/dwprobe.py). Nothing here is fitted to a reference image; each stage is what the renderer does.
//
//   1. The outline is the hinted one (`e.text.ttglyph`, the font's own instructions at the whole pixel size).
//   2. It is sampled on a grid six samples wide and five tall to the pixel, a sample set when its centre lies inside the outline
//      (non-zero winding), the glyph's pen placed on a sixth of a pixel (Skia's quarter pixel position, then DirectWrite's sixth).
//   3. A pixel's three ClearType channels are boxes of six sample columns, two columns apart (columns -2..3, 0..5 and 2..7 of the
//      pixel), each column a vertical sum of the five sample rows weighted 4 9 10 9 4; a channel is 255 * sum / 216, rounded.
//   4. Skia's grey mask is the whole-number mean of the three channels, put through its pre-blend table: a gamma-correcting
//      table keyed on the luminance of the text colour (`SkComputeLuminance` on the sRGB bytes, three bits of it), sRGB as the
//      transfer curve and a contrast of 1 (`SkTMaskGamma_build_correcting_lut`).
//
// The mask is composed by the caller as an A8 mask under the text colour, glyph by glyph.

use e.math

const SAMPLES_X: usize = 6usize
const SAMPLES_Y: usize = 5usize
// Scratch for one glyph: the sample grid first, then the alpha mask.
const GRID_BYTES: usize = 3145728usize
const SCRATCH_BYTES: usize = 4194304usize
const CURVE_STEPS: i64 = 16i64

var seg_x0: [8192]f64 = zero
var seg_y0: [8192]f64 = zero
var seg_x1: [8192]f64 = zero
var seg_y1: [8192]f64 = zero
var seg_count: usize = zero
var seg_full: bool = zero

type GlyphMask = struct { x0: i64, y0: i64, width: usize, height: usize }

fn scratch_bytes() -> usize { ret SCRATCH_BYTES }

fn srgb_to_linear(c: f64) -> f64 {
    if c <= 0.04045 { ret c / 12.92 }
    ret math.pow[f64]((c + 0.055) / 1.055, 2.4)
}

fn linear_to_srgb(l: f64) -> f64 {
    if l <= 0.0031308 { ret l * 12.92 }
    ret 1.055 * math.pow[f64](l, 1.0 / 2.4) - 0.055
}

fn byte_of(v: f32) -> i64 {
    var b = i64(math.floor[f32](v * 255.0 + 0.5))
    if b < 0i64 { b = 0i64 }
    if b > 255i64 { b = 255i64 }
    ret b
}

// The pre-blend table a text colour selects: `SkComputeLuminance` of its sRGB bytes, the top three bits.
fn lut_key(red: f32, green: f32, blue: f32) -> usize {
    let lum = (byte_of(red) * 54i64 + byte_of(green) * 183i64 + byte_of(blue) * 19i64) / 256i64
    ret usize(lum / 32i64)
}

// Table `key` (0..7) into `out` (256 bytes): Skia's `SkTMaskGamma_build_correcting_lut` for a source luminance of the key's
// three bits repeated to a byte, sRGB for both gammas and a contrast of 1; the destination is guessed as the opposite.
fn lut_build(key: usize, out: []u8) {
    let q = i64(key)
    let src_byte = q * 32i64 + q * 4i64 + q / 2i64
    let src = f64(src_byte) / 255.0
    let dst = 1.0 - src
    let lin_src = srgb_to_linear(src)
    let lin_dst = srgb_to_linear(dst)
    let contrast: f64 = 1.0
    let adjusted = contrast * lin_dst
    var diff = src - dst
    if diff < 0.0 { diff = 0.0 - diff }
    var i = 0usize
    while i < 256usize {
        let c = f64(i) / 255.0
        if diff < 1.0 / 256.0 {
            out[i] = u8(i)
        } else {
            let srca = c + (1.0 - c) * adjusted * c
            let dsta = 1.0 - srca
            let lin_out = lin_src * srca + dsta * lin_dst
            let res = (linear_to_srgb(lin_out) - dst) / (src - dst)
            var v = i64(math.floor[f64](255.0 * res + 0.5))
            if v < 0i64 { v = 0i64 }
            if v > 255i64 { v = 255i64 }
            out[i] = u8(v)
        }
        i += 1usize
    }
}

fn add_seg(x0: f64, y0: f64, x1: f64, y1: f64) {
    if y0 == y1 { ret }
    if seg_count >= 8192usize {
        seg_full = true
        ret
    }
    seg_x0[seg_count] = x0
    seg_y0[seg_count] = y0
    seg_x1[seg_count] = x1
    seg_y1[seg_count] = y1
    seg_count += 1usize
}

fn add_quad(x0: f64, y0: f64, cx: f64, cy: f64, x1: f64, y1: f64) {
    var px = x0
    var py = y0
    var s = 1i64
    while s <= CURVE_STEPS {
        let u = f64(s) / f64(CURVE_STEPS)
        let v = 1.0 - u
        let nx = v * v * x0 + 2.0 * u * v * cx + u * u * x1
        let ny = v * v * y0 + 2.0 * u * v * cy + u * u * y1
        add_seg(px, py, nx, ny)
        px = nx
        py = ny
        s += 1i64
    }
}

// The outline's contours as line segments in pixels (y down, the pen at the origin, `xfrac` added to x). `cur` holds the points
// as 26.6 pixels, x then y; a quadratic's control points are the off-curve ones, two in a row implying the point between them.
fn flatten(cur: []const i64, tags: []const i64, ends: []const usize, nends: usize, ratio: f64, xfrac: f64) {
    seg_count = 0usize
    seg_full = false
    var first = 0usize
    var c = 0usize
    while c < nends {
        let last = ends[c]
        if last >= first {
            let m = last - first + 1usize
            if m >= 2usize {
                // The contour's points with the implied on-curve ones inserted, rotated to start on an on-curve point.
                var sx: [1024]f64 = zero
                var sy: [1024]f64 = zero
                var so: [1024]bool = zero
                var n = 0usize
                var i = 0usize
                while i < m && n + 2usize < 1024usize {
                    let a = first + i
                    let b = first + (i + 1usize) % m
                    let ax = f64(cur[2usize * a]) / 64.0 * ratio + xfrac
                    let ay = 0.0 - f64(cur[2usize * a + 1usize]) / 64.0 * ratio
                    let a_on = tags[a] & 1i64 != 0i64
                    let b_on = tags[b] & 1i64 != 0i64
                    sx[n] = ax
                    sy[n] = ay
                    so[n] = a_on
                    n += 1usize
                    if !a_on && !b_on {
                        let bx = f64(cur[2usize * b]) / 64.0 * ratio + xfrac
                        let by = 0.0 - f64(cur[2usize * b + 1usize]) / 64.0 * ratio
                        sx[n] = (ax + bx) * 0.5
                        sy[n] = (ay + by) * 0.5
                        so[n] = true
                        n += 1usize
                    }
                    i += 1usize
                }
                var start = 0usize
                while start < n && !so[start] { start += 1usize }
                if start < n {
                    var cx = sx[start]
                    var cy = sy[start]
                    var k = 1usize
                    while k <= n {
                        let at = (start + k) % n
                        if so[at] {
                            add_seg(cx, cy, sx[at], sy[at])
                            cx = sx[at]
                            cy = sy[at]
                            k += 1usize
                        } else {
                            let to = (start + k + 1usize) % n
                            add_quad(cx, cy, sx[at], sy[at], sx[to], sy[to])
                            cx = sx[to]
                            cy = sy[to]
                            k += 2usize
                        }
                    }
                }
            }
        }
        first = last + 1usize
        c += 1usize
    }
}

// Rasterises the hinted outline into `scratch` (`scratch_bytes()` long) and answers the mask: `width * height` alpha bytes
// from the scratch's `GRID_BYTES` on, row by row, its top left pixel at (`x0`, `y0`) from the pen's pixel (the baseline is the
// line y = 0; y grows downward). `ratio` scales the outline's pixel size (a size that is not a whole pixel hints at the nearest
// whole one), `xfrac` is the pen's fraction of a pixel (a sixth, 0..5/6) and `lut` the 256 byte table. False when the glyph
// does not fit the scratch or has too many segments.
fn rasterize(scratch: []u8, cur: []const i64, tags: []const i64, ends: []const usize, nends: usize, n: usize, ratio: f32, xfrac: f32, lut: []const u8) -> (GlyphMask, bool) {
    var mask: GlyphMask = zero
    if n < 2usize || scratch.len < SCRATCH_BYTES { ret (mask, false) }
    let k = f64(ratio)
    let f = f64(xfrac)
    var minx: f64 = 1.0e9
    var maxx: f64 = -1.0e9
    var miny: f64 = 1.0e9
    var maxy: f64 = -1.0e9
    var i = 0usize
    while i < n {
        let x = f64(cur[2usize * i]) / 64.0 * k + f
        let y = 0.0 - f64(cur[2usize * i + 1usize]) / 64.0 * k
        if x < minx { minx = x }
        if x > maxx { maxx = x }
        if y < miny { miny = y }
        if y > maxy { maxy = y }
        i += 1usize
    }
    let px0 = i64(math.floor[f64](minx)) - 2i64
    let px1 = i64(math.ceil[f64](maxx)) + 2i64
    let py0 = i64(math.floor[f64](miny)) - 1i64
    let py1 = i64(math.ceil[f64](maxy)) + 1i64
    let w = usize(px1 - px0)
    let h = usize(py1 - py0)
    let gw = w * SAMPLES_X
    let gh = h * SAMPLES_Y
    if gw + 4usize > 2048usize || gw * gh > GRID_BYTES || w * h > SCRATCH_BYTES - GRID_BYTES { ret (mask, false) }
    flatten(cur, tags, ends, nends, k, f)
    if seg_full { ret (mask, false) }
    var z = 0usize
    while z < gw * gh {
        scratch[z] = 0u8
        z += 1usize
    }
    // Sample rows: the centre of each, the crossings of the segments with it, the spans of non-zero winding between them.
    var cx: [256]f64 = zero
    var cd: [256]i64 = zero
    var row = 0usize
    while row < gh {
        let y = f64(py0) + (f64(row) + 0.5) / f64(SAMPLES_Y)
        var nc = 0usize
        var s = 0usize
        while s < seg_count {
            let ya = seg_y0[s]
            let yb = seg_y1[s]
            var hit = false
            if ya < yb {
                hit = ya <= y && y < yb
            } else {
                hit = yb <= y && y < ya
            }
            if hit && nc < 256usize {
                let xa = seg_x0[s]
                let xb = seg_x1[s]
                let x = xa + (y - ya) * (xb - xa) / (yb - ya)
                var d = 1i64
                if yb < ya { d = -1i64 }
                // insertion, ordered by x
                var at = nc
                while at > 0usize && cx[at - 1usize] > x {
                    cx[at] = cx[at - 1usize]
                    cd[at] = cd[at - 1usize]
                    at -= 1usize
                }
                cx[at] = x
                cd[at] = d
                nc += 1usize
            }
            s += 1usize
        }
        var wind = 0i64
        var e = 0usize
        while e + 1usize < nc {
            wind += cd[e]
            if wind != 0i64 {
                var a = i64(math.ceil[f64]((cx[e] - f64(px0)) * f64(SAMPLES_X) - 0.5))
                var b = i64(math.ceil[f64]((cx[e + 1usize] - f64(px0)) * f64(SAMPLES_X) - 0.5))
                if a < 0i64 { a = 0i64 }
                if b > i64(gw) { b = i64(gw) }
                while a < b {
                    scratch[row * gw + usize(a)] = 1u8
                    a += 1i64
                }
            }
            e += 1usize
        }
        row += 1usize
    }
    // Pixels: a vertical sum per sample column (weights 4 9 10 9 4), three channel boxes, the mean of their bytes, the table.
    var vc: [2064]i64 = zero
    var py = 0usize
    while py < h {
        var col = 0usize
        while col < gw + 4usize {
            vc[col] = 0i64
            col += 1usize
        }
        col = 0usize
        while col < gw {
            let base = py * SAMPLES_Y * gw + col
            vc[col + 2usize] = 4i64 * i64(scratch[base]) + 9i64 * i64(scratch[base + gw]) + 10i64 * i64(scratch[base + 2usize * gw]) + 9i64 * i64(scratch[base + 3usize * gw]) + 4i64 * i64(scratch[base + 4usize * gw])
            col += 1usize
        }
        var px = 0usize
        while px < w {
            var sum = 0i64
            var ch = 0usize
            while ch < 3usize {
                var nsum = 0i64
                var j = 0usize
                while j < 6usize {
                    nsum += vc[px * SAMPLES_X + 2usize * ch + j]
                    j += 1usize
                }
                sum += (255i64 * nsum + 108i64) / 216i64
                ch += 1usize
            }
            scratch[GRID_BYTES + py * w + px] = lut[usize(sum / 3i64)]
            px += 1usize
        }
        py += 1usize
    }
    mask.x0 = px0
    mask.y0 = py0
    mask.width = w
    mask.height = h
    ret (mask, true)
}
