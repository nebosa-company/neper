// R's colour palettes, string for string: viridisLite's eight maps (`viridis`, with begin, end,
// direction and alpha) and RColorBrewer's `brewer_pal`. The tables are generated from the R
// packages (palette_data.e).
//
// `viridis` is what viridisLite does: the 256 colours of the map, taken to 8 bits, go through
// grDevices::colorRamp(space = "Lab", interpolate = "spline") -- sRGB to CIE Lab with the D65
// white R's convertColor uses, one fmm spline per channel over knots i/255, back to sRGB with
// R's round(, 5) and clamp -- and `rgb()` writes each channel as the integer 255 x + 0.5.
// The answer is "#RRGGBBAA", upper case, alpha included even when it is 1, as R writes it.

use e.gfx.palette_data as data
use e.math
use e.mem
use e.str

error InvalidOption
error InvalidName
error InvalidRange

type Triple = struct { a: f64, b: f64, c: f64 }

fn hex_digit(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn hex_byte(s: str, at: usize) -> u8 { ret (hex_digit(s[at]) << 4u8) | hex_digit(s[at + 1usize]) }

// 'A'..'H' from a viridisLite option or palette name; anything else answers 'D', as R does
// after its warning.
fn option_letter(name: str) -> u8 {
    if name.len == 1usize {
        let c = name[0usize]
        if c >= 65u8 && c <= 72u8 { ret c }
    }
    if str.eq(name, "magma") { ret 65u8 }
    if str.eq(name, "inferno") { ret 66u8 }
    if str.eq(name, "plasma") { ret 67u8 }
    if str.eq(name, "cividis") { ret 69u8 }
    if str.eq(name, "rocket") { ret 70u8 }
    if str.eq(name, "mako") { ret 71u8 }
    if str.eq(name, "turbo") { ret 72u8 }
    ret 68u8
}

fn map_of(option: u8) -> str {
    if option == 65u8 { ret data.viridis_map_a() }
    if option == 66u8 { ret data.viridis_map_b() }
    if option == 67u8 { ret data.viridis_map_c() }
    if option == 69u8 { ret data.viridis_map_e() }
    if option == 70u8 { ret data.viridis_map_f() }
    if option == 71u8 { ret data.viridis_map_g() }
    if option == 72u8 { ret data.viridis_map_h() }
    ret data.viridis_map_d()
}

// --- Colour conversion as grDevices::convertColor does it (sRGB <-> Lab, D65).

type Space = struct { m: [9]f64, inv: [9]f64, white: [3]f64 }

fn inverse3(m: []const f64, out: []f64) {
    let a = m[0usize]
    let b = m[1usize]
    let c = m[2usize]
    let d = m[3usize]
    let e = m[4usize]
    let f = m[5usize]
    let g = m[6usize]
    let h = m[7usize]
    let i = m[8usize]
    let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    out[0usize] = (e * i - f * h) / det
    out[1usize] = (c * h - b * i) / det
    out[2usize] = (b * f - c * e) / det
    out[3usize] = (f * g - d * i) / det
    out[4usize] = (a * i - c * g) / det
    out[5usize] = (c * d - a * f) / det
    out[6usize] = (d * h - e * g) / det
    out[7usize] = (b * g - a * h) / det
    out[8usize] = (a * e - b * d) / det
}

fn make_space() -> Space {
    var s: Space = zero
    s.white[0usize] = 0.3137f64 / 0.3291f64
    s.white[1usize] = 1.0f64
    s.white[2usize] = (1.0f64 - (0.3137f64 + 0.3291f64)) / 0.3291f64
    var rgb: [9]f64 = zero
    rgb[0usize] = 0.64f64 / 0.33f64
    rgb[1usize] = 1.0f64
    rgb[2usize] = (1.0f64 - (0.64f64 + 0.33f64)) / 0.33f64
    rgb[3usize] = 0.3f64 / 0.6f64
    rgb[4usize] = 1.0f64
    rgb[5usize] = (1.0f64 - (0.3f64 + 0.6f64)) / 0.6f64
    rgb[6usize] = 0.15f64 / 0.06f64
    rgb[7usize] = 1.0f64
    rgb[8usize] = (1.0f64 - (0.15f64 + 0.06f64)) / 0.06f64
    var rinv: [9]f64 = zero
    inverse3(rgb[0usize..9usize], rinv[0usize..9usize])
    var r = 0usize
    while r < 3usize {
        var scale = 0.0f64
        var k = 0usize
        while k < 3usize {
            scale = scale + s.white[k] * rinv[3usize * k + r]
            k += 1usize
        }
        var c = 0usize
        while c < 3usize {
            s.m[3usize * r + c] = scale * rgb[3usize * r + c]
            c += 1usize
        }
        r += 1usize
    }
    inverse3(s.m[0usize..9usize], s.inv[0usize..9usize])
    ret s
}

fn pow3(x: f64) -> f64 { ret x * x * x }

// R's `%^%`: the power with the sign of the base.
fn signed_pow(x: f64, y: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - math.pow[f64](0.0f64 - x, y) }
    if x > 0.0f64 { ret math.pow[f64](x, y) }
    ret 0.0f64
}

fn to_lab(s: *const Space, r: f64, g: f64, b: f64) -> Triple {
    var lin: [3]f64 = zero
    lin[0usize] = r
    lin[1usize] = g
    lin[2usize] = b
    var i = 0usize
    while i < 3usize {
        let x = lin[i]
        if x < 0.04045f64 { lin[i] = x / 12.92f64 } else { lin[i] = math.pow[f64]((x + 0.055f64) / 1.055f64, 2.4f64) }
        i += 1usize
    }
    var xyz: [3]f64 = zero
    var c = 0usize
    while c < 3usize {
        xyz[c] = lin[0usize] * s.m[c] + lin[1usize] * s.m[3usize + c] + lin[2usize] * s.m[6usize + c]
        c += 1usize
    }
    let epsilon = 216.0f64 / 24389.0f64
    let kappa = 24389.0f64 / 27.0f64
    var f: [3]f64 = zero
    i = 0usize
    while i < 3usize {
        let xr = xyz[i] / s.white[i]
        if xr <= epsilon { f[i] = (kappa * xr + 16.0f64) / 116.0f64 } else { f[i] = math.pow[f64](xr, 1.0f64 / 3.0f64) }
        i += 1usize
    }
    ret Triple { a: 116.0f64 * f[1usize] - 16.0f64, b: 500.0f64 * (f[0usize] - f[1usize]), c: 200.0f64 * (f[1usize] - f[2usize]) }
}

// R's round(x, 5): the nearer of the two five-digit neighbours, ties to the even one.
fn round5(x0: f64) -> f64 {
    if x0 == 0.0f64 { ret x0 }
    var sgn = 1.0f64
    var x = x0
    if x < 0.0f64 {
        sgn = -1.0f64
        x = 0.0f64 - x
    }
    let x10 = x * 100000.0f64
    let i10 = math.floor[f64](x10)
    let xd = i10 / 100000.0f64
    let xu = math.ceil[f64](x10) / 100000.0f64
    let du = xu - x
    let dd = x - xd
    let odd = i10 - 2.0f64 * math.floor[f64](i10 / 2.0f64) == 1.0f64
    if du < dd || (odd && du == dd) { ret sgn * xu }
    ret sgn * xd
}

fn clip01(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x > 1.0f64 { ret 1.0f64 }
    ret x
}

fn from_lab(s: *const Space, l: f64, a: f64, b: f64) -> Triple {
    let epsilon = 216.0f64 / 24389.0f64
    let kappa = 24389.0f64 / 27.0f64
    var yr = 0.0f64
    if l < kappa * epsilon { yr = l / kappa } else { yr = pow3((l + 16.0f64) / 116.0f64) }
    var fy = 0.0f64
    if yr <= epsilon { fy = (kappa * yr + 16.0f64) / 116.0f64 } else { fy = (l + 16.0f64) / 116.0f64 }
    let fx = a / 500.0f64 + fy
    let fz = fy - b / 200.0f64
    let fz3 = pow3(fz)
    let fx3 = pow3(fx)
    var zr = fz3
    if fz3 <= epsilon { zr = (116.0f64 * fz - 16.0f64) / kappa }
    var xr = fx3
    if fx3 <= epsilon { xr = (116.0f64 * fx - 16.0f64) / kappa }
    var xyz: [3]f64 = zero
    xyz[0usize] = xr * s.white[0usize]
    xyz[1usize] = yr * s.white[1usize]
    xyz[2usize] = zr * s.white[2usize]
    var out: [3]f64 = zero
    var j = 0usize
    while j < 3usize {
        let lin = xyz[0usize] * s.inv[j] + xyz[1usize] * s.inv[3usize + j] + xyz[2usize] * s.inv[6usize + j]
        var v = 0.0f64
        if lin <= 0.0031308f64 { v = 12.92f64 * lin } else { v = 1.055f64 * signed_pow(lin, 1.0f64 / 2.4f64) - 0.055f64 }
        out[j] = clip01(round5(v))
        j += 1usize
    }
    ret Triple { a: out[0usize], b: out[1usize], c: out[2usize] }
}

// --- stats::splinefun(method = "fmm"), the coefficients and the evaluation.

fn fmm(n: usize, x: []const f64, y: []const f64, b: []f64, c: []f64, d: []f64) {
    let nm1 = n - 1usize
    d[0usize] = x[1usize] - x[0usize]
    c[1usize] = (y[1usize] - y[0usize]) / d[0usize]
    var i = 1usize
    while i < nm1 {
        d[i] = x[i + 1usize] - x[i]
        b[i] = 2.0f64 * (d[i - 1usize] + d[i])
        c[i + 1usize] = (y[i + 1usize] - y[i]) / d[i]
        c[i] = c[i + 1usize] - c[i]
        i += 1usize
    }
    b[0usize] = 0.0f64 - d[0usize]
    b[nm1] = 0.0f64 - d[nm1 - 1usize]
    c[0usize] = 0.0f64
    c[nm1] = 0.0f64
    if n > 3usize {
        c[0usize] = c[2usize] / (x[3usize] - x[1usize]) - c[1usize] / (x[2usize] - x[0usize])
        c[nm1] = c[nm1 - 1usize] / (x[nm1] - x[nm1 - 2usize]) - c[nm1 - 2usize] / (x[nm1 - 1usize] - x[nm1 - 3usize])
        c[0usize] = c[0usize] * d[0usize] * d[0usize] / (x[3usize] - x[0usize])
        c[nm1] = (0.0f64 - c[nm1]) * d[nm1 - 1usize] * d[nm1 - 1usize] / (x[nm1] - x[nm1 - 3usize])
    }
    i = 1usize
    while i <= nm1 {
        let t = d[i - 1usize] / b[i - 1usize]
        b[i] = b[i] - t * d[i - 1usize]
        c[i] = c[i] - t * c[i - 1usize]
        i += 1usize
    }
    c[nm1] = c[nm1] / b[nm1]
    i = nm1
    while i > 0usize {
        i -= 1usize
        c[i] = (c[i] - d[i] * c[i + 1usize]) / b[i]
    }
    b[nm1] = (y[nm1] - y[nm1 - 1usize]) / d[nm1 - 1usize] + d[nm1 - 1usize] * (c[nm1 - 1usize] + 2.0f64 * c[nm1])
    i = 0usize
    while i < nm1 {
        b[i] = (y[i + 1usize] - y[i]) / d[i] - d[i] * (c[i + 1usize] + 2.0f64 * c[i])
        d[i] = (c[i + 1usize] - c[i]) / d[i]
        c[i] = 3.0f64 * c[i]
        i += 1usize
    }
    c[nm1] = 3.0f64 * c[nm1]
    d[nm1] = d[nm1 - 1usize]
}

fn spline_at(n: usize, x: []const f64, y: []const f64, b: []const f64, c: []const f64, d: []const f64, ul: f64) -> f64 {
    var i = 0usize
    var j = n
    while true {
        if !(j > i + 1usize) { break }
        let k = (i + j) / 2usize
        if ul < x[k] { j = k } else { i = k }
    }
    let dx = ul - x[i]
    ret y[i] + dx * (b[i] + dx * (c[i] + dx * d[i]))
}

// seq(from, to, length.out = n)
fn seq_point(from: f64, to: f64, n: usize, k: usize) -> f64 {
    if n == 1usize { ret from }
    if k == 0usize { ret from }
    if k == n - 1usize { ret to }
    ret from + f64(k) * ((to - from) / f64(n - 1usize))
}

fn scale_color(x: f64) -> u8 { ret u8(255.0f64 * x + 0.5f64) }

fn put_hex(buf: []u8, at: usize, v: u8) {
    let hi = v >> 4u8
    let lo = v & 15u8
    var ch = 48u8 + hi
    if hi > 9u8 { ch = 55u8 + hi }
    var cl = 48u8 + lo
    if lo > 9u8 { cl = 55u8 + lo }
    buf[at] = ch
    buf[at + 1usize] = cl
}

type Chan = struct { y: []f64, b: []f64, c: []f64, d: []f64 }

fn make_chan(a: *mem.Arena) -> (Chan, err) {
    var ch: Chan = zero
    let (y, e1) = mem.alloc[f64](a, 256usize)
    if e1 != ok { ret (ch, e1) }
    let (b, e2) = mem.alloc[f64](a, 256usize)
    if e2 != ok { ret (ch, e2) }
    let (c, e3) = mem.alloc[f64](a, 256usize)
    if e3 != ok { ret (ch, e3) }
    let (d, e4) = mem.alloc[f64](a, 256usize)
    if e4 != ok { ret (ch, e4) }
    ch.y = y
    ch.b = b
    ch.c = c
    ch.d = d
    ret (ch, ok)
}

// viridisLite::viridis(n, alpha, begin, end, direction, option) with `option` a letter 'A'..'H'
// (see `option_letter`). Each answer is nine bytes, "#RRGGBBAA".
fn viridis(a: *mem.Arena, n: usize, alpha: f64, begin0: f64, end0: f64, direction: i64, option: u8) -> ([]str, err) {
    var none: []str = zero
    if begin0 < 0.0f64 || begin0 > 1.0f64 || end0 < 0.0f64 || end0 > 1.0f64 { ret (none, InvalidRange) }
    if direction != 1i64 && direction != -1i64 { ret (none, InvalidRange) }
    let (out, out_error) = mem.alloc[str](a, n)
    if out_error != ok { ret (none, out_error) }
    if n == 0usize { ret (out, ok) }
    var begin = begin0
    var end = end0
    if direction == -1i64 {
        begin = end0
        end = begin0
    }
    let table = map_of(option)
    let space = make_space()
    let (x, x_error) = mem.alloc[f64](a, 256usize)
    if x_error != ok { ret (none, x_error) }
    var k = 0usize
    while k < 256usize {
        x[k] = seq_point(0.0f64, 1.0f64, 256usize, k)
        k += 1usize
    }
    let (c0, e0) = make_chan(a)
    let (c1, e1) = make_chan(a)
    let (c2, e2) = make_chan(a)
    if e0 != ok { ret (none, e0) }
    if e1 != ok { ret (none, e1) }
    if e2 != ok { ret (none, e2) }
    k = 0usize
    while k < 256usize {
        let r = f64(hex_byte(table, 6usize * k)) / 255.0f64
        let g = f64(hex_byte(table, 6usize * k + 2usize)) / 255.0f64
        let b = f64(hex_byte(table, 6usize * k + 4usize)) / 255.0f64
        let lab = to_lab(&space, r, g, b)
        c0.y[k] = lab.a
        c1.y[k] = lab.b
        c2.y[k] = lab.c
        k += 1usize
    }
    fmm(256usize, x, c0.y, c0.b, c0.c, c0.d)
    fmm(256usize, x, c1.y, c1.b, c1.c, c1.d)
    fmm(256usize, x, c2.y, c2.b, c2.c, c2.d)
    var i = 0usize
    while i < n {
        let u = seq_point(begin, end, n, i)
        let l = spline_at(256usize, x, c0.y, c0.b, c0.c, c0.d, u)
        let aa = spline_at(256usize, x, c1.y, c1.b, c1.c, c1.d, u)
        let bb = spline_at(256usize, x, c2.y, c2.b, c2.c, c2.d, u)
        let rgb = from_lab(&space, l, aa, bb)
        let (text, text_error) = mem.alloc[u8](a, 9usize)
        if text_error != ok { ret (none, text_error) }
        text[0usize] = 35u8
        put_hex(text, 1usize, scale_color((rgb.a * 255.0f64) / 255.0f64))
        put_hex(text, 3usize, scale_color((rgb.b * 255.0f64) / 255.0f64))
        put_hex(text, 5usize, scale_color((rgb.c * 255.0f64) / 255.0f64))
        put_hex(text, 7usize, scale_color(alpha))
        out[i] = text
        i += 1usize
    }
    ret (out, ok)
}

// RColorBrewer::brewer.pal(n, name): "#RRGGBB" strings. n below 3 answers the 3-colour palette
// and n past the palette's maximum answers its largest, as R does after its warning.
fn brewer_pal(a: *mem.Arena, n: usize, name: str) -> ([]str, err) {
    var none: []str = zero
    let rows = data.brewer_rows()
    var at = 0usize
    while at < rows.len {
        var end = at
        while end < rows.len && rows[end] != 59u8 { end += 1usize }
        let row = rows[at..end]
        var bar = 0usize
        while bar < row.len && row[bar] != 124u8 { bar += 1usize }
        if str.eq(row[0usize..bar], name) {
            var maxc = 0usize
            var p = bar + 1usize
            while row[p] != 124u8 {
                maxc = maxc * 10usize + usize(row[p] - 48u8)
                p += 1usize
            }
            p += 1usize
            while row[p] != 124u8 { p += 1usize }
            p += 1usize
            var want = n
            if want < 3usize { want = 3usize }
            if want > maxc { want = maxc }
            var m = 3usize
            while m < want {
                p += 6usize * m + 1usize
                m += 1usize
            }
            let (out, out_error) = mem.alloc[str](a, want)
            if out_error != ok { ret (none, out_error) }
            var k = 0usize
            while k < want {
                let (text, text_error) = mem.alloc[u8](a, 7usize)
                if text_error != ok { ret (none, text_error) }
                text[0usize] = 35u8
                var d = 0usize
                while d < 6usize {
                    var c = row[p + 6usize * k + d]
                    if c >= 97u8 { c = c - 32u8 }
                    text[1usize + d] = c
                    d += 1usize
                }
                out[k] = text
                k += 1usize
            }
            ret (out, ok)
        }
        at = end + 1usize
    }
    ret (none, InvalidName)
}
