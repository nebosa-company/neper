// `e.gfx.svg_filter` (L125, D4503): the pixel half of SVG filter effects. `e.gfx.svg` parses a `<filter>`
// into a short program of primitives and renders the filtered element's source graphic into a scratch
// target; this module runs the program over that pixel buffer and hands the result back to be drawn as an
// image. It knows nothing of XML: a primitive is a `Prim` (a kind, its inputs as indexes of earlier results or
// the source, a pixel subregion, a colour-space flag and a few numbers).
//
// Buffers are premultiplied RGBA f32 in 0..1, `w * h * 4` values, row-major, sRGB-encoded as the scene
// renderer writes them. A primitive that is not colour-neutral runs in linear light when `linear` is set (the
// SVG default for `color-interpolation-filters`): inputs are unpremultiplied, taken through the sRGB transfer
// function and premultiplied again, and the result goes back the same way. Outside the filter region every
// pixel is transparent black, and a primitive's result is cut to its subregion.
//
// Kinds: Gaussian blur (the three-box approximation of the SVG text for a deviation of 2 pixels or more,
// an exact kernel below that; either axis may be zero), offset (whole pixels), flood, blend (the sixteen
// compositing-and-blending modes), composite (over, in, out, atop, xor, arithmetic), colour matrix (matrix,
// saturate, hueRotate, luminanceToAlpha), merge (up to eight inputs) and drop shadow (blur of the input's
// alpha, offset, flooded, under the input). A primitive the caller does not know passes its input through.
//
// `Host` is what the pixel work needs of the scene backend: the renderer the result texture is uploaded to
// (one texture slot per filtered element, recorded so `release` can free them) and the pixel limits of the
// scratch target, which is as big as the filter region and no bigger. `render_pixels` draws a display list
// into a scratch target of its own renderer on the same device, so the caller's renderer and its damage
// tracking are untouched; an opacity layer inside it costs a canvas of that scratch size, not the screen's.

use e.math
use e.mem
use e.gpu
use e.gfx.geometry
use e.gfx.image
use e.gfx.scene
use e.text.shape as fonts

error TooComplex

const KIND_PASS: u32 = 0u32
const KIND_BLUR: u32 = 1u32
const KIND_OFFSET: u32 = 2u32
const KIND_FLOOD: u32 = 3u32
const KIND_BLEND: u32 = 4u32
const KIND_COMPOSITE: u32 = 5u32
const KIND_MATRIX: u32 = 6u32
const KIND_MERGE: u32 = 7u32
const KIND_SHADOW: u32 = 8u32
const MAX_PRIMS: usize = 16usize
const MAX_MERGE: usize = 8usize
const MAX_TEXTURES: usize = 16usize

// Input references: an index of an earlier result, or one of these.
fn in_source() -> i32 { ret 0i32 - 1i32 }
fn in_alpha() -> i32 { ret 0i32 - 2i32 }
fn in_empty() -> i32 { ret 0i32 - 3i32 }

// `p` by kind: blur p0, p1 = deviation in pixels along x and y; offset p0, p1 = dx, dy pixels; flood p0..p3 =
// straight RGBA; blend: `mode`; composite: `mode` (0 over, 1 in, 2 out, 3 atop, 4 xor, 5 arithmetic) and p0..p3 =
// k1..k4; matrix: `mode` (0 matrix with p0..p19, 1 saturate p0, 2 hueRotate p0 in degrees, 3 luminanceToAlpha);
// shadow: p0, p1 = dx, dy, p2, p3 = deviation, p4..p7 = straight RGBA of the shadow colour.
type Prim = struct {
    kind: u32, mode: u32, in1: i32, in2: i32, merge: [8]i32, merge_n: usize, linear: bool,
    x0: i32, y0: i32, x1: i32, y1: i32, p: [20]f32
}

type Host = struct { renderer: *scene.Renderer, width: u32, height: u32, max_pixels: usize, textures: [16]scene.TextureId, texture_count: usize }

fn host(renderer: *scene.Renderer, width: u32, height: u32, max_pixels: usize) -> Host {
    var h: Host = zero
    h.renderer = renderer
    h.width = width
    h.height = height
    h.max_pixels = max_pixels
    ret h
}

// Frees the texture slots the filtered elements took; call after the scene using them has been rendered.
fn release(h: *Host) -> err {
    var i = 0usize
    while i < h.texture_count {
        try scene.release_image(h.renderer, h.textures[i])
        i += 1usize
    }
    h.texture_count = 0usize
    ret ok
}

// ---- colour space ------------------------------------------------------------------------------------

fn srgb_to_linear(c: f32) -> f32 {
    if c <= 0.04045 { ret c / 12.92 }
    ret math.pow[f32]((c + 0.055) / 1.055, 2.4)
}

fn linear_to_srgb(c: f32) -> f32 {
    if c <= 0.0031308 { ret c * 12.92 }
    ret 1.055 * math.pow[f32](c, 1.0 / 2.4) - 0.055
}

fn clamp01(v: f32) -> f32 {
    if !(v > 0.0) { ret 0.0 }
    if v > 1.0 { ret 1.0 }
    ret v
}

// `dst = src` through the transfer function in the direction asked, colours unpremultiplied around it.
fn convert(src: []const f32, dst: []f32, count: usize, to_linear: bool) {
    var i = 0usize
    while i < count {
        let at = i * 4usize
        let a = src[at + 3usize]
        if a > 0.0 {
            var c = 0usize
            while c < 3usize {
                let v = clamp01(src[at + c] / a)
                var t = 0.0f32
                if to_linear { t = srgb_to_linear(v) } else { t = linear_to_srgb(v) }
                dst[at + c] = t * a
                c += 1usize
            }
        } else {
            dst[at] = 0.0
            dst[at + 1usize] = 0.0
            dst[at + 2usize] = 0.0
        }
        dst[at + 3usize] = a
        i += 1usize
    }
}

// ---- blur --------------------------------------------------------------------------------------------

// `dst[i] = mean of src[i - lo ..= i + hi]` along one axis, zero outside the image.
fn box_axis(src: []const f32, dst: []f32, w: usize, h: usize, horizontal: bool, lo: usize, hi: usize) {
    var lines = w
    var len = h
    var line_stride = 4usize
    var step = w * 4usize
    if horizontal {
        lines = h
        len = w
        line_stride = w * 4usize
        step = 4usize
    }
    let size = f64(lo + hi + 1usize)
    var l = 0usize
    while l < lines {
        let base = l * line_stride
        var c = 0usize
        while c < 4usize {
            var sum = 0.0f64
            var j = 0usize
            while j <= hi && j < len {
                sum += f64(src[base + j * step + c])
                j += 1usize
            }
            var i = 0usize
            while i < len {
                dst[base + i * step + c] = f32(sum / size)
                if i + hi + 1usize < len { sum += f64(src[base + (i + hi + 1usize) * step + c]) }
                if i >= lo { sum -= f64(src[base + (i - lo) * step + c]) }
                i += 1usize
            }
            c += 1usize
        }
        l += 1usize
    }
}

fn gauss_axis(src: []const f32, dst: []f32, w: usize, h: usize, horizontal: bool, sigma: f32) {
    var radius = usize(math.ceil[f32](sigma * 3.0))
    if radius > 8usize { radius = 8usize }
    var kernel: [17]f32 = zero
    var total = 0.0f32
    var k = 0usize
    while k <= 2usize * radius {
        let x = f32(k) - f32(radius)
        let v = math.exp[f32](0.0 - x * x / (2.0 * sigma * sigma))
        kernel[k] = v
        total += v
        k += 1usize
    }
    var lines = w
    var len = h
    var line_stride = 4usize
    var step = w * 4usize
    if horizontal {
        lines = h
        len = w
        line_stride = w * 4usize
        step = 4usize
    }
    var l = 0usize
    while l < lines {
        let base = l * line_stride
        var i = 0usize
        while i < len {
            var c = 0usize
            while c < 4usize {
                var sum = 0.0f32
                var t = 0usize
                while t <= 2usize * radius {
                    let j = i + t
                    if j >= radius && j - radius < len { sum += kernel[t] * src[base + (j - radius) * step + c] }
                    t += 1usize
                }
                dst[base + i * step + c] = sum / total
                c += 1usize
            }
            i += 1usize
        }
        l += 1usize
    }
}

// Blur `buf` in place along one axis by `sigma` pixels; `tmp` is the same size.
fn blur_axis(buf: []f32, tmp: []f32, w: usize, h: usize, horizontal: bool, sigma: f32, count: usize) {
    if !(sigma > 0.0) { ret }
    if sigma < 2.0 {
        gauss_axis(buf, tmp, w, h, horizontal, sigma)
    } else {
        let d = usize(math.floor[f32](sigma * 1.8799712 + 0.5))
        let half = d / 2usize
        if d % 2usize == 1usize {
            box_axis(buf, tmp, w, h, horizontal, half, half)
            box_axis(tmp, buf, w, h, horizontal, half, half)
            box_axis(buf, tmp, w, h, horizontal, half, half)
        } else {
            box_axis(buf, tmp, w, h, horizontal, half, half - 1usize)
            box_axis(tmp, buf, w, h, horizontal, half - 1usize, half)
            box_axis(buf, tmp, w, h, horizontal, half, half)
        }
    }
    var i = 0usize
    while i < count {
        buf[i] = tmp[i]
        i += 1usize
    }
}

// ---- blend and composite -------------------------------------------------------------------------------

fn soft_light_d(c: f32) -> f32 {
    if c <= 0.25 { ret ((16.0 * c - 12.0) * c + 4.0) * c }
    ret math.sqrt[f32](c)
}

fn hard_light(cb: f32, cs: f32) -> f32 {
    if cs <= 0.5 { ret cb * 2.0 * cs }
    let s = 2.0 * cs - 1.0
    ret cb + s - cb * s
}

// One channel of a separable blend mode over unpremultiplied backdrop `cb` and source `cs`.
fn blend_channel(mode: u32, cb: f32, cs: f32) -> f32 {
    if mode == 0u32 { ret cs }
    if mode == 1u32 { ret cb * cs }
    if mode == 2u32 { ret cb + cs - cb * cs }
    if mode == 3u32 {
        if cb < cs { ret cb }
        ret cs
    }
    if mode == 4u32 {
        if cb > cs { ret cb }
        ret cs
    }
    if mode == 5u32 { ret hard_light(cs, cb) }
    if mode == 6u32 {
        if cb == 0.0 { ret 0.0 }
        if cs >= 1.0 { ret 1.0 }
        var v = cb / (1.0 - cs)
        if v > 1.0 { v = 1.0 }
        ret v
    }
    if mode == 7u32 {
        if cb >= 1.0 { ret 1.0 }
        if cs <= 0.0 { ret 0.0 }
        var v = (1.0 - cb) / cs
        if v > 1.0 { v = 1.0 }
        ret 1.0 - v
    }
    if mode == 8u32 { ret hard_light(cb, cs) }
    if mode == 9u32 {
        if cs <= 0.5 { ret cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb) }
        ret cb + (2.0 * cs - 1.0) * (soft_light_d(cb) - cb)
    }
    if mode == 10u32 {
        if cb > cs { ret cb - cs }
        ret cs - cb
    }
    ret cb + cs - 2.0 * cb * cs
}

fn lum(r: f32, g: f32, b: f32) -> f32 { ret 0.3 * r + 0.59 * g + 0.11 * b }

fn clip_color(r: *f32, g: *f32, b: *f32) {
    let l = lum(*r, *g, *b)
    var n = *r
    if *g < n { n = *g }
    if *b < n { n = *b }
    var x = *r
    if *g > x { x = *g }
    if *b > x { x = *b }
    if n < 0.0 {
        *r = l + (*r - l) * l / (l - n)
        *g = l + (*g - l) * l / (l - n)
        *b = l + (*b - l) * l / (l - n)
    }
    if x > 1.0 {
        *r = l + (*r - l) * (1.0 - l) / (x - l)
        *g = l + (*g - l) * (1.0 - l) / (x - l)
        *b = l + (*b - l) * (1.0 - l) / (x - l)
    }
}

fn set_lum(r: f32, g: f32, b: f32, l: f32) -> (f32, f32, f32) {
    let d = l - lum(r, g, b)
    var rr = r + d
    var gg = g + d
    var bb = b + d
    clip_color(&rr, &gg, &bb)
    ret (rr, gg, bb)
}

fn sat_of(r: f32, g: f32, b: f32) -> f32 {
    var n = r
    if g < n { n = g }
    if b < n { n = b }
    var x = r
    if g > x { x = g }
    if b > x { x = b }
    ret x - n
}

fn set_sat(r: f32, g: f32, b: f32, s: f32) -> (f32, f32, f32) {
    var lo = r
    if g < lo { lo = g }
    if b < lo { lo = b }
    var hi = r
    if g > hi { hi = g }
    if b > hi { hi = b }
    let range = hi - lo
    if !(range > 0.0) { ret (0.0, 0.0, 0.0) }
    ret ((r - lo) * s / range, (g - lo) * s / range, (b - lo) * s / range)
}

// The non-separable modes: 12 hue, 13 saturation, 14 colour, 15 luminosity.
fn blend_rgb(mode: u32, br: f32, bg: f32, bb: f32, sr: f32, sg: f32, sb: f32) -> (f32, f32, f32) {
    var r = sr
    var g = sg
    var b = sb
    var l = lum(sr, sg, sb)
    if mode == 12u32 {
        let (hr, hg, hb) = set_sat(sr, sg, sb, sat_of(br, bg, bb))
        r = hr
        g = hg
        b = hb
        l = lum(br, bg, bb)
    } else if mode == 13u32 {
        let (hr, hg, hb) = set_sat(br, bg, bb, sat_of(sr, sg, sb))
        r = hr
        g = hg
        b = hb
        l = lum(br, bg, bb)
    } else if mode == 14u32 {
        l = lum(br, bg, bb)
    } else {
        r = br
        g = bg
        b = bb
    }
    let (fr, fg, fb) = set_lum(r, g, b, l)
    ret (fr, fg, fb)
}

// `in1` (the source) over `in2` (the backdrop) by blend mode.
fn blend(src: []const f32, back: []const f32, dst: []f32, count: usize, mode: u32) {
    var i = 0usize
    while i < count {
        let at = i * 4usize
        let sa = src[at + 3usize]
        let ba = back[at + 3usize]
        let ra = sa + ba - sa * ba
        var sc: [3]f32 = zero
        var bc: [3]f32 = zero
        var c = 0usize
        while c < 3usize {
            if sa > 0.0 { sc[c] = clamp01(src[at + c] / sa) }
            if ba > 0.0 { bc[c] = clamp01(back[at + c] / ba) }
            c += 1usize
        }
        var mixed: [3]f32 = zero
        if mode >= 12u32 {
            let (r, g, b) = blend_rgb(mode, bc[0usize], bc[1usize], bc[2usize], sc[0usize], sc[1usize], sc[2usize])
            mixed[0usize] = r
            mixed[1usize] = g
            mixed[2usize] = b
        } else {
            c = 0usize
            while c < 3usize {
                mixed[c] = blend_channel(mode, bc[c], sc[c])
                c += 1usize
            }
        }
        c = 0usize
        while c < 3usize {
            dst[at + c] = (1.0 - ba) * src[at + c] + (1.0 - sa) * back[at + c] + sa * ba * clamp01(mixed[c])
            c += 1usize
        }
        dst[at + 3usize] = ra
        i += 1usize
    }
}

fn composite(src: []const f32, back: []const f32, dst: []f32, count: usize, op: u32, k1: f32, k2: f32, k3: f32, k4: f32) {
    var i = 0usize
    while i < count {
        let at = i * 4usize
        let a1 = src[at + 3usize]
        let a2 = back[at + 3usize]
        var c = 0usize
        while c < 4usize {
            let v1 = src[at + c]
            let v2 = back[at + c]
            var r = 0.0f32
            if op == 0u32 { r = v1 + v2 * (1.0 - a1) } else if op == 1u32 { r = v1 * a2 } else if op == 2u32 { r = v1 * (1.0 - a2) } else if op == 3u32 { r = v1 * a2 + v2 * (1.0 - a1) } else if op == 4u32 { r = v1 * (1.0 - a2) + v2 * (1.0 - a1) } else { r = k1 * v1 * v2 + k2 * v1 + k3 * v2 + k4 }
            dst[at + c] = clamp01(r)
            c += 1usize
        }
        if op == 5u32 {
            // An arithmetic result keeps premultiplied colour within its alpha.
            let a = dst[at + 3usize]
            c = 0usize
            while c < 3usize {
                if dst[at + c] > a { dst[at + c] = a }
                c += 1usize
            }
        }
        i += 1usize
    }
}

// ---- colour matrix, offset, merge, flood ----------------------------------------------------------------

fn matrix_of(mode: u32, p: []const f32, m: []f32) {
    var i = 0usize
    while i < 20usize {
        m[i] = 0.0
        i += 1usize
    }
    m[18usize] = 1.0
    if mode == 0u32 {
        i = 0usize
        while i < 20usize {
            m[i] = p[i]
            i += 1usize
        }
    } else if mode == 1u32 {
        let s = p[0usize]
        m[0usize] = 0.213 + 0.787 * s
        m[1usize] = 0.715 - 0.715 * s
        m[2usize] = 0.072 - 0.072 * s
        m[5usize] = 0.213 - 0.213 * s
        m[6usize] = 0.715 + 0.285 * s
        m[7usize] = 0.072 - 0.072 * s
        m[10usize] = 0.213 - 0.213 * s
        m[11usize] = 0.715 - 0.715 * s
        m[12usize] = 0.072 + 0.928 * s
    } else if mode == 2u32 {
        let rad = p[0usize] * 3.14159265 / 180.0
        let co = math.cos[f32](rad)
        let si = math.sin[f32](rad)
        m[0usize] = 0.213 + co * 0.787 - si * 0.213
        m[1usize] = 0.715 - co * 0.715 - si * 0.715
        m[2usize] = 0.072 - co * 0.072 + si * 0.928
        m[5usize] = 0.213 - co * 0.213 + si * 0.143
        m[6usize] = 0.715 + co * 0.285 + si * 0.140
        m[7usize] = 0.072 - co * 0.072 - si * 0.283
        m[10usize] = 0.213 - co * 0.213 - si * 0.787
        m[11usize] = 0.715 - co * 0.715 + si * 0.715
        m[12usize] = 0.072 + co * 0.928 + si * 0.072
    } else {
        m[18usize] = 0.0
        m[15usize] = 0.2125
        m[16usize] = 0.7154
        m[17usize] = 0.0721
    }
}

fn color_matrix(src: []const f32, dst: []f32, count: usize, m: []const f32) {
    var i = 0usize
    while i < count {
        let at = i * 4usize
        let a = src[at + 3usize]
        var r = 0.0f32
        var g = 0.0f32
        var b = 0.0f32
        if a > 0.0 {
            r = clamp01(src[at] / a)
            g = clamp01(src[at + 1usize] / a)
            b = clamp01(src[at + 2usize] / a)
        }
        let nr = clamp01(m[0usize] * r + m[1usize] * g + m[2usize] * b + m[3usize] * a + m[4usize])
        let ng = clamp01(m[5usize] * r + m[6usize] * g + m[7usize] * b + m[8usize] * a + m[9usize])
        let nb = clamp01(m[10usize] * r + m[11usize] * g + m[12usize] * b + m[13usize] * a + m[14usize])
        let na = clamp01(m[15usize] * r + m[16usize] * g + m[17usize] * b + m[18usize] * a + m[19usize])
        dst[at] = nr * na
        dst[at + 1usize] = ng * na
        dst[at + 2usize] = nb * na
        dst[at + 3usize] = na
        i += 1usize
    }
}

fn shift_pixels(src: []const f32, dst: []f32, w: usize, h: usize, dx: i32, dy: i32) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let sx = i64(x) - i64(dx)
            let sy = i64(y) - i64(dy)
            let at = (y * w + x) * 4usize
            if sx >= 0i64 && sy >= 0i64 && sx < i64(w) && sy < i64(h) {
                let from = (usize(sy) * w + usize(sx)) * 4usize
                dst[at] = src[from]
                dst[at + 1usize] = src[from + 1usize]
                dst[at + 2usize] = src[from + 2usize]
                dst[at + 3usize] = src[from + 3usize]
            } else {
                dst[at] = 0.0
                dst[at + 1usize] = 0.0
                dst[at + 2usize] = 0.0
                dst[at + 3usize] = 0.0
            }
            x += 1usize
        }
        y += 1usize
    }
}

// `top` over `bottom`, both premultiplied, into `bottom` in place.
fn over_into(top: []const f32, bottom: []f32, count: usize) {
    var i = 0usize
    while i < count {
        let at = i * 4usize
        let keep = 1.0 - top[at + 3usize]
        bottom[at] = top[at] + bottom[at] * keep
        bottom[at + 1usize] = top[at + 1usize] + bottom[at + 1usize] * keep
        bottom[at + 2usize] = top[at + 2usize] + bottom[at + 2usize] * keep
        bottom[at + 3usize] = top[at + 3usize] + bottom[at + 3usize] * keep
        i += 1usize
    }
}

fn copy_into(src: []const f32, dst: []f32, count: usize) {
    var i = 0usize
    while i < count {
        dst[i] = src[i]
        i += 1usize
    }
}

// Pixels outside [x0, x1) x [y0, y1) become transparent black.
fn cut(buf: []f32, w: usize, h: usize, x0: i32, y0: i32, x1: i32, y1: i32) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            if i64(x) < i64(x0) || i64(x) >= i64(x1) || i64(y) < i64(y0) || i64(y) >= i64(y1) {
                let at = (y * w + x) * 4usize
                buf[at] = 0.0
                buf[at + 1usize] = 0.0
                buf[at + 2usize] = 0.0
                buf[at + 3usize] = 0.0
            }
            x += 1usize
        }
        y += 1usize
    }
}

// ---- the program -----------------------------------------------------------------------------------------

fn pick(r: i32, source: []const f32, alpha: []const f32, empty: []const f32, results: []const []f32, count: usize) -> []const f32 {
    if r == in_source() { ret source }
    if r == in_alpha() { ret alpha }
    if r >= 0i32 && usize(r) < count { ret results[usize(r)] }
    ret empty
}

// Runs `prims` over `source` (`w * h` premultiplied pixels) and writes the last result into `out`. Scratch comes
// from `a` (about (prims + 4) buffers of the image's size) and is the caller's to reset.
fn run(a: *mem.Arena, prims: []const Prim, source: []const f32, w: usize, h: usize, out: []f32) -> err {
    let count = w * h * 4usize
    if prims.len > MAX_PRIMS { ret TooComplex }
    if source.len < count || out.len < count { ret TooComplex }
    if prims.len == 0usize {
        copy_into(source, out, count)
        ret ok
    }
    let (alpha, e1) = mem.alloc[f32](a, count)
    if e1 != ok { ret e1 }
    let (empty, e2) = mem.alloc[f32](a, count)
    if e2 != ok { ret e2 }
    let (work, e3) = mem.alloc[f32](a, count)
    if e3 != ok { ret e3 }
    let (tmp, e4) = mem.alloc[f32](a, count)
    if e4 != ok { ret e4 }
    let (lin1, e5) = mem.alloc[f32](a, count)
    if e5 != ok { ret e5 }
    let (lin2, e6) = mem.alloc[f32](a, count)
    if e6 != ok { ret e6 }
    var i = 0usize
    while i < count {
        empty[i] = 0.0
        if i % 4usize == 3usize { alpha[i] = source[i] } else { alpha[i] = 0.0 }
        i += 1usize
    }
    var results: [16][]f32 = zero
    var k = 0usize
    while k < prims.len {
        let p = prims[k]
        let (dst, de) = mem.alloc[f32](a, count)
        if de != ok { ret de }
        var in1 = pick(p.in1, source, alpha, empty, results[0usize..16usize], k)
        var in2 = pick(p.in2, source, alpha, empty, results[0usize..16usize], k)
        // Colour-neutral kinds never need the transfer curve.
        let neutral = p.kind == KIND_OFFSET || p.kind == KIND_FLOOD || p.kind == KIND_MERGE || p.kind == KIND_PASS
        var convert_in = p.linear && !neutral
        if convert_in {
            convert(in1, lin1, w * h, true)
            in1 = lin1
            if p.kind == KIND_BLEND || p.kind == KIND_COMPOSITE {
                convert(in2, lin2, w * h, true)
                in2 = lin2
            }
        }
        if p.kind == KIND_BLUR {
            copy_into(in1, dst, count)
            blur_axis(dst, tmp, w, h, true, p.p[0usize], count)
            blur_axis(dst, tmp, w, h, false, p.p[1usize], count)
        } else if p.kind == KIND_OFFSET {
            shift_pixels(in1, dst, w, h, i32(math.round[f32](p.p[0usize])), i32(math.round[f32](p.p[1usize])))
        } else if p.kind == KIND_FLOOD {
            var j = 0usize
            while j < w * h {
                let at = j * 4usize
                dst[at] = p.p[0usize] * p.p[3usize]
                dst[at + 1usize] = p.p[1usize] * p.p[3usize]
                dst[at + 2usize] = p.p[2usize] * p.p[3usize]
                dst[at + 3usize] = p.p[3usize]
                j += 1usize
            }
        } else if p.kind == KIND_BLEND {
            blend(in1, in2, dst, w * h, p.mode)
        } else if p.kind == KIND_COMPOSITE {
            composite(in1, in2, dst, w * h, p.mode, p.p[0usize], p.p[1usize], p.p[2usize], p.p[3usize])
        } else if p.kind == KIND_MATRIX {
            var m: [20]f32 = zero
            matrix_of(p.mode, p.p[0usize..20usize], m[0usize..20usize])
            color_matrix(in1, dst, w * h, m[0usize..20usize])
        } else if p.kind == KIND_MERGE {
            var j = 0usize
            while j < count {
                dst[j] = 0.0
                j += 1usize
            }
            var n = 0usize
            while n < p.merge_n && n < MAX_MERGE {
                over_into(pick(p.merge[n], source, alpha, empty, results[0usize..16usize], k), dst, w * h)
                n += 1usize
            }
        } else if p.kind == KIND_SHADOW {
            // The input's alpha, blurred, moved and flooded, then the input over it.
            var j = 0usize
            while j < w * h {
                work[j * 4usize] = 0.0
                work[j * 4usize + 1usize] = 0.0
                work[j * 4usize + 2usize] = 0.0
                work[j * 4usize + 3usize] = in1[j * 4usize + 3usize]
                j += 1usize
            }
            blur_axis(work, tmp, w, h, true, p.p[2usize], count)
            blur_axis(work, tmp, w, h, false, p.p[3usize], count)
            shift_pixels(work, dst, w, h, i32(math.round[f32](p.p[0usize])), i32(math.round[f32](p.p[1usize])))
            var cr = p.p[4usize]
            var cg = p.p[5usize]
            var cb = p.p[6usize]
            if convert_in {
                cr = srgb_to_linear(cr)
                cg = srgb_to_linear(cg)
                cb = srgb_to_linear(cb)
            }
            j = 0usize
            while j < w * h {
                let at = j * 4usize
                let s = dst[at + 3usize] * p.p[7usize]
                dst[at] = cr * s
                dst[at + 1usize] = cg * s
                dst[at + 2usize] = cb * s
                dst[at + 3usize] = s
                j += 1usize
            }
            over_into(in1, dst, w * h)
        } else {
            copy_into(in1, dst, count)
        }
        if convert_in {
            // The result was computed in linear light.
            copy_into(dst, work, count)
            convert(work, dst, w * h, false)
        }
        cut(dst, w, h, p.x0, p.y0, p.x1, p.y1)
        results[k] = dst
        k += 1usize
    }
    copy_into(results[prims.len - 1usize], out, count)
    ret ok
}

// ---- the scratch target ---------------------------------------------------------------------------------

// Draws `list` (in the scratch's own pixel space: the origin is the top left of the `w` x `h` target) and reads
// the pixels back as premultiplied f32 into `out`. A font drawn by the list is registered with the scratch
// renderer.
fn render_pixels(a: *mem.Arena, hst: *const Host, list: scene.DisplayList, w: usize, h: usize, font: fonts.Font, has_font: bool, out: []f32) -> err {
    if w == 0usize || h == 0usize || w * h > hst.max_pixels || out.len < w * h * 4usize { ret TooComplex }
    let (pixels, pixels_error) = mem.alloc[u32](a, w * h)
    if pixels_error != ok { ret pixels_error }
    let (state, state_error) = scene.renderer_state(hst.renderer)
    if state_error != ok { ret state_error }
    let queue = state.queue
    let (made, made_error) = scene.renderer(a, state.device, queue, 1u32, 1u32)
    if made_error != ok { ret made_error }
    var scratch = made
    if has_font { try scene.register_font(&scratch, font) }
    let (frames, frames_error) = gpu.open_target(queue, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(w), u32(h), gpu.Format.Bgra8)
    if frames_error != ok { ret frames_error }
    defer let _ = gpu.close_target(frames)
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret canvas_error }
    let (id, compile_error) = scene.compile(&scratch, list)
    if compile_error != ok { ret compile_error }
    try scene.render(&scratch, id, canvas, geometry.Size { width: f32(w), height: f32(h) })
    let (shown, shown_error) = gpu.presented(frames)
    if shown_error != ok { ret shown_error }
    let reader = state.queue
    if gpu.read_image(reader, shown, pixels) != ok { ret TooComplex }
    var i = 0usize
    while i < w * h {
        let v = pixels[i]
        out[i * 4usize] = f32((v >> 16u32) & 255u32) / 255.0
        out[i * 4usize + 1usize] = f32((v >> 8u32) & 255u32) / 255.0
        out[i * 4usize + 2usize] = f32(v & 255u32) / 255.0
        out[i * 4usize + 3usize] = f32((v >> 24u32) & 255u32) / 255.0
        i += 1usize
    }
    try scene.close(&scratch)
    ret ok
}

// A texture of the host's renderer for a `w` x `h` result, taken first so that its pixels (allocated from the
// renderer's arena, which is usually `a`) sit below any scratch the caller then resets. `fill` writes the result.
type Slot = struct { id: scene.TextureId, bytes: []u8 }

fn reserve(a: *mem.Arena, hst: *Host, w: usize, h: usize) -> (Slot, err) {
    if hst.texture_count >= MAX_TEXTURES { ret (zero, TooComplex) }
    let (bytes, bytes_error) = mem.alloc[u8](a, w * h * 4usize)
    if bytes_error != ok { ret (zero, bytes_error) }
    var i = 0usize
    while i < w * h * 4usize {
        bytes[i] = 0u8
        i += 1usize
    }
    let view = image.ConstImage { pixels: bytes, width: u32(w), height: u32(h), stride: w * 4usize, format: .Rgba8, alpha: .Premultiplied }
    let (id, upload_error) = scene.upload_image(hst.renderer, view)
    if upload_error != ok { ret (zero, upload_error) }
    hst.textures[hst.texture_count] = id
    hst.texture_count += 1usize
    ret (Slot { id: id, bytes: bytes }, ok)
}

fn fill(hst: *const Host, slot: Slot, pixels: []const f32, w: usize, h: usize) -> err {
    var i = 0usize
    while i < w * h * 4usize {
        let v = clamp01(pixels[i])
        slot.bytes[i] = u8(v * 255.0 + 0.5)
        i += 1usize
    }
    let view = image.ConstImage { pixels: slot.bytes, width: u32(w), height: u32(h), stride: w * 4usize, format: .Rgba8, alpha: .Premultiplied }
    ret scene.update_image(hst.renderer, slot.id, view)
}
