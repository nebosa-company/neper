// Colors and brushes with nothing that rasterises. A `Color` is linear-light RGBA in
// `0..1`, straight alpha unless it came through `premultiply`; `srgb8` applies the
// sRGB transfer (the 0.04045 knee and the 2.4 power) to the three channels and scales
// alpha, so an 8-bit sRGB pixel becomes the linear value compositing wants. `validate`
// is the one check a brush gets: every channel in `0..1`, gradient stops borrowed, at
// least one, offsets in `0..1` and non-decreasing, a radial radius non-negative.
//
// `gradient` evaluates a brush at a point with a `Spread` past the ends; `composite`
// is the Porter-Duff table over premultiplied colours; `fill_rule` decides a winding
// count. `fill_path` rasterises a flat path (`geometry.flatten` output) into a caller
// coverage mask of `width * height` values in `0..1`: four sub-scanlines per row, each
// with exact horizontal coverage of its spans. `glyph_subpixel` does the same at three
// times the horizontal resolution and runs FreeType's 5-tap FIR over the subpixels;
// `glyph_sdf` turns a coverage mask into a signed distance, positive inside.

use e.gfx.geometry
use e.math

type Color = struct { red: f32, green: f32, blue: f32, alpha: f32 }
type Blend = enum u8 { SourceOver, Source, DestinationOver, Multiply, Screen, Overlay, Darken, Lighten }
type StrokeCap = enum u8 { Butt, Round, Square }
type StrokeJoin = enum u8 { Miter, Round, Bevel }
type Stroke = struct { width: f32, cap: StrokeCap, join: StrokeJoin, miter_limit: f32 }
type Stop = struct { offset: f32, color: Color }
type Brush = union enum u8 { Solid: Color, Linear: LinearGradient, Radial: RadialGradient }
type LinearGradient = struct { start: geometry.Point, end: geometry.Point, stops: []const Stop }
type RadialGradient = struct { center: geometry.Point, radius: f32, stops: []const Stop }
type Spread = enum u8 { Pad, Repeat, Reflect }
type Operator = enum u8 { Clear, Src, Dst, SrcOver, DstOver, SrcIn, DstIn, SrcOut, DstOut, SrcAtop, DstAtop, Xor, Plus }
type FillRule = enum u8 { NonZero, EvenOdd }
error Invalid
error TooLarge

fn rgba(red: f32, green: f32, blue: f32, alpha: f32) -> Color {
    ret Color { red: red, green: green, blue: blue, alpha: alpha }
}

// The sRGB electro-optical transfer: linear below the knee, a 2.4 power above it.
fn srgb_to_linear(c: f32) -> f32 {
    if c <= 0.04045 { ret c / 12.92 }
    ret pow24((c + 0.055) / 1.055)
}

fn linear_of(byte: u8) -> f32 {
    ret srgb_to_linear(f32(byte) / 255.0)
}

// The inverse transfer, clamped to `0..1`.
fn linear_to_srgb(linear: f32) -> f32 {
    if !(linear > 0.0) { ret 0.0 }
    if linear >= 1.0 { ret 1.0 }
    if linear <= 0.0031308 { ret linear * 12.92 }
    ret 1.055 * root24(linear) - 0.055
}

// x^(1/2.4) as the inverse of `pow24`: y with y^12 = x^5, by Newton from 1, which
// walks down to the root and never through a vanishing derivative.
fn root24(x: f32) -> f32 {
    if x <= 0.0 { ret 0.0 }
    if x >= 1.0 { ret 1.0 }
    let x5 = x * x * x * x * x
    var y: f32 = 1.0
    var i = 0usize
    while i < 60usize {
        let y11 = y * y * y * y * y * y * y * y * y * y * y
        y = y - (y11 * y - x5) / (12.0 * y11)
        i += 1usize
    }
    ret y
}

// x^2.4 as x^2 * x^0.4, the fractional power by Newton on y^5 = x^2 from 1, which
// walks down to the root -- plain arithmetic, no transcendental library behind a colour.
fn pow24(x: f32) -> f32 {
    if x <= 0.0 { ret 0.0 }
    let square = x * x
    var y: f32 = 1.0
    var i = 0usize
    while i < 40usize {
        let y4 = y * y * y * y
        y = y - (y4 * y - square) / (5.0 * y4)
        i += 1usize
    }
    ret square * y
}

fn srgb8(red: u8, green: u8, blue: u8, alpha: u8) -> Color {
    ret Color { red: linear_of(red), green: linear_of(green), blue: linear_of(blue), alpha: f32(alpha) / 255.0 }
}

fn premultiply(color: Color) -> Color {
    ret Color { red: color.red * color.alpha, green: color.green * color.alpha, blue: color.blue * color.alpha, alpha: color.alpha }
}

fn unit(v: f32) -> bool {
    ret v >= 0.0 && v <= 1.0
}

fn color_ok(c: Color) -> bool {
    ret unit(c.red) && unit(c.green) && unit(c.blue) && unit(c.alpha)
}

fn stops_ok(stops: []const Stop) -> bool {
    if stops.len == 0usize { ret false }
    var previous: f32 = 0.0
    var i = 0usize
    while i < stops.len {
        if !unit(stops[i].offset) || stops[i].offset < previous || !color_ok(stops[i].color) { ret false }
        previous = stops[i].offset
        i += 1usize
    }
    ret true
}

fn validate(brush: *const Brush) -> err {
    switch *brush {
    case .Solid as color:
        if !color_ok(color) { ret Invalid }
    case .Linear as linear:
        if !stops_ok(linear.stops) { ret Invalid }
        if linear.start.x != linear.start.x || linear.end.x != linear.end.x { ret Invalid }
    case .Radial as radial:
        if !stops_ok(radial.stops) || radial.radius < 0.0 { ret Invalid }
    }
    ret ok
}

fn mix(a: Color, b: Color, t: f32) -> Color {
    ret Color { red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t, blue: a.blue + (b.blue - a.blue) * t, alpha: a.alpha + (b.alpha - a.alpha) * t }
}

fn spread_of(t: f32, spread: Spread) -> f32 {
    if spread == .Pad {
        if t < 0.0 { ret 0.0 }
        if t > 1.0 { ret 1.0 }
        ret t
    }
    if spread == .Repeat { ret t - math.floor[f32](t) }
    let period = t - 2.0 * math.floor[f32](t / 2.0)
    if period > 1.0 { ret 2.0 - period }
    ret period
}

// The colour at `t` along validated stops: the first before the first offset, the
// last after the last, a linear blend between neighbours and a hard edge where two
// stops share an offset.
fn stops_at(stops: []const Stop, t: f32) -> Color {
    var i = 0usize
    while i < stops.len && stops[i].offset < t { i += 1usize }
    if i == 0usize { ret stops[0usize].color }
    if i == stops.len { ret stops[stops.len - 1usize].color }
    let span = stops[i].offset - stops[i - 1usize].offset
    if span <= 0.0 { ret stops[i].color }
    ret mix(stops[i - 1usize].color, stops[i].color, (t - stops[i - 1usize].offset) / span)
}

// The brush's colour at `p`: a solid is itself; a linear gradient projects `p` onto
// `start -> end` (a zero-length one answers its first stop); a radial takes the
// distance from the centre over the radius.
fn gradient(brush: *const Brush, spread: Spread, p: geometry.Point) -> Color {
    switch *brush {
    case .Solid as color:
        ret color
    case .Linear as linear:
        let dx = linear.end.x - linear.start.x
        let dy = linear.end.y - linear.start.y
        let len2 = dx * dx + dy * dy
        if len2 <= 0.0 { ret linear.stops[0usize].color }
        let t = ((p.x - linear.start.x) * dx + (p.y - linear.start.y) * dy) / len2
        ret stops_at(linear.stops, spread_of(t, spread))
    case .Radial as radial:
        if radial.radius <= 0.0 { ret radial.stops[0usize].color }
        let dx = p.x - radial.center.x
        let dy = p.y - radial.center.y
        ret stops_at(radial.stops, spread_of(math.sqrt[f32](dx * dx + dy * dy) / radial.radius, spread))
    }
    ret zero
}

// Porter-Duff over premultiplied colours: `src * fa + dst * fb` with the table's
// factors; `Plus` clamps every channel to one.
fn composite(op: Operator, src: Color, dst: Color) -> Color {
    var fa: f32 = 0.0
    var fb: f32 = 0.0
    let ia = 1.0 - src.alpha
    let ib = 1.0 - dst.alpha
    if op == .Src { fa = 1.0 }
    if op == .Dst { fb = 1.0 }
    if op == .SrcOver || op == .Plus { fa = 1.0 }
    if op == .SrcOver || op == .DstOut || op == .SrcAtop || op == .Xor { fb = ia }
    if op == .DstOver || op == .SrcOut || op == .DstAtop || op == .Xor { fa = ib }
    if op == .DstOver || op == .Plus { fb = 1.0 }
    if op == .SrcIn || op == .SrcAtop { fa = dst.alpha }
    if op == .DstIn || op == .DstAtop { fb = src.alpha }
    var out = Color { red: src.red * fa + dst.red * fb, green: src.green * fa + dst.green * fb, blue: src.blue * fa + dst.blue * fb, alpha: src.alpha * fa + dst.alpha * fb }
    if op == .Plus {
        if out.red > 1.0 { out.red = 1.0 }
        if out.green > 1.0 { out.green = 1.0 }
        if out.blue > 1.0 { out.blue = 1.0 }
        if out.alpha > 1.0 { out.alpha = 1.0 }
    }
    ret out
}

fn fill_rule(rule: FillRule, winding: i32) -> bool {
    if rule == .NonZero { ret winding != 0i32 }
    ret (winding & 1i32) != 0i32
}

// The crossings of the flat path with the horizontal line at `y`, each an x and a
// direction, unsorted; every contour is closed, an open one implicitly. An edge
// takes the half-open interval from its lower to its upper y.
fn crossings(path: geometry.Path, y: f32, scale_x: f32, xs: []f32, ds: []i32) -> (usize, err) {
    var n = 0usize
    var current: geometry.Point = zero
    var first: geometry.Point = zero
    var pending = false
    var pi = 0usize
    var vi = 0usize
    while vi <= path.verbs.len {
        var verb: geometry.PathVerb = .Close
        if vi < path.verbs.len { verb = path.verbs[vi] }
        if verb == .Quad || verb == .Cubic { ret (0usize, Invalid) }
        var to: geometry.Point = first
        var edge = false
        if verb == .Move {
            if pending && (current.x != first.x || current.y != first.y) { edge = true }
            pending = true
        } else if verb == .Line {
            to = path.points[pi]
            edge = true
        } else {
            if pending { edge = true }
            pending = false
        }
        if edge && current.y != to.y {
            var lo = current.y
            var hi = to.y
            var dir = 1i32
            if lo > hi {
                lo = to.y
                hi = current.y
                dir = -1i32
            }
            if y >= lo && y < hi {
                if n == xs.len { ret (0usize, TooLarge) }
                xs[n] = scale_x * (current.x + (y - current.y) * (to.x - current.x) / (to.y - current.y))
                ds[n] = dir
                n += 1usize
            }
        }
        if verb == .Move {
            current = path.points[pi]
            first = current
            pi += 1usize
        } else if verb == .Line {
            current = to
            pi += 1usize
        } else {
            current = first
        }
        vi += 1usize
    }
    ret (n, ok)
}

// ponytail: every edge is tested per sub-scanline and at most 256 crossings are kept
// per line; an active-edge table and caller scratch when paths outgrow glyphs.
fn rasterize(path: geometry.Path, rule: FillRule, scale_x: f32, width: usize, height: usize, coverage: []f32) -> err {
    if coverage.len < width * height { ret Invalid }
    var i = 0usize
    while i < width * height {
        coverage[i] = 0.0
        i += 1usize
    }
    var xs: [256]f32 = zero
    var ds: [256]i32 = zero
    var row = 0usize
    while row < height {
        var sub = 0usize
        while sub < 4usize {
            let y = f32(row) + (f32(sub) + 0.5) / 4.0
            let (n, e) = crossings(path, y, scale_x, xs[..], ds[..])
            if e != ok { ret e }
            var a = 1usize
            while a < n {
                let x = xs[a]
                let d = ds[a]
                var b = a
                while b > 0usize && xs[b - 1usize] > x {
                    xs[b] = xs[b - 1usize]
                    ds[b] = ds[b - 1usize]
                    b -= 1usize
                }
                xs[b] = x
                ds[b] = d
                a += 1usize
            }
            var winding = 0i32
            a = 0usize
            while a + 1usize < n {
                winding += ds[a]
                if fill_rule(rule, winding) {
                    var left = xs[a]
                    var right = xs[a + 1usize]
                    if left < 0.0 { left = 0.0 }
                    if right > f32(width) { right = f32(width) }
                    if right > left {
                        var px = usize(i64(left))
                        while f32(px) < right && px < width {
                            var lo = f32(px)
                            var hi = lo + 1.0
                            if left > lo { lo = left }
                            if right < hi { hi = right }
                            coverage[row * width + px] += (hi - lo) * 0.25
                            px += 1usize
                        }
                    }
                }
                a += 1usize
            }
            sub += 1usize
        }
        row += 1usize
    }
    i = 0usize
    while i < width * height {
        if coverage[i] > 1.0 { coverage[i] = 1.0 }
        i += 1usize
    }
    ret ok
}

fn fill_path(path: geometry.Path, rule: FillRule, width: usize, height: usize, coverage: []f32) -> err {
    ret rasterize(path, rule, 1.0, width, height, coverage)
}

// Per-channel coverage, `3 * width * height` values, from a rasterisation at three
// subpixels per pixel filtered by [8, 77, 86, 77, 8] / 256; `wide` is scratch of the
// same length.
fn glyph_subpixel(path: geometry.Path, rule: FillRule, width: usize, height: usize, wide: []f32, out: []f32) -> err {
    let stride = 3usize * width
    if out.len < stride * height { ret Invalid }
    let e = rasterize(path, rule, 3.0, stride, height, wide)
    if e != ok { ret e }
    let taps = [5]f32{ 8.0 / 256.0, 77.0 / 256.0, 86.0 / 256.0, 77.0 / 256.0, 8.0 / 256.0 }
    var row = 0usize
    while row < height {
        var i = 0usize
        while i < stride {
            var sum: f32 = 0.0
            var k = 0usize
            while k < 5usize {
                let j = i + k
                if j >= 2usize && j - 2usize < stride { sum += taps[k] * wide[row * stride + j - 2usize] }
                k += 1usize
            }
            out[row * stride + i] = sum
            i += 1usize
        }
        row += 1usize
    }
    ret ok
}

// The signed distance, in pixels between centres, from each pixel to the nearest one
// across the 0.5 coverage threshold: positive inside, negative outside, and
// `width + height` when nothing lies across.
// ponytail: brute force, O(pixels^2); the 8SSEDT when glyphs pass 64x64.
fn glyph_sdf(coverage: []const f32, width: usize, height: usize, out: []f32) -> err {
    if coverage.len < width * height || out.len < width * height { ret Invalid }
    var y = 0usize
    while y < height {
        var x = 0usize
        while x < width {
            let inside = coverage[y * width + x] >= 0.5
            var best = f32(width + height)
            best = best * best
            var v = 0usize
            while v < height {
                var u = 0usize
                while u < width {
                    if (coverage[v * width + u] >= 0.5) != inside {
                        let dx = f32(u) - f32(x)
                        let dy = f32(v) - f32(y)
                        let d2 = dx * dx + dy * dy
                        if d2 < best { best = d2 }
                    }
                    u += 1usize
                }
                v += 1usize
            }
            var d = math.sqrt[f32](best)
            if !inside { d = 0.0 - d }
            out[y * width + x] = d
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}
