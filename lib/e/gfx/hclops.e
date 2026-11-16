// R colorspace beyond the palettes: `lighten` and `darken` in HCL, HLS and combined spaces (with `max_chroma` read from
// the package's table by bilinear interpolation), the polarLAB and polarLUV coordinates of an sRGB colour and the hex
// of a polarLAB colour, and the APCA contrast of a pair of colours. Colours are packed `r * 65536 + g * 256 + b`;
// -1 is NA. The white point is the package's default D65, (95.047, 100, 108.883).
//
// Not here: the other spaces (HSV, XYZ as objects), alpha, `desaturate`, `adjust_transparency`.

use e.gfx.hclpal as pal
use e.gfx.maxchroma_table as mct
use e.math
use e.mem
use e.str

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pi() -> f64 { ret 3.141592653589793f64 }

fn rad2deg(x: f64) -> f64 { ret 57.29577951308232087721f64 * x }

fn deg2rad(x: f64) -> f64 { ret 0.01745329251994329576f64 * x }

fn gtrans(u: f64) -> f64 {
    if u > 0.00304f64 { ret 1.055f64 * math.pow[f64](u, 1.0f64 / 2.4f64) - 0.055f64 }
    ret 12.92f64 * u
}

fn ftrans(u: f64) -> f64 {
    if u > 0.03928f64 { ret math.pow[f64]((u + 0.055f64) / 1.055f64, 2.4f64) }
    ret u / 12.92f64
}

fn kappa() -> f64 { ret 24389.0f64 / 27.0f64 }

fn epsilon() -> f64 { ret 216.0f64 / 24389.0f64 }

type Xyz = struct { x: f64, y: f64, z: f64 }
type Tri = struct { a: f64, b: f64, c: f64 }

fn unpack(rgb: i64) -> Tri {
    ret Tri { a: f64(rgb / 65536i64) / 255.0f64, b: f64((rgb / 256i64) % 256i64) / 255.0f64, c: f64(rgb % 256i64) / 255.0f64 }
}

fn srgb_to_xyz(r: f64, g: f64, b: f64) -> Xyz { ret lin_to_xyz(ftrans(r), ftrans(g), ftrans(b)) }

fn lin_to_xyz(lr: f64, lg: f64, lb: f64) -> Xyz {
    ret Xyz { x: 100.0f64 * (0.412453f64 * lr + 0.357580f64 * lg + 0.180423f64 * lb), y: 100.0f64 * (0.212671f64 * lr + 0.715160f64 * lg + 0.072169f64 * lb), z: 100.0f64 * (0.019334f64 * lr + 0.119193f64 * lg + 0.950227f64 * lb) }
}

fn xyz_to_srgb(v: Xyz) -> Tri {
    ret Tri { a: gtrans((3.240479f64 * v.x - 1.537150f64 * v.y - 0.498535f64 * v.z) / 100.0f64), b: gtrans((0.0f64 - 0.969256f64 * v.x + 1.875992f64 * v.y + 0.041556f64 * v.z) / 100.0f64), c: gtrans((0.055648f64 * v.x - 0.204043f64 * v.y + 1.057311f64 * v.z) / 100.0f64) }
}

// the packed hex of sRGB coordinates: truncation of 255 v + 0.5, then a clamp that is NA when fixup is off
fn srgb_hex(r: f64, g: f64, b: f64, fixup: bool) -> i64 {
    if !(r - r == 0.0f64 && g - g == 0.0f64 && b - b == 0.0f64) { ret 0i64 - 1i64 }
    var ir = i64(255.0f64 * r + 0.5f64)
    var ig = i64(255.0f64 * g + 0.5f64)
    var ib = i64(255.0f64 * b + 0.5f64)
    var fixed = false
    if ir < 0i64 { ir = 0i64
        fixed = true }
    if ir > 255i64 { ir = 255i64
        fixed = true }
    if ig < 0i64 { ig = 0i64
        fixed = true }
    if ig > 255i64 { ig = 255i64
        fixed = true }
    if ib < 0i64 { ib = 0i64
        fixed = true }
    if ib > 255i64 { ib = 255i64
        fixed = true }
    if fixed && !fixup { ret 0i64 - 1i64 }
    ret ir * 65536i64 + ig * 256i64 + ib
}

fn xyz_to_uv(x: f64, y: f64, z: f64) -> (f64, f64) {
    let t = x + y + z
    var xx = 0.0f64
    var yy = 0.0f64
    if t != 0.0f64 {
        xx = x / t
        yy = y / t
    }
    ret (2.0f64 * xx / (6.0f64 * yy - xx + 1.5f64), 4.5f64 * yy / (6.0f64 * yy - xx + 1.5f64))
}

fn wrap_deg(h0: f64) -> f64 {
    var h = h0
    while h > 360.0f64 { h -= 360.0f64 }
    while h < 0.0f64 { h += 360.0f64 }
    ret h
}

// as(sRGB(r, g, b), "polarLUV") coordinates (L, C, H)
fn srgb_to_polar_luv(r: f64, g: f64, b: f64) -> Tri { ret xyz_to_polar_luv(srgb_to_xyz(r, g, b)) }

fn xyz_to_polar_luv(v: Xyz) -> Tri {
    let (u, vv) = xyz_to_uv(v.x, v.y, v.z)
    let (un, vn) = xyz_to_uv(95.047f64, 100.0f64, 108.883f64)
    let y = v.y / 100.0f64
    var l = kappa() * y
    if y > epsilon() { l = 116.0f64 * math.pow[f64](y, 1.0f64 / 3.0f64) - 16.0f64 }
    let uu = 13.0f64 * l * (u - un)
    let vvv = 13.0f64 * l * (vv - vn)
    ret Tri { a: l, b: math.sqrt[f64](uu * uu + vvv * vvv), c: wrap_deg(rad2deg(math.atan2[f64](vvv, uu))) }
}

fn lab_f(t: f64) -> f64 {
    if t > epsilon() { ret math.pow[f64](t, 1.0f64 / 3.0f64) }
    ret (kappa() / 116.0f64) * t + 16.0f64 / 116.0f64
}

// as(sRGB(r, g, b), "polarLAB") coordinates (L, C, H)
fn srgb_to_polar_lab(r: f64, g: f64, b: f64) -> Tri {
    let v = srgb_to_xyz(r, g, b)
    let xr = v.x / 95.047f64
    let yr = v.y / 100.0f64
    let zr = v.z / 108.883f64
    var l = kappa() * yr
    if yr > epsilon() { l = 116.0f64 * math.pow[f64](yr, 1.0f64 / 3.0f64) - 16.0f64 }
    let xt = lab_f(xr)
    let yt = lab_f(yr)
    let zt = lab_f(zr)
    let a = 500.0f64 * (xt - yt)
    let bb = 200.0f64 * (yt - zt)
    ret Tri { a: l, b: math.sqrt[f64](a * a + bb * bb), c: wrap_deg(rad2deg(math.atan2[f64](bb, a))) }
}

// hex(polarLAB(L, C, H), fixup)
fn polar_lab_hex(l: f64, c: f64, h: f64, fixup: bool) -> i64 {
    let a = math.cos[f64](deg2rad(h)) * c
    let b = math.sin[f64](deg2rad(h)) * c
    let xn = 95.047f64
    let yn = 100.0f64
    let zn = 108.883f64
    var y = yn
    if l <= 0.0f64 { y = 0.0f64 } else if l <= 8.0f64 { y = l * yn / kappa() } else if l <= 100.0f64 {
        let q = (l + 16.0f64) / 116.0f64
        y = yn * (q * q * q)
    }
    var fy = 0.0f64
    if y <= epsilon() * yn { fy = (kappa() / 116.0f64) * y / yn + 16.0f64 / 116.0f64 } else { fy = math.pow[f64](y / yn, 1.0f64 / 3.0f64) }
    let fx = fy + a / 500.0f64
    var x = 0.0f64
    if fx * fx * fx <= epsilon() { x = xn * (fx - 16.0f64 / 116.0f64) / (kappa() / 116.0f64) } else { x = xn * (fx * fx * fx) }
    let fz = fy - b / 200.0f64
    var z = 0.0f64
    if fz * fz * fz <= epsilon() { z = zn * (fz - 16.0f64 / 116.0f64) / (kappa() / 116.0f64) } else { z = zn * (fz * fz * fz) }
    let s = xyz_to_srgb(Xyz { x: x, y: y, z: z })
    ret srgb_hex(s.a, s.b, s.c, fixup)
}

fn rgb_to_hls(r: f64, g: f64, b: f64) -> Tri {
    var mn = r
    if mn > g { mn = g }
    if mn > b { mn = b }
    var mx = r
    if mx < g { mx = g }
    if mx < b { mx = b }
    let l = (mx + mn) / 2.0f64
    var s = 0.0f64
    var h = 0.0f64
    if mx != mn {
        if l < 0.5f64 { s = (mx - mn) / (mx + mn) }
        if l >= 0.5f64 { s = (mx - mn) / (2.0f64 - mx - mn) }
        if r == mx { h = (g - b) / (mx - mn) }
        if g == mx { h = 2.0f64 + (b - r) / (mx - mn) }
        if b == mx { h = 4.0f64 + (r - g) / (mx - mn) }
        h = h * 60.0f64
        if h < 0.0f64 { h = h + 360.0f64 }
        if h > 360.0f64 { h = h - 360.0f64 }
    }
    ret Tri { a: h, b: l, c: s }
}

fn qtrans(q1: f64, q2: f64, hue0: f64) -> f64 {
    var hue = hue0
    if hue > 360.0f64 { hue = hue - 360.0f64 }
    if hue < 0.0f64 { hue = hue + 360.0f64 }
    if hue < 60.0f64 { ret q1 + (q2 - q1) * hue / 60.0f64 }
    if hue < 180.0f64 { ret q2 }
    if hue < 240.0f64 { ret q1 + (q2 - q1) * (240.0f64 - hue) / 60.0f64 }
    ret q1
}

fn hls_to_rgb(h: f64, l: f64, s: f64) -> Tri {
    var p2 = l + s - l * s
    if l <= 0.5f64 { p2 = l * (1.0f64 + s) }
    let p1 = 2.0f64 * l - p2
    if s == 0.0f64 { ret Tri { a: l, b: l, c: l } }
    ret Tri { a: qtrans(p1, p2, h + 120.0f64), b: qtrans(p1, p2, h), c: qtrans(p1, p2, h - 120.0f64) }
}

// the table of max_chroma, parsed once: index l * 361 + h
fn load_table(a: *mem.Arena) -> ([]f64, err) {
    let (t, e) = mem.alloc[f64](a, 361usize * 101usize)
    if e != ok { ret (t, e) }
    let text = mct.values()
    var at = 0usize
    var start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 32u8 {
            if i > start {
                let (v, pe) = str.parse_f64(text[start..i])
                if pe != ok { ret (t, pe) }
                t[at] = v
                at += 1usize
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret (t, ok)
}

// colorspace::max_chroma(h, l, floor)
fn max_chroma(t: []const f64, h0: f64, l0: f64, floor_it: bool) -> f64 {
    if h0 != h0 || l0 != l0 { ret nan() }
    var h = h0
    while h < 0.0f64 { h += 360.0f64 }
    while h >= 360.0f64 { h -= 360.0f64 }
    var l = l0
    if l > 100.0f64 { l = 100.0f64 }
    if l < 0.0f64 { l = 0.0f64 }
    let hmin = math.floor[f64](h + 1.0e-8f64)
    let hmax = math.ceil[f64](h + 1.0e-8f64)
    let lmin = math.floor[f64](l + 1.0e-8f64)
    let lmax = math.ceil[f64](l + 1.0e-8f64)
    if l <= 0.0f64 || l >= 100.0f64 { ret 0.0f64 }
    let a = t[usize(lmin) * 361usize + usize(hmin)]
    let b = t[usize(lmax) * 361usize + usize(hmin)]
    let c = t[usize(lmin) * 361usize + usize(hmax)]
    let d = t[usize(lmax) * 361usize + usize(hmax)]
    var v = (hmax - h) * (lmax - l) * a + (hmax - h) * (l - lmin) * b + (h - hmin) * (lmax - l) * c + (h - hmin) * (l - lmin) * d
    if l <= 0.0f64 || l >= 100.0f64 { v = 0.0f64 }
    if floor_it { v = math.floor[f64](v) }
    ret v
}

fn clip(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

fn new_l(lold: f64, amount: f64, relative: bool, scale: f64) -> f64 {
    // lightness in [0, scale]: relative moves toward scale (amount >= 0) or toward 0
    if relative {
        if amount >= 0.0f64 { ret scale - (scale - lold) * (1.0f64 - amount) }
        ret lold * (1.0f64 + amount)
    }
    ret lold + amount * scale
}

// lighten(col, amount, method, space, fixup): relative true or absolute; space 0 HCL, 1 HLS, 2 combined; darken(col, a) is lighten(col, -a)
fn lighten(t: []const f64, rgb: i64, amount: f64, relative: bool, space: u8, fixup: bool) -> i64 {
    if amount == 0.0f64 { ret rgb }
    let c = unpack(rgb)
    if space == 1u8 {
        let hls = rgb_to_hls(c.a, c.b, c.c)
        let l = clip(new_l(hls.b, amount, relative, 1.0f64), 0.0f64, 1.0f64)
        let s = hls_to_rgb(hls.a, l, hls.c)
        ret srgb_hex(s.a, s.b, s.c, fixup)
    }
    let pl = srgb_to_polar_luv(c.a, c.b, c.c)
    var l = clip(pl.a, 0.0f64, 100.0f64)
    l = clip(new_l(l, amount, relative, 100.0f64), 0.0f64, 100.0f64)
    var ch = pl.b
    if space == 0u8 {
        var mc = max_chroma(t, pl.c, l, true)
        var c0 = pl.b
        if c0 < 0.0f64 { c0 = 0.0f64 }
        if c0 < mc { mc = c0 }
        ch = mc
    } else {
        let hls = rgb_to_hls(c.a, c.b, c.c)
        let hl = clip(new_l(hls.b, amount, relative, 1.0f64), 0.0f64, 1.0f64)
        let s = hls_to_rgb(hls.a, hl, hls.c)
        // as(HLS, "RGB") takes the HLS_to_RGB values as linear RGB, with no gamma
        let hp = xyz_to_polar_luv(lin_to_xyz(s.a, s.b, s.c))
        let mc = max_chroma(t, pl.c, l, true)
        ch = hp.b
        if mc < ch { ch = mc }
    }
    ret pal.luv_hex(l, ch, pl.c, fixup)
}

// the APCA relative luminance of a packed colour
fn apca_luminance(rgb: i64) -> f64 {
    let c = unpack(rgb)
    var rl = math.pow[f64](c.a, 2.4f64) * 0.2126478133913640f64 + math.pow[f64](c.b, 2.4f64) * 0.7151791475336150f64 + math.pow[f64](c.c, 2.4f64) * 0.0721730390750208f64
    if rl <= 0.022f64 { rl = rl + math.pow[f64](0.022f64 - rl, 1.414f64) }
    ret rl
}

fn apca_one(txt: f64, bg: f64) -> f64 {
    var ratio = (math.pow[f64](bg, 0.56f64) - math.pow[f64](txt, 0.57f64)) * 1.14f64
    if ratio < 0.1f64 { ratio = 0.0f64 } else { ratio = ratio - 0.027f64 }
    if bg <= txt {
        ratio = (math.pow[f64](bg, 0.65f64) - math.pow[f64](txt, 0.62f64)) * 1.14f64
        if ratio > 0.0f64 - 0.1f64 { ratio = 0.0f64 } else { ratio = ratio + 0.027f64 }
    }
    if math.abs[f64](bg - txt) < 0.0005f64 { ratio = 0.0f64 }
    ret ratio * 100.0f64
}

// contrast_ratio(c1, c2, algorithm = "APCA"): normal (c1 text on c2) when reverse is false, else reverse
fn apca(c1: i64, c2: i64, reverse: bool) -> f64 {
    let l1 = apca_luminance(c1)
    let l2 = apca_luminance(c2)
    if reverse { ret apca_one(l2, l1) }
    ret apca_one(l1, l2)
}
