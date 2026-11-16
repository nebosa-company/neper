// The HCL palettes of R's colorspace: sequential_hcl, diverging_hcl and qualitative_hcl over the ten
// parameters of hcl_palettes() (h1, h2, c1, c2, l1, l2, p1, p2, cmax, fixup), and the conversion of a
// polar LUV colour to sRGB the way colorspace's C code does it (D65 white, the sRGB matrix to 6 digits,
// gamma 2.4, fixup clamps to the gamut, 255 * x + 0.5 truncated). A colour is packed as r * 65536 + g *
// 256 + b; -1 is NA (out of gamut without fixup).
//
// Not here: alpha, rev, palette-by-name lookup (the caller passes the parameters), contrast ratio and
// the colour-vision-deficiency simulations.

use e.gfx.cvd_table as tab
use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn gtrans(u: f64) -> f64 {
    if u > 0.00304f64 { ret 1.055f64 * math.pow[f64](u, 1.0f64 / 2.4f64) - 0.055f64 }
    ret 12.92f64 * u
}

fn unit(x: f64, fixup: bool) -> f64 {
    if fixup {
        if x < 0.0f64 { ret 0.0f64 }
        if x > 1.0f64 { ret 1.0f64 }
    }
    ret x
}

// polarLUV to the packed hex colour; -1 when a channel is outside [0, 1] and fixup is off
fn luv_hex(l: f64, c: f64, h: f64, fixup: bool) -> i64 {
    if l != l || c != c || h != h { ret 0i64 - 1i64 }
    let hr = h * 3.141592653589793f64 / 180.0f64
    let u0 = c * math.cos[f64](hr)
    let v0 = c * math.sin[f64](hr)
    var x = 0.0f64
    var y = 0.0f64
    var z = 0.0f64
    if !(l <= 0.0f64 && u0 == 0.0f64 && v0 == 0.0f64) {
        var t = l / 903.3f64
        if l > 7.999592f64 {
            let q = (l + 16.0f64) / 116.0f64
            t = q * q * q
        }
        y = 100.0f64 * t
        let u = u0 / (13.0f64 * l) + 0.1978398f64
        let v = v0 / (13.0f64 * l) + 0.4683363f64
        x = 9.0f64 * y * u / (4.0f64 * v)
        z = 0.0f64 - x / 3.0f64 - 5.0f64 * y + 3.0f64 * y / v
    }
    let r = gtrans((3.240479f64 * x - 1.537150f64 * y - 0.498535f64 * z) / 100.0f64)
    let g = gtrans((0.0f64 - 0.969256f64 * x + 1.875992f64 * y + 0.041556f64 * z) / 100.0f64)
    let b = gtrans((0.055648f64 * x - 0.204043f64 * y + 1.057311f64 * z) / 100.0f64)
    if !fixup {
        // colorspace refuses a channel whose rounded byte leaves 0 to 255
        let vr = 255.0f64 * r + 0.5f64
        let vg = 255.0f64 * g + 0.5f64
        let vb = 255.0f64 * b + 0.5f64
        if vr <= 0.0f64 - 1.0f64 || vr >= 256.0f64 || vg <= 0.0f64 - 1.0f64 || vg >= 256.0f64 || vb <= 0.0f64 - 1.0f64 || vb >= 256.0f64 { ret 0i64 - 1i64 }
    }
    let ri = i64(255.0f64 * unit(r, fixup) + 0.5f64)
    let gi = i64(255.0f64 * unit(g, fixup) + 0.5f64)
    let bi = i64(255.0f64 * unit(b, fixup) + 0.5f64)
    ret ri * 65536i64 + gi * 256i64 + bi
}

fn lintrj(i: f64, p1: f64, p2: f64) -> f64 { ret p2 - (p2 - p1) * i }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn tritrj(i: f64, j: f64, p1: f64, p2: f64, pm: f64) -> f64 {
    if i <= j { ret p2 - (p2 - pm) * i / j }
    ret pm - (pm - p1) * abs_of((i - j) / (1.0f64 - j))
}

// seqhcl for one position i in [0, 1]; NaN parameters stand for NA (cmax NaN: linear chroma)
fn seqhcl(i: f64, h1: f64, h2: f64, c1: f64, c2: f64, l1: f64, l2: f64, p1: f64, p2: f64, cmax: f64, fixup: bool) -> i64 {
    var j = 1.0f64 / (1.0f64 + abs_of(cmax - c1) / abs_of(cmax - c2))
    if j == j && (j <= 0.0f64 || j >= 1.0f64) { j = nan() }
    var c = 0.0f64
    if j != j {
        c = lintrj(math.pow[f64](i, p1), c1, c2)
    } else {
        c = tritrj(math.pow[f64](i, p1), j, c1, c2, cmax)
    }
    ret luv_hex(lintrj(math.pow[f64](i, p2), l1, l2), c, lintrj(i, h1, h2), fixup)
}

// sequential_hcl(n, palette parameters): the k-th (0-based) of n colours
fn sequential(n: usize, k: usize, h1: f64, h2: f64, c1: f64, c2: f64, l1: f64, l2: f64, p1: f64, p2: f64, cmax: f64, fixup: bool) -> i64 {
    var i = 0.0f64
    if n > 1usize { i = 1.0f64 - f64(k) / f64(n - 1usize) }
    var hh2 = h2
    if hh2 != hh2 { hh2 = h1 }
    var cc2 = c2
    if cc2 != cc2 { cc2 = 0.0f64 }
    var pp2 = p2
    if pp2 != pp2 { pp2 = p1 }
    if n == 1usize { i = 1.0f64 }
    ret seqhcl(i, h1, hh2, c1, cc2, l1, l2, p1, pp2, cmax, fixup)
}

// diverging_hcl: two sequential arms of one hue each, joined at the light middle
fn diverging(n: usize, k: usize, h1: f64, h2: f64, c1: f64, l1: f64, l2: f64, p1: f64, p2: f64, cmax: f64, fixup: bool) -> i64 {
    var pp2 = p2
    if pp2 != pp2 { pp2 = p1 }
    let n2 = (n + 1usize) / 2usize
    // positions of the first arm: seq(1, by = -2 / (n - 1), length.out = n2), floored at 0
    var by = 0.0f64
    if n > 1usize { by = 2.0f64 / f64(n - 1usize) }
    var left = true
    var idx = k
    if k >= n2 {
        left = false
        // the second arm is the first reversed, minus its middle when n is odd
        var top = n2
        if n % 2usize == 1usize { top = n2 - 1usize }
        idx = top - 1usize - (k - n2)
    }
    var i = 1.0f64 - f64(idx) * by
    if i < 0.0f64 { i = 0.0f64 }
    if n == 1usize { i = 0.0f64 }
    var h = h1
    if !left { h = h2 }
    ret seqhcl(i, h, h, c1, 0.0f64, l1, l2, p1, pp2, cmax, fixup)
}

// qualitative_hcl: constant L and C, hue spread from h1 to h2 (h2 NaN: h1 + 360 * (n - 1) / n)
fn qualitative(n: usize, k: usize, h1: f64, h2: f64, c1: f64, l1: f64, fixup: bool) -> i64 {
    var hh2 = h2
    if hh2 != hh2 { hh2 = h1 + 360.0f64 * f64(n - 1usize) / f64(n) }
    var h = h1
    if n > 1usize { h = h1 + f64(k) * (hh2 - h1) / f64(n - 1usize) }
    ret luv_hex(l1, c1, h, fixup)
}

// WCAG relative luminance of a packed colour, with colorspace's rounded coefficients.
fn lin(v: f64) -> f64 {
    if v <= 0.03928f64 { ret v / 12.92f64 }
    ret math.pow[f64]((v + 0.055f64) / 1.055f64, 2.4f64)
}

fn luminance(rgb: i64) -> f64 {
    let r = f64(rgb / 65536i64) / 255.0f64
    let g = f64((rgb / 256i64) % 256i64) / 255.0f64
    let b = f64(rgb % 256i64) / 255.0f64
    ret lin(r) * 0.2126f64 + lin(g) * 0.7152f64 + lin(b) * 0.0722f64
}

// contrast_ratio, WCAG: (L1 + 0.05) / (L2 + 0.05), inverted when below 1
fn contrast_ratio(c1: i64, c2: i64) -> f64 {
    var r = (luminance(c1) + 0.05f64) / (luminance(c2) + 0.05f64)
    if r < 1.0f64 { r = 1.0f64 / r }
    ret r
}

fn lin255(x: f64) -> f64 {
    let v = x / 255.0f64
    if v <= 0.03928f64 { ret v / 12.92f64 * 255.0f64 }
    ret math.pow[f64]((v + 0.055f64) / 1.055f64, 2.4f64) * 255.0f64
}

fn srgb255(y0: f64) -> f64 {
    let y = y0 / 255.0f64
    if y <= 0.03928f64 / 12.92f64 { ret 12.92f64 * y * 255.0f64 }
    ret (1.055f64 * math.pow[f64](y, 1.0f64 / 2.4f64) - 0.055f64) * 255.0f64
}

fn clamp255(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x > 255.0f64 { ret 255.0f64 }
    ret x
}

// R's round: halves go to the even neighbour
fn round_even(x: f64) -> f64 {
    let f = math.floor[f64](x)
    let d = x - f
    if d < 0.5f64 { ret f }
    if d > 0.5f64 { ret f + 1.0f64 }
    if (i64(f) % 2i64) == 0i64 { ret f }
    ret f + 1.0f64
}

// deutan (0), protan (1) or tritan (2) simulation at severity 0 to 1 of a packed sRGB colour, in
// linear RGB as simulate_cvd does by default.
fn cvd(kind: u8, severity: f64, rgb: i64) -> i64 {
    var t: [99]f64 = zero
    if kind == 0u8 { t = tab.deut_table() } else if kind == 1u8 { t = tab.prot_table() } else { t = tab.trit_table() }
    var m: [9]f64 = zero
    var k = 0usize
    if severity <= 0.0f64 {
        while k < 9usize {
            m[k] = t[k]
            k += 1usize
        }
    } else if severity >= 1.0f64 {
        while k < 9usize {
            m[k] = t[90usize + k]
            k += 1usize
        }
    } else {
        let s = 10.0f64 * severity
        let i1 = math.floor[f64](s)
        let i2 = math.ceil[f64](s)
        while k < 9usize {
            if i1 == i2 {
                m[k] = t[usize(i1) * 9usize + k]
            } else {
                m[k] = (i2 - s) * t[usize(i1) * 9usize + k] + (s - i1) * t[usize(i2) * 9usize + k]
            }
            k += 1usize
        }
    }
    let r = lin255(f64(rgb / 65536i64))
    let g = lin255(f64((rgb / 256i64) % 256i64))
    let b = lin255(f64(rgb % 256i64))
    let nr = srgb255(clamp255(m[0usize] * r + m[1usize] * g + m[2usize] * b))
    let ng = srgb255(clamp255(m[3usize] * r + m[4usize] * g + m[5usize] * b))
    let nb = srgb255(clamp255(m[6usize] * r + m[7usize] * g + m[8usize] * b))
    ret i64(round_even(nr)) * 65536i64 + i64(round_even(ng)) * 256i64 + i64(round_even(nb))
}
