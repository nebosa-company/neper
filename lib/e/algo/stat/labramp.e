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

// farver's (ColorSpace library) sRGB to Lab and back, as scales::colour_ramp uses them
fn fv_lab(r8: f64, g8: f64, b8: f64, lab: []f64) {
    var r = r8 / 255.0f64
    var g = g8 / 255.0f64
    var b = b8 / 255.0f64
    if r > 0.04045f64 { r = math.pow[f64]((r + 0.055f64) / 1.055f64, 2.4f64) } else { r = r / 12.92f64 }
    if g > 0.04045f64 { g = math.pow[f64]((g + 0.055f64) / 1.055f64, 2.4f64) } else { g = g / 12.92f64 }
    if b > 0.04045f64 { b = math.pow[f64]((b + 0.055f64) / 1.055f64, 2.4f64) } else { b = b / 12.92f64 }
    r = r * 100.0f64
    g = g * 100.0f64
    b = b * 100.0f64
    let x = (r * 0.4124564f64 + g * 0.3575761f64 + b * 0.1804375f64) / 95.047f64
    let y = (r * 0.2126729f64 + g * 0.7151522f64 + b * 0.0721750f64) / 100.0f64
    let z = (r * 0.0193339f64 + g * 0.1191920f64 + b * 0.9503041f64) / 108.883f64
    var fx = 7.787f64 * x + 16.0f64 / 116.0f64
    if x > 0.008856f64 { fx = math.pow[f64](x, 1.0f64 / 3.0f64) }
    var fy = 7.787f64 * y + 16.0f64 / 116.0f64
    if y > 0.008856f64 { fy = math.pow[f64](y, 1.0f64 / 3.0f64) }
    var fz = 7.787f64 * z + 16.0f64 / 116.0f64
    if z > 0.008856f64 { fz = math.pow[f64](z, 1.0f64 / 3.0f64) }
    lab[0usize] = 116.0f64 * fy - 16.0f64
    lab[1usize] = 500.0f64 * (fx - fy)
    lab[2usize] = 200.0f64 * (fy - fz)
}

fn fv_srgb(l: f64, aa: f64, bb: f64, out: []f64) {
    let y0 = (l + 16.0f64) / 116.0f64
    let x0 = aa / 500.0f64 + y0
    let z0 = y0 - bb / 200.0f64
    let x3 = x0 * x0 * x0
    let y3 = y0 * y0 * y0
    let z3 = z0 * z0 * z0
    var x = (x0 - 16.0f64 / 116.0f64) / 7.787f64
    if x3 > 0.008856f64 { x = x3 }
    var y = (y0 - 16.0f64 / 116.0f64) / 7.787f64
    if y3 > 0.008856f64 { y = y3 }
    var z = (z0 - 16.0f64 / 116.0f64) / 7.787f64
    if z3 > 0.008856f64 { z = z3 }
    x = x * 95.047f64 / 100.0f64
    y = y * 100.0f64 / 100.0f64
    z = z * 108.883f64 / 100.0f64
    var r = x * 3.2404542f64 + y * (0.0f64 - 1.5371385f64) + z * (0.0f64 - 0.4985314f64)
    var g = x * (0.0f64 - 0.9692660f64) + y * 1.8760108f64 + z * 0.0415560f64
    var b = x * 0.0556434f64 + y * (0.0f64 - 0.2040259f64) + z * 1.0572252f64
    if r > 0.0031308f64 { r = 1.055f64 * math.pow[f64](r, 1.0f64 / 2.4f64) - 0.055f64 } else { r = 12.92f64 * r }
    if g > 0.0031308f64 { g = 1.055f64 * math.pow[f64](g, 1.0f64 / 2.4f64) - 0.055f64 } else { g = 12.92f64 * g }
    if b > 0.0031308f64 { b = 1.055f64 * math.pow[f64](b, 1.0f64 / 2.4f64) - 0.055f64 } else { b = 12.92f64 * b }
    out[0usize] = r * 255.0f64
    out[1usize] = g * 255.0f64
    out[2usize] = b * 255.0f64
}

fn clamp8(v: f64) -> u64 {
    var x = v
    if x < 0.0f64 { x = 0.0f64 }
    if x > 255.0f64 { x = 255.0f64 }
    ret u64(x + 0.5f64)
}

// scales::pal_gradient_n(colours)(x) for x in [0, 1]: linear interpolation of the colours in Lab at equal spacing, packed r * 65536 + g * 256 + b; 0 outside [0, 1] (NA)
fn gradient_colour(a: *mem.Arena, raw: []const u64, x: f64) -> u64 {
    let m = raw.len
    if x < 0.0f64 || x > 1.0f64 { ret 0u64 }
    let (lab, e1) = mem.alloc[f64](a, 3usize * m)
    if e1 != ok { ret 0u64 }
    var i = 0usize
    while i < m {
        let c = raw[i]
        fv_lab(f64((c / 65536u64) % 256u64), f64((c / 256u64) % 256u64), f64(c % 256u64), lab[3usize * i..3usize * i + 3usize])
        i += 1usize
    }
    // approxfun on x_in = seq(0, 1, length.out = m)
    var seg = 0usize
    while seg + 2usize < m && x > f64(seg + 1usize) / f64(m - 1usize) { seg += 1usize }
    let x0 = f64(seg) / f64(m - 1usize)
    let x1 = f64(seg + 1usize) / f64(m - 1usize)
    let t = (x - x0) / (x1 - x0)
    var o3: [3]f64 = zero
    var ch = 0usize
    while ch < 3usize {
        let v0 = lab[3usize * seg + ch]
        let v1 = lab[3usize * (seg + 1usize) + ch]
        o3[ch] = v0 + (v1 - v0) * t
        ch += 1usize
    }
    var rgb: [3]f64 = zero
    fv_srgb(o3[0usize], o3[1usize], o3[2usize], rgb[0usize..3usize])
    ret clamp8(rgb[0usize]) * 65536u64 + clamp8(rgb[1usize]) * 256u64 + clamp8(rgb[2usize])
}
