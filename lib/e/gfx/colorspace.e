// Colour-space conversion and colour difference, as R's farver does them: sRGB (0-255), CMY,
// CMYK, HSL, HSB, HSV, XYZ, xyY, CIE Lab, Hunter Lab, Lch, Luv, HCL, OkLab and OkLch, with a
// white reference for the relative ones, the same capping of input and output, and the same
// formulas (farver's ColorSpace library, and its Euclidean, CIE76, CIE94, CIE2000 and CMC
// distances). Colours move through sRGB, so a conversion is "to sRGB under the source white,
// then from sRGB under the target white", and a non-finite channel makes the colour invalid
// (every channel NaN).
//
// Not here: farver's `encode_colour`/`decode_colour`, the `modify` operations, and alpha.

use e.math
use e.mem

// farver's numbering of the spaces.
const CMY: u8 = 1u8
const CMYK: u8 = 2u8
const HSL: u8 = 3u8
const HSB: u8 = 4u8
const HSV: u8 = 5u8
const LAB: u8 = 6u8
const HUNTERLAB: u8 = 7u8
const LCH: u8 = 8u8
const LUV: u8 = 9u8
const RGB: u8 = 10u8
const XYZ: u8 = 11u8
const YXY: u8 = 12u8
const HCL: u8 = 13u8
const OKLAB: u8 = 14u8
const OKLCH: u8 = 15u8

type Color = struct { a: f64, b: f64, c: f64, d: f64 }
type White = struct { x: f64, y: f64, z: f64 }
type Rgb = struct { r: f64, g: f64, b: f64, valid: bool }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn min_of(a: f64, b: f64) -> f64 {
    if b < a { ret b }
    ret a
}

fn max_of(a: f64, b: f64) -> f64 {
    if a < b { ret b }
    ret a
}

fn clamp(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

fn floor_nonneg(x: f64) -> f64 { ret math.floor[f64](x) }

// C's fmod for positive operands.
fn fmod(x: f64, y: f64) -> f64 {
    let n = math.floor[f64](x / y)
    ret x - n * y
}

fn cbrt(x: f64) -> f64 {
    if x == 0.0f64 || !is_finite(x) { ret x }
    var ax = abs_of(x)
    var r = math.pow[f64](ax, 1.0f64 / 3.0f64)
    r = r - (r * r * r - ax) / (3.0f64 * r * r)
    if x < 0.0f64 { ret 0.0f64 - r }
    ret r
}

fn pi() -> f64 { ret 3.141592653589793f64 }

fn white_d65() -> White { ret White { x: 95.047f64, y: 100.0f64, z: 108.883f64 } }

// as_white_ref(): a chromaticity pair (x, y) or a tristimulus triple, normalised to Y = 100.
fn white_from_xy(x: f64, y: f64) -> White {
    let tmp = 100.0f64 / y
    ret White { x: tmp * x, y: 100.0f64, z: tmp * (1.0f64 - (x + y)) }
}

fn white_from_xyz(x: f64, y: f64, z: f64) -> White {
    if y != 100.0f64 {
        let k = 100.0f64 / y
        ret White { x: x * k, y: y * k, z: z * k }
    }
    ret White { x: x, y: y, z: z }
}

fn dimension(space: u8) -> usize {
    if space == CMYK { ret 4usize }
    ret 3usize
}

fn invalid() -> Color { ret Color { a: nan(), b: nan(), c: nan(), d: nan() } }

fn all_finite(v: Color, n: usize) -> bool {
    if !is_finite(v.a) || !is_finite(v.b) || !is_finite(v.c) { ret false }
    if n == 4usize && !is_finite(v.d) { ret false }
    ret true
}

// Cap(): the channel limits of each space.
fn cap(space: u8, v: Color) -> Color {
    var o = v
    if space == RGB {
        o.a = clamp(v.a, 0.0f64, 255.0f64)
        o.b = clamp(v.b, 0.0f64, 255.0f64)
        o.c = clamp(v.c, 0.0f64, 255.0f64)
    } else if space == XYZ {
        o.a = max_of(v.a, 0.0f64)
        o.b = max_of(v.b, 0.0f64)
        o.c = max_of(v.c, 0.0f64)
    } else if space == HSL {
        o.a = clamp(v.a, 0.0f64, 360.0f64)
        o.b = clamp(v.b, 0.0f64, 100.0f64)
        o.c = clamp(v.c, 0.0f64, 100.0f64)
    } else if space == LAB || space == LUV || space == HUNTERLAB {
        o.a = clamp(v.a, 0.0f64, 100.0f64)
    } else if space == LCH {
        o.a = clamp(v.a, 0.0f64, 100.0f64)
        o.b = max_of(v.b, 0.0f64)
        o.c = clamp(v.c, 0.0f64, 360.0f64)
    } else if space == YXY {
        o.a = clamp(v.a, 0.0f64, 100.0f64)
        o.b = max_of(v.b, 0.0f64)
        o.c = max_of(v.c, 0.0f64)
    } else if space == CMY || space == CMYK {
        o.a = clamp(v.a, 0.0f64, 1.0f64)
        o.b = clamp(v.b, 0.0f64, 1.0f64)
        o.c = clamp(v.c, 0.0f64, 1.0f64)
        if space == CMYK { o.d = clamp(v.d, 0.0f64, 1.0f64) }
    } else if space == HSV || space == HSB {
        o.a = clamp(v.a, 0.0f64, 360.0f64)
        o.b = clamp(v.b, 0.0f64, 1.0f64)
        o.c = clamp(v.c, 0.0f64, 1.0f64)
    } else if space == HCL {
        o.a = clamp(v.a, 0.0f64, 360.0f64)
        o.b = max_of(v.b, 0.0f64)
        o.c = clamp(v.c, 0.0f64, 100.0f64)
    } else if space == OKLAB {
        o.a = clamp(v.a, 0.0f64, 1.0f64)
    } else if space == OKLCH {
        o.a = clamp(v.a, 0.0f64, 1.0f64)
    }
    ret o
}

fn pow3(x: f64) -> f64 { ret x * x * x }

// --- sRGB <-> XYZ (percent scale), and the white-relative spaces built on it.

fn xyz_of(r: Rgb) -> Color {
    var rr = r.r / 255.0f64
    var gg = r.g / 255.0f64
    var bb = r.b / 255.0f64
    if rr > 0.04045f64 { rr = math.pow[f64]((rr + 0.055f64) / 1.055f64, 2.4f64) } else { rr = rr / 12.92f64 }
    if gg > 0.04045f64 { gg = math.pow[f64]((gg + 0.055f64) / 1.055f64, 2.4f64) } else { gg = gg / 12.92f64 }
    if bb > 0.04045f64 { bb = math.pow[f64]((bb + 0.055f64) / 1.055f64, 2.4f64) } else { bb = bb / 12.92f64 }
    rr = rr * 100.0f64
    gg = gg * 100.0f64
    bb = bb * 100.0f64
    ret Color { a: rr * 0.4124564f64 + gg * 0.3575761f64 + bb * 0.1804375f64, b: rr * 0.2126729f64 + gg * 0.7151522f64 + bb * 0.0721750f64, c: rr * 0.0193339f64 + gg * 0.1191920f64 + bb * 0.9503041f64, d: 0.0f64 }
}

fn companded(v: f64) -> f64 {
    if v > 0.0031308f64 { ret (1.055f64 * math.pow[f64](v, 1.0f64 / 2.4f64) - 0.055f64) * 255.0f64 }
    ret (12.92f64 * v) * 255.0f64
}

fn rgb_of_xyz(x0: f64, y0: f64, z0: f64) -> Rgb {
    let x = x0 / 100.0f64
    let y = y0 / 100.0f64
    let z = z0 / 100.0f64
    let r = x * 3.2404542f64 + y * -1.5371385f64 + z * -0.4985314f64
    let g = x * -0.9692660f64 + y * 1.8760108f64 + z * 0.0415560f64
    let b = x * 0.0556434f64 + y * -0.2040259f64 + z * 1.0572252f64
    ret Rgb { r: companded(r), g: companded(g), b: companded(b), valid: true }
}

fn eps() -> f64 { ret 216.0f64 / 24389.0f64 }

fn kappa() -> f64 { ret 24389.0f64 / 27.0f64 }

fn lab_of(r: Rgb, w: White) -> Color {
    let xyz = xyz_of(r)
    var x = xyz.a / w.x
    var y = xyz.b / w.y
    var z = xyz.c / w.z
    if x > 0.008856f64 { x = cbrt(x) } else { x = 7.787f64 * x + 16.0f64 / 116.0f64 }
    if y > 0.008856f64 { y = cbrt(y) } else { y = 7.787f64 * y + 16.0f64 / 116.0f64 }
    if z > 0.008856f64 { z = cbrt(z) } else { z = 7.787f64 * z + 16.0f64 / 116.0f64 }
    ret Color { a: 116.0f64 * y - 16.0f64, b: 500.0f64 * (x - y), c: 200.0f64 * (y - z), d: 0.0f64 }
}

fn rgb_of_lab(l: f64, a: f64, b: f64, w: White) -> Rgb {
    var y = (l + 16.0f64) / 116.0f64
    var x = a / 500.0f64 + y
    var z = y - b / 200.0f64
    let x3 = pow3(x)
    let y3 = pow3(y)
    let z3 = pow3(z)
    if x3 > 0.008856f64 { x = x3 } else { x = (x - 16.0f64 / 116.0f64) / 7.787f64 }
    if y3 > 0.008856f64 { y = y3 } else { y = (y - 16.0f64 / 116.0f64) / 7.787f64 }
    if z3 > 0.008856f64 { z = z3 } else { z = (z - 16.0f64 / 116.0f64) / 7.787f64 }
    ret rgb_of_xyz(x * w.x, y * w.y, z * w.z)
}

fn polar(a: f64, b: f64) -> (f64, f64) {
    let c = math.sqrt[f64](a * a + b * b)
    var h = math.atan2[f64](b, a)
    h = h / pi() * 180.0f64
    if h < 0.0f64 { h = h + 360.0f64 } else if h >= 360.0f64 { h = h - 360.0f64 }
    ret (c, h)
}

fn luv_of(r: Rgb, w: White) -> Color {
    let xyz = xyz_of(r)
    let y = xyz.b / w.y
    let temp = xyz.a + 15.0f64 * xyz.b + 3.0f64 * xyz.c
    let tempr = w.x + 15.0f64 * w.y + 3.0f64 * w.z
    var l = kappa() * y
    if y > eps() { l = 116.0f64 * cbrt(y) - 16.0f64 }
    var fx = 0.0f64
    var fy = 0.0f64
    if temp > 0.001f64 {
        fx = xyz.a / temp
        fy = xyz.b / temp
    }
    ret Color { a: l, b: 52.0f64 * l * (fx - w.x / tempr), c: 117.0f64 * l * (fy - w.y / tempr), d: 0.0f64 }
}

fn rgb_of_luv(l: f64, u: f64, v: f64, w: White) -> Rgb {
    if l == 0.0f64 { ret rgb_of_xyz(0.0f64, 0.0f64, 0.0f64) }
    var y = l / kappa()
    if l > eps() * kappa() { y = pow3((l + 16.0f64) / 116.0f64) }
    let tempr = w.x + 15.0f64 * w.y + 3.0f64 * w.z
    let up = 4.0f64 * w.x / tempr
    let vp = 9.0f64 * w.y / tempr
    let a = 1.0f64 / 3.0f64 * (52.0f64 * l / (u + 13.0f64 * l * up) - 1.0f64)
    let b = -5.0f64 * y
    let x = (y * (39.0f64 * l / (v + 13.0f64 * l * vp) - 5.0f64) - b) / (a + 1.0f64 / 3.0f64)
    let z = x * a + b
    if z != z { ret rgb_of_xyz(0.0f64, 0.0f64, 0.0f64) }
    ret rgb_of_xyz(x * 100.0f64, y * 100.0f64, z * 100.0f64)
}

fn hue_to_rgb(v1: f64, v2: f64, vh0: f64) -> f64 {
    var vh = vh0
    if vh < 0.0f64 { vh = vh + 1.0f64 }
    if vh > 1.0f64 { vh = vh - 1.0f64 }
    if 6.0f64 * vh < 1.0f64 { ret v1 + (v2 - v1) * 6.0f64 * vh }
    if 2.0f64 * vh < 1.0f64 { ret v2 }
    if 3.0f64 * vh < 2.0f64 { ret v1 + (v2 - v1) * (2.0f64 / 3.0f64 - vh) * 6.0f64 }
    ret v1
}

fn srgb_decode(v: f64) -> f64 {
    if v > 0.04045f64 { ret math.pow[f64]((v + 0.055f64) / 1.055f64, 2.4f64) }
    ret v / 12.92f64
}

// --- To and from sRGB for every space.

fn to_rgb(space: u8, v: Color, w: White) -> Rgb {
    if !all_finite(v, dimension(space)) { ret Rgb { r: nan(), g: nan(), b: nan(), valid: false } }
    let a = v.a
    let b = v.b
    let c = v.c
    if space == RGB { ret Rgb { r: a, g: b, b: c, valid: true } }
    if space == XYZ { ret rgb_of_xyz(a, b, c) }
    if space == HSL {
        let h = a / 360.0f64
        let s = b / 100.0f64
        let l = c / 100.0f64
        if b == 0.0f64 {
            let g = c / 100.0f64 * 255.0f64
            ret Rgb { r: g, g: g, b: g, valid: true }
        }
        var t2 = l + s - (s * l)
        if l < 0.5f64 { t2 = l * (1.0f64 + s) }
        let t1 = 2.0f64 * l - t2
        ret Rgb { r: 255.0f64 * hue_to_rgb(t1, t2, h + 1.0f64 / 3.0f64), g: 255.0f64 * hue_to_rgb(t1, t2, h), b: 255.0f64 * hue_to_rgb(t1, t2, h - 1.0f64 / 3.0f64), valid: true }
    }
    if space == LAB { ret rgb_of_lab(a, b, c, w) }
    if space == LCH {
        let h = c * pi() / 180.0f64
        ret rgb_of_lab(a, math.cos[f64](h) * b, math.sin[f64](h) * b, w)
    }
    if space == LUV { ret rgb_of_luv(a, b, c, w) }
    if space == HCL {
        let h = a * pi() / 180.0f64
        ret rgb_of_luv(c, math.cos[f64](h) * b, math.sin[f64](h) * b, w)
    }
    if space == YXY {
        let x = b * (a / c)
        let z = (1.0f64 - b - c) * (a / c)
        ret rgb_of_xyz(x, a, z)
    }
    if space == CMY { ret Rgb { r: (1.0f64 - a) * 255.0f64, g: (1.0f64 - b) * 255.0f64, b: (1.0f64 - c) * 255.0f64, valid: true } }
    if space == CMYK {
        let k = v.d
        let cc = a * (1.0f64 - k) + k
        let mm = b * (1.0f64 - k) + k
        let yy = c * (1.0f64 - k) + k
        ret Rgb { r: (1.0f64 - cc) * 255.0f64, g: (1.0f64 - mm) * 255.0f64, b: (1.0f64 - yy) * 255.0f64, valid: true }
    }
    if space == HSV || space == HSB {
        let range = i64(math.floor[f64](a / 60.0f64))
        let cc = c * b
        let x = cc * (1.0f64 - abs_of(fmod(a / 60.0f64, 2.0f64) - 1.0f64))
        let m = c - cc
        if range == 0i64 { ret Rgb { r: (cc + m) * 255.0f64, g: (x + m) * 255.0f64, b: m * 255.0f64, valid: true } }
        if range == 1i64 { ret Rgb { r: (x + m) * 255.0f64, g: (cc + m) * 255.0f64, b: m * 255.0f64, valid: true } }
        if range == 2i64 { ret Rgb { r: m * 255.0f64, g: (cc + m) * 255.0f64, b: (x + m) * 255.0f64, valid: true } }
        if range == 3i64 { ret Rgb { r: m * 255.0f64, g: (x + m) * 255.0f64, b: (cc + m) * 255.0f64, valid: true } }
        if range == 4i64 { ret Rgb { r: (x + m) * 255.0f64, g: m * 255.0f64, b: (cc + m) * 255.0f64, valid: true } }
        ret Rgb { r: (cc + m) * 255.0f64, g: m * 255.0f64, b: (x + m) * 255.0f64, valid: true }
    }
    if space == HUNTERLAB {
        let x = (b / 17.5f64) * (a / 10.0f64)
        let y = a * a / 100.0f64
        let z = c / 7.0f64 * a / 10.0f64
        ret rgb_of_xyz((x + y) / 1.02f64, y, 0.0f64 - (z - y) / 0.847f64)
    }
    if space == OKLAB || space == OKLCH {
        var la = a
        var lb = b
        var lc = c
        if space == OKLCH {
            let h = c * pi() / 180.0f64
            lb = math.cos[f64](h) * b
            lc = math.sin[f64](h) * b
        }
        var l = la + 0.3963377774f64 * lb + 0.2158037573f64 * lc
        var m = la - 0.1055613458f64 * lb - 0.0638541728f64 * lc
        var s = la - 0.0894841775f64 * lb - 1.2914855480f64 * lc
        l = l * l * l
        m = m * m * m
        s = s * s * s
        let r = 4.0767245293f64 * l - 3.3072168827f64 * m + 0.2307590544f64 * s
        let g = -1.2681437731f64 * l + 2.6093323231f64 * m - 0.3411344290f64 * s
        let bl = -0.0041119885f64 * l - 0.7034763098f64 * m + 1.7068625689f64 * s
        ret Rgb { r: companded(r), g: companded(g), b: companded(bl), valid: true }
    }
    ret Rgb { r: nan(), g: nan(), b: nan(), valid: false }
}

fn from_rgb(space: u8, r: Rgb, w: White) -> Color {
    if !r.valid { ret invalid() }
    if space == RGB { ret Color { a: r.r, b: r.g, c: r.b, d: 0.0f64 } }
    if space == XYZ { ret xyz_of(r) }
    if space == LAB { ret lab_of(r, w) }
    if space == LUV { ret luv_of(r, w) }
    if space == LCH {
        let lab = lab_of(r, w)
        let (c, h) = polar(lab.b, lab.c)
        ret Color { a: lab.a, b: c, c: h, d: 0.0f64 }
    }
    if space == HCL {
        let luv = luv_of(r, w)
        let (c, h) = polar(luv.b, luv.c)
        ret Color { a: h, b: c, c: luv.a, d: 0.0f64 }
    }
    if space == YXY {
        let xyz = xyz_of(r)
        let temp = xyz.a + xyz.b + xyz.c
        var x = 0.0f64
        var y2 = 0.0f64
        if temp != 0.0f64 {
            x = xyz.a / temp
            y2 = xyz.b / temp
        }
        ret Color { a: xyz.b, b: x, c: y2, d: 0.0f64 }
    }
    if space == CMY { ret Color { a: 1.0f64 - r.r / 255.0f64, b: 1.0f64 - r.g / 255.0f64, c: 1.0f64 - r.b / 255.0f64, d: 0.0f64 } }
    if space == CMYK {
        let c = 1.0f64 - r.r / 255.0f64
        let m = 1.0f64 - r.g / 255.0f64
        let y = 1.0f64 - r.b / 255.0f64
        var k = 1.0f64
        k = min_of(k, c)
        k = min_of(k, m)
        k = min_of(k, y)
        if abs_of(k - 1.0f64) < 0.001f64 { ret Color { a: 0.0f64, b: 0.0f64, c: 0.0f64, d: k } }
        ret Color { a: (c - k) / (1.0f64 - k), b: (m - k) / (1.0f64 - k), c: (y - k) / (1.0f64 - k), d: k }
    }
    if space == HSL {
        let rr = r.r / 255.0f64
        let gg = r.g / 255.0f64
        let bb = r.b / 255.0f64
        let mn = min_of(rr, min_of(gg, bb))
        let mx = max_of(rr, max_of(gg, bb))
        let delta = mx - mn
        var l = (mx + mn) / 2.0f64
        var h = 0.0f64
        var s = 0.0f64
        if delta != 0.0f64 {
            if l < 0.5f64 { s = delta / (mx + mn) * 100.0f64 } else { s = delta / (1.0f64 - abs_of(2.0f64 * l - 1.0f64)) * 100.0f64 }
            if rr == mx { h = (gg - bb) / delta } else if gg == mx { h = (bb - rr) / delta + 2.0f64 } else if bb == mx { h = (rr - gg) / delta + 4.0f64 }
            h = fmod(60.0f64 * h + 360.0f64, 360.0f64)
        }
        l = l * 100.0f64
        ret Color { a: h, b: s, c: l, d: 0.0f64 }
    }
    if space == HSV || space == HSB {
        let rr = r.r / 255.0f64
        let gg = r.g / 255.0f64
        let bb = r.b / 255.0f64
        let mn = min_of(rr, min_of(gg, bb))
        let mx = max_of(rr, max_of(gg, bb))
        let delta = mx - mn
        var s = 0.0f64
        if mx > 0.001f64 { s = delta / mx }
        var h = 0.0f64
        if delta != 0.0f64 {
            if rr == mx { h = (gg - bb) / delta } else if gg == mx { h = 2.0f64 + (bb - rr) / delta } else if bb == mx { h = 4.0f64 + (rr - gg) / delta }
            h = h * 60.0f64
            h = fmod(h + 360.0f64, 360.0f64)
        }
        ret Color { a: h, b: s, c: mx, d: 0.0f64 }
    }
    if space == HUNTERLAB {
        let xyz = xyz_of(r)
        var a = 0.0f64
        var b = 0.0f64
        if xyz.b != 0.0f64 {
            a = 17.5f64 * (1.02f64 * xyz.a - xyz.b) / math.sqrt[f64](xyz.b)
            b = 7.0f64 * (xyz.b - 0.847f64 * xyz.c) / math.sqrt[f64](xyz.b)
        }
        ret Color { a: 10.0f64 * math.sqrt[f64](xyz.b), b: a, c: b, d: 0.0f64 }
    }
    if space == OKLAB || space == OKLCH {
        var l = srgb_decode(r.r / 255.0f64)
        var m = srgb_decode(r.g / 255.0f64)
        var s = srgb_decode(r.b / 255.0f64)
        let rr = l
        let gg = m
        let bb = s
        l = cbrt(0.4121656120f64 * rr + 0.5362752080f64 * gg + 0.0514575653f64 * bb)
        m = cbrt(0.2118591070f64 * rr + 0.6807189584f64 * gg + 0.1074065790f64 * bb)
        s = cbrt(0.0883097947f64 * rr + 0.2818474174f64 * gg + 0.6302613616f64 * bb)
        let ol = 0.2104542553f64 * l + 0.7936177850f64 * m - 0.0040720468f64 * s
        let oa = 1.9779984951f64 * l - 2.4285922050f64 * m + 0.4505937099f64 * s
        let ob = 0.0259040371f64 * l + 0.7827717662f64 * m - 0.8086757660f64 * s
        if space == OKLAB { ret Color { a: ol, b: oa, c: ob, d: 0.0f64 } }
        let (c, h) = polar(oa, ob)
        ret Color { a: ol, b: c, c: h, d: 0.0f64 }
    }
    ret invalid()
}

// convert_colour(colour, from, to, white_from, white_to) for one colour.
fn convert(from: u8, to: u8, v: Color, wf: White, wt: White) -> Color {
    let rgb = to_rgb(from, cap(from, v), wf)
    let out = from_rgb(to, rgb, wt)
    if !rgb.valid { ret invalid() }
    ret cap(to, out)
}

// --- Distances.

const EUCLIDEAN: u8 = 1u8
const CIE1976: u8 = 2u8
const CIE94: u8 = 3u8
const CIE2000: u8 = 4u8
const CMC: u8 = 5u8

fn sqr(x: f64) -> f64 { ret x * x }

fn pow7(x: f64) -> f64 { ret pow3(x) * pow3(x) * x }

fn deg_to_rad(x: f64) -> f64 { ret x * pi() / 180.0f64 }

// compare_colour for one pair: both colours are read as `space` (farver reads the second in the
// first's space too), the first under white_from and the second under white_to, and the
// distance is taken under white_to. Negative answers (invalid colours) are NaN.
fn compare(space: u8, a: Color, b: Color, wf: White, wt: White, method: u8, lightness: f64, chroma: f64) -> f64 {
    let ra = to_rgb(space, cap(space, a), wf)
    let rb = to_rgb(space, cap(space, b), wt)
    if !ra.valid || !rb.valid { ret nan() }
    if method == EUCLIDEAN { ret math.sqrt[f64](sqr(ra.r - rb.r) + sqr(ra.g - rb.g) + sqr(ra.b - rb.b)) }
    let la = lab_of(ra, wt)
    let lb = lab_of(rb, wt)
    if method == CIE1976 { ret math.sqrt[f64](sqr(la.a - lb.a) + sqr(la.b - lb.b) + sqr(la.c - lb.c)) }
    if method == CIE94 {
        var delta_l = la.a - lb.a
        let da = la.b - lb.b
        let db = la.c - lb.c
        let c1 = math.sqrt[f64](sqr(la.b) + sqr(la.c))
        let c2 = math.sqrt[f64](sqr(lb.b) + sqr(lb.c))
        var delta_c = c1 - c2
        let delta_h = sqr(da) + sqr(db) - sqr(delta_c)
        let sc = 1.0f64 + 0.045f64 * c1
        let sh = 1.0f64 + 0.015f64 * c1
        delta_l = delta_l / (1.0f64 * 1.0f64)
        delta_c = delta_c / sc
        ret math.sqrt[f64](sqr(delta_l) + sqr(delta_c) + delta_h / sqr(sh))
    }
    if method == CIE2000 {
        let e = 0.00001f64
        var c1 = math.sqrt[f64](sqr(la.b) + sqr(la.c))
        var c2 = math.sqrt[f64](sqr(lb.b) + sqr(lb.c))
        var mean_c = (c1 + c2) / 2.0f64
        var mean_c7 = pow7(mean_c)
        let g = 0.5f64 * (1.0f64 - math.sqrt[f64](mean_c7 / (mean_c7 + 6103515625.0f64)))
        let a1p = la.b * (1.0f64 + g)
        let a2p = lb.b * (1.0f64 + g)
        c1 = math.sqrt[f64](sqr(a1p) + sqr(la.c))
        c2 = math.sqrt[f64](sqr(a2p) + sqr(lb.c))
        let h1 = fmod(math.atan2[f64](la.c, a1p) + 2.0f64 * pi(), 2.0f64 * pi())
        let h2 = fmod(math.atan2[f64](lb.c, a2p) + 2.0f64 * pi(), 2.0f64 * pi())
        let delta_l = lb.a - la.a
        let delta_c = c2 - c1
        var delta_h_small = 0.0f64
        if c1 * c2 < e {
            delta_h_small = 0.0f64
        }
        if abs_of(h2 - h1) <= pi() {
            delta_h_small = h2 - h1
        } else if h2 > h1 {
            delta_h_small = h2 - h1 - 2.0f64 * pi()
        } else {
            delta_h_small = h2 - h1 + 2.0f64 * pi()
        }
        let delta_h = 2.0f64 * math.sqrt[f64](c1 * c2) * math.sin[f64](delta_h_small / 2.0f64)
        let mean_l = (la.a + lb.a) / 2.0f64
        mean_c = (c1 + c2) / 2.0f64
        mean_c7 = pow7(mean_c)
        var mean_h = 0.0f64
        if c1 * c2 < e {
            mean_h = h1 + h2
        }
        if abs_of(h1 - h2) <= pi() + e {
            mean_h = (h1 + h2) / 2.0f64
        } else if h1 + h2 < 2.0f64 * pi() {
            mean_h = (h1 + h2 + 2.0f64 * pi()) / 2.0f64
        } else {
            mean_h = (h1 + h2 - 2.0f64 * pi()) / 2.0f64
        }
        let t = 1.0f64 - 0.17f64 * math.cos[f64](mean_h - deg_to_rad(30.0f64)) + 0.24f64 * math.cos[f64](2.0f64 * mean_h) + 0.32f64 * math.cos[f64](3.0f64 * mean_h + deg_to_rad(6.0f64)) - 0.2f64 * math.cos[f64](4.0f64 * mean_h - deg_to_rad(63.0f64))
        let sl = 1.0f64 + (0.015f64 * sqr(mean_l - 50.0f64)) / math.sqrt[f64](20.0f64 + sqr(mean_l - 50.0f64))
        let sc = 1.0f64 + 0.045f64 * mean_c
        let sh = 1.0f64 + 0.015f64 * mean_c * t
        let rc = 2.0f64 * math.sqrt[f64](mean_c7 / (mean_c7 + 6103515625.0f64))
        let rt = 0.0f64 - math.sin[f64](deg_to_rad(60.0f64 * math.exp[f64](0.0f64 - sqr((mean_h / pi() * 180.0f64 - 275.0f64) / 25.0f64)))) * rc
        ret math.sqrt[f64](sqr(delta_l / sl) + sqr(delta_c / sc) + sqr(delta_h / sh) + rt * delta_c / sc * delta_h / sh)
    }
    // CMC l:c
    let lcha = lch_from_lab(la)
    let lchb = lch_from_lab(lb)
    var sl = 0.040975f64 * lcha.a / (1.0f64 + 0.01765f64 * lcha.a)
    if lcha.a < 16.0f64 { sl = 0.511f64 }
    let sc = 0.0638f64 * lcha.b / (1.0f64 + 0.0131f64 * lcha.b) + 0.638f64
    var t = 0.36f64 + abs_of(0.4f64 * math.cos[f64](pi() * (lcha.c + 35.0f64) / 180.0f64))
    if 164.0f64 <= lcha.c && lcha.c <= 345.0f64 { t = 0.56f64 + abs_of(0.2f64 * math.cos[f64](pi() * (lcha.c + 168.0f64) / 180.0f64)) }
    let c4 = sqr(lcha.b) * sqr(lcha.b)
    let f = math.sqrt[f64](c4 / (c4 + 1900.0f64))
    let sh = sc * (f * t + 1.0f64 - f)
    let delta_l = lcha.a - lchb.a
    let delta_c = lcha.b - lchb.b
    let da = la.b - lb.b
    let db = la.c - lb.c
    let delta_h2 = da * da + db * db - delta_c * delta_c
    ret math.sqrt[f64](sqr(delta_l / (lightness * sl)) + sqr(delta_c / (chroma * sc)) + delta_h2 / sqr(sh))
}

fn lch_from_lab(lab: Color) -> Color {
    let (c, h) = polar(lab.b, lab.c)
    ret Color { a: lab.a, b: c, c: h, d: 0.0f64 }
}
