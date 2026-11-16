// ggsci continuous palettes: colorRamp(raw, space = "Lab", interpolate = "spline") as rgb_gsea, rgb_material and rgb_tw3 use it, with grDevices' sRGB, XYZ and Lab converters and
// the fmm spline of stats::splinefun.
//
// Not here: the raw colour tables of those palettes (the oracle passes them in) and pal_gradient.

use e.algo.stat.labramp_data as data
use e.algo.stat.splinepkg as sp
use e.math
use e.mem

// grDevices sRGB / XYZ / Lab converters as convertColor does them (D65 white from white.points, R's matrix for the sRGB primaries)
fn srgb_to_lab(r: f64, g: f64, b: f64, lab: []f64) {
    let m00 = 0.41682134188531705f64
    let m01 = 0.214923504409616606f64
    let m02 = 0.019538500400874251f64
    let m10 = 0.35657671707797467f64
    let m11 = 0.713153434155949340f64
    let m12 = 0.118858905692658334f64
    let m20 = 0.17980765358608541f64
    let m21 = 0.071923061434434166f64
    let m22 = 0.946986975553383292f64
    let rl = gamma_in(r)
    let gl = gamma_in(g)
    let bl = gamma_in(b)
    let x = rl * m00 + gl * m10 + bl * m20
    let y = rl * m01 + gl * m11 + bl * m21
    let z = rl * m02 + gl * m12 + bl * m22
    let wx = 0.31369999999999998f64
    let wy = 0.32910000000000000f64
    let w0 = wx / wy
    let w2 = (1.0f64 - wx - wy) / wy
    let eps = 216.0f64 / 24389.0f64
    let kap = 24389.0f64 / 27.0f64
    let xr = x / w0
    let yr = y
    let zr = z / w2
    var fx = math.pow[f64](xr, 1.0f64 / 3.0f64)
    if xr <= eps { fx = (kap * xr + 16.0f64) / 116.0f64 }
    var fy = math.pow[f64](yr, 1.0f64 / 3.0f64)
    if yr <= eps { fy = (kap * yr + 16.0f64) / 116.0f64 }
    var fz = math.pow[f64](zr, 1.0f64 / 3.0f64)
    if zr <= eps { fz = (kap * zr + 16.0f64) / 116.0f64 }
    lab[0usize] = 116.0f64 * fy - 16.0f64
    lab[1usize] = 500.0f64 * (fx - fy)
    lab[2usize] = 200.0f64 * (fy - fz)
}

fn gamma_in(x: f64) -> f64 {
    if x < 0.04045f64 { ret x / 12.92f64 }
    ret math.pow[f64]((x + 0.055f64) / 1.055f64, 2.4f64)
}

fn gamma_out(x: f64) -> f64 {
    if x <= 0.0031308f64 { ret 12.92f64 * x }
    ret 1.055f64 * math.pow[f64](x, 1.0f64 / 2.4f64) - 0.055f64
}

fn cube(x: f64) -> f64 { ret x * x * x }

// Lab to clipped sRGB in [0, 1] (round to 5 digits first, as convertColor's trim)
fn lab_to_srgb(l: f64, aa: f64, bb: f64, out: []f64) {
    let eps = 216.0f64 / 24389.0f64
    let kap = 24389.0f64 / 27.0f64
    let wx = 0.31369999999999998f64
    let wy = 0.32910000000000000f64
    let w0 = wx / wy
    let w2 = (1.0f64 - wx - wy) / wy
    var yr = cube((l + 16.0f64) / 116.0f64)
    if l < kap * eps { yr = l / kap }
    var fy = (l + 16.0f64) / 116.0f64
    if yr <= eps { fy = (kap * yr + 16.0f64) / 116.0f64 }
    let fx = aa / 500.0f64 + fy
    let fz = fy - bb / 200.0f64
    let fz3 = cube(fz)
    let fx3 = cube(fx)
    var zr = fz3
    if fz3 <= eps { zr = (116.0f64 * fz - 16.0f64) / kap }
    var xr = fx3
    if fx3 <= eps { xr = (116.0f64 * fx - 16.0f64) / kap }
    let x = xr * w0
    let y = yr
    let z = zr * w2
    // linear rgb = xyz %*% solve(M)
    let m00 = 0.41682134188531705f64
    let m01 = 0.214923504409616606f64
    let m02 = 0.019538500400874251f64
    let m10 = 0.35657671707797467f64
    let m11 = 0.713153434155949340f64
    let m12 = 0.118858905692658334f64
    let m20 = 0.17980765358608541f64
    let m21 = 0.071923061434434166f64
    let m22 = 0.946986975553383292f64
    let det = m00 * (m11 * m22 - m12 * m21) - m01 * (m10 * m22 - m12 * m20) + m02 * (m10 * m21 - m11 * m20)
    let i00 = (m11 * m22 - m12 * m21) / det
    let i01 = (m02 * m21 - m01 * m22) / det
    let i02 = (m01 * m12 - m02 * m11) / det
    let i10 = (m12 * m20 - m10 * m22) / det
    let i11 = (m00 * m22 - m02 * m20) / det
    let i12 = (m02 * m10 - m00 * m12) / det
    let i20 = (m10 * m21 - m11 * m20) / det
    let i21 = (m01 * m20 - m00 * m21) / det
    let i22 = (m00 * m11 - m01 * m10) / det
    let rl = x * i00 + y * i10 + z * i20
    let gl = x * i01 + y * i11 + z * i21
    let bl = x * i02 + y * i12 + z * i22
    out[0usize] = trim5(gamma_out(rl))
    out[1usize] = trim5(gamma_out(gl))
    out[2usize] = trim5(gamma_out(bl))
}

fn trim5(v: f64) -> f64 {
    var r = math.floor[f64](v * 100000.0f64 + 0.5f64) / 100000.0f64
    if r < 0.0f64 { r = 0.0f64 }
    if r > 1.0f64 { r = 1.0f64 }
    ret r
}

// ggsci's continuous palettes: rgb_gsea / rgb_material / rgb_tw3, the k-th of n colours of colorRamp(raw, space = "Lab", interpolate = "spline") with the raw colours packed r * 65536 + g * 256 + b, alpha as rgb(alpha = alpha * 255, maxColorValue = 255); packed r * 2^24 + g * 2^16 + b * 2^8 + alpha
fn lab_ramp(a: *mem.Arena, raw: []const u64, n: usize, k: usize, alpha: f64) -> u64 {
    let m = raw.len
    let (lab, e1) = mem.alloc[f64](a, 3usize * m)
    let (xs, e2) = mem.alloc[f64](a, m)
    let (ys, e3) = mem.alloc[f64](a, m)
    let (bs, e4) = mem.alloc[f64](a, m)
    let (cs, e5) = mem.alloc[f64](a, m)
    let (ds, e6) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0u64 }
    var i = 0usize
    while i < m {
        let c = raw[i]
        let r = f64((c / 65536u64) % 256u64) / 255.0f64
        let g = f64((c / 256u64) % 256u64) / 255.0f64
        let b = f64(c % 256u64) / 255.0f64
        srgb_to_lab(r, g, b, lab[3usize * i..3usize * i + 3usize])
        xs[i] = f64(i) / f64(m - 1usize)
        i += 1usize
    }
    xs[m - 1usize] = 1.0f64
    var u = 1.0f64
    if n > 1usize { u = f64(k) / f64(n - 1usize) }
    if u > 1.0f64 { u = 1.0f64 }
    var ch = 0usize
    var out3: [3]f64 = zero
    while ch < 3usize {
        i = 0usize
        while i < m {
            ys[i] = lab[3usize * i + ch]
            i += 1usize
        }
        sp.fmm_spline(m, xs, ys, bs, cs, ds)
        out3[ch] = sp.spline_eval(m, xs, ys, bs, cs, ds, u)
        ch += 1usize
    }
    var rgb: [3]f64 = zero
    lab_to_srgb(out3[0usize], out3[1usize], out3[2usize], rgb[0usize..3usize])
    let r8 = u64(rgb[0usize] * 255.0f64)
    let g8 = u64(rgb[1usize] * 255.0f64)
    let b8 = u64(rgb[2usize] * 255.0f64)
    let a8 = u64(alpha * 255.0f64)
    ret r8 * 16777216u64 + g8 * 65536u64 + b8 * 256u64 + a8
}

fn hex_val(c: u8) -> u64 {
    if c >= 97u8 { ret u64(c - 87u8) }
    if c >= 65u8 { ret u64(c - 55u8) }
    ret u64(c - 48u8)
}

// the number of palettes in the generated table
fn row_count() -> usize {
    let t = data.rows()
    var c = 0usize
    var i = 0usize
    while i < t.len {
        if t[i] == 10u8 { c += 1usize }
        i += 1usize
    }
    ret c
}

// the raw colours of palette row idx (0-based; gsea:default, then material, then tw3 in ggsci order) into out, packed r * 65536 + g * 256 + b; returns how many
fn raw_row(idx: usize, out: []u64) -> usize {
    let t = data.rows()
    var at = 0usize
    var r = 0usize
    while r < idx && at < t.len {
        while at < t.len && t[at] != 10u8 { at += 1usize }
        at += 1usize
        r += 1usize
    }
    while at < t.len && t[at] != 124u8 { at += 1usize }
    at += 1usize
    var m = 0usize
    while at < t.len && t[at] != 10u8 {
        // "#RRGGBB" then a comma
        var v = 0u64
        var d = 1usize
        while d <= 6usize {
            v = v * 16u64 + hex_val(t[at + d])
            d += 1usize
        }
        out[m] = v
        m += 1usize
        at += 7usize
        if at < t.len && t[at] == 44u8 { at += 1usize }
    }
    ret m
}

// the k-th of n colours of palette row idx, as lab_ramp
fn palette_colour(a: *mem.Arena, idx: usize, n: usize, k: usize, alpha: f64) -> u64 {
    let (raw, e) = mem.alloc[u64](a, 32usize)
    if e != ok { ret 0u64 }
    let m = raw_row(idx, raw)
    ret lab_ramp(a, raw[0usize..m], n, k, alpha)
}
