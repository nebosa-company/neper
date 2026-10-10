// Animation interpolation primitives (L039), after Vaper's `vaper_css_values/lib/src/interpolate.dart`: a linear
// interpolation, a colour interpolation in sRGB component by component, a cubic-bezier timing function evaluated by
// bisection on x, and the interpolation of two 2D affine transforms by decomposition into translation, scale, rotation
// and one shear, the rotation taking the shorter arc. A 2D affine is `[a, b, c, d, e, f]` mapping (x, y) to
// (a x + c y + e, b x + d y + f). `e.ui.animation` keeps the widget-facing controller; these are the pure kernels.

use e.math

// A transform split into the parts CSS interpolates independently; `angle` in radians.
type Decomposed = struct { translate_x: f64, translate_y: f64, scale_x: f64, scale_y: f64, angle: f64, skew: f64 }

fn pi() -> f64 { ret 3.141592653589793f64 }

// `a + (b - a) * t`.
fn lerp(a: f64, b: f64, t: f64) -> f64 { ret a + (b - a) * t }

// Round to the nearest whole number, a half going away from zero (Dart's `round()`; `e.math.round` takes ties to even).
fn round_half_away(x: f64) -> f64 {
    if !(math.abs[f64](x) < 4503599627370496.0f64) { ret x }
    let t = math.trunc[f64](x)
    let fraction = math.abs[f64](x - t)
    if fraction >= 0.5f64 { ret t + math.copysign[f64](1.0f64, x) }
    ret t
}

fn channel(a: u32, b: u32, shift: u32, t: f64) -> u32 {
    let ca = f64((a >> shift) & 255u32)
    let cb = f64((b >> shift) & 255u32)
    var v = round_half_away(ca + (cb - ca) * t)
    if v < 0.0f64 { v = 0.0f64 }
    if v > 255.0f64 { v = 255.0f64 }
    ret u32(v)
}

// Two ARGB colours interpolated component-wise in sRGB (the CSS default) at `t`.
fn lerp_color_argb(a: u32, b: u32, t: f64) -> u32 {
    ret (channel(a, b, 24u32, t) << 24u32) | (channel(a, b, 16u32, t) << 16u32) | (channel(a, b, 8u32, t) << 8u32) | channel(a, b, 0u32, t)
}

// `y(t)` of a cubic-bezier timing function with control points (x1, y1) and (x2, y2), by 24 bisections on x.
fn cubic_bezier(x1: f64, y1: f64, x2: f64, y2: f64, t: f64) -> f64 {
    if t <= 0.0f64 { ret 0.0f64 }
    if t >= 1.0f64 { ret 1.0f64 }
    var lo = 0.0f64
    var hi = 1.0f64
    var i = 0i32
    while i < 24i32 {
        let mid = (lo + hi) / 2.0f64
        let v = 1.0f64 - mid
        let bx = 3.0f64 * v * v * mid * x1 + 3.0f64 * v * mid * mid * x2 + mid * mid * mid
        if bx < t { lo = mid } else { hi = mid }
        i += 1i32
    }
    let u = (lo + hi) / 2.0f64
    let v = 1.0f64 - u
    ret 3.0f64 * v * v * u * y1 + 3.0f64 * v * u * u * y2 + u * u * u
}

// The CSS 2D matrix decomposition: scale along the first row, shear removed, a reflection folded into scale_x.
fn decompose2d(m: [6]f64) -> Decomposed {
    var row0x = m[0]
    var row0y = m[1]
    var row1x = m[2]
    var row1y = m[3]
    var scale_x = math.sqrt[f64](row0x * row0x + row0y * row0y)
    if scale_x != 0.0f64 {
        row0x = row0x / scale_x
        row0y = row0y / scale_x
    }
    var skew = row0x * row1x + row0y * row1y
    row1x = row1x - row0x * skew
    row1y = row1y - row0y * skew
    let scale_y = math.sqrt[f64](row1x * row1x + row1y * row1y)
    if scale_y != 0.0f64 {
        row1x = row1x / scale_y
        row1y = row1y / scale_y
        skew = skew / scale_y
    }
    if row0x * row1y - row0y * row1x < 0.0f64 {
        row0x = -row0x
        row0y = -row0y
        scale_x = -scale_x
    }
    ret Decomposed { translate_x: m[4], translate_y: m[5], scale_x: scale_x, scale_y: scale_y, angle: math.atan2[f64](row0y, row0x), skew: skew }
}

fn recompose2d(d: Decomposed) -> [6]f64 {
    let c = math.cos[f64](d.angle)
    let s = math.sin[f64](d.angle)
    var out: [6]f64 = zero
    out[0] = c * d.scale_x
    out[1] = s * d.scale_x
    out[2] = d.scale_y * (-s + c * d.skew)
    out[3] = d.scale_y * (c + s * d.skew)
    out[4] = d.translate_x
    out[5] = d.translate_y
    ret out
}

// Two 2D affine transforms interpolated at `t` by decomposition.
fn lerp_affine(a: [6]f64, b: [6]f64, t: f64) -> [6]f64 {
    if t <= 0.0f64 { ret a }
    if t >= 1.0f64 { ret b }
    let da = decompose2d(a)
    let db = decompose2d(b)
    var angle_b = db.angle
    if math.abs[f64](angle_b - da.angle) > pi() {
        if angle_b < da.angle { angle_b = angle_b + 2.0f64 * pi() } else { angle_b = angle_b - 2.0f64 * pi() }
    }
    ret recompose2d(Decomposed {
        translate_x: lerp(da.translate_x, db.translate_x, t),
        translate_y: lerp(da.translate_y, db.translate_y, t),
        scale_x: lerp(da.scale_x, db.scale_x, t),
        scale_y: lerp(da.scale_y, db.scale_y, t),
        angle: lerp(da.angle, angle_b, t),
        skew: lerp(da.skew, db.skew, t),
    })
}
