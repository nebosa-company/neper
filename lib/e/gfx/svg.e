// `e.gfx.svg` (D2198): a subset of SVG 1.1 drawn into an `e.gfx.scene` builder. The text of an
// `.svg` file goes in; display-list commands come out, scaled to fit a destination rectangle
// (the viewBox is meet-fitted and centred, the default `preserveAspectRatio`). The renderer is
// OS-independent -- it only builds scene commands -- so one icon file draws identically on every
// target `e.gfx.scene` renders to.
//
// Elements: `svg`, `g`, `rect` (with `rx`/`ry`), `circle`, `ellipse`, `line`, `polyline`,
// `polygon`, and `path` (`M L H V C S Q T A Z`, absolute and relative, implicit repeats, compact
// arc flags). Properties, from an attribute or a `style="a:b;c:d"` declaration list and
// inherited down groups: `fill`, `stroke`, `stroke-width`, `stroke-linecap`, `stroke-linejoin`,
// `stroke-miterlimit`, `opacity`, `fill-opacity`, `stroke-opacity`, `color`. Colours are `#rgb`,
// `#rrggbb`, `#rrggbbaa`, `rgb(r,g,b)`, the names `none`, `transparent`, `black`, `white`, `red`,
// `green`, `blue`, `yellow`, `gray`, `grey` and `currentColor` (the caller's colour, so one
// monochrome icon takes the theme's ink). `transform` takes `matrix`, `translate`, `scale`,
// `rotate` (with optional centre), `skewX` and `skewY`.
//
// Not drawn: gradients, patterns, clip paths, masks, filters, text, `use`, markers, `<style>`
// sheets, percentages and units other than px (a `url(...)` paint draws nothing). Their elements
// are skipped whole. Group `opacity` multiplies each shape's own alpha rather than compositing
// the group as a layer, and every fill is non-zero.
//
// ponytail: an overlapping group at partial opacity darkens where its shapes overlap; wrap in an
// OpacityLayer when that matters. A path draws into arena storage sized from its data and never
// frees it -- icons are small and the arena is the caller's.

use e.math
use e.mem
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene

error BadSvg
error TooComplex

const MAX_DEPTH: usize = 16usize

type Style = struct { fill: paint.Color, fill_on: bool, stroke: paint.Color, stroke_on: bool, stroke_width: f32, cap: paint.StrokeCap, join: paint.StrokeJoin, miter: f32, opacity: f32, fill_opacity: f32, stroke_opacity: f32, current: paint.Color }
type Frame = struct { style: Style, ctm: geometry.Transform }

fn is_space(c: u8) -> bool {
    ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8
}

fn is_digit(c: u8) -> bool {
    ret c >= 48u8 && c <= 57u8
}

fn is_alpha(c: u8) -> bool {
    ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8)
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn begins(text: str, at: usize, word: str) -> bool {
    if at + word.len > text.len { ret false }
    ret same(text[at..at + word.len], word)
}

// The first index at or after `from` where `word` begins, or text.len.
fn find(text: str, from: usize, word: str) -> usize {
    var i = from
    while i + word.len <= text.len {
        if begins(text, i, word) { ret i }
        i += 1usize
    }
    ret text.len
}

fn trim(value: str) -> str {
    var start = 0usize
    var end = value.len
    while start < end && is_space(value[start]) { start += 1usize }
    while end > start && is_space(value[end - 1usize]) { end -= 1usize }
    ret value[start..end]
}

// The '>' that ends the tag opening at `from`, skipping any inside quotes.
fn tag_end(text: str, from: usize) -> usize {
    var quote = 0u8
    var i = from
    while i < text.len {
        let c = text[i]
        if quote != 0u8 {
            if c == quote { quote = 0u8 }
        } else if c == 34u8 || c == 39u8 {
            quote = c
        } else if c == 62u8 {
            ret i
        }
        i += 1usize
    }
    ret text.len
}

// The value of attribute `name` in the text of one tag (between the brackets).
fn attr(tag: str, name: str) -> (str, bool) {
    var i = 0usize
    while i + name.len < tag.len {
        let boundary = i == 0usize || is_space(tag[i - 1usize])
        if boundary && begins(tag, i, name) {
            var j = i + name.len
            while j < tag.len && is_space(tag[j]) { j += 1usize }
            if j < tag.len && tag[j] == 61u8 {
                j += 1usize
                while j < tag.len && is_space(tag[j]) { j += 1usize }
                if j < tag.len && (tag[j] == 34u8 || tag[j] == 39u8) {
                    let quote = tag[j]
                    let first = j + 1usize
                    var last = first
                    while last < tag.len && tag[last] != quote { last += 1usize }
                    ret (tag[first..last], true)
                }
            }
        }
        i += 1usize
    }
    ret ("", false)
}

// A property: from the `style` declaration list first, then the attribute of the same name.
fn prop(tag: str, name: str) -> (str, bool) {
    let (style, has_style) = attr(tag, "style")
    if has_style {
        var at = 0usize
        while at < style.len {
            var end = at
            while end < style.len && style[end] != 59u8 { end += 1usize }
            let decl = style[at..end]
            var colon = 0usize
            while colon < decl.len && decl[colon] != 58u8 { colon += 1usize }
            if colon < decl.len && same(trim(decl[0usize..colon]), name) { ret (trim(decl[colon + 1usize..decl.len]), true) }
            at = end + 1usize
        }
    }
    let (value, found) = attr(tag, name)
    ret (value, found)
}

fn skip_sep(text: str, at: *usize) {
    while *at < text.len && (is_space(text[*at]) || text[*at] == 44u8) { *at += 1usize }
}

// The next number at `at` (an SVG number: sign, digits, fraction, exponent), advancing past it.
fn read_number(text: str, at: *usize, out: *f32) -> bool {
    skip_sep(text, at)
    var i = *at
    if i >= text.len { ret false }
    var sign = 1.0f64
    if text[i] == 45u8 {
        sign = 0.0f64 - 1.0f64
        i += 1usize
    } else if text[i] == 43u8 {
        i += 1usize
    }
    var mantissa = 0.0f64
    var digits = 0usize
    var fraction = 0i64
    while i < text.len && is_digit(text[i]) {
        mantissa = mantissa * 10.0f64 + f64(text[i] - 48u8)
        digits += 1usize
        i += 1usize
    }
    if i < text.len && text[i] == 46u8 {
        i += 1usize
        while i < text.len && is_digit(text[i]) {
            mantissa = mantissa * 10.0f64 + f64(text[i] - 48u8)
            digits += 1usize
            fraction += 1i64
            i += 1usize
        }
    }
    if digits == 0usize { ret false }
    var exponent = 0i64
    if i < text.len && (text[i] == 101u8 || text[i] == 69u8) {
        var j = i + 1usize
        var exp_sign = 1i64
        if j < text.len && text[j] == 45u8 {
            exp_sign = 0i64 - 1i64
            j += 1usize
        } else if j < text.len && text[j] == 43u8 {
            j += 1usize
        }
        if j < text.len && is_digit(text[j]) {
            var value = 0i64
            while j < text.len && is_digit(text[j]) {
                value = value * 10i64 + i64(text[j] - 48u8)
                j += 1usize
            }
            exponent = exp_sign * value
            i = j
        }
    }
    var power = exponent - fraction
    var scale = 1.0f64
    while power > 0i64 {
        scale = scale * 10.0f64
        power -= 1i64
    }
    while power < 0i64 {
        scale = scale / 10.0f64
        power += 1i64
    }
    *out = f32(sign * mantissa * scale)
    *at = i
    ret true
}

// A whole attribute value as one number, ignoring a trailing `px`.
fn number_of(value: str, fallback: f32) -> f32 {
    var at = 0usize
    var out = fallback
    if read_number(value, &at, &out) { ret out }
    ret fallback
}

fn hex_value(c: u8) -> usize {
    if c >= 48u8 && c <= 57u8 { ret usize(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret usize(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret usize(c - 55u8) }
    ret 16usize
}

// The renderer writes colour values straight into the target (no transfer curve), so a byte is the
// display value over 255 -- not converted to linear, which would darken every mid tone.
fn byte_color(r: usize, g: usize, b: usize, a: usize) -> paint.Color {
    ret paint.Color { red: f32(r) / 255.0, green: f32(g) / 255.0, blue: f32(b) / 255.0, alpha: f32(a) / 255.0 }
}

// A paint: 0 none, 1 a colour, 2 a reference this subset does not draw.
fn parse_paint(value: str, current: paint.Color) -> (paint.Color, u8) {
    let v = trim(value)
    let none = paint.rgba(0.0, 0.0, 0.0, 0.0)
    if v.len == 0usize || same(v, "none") || same(v, "transparent") { ret (none, 0u8) }
    if begins(v, 0usize, "url(") { ret (none, 2u8) }
    if same(v, "currentColor") { ret (current, 1u8) }
    if same(v, "black") { ret (byte_color(0usize, 0usize, 0usize, 255usize), 1u8) }
    if same(v, "white") { ret (byte_color(255usize, 255usize, 255usize, 255usize), 1u8) }
    if same(v, "red") { ret (byte_color(255usize, 0usize, 0usize, 255usize), 1u8) }
    if same(v, "green") { ret (byte_color(0usize, 128usize, 0usize, 255usize), 1u8) }
    if same(v, "blue") { ret (byte_color(0usize, 0usize, 255usize, 255usize), 1u8) }
    if same(v, "yellow") { ret (byte_color(255usize, 255usize, 0usize, 255usize), 1u8) }
    if same(v, "gray") || same(v, "grey") { ret (byte_color(128usize, 128usize, 128usize, 255usize), 1u8) }
    if v[0usize] == 35u8 {
        var d: [8]usize = zero
        var n = 0usize
        while n < 8usize && 1usize + n < v.len {
            let h = hex_value(v[1usize + n])
            if h == 16usize { ret (none, 0u8) }
            d[n] = h
            n += 1usize
        }
        if n == 3usize || n == 4usize {
            var alpha = 255usize
            if n == 4usize { alpha = d[3usize] * 17usize }
            ret (byte_color(d[0usize] * 17usize, d[1usize] * 17usize, d[2usize] * 17usize, alpha), 1u8)
        }
        if n == 6usize || n == 8usize {
            var alpha = 255usize
            if n == 8usize { alpha = d[6usize] * 16usize + d[7usize] }
            ret (byte_color(d[0usize] * 16usize + d[1usize], d[2usize] * 16usize + d[3usize], d[4usize] * 16usize + d[5usize], alpha), 1u8)
        }
        ret (none, 0u8)
    }
    if begins(v, 0usize, "rgb(") {
        var at = 4usize
        var r = 0.0f32
        var g = 0.0f32
        var b = 0.0f32
        if read_number(v, &at, &r) && read_number(v, &at, &g) && read_number(v, &at, &b) {
            ret (byte_color(clamp_byte(r), clamp_byte(g), clamp_byte(b), 255usize), 1u8)
        }
    }
    ret (none, 0u8)
}

fn clamp_byte(v: f32) -> usize {
    if v <= 0.0 { ret 0usize }
    if v >= 255.0 { ret 255usize }
    ret usize(v + 0.5)
}

fn unit_value(v: f32) -> f32 {
    if v < 0.0 { ret 0.0 }
    if v > 1.0 { ret 1.0 }
    ret v
}

// `base` with the tag's own presentation properties applied.
fn apply_style(tag: str, base: Style) -> Style {
    var s = base
    let (color, has_color) = prop(tag, "color")
    if has_color {
        let (c, kind) = parse_paint(color, s.current)
        if kind == 1u8 { s.current = c }
    }
    let (fill, has_fill) = prop(tag, "fill")
    if has_fill {
        let (c, kind) = parse_paint(fill, s.current)
        s.fill = c
        s.fill_on = kind == 1u8
    }
    let (stroke, has_stroke) = prop(tag, "stroke")
    if has_stroke {
        let (c, kind) = parse_paint(stroke, s.current)
        s.stroke = c
        s.stroke_on = kind == 1u8
    }
    let (width, has_width) = prop(tag, "stroke-width")
    if has_width { s.stroke_width = number_of(width, s.stroke_width) }
    let (cap, has_cap) = prop(tag, "stroke-linecap")
    if has_cap {
        if same(trim(cap), "round") { s.cap = paint.StrokeCap.Round } else if same(trim(cap), "square") { s.cap = paint.StrokeCap.Square } else { s.cap = paint.StrokeCap.Butt }
    }
    let (join, has_join) = prop(tag, "stroke-linejoin")
    if has_join {
        if same(trim(join), "round") { s.join = paint.StrokeJoin.Round } else if same(trim(join), "bevel") { s.join = paint.StrokeJoin.Bevel } else { s.join = paint.StrokeJoin.Miter }
    }
    let (miter, has_miter) = prop(tag, "stroke-miterlimit")
    if has_miter { s.miter = number_of(miter, s.miter) }
    let (opacity, has_opacity) = prop(tag, "opacity")
    if has_opacity { s.opacity = s.opacity * unit_value(number_of(opacity, 1.0)) }
    let (fill_opacity, has_fill_opacity) = prop(tag, "fill-opacity")
    if has_fill_opacity { s.fill_opacity = unit_value(number_of(fill_opacity, 1.0)) }
    let (stroke_opacity, has_stroke_opacity) = prop(tag, "stroke-opacity")
    if has_stroke_opacity { s.stroke_opacity = unit_value(number_of(stroke_opacity, 1.0)) }
    ret s
}

fn tangent(radians: f32) -> f32 {
    ret math.sin[f32](radians) / math.cos[f32](radians)
}

fn degrees(value: f32) -> f32 {
    ret value * 0.017453292
}

// A `transform` attribute: the list's matrices multiplied left to right.
fn parse_transform(value: str) -> geometry.Transform {
    var t = geometry.transform_identity()
    var at = 0usize
    while at < value.len {
        while at < value.len && (is_space(value[at]) || value[at] == 44u8) { at += 1usize }
        let name_start = at
        while at < value.len && is_alpha(value[at]) { at += 1usize }
        let name = value[name_start..at]
        while at < value.len && value[at] != 40u8 { at += 1usize }
        if at >= value.len { ret t }
        at += 1usize
        var n: [6]f32 = zero
        var count = 0usize
        var more = true
        while more && count < 6usize {
            var got = 0.0f32
            if read_number(value, &at, &got) {
                n[count] = got
                count += 1usize
            } else {
                more = false
            }
        }
        while at < value.len && value[at] != 41u8 { at += 1usize }
        at += 1usize
        var m = geometry.transform_identity()
        if same(name, "matrix") && count == 6usize {
            m = geometry.Transform { m00: n[0usize], m01: n[2usize], m02: n[4usize], m10: n[1usize], m11: n[3usize], m12: n[5usize] }
        } else if same(name, "translate") && count >= 1usize {
            var ty = 0.0f32
            if count >= 2usize { ty = n[1usize] }
            m = geometry.transform_translate(n[0usize], ty)
        } else if same(name, "scale") && count >= 1usize {
            var sy = n[0usize]
            if count >= 2usize { sy = n[1usize] }
            m = geometry.transform_scale(n[0usize], sy)
        } else if same(name, "rotate") && count >= 1usize {
            m = geometry.transform_rotate(degrees(n[0usize]))
            if count >= 3usize {
                let back = geometry.transform_translate(0.0 - n[1usize], 0.0 - n[2usize])
                m = geometry.transform_multiply(geometry.transform_translate(n[1usize], n[2usize]), geometry.transform_multiply(m, back))
            }
        } else if same(name, "skewX") && count >= 1usize {
            m = geometry.Transform { m00: 1.0, m01: tangent(degrees(n[0usize])), m02: 0.0, m10: 0.0, m11: 1.0, m12: 0.0 }
        } else if same(name, "skewY") && count >= 1usize {
            m = geometry.Transform { m00: 1.0, m01: 0.0, m02: 0.0, m10: tangent(degrees(n[0usize])), m11: 1.0, m12: 0.0 }
        }
        t = geometry.transform_multiply(t, m)
    }
    ret t
}

fn pt(x: f32, y: f32) -> geometry.Point {
    ret geometry.Point { x: x, y: y }
}

fn absolute(v: f32) -> f32 {
    if v < 0.0 { ret 0.0 - v }
    ret v
}

// An elliptical arc from (x0, y0) to (x, y) as at most four cubics (SVG 1.1 appendix F.6).
fn arc_to(pb: *geometry.PathBuilder, x0: f32, y0: f32, rx_in: f32, ry_in: f32, rotation: f32, large: bool, sweep: bool, x: f32, y: f32) -> err {
    var rx = absolute(rx_in)
    var ry = absolute(ry_in)
    if (x0 == x && y0 == y) { ret ok }
    if rx == 0.0 || ry == 0.0 { ret geometry.line_to(pb, pt(x, y)) }
    let phi = degrees(rotation)
    let cos_phi = math.cos[f32](phi)
    let sin_phi = math.sin[f32](phi)
    let dx = (x0 - x) / 2.0
    let dy = (y0 - y) / 2.0
    let x1 = cos_phi * dx + sin_phi * dy
    let y1 = 0.0 - sin_phi * dx + cos_phi * dy
    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1.0 {
        let root = math.sqrt[f32](lambda)
        rx = rx * root
        ry = ry * root
    }
    let rx2 = rx * rx
    let ry2 = ry * ry
    var numerator = rx2 * ry2 - rx2 * y1 * y1 - ry2 * x1 * x1
    if numerator < 0.0 { numerator = 0.0 }
    var coefficient = math.sqrt[f32](numerator / (rx2 * y1 * y1 + ry2 * x1 * x1))
    if large == sweep { coefficient = 0.0 - coefficient }
    let cx1 = coefficient * rx * y1 / ry
    let cy1 = 0.0 - coefficient * ry * x1 / rx
    let cx = cos_phi * cx1 - sin_phi * cy1 + (x0 + x) / 2.0
    let cy = sin_phi * cx1 + cos_phi * cy1 + (y0 + y) / 2.0
    let theta1 = math.atan2[f32]((y1 - cy1) / ry, (x1 - cx1) / rx)
    let theta2 = math.atan2[f32]((0.0 - y1 - cy1) / ry, (0.0 - x1 - cx1) / rx)
    var delta = theta2 - theta1
    let pi: f32 = 3.1415927
    if sweep && delta < 0.0 { delta = delta + 2.0 * pi }
    if !sweep && delta > 0.0 { delta = delta - 2.0 * pi }
    var segments = usize(absolute(delta) / (pi / 2.0) + 0.999)
    if segments < 1usize { segments = 1usize }
    if segments > 4usize { segments = 4usize }
    let step = delta / f32(segments)
    let alpha = 4.0 / 3.0 * tangent(step / 4.0)
    var angle = theta1
    var i = 0usize
    while i < segments {
        let c1 = math.cos[f32](angle)
        let s1 = math.sin[f32](angle)
        let c2 = math.cos[f32](angle + step)
        let s2 = math.sin[f32](angle + step)
        let e1x = c1 - alpha * s1
        let e1y = s1 + alpha * c1
        let e2x = c2 + alpha * s2
        let e2y = s2 - alpha * c2
        let p1 = pt(cx + rx * cos_phi * e1x - ry * sin_phi * e1y, cy + rx * sin_phi * e1x + ry * cos_phi * e1y)
        let p2 = pt(cx + rx * cos_phi * e2x - ry * sin_phi * e2y, cy + rx * sin_phi * e2x + ry * cos_phi * e2y)
        var end = pt(cx + rx * cos_phi * c2 - ry * sin_phi * s2, cy + rx * sin_phi * c2 + ry * cos_phi * s2)
        if i + 1usize == segments { end = pt(x, y) }
        try geometry.cubic_to(pb, p1, p2, end)
        angle = angle + step
        i += 1usize
    }
    ret ok
}

fn read_flag(d: str, at: *usize, out: *bool) -> bool {
    skip_sep(d, at)
    if *at >= d.len { ret false }
    let c = d[*at]
    if c != 48u8 && c != 49u8 { ret false }
    *out = c == 49u8
    *at += 1usize
    ret true
}

// The data of a `path`, built into `pb`.
fn build_path(pb: *geometry.PathBuilder, d: str) -> err {
    var at = 0usize
    var cmd = 0u8
    var x = 0.0f32
    var y = 0.0f32
    var sx = 0.0f32
    var sy = 0.0f32
    var cubic_x = 0.0f32
    var cubic_y = 0.0f32
    var quad_x = 0.0f32
    var quad_y = 0.0f32
    var prev = 0u8
    while true {
        skip_sep(d, &at)
        if at >= d.len { break }
        let c = d[at]
        if is_alpha(c) {
            cmd = c
            at += 1usize
        } else if cmd == 0u8 {
            ret BadSvg
        }
        let rel = cmd >= 97u8
        var upper = cmd
        if rel { upper = cmd - 32u8 }
        var a0 = 0.0f32
        var a1 = 0.0f32
        var a2 = 0.0f32
        var a3 = 0.0f32
        var a4 = 0.0f32
        var a5 = 0.0f32
        var ox = 0.0f32
        var oy = 0.0f32
        if rel {
            ox = x
            oy = y
        }
        if upper == 90u8 {
            try geometry.close_path(pb)
            x = sx
            y = sy
            prev = 90u8
            cmd = 0u8
        } else if upper == 77u8 {
            if !read_number(d, &at, &a0) || !read_number(d, &at, &a1) { ret BadSvg }
            x = ox + a0
            y = oy + a1
            sx = x
            sy = y
            try geometry.move_to(pb, pt(x, y))
            if rel { cmd = 108u8 } else { cmd = 76u8 }
            prev = 77u8
        } else if upper == 76u8 {
            if !read_number(d, &at, &a0) || !read_number(d, &at, &a1) { ret BadSvg }
            x = ox + a0
            y = oy + a1
            try geometry.line_to(pb, pt(x, y))
            prev = 76u8
        } else if upper == 72u8 {
            if !read_number(d, &at, &a0) { ret BadSvg }
            x = ox + a0
            try geometry.line_to(pb, pt(x, y))
            prev = 76u8
        } else if upper == 86u8 {
            if !read_number(d, &at, &a0) { ret BadSvg }
            y = oy + a0
            try geometry.line_to(pb, pt(x, y))
            prev = 76u8
        } else if upper == 67u8 {
            if !read_number(d, &at, &a0) || !read_number(d, &at, &a1) || !read_number(d, &at, &a2) || !read_number(d, &at, &a3) || !read_number(d, &at, &a4) || !read_number(d, &at, &a5) { ret BadSvg }
            try geometry.cubic_to(pb, pt(ox + a0, oy + a1), pt(ox + a2, oy + a3), pt(ox + a4, oy + a5))
            cubic_x = ox + a2
            cubic_y = oy + a3
            x = ox + a4
            y = oy + a5
            prev = 67u8
        } else if upper == 83u8 {
            if !read_number(d, &at, &a0) || !read_number(d, &at, &a1) || !read_number(d, &at, &a2) || !read_number(d, &at, &a3) { ret BadSvg }
            var fx = x
            var fy = y
            if prev == 67u8 {
                fx = 2.0 * x - cubic_x
                fy = 2.0 * y - cubic_y
            }
            try geometry.cubic_to(pb, pt(fx, fy), pt(ox + a0, oy + a1), pt(ox + a2, oy + a3))
            cubic_x = ox + a0
            cubic_y = oy + a1
            x = ox + a2
            y = oy + a3
            prev = 67u8
        } else if upper == 81u8 {
            if !read_number(d, &at, &a0) || !read_number(d, &at, &a1) || !read_number(d, &at, &a2) || !read_number(d, &at, &a3) { ret BadSvg }
            try geometry.quad_to(pb, pt(ox + a0, oy + a1), pt(ox + a2, oy + a3))
            quad_x = ox + a0
            quad_y = oy + a1
            x = ox + a2
            y = oy + a3
            prev = 81u8
        } else if upper == 84u8 {
            if !read_number(d, &at, &a0) || !read_number(d, &at, &a1) { ret BadSvg }
            var qx = x
            var qy = y
            if prev == 81u8 {
                qx = 2.0 * x - quad_x
                qy = 2.0 * y - quad_y
            }
            try geometry.quad_to(pb, pt(qx, qy), pt(ox + a0, oy + a1))
            quad_x = qx
            quad_y = qy
            x = ox + a0
            y = oy + a1
            prev = 81u8
        } else if upper == 65u8 {
            var large = false
            var sweep = false
            if !read_number(d, &at, &a0) || !read_number(d, &at, &a1) || !read_number(d, &at, &a2) { ret BadSvg }
            if !read_flag(d, &at, &large) || !read_flag(d, &at, &sweep) { ret BadSvg }
            if !read_number(d, &at, &a3) || !read_number(d, &at, &a4) { ret BadSvg }
            try arc_to(pb, x, y, a0, a1, a2, large, sweep, ox + a3, oy + a4)
            x = ox + a3
            y = oy + a4
            prev = 65u8
        } else {
            ret BadSvg
        }
    }
    ret ok
}

fn new_path(a: *mem.Arena, verbs: usize, points: usize) -> (geometry.PathBuilder, err) {
    let (builder, builder_error) = geometry.path_builder(a, verbs, points)
    ret (builder, builder_error)
}

fn ellipse_path(a: *mem.Arena, cx: f32, cy: f32, rx: f32, ry: f32) -> (geometry.Path, err) {
    let (pb, pb_error) = new_path(a, 8usize, 16usize)
    if pb_error != ok { ret (zero, pb_error) }
    var b = pb
    let k: f32 = 0.5522847
    try geometry.move_to(&b, pt(cx + rx, cy))
    try geometry.cubic_to(&b, pt(cx + rx, cy + ry * k), pt(cx + rx * k, cy + ry), pt(cx, cy + ry))
    try geometry.cubic_to(&b, pt(cx - rx * k, cy + ry), pt(cx - rx, cy + ry * k), pt(cx - rx, cy))
    try geometry.cubic_to(&b, pt(cx - rx, cy - ry * k), pt(cx - rx * k, cy - ry), pt(cx, cy - ry))
    try geometry.cubic_to(&b, pt(cx + rx * k, cy - ry), pt(cx + rx, cy - ry * k), pt(cx + rx, cy))
    try geometry.close_path(&b)
    ret (geometry.finish(&b), ok)
}

fn rect_path(a: *mem.Arena, x: f32, y: f32, w: f32, h: f32, rx_in: f32, ry_in: f32) -> (geometry.Path, err) {
    let (pb, pb_error) = new_path(a, 10usize, 28usize)
    if pb_error != ok { ret (zero, pb_error) }
    var b = pb
    var rx = rx_in
    var ry = ry_in
    if rx > w / 2.0 { rx = w / 2.0 }
    if ry > h / 2.0 { ry = h / 2.0 }
    if rx <= 0.0 || ry <= 0.0 {
        try geometry.move_to(&b, pt(x, y))
        try geometry.line_to(&b, pt(x + w, y))
        try geometry.line_to(&b, pt(x + w, y + h))
        try geometry.line_to(&b, pt(x, y + h))
        try geometry.close_path(&b)
        ret (geometry.finish(&b), ok)
    }
    let k: f32 = 0.5522847
    try geometry.move_to(&b, pt(x + rx, y))
    try geometry.line_to(&b, pt(x + w - rx, y))
    try geometry.cubic_to(&b, pt(x + w - rx + rx * k, y), pt(x + w, y + ry - ry * k), pt(x + w, y + ry))
    try geometry.line_to(&b, pt(x + w, y + h - ry))
    try geometry.cubic_to(&b, pt(x + w, y + h - ry + ry * k), pt(x + w - rx + rx * k, y + h), pt(x + w - rx, y + h))
    try geometry.line_to(&b, pt(x + rx, y + h))
    try geometry.cubic_to(&b, pt(x + rx - rx * k, y + h), pt(x, y + h - ry + ry * k), pt(x, y + h - ry))
    try geometry.line_to(&b, pt(x, y + ry))
    try geometry.cubic_to(&b, pt(x, y + ry - ry * k), pt(x + rx - rx * k, y), pt(x + rx, y))
    try geometry.close_path(&b)
    ret (geometry.finish(&b), ok)
}

fn points_path(a: *mem.Arena, list: str, closed: bool) -> (geometry.Path, err) {
    let (pb, pb_error) = new_path(a, list.len / 2usize + 4usize, list.len / 2usize + 4usize)
    if pb_error != ok { ret (zero, pb_error) }
    var b = pb
    var at = 0usize
    var first = true
    var px = 0.0f32
    var py = 0.0f32
    while read_number(list, &at, &px) {
        if !read_number(list, &at, &py) { ret (zero, BadSvg) }
        if first {
            try geometry.move_to(&b, pt(px, py))
            first = false
        } else {
            try geometry.line_to(&b, pt(px, py))
        }
    }
    if first { ret (zero, BadSvg) }
    if closed { try geometry.close_path(&b) }
    ret (geometry.finish(&b), ok)
}

fn color_with(c: paint.Color, alpha: f32) -> paint.Color {
    ret paint.Color { red: c.red, green: c.green, blue: c.blue, alpha: c.alpha * alpha }
}

fn emit(b: *scene.Builder, frame: Frame, path: geometry.Path) -> err {
    let s = frame.style
    var fill_alpha = s.opacity * s.fill_opacity
    var stroke_alpha = s.opacity * s.stroke_opacity
    let save: scene.Command = .Save
    try scene.push(b, save)
    try scene.push(b, scene.Command { Transform: frame.ctm })
    if s.fill_on && fill_alpha > 0.0 {
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: color_with(s.fill, fill_alpha) } } })
    }
    if s.stroke_on && s.stroke_width > 0.0 && stroke_alpha > 0.0 {
        try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: path, brush: paint.Brush { Solid: color_with(s.stroke, stroke_alpha) }, stroke: paint.Stroke { width: s.stroke_width, cap: s.cap, join: s.join, miter_limit: s.miter } } })
    }
    let restore: scene.Command = .Restore
    try scene.push(b, restore)
    ret ok
}

fn length_of(tag: str, name: str) -> f32 {
    let (value, found) = attr(tag, name)
    if !found { ret 0.0 }
    ret number_of(value, 0.0)
}

fn child_of(tag: str, parent: Frame) -> Frame {
    let (value, found) = attr(tag, "transform")
    var ctm = parent.ctm
    if found { ctm = geometry.transform_multiply(parent.ctm, parse_transform(value)) }
    ret Frame { style: apply_style(tag, parent.style), ctm: ctm }
}

// The tag's name: the run of characters up to a space, a slash or the end.
fn name_of(tag: str) -> str {
    var i = 0usize
    while i < tag.len && !is_space(tag[i]) && tag[i] != 47u8 { i += 1usize }
    ret tag[0usize..i]
}

fn skipped(name: str) -> bool {
    ret same(name, "defs") || same(name, "title") || same(name, "desc") || same(name, "metadata") || same(name, "style") || same(name, "clipPath") || same(name, "mask") || same(name, "linearGradient") || same(name, "radialGradient") || same(name, "pattern") || same(name, "symbol") || same(name, "filter") || same(name, "marker") || same(name, "text") || same(name, "script")
}

// The document's own size: the viewBox's width and height, else the `width` and `height`.
fn size(text: str) -> (f32, f32, bool) {
    let open = find(text, 0usize, "<svg")
    if open >= text.len { ret (0.0, 0.0, false) }
    let tag = text[open + 1usize..tag_end(text, open)]
    let (view, has_view) = attr(tag, "viewBox")
    if has_view {
        var at = 0usize
        var vx = 0.0f32
        var vy = 0.0f32
        var vw = 0.0f32
        var vh = 0.0f32
        if read_number(view, &at, &vx) && read_number(view, &at, &vy) && read_number(view, &at, &vw) && read_number(view, &at, &vh) && vw > 0.0 && vh > 0.0 { ret (vw, vh, true) }
    }
    let w = length_of(tag, "width")
    let h = length_of(tag, "height")
    if w > 0.0 && h > 0.0 { ret (w, h, true) }
    ret (0.0, 0.0, false)
}

fn default_style(current: paint.Color) -> Style {
    ret Style { fill: paint.rgba(0.0, 0.0, 0.0, 1.0), fill_on: true, stroke: paint.rgba(0.0, 0.0, 0.0, 1.0), stroke_on: false, stroke_width: 1.0, cap: paint.StrokeCap.Butt, join: paint.StrokeJoin.Miter, miter: 4.0, opacity: 1.0, fill_opacity: 1.0, stroke_opacity: 1.0, current: current }
}

// Draw `text` into `b`, fitted to `dest`. `current` is what `currentColor` and an unset
// `color` mean. The commands are balanced -- one outer Save/Restore, one pair per shape.
fn draw(a: *mem.Arena, b: *scene.Builder, text: str, dest: geometry.Rect, current: paint.Color) -> err {
    var frames: [16]Frame = zero
    frames[0usize] = Frame { style: default_style(current), ctm: geometry.transform_identity() }
    var depth = 0usize
    var opened = false
    var i = 0usize
    while i < text.len {
        if text[i] != 60u8 {
            i += 1usize
            continue
        }
        if begins(text, i, "<!--") {
            i = find(text, i + 4usize, "-->") + 3usize
            continue
        }
        if i + 1usize < text.len && (text[i + 1usize] == 33u8 || text[i + 1usize] == 63u8) {
            i = tag_end(text, i) + 1usize
            continue
        }
        let end = tag_end(text, i)
        if i + 1usize < text.len && text[i + 1usize] == 47u8 {
            let closing = name_of(text[i + 2usize..end])
            if same(closing, "g") && depth > 0usize { depth -= 1usize }
            i = end + 1usize
            continue
        }
        let tag = text[i + 1usize..end]
        let name = name_of(tag)
        let self_closing = tag.len > 0usize && tag[tag.len - 1usize] == 47u8
        i = end + 1usize
        if skipped(name) {
            if !self_closing {
                var j = i
                var found = false
                while j + 2usize < text.len && !found {
                    if begins(text, j, "</") && same(name_of(text[j + 2usize..tag_end(text, j)]), name) { found = true } else { j += 1usize }
                }
                i = tag_end(text, j) + 1usize
            }
            continue
        }
        if same(name, "svg") {
            if !opened {
                opened = true
                frames[0usize].style = apply_style(tag, frames[0usize].style)
                let (vw, vh, has_size) = size(text)
                if !has_size { ret BadSvg }
                var vx = 0.0f32
                var vy = 0.0f32
                let (view, has_view) = attr(tag, "viewBox")
                if has_view {
                    var at = 0usize
                    var skip_w = 0.0f32
                    var skip_h = 0.0f32
                    let got = read_number(view, &at, &vx) && read_number(view, &at, &vy) && read_number(view, &at, &skip_w) && read_number(view, &at, &skip_h)
                }
                var scale = dest.width / vw
                if dest.height / vh < scale { scale = dest.height / vh }
                let fit = geometry.transform_multiply(geometry.transform_translate(dest.x + (dest.width - vw * scale) / 2.0, dest.y + (dest.height - vh * scale) / 2.0), geometry.transform_multiply(geometry.transform_scale(scale, scale), geometry.transform_translate(0.0 - vx, 0.0 - vy)))
                let save: scene.Command = .Save
                try scene.push(b, save)
                try scene.push(b, scene.Command { Transform: fit })
            } else {
                if depth + 1usize >= MAX_DEPTH { ret TooComplex }
                if !self_closing {
                    frames[depth + 1usize] = child_of(tag, frames[depth])
                    depth += 1usize
                }
            }
            continue
        }
        if !opened { continue }
        if same(name, "g") || same(name, "a") {
            if !self_closing {
                if depth + 1usize >= MAX_DEPTH { ret TooComplex }
                frames[depth + 1usize] = child_of(tag, frames[depth])
                depth += 1usize
            }
            continue
        }
        let frame = child_of(tag, frames[depth])
        if same(name, "rect") {
            // One radius given stands for both.
            var rx = length_of(tag, "rx")
            var ry = length_of(tag, "ry")
            if rx == 0.0 { rx = ry }
            if ry == 0.0 { ry = rx }
            let (path, path_error) = rect_path(a, length_of(tag, "x"), length_of(tag, "y"), length_of(tag, "width"), length_of(tag, "height"), rx, ry)
            if path_error != ok { ret path_error }
            try emit(b, frame, path)
        } else if same(name, "circle") {
            let r = length_of(tag, "r")
            let (path, path_error) = ellipse_path(a, length_of(tag, "cx"), length_of(tag, "cy"), r, r)
            if path_error != ok { ret path_error }
            try emit(b, frame, path)
        } else if same(name, "ellipse") {
            let (path, path_error) = ellipse_path(a, length_of(tag, "cx"), length_of(tag, "cy"), length_of(tag, "rx"), length_of(tag, "ry"))
            if path_error != ok { ret path_error }
            try emit(b, frame, path)
        } else if same(name, "line") {
            let (pb, pb_error) = new_path(a, 2usize, 2usize)
            if pb_error != ok { ret pb_error }
            var lb = pb
            try geometry.move_to(&lb, pt(length_of(tag, "x1"), length_of(tag, "y1")))
            try geometry.line_to(&lb, pt(length_of(tag, "x2"), length_of(tag, "y2")))
            var lined = frame
            lined.style.fill_on = false
            try emit(b, lined, geometry.finish(&lb))
        } else if same(name, "polyline") || same(name, "polygon") {
            let (list, has_list) = attr(tag, "points")
            if has_list {
                let (path, path_error) = points_path(a, list, same(name, "polygon"))
                if path_error != ok { ret path_error }
                try emit(b, frame, path)
            }
        } else if same(name, "path") {
            let (d, has_d) = attr(tag, "d")
            if has_d {
                let (pb, pb_error) = new_path(a, d.len * 2usize + 8usize, d.len * 6usize + 24usize)
                if pb_error != ok { ret pb_error }
                var pbv = pb
                try build_path(&pbv, d)
                try emit(b, frame, geometry.finish(&pbv))
            }
        }
    }
    if !opened { ret BadSvg }
    let restore: scene.Command = .Restore
    try scene.push(b, restore)
    ret ok
}
