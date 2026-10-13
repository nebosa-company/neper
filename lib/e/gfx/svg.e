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
// Also (L125, D2843): `fill` and `stroke` as `url(#id)` of a `linearGradient` or `radialGradient`
// (objectBoundingBox or userSpaceOnUse, `gradientTransform`, `stop-color`/`stop-opacity`, stops
// inherited by `href`; a single stop is a solid colour; a radial gradient over a non-square box
// takes the geometric mean of its sides as radius, and a focal point is ignored), `use` of any
// element or `symbol` by `href`/`xlink:href` (translated by `x`/`y`, at most 8 deep) with `defs`
// content drawn only that way, `clip-path="url(#id)"` over the first shape of a `clipPath` (in
// the clipped element's user space), and lengths with `px pt pc mm cm in em` or `%` of the
// viewBox's width (x-ish) or height (y-ish).
//
// Also (L125, D3100): `<style>` sheets of simple selectors (`*`, `rect`, `.a`, `rect.a.b`, `#id`,
// comma lists; no combinators, pseudo-classes or at-rules) cascaded above attributes and below an
// element's own `style`; `preserveAspectRatio` (`none`, the nine `x?Y?` alignments, `meet` and
// `slice`, which clips to the destination); `spreadMethod` reflect and repeat on linear and radial
// gradients (the stops are tiled over the periods the shape reaches, at most 32); `stroke-dasharray`
// and `stroke-dashoffset` (the path is flattened and cut into dash subpaths, restarting per
// subpath; round and square caps draw zero-length dashes as dots); `fill-rule="evenodd"` (each
// subpath is wound by its nesting depth so the non-zero scene fill is the even-odd fill: exact for
// disjoint and nested simple loops, a path that crosses itself still fills non-zero); `pattern`
// fills (tiles of the pattern's children, `patternUnits`, `patternContentUnits`,
// `patternTransform`, clipped to the shape; no `viewBox`, no `href`); and `marker-start`, `-mid`,
// `-end` and `marker` on `path`, `line`, `polyline` and `polygon` (`markerWidth`/`Height`, `refX`/
// `refY`, `viewBox`, `orient` as `auto` or an angle, `markerUnits`, clipped to the marker viewport).
//
// Also (L125, D3701): `opacity` on a group, `use` or shape composites the element once as an
// OpacityLayer (four deep; deeper, and inside patterns and markers, it multiplies into the
// children's alpha); selectors with the descendant, `>`, `+` and `~` combinators, `[attr]`,
// `[attr=value]` and `:first-child`, by real specificity; a pattern's `viewBox` and `href`
// (attributes and content); a radial gradient's focal point (a stack of FOCAL_STEPS circles, opaque
// stops and pad spread only); `mask` on a shape, group or `use` (the element is replayed under each
// filled shape of the mask at that shape's luminance times alpha, a linear gradient as MASK_STRIPS
// strips; strokes and text in the mask add nothing); and `<text>` through
// `draw_with_font` over `e.text.layout` (`x`, `y`, `font-size`, `text-anchor`, `fill`, `tspan`
// with its own position as a new chunk).
//
// Also (L125, D4503): filter effects through `draw_filtered`. An element with `filter="url(#id)"` is
// measured (its object bounding box, by a throwaway walk under the inverse of its own transform),
// its filter region taken in device pixels (`filterUnits`, default -10%/120% of the box; clipped to the
// host's target), its source graphic rendered into a scratch target of that size, the `<filter>`'s
// primitives parsed into `e.gfx.svg_filter` programs and run over the pixels, and the result drawn as an
// image of the host's renderer before the element's own clip, mask and opacity (the opacity and clip
// are lifted out of the source walk by `Style.filter_skip`). The primitives are `feGaussianBlur`,
// `feOffset`, `feFlood`, `feBlend`, `feComposite`, `feColorMatrix`, `feMerge` and `feDropShadow`, with
// `in`/`in2`/`result` names, `x`/`y`/`width`/`height` subregions, `primitiveUnits` and
// `color-interpolation-filters`; any other `fe*` passes its input through. An unknown filter id draws
// nothing; inside a replay (mask, pattern, marker) and in the source graphic of another filter the
// element is drawn unfiltered.
//
// Also (L125, D4504): `mask` with `maskUnits`, `maskContentUnits` and `x`/`y`/`width`/`height` (the
// region clips each mask piece; box units measure the element as for filters); `font-family`,
// `font-weight` and `font-style` choose among the caller's `Face`s (`draw_with_faces`); and
// `<textPath>` sets each character on the first subpath of the path its `href` names.
//
// Not drawn: text through `draw` (no font). The elements of a definition are skipped whole (an
// unresolvable `url(...)` paint draws nothing).
//
// ponytail: mask pieces composite over each other where the mask's shapes overlap, and every piece
// replays the masked element (cost: pieces x the element's commands, bounded by the scene's size).
// A path draws into arena storage sized from its data and never frees it -- icons are small and
// the arena is the caller's.

use e.math
use e.mem
use e.str
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg_filter as sf
use e.text.layout
use e.text.shape as fonts

error BadSvg
error TooComplex

const MAX_DEPTH: usize = 16usize

type Style = struct { fill: paint.Color, fill_on: bool, stroke: paint.Color, stroke_on: bool, stroke_width: f32, cap: paint.StrokeCap, join: paint.StrokeJoin, miter: f32, opacity: f32, fill_opacity: f32, stroke_opacity: f32, current: paint.Color, fill_ref: str, stroke_ref: str, clip_ref: str, clip_ctm: geometry.Transform, dash: str, dash_offset: f32, even_odd: bool, marker_start: str, marker_mid: str, marker_end: str, mask_skip: bool, filter_skip: bool, font_size: f32, anchor: usize, font_family: str, font_weight: u32, font_italic: bool }
// `layers` counts the opacity layers open around the frame's content (a frame that may open no
// more has 4); `opens` says this frame's own element opened one, closed with its end tag.
type Frame = struct { style: Style, ctm: geometry.Transform, layers: usize, opens: bool }

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
        s.fill_on = kind == 1u8 || kind == 2u8
        s.fill_ref = ""
        if kind == 2u8 { s.fill_ref = url_id(fill) }
    }
    let (stroke, has_stroke) = prop(tag, "stroke")
    if has_stroke {
        let (c, kind) = parse_paint(stroke, s.current)
        s.stroke = c
        s.stroke_on = kind == 1u8 || kind == 2u8
        s.stroke_ref = ""
        if kind == 2u8 { s.stroke_ref = url_id(stroke) }
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
    let (dash, has_dash) = prop(tag, "stroke-dasharray")
    if has_dash { s.dash = trim(dash) }
    let (dash_offset, has_dash_offset) = prop(tag, "stroke-dashoffset")
    if has_dash_offset { s.dash_offset = number_of(dash_offset, 0.0) }
    let (rule, has_rule) = prop(tag, "fill-rule")
    if has_rule { s.even_odd = same(trim(rule), "evenodd") }
    let (marker_all, has_marker_all) = prop(tag, "marker")
    if has_marker_all {
        s.marker_start = url_id(marker_all)
        s.marker_mid = s.marker_start
        s.marker_end = s.marker_start
    }
    let (marker_start, has_marker_start) = prop(tag, "marker-start")
    if has_marker_start { s.marker_start = url_id(marker_start) }
    let (marker_mid, has_marker_mid) = prop(tag, "marker-mid")
    if has_marker_mid { s.marker_mid = url_id(marker_mid) }
    let (marker_end, has_marker_end) = prop(tag, "marker-end")
    if has_marker_end { s.marker_end = url_id(marker_end) }
    let (font_size, has_font_size) = prop(tag, "font-size")
    if has_font_size { s.font_size = length_value(font_size, s.font_size, s.font_size) }
    let (anchor, has_anchor) = prop(tag, "text-anchor")
    if has_anchor {
        if same(trim(anchor), "middle") { s.anchor = 1usize } else if same(trim(anchor), "end") { s.anchor = 2usize } else { s.anchor = 0usize }
    }
    let (family, has_family) = prop(tag, "font-family")
    if has_family { s.font_family = trim(family) }
    let (weight, has_weight) = prop(tag, "font-weight")
    if has_weight { s.font_weight = weight_of(trim(weight), s.font_weight) }
    let (face_style, has_face_style) = prop(tag, "font-style")
    if has_face_style { s.font_italic = same(trim(face_style), "italic") || same(trim(face_style), "oblique") }
    ret s
}

// A `font-weight` value: the keywords, a number 1..1000 (clamped), `bolder` and `lighter` a step from the parent.
fn weight_of(value: str, parent: u32) -> u32 {
    if same(value, "normal") { ret 400u32 }
    if same(value, "bold") { ret 700u32 }
    if same(value, "bolder") {
        if parent < 600u32 { ret 700u32 }
        ret 900u32
    }
    if same(value, "lighter") {
        if parent > 500u32 { ret 400u32 }
        ret 100u32
    }
    var at = 0usize
    var v = 0.0f32
    if read_number(value, &at, &v) {
        if v < 1.0 { ret 1u32 }
        if v > 1000.0 { ret 1000u32 }
        ret u32(v)
    }
    ret parent
}

fn lower_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn same_name(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if lower_byte(left[i]) != lower_byte(right[i]) { ret false }
        i += 1usize
    }
    ret true
}

// The face for `family` (a comma list, quotes optional; the first name any face has) at `weight` and `italic`:
// among that family's faces the nearest weight, an italic mismatch costing more than any weight gap. Index 0
// when no name matches.
fn pick_face(faces: []const Face, family: str, weight: u32, italic: bool) -> usize {
    var at = 0usize
    while at < family.len {
        var end = at
        while end < family.len && family[end] != 44u8 { end += 1usize }
        var name = trim(family[at..end])
        if name.len >= 2usize && (name[0usize] == 34u8 || name[0usize] == 39u8) && name[name.len - 1usize] == name[0usize] { name = name[1usize..name.len - 1usize] }
        var best = faces.len
        var best_cost = 0u32
        var i = 0usize
        while i < faces.len {
            if same_name(faces[i].family, name) {
                var cost = 0u32
                if faces[i].italic != italic { cost = 100000u32 }
                if faces[i].weight > weight { cost += faces[i].weight - weight } else { cost += weight - faces[i].weight }
                if best == faces.len || cost < best_cost {
                    best = i
                    best_cost = cost
                }
            }
            i += 1usize
        }
        if best < faces.len { ret best }
        at = end + 1usize
    }
    ret 0usize
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

// A masked element being replayed under each piece of its mask (D3701): the element's source, the
// frame its parent drew it in, and where the replay walks from.
type Job = struct { text: str, frame: Frame, dest: geometry.Rect, level: usize, anc: []const str, region: geometry.Path, has_region: bool }
// The document: its text and the viewport a percentage is taken of; `view` is the viewBox in the
// root user space (what an opacity layer's bounds are), `job` is set while a mask's content is
// walked, and `font` is what `<text>` is set in when the caller gave one.
// A face a caller offers for `font-family`, `font-weight` and `font-style` to choose from (a family name
// compared without case, a weight 1..1000, whether it is italic).
type Face = struct { family: str, weight: u32, italic: bool, font: fonts.Font }
type Doc = struct { text: str, vw: f32, vh: f32, view: geometry.Rect, job: *Job, has_job: bool, font: fonts.Font, has_font: bool, base_anc: []const str, fit: *geometry.Transform, host: *sf.Host, has_host: bool, faces: []const Face }
// An element found by its `id`: its opening tag, its whole text and its body.
type Found = struct { tag: str, start: usize, end: usize, body_start: usize, body_end: usize, found: bool }

// The id inside `url(#id)`, or "".
fn url_id(value: str) -> str {
    var i = 0usize
    while i < value.len && value[i] != 35u8 { i += 1usize }
    if i >= value.len { ret "" }
    let start = i + 1usize
    var end = start
    while end < value.len && value[end] != 41u8 && value[end] != 39u8 && value[end] != 34u8 && !is_space(value[end]) { end += 1usize }
    ret value[start..end]
}

// The tag's name: the run of characters up to a space, a slash or the end.
fn name_of(tag: str) -> str {
    var i = 0usize
    while i < tag.len && !is_space(tag[i]) && tag[i] != 47u8 { i += 1usize }
    ret tag[0usize..i]
}

// The element whose `id` is `want`: its opening tag and the span through its matching
// closing tag (nested elements of the same name counted).
fn find_by_id(text: str, want: str) -> Found {
    var out: Found = zero
    if want.len == 0usize { ret out }
    var i = 0usize
    while i < text.len {
        if text[i] != 60u8 || i + 1usize >= text.len || text[i + 1usize] == 47u8 || text[i + 1usize] == 33u8 || text[i + 1usize] == 63u8 {
            i += 1usize
            continue
        }
        let end = tag_end(text, i)
        let tag = text[i + 1usize..end]
        let (id, has_id) = attr(tag, "id")
        if has_id && same(id, want) {
            out.tag = tag
            out.start = i
            out.found = true
            let self_closing = tag.len > 0usize && tag[tag.len - 1usize] == 47u8
            if self_closing {
                out.end = end + 1usize
                out.body_start = end + 1usize
                out.body_end = end + 1usize
                ret out
            }
            let name = name_of(tag)
            var depth = 1usize
            var j = end + 1usize
            out.body_start = j
            out.body_end = text.len
            out.end = text.len
            while j < text.len {
                if text[j] != 60u8 {
                    j += 1usize
                    continue
                }
                let close = tag_end(text, j)
                if j + 1usize < text.len && text[j + 1usize] == 47u8 {
                    if same(name_of(text[j + 2usize..close]), name) {
                        depth -= 1usize
                        if depth == 0usize {
                            out.body_end = j
                            out.end = close + 1usize
                            ret out
                        }
                    }
                } else if j + 1usize < text.len && text[j + 1usize] != 33u8 && text[j + 1usize] != 63u8 {
                    let inner = text[j + 1usize..close]
                    if same(name_of(inner), name) && !(inner.len > 0usize && inner[inner.len - 1usize] == 47u8) { depth += 1usize }
                }
                j = close + 1usize
            }
            ret out
        }
        i = end + 1usize
    }
    ret out
}

// A length's unit factor at `at` in `value`: (user units per unit, is a percentage).
fn unit_factor(value: str, at: usize) -> (f32, bool) {
    var j = at
    while j < value.len && is_space(value[j]) { j += 1usize }
    let unit = trim(value[j..value.len])
    if unit.len == 0usize || same(unit, "px") { ret (1.0, false) }
    if same(unit, "%") { ret (0.01, true) }
    if same(unit, "pt") { ret (1.3333334, false) }
    if same(unit, "pc") { ret (16.0, false) }
    if same(unit, "mm") { ret (3.7795277, false) }
    if same(unit, "cm") { ret (37.795277, false) }
    if same(unit, "in") { ret (96.0, false) }
    if same(unit, "em") { ret (16.0, false) }
    ret (1.0, false)
}

// A length in user units; a percentage is of `axis`.
fn length_value(value: str, fallback: f32, axis: f32) -> f32 {
    var at = 0usize
    var out = fallback
    if !read_number(value, &at, &out) { ret fallback }
    let (factor, percent) = unit_factor(value, at)
    if percent { ret out * factor * axis }
    ret out * factor
}

fn length_of(tag: str, name: str) -> f32 {
    let (value, found) = attr(tag, name)
    if !found { ret 0.0 }
    ret length_value(value, 0.0, 0.0)
}

// Lengths along x (`x`, `width`, `cx`, `rx`) and along y of the viewport.
fn len_x(doc: Doc, tag: str, name: str) -> f32 {
    let (value, found) = attr(tag, name)
    if !found { ret 0.0 }
    ret length_value(value, 0.0, doc.vw)
}

fn len_y(doc: Doc, tag: str, name: str) -> f32 {
    let (value, found) = attr(tag, name)
    if !found { ret 0.0 }
    ret length_value(value, 0.0, doc.vh)
}

// The path of a shape element; false when `name` is not one.
fn shape_path(a: *mem.Arena, doc: Doc, tag: str, name: str) -> (geometry.Path, bool, err) {
    if same(name, "rect") {
        var rx = len_x(doc, tag, "rx")
        var ry = len_y(doc, tag, "ry")
        if rx == 0.0 { rx = ry }
        if ry == 0.0 { ry = rx }
        let (path, path_error) = rect_path(a, len_x(doc, tag, "x"), len_y(doc, tag, "y"), len_x(doc, tag, "width"), len_y(doc, tag, "height"), rx, ry)
        ret (path, path_error == ok, path_error)
    }
    if same(name, "circle") {
        let r = len_x(doc, tag, "r")
        let (path, path_error) = ellipse_path(a, len_x(doc, tag, "cx"), len_y(doc, tag, "cy"), r, r)
        ret (path, path_error == ok, path_error)
    }
    if same(name, "ellipse") {
        let (path, path_error) = ellipse_path(a, len_x(doc, tag, "cx"), len_y(doc, tag, "cy"), len_x(doc, tag, "rx"), len_y(doc, tag, "ry"))
        ret (path, path_error == ok, path_error)
    }
    if same(name, "line") {
        let (pb, pb_error) = new_path(a, 2usize, 2usize)
        if pb_error != ok { ret (zero, false, pb_error) }
        var lb = pb
        try geometry.move_to(&lb, pt(len_x(doc, tag, "x1"), len_y(doc, tag, "y1")))
        try geometry.line_to(&lb, pt(len_x(doc, tag, "x2"), len_y(doc, tag, "y2")))
        ret (geometry.finish(&lb), true, ok)
    }
    if same(name, "polyline") || same(name, "polygon") {
        let (list, has_list) = attr(tag, "points")
        if !has_list { ret (zero, false, ok) }
        let (path, path_error) = points_path(a, list, same(name, "polygon"))
        ret (path, path_error == ok, path_error)
    }
    if same(name, "path") {
        let (d, has_d) = attr(tag, "d")
        if !has_d { ret (zero, false, ok) }
        let (pb, pb_error) = new_path(a, d.len * 2usize + 8usize, d.len * 6usize + 24usize)
        if pb_error != ok { ret (zero, false, pb_error) }
        var pbv = pb
        try build_path(&pbv, d)
        ret (geometry.finish(&pbv), true, ok)
    }
    ret (zero, false, ok)
}

fn path_bounds(path: geometry.Path) -> geometry.Rect {
    if path.points.len == 0usize { ret geometry.rect(0.0, 0.0, 0.0, 0.0) }
    var x0 = path.points[0usize].x
    var y0 = path.points[0usize].y
    var x1 = x0
    var y1 = y0
    var i = 1usize
    while i < path.points.len {
        let p = path.points[i]
        if p.x < x0 { x0 = p.x }
        if p.y < y0 { y0 = p.y }
        if p.x > x1 { x1 = p.x }
        if p.y > y1 { y1 = p.y }
        i += 1usize
    }
    ret geometry.rect(x0, y0, x1 - x0, y1 - y0)
}

// A coordinate of a gradient: a number or percentage; as a fraction of the bounding box
// (objectBoundingBox) or in user units (a percentage then of `axis`).
fn gradient_coord(tag: str, name: str, fallback: f32, boxed: bool, axis: f32) -> f32 {
    let (value, found) = attr(tag, name)
    ret coord_value(value, found, fallback, boxed, axis)
}

// The same for a value already looked up.
fn coord_value(value: str, found: bool, fallback: f32, boxed: bool, axis: f32) -> f32 {
    if !found { ret fallback }
    var at = 0usize
    var out = 0.0f32
    if !read_number(value, &at, &out) { ret fallback }
    let (factor, percent) = unit_factor(value, at)
    if boxed {
        if percent { ret out * factor }
        ret out
    }
    if percent { ret out * factor * axis }
    ret out * factor
}

// The stops inside the element's body (`<stop offset= stop-color= stop-opacity=>`),
// offsets clamped to 0..1 and made non-decreasing, alpha scaled by `alpha`.
fn gradient_stops(a: *mem.Arena, text: str, body_start: usize, body_end: usize, alpha: f32, current: paint.Color) -> ([]paint.Stop, err) {
    var count = 0usize
    var i = body_start
    while i < body_end {
        let at = find(text, i, "<stop")
        if at >= body_end { break }
        count += 1usize
        i = at + 5usize
    }
    if count == 0usize { ret (zero, ok) }
    let (stops, stops_error) = mem.alloc[paint.Stop](a, count)
    if stops_error != ok { ret (zero, stops_error) }
    var n = 0usize
    var last = 0.0f32
    i = body_start
    while i < body_end && n < count {
        let at = find(text, i, "<stop")
        if at >= body_end { break }
        let end = tag_end(text, at)
        let tag = text[at + 1usize..end]
        var offset = last
        let (offset_text, has_offset) = attr(tag, "offset")
        if has_offset {
            var p = 0usize
            var number = 0.0f32
            if read_number(offset_text, &p, &number) {
                let (factor, percent) = unit_factor(offset_text, p)
                if percent { number = number * factor }
                offset = number
            }
        }
        if offset < last { offset = last }
        if offset > 1.0 { offset = 1.0 }
        last = offset
        var color = byte_color(0usize, 0usize, 0usize, 255usize)
        let (color_text, has_color) = prop(tag, "stop-color")
        if has_color {
            let (c, kind) = parse_paint(color_text, current)
            if kind == 1u8 { color = c }
        }
        var stop_alpha = 1.0f32
        let (opacity_text, has_opacity) = prop(tag, "stop-opacity")
        if has_opacity { stop_alpha = unit_value(number_of(opacity_text, 1.0)) }
        stops[n] = paint.Stop { offset: offset, color: color_with(color, stop_alpha * alpha) }
        n += 1usize
        i = end + 1usize
    }
    ret (stops[..n], ok)
}

// 0 pad, 1 reflect, 2 repeat: the gradient's `spreadMethod`, else its href's.
fn spread_of(doc: Doc, tag: str) -> usize {
    var holder = tag
    var hops = 0usize
    while hops < 4usize {
        let (method, has_method) = attr(holder, "spreadMethod")
        if has_method {
            if same(method, "reflect") { ret 1usize }
            if same(method, "repeat") { ret 2usize }
            ret 0usize
        }
        let (plain, has_plain) = attr(holder, "href")
        let (linked, has_linked) = attr(holder, "xlink:href")
        var reference = plain
        if !has_plain { reference = linked }
        if !has_plain && !has_linked { ret 0usize }
        let next = find_by_id(doc.text, url_id(reference))
        if !next.found { ret 0usize }
        holder = next.tag
        hops += 1usize
    }
    ret 0usize
}

// `periods` copies of the stops end to end; reflect runs every odd period backwards
// (`first_odd` is the parity of the first one).
fn spread_stops(a: *mem.Arena, stops: []const paint.Stop, periods: usize, reflect: bool, first_odd: usize) -> ([]paint.Stop, err) {
    let n = stops.len
    let (out, out_error) = mem.alloc[paint.Stop](a, n * periods)
    if out_error != ok { ret (zero, out_error) }
    var k = 0usize
    while k < periods {
        var i = 0usize
        while i < n {
            var source = stops[i]
            var offset = source.offset
            if reflect && (k + first_odd) % 2usize == 1usize {
                source = stops[n - 1usize - i]
                offset = 1.0 - source.offset
            }
            out[k * n + i] = paint.Stop { offset: (f32(k) + offset) / f32(periods), color: source.color }
            i += 1usize
        }
        k += 1usize
    }
    ret (out, ok)
}

// The brush for `url(#id)` over a shape with bounds `bounds`; false when the id names
// no gradient or it has no stops. A single stop is a solid colour. Spread methods other
// than pad, a radial focal point and a radial gradient's elliptical box are not drawn.
fn gradient_brush(a: *mem.Arena, doc: Doc, id: str, bounds: geometry.Rect, cover: geometry.Rect, alpha: f32, current: paint.Color) -> (paint.Brush, bool, err) {
    let found = find_by_id(doc.text, id)
    var none: paint.Brush = zero
    if !found.found { ret (none, false, ok) }
    let name = name_of(found.tag)
    let linear = same(name, "linearGradient")
    if !linear && !same(name, "radialGradient") { ret (none, false, ok) }
    var stops: []paint.Stop = zero
    let (own, own_error) = gradient_stops(a, doc.text, found.body_start, found.body_end, alpha, current)
    if own_error != ok { ret (none, false, own_error) }
    stops = own
    if stops.len == 0usize {
        // Stops inherited through href="#other".
        let (plain_href, has_plain) = attr(found.tag, "href")
        let (xlink_href, has_xlink) = attr(found.tag, "xlink:href")
        var href = plain_href
        if !has_plain { href = xlink_href }
        if has_plain || has_xlink {
            let source = find_by_id(doc.text, url_id(href))
            if source.found {
                let (inherited, inherited_error) = gradient_stops(a, doc.text, source.body_start, source.body_end, alpha, current)
                if inherited_error != ok { ret (none, false, inherited_error) }
                stops = inherited
            }
        }
    }
    if stops.len == 0usize { ret (none, false, ok) }
    if stops.len == 1usize { ret (paint.Brush { Solid: stops[0usize].color }, true, ok) }
    var boxed = true
    let (units, has_units) = attr(found.tag, "gradientUnits")
    if has_units && same(units, "userSpaceOnUse") { boxed = false }
    var transform = geometry.transform_identity()
    let (transform_text, has_transform) = attr(found.tag, "gradientTransform")
    if has_transform { transform = parse_transform(transform_text) }
    if linear {
        var x1 = gradient_coord(found.tag, "x1", 0.0, boxed, doc.vw)
        var y1 = gradient_coord(found.tag, "y1", 0.0, boxed, doc.vh)
        var x2 = gradient_coord(found.tag, "x2", 1.0, boxed, doc.vw)
        var y2 = gradient_coord(found.tag, "y2", 0.0, boxed, doc.vh)
        if boxed {
            x1 = bounds.x + x1 * bounds.width
            x2 = bounds.x + x2 * bounds.width
            y1 = bounds.y + y1 * bounds.height
            y2 = bounds.y + y2 * bounds.height
        }
        var start = geometry.transform_point(transform, pt(x1, y1))
        var stop_point = geometry.transform_point(transform, pt(x2, y2))
        let spread = spread_of(doc, found.tag)
        let dx = stop_point.x - start.x
        let dy = stop_point.y - start.y
        let dd = dx * dx + dy * dy
        if spread != 0usize && dd > 0.0 {
            // Repeat and reflect: tile the stops over every period the shape reaches.
            let t0 = ((cover.x - start.x) * dx + (cover.y - start.y) * dy) / dd
            let t1 = ((cover.x + cover.width - start.x) * dx + (cover.y - start.y) * dy) / dd
            let t2 = ((cover.x - start.x) * dx + (cover.y + cover.height - start.y) * dy) / dd
            let t3 = ((cover.x + cover.width - start.x) * dx + (cover.y + cover.height - start.y) * dy) / dd
            var lo = t0
            var hi = t0
            if t1 < lo { lo = t1 }
            if t2 < lo { lo = t2 }
            if t3 < lo { lo = t3 }
            if t1 > hi { hi = t1 }
            if t2 > hi { hi = t2 }
            if t3 > hi { hi = t3 }
            let k0 = i64(math.floor[f32](lo))
            var k1 = i64(math.ceil[f32](hi))
            if k1 <= k0 { k1 = k0 + 1i64 }
            if k1 - k0 > 32i64 { k1 = k0 + 32i64 }
            var parity = k0 % 2i64
            if parity < 0i64 { parity += 2i64 }
            let (tiled, tiled_error) = spread_stops(a, stops, usize(k1 - k0), spread == 1usize, usize(parity))
            if tiled_error != ok { ret (none, false, tiled_error) }
            stops = tiled
            stop_point = pt(start.x + dx * f32(k1), start.y + dy * f32(k1))
            start = pt(start.x + dx * f32(k0), start.y + dy * f32(k0))
        }
        ret (paint.Brush { Linear: paint.LinearGradient { start: start, end: stop_point, stops: stops } }, true, ok)
    }
    var cx = gradient_coord(found.tag, "cx", 0.5, boxed, doc.vw)
    var cy = gradient_coord(found.tag, "cy", 0.5, boxed, doc.vh)
    var r = gradient_coord(found.tag, "r", 0.5, boxed, doc.vw)
    if boxed {
        cx = bounds.x + cx * bounds.width
        cy = bounds.y + cy * bounds.height
        // The box is not always square; the circle takes the geometric mean of its sides.
        r = r * math.sqrt[f32](bounds.width * bounds.height)
    }
    let center = geometry.transform_point(transform, pt(cx, cy))
    let det = transform.m00 * transform.m11 - transform.m01 * transform.m10
    var scale = det
    if scale < 0.0 { scale = 0.0 - scale }
    var radius = r * math.sqrt[f32](scale)
    let spread = spread_of(doc, found.tag)
    if spread != 0usize && radius > 0.0 {
        var far = 0.0f32
        var corner = 0usize
        while corner < 4usize {
            var px = cover.x
            var py = cover.y
            if corner % 2usize == 1usize { px += cover.width }
            if corner >= 2usize { py += cover.height }
            let d = geometry.distance(center, pt(px, py))
            if d > far { far = d }
            corner += 1usize
        }
        var periods = i64(math.ceil[f32](far / radius))
        if periods < 1i64 { periods = 1i64 }
        if periods > 32i64 { periods = 32i64 }
        let (tiled, tiled_error) = spread_stops(a, stops, usize(periods), spread == 1usize, 0usize)
        if tiled_error != ok { ret (none, false, tiled_error) }
        stops = tiled
        radius = radius * f32(periods)
    }
    ret (paint.Brush { Radial: paint.RadialGradient { center: center, radius: radius, stops: stops } }, true, ok)
}

// The first shape inside the `clipPath` named `id`, as a path in the space of `ctm`.
fn clip_path(a: *mem.Arena, doc: Doc, id: str, ctm: geometry.Transform) -> (geometry.Path, bool, err) {
    let found = find_by_id(doc.text, id)
    if !found.found || !same(name_of(found.tag), "clipPath") { ret (zero, false, ok) }
    var i = found.body_start
    while i < found.body_end {
        if doc.text[i] != 60u8 || i + 1usize >= doc.text.len || doc.text[i + 1usize] == 47u8 {
            i += 1usize
            continue
        }
        let end = tag_end(doc.text, i)
        let tag = doc.text[i + 1usize..end]
        let (path, has_path, path_error) = shape_path(a, doc, tag, name_of(tag))
        if path_error != ok { ret (zero, false, path_error) }
        if has_path {
            let (points, points_error) = mem.alloc[geometry.Point](a, path.points.len)
            if points_error != ok { ret (zero, false, points_error) }
            var k = 0usize
            while k < points.len {
                points[k] = geometry.transform_point(ctm, path.points[k])
                k += 1usize
            }
            ret (geometry.Path { verbs: path.verbs, points: points }, true, ok)
        }
        i = end + 1usize
    }
    ret (zero, false, ok)
}

// ---- <style> sheets (L125, D3100) ----------------------------------------------------------

// One matched declaration block: its specificity level and its byte span in the document.
type Hit = struct { level: usize, from: usize, to: usize }

fn class_has(list: str, word: str) -> bool {
    var i = 0usize
    while i < list.len {
        while i < list.len && is_space(list[i]) { i += 1usize }
        var j = i
        while j < list.len && !is_space(list[j]) { j += 1usize }
        if j > i && same(list[i..j], word) { ret true }
        i = j
    }
    ret false
}

// ---- selectors with combinators (L125, D3701) ----------------------------------------------

const MAX_PARTS: usize = 8usize

// A selector split at its combinators: compound `i` and the combinator (space, `>`, `+`, `~`)
// between compound `i` and `i + 1`.
type Selector = struct { parts: [8]str, combs: [8]u8, n: usize }
// The element a selector is matched against: its raw tag, its ancestors from the root, and the
// siblings before it (oldest first).
type Scope = struct { subject: str, anc: []const str, sibs: []const str }
type Node = struct { tag: str, first: bool }

fn split_selector(sel: str) -> (Selector, bool) {
    var out: Selector = zero
    var comb = 0u8
    var i = 0usize
    while i < sel.len {
        let c = sel[i]
        if is_space(c) {
            i += 1usize
            continue
        }
        if c == 62u8 || c == 43u8 || c == 126u8 {
            if out.n == 0usize || comb != 0u8 { ret (out, false) }
            comb = c
            i += 1usize
            continue
        }
        let start = i
        var inside = false
        while i < sel.len && (inside || !(is_space(sel[i]) || sel[i] == 62u8 || sel[i] == 43u8 || sel[i] == 126u8)) {
            if sel[i] == 91u8 { inside = true }
            if sel[i] == 93u8 { inside = false }
            i += 1usize
        }
        if out.n >= MAX_PARTS { ret (out, false) }
        if out.n > 0usize {
            if comb == 0u8 { out.combs[out.n - 1usize] = 32u8 } else { out.combs[out.n - 1usize] = comb }
        }
        out.parts[out.n] = sel[start..i]
        out.n += 1usize
        comb = 0u8
    }
    ret (out, out.n > 0usize && comb == 0u8)
}

fn unquote(value: str) -> str {
    let v = trim(value)
    if v.len >= 2usize && (v[0usize] == 34u8 || v[0usize] == 39u8) && v[v.len - 1usize] == v[0usize] { ret v[1usize..v.len - 1usize] }
    ret v
}

// Does one compound selector (`rect.a#id[k=v]:first-child`, `*`) match the node? Adds its
// specificity (ids 10000, classes, attributes and pseudo-classes 100, a type 1) to `*spec`.
fn compound_match(comp: str, node: Node, spec: *usize) -> bool {
    let element = name_of(node.tag)
    let (classes, has_classes) = attr(node.tag, "class")
    let (id, has_id) = attr(node.tag, "id")
    var j = 0usize
    while j < comp.len && comp[j] != 46u8 && comp[j] != 35u8 && comp[j] != 91u8 && comp[j] != 58u8 { j += 1usize }
    if j > 0usize && !same(comp[0usize..j], "*") {
        if !same(comp[0usize..j], element) { ret false }
        *spec += 1usize
    }
    var i = j
    while i < comp.len {
        let kind = comp[i]
        if kind == 91u8 {
            var close = i
            while close < comp.len && comp[close] != 93u8 { close += 1usize }
            let body = comp[i + 1usize..close]
            var eq = 0usize
            while eq < body.len && body[eq] != 61u8 { eq += 1usize }
            let (value, has_value) = attr(node.tag, trim(body[0usize..eq]))
            if !has_value { ret false }
            if eq < body.len && !same(value, unquote(body[eq + 1usize..body.len])) { ret false }
            *spec += 100usize
            i = close + 1usize
        } else if kind == 58u8 {
            var k = i + 1usize
            while k < comp.len && comp[k] != 46u8 && comp[k] != 35u8 && comp[k] != 91u8 && comp[k] != 58u8 { k += 1usize }
            if !same(comp[i + 1usize..k], "first-child") || !node.first { ret false }
            *spec += 100usize
            i = k
        } else {
            var k = i + 1usize
            while k < comp.len && comp[k] != 46u8 && comp[k] != 35u8 && comp[k] != 91u8 && comp[k] != 58u8 { k += 1usize }
            let part = comp[i + 1usize..k]
            if kind == 46u8 {
                if !class_has(classes, part) { ret false }
                *spec += 100usize
            } else {
                if !same(part, id) { ret false }
                *spec += 10000usize
            }
            i = k
        }
    }
    ret true
}

// The node of a scope: kind 0 the subject, 1 the sibling `idx`, 2 the ancestor `idx`. Whether an
// ancestor is a first child is not known, so `:first-child` never matches one.
fn node_at(sc: Scope, kind: usize, idx: usize) -> Node {
    if kind == 0usize { ret Node { tag: sc.subject, first: sc.sibs.len == 0usize } }
    if kind == 1usize { ret Node { tag: sc.sibs[idx], first: idx == 0usize } }
    ret Node { tag: sc.anc[idx], first: false }
}

// Does compound `i` of the selector match the node (kind, idx), and the compounds before it
// the nodes its combinators reach? Specificity of the whole chain is added to `*spec`.
fn match_parts(sel: Selector, sc: Scope, i: usize, kind: usize, idx: usize, spec: *usize) -> bool {
    var local = 0usize
    if !compound_match(sel.parts[i], node_at(sc, kind, idx), &local) { ret false }
    if i == 0usize {
        *spec += local
        ret true
    }
    let comb = sel.combs[i - 1usize]
    var sub = 0usize
    if comb == 62u8 {
        var parent = sc.anc.len
        if kind == 2usize { parent = idx }
        if parent == 0usize { ret false }
        if match_parts(sel, sc, i - 1usize, 2usize, parent - 1usize, &sub) {
            *spec += local + sub
            ret true
        }
        ret false
    }
    if comb == 32u8 {
        var from = sc.anc.len
        if kind == 2usize { from = idx }
        var a = from
        while a > 0usize {
            a -= 1usize
            sub = 0usize
            if match_parts(sel, sc, i - 1usize, 2usize, a, &sub) {
                *spec += local + sub
                ret true
            }
        }
        ret false
    }
    if kind == 2usize { ret false }
    var upto = sc.sibs.len
    if kind == 1usize { upto = idx }
    if comb == 43u8 {
        if upto == 0usize { ret false }
        if match_parts(sel, sc, i - 1usize, 1usize, upto - 1usize, &sub) {
            *spec += local + sub
            ret true
        }
        ret false
    }
    var s = upto
    while s > 0usize {
        s -= 1usize
        sub = 0usize
        if match_parts(sel, sc, i - 1usize, 1usize, s, &sub) {
            *spec += local + sub
            ret true
        }
    }
    ret false
}

// The specificity of the selector against the scope's element, or 0 for no match (a matching
// selector always has at least 1: the universal selector alone counts 1).
fn selector_spec(text: str, sc: Scope) -> usize {
    let (sel, valid) = split_selector(text)
    if !valid { ret 0usize }
    var spec = 0usize
    if !match_parts(sel, sc, sel.n - 1usize, 0usize, 0usize, &spec) { ret 0usize }
    ret spec + 1usize
}

// The rules of every `<style>` element that match the element, in source order.
fn collect_hits(text: str, sc: Scope, hits: []Hit) -> usize {
    var n = 0usize
    var at = find(text, 0usize, "<style")
    while at < text.len {
        let open_end = tag_end(text, at)
        let close = find(text, open_end, "</style")
        var base = open_end + 1usize
        if base > close { base = close }
        let css = text[base..close]
        var i = 0usize
        while i < css.len {
            if is_space(css[i]) {
                i += 1usize
                continue
            }
            if begins(css, i, "/*") {
                i = find(css, i + 2usize, "*/") + 2usize
                continue
            }
            if begins(css, i, "<![CDATA[") {
                i += 9usize
                continue
            }
            if begins(css, i, "]]>") {
                i += 3usize
                continue
            }
            var j = i
            while j < css.len && css[j] != 123u8 { j += 1usize }
            if j >= css.len { break }
            var k = j + 1usize
            while k < css.len && css[k] != 125u8 { k += 1usize }
            let selectors = css[i..j]
            if selectors[0usize] != 64u8 {
                var best = 0usize
                var s = 0usize
                while s <= selectors.len {
                    var e = s
                    while e < selectors.len && selectors[e] != 44u8 { e += 1usize }
                    let rank = selector_spec(trim(selectors[s..e]), sc)
                    if rank > best { best = rank }
                    s = e + 1usize
                }
                if best > 0usize && n < hits.len {
                    hits[n] = Hit { level: best, from: base + j + 1usize, to: base + k }
                    n += 1usize
                }
            }
            i = k + 1usize
        }
        at = find(text, close, "<style")
    }
    ret n
}

// The tag with the declarations of the matching sheet rules folded into a leading
// `style` attribute: the element's own `style` first (it wins), then the rules by
// specificity and then by source order, later first. Attributes sit below `style` in
// `prop`, which is the cascade's order for presentation attributes.
fn styled(a: *mem.Arena, doc: Doc, tag: str, anc: []const str, sibs: []const str) -> (str, err) {
    if find(doc.text, 0usize, "<style") >= doc.text.len { ret (tag, ok) }
    let element = name_of(tag)
    var hits: [32]Hit = zero
    let n = collect_hits(doc.text, Scope { subject: tag, anc: anc, sibs: sibs }, hits[0usize..32usize])
    if n == 0usize { ret (tag, ok) }
    let (inline, has_inline) = attr(tag, "style")
    let (made, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (tag, builder_error) }
    var sb = made
    try str.push(&sb, element)
    try str.push(&sb, " style=\"")
    if has_inline {
        try str.push(&sb, inline)
        try str.push(&sb, ";")
    }
    // Highest specificity first, later rules first among equals (the first declaration of a
    // property wins in `prop`).
    var used: [32]bool = zero
    var done = 0usize
    while done < n {
        var best = 32usize
        var h = 0usize
        while h < n {
            if !used[h] && (best == 32usize || hits[h].level >= hits[best].level) { best = h }
            h += 1usize
        }
        used[best] = true
        try str.push(&sb, doc.text[hits[best].from..hits[best].to])
        try str.push(&sb, ";")
        done += 1usize
    }
    try str.push(&sb, "\"")
    try str.push(&sb, tag[element.len..tag.len])
    ret (str.done(&sb), ok)
}

// ---- dashes and even-odd fills -------------------------------------------------------------

const MAX_DASHES: usize = 16usize

// `stroke-dasharray` as lengths in `out`; zero entries for `none`, a negative entry or an
// all-zero list. An odd list is repeated to make it even, as the specification has it.
fn dash_values(value: str, out: []f32) -> usize {
    if same(value, "none") { ret 0usize }
    var n = 0usize
    var at = 0usize
    var total = 0.0f32
    while n < out.len {
        var v = 0.0f32
        if !read_number(value, &at, &v) { break }
        var j = at
        while j < value.len && is_alpha(value[j]) { j += 1usize }
        let (factor, percent) = unit_factor(value[at..j], 0usize)
        at = j
        if v < 0.0 { ret 0usize }
        out[n] = v * factor
        total += out[n]
        n += 1usize
    }
    if n == 0usize || !(total > 0.0) { ret 0usize }
    if n % 2usize == 1usize && n * 2usize <= out.len {
        var k = 0usize
        while k < n {
            out[n + k] = out[k]
            k += 1usize
        }
        n *= 2usize
    }
    ret n
}

type DashState = struct { on: bool, idx: usize, remaining: f32, started: bool }

// Flattening tolerance for a path of these bounds: 1/2000 of the larger side.
fn flat_tolerance(bounds: geometry.Rect) -> f32 {
    var tol = bounds.width
    if bounds.height > tol { tol = bounds.height }
    tol = tol / 2000.0
    if tol < 0.01 { tol = 0.01 }
    ret tol
}

fn flat_of(a: *mem.Arena, path: geometry.Path) -> (geometry.Path, err) {
    let (fv, fv_error) = mem.alloc[geometry.PathVerb](a, path.verbs.len * 48usize + 16usize)
    if fv_error != ok { ret (zero, fv_error) }
    let (fp, fp_error) = mem.alloc[geometry.Point](a, path.points.len * 48usize + 16usize)
    if fp_error != ok { ret (zero, fp_error) }
    let (flat, flat_error) = geometry.flatten(path, flat_tolerance(path_bounds(path)), fv, fp)
    if flat_error != ok { ret (zero, TooComplex) }
    ret (flat, ok)
}

fn dash_advance(st: *DashState, dashes: []const f32) {
    st.idx = (st.idx + 1usize) % dashes.len
    st.on = !st.on
    st.started = false
    st.remaining = dashes[st.idx]
}

// Dashes of the segment p..q, appended to `pb`; the state carries across segments.
fn dash_segment(pb: *geometry.PathBuilder, st: *DashState, dashes: []const f32, p: geometry.Point, q: geometry.Point) -> err {
    let seg = geometry.distance(p, q)
    if !(seg > 0.0) { ret ok }
    var pos = 0.0f32
    while pos < seg {
        var step = st.remaining
        if step > seg - pos { step = seg - pos }
        let here = geometry.lerp(p, q, (pos + step) / seg)
        if st.on {
            if !st.started {
                try geometry.move_to(pb, geometry.lerp(p, q, pos / seg))
                st.started = true
            }
            try geometry.line_to(pb, here)
        }
        pos += step
        st.remaining -= step
        if st.remaining <= 0.0 {
            dash_advance(st, dashes)
            var spins = 0usize
            while st.remaining <= 0.0 && spins < dashes.len {
                // A zero-length dash is a dot (round and square caps draw it).
                if st.on {
                    try geometry.move_to(pb, here)
                    try geometry.line_to(pb, here)
                }
                dash_advance(st, dashes)
                spins += 1usize
            }
        }
    }
    ret ok
}

// The path cut into dashes: every subpath restarts the pattern at `offset`.
fn dash_path(a: *mem.Arena, path: geometry.Path, dashes: []const f32, offset: f32) -> (geometry.Path, err) {
    let (flat, flat_error) = flat_of(a, path)
    if flat_error != ok { ret (zero, flat_error) }
    var cycle = 0.0f32
    var d = 0usize
    while d < dashes.len {
        cycle += dashes[d]
        d += 1usize
    }
    var length = 0.0f32
    var pi = 0usize
    var cur: geometry.Point = zero
    var first: geometry.Point = zero
    var vi = 0usize
    while vi < flat.verbs.len {
        let verb = flat.verbs[vi]
        if verb == .Move {
            cur = flat.points[pi]
            first = cur
            pi += 1usize
        } else if verb == .Line {
            length += geometry.distance(cur, flat.points[pi])
            cur = flat.points[pi]
            pi += 1usize
        } else {
            length += geometry.distance(cur, first)
            cur = first
        }
        vi += 1usize
    }
    let events = usize(length / cycle) + 2usize
    if events > 20000usize { ret (zero, TooComplex) }
    let cap = flat.points.len + 2usize * events * dashes.len + 16usize
    let (pb, pb_error) = new_path(a, cap, cap)
    if pb_error != ok { ret (zero, pb_error) }
    var builder = pb
    var st = DashState { on: true, idx: 0usize, remaining: 0.0, started: false }
    var skip = offset - cycle * math.floor[f32](offset / cycle)
    pi = 0usize
    vi = 0usize
    while vi < flat.verbs.len {
        let verb = flat.verbs[vi]
        if verb == .Move {
            cur = flat.points[pi]
            first = cur
            pi += 1usize
            st = DashState { on: true, idx: 0usize, remaining: dashes[0usize], started: false }
            var left = skip
            while left > 0.0 {
                if left >= st.remaining {
                    left -= st.remaining
                    dash_advance(&st, dashes)
                } else {
                    st.remaining -= left
                    left = 0.0
                }
            }
        } else if verb == .Line {
            let next = flat.points[pi]
            pi += 1usize
            try dash_segment(&builder, &st, dashes, cur, next)
            cur = next
        } else {
            try dash_segment(&builder, &st, dashes, cur, first)
            cur = first
        }
        vi += 1usize
    }
    ret (geometry.finish(&builder), ok)
}

// Is `p` inside the polygon pts[from..to] by the even-odd rule?
fn polygon_has(pts: []const geometry.Point, from: usize, to: usize, p: geometry.Point) -> bool {
    var inside = false
    var j = to - 1usize
    var i = from
    while i < to {
        let u = pts[i]
        let w = pts[j]
        if (u.y > p.y) != (w.y > p.y) {
            let x = (w.x - u.x) * (p.y - u.y) / (w.y - u.y) + u.x
            if p.x < x { inside = !inside }
        }
        j = i
        i += 1usize
    }
    ret inside
}

// A path whose non-zero fill is its even-odd fill: each subpath wound the way its nesting
// depth asks (even depth one way, odd the other), so a loop inside a loop cuts a hole.
// Exact for disjoint and nested simple loops; a loop that crosses itself still fills non-zero.
fn even_odd_path(a: *mem.Arena, path: geometry.Path) -> (geometry.Path, err) {
    let (flat, flat_error) = flat_of(a, path)
    if flat_error != ok { ret (zero, flat_error) }
    var count = 0usize
    var vi = 0usize
    while vi < flat.verbs.len {
        if flat.verbs[vi] == .Move { count += 1usize }
        vi += 1usize
    }
    if count == 0usize { ret (path, ok) }
    let (starts, starts_error) = mem.alloc[usize](a, count + 1usize)
    if starts_error != ok { ret (zero, starts_error) }
    var s = 0usize
    var pi = 0usize
    vi = 0usize
    while vi < flat.verbs.len {
        let verb = flat.verbs[vi]
        if verb == .Move {
            starts[s] = pi
            s += 1usize
            pi += 1usize
        } else if verb == .Line {
            pi += 1usize
        }
        vi += 1usize
    }
    starts[count] = pi
    let (pb, pb_error) = new_path(a, flat.points.len + count * 2usize + 8usize, flat.points.len + 8usize)
    if pb_error != ok { ret (zero, pb_error) }
    var builder = pb
    s = 0usize
    while s < count {
        let from = starts[s]
        let to = starts[s + 1usize]
        if to - from >= 3usize {
            var depth = 0usize
            var o = 0usize
            while o < count {
                if o != s && starts[o + 1usize] - starts[o] >= 3usize && polygon_has(flat.points, starts[o], starts[o + 1usize], flat.points[from]) { depth += 1usize }
                o += 1usize
            }
            var area = 0.0f32
            var j = to - 1usize
            var i = from
            while i < to {
                area += flat.points[j].x * flat.points[i].y - flat.points[i].x * flat.points[j].y
                j = i
                i += 1usize
            }
            let want_positive = depth % 2usize == 0usize
            let reverse = (area > 0.0) != want_positive
            var n = 0usize
            while n < to - from {
                var at = from + n
                if reverse { at = to - 1usize - n }
                if n == 0usize { try geometry.move_to(&builder, flat.points[at]) } else { try geometry.line_to(&builder, flat.points[at]) }
                n += 1usize
            }
            try geometry.close_path(&builder)
        } else {
            var n = from
            while n < to {
                if n == from { try geometry.move_to(&builder, flat.points[n]) } else { try geometry.line_to(&builder, flat.points[n]) }
                n += 1usize
            }
        }
        s += 1usize
    }
    ret (geometry.finish(&builder), ok)
}

// ---- patterns -------------------------------------------------------------------------------

const MAX_LAYERS_SVG: usize = 4usize

// The value of a pattern attribute: the pattern's own, else the first pattern its href chain reaches
// that has it.
fn pattern_attr(doc: Doc, pat: Found, name: str) -> (str, bool) {
    var holder = pat
    var hops = 0usize
    while hops < 4usize {
        let (value, found) = attr(holder.tag, name)
        if found { ret (value, true) }
        let (plain, has_plain) = attr(holder.tag, "href")
        let (linked, has_linked) = attr(holder.tag, "xlink:href")
        var reference = plain
        if !has_plain { reference = linked }
        if !has_plain && !has_linked { ret ("", false) }
        let next = find_by_id(doc.text, url_id(reference))
        if !next.found || !same(name_of(next.tag), "pattern") { ret ("", false) }
        holder = next
        hops += 1usize
    }
    ret ("", false)
}

// The pattern whose children are drawn: this one, or the first on its href chain that has any.
fn pattern_content(doc: Doc, pat: Found) -> Found {
    var holder = pat
    var hops = 0usize
    while hops < 4usize {
        if trim(doc.text[holder.body_start..holder.body_end]).len > 0usize { ret holder }
        let (plain, has_plain) = attr(holder.tag, "href")
        let (linked, has_linked) = attr(holder.tag, "xlink:href")
        var reference = plain
        if !has_plain { reference = linked }
        if !has_plain && !has_linked { ret holder }
        let next = find_by_id(doc.text, url_id(reference))
        if !next.found || !same(name_of(next.tag), "pattern") { ret holder }
        holder = next
        hops += 1usize
    }
    ret holder
}

// The transform that maps a `viewBox` onto a `w` x `h` viewport under a `preserveAspectRatio`
// value ("" for the default xMidYMid meet); false when the viewBox is unusable.
fn view_transform(view: str, w: f32, h: f32, aspect: str) -> (geometry.Transform, bool) {
    var p = 0usize
    var vx = 0.0f32
    var vy = 0.0f32
    var vw = 0.0f32
    var vh = 0.0f32
    if !(read_number(view, &p, &vx) && read_number(view, &p, &vy) && read_number(view, &p, &vw) && read_number(view, &p, &vh) && vw > 0.0 && vh > 0.0) { ret (geometry.transform_identity(), false) }
    var fx = 0.5f32
    var fy = 0.5f32
    var stretch = false
    var slice = false
    if find(aspect, 0usize, "none") < aspect.len { stretch = true }
    if find(aspect, 0usize, "xMin") < aspect.len { fx = 0.0 }
    if find(aspect, 0usize, "xMax") < aspect.len { fx = 1.0 }
    if find(aspect, 0usize, "YMin") < aspect.len { fy = 0.0 }
    if find(aspect, 0usize, "YMax") < aspect.len { fy = 1.0 }
    if find(aspect, 0usize, "slice") < aspect.len { slice = true }
    var sx = w / vw
    var sy = h / vh
    if !stretch {
        var k = sx
        if slice { if sy > k { k = sy } } else { if sy < k { k = sy } }
        sx = k
        sy = k
    }
    ret (geometry.transform_multiply(geometry.transform_translate((w - vw * sx) * fx, (h - vh * sy) * fy), geometry.transform_multiply(geometry.transform_scale(sx, sy), geometry.transform_translate(0.0 - vx, 0.0 - vy))), true)
}

fn invert(t: geometry.Transform) -> (geometry.Transform, bool) {
    let det = t.m00 * t.m11 - t.m01 * t.m10
    if det < 0.000001 && det > 0.0 - 0.000001 { ret (t, false) }
    ret (geometry.Transform { m00: t.m11 / det, m01: 0.0 - t.m01 / det, m02: (t.m01 * t.m12 - t.m11 * t.m02) / det, m10: 0.0 - t.m10 / det, m11: t.m00 / det, m12: (t.m10 * t.m02 - t.m00 * t.m12) / det }, true)
}

// Fill `path` by tiling the `pattern` element's children over its bounds, clipped to the
// path. `viewBox` on the pattern and a pattern's own `href` are not read.
fn fill_pattern(a: *mem.Arena, b: *scene.Builder, doc: Doc, style: Style, path: geometry.Path, bounds: geometry.Rect, pat: Found, level: usize) -> err {
    if level + 1usize >= 8usize { ret TooComplex }
    var boxed = true
    let (units, has_units) = pattern_attr(doc, pat, "patternUnits")
    if has_units && same(units, "userSpaceOnUse") { boxed = false }
    var content_boxed = false
    let (content_units, has_content_units) = pattern_attr(doc, pat, "patternContentUnits")
    if has_content_units && same(content_units, "objectBoundingBox") { content_boxed = true }
    var tx = 0.0f32
    var ty = 0.0f32
    var tw = 0.0f32
    var th = 0.0f32
    let (x_text, has_x) = pattern_attr(doc, pat, "x")
    let (y_text, has_y) = pattern_attr(doc, pat, "y")
    let (w_text, has_w) = pattern_attr(doc, pat, "width")
    let (h_text, has_h) = pattern_attr(doc, pat, "height")
    if boxed {
        tx = bounds.x + coord_value(x_text, has_x, 0.0, true, 0.0) * bounds.width
        ty = bounds.y + coord_value(y_text, has_y, 0.0, true, 0.0) * bounds.height
        tw = coord_value(w_text, has_w, 0.0, true, 0.0) * bounds.width
        th = coord_value(h_text, has_h, 0.0, true, 0.0) * bounds.height
    } else {
        if has_x { tx = length_value(x_text, 0.0, doc.vw) }
        if has_y { ty = length_value(y_text, 0.0, doc.vh) }
        if has_w { tw = length_value(w_text, 0.0, doc.vw) }
        if has_h { th = length_value(h_text, 0.0, doc.vh) }
    }
    if !(tw > 0.0) || !(th > 0.0) { ret ok }
    var pm = geometry.transform_identity()
    let (pm_text, has_pm) = pattern_attr(doc, pat, "patternTransform")
    if has_pm { pm = parse_transform(pm_text) }
    // A viewBox maps onto the tile (and then patternContentUnits does not apply).
    var content = geometry.transform_identity()
    var has_content = false
    let (view_text, has_view) = pattern_attr(doc, pat, "viewBox")
    if has_view {
        let (aspect_text, has_aspect) = pattern_attr(doc, pat, "preserveAspectRatio")
        var aspect = ""
        if has_aspect { aspect = aspect_text }
        let (mapped, has_mapped) = view_transform(view_text, tw, th, aspect)
        if has_mapped {
            content = mapped
            has_content = true
            content_boxed = false
        }
    }
    let (inv, invertible) = invert(pm)
    if !invertible { ret ok }
    let c0 = geometry.transform_point(inv, pt(bounds.x, bounds.y))
    let c1 = geometry.transform_point(inv, pt(bounds.x + bounds.width, bounds.y))
    let c2 = geometry.transform_point(inv, pt(bounds.x, bounds.y + bounds.height))
    let c3 = geometry.transform_point(inv, pt(bounds.x + bounds.width, bounds.y + bounds.height))
    var min_x = c0.x
    var max_x = c0.x
    var min_y = c0.y
    var max_y = c0.y
    if c1.x < min_x { min_x = c1.x }
    if c2.x < min_x { min_x = c2.x }
    if c3.x < min_x { min_x = c3.x }
    if c1.x > max_x { max_x = c1.x }
    if c2.x > max_x { max_x = c2.x }
    if c3.x > max_x { max_x = c3.x }
    if c1.y < min_y { min_y = c1.y }
    if c2.y < min_y { min_y = c2.y }
    if c3.y < min_y { min_y = c3.y }
    if c1.y > max_y { max_y = c1.y }
    if c2.y > max_y { max_y = c2.y }
    if c3.y > max_y { max_y = c3.y }
    let ix0 = i64(math.floor[f32]((min_x - tx) / tw))
    let ix1 = i64(math.ceil[f32]((max_x - tx) / tw))
    let iy0 = i64(math.floor[f32]((min_y - ty) / th))
    let iy1 = i64(math.ceil[f32]((max_y - ty) / th))
    if (ix1 - ix0) * (iy1 - iy0) > 1024i64 { ret TooComplex }
    let holder = pattern_content(doc, pat)
    let inner = doc.text[holder.body_start..holder.body_end]
    let frame = Frame { style: apply_style(pat.tag, default_style(style.current)), ctm: geometry.transform_identity(), layers: MAX_LAYERS_SVG, opens: false }
    let save: scene.Command = .Save
    let restore: scene.Command = .Restore
    try scene.push(b, save)
    try scene.push(b, scene.Command { Clip: scene.Clip { Path: path } })
    try scene.push(b, scene.Command { Transform: pm })
    var iy = iy0
    while iy < iy1 {
        var ix = ix0
        while ix < ix1 {
            try scene.push(b, save)
            try scene.push(b, scene.Command { Transform: geometry.transform_translate(tx + f32(ix) * tw, ty + f32(iy) * th) })
            try scene.push(b, scene.Command { Clip: scene.Clip { Rect: geometry.rect(0.0, 0.0, tw, th) } })
            if content_boxed { try scene.push(b, scene.Command { Transform: geometry.transform_scale(bounds.width, bounds.height) }) }
            if has_content { try scene.push(b, scene.Command { Transform: content }) }
            try walk(a, b, doc, inner, frame, false, bounds, level + 1usize)
            try scene.push(b, restore)
            ix += 1i64
        }
        iy += 1i64
    }
    try scene.push(b, restore)
    ret ok
}

// ---- markers --------------------------------------------------------------------------------

// A path vertex with the unit directions of the segments arriving and leaving it.
type Vertex = struct { at: geometry.Point, in_x: f32, in_y: f32, has_in: bool, out_x: f32, out_y: f32, has_out: bool }

fn unit_dir(from: geometry.Point, to: geometry.Point) -> (f32, f32, bool) {
    let dx = to.x - from.x
    let dy = to.y - from.y
    let len = math.sqrt[f32](dx * dx + dy * dy)
    if !(len > 0.000001) { ret (0.0, 0.0, false) }
    ret (dx / len, dy / len, true)
}

// The vertices of a path with their tangents (curves use their control polygon).
fn vertices_of(a: *mem.Arena, path: geometry.Path) -> ([]Vertex, err) {
    let (out, out_error) = mem.alloc[Vertex](a, path.verbs.len + 1usize)
    if out_error != ok { ret (zero, out_error) }
    var n = 0usize
    var pi = 0usize
    var cur: geometry.Point = zero
    var first: geometry.Point = zero
    var vi = 0usize
    while vi < path.verbs.len {
        let verb = path.verbs[vi]
        if verb == .Move {
            cur = path.points[pi]
            first = cur
            pi += 1usize
            out[n] = Vertex { at: cur, in_x: 0.0, in_y: 0.0, has_in: false, out_x: 0.0, out_y: 0.0, has_out: false }
            n += 1usize
        } else if n > 0usize {
            var start_to = cur
            var end_from = cur
            var end = cur
            if verb == .Line {
                end = path.points[pi]
                start_to = end
                end_from = cur
                pi += 1usize
            } else if verb == .Quad {
                start_to = path.points[pi]
                end_from = path.points[pi]
                end = path.points[pi + 1usize]
                pi += 2usize
            } else if verb == .Cubic {
                start_to = path.points[pi]
                end_from = path.points[pi + 1usize]
                end = path.points[pi + 2usize]
                pi += 3usize
            } else {
                end = first
                start_to = first
            }
            let (s1x, s1y, s1ok) = unit_dir(cur, start_to)
            let (s2x, s2y, s2ok) = unit_dir(cur, end)
            let (e1x, e1y, e1ok) = unit_dir(end_from, end)
            var sx = s1x
            var sy = s1y
            var has_s = s1ok
            if !s1ok {
                sx = s2x
                sy = s2y
                has_s = s2ok
            }
            var ex = e1x
            var ey = e1y
            var has_e = e1ok
            if !e1ok {
                ex = s2x
                ey = s2y
                has_e = s2ok
            }
            out[n - 1usize].out_x = sx
            out[n - 1usize].out_y = sy
            out[n - 1usize].has_out = has_s
            out[n] = Vertex { at: end, in_x: ex, in_y: ey, has_in: has_e, out_x: 0.0, out_y: 0.0, has_out: false }
            n += 1usize
            cur = end
        }
        vi += 1usize
    }
    ret (out[..n], ok)
}

// Draw the marker element `id` at `at` heading `(dx, dy)`, at `scale` times its own size.
fn draw_marker(a: *mem.Arena, b: *scene.Builder, doc: Doc, style: Style, id: str, at: geometry.Point, dx: f32, dy: f32, level: usize) -> err {
    if id.len == 0usize { ret ok }
    if level + 1usize >= 8usize { ret TooComplex }
    let m = find_by_id(doc.text, id)
    if !m.found || !same(name_of(m.tag), "marker") { ret ok }
    var mw = 3.0f32
    var mh = 3.0f32
    let (mw_text, has_mw) = attr(m.tag, "markerWidth")
    if has_mw { mw = length_value(mw_text, 3.0, doc.vw) }
    let (mh_text, has_mh) = attr(m.tag, "markerHeight")
    if has_mh { mh = length_value(mh_text, 3.0, doc.vh) }
    if !(mw > 0.0) || !(mh > 0.0) { ret ok }
    var scale = style.stroke_width
    let (units, has_units) = attr(m.tag, "markerUnits")
    if has_units && same(units, "userSpaceOnUse") { scale = 1.0 }
    var rx = 0.0f32
    var ry = 0.0f32
    let (rx_text, has_rx) = attr(m.tag, "refX")
    if has_rx { rx = length_value(rx_text, 0.0, doc.vw) }
    let (ry_text, has_ry) = attr(m.tag, "refY")
    if has_ry { ry = length_value(ry_text, 0.0, doc.vh) }
    // The viewBox maps into the (mw, mh) viewport, meet and centred.
    var content = geometry.transform_identity()
    let (view, has_view) = attr(m.tag, "viewBox")
    if has_view {
        var p = 0usize
        var vx = 0.0f32
        var vy = 0.0f32
        var vw = 0.0f32
        var vh = 0.0f32
        if read_number(view, &p, &vx) && read_number(view, &p, &vy) && read_number(view, &p, &vw) && read_number(view, &p, &vh) && vw > 0.0 && vh > 0.0 {
            var k = mw / vw
            if mh / vh < k { k = mh / vh }
            content = geometry.transform_multiply(geometry.transform_translate((mw - vw * k) / 2.0, (mh - vh * k) / 2.0), geometry.transform_multiply(geometry.transform_scale(k, k), geometry.transform_translate(0.0 - vx, 0.0 - vy)))
        }
    }
    let ref_point = geometry.transform_point(content, pt(rx, ry))
    var heading_x = 1.0f32
    var heading_y = 0.0f32
    let (orient, has_orient) = attr(m.tag, "orient")
    if has_orient {
        if same(orient, "auto") {
            heading_x = dx
            heading_y = dy
        } else if same(orient, "auto-start-reverse") {
            heading_x = dx
            heading_y = dy
        } else {
            let radians = number_of(orient, 0.0) * 0.017453292
            heading_x = math.cos[f32](radians)
            heading_y = math.sin[f32](radians)
        }
    }
    let place = geometry.Transform { m00: heading_x * scale, m01: 0.0 - heading_y * scale, m02: at.x, m10: heading_y * scale, m11: heading_x * scale, m12: at.y }
    let save: scene.Command = .Save
    let restore: scene.Command = .Restore
    try scene.push(b, save)
    try scene.push(b, scene.Command { Transform: place })
    try scene.push(b, scene.Command { Transform: geometry.transform_translate(0.0 - ref_point.x, 0.0 - ref_point.y) })
    try scene.push(b, scene.Command { Clip: scene.Clip { Rect: geometry.rect(0.0, 0.0, mw, mh) } })
    try scene.push(b, scene.Command { Transform: content })
    let frame = Frame { style: apply_style(m.tag, default_style(style.current)), ctm: geometry.transform_identity(), layers: MAX_LAYERS_SVG, opens: false }
    try walk(a, b, doc, doc.text[m.body_start..m.body_end], frame, false, geometry.rect(0.0, 0.0, mw, mh), level + 1usize)
    try scene.push(b, restore)
    ret ok
}

fn draw_markers(a: *mem.Arena, b: *scene.Builder, doc: Doc, style: Style, path: geometry.Path, level: usize) -> err {
    if style.marker_start.len == 0usize && style.marker_mid.len == 0usize && style.marker_end.len == 0usize { ret ok }
    let (vs, vs_error) = vertices_of(a, path)
    if vs_error != ok { ret vs_error }
    var i = 0usize
    while i < vs.len {
        let v = vs[i]
        var dx = 1.0f32
        var dy = 0.0f32
        if v.has_in && v.has_out {
            dx = v.in_x + v.out_x
            dy = v.in_y + v.out_y
            let len = math.sqrt[f32](dx * dx + dy * dy)
            if len > 0.000001 {
                dx = dx / len
                dy = dy / len
            } else {
                dx = v.out_x
                dy = v.out_y
            }
        } else if v.has_out {
            dx = v.out_x
            dy = v.out_y
        } else if v.has_in {
            dx = v.in_x
            dy = v.in_y
        }
        var id = style.marker_mid
        if i == 0usize { id = style.marker_start }
        if i + 1usize == vs.len { id = style.marker_end }
        if i == 0usize && vs.len == 1usize { id = style.marker_start }
        try draw_marker(a, b, doc, style, id, v.at, dx, dy, level)
        i += 1usize
    }
    ret ok
}

// ---- radial focal point (L125, D3701) -------------------------------------------------------

// The gradient colour at `t` (pad): stops are in ascending offset.
fn color_at(stops: []const paint.Stop, t: f32) -> paint.Color {
    if stops.len == 0usize { ret paint.rgba(0.0, 0.0, 0.0, 0.0) }
    if t <= stops[0usize].offset { ret stops[0usize].color }
    var i = 1usize
    while i < stops.len {
        if t <= stops[i].offset {
            let lo = stops[i - 1usize]
            let hi = stops[i]
            var u = 1.0f32
            if hi.offset > lo.offset { u = (t - lo.offset) / (hi.offset - lo.offset) }
            ret paint.Color { red: lo.color.red + (hi.color.red - lo.color.red) * u, green: lo.color.green + (hi.color.green - lo.color.green) * u, blue: lo.color.blue + (hi.color.blue - lo.color.blue) * u, alpha: lo.color.alpha + (hi.color.alpha - lo.color.alpha) * u }
        }
        i += 1usize
    }
    ret stops[stops.len - 1usize].color
}

// The focal point `fx`/`fy` of the radial gradient `id`, in the space of its centre; false when
// it has none of its own, or its spread is not pad (the stops are then tiled around the centre).
fn focus_of(doc: Doc, id: str, bounds: geometry.Rect) -> (geometry.Point, bool) {
    let found = find_by_id(doc.text, id)
    let none = pt(0.0, 0.0)
    if !found.found || !same(name_of(found.tag), "radialGradient") { ret (none, false) }
    let (fx_text, has_fx) = attr(found.tag, "fx")
    let (fy_text, has_fy) = attr(found.tag, "fy")
    if !has_fx && !has_fy { ret (none, false) }
    if spread_of(doc, found.tag) != 0usize { ret (none, false) }
    var boxed = true
    let (units, has_units) = attr(found.tag, "gradientUnits")
    if has_units && same(units, "userSpaceOnUse") { boxed = false }
    let cx = gradient_coord(found.tag, "cx", 0.5, boxed, doc.vw)
    let cy = gradient_coord(found.tag, "cy", 0.5, boxed, doc.vh)
    var fx = coord_value(fx_text, has_fx, cx, boxed, doc.vw)
    var fy = coord_value(fy_text, has_fy, cy, boxed, doc.vh)
    if boxed {
        fx = bounds.x + fx * bounds.width
        fy = bounds.y + fy * bounds.height
    }
    var transform = geometry.transform_identity()
    let (transform_text, has_transform) = attr(found.tag, "gradientTransform")
    if has_transform { transform = parse_transform(transform_text) }
    ret (geometry.transform_point(transform, pt(fx, fy)), true)
}

const FOCAL_STEPS: usize = 96usize

// A radial gradient with its focus off the centre, as a stack of circles: the level set of
// parameter t is the circle of radius t*r centred t of the way from the focus to the centre, so
// painting t = 1 down to 0 in FOCAL_STEPS bands, each its colour at the band's middle, draws the
// two-point gradient up to the banding. Opaque stops only: translucent ones would pile up.
fn focal_fill(a: *mem.Arena, b: *scene.Builder, shape: geometry.Path, rad: paint.RadialGradient, focus: geometry.Point) -> (bool, err) {
    if rad.stops.len == 0usize || !(rad.radius > 0.0) { ret (false, ok) }
    var i = 0usize
    while i < rad.stops.len {
        if rad.stops[i].color.alpha < 0.999 { ret (false, ok) }
        i += 1usize
    }
    var fx = focus.x
    var fy = focus.y
    let dx = fx - rad.center.x
    let dy = fy - rad.center.y
    let d = math.sqrt[f32](dx * dx + dy * dy)
    let limit = rad.radius * 0.98
    if d > limit {
        fx = rad.center.x + dx * limit / d
        fy = rad.center.y + dy * limit / d
    }
    let save: scene.Command = .Save
    let restore: scene.Command = .Restore
    try scene.push(b, scene.Command { FillPath: scene.FillPath { path: shape, brush: paint.Brush { Solid: rad.stops[rad.stops.len - 1usize].color } } })
    try scene.push(b, save)
    try scene.push(b, scene.Command { Clip: scene.Clip { Path: shape } })
    var k = FOCAL_STEPS
    while k > 0usize {
        let t = f32(k) / f32(FOCAL_STEPS)
        let middle = (f32(k) - 0.5) / f32(FOCAL_STEPS)
        let (circle, circle_error) = ellipse_path(a, fx + (rad.center.x - fx) * t, fy + (rad.center.y - fy) * t, rad.radius * t, rad.radius * t)
        if circle_error != ok { ret (false, circle_error) }
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: circle, brush: paint.Brush { Solid: color_at(rad.stops, middle) } } })
        k -= 1usize
    }
    try scene.push(b, restore)
    ret (true, ok)
}

// ---- masks (L125, D3701) --------------------------------------------------------------------

// The relative luminance of a colour (SVG 1.1's coefficients, over the stored display values).
fn luminance(c: paint.Color) -> f32 {
    ret 0.2125 * c.red + 0.7154 * c.green + 0.0721 * c.blue
}

// The path with every point carried through `t`.
fn place_path(a: *mem.Arena, path: geometry.Path, t: geometry.Transform) -> (geometry.Path, err) {
    let (points, points_error) = mem.alloc[geometry.Point](a, path.points.len)
    if points_error != ok { ret (zero, points_error) }
    var k = 0usize
    while k < points.len {
        points[k] = geometry.transform_point(t, path.points[k])
        k += 1usize
    }
    ret (geometry.Path { verbs: path.verbs, points: points }, ok)
}

fn quad_path(a: *mem.Arena, p0: geometry.Point, p1: geometry.Point, p2: geometry.Point, p3: geometry.Point) -> (geometry.Path, err) {
    let (pb, pb_error) = new_path(a, 5usize, 4usize)
    if pb_error != ok { ret (zero, pb_error) }
    var b = pb
    try geometry.move_to(&b, p0)
    try geometry.line_to(&b, p1)
    try geometry.line_to(&b, p2)
    try geometry.line_to(&b, p3)
    try geometry.close_path(&b)
    ret (geometry.finish(&b), ok)
}

// One piece of a mask: the masked element, clipped to `shape` (and to `strip`), at the mask's
// value `k` there. The element is replayed from its source, under a layer of opacity `k`.
fn mask_piece(a: *mem.Arena, b: *scene.Builder, plain: Doc, job: *Job, shape: geometry.Path, strip: geometry.Path, has_strip: bool, k: f32) -> err {
    if !(k > 0.001) { ret ok }
    let save: scene.Command = .Save
    let restore: scene.Command = .Restore
    try scene.push(b, save)
    try scene.push(b, scene.Command { Clip: scene.Clip { Path: shape } })
    if has_strip { try scene.push(b, scene.Command { Clip: scene.Clip { Path: strip } }) }
    if job.has_region { try scene.push(b, scene.Command { Clip: scene.Clip { Path: job.region } }) }
    var frame = job.frame
    var value = k
    if value > 1.0 { value = 1.0 }
    var layered = false
    if frame.layers < MAX_LAYERS_SVG {
        try scene.push(b, scene.Command { OpacityLayer: scene.OpacityLayer { bounds: plain.view, opacity: value } })
        frame.layers += 1usize
        layered = true
    } else {
        frame.style.opacity = frame.style.opacity * value
    }
    try walk(a, b, plain, job.text, frame, false, job.dest, job.level + 1usize)
    if layered { try scene.push(b, restore) }
    try scene.push(b, restore)
    ret ok
}

const MASK_STRIPS: usize = 32usize

// A shape of a mask's content: its fill's luminance times its alpha is the mask's value over it.
// A solid fill is one piece; a linear gradient is MASK_STRIPS strips across its axis (and a pad
// piece either side); a radial gradient or pattern is its mean stop. Strokes and text add nothing.
fn emit_mask_piece(a: *mem.Arena, b: *scene.Builder, doc: Doc, frame: Frame, path: geometry.Path, fillable: bool) -> err {
    let s = frame.style
    if !fillable || !s.fill_on { ret ok }
    let job = doc.job
    var plain = doc
    plain.has_job = false
    let alpha = s.opacity * s.fill_opacity
    let (shape, shape_error) = place_path(a, path, frame.ctm)
    if shape_error != ok { ret shape_error }
    var strip: geometry.Path = zero
    if s.fill_ref.len == 0usize {
        try mask_piece(a, b, plain, job, shape, strip, false, luminance(s.fill) * s.fill.alpha * alpha)
        ret ok
    }
    let bounds = path_bounds(path)
    let (brush, has_brush, brush_error) = gradient_brush(a, doc, s.fill_ref, bounds, bounds, 1.0, s.current)
    if brush_error != ok { ret brush_error }
    if !has_brush { ret ok }
    switch brush {
    case .Solid as c:
        try mask_piece(a, b, plain, job, shape, strip, false, luminance(c) * c.alpha * alpha)
    case .Radial as rad:
        var sum = 0.0f32
        var n = 0usize
        while n < rad.stops.len {
            sum += luminance(rad.stops[n].color) * rad.stops[n].color.alpha
            n += 1usize
        }
        if rad.stops.len > 0usize { try mask_piece(a, b, plain, job, shape, strip, false, sum / f32(rad.stops.len) * alpha) }
    case .Linear as lin:
        let start = geometry.transform_point(frame.ctm, lin.start)
        let stop_point = geometry.transform_point(frame.ctm, lin.end)
        let dx = stop_point.x - start.x
        let dy = stop_point.y - start.y
        let length = math.sqrt[f32](dx * dx + dy * dy)
        let reach = path_bounds(shape)
        let far = reach.width + reach.height + length + 1.0
        if !(length > 0.0001) {
            try mask_piece(a, b, plain, job, shape, strip, false, luminance(color_at(lin.stops, 0.0)) * alpha)
            ret ok
        }
        let nx = 0.0 - dy / length
        let ny = dx / length
        let big = far / length + 1.0
        var j = 0usize
        while j < MASK_STRIPS + 2usize {
            // Strip 0 is the pad before the start, the last one the pad after the end.
            var t0 = 0.0f32 - big
            var t1 = 0.0f32
            var middle = 0.0f32
            if j == MASK_STRIPS + 1usize {
                t0 = 1.0
                t1 = 1.0 + big
                middle = 1.0
            } else if j > 0usize {
                t0 = f32(j - 1usize) / f32(MASK_STRIPS)
                t1 = f32(j) / f32(MASK_STRIPS)
                middle = (t0 + t1) / 2.0
            }
            let c = color_at(lin.stops, middle)
            let p0 = pt(start.x + dx * t0, start.y + dy * t0)
            let p1 = pt(start.x + dx * t1, start.y + dy * t1)
            let (poly, poly_error) = quad_path(a, pt(p0.x + nx * far, p0.y + ny * far), pt(p1.x + nx * far, p1.y + ny * far), pt(p1.x - nx * far, p1.y - ny * far), pt(p0.x - nx * far, p0.y - ny * far))
            if poly_error != ok { ret poly_error }
            try mask_piece(a, b, plain, job, shape, poly, true, luminance(c) * c.alpha * alpha)
            j += 1usize
        }
    }
    ret ok
}

// Draw the element at `source` under the mask element `mask_id`: the mask's content is walked
// in the element's user space, each of its shapes replaying the element under its value. False
// when the mask cannot be applied here (an unknown id, no room for a layer, inside a mask or a
// pattern), and the caller then draws the element unmasked.
fn draw_masked(a: *mem.Arena, b: *scene.Builder, doc: Doc, parent: Frame, frame: Frame, mask_id: str, source: str, anc: []const str, dest: geometry.Rect, level: usize) -> (bool, err) {
    if doc.has_job || level + 1usize >= 8usize { ret (false, ok) }
    if frame.layers >= MAX_LAYERS_SVG || !(doc.view.width > 0.0) { ret (false, ok) }
    let m = find_by_id(doc.text, mask_id)
    if !m.found || !same(name_of(m.tag), "mask") { ret (false, ok) }
    var job_frame = parent
    job_frame.style.mask_skip = true
    // The mask's region and content units (L125, D4504): a region is given by `x`, `y`, `width`, `height` or
    // `maskUnits` and clips every piece; box units and a content in box fractions need the element's box.
    var content_ctm = frame.ctm
    var region: geometry.Path = zero
    var has_region = false
    let (units_text, has_units) = attr(m.tag, "maskUnits")
    let (content_text, has_content) = attr(m.tag, "maskContentUnits")
    let (xs, has_x) = attr(m.tag, "x")
    let (ys, has_y) = attr(m.tag, "y")
    let (ws, has_w) = attr(m.tag, "width")
    let (hs, has_h) = attr(m.tag, "height")
    let region_given = has_x || has_y || has_w || has_h || has_units
    let obb_region = !has_units || !same(trim(units_text), "userSpaceOnUse")
    let obb_content = has_content && same(trim(content_text), "objectBoundingBox")
    if region_given || obb_content {
        let first = source.len > 0usize && source[0usize] == 60u8
        var tag_text = source
        if first { tag_text = source[1usize..tag_end(source, 0usize)] }
        let (box, has_box, box_error) = measure_element(a, doc, parent, tag_text, source, dest, level)
        if box_error != ok { ret (false, box_error) }
        let box_ok = has_box && box.width > 0.0 && box.height > 0.0
        if (obb_content || (region_given && obb_region)) && !box_ok { ret (true, ok) }
        if region_given {
            var rx = 0.0f32 - 0.1 * doc.vw
            var ry = 0.0f32 - 0.1 * doc.vh
            var rw = 1.2f32 * doc.vw
            var rh = 1.2f32 * doc.vh
            if obb_region {
                var fx = 0.0f32 - 0.1
                var fy = 0.0f32 - 0.1
                var fw = 1.2f32
                var fh = 1.2f32
                if has_x { fx = fraction_of(xs, fx) }
                if has_y { fy = fraction_of(ys, fy) }
                if has_w { fw = fraction_of(ws, fw) }
                if has_h { fh = fraction_of(hs, fh) }
                rx = box.x + fx * box.width
                ry = box.y + fy * box.height
                rw = fw * box.width
                rh = fh * box.height
            } else {
                if has_x { rx = length_value(xs, rx, doc.vw) }
                if has_y { ry = length_value(ys, ry, doc.vh) }
                if has_w { rw = length_value(ws, rw, doc.vw) }
                if has_h { rh = length_value(hs, rh, doc.vh) }
            }
            if !(rw > 0.0) || !(rh > 0.0) { ret (true, ok) }
            let (rect, rect_error) = rect_path(a, rx, ry, rw, rh, 0.0, 0.0)
            if rect_error != ok { ret (false, rect_error) }
            let (placed, placed_error) = place_path(a, rect, frame.ctm)
            if placed_error != ok { ret (false, placed_error) }
            region = placed
            has_region = true
        }
        if obb_content {
            content_ctm = geometry.transform_multiply(frame.ctm, geometry.transform_multiply(geometry.transform_translate(box.x, box.y), geometry.transform_scale(box.width, box.height)))
        }
    }
    var job = Job { text: source, frame: job_frame, dest: dest, level: level, anc: anc, region: region, has_region: has_region }
    var inner = doc
    inner.job = &job
    inner.has_job = true
    let content = Frame { style: apply_style(m.tag, default_style(parent.style.current)), ctm: content_ctm, layers: MAX_LAYERS_SVG, opens: false }
    try walk(a, b, inner, doc.text[m.body_start..m.body_end], content, false, dest, level + 1usize)
    ret (true, ok)
}

// Fill and stroke of `path` under the frame, clipped by its clip-path when it has one.
// `fillable` is false for a line, whose fill is never drawn. In a mask's content it adds a piece.
fn emit(a: *mem.Arena, b: *scene.Builder, doc: Doc, frame: Frame, path: geometry.Path, fillable: bool, level: usize) -> err {
    if doc.has_job { ret emit_mask_piece(a, b, doc, frame, path, fillable) }
    let s = frame.style
    let fill_alpha = s.opacity * s.fill_opacity
    let stroke_alpha = s.opacity * s.stroke_opacity
    let bounds = path_bounds(path)
    let reach = geometry.rect(bounds.x - s.stroke_width, bounds.y - s.stroke_width, bounds.width + 2.0 * s.stroke_width, bounds.height + 2.0 * s.stroke_width)
    let save: scene.Command = .Save
    try scene.push(b, save)
    if s.clip_ref.len > 0usize {
        let (clip, has_clip, clip_error) = clip_path(a, doc, s.clip_ref, s.clip_ctm)
        if clip_error != ok { ret clip_error }
        if has_clip { try scene.push(b, scene.Command { Clip: scene.Clip { Path: clip } }) }
    }
    try scene.push(b, scene.Command { Transform: frame.ctm })
    if fillable && s.fill_on && fill_alpha > 0.0 {
        var shape = path
        if s.even_odd {
            let (wound, wound_error) = even_odd_path(a, path)
            if wound_error != ok { ret wound_error }
            shape = wound
        }
        if s.fill_ref.len > 0usize {
            let pat = find_by_id(doc.text, s.fill_ref)
            if pat.found && same(name_of(pat.tag), "pattern") {
                try fill_pattern(a, b, doc, s, shape, bounds, pat, level)
            } else {
                let (brush, has_brush, brush_error) = gradient_brush(a, doc, s.fill_ref, bounds, bounds, fill_alpha, s.current)
                if brush_error != ok { ret brush_error }
                if has_brush {
                    var drawn = false
                    switch brush {
                    case .Radial as rad:
                        let (focus, has_focus) = focus_of(doc, s.fill_ref, bounds)
                        if has_focus {
                            let (done, focal_error) = focal_fill(a, b, shape, rad, focus)
                            if focal_error != ok { ret focal_error }
                            drawn = done
                        }
                    default:
                        drawn = false
                    }
                    if !drawn { try scene.push(b, scene.Command { FillPath: scene.FillPath { path: shape, brush: brush } }) }
                }
            }
        } else {
            try scene.push(b, scene.Command { FillPath: scene.FillPath { path: shape, brush: paint.Brush { Solid: color_with(s.fill, fill_alpha) } } })
        }
    }
    if s.stroke_on && s.stroke_width > 0.0 && stroke_alpha > 0.0 {
        var brush = paint.Brush { Solid: color_with(s.stroke, stroke_alpha) }
        var draw_stroke = true
        if s.stroke_ref.len > 0usize {
            let (made, has_made, made_error) = gradient_brush(a, doc, s.stroke_ref, bounds, reach, stroke_alpha, s.current)
            if made_error != ok { ret made_error }
            draw_stroke = has_made
            if has_made { brush = made }
        }
        var cut = path
        if draw_stroke && s.dash.len > 0usize {
            var dashes: [16]f32 = zero
            let n = dash_values(s.dash, dashes[0usize..16usize])
            if n > 0usize {
                let (dashed, dashed_error) = dash_path(a, path, dashes[0usize..n], s.dash_offset)
                if dashed_error != ok { ret dashed_error }
                cut = dashed
            }
        }
        if draw_stroke {
            try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: cut, brush: brush, stroke: paint.Stroke { width: s.stroke_width, cap: s.cap, join: s.join, miter_limit: s.miter } } })
        }
    }
    try draw_markers(a, b, doc, s, path, level)
    let restore: scene.Command = .Restore
    try scene.push(b, restore)
    ret ok
}

// ---- filter effects (L125, D4503) --------------------------------------------------------------------

// The bounds of the geometry in a display list in the space it was drawn in: fills and the paths of strokes
// (without their widths), text boxes and images. False for a list that draws nothing.
fn list_bounds(list: scene.DisplayList) -> (geometry.Rect, bool) {
    var stack: [32]geometry.Transform = zero
    var depth = 0usize
    var t = geometry.transform_identity()
    var x0 = 0.0f32
    var y0 = 0.0f32
    var x1 = 0.0f32
    var y1 = 0.0f32
    var any = false
    var i = 0usize
    while i < list.commands.len {
        let c = list.commands[i]
        var box = geometry.rect(0.0, 0.0, 0.0, 0.0)
        var has = false
        if c.tag == .Save || c.tag == .OpacityLayer {
            if depth < 32usize {
                stack[depth] = t
                depth += 1usize
            }
        } else if c.tag == .Restore {
            if depth > 0usize {
                depth -= 1usize
                t = stack[depth]
            }
        } else {
            switch c {
            case .Transform as m:
                t = geometry.transform_multiply(t, m)
            case .FillRect as fill:
                box = fill.rect
                has = true
            case .FillPath as fill:
                box = path_bounds(fill.path)
                has = true
            case .StrokePath as stroke:
                box = path_bounds(stroke.path)
                has = true
            case .Image as picture:
                box = picture.destination
                has = true
            case .Text as text:
                let tb = text.layout.bounds
                box = geometry.rect(text.origin.x + tb.x, text.origin.y + tb.y, tb.width, tb.height)
                has = true
            default:
                has = false
            }
        }
        if has {
            let r = scene.transform_rect(t, box)
            if !any {
                x0 = r.x
                y0 = r.y
                x1 = r.x + r.width
                y1 = r.y + r.height
                any = true
            } else {
                if r.x < x0 { x0 = r.x }
                if r.y < y0 { y0 = r.y }
                if r.x + r.width > x1 { x1 = r.x + r.width }
                if r.y + r.height > y1 { y1 = r.y + r.height }
            }
        }
        i += 1usize
    }
    ret (geometry.rect(x0, y0, x1 - x0, y1 - y0), any)
}

// A fraction: a number, or a percentage as hundredths.
fn fraction_of(value: str, fallback: f32) -> f32 {
    var at = 0usize
    var v = fallback
    if !read_number(value, &at, &v) { ret fallback }
    if at < value.len && value[at] == 37u8 { ret v / 100.0 }
    ret v
}

// An input reference of a primitive: the source, its alpha, nothing, or the index of an earlier result.
fn input_ref(raw: str, name: str, n: usize, names: []const str) -> i32 {
    let (value, has) = attr(raw, name)
    var fallback = sf.in_source()
    if n > 0usize { fallback = i32(n - 1usize) }
    if !has { ret fallback }
    let v = trim(value)
    if same(v, "SourceGraphic") { ret sf.in_source() }
    if same(v, "SourceAlpha") { ret sf.in_alpha() }
    if same(v, "BackgroundImage") || same(v, "BackgroundAlpha") || same(v, "FillPaint") || same(v, "StrokePaint") { ret sf.in_empty() }
    var k = n
    while k > 0usize {
        k -= 1usize
        if names[k].len > 0usize && same(names[k], v) { ret i32(k) }
    }
    ret fallback
}

fn blend_mode_of(value: str) -> u32 {
    let v = trim(value)
    if same(v, "multiply") { ret 1u32 }
    if same(v, "screen") { ret 2u32 }
    if same(v, "darken") { ret 3u32 }
    if same(v, "lighten") { ret 4u32 }
    if same(v, "overlay") { ret 5u32 }
    if same(v, "color-dodge") { ret 6u32 }
    if same(v, "color-burn") { ret 7u32 }
    if same(v, "hard-light") { ret 8u32 }
    if same(v, "soft-light") { ret 9u32 }
    if same(v, "difference") { ret 10u32 }
    if same(v, "exclusion") { ret 11u32 }
    if same(v, "hue") { ret 12u32 }
    if same(v, "saturation") { ret 13u32 }
    if same(v, "color") { ret 14u32 }
    if same(v, "luminosity") { ret 15u32 }
    ret 0u32
}

fn composite_op_of(value: str) -> u32 {
    let v = trim(value)
    if same(v, "in") { ret 1u32 }
    if same(v, "out") { ret 2u32 }
    if same(v, "atop") { ret 3u32 }
    if same(v, "xor") { ret 4u32 }
    if same(v, "arithmetic") { ret 5u32 }
    ret 0u32
}

// `flood-color` and `flood-opacity` of a primitive as straight RGBA.
fn flood_into(raw: str, current: paint.Color, p: []f32, at: usize) {
    var c = paint.rgba(0.0, 0.0, 0.0, 1.0)
    let (color, has_color) = prop(raw, "flood-color")
    if has_color {
        let (parsed, kind) = parse_paint(color, current)
        if kind == 1u8 { c = parsed } else { c = paint.rgba(0.0, 0.0, 0.0, 0.0) }
    }
    var o = 1.0f32
    let (opacity, has_opacity) = prop(raw, "flood-opacity")
    if has_opacity { o = unit_value(number_of(opacity, 1.0)) }
    p[at] = c.red
    p[at + 1usize] = c.green
    p[at + 2usize] = c.blue
    p[at + 3usize] = c.alpha * o
}

// `stdDeviation`-style pair: "x" or "x y".
fn pair_of(value: str, fallback: f32) -> (f32, f32) {
    var at = 0usize
    var x = fallback
    var y = fallback
    if !read_number(value, &at, &x) { ret (fallback, fallback) }
    y = x
    let got = read_number(value, &at, &y)
    ret (x, y)
}

// A filter element's primitives as a program over `w` x `h` pixels whose origin is device pixel (px0, py0).
// `region` is the filter region and `box` the element's bounding box, both in user space, `device` the
// user-to-device transform, `prim_obb` whether primitive units are the bounding box's fractions.
fn filter_prims(doc: Doc, f: Found, region: geometry.Rect, box: geometry.Rect, prim_obb: bool, device: geometry.Transform, current: paint.Color, px0: i64, py0: i64, w: usize, h: usize, out: []sf.Prim) -> usize {
    let text = doc.text
    var names: [16]str = zero
    var n = 0usize
    let scale_x = math.sqrt[f32](device.m00 * device.m00 + device.m10 * device.m10)
    let scale_y = math.sqrt[f32](device.m01 * device.m01 + device.m11 * device.m11)
    var linear = true
    let (own_space, has_space) = prop(f.tag, "color-interpolation-filters")
    if has_space && (same(trim(own_space), "sRGB") || same(trim(own_space), "auto")) { linear = false }
    var i = f.body_start
    while i < f.body_end && n < sf.MAX_PRIMS {
        if text[i] != 60u8 {
            i += 1usize
            continue
        }
        if begins(text, i, "<!--") {
            i = find(text, i + 4usize, "-->") + 3usize
            continue
        }
        let end = tag_end(text, i)
        if i + 1usize < text.len && (text[i + 1usize] == 47u8 || text[i + 1usize] == 33u8 || text[i + 1usize] == 63u8) {
            i = end + 1usize
            continue
        }
        let raw = text[i + 1usize..end]
        let name = name_of(raw)
        let self_closing = raw.len > 0usize && raw[raw.len - 1usize] == 47u8
        var next = end + 1usize
        if !self_closing { next = element_end(text, end, name, false) }
        if begins(name, 0usize, "fe") && !same(name, "feMergeNode") {
            var p: sf.Prim = zero
            p.x0 = 0i32
            p.y0 = 0i32
            p.x1 = i32(w)
            p.y1 = i32(h)
            p.in1 = input_ref(raw, "in", n, names[0usize..16usize])
            p.in2 = input_ref(raw, "in2", n, names[0usize..16usize])
            p.linear = linear
            let (space, has_prim_space) = prop(raw, "color-interpolation-filters")
            if has_prim_space { p.linear = !(same(trim(space), "sRGB") || same(trim(space), "auto")) }
            // Lengths in primitive units, as user-space numbers: fractions of the box when asked.
            var unit_x = 1.0f32
            var unit_y = 1.0f32
            if prim_obb {
                unit_x = box.width
                unit_y = box.height
            }
            if same(name, "feGaussianBlur") {
                p.kind = sf.KIND_BLUR
                let (dev, has_dev) = attr(raw, "stdDeviation")
                var sx = 0.0f32
                var sy = 0.0f32
                if has_dev {
                    let (px, py) = pair_of(dev, 0.0)
                    sx = px
                    sy = py
                }
                if sx < 0.0 { sx = 0.0 }
                if sy < 0.0 { sy = 0.0 }
                p.p[0usize] = sx * unit_x * scale_x
                p.p[1usize] = sy * unit_y * scale_y
            } else if same(name, "feOffset") {
                p.kind = sf.KIND_OFFSET
                let dx = first_number(raw, "dx", 0.0) * unit_x
                let dy = first_number(raw, "dy", 0.0) * unit_y
                p.p[0usize] = device.m00 * dx + device.m01 * dy
                p.p[1usize] = device.m10 * dx + device.m11 * dy
            } else if same(name, "feFlood") {
                p.kind = sf.KIND_FLOOD
                flood_into(raw, current, p.p[0usize..20usize], 0usize)
            } else if same(name, "feBlend") {
                p.kind = sf.KIND_BLEND
                let (mode, has_mode) = attr(raw, "mode")
                if has_mode { p.mode = blend_mode_of(mode) }
            } else if same(name, "feComposite") {
                p.kind = sf.KIND_COMPOSITE
                let (op, has_op) = attr(raw, "operator")
                if has_op { p.mode = composite_op_of(op) }
                p.p[0usize] = first_number(raw, "k1", 0.0)
                p.p[1usize] = first_number(raw, "k2", 0.0)
                p.p[2usize] = first_number(raw, "k3", 0.0)
                p.p[3usize] = first_number(raw, "k4", 0.0)
            } else if same(name, "feColorMatrix") {
                p.kind = sf.KIND_MATRIX
                let (kind, has_kind) = attr(raw, "type")
                let (values, has_values) = attr(raw, "values")
                var m = 0u32
                if has_kind {
                    let k = trim(kind)
                    if same(k, "saturate") { m = 1u32 } else if same(k, "hueRotate") { m = 2u32 } else if same(k, "luminanceToAlpha") { m = 3u32 }
                }
                p.mode = m
                if m == 1u32 { p.p[0usize] = 1.0 }
                if has_values {
                    if m == 0u32 {
                        var at = 0usize
                        var count = 0usize
                        var v = 0.0f32
                        while count < 20usize && read_number(values, &at, &v) {
                            p.p[count] = v
                            count += 1usize
                        }
                        if count != 20usize {
                            // Not twenty numbers: the identity.
                            var z = 0usize
                            while z < 20usize {
                                p.p[z] = 0.0
                                z += 1usize
                            }
                            p.p[0usize] = 1.0
                            p.p[6usize] = 1.0
                            p.p[12usize] = 1.0
                            p.p[18usize] = 1.0
                        }
                    } else {
                        p.p[0usize] = number_of(values, p.p[0usize])
                    }
                } else if m == 0u32 {
                    p.p[0usize] = 1.0
                    p.p[6usize] = 1.0
                    p.p[12usize] = 1.0
                    p.p[18usize] = 1.0
                }
            } else if same(name, "feMerge") {
                p.kind = sf.KIND_MERGE
                var j = end + 1usize
                while j < next && p.merge_n < 8usize {
                    if text[j] != 60u8 {
                        j += 1usize
                        continue
                    }
                    let inner_end = tag_end(text, j)
                    let inner = text[j + 1usize..inner_end]
                    if begins(inner, 0usize, "feMergeNode") {
                        p.merge[p.merge_n] = input_ref(inner, "in", n, names[0usize..16usize])
                        p.merge_n += 1usize
                    }
                    j = inner_end + 1usize
                }
            } else if same(name, "feDropShadow") {
                p.kind = sf.KIND_SHADOW
                let dx = first_number(raw, "dx", 2.0) * unit_x
                let dy = first_number(raw, "dy", 2.0) * unit_y
                p.p[0usize] = device.m00 * dx + device.m01 * dy
                p.p[1usize] = device.m10 * dx + device.m11 * dy
                let (dev, has_dev) = attr(raw, "stdDeviation")
                var sx = 2.0f32
                var sy = 2.0f32
                if has_dev {
                    let (px, py) = pair_of(dev, 2.0)
                    sx = px
                    sy = py
                }
                if sx < 0.0 { sx = 0.0 }
                if sy < 0.0 { sy = 0.0 }
                p.p[2usize] = sx * unit_x * scale_x
                p.p[3usize] = sy * unit_y * scale_y
                flood_into(raw, current, p.p[0usize..20usize], 4usize)
            } else {
                p.kind = sf.KIND_PASS
            }
            // The subregion: x, y, width and height override the filter region's.
            let (xs, has_x) = attr(raw, "x")
            let (ys, has_y) = attr(raw, "y")
            let (ws, has_w) = attr(raw, "width")
            let (hs, has_h) = attr(raw, "height")
            if has_x || has_y || has_w || has_h {
                var sr = region
                if prim_obb {
                    if has_x { sr.x = box.x + fraction_of(xs, 0.0) * box.width }
                    if has_y { sr.y = box.y + fraction_of(ys, 0.0) * box.height }
                    if has_w { sr.width = fraction_of(ws, 1.0) * box.width }
                    if has_h { sr.height = fraction_of(hs, 1.0) * box.height }
                } else {
                    if has_x { sr.x = length_value(xs, sr.x, doc.vw) }
                    if has_y { sr.y = length_value(ys, sr.y, doc.vh) }
                    if has_w { sr.width = length_value(ws, sr.width, doc.vw) }
                    if has_h { sr.height = length_value(hs, sr.height, doc.vh) }
                }
                let dr = scene.transform_rect(device, sr)
                p.x0 = i32(i64(math.floor[f32](dr.x)) - px0)
                p.y0 = i32(i64(math.floor[f32](dr.y)) - py0)
                p.x1 = i32(i64(math.ceil[f32](dr.x + dr.width)) - px0)
                p.y1 = i32(i64(math.ceil[f32](dr.y + dr.height)) - py0)
            }
            let (result, has_result) = attr(raw, "result")
            if has_result { names[n] = trim(result) }
            out[n] = p
            n += 1usize
        }
        i = next
    }
    ret n
}

// The element at `source`'s geometry box in the user space it establishes (the space inside its own
// `transform`): the element is walked under the inverse of that transform, without filters, masks or layers,
// and the display list's bounds taken. False when there is no geometry or the transform cannot be inverted.
fn measure_element(a: *mem.Arena, doc: Doc, parent: Frame, tag: str, source: str, dest: geometry.Rect, level: usize) -> (geometry.Rect, bool, err) {
    var local = geometry.transform_identity()
    let (own_transform, has_own) = attr(tag, "transform")
    if has_own {
        let (inverse, invertible) = invert(parse_transform(own_transform))
        if !invertible { ret (geometry.rect(0.0, 0.0, 0.0, 0.0), false, ok) }
        local = inverse
    }
    var plain = doc
    plain.has_host = false
    var measure = parent
    measure.ctm = local
    measure.layers = MAX_LAYERS_SVG
    measure.style.filter_skip = true
    measure.style.mask_skip = true
    measure.style.opacity = 1.0
    let (measured, measured_error) = scene.builder(a, 4096usize)
    if measured_error != ok { ret (geometry.rect(0.0, 0.0, 0.0, 0.0), false, measured_error) }
    var mb = measured
    let walked = walk(a, &mb, plain, source, measure, false, dest, level + 1usize)
    if walked != ok { ret (geometry.rect(0.0, 0.0, 0.0, 0.0), false, walked) }
    let (box, has_box) = list_bounds(scene.finish(&mb))
    ret (box, has_box, ok)
}

// Draw the element at `source` (its tag and everything inside it) through the filter `filter_id`. The first
// answer is false when it cannot be filtered here (a replay, no host, no room) and the caller draws it plain; an
// unknown filter, or an empty box for box units, draws nothing, as the specification says.
fn draw_filtered_element(a: *mem.Arena, b: *scene.Builder, doc: Doc, parent: Frame, frame: Frame, tag: str, filter_id: str, source: str, dest: geometry.Rect, level: usize) -> (bool, err) {
    if !doc.has_host || doc.has_job || level + 1usize >= 8usize || frame.layers >= MAX_LAYERS_SVG || !(doc.view.width > 0.0) { ret (false, ok) }
    let f = find_by_id(doc.text, filter_id)
    if !f.found || !same(name_of(f.tag), "filter") { ret (true, ok) }
    let host = doc.host
    let device = geometry.transform_multiply(*doc.fit, frame.ctm)
    let (fit_inverse, fit_ok) = invert(*doc.fit)
    if !fit_ok { ret (true, ok) }
    let mark = mem.mark(a)
    var plain = doc
    plain.has_host = false
    let (box, has_box, box_error) = measure_element(a, doc, parent, tag, source, dest, level)
    if box_error != ok { ret (false, box_error) }
    var obb = true
    let (units, has_units) = attr(f.tag, "filterUnits")
    if has_units && same(trim(units), "userSpaceOnUse") { obb = false }
    var region = geometry.rect(0.0, 0.0, 0.0, 0.0)
    let (rxs, has_rx) = attr(f.tag, "x")
    let (rys, has_ry) = attr(f.tag, "y")
    let (rws, has_rw) = attr(f.tag, "width")
    let (rhs, has_rh) = attr(f.tag, "height")
    if obb {
        if !has_box || !(box.width > 0.0) || !(box.height > 0.0) {
            mem.reset(a, mark)
            ret (true, ok)
        }
        var fx = 0.0f32 - 0.1
        var fy = 0.0f32 - 0.1
        var fw = 1.2f32
        var fh = 1.2f32
        if has_rx { fx = fraction_of(rxs, fx) }
        if has_ry { fy = fraction_of(rys, fy) }
        if has_rw { fw = fraction_of(rws, fw) }
        if has_rh { fh = fraction_of(rhs, fh) }
        region = geometry.rect(box.x + fx * box.width, box.y + fy * box.height, fw * box.width, fh * box.height)
    } else {
        var rx = 0.0f32 - 0.1 * doc.vw
        var ry = 0.0f32 - 0.1 * doc.vh
        var rw = 1.2f32 * doc.vw
        var rh = 1.2f32 * doc.vh
        if has_rx { rx = length_value(rxs, rx, doc.vw) }
        if has_ry { ry = length_value(rys, ry, doc.vh) }
        if has_rw { rw = length_value(rws, rw, doc.vw) }
        if has_rh { rh = length_value(rhs, rh, doc.vh) }
        region = geometry.rect(rx, ry, rw, rh)
    }
    if !(region.width > 0.0) || !(region.height > 0.0) {
        mem.reset(a, mark)
        ret (true, ok)
    }
    // The region in device pixels, clipped to the target.
    let dev = scene.transform_rect(device, region)
    var px0 = i64(math.floor[f32](dev.x))
    var py0 = i64(math.floor[f32](dev.y))
    var px1 = i64(math.ceil[f32](dev.x + dev.width))
    var py1 = i64(math.ceil[f32](dev.y + dev.height))
    if px0 < 0i64 { px0 = 0i64 }
    if py0 < 0i64 { py0 = 0i64 }
    if px1 > i64(host.width) { px1 = i64(host.width) }
    if py1 > i64(host.height) { py1 = i64(host.height) }
    if px1 <= px0 || py1 <= py0 {
        mem.reset(a, mark)
        ret (true, ok)
    }
    let w = usize(px1 - px0)
    let h = usize(py1 - py0)
    if w * h > host.max_pixels {
        mem.reset(a, mark)
        ret (true, TooComplex)
    }
    // The result's texture first, so its pixels sit below the scratch that is reset when this is done.
    mem.reset(a, mark)
    let (slot, slot_error) = sf.reserve(a, host, w, h)
    if slot_error != ok { ret (true, slot_error) }
    let scratch_mark = mem.mark(a)
    // The source graphic into a scratch target of that size.
    let (made, made_error) = scene.builder(a, 4096usize)
    if made_error != ok { ret (false, made_error) }
    var sb = made
    let save: scene.Command = .Save
    let restore: scene.Command = .Restore
    try scene.push(&sb, save)
    try scene.push(&sb, scene.Command { Transform: geometry.transform_multiply(geometry.transform_translate(f32(0i64 - px0), f32(0i64 - py0)), *doc.fit) })
    var content = parent
    content.style.filter_skip = true
    content.style.opacity = 1.0
    try walk(a, &sb, plain, source, content, false, dest, level + 1usize)
    try scene.push(&sb, restore)
    let (pixels, pixels_error) = mem.alloc[f32](a, w * h * 4usize)
    if pixels_error != ok { ret (false, pixels_error) }
    var registered: [16]fonts.Font = zero
    var nreg = 0usize
    if doc.faces.len > 0usize {
        while nreg < doc.faces.len && nreg < 16usize {
            registered[nreg] = doc.faces[nreg].font
            nreg += 1usize
        }
    } else if doc.has_font {
        registered[0usize] = doc.font
        nreg = 1usize
    }
    try sf.render_pixels(a, host, scene.finish(&sb), w, h, registered[0usize..nreg], pixels)
    var prim_obb = false
    let (prim_units, has_prim_units) = attr(f.tag, "primitiveUnits")
    if has_prim_units && same(trim(prim_units), "objectBoundingBox") { prim_obb = true }
    var prims: [16]sf.Prim = zero
    let count = filter_prims(doc, f, region, box, prim_obb, device, frame.style.current, px0, py0, w, h, prims[0usize..16usize])
    let (result, result_error) = mem.alloc[f32](a, w * h * 4usize)
    if result_error != ok { ret (false, result_error) }
    try sf.run(a, prims[0usize..count], pixels, w, h, result)
    let fill_error = sf.fill(host, slot, result, w, h)
    if fill_error != ok { ret (true, fill_error) }
    mem.reset(a, scratch_mark)
    // Drawn in device space, then clipped by the element's own clip path.
    try scene.push(b, save)
    let (clip_text, has_clip_prop) = prop(tag, "clip-path")
    if has_clip_prop && url_id(clip_text).len > 0usize {
        let (clip, has_clip, clip_error) = clip_path(a, doc, url_id(clip_text), frame.ctm)
        if clip_error != ok { ret (true, clip_error) }
        if has_clip { try scene.push(b, scene.Command { Clip: scene.Clip { Path: clip } }) }
    }
    try scene.push(b, scene.Command { Transform: fit_inverse })
    try scene.push(b, scene.Command { Image: scene.DrawImage { texture: slot.id, source: geometry.rect(0.0, 0.0, f32(w), f32(h)), destination: geometry.rect(f32(px0), f32(py0), f32(w), f32(h)), opacity: frame.style.opacity } })
    try scene.push(b, restore)
    ret (true, ok)
}

fn child_of(tag: str, parent: Frame) -> Frame {
    let (value, found) = attr(tag, "transform")
    var ctm = parent.ctm
    if found { ctm = geometry.transform_multiply(parent.ctm, parse_transform(value)) }
    var style = apply_style(tag, parent.style)
    style.mask_skip = false
    style.filter_skip = false
    // The element being filtered: its own opacity and clip apply to the filter's result, not its source.
    if parent.style.filter_skip { style.opacity = parent.style.opacity }
    let (clip, has_clip) = prop(tag, "clip-path")
    if has_clip && !parent.style.filter_skip {
        // The clip is in the user space of the element that names it.
        style.clip_ref = url_id(clip)
        style.clip_ctm = ctm
    }
    ret Frame { style: style, ctm: ctm, layers: parent.layers, opens: false }
}

// Opens an opacity layer for the element's own `opacity` when it is below one and there is room,
// moving that opacity out of the frame (it keeps what its ancestors left). The caller closes the
// layer with a Restore when `frame.opens`.
fn open_layer(b: *scene.Builder, doc: Doc, tag: str, parent: Frame, frame: *Frame) -> err {
    let (value, has_value) = prop(tag, "opacity")
    if !has_value { ret ok }
    let own = unit_value(number_of(value, 1.0))
    if own >= 1.0 || frame.layers >= MAX_LAYERS_SVG || !(doc.view.width > 0.0) || doc.has_job || parent.style.filter_skip { ret ok }
    // A shape with one paint needs no layer: its opacity multiplies into that paint's alpha exactly
    // as the layer would (the NeperOS shell's icons carry such opacities, and a full-view layer per
    // element costs a render target the guest's arena does not have).
    let element = name_of(tag)
    let container = same(element, "g") || same(element, "svg") || same(element, "use") || same(element, "a") || same(element, "switch")
    if !container && !(frame.style.fill_on && frame.style.stroke_on) { ret ok }
    frame.style.opacity = parent.style.opacity
    frame.layers += 1usize
    frame.opens = true
    try scene.push(b, scene.Command { OpacityLayer: scene.OpacityLayer { bounds: doc.view, opacity: own } })
    ret ok
}

fn skipped(name: str) -> bool {
    ret same(name, "defs") || same(name, "title") || same(name, "desc") || same(name, "metadata") || same(name, "style") || same(name, "clipPath") || same(name, "mask") || same(name, "linearGradient") || same(name, "radialGradient") || same(name, "pattern") || same(name, "symbol") || same(name, "filter") || same(name, "marker") || same(name, "text") || same(name, "script")
}

// The viewBox as a rectangle in the root user space, else the width and height from the origin.
fn view_of(text: str) -> geometry.Rect {
    let open = find(text, 0usize, "<svg")
    if open >= text.len { ret geometry.rect(0.0, 0.0, 0.0, 0.0) }
    let tag = text[open + 1usize..tag_end(text, open)]
    let (view, has_view) = attr(tag, "viewBox")
    if has_view {
        var at = 0usize
        var vx = 0.0f32
        var vy = 0.0f32
        var vw = 0.0f32
        var vh = 0.0f32
        if read_number(view, &at, &vx) && read_number(view, &at, &vy) && read_number(view, &at, &vw) && read_number(view, &at, &vh) && vw > 0.0 && vh > 0.0 { ret geometry.rect(vx, vy, vw, vh) }
    }
    let w = length_of(tag, "width")
    let h = length_of(tag, "height")
    if w > 0.0 && h > 0.0 { ret geometry.rect(0.0, 0.0, w, h) }
    ret geometry.rect(0.0, 0.0, 0.0, 0.0)
}

// The document's own size: the viewBox's width and height, else the `width` and `height`.
fn size(text: str) -> (f32, f32, bool) {
    let r = view_of(text)
    if r.width > 0.0 && r.height > 0.0 { ret (r.width, r.height, true) }
    ret (0.0, 0.0, false)
}

fn default_style(current: paint.Color) -> Style {
    ret Style { fill: paint.rgba(0.0, 0.0, 0.0, 1.0), fill_on: true, stroke: paint.rgba(0.0, 0.0, 0.0, 1.0), stroke_on: false, stroke_width: 1.0, cap: paint.StrokeCap.Butt, join: paint.StrokeJoin.Miter, miter: 4.0, opacity: 1.0, fill_opacity: 1.0, stroke_opacity: 1.0, current: current, fill_ref: "", stroke_ref: "", clip_ref: "", clip_ctm: geometry.transform_identity(), dash: "", dash_offset: 0.0, even_odd: false, marker_start: "", marker_mid: "", marker_end: "", mask_skip: false, filter_skip: false, font_size: 16.0, anchor: 0usize, font_family: "", font_weight: 400u32, font_italic: false }
}

// Draw `text` into `b`, fitted to `dest`. `current` is what `currentColor` and an unset
// `color` mean. The commands are balanced -- one outer Save/Restore, one pair per shape.
// `<text>` is not drawn (see `draw_with_font`).
fn draw(a: *mem.Arena, b: *scene.Builder, text: str, dest: geometry.Rect, current: paint.Color) -> err {
    var font: fonts.Font = zero
    ret draw_with(a, b, text, dest, current, font, false)
}

// As `draw`, with `<text>` set in `font` through `e.text.layout` (the caller registers the font
// with the renderer). `font-size`, `text-anchor`, `x`, `y` and `fill` are read; a `tspan` with an
// `x` or `y` of its own starts a new chunk, any other joins the text of its parent.
fn draw_with_font(a: *mem.Arena, b: *scene.Builder, text: str, dest: geometry.Rect, current: paint.Color, font: fonts.Font) -> err {
    ret draw_with(a, b, text, dest, current, font, true)
}

// As `draw_with_font`, with filter effects (L125, D4503): an element naming `filter="url(#id)"` is drawn
// through the `<filter>` element's primitives -- `feGaussianBlur`, `feOffset`, `feFlood`, `feBlend`,
// `feComposite`, `feColorMatrix`, `feMerge` and `feDropShadow` -- by rendering it into a scratch target as
// big as its filter region (clipped to the host's target), running the primitives over those pixels
// (`e.gfx.svg_filter`) and drawing the result as an image of the host's renderer. `dest` must be in target
// pixels (nothing pushed around the call); the host's renderer needs a texture slot per filtered element,
// freed by `svg_filter.release` after the scene has been rendered. Each filtered element takes working
// memory from `a` only while it is processed.
fn draw_filtered(a: *mem.Arena, b: *scene.Builder, text: str, dest: geometry.Rect, current: paint.Color, font: fonts.Font, has_font: bool, host: *sf.Host) -> err {
    var none: [1]Face = zero
    ret draw_core(a, b, text, dest, current, font, has_font, none[0usize..0usize], host, true)
}

// As `draw_filtered`, with `<text>` set in the face its `font-family`, `font-weight` and `font-style` choose
// from `faces` (L125, D4504): the family names are tried in order without regard to case, the nearest weight
// of the matching family wins (an italic mismatch costs more than any weight gap), and with no match the first
// face is used; the other faces are the fallbacks for glyphs the chosen one lacks. The caller registers every
// face's font with the renderer.
fn draw_filtered_faces(a: *mem.Arena, b: *scene.Builder, text: str, dest: geometry.Rect, current: paint.Color, faces: []const Face, host: *sf.Host) -> err {
    var font: fonts.Font = zero
    if faces.len > 0usize { font = faces[0usize].font }
    ret draw_core(a, b, text, dest, current, font, faces.len > 0usize, faces, host, true)
}

// Text on faces without filter effects.
fn draw_with_faces(a: *mem.Arena, b: *scene.Builder, text: str, dest: geometry.Rect, current: paint.Color, faces: []const Face) -> err {
    var nowhere: sf.Host = zero
    var font: fonts.Font = zero
    if faces.len > 0usize { font = faces[0usize].font }
    ret draw_core(a, b, text, dest, current, font, faces.len > 0usize, faces, &nowhere, false)
}

fn draw_with(a: *mem.Arena, b: *scene.Builder, text: str, dest: geometry.Rect, current: paint.Color, font: fonts.Font, has_font: bool) -> err {
    var nowhere: sf.Host = zero
    var none: [1]Face = zero
    ret draw_core(a, b, text, dest, current, font, has_font, none[0usize..0usize], &nowhere, false)
}

fn draw_core(a: *mem.Arena, b: *scene.Builder, text: str, dest: geometry.Rect, current: paint.Color, font: fonts.Font, has_font: bool, faces: []const Face, host: *sf.Host, has_host: bool) -> err {
    let (vw, vh, has_size) = size(text)
    var nothing: [1]str = zero
    var blank: Job = zero
    var fit = geometry.transform_identity()
    let doc = Doc { text: text, vw: vw, vh: vh, view: view_of(text), job: &blank, has_job: false, font: font, has_font: has_font, base_anc: nothing[0usize..0usize], fit: &fit, host: host, has_host: has_host, faces: faces }
    let first = Frame { style: default_style(current), ctm: geometry.transform_identity(), layers: 0usize, opens: false }
    ret walk(a, b, doc, text, first, true, dest, 0usize)
}

// ---- text (L125, D3701) ---------------------------------------------------------------------

type Chunk = struct { x: f32, y: f32, text: str }

// The first number of a coordinate list attribute, else `fallback`.
fn first_number(tag: str, name: str, fallback: f32) -> f32 {
    let (value, found) = attr(tag, name)
    if !found { ret fallback }
    ret length_value(value, fallback, 0.0)
}

// Appends `piece` with entities decoded and whitespace runs folded to one space (a space is not
// written at the start of a chunk or twice running).
fn push_text(sb: *str.Builder, piece: str, last_space: *bool) -> err {
    var i = 0usize
    while i < piece.len {
        let c = piece[i]
        if is_space(c) {
            if !*last_space {
                try str.push(sb, " ")
                *last_space = true
            }
            i += 1usize
            continue
        }
        *last_space = false
        if c == 38u8 {
            var j = i + 1usize
            while j < piece.len && piece[j] != 59u8 && j - i < 8usize { j += 1usize }
            if j < piece.len && piece[j] == 59u8 {
                let name = piece[i + 1usize..j]
                if same(name, "amp") {
                    try str.push(sb, "&")
                } else if same(name, "lt") {
                    try str.push(sb, "<")
                } else if same(name, "gt") {
                    try str.push(sb, ">")
                } else if same(name, "quot") {
                    try str.push(sb, "\"")
                } else if same(name, "apos") {
                    try str.push(sb, "'")
                } else {
                    try str.push(sb, piece[i..j + 1usize])
                }
                i = j + 1usize
                continue
            }
        }
        try str.push(sb, piece[i..i + 1usize])
        i += 1usize
    }
    ret ok
}

// The layout style for `s`: the face `font-family`, `font-weight` and `font-style` choose from the caller's
// faces first (as `doc.font` when there are none), then the other faces as fallbacks for missing glyphs.
fn text_style(doc: Doc, s: Style, buf: []layout.FontChoice) -> layout.Style {
    var n = 1usize
    buf[0usize] = layout.FontChoice { font: doc.font, size: s.font_size }
    if doc.faces.len > 0usize {
        let pick = pick_face(doc.faces, s.font_family, s.font_weight, s.font_italic)
        buf[0usize] = layout.FontChoice { font: doc.faces[pick].font, size: s.font_size }
        var f = 0usize
        while f < doc.faces.len && n < buf.len {
            if f != pick {
                buf[n] = layout.FontChoice { font: doc.faces[f].font, size: s.font_size }
                n += 1usize
            }
            f += 1usize
        }
    }
    ret layout.Style { fonts: buf[0usize..n], language: "", line_height: 0.0 }
}

// The advance width of `content` as one line; its layout is not kept.
fn text_width(a: *mem.Arena, content: str, style: layout.Style, options: layout.Options) -> (f32, err) {
    if content.len == 0usize { ret (0.0, ok) }
    let m = mem.mark(a)
    let (laid, laid_error) = layout.layout(a, content, style, options)
    if laid_error != ok { ret (0.0, laid_error) }
    let w = laid.bounds.width
    mem.reset(a, m)
    ret (w, ok)
}

// The advance of `content`, trailing spaces counted at `space` each.
fn prefix_width(a: *mem.Arena, content: str, space: f32, style: layout.Style, options: layout.Options) -> (f32, err) {
    var end = content.len
    var spaces = 0usize
    while end > 0usize && content[end - 1usize] == 32u8 {
        end -= 1usize
        spaces += 1usize
    }
    let (base, base_error) = text_width(a, content[0usize..end], style, options)
    if base_error != ok { ret (0.0, base_error) }
    ret (base + f32(spaces) * space, ok)
}

// `<textPath>` (L125, D4504): each character of `content` is set on the path the element's `href` names, its
// advance taken from the shaped prefix (so kerning counts), centred on the arc length where its middle falls
// (from `startOffset`, shifted by `text-anchor`) and turned to the path's tangent there; a character whose
// middle is off either end of the path is not drawn. The first subpath of the path is used, flattened.
fn draw_path_text(a: *mem.Arena, b: *scene.Builder, doc: Doc, frame: Frame, tp_tag: str, content: str) -> err {
    if !doc.has_font { ret ok }
    let s = apply_style(tp_tag, frame.style)
    let fill_alpha = s.opacity * s.fill_opacity
    if !s.fill_on || !(fill_alpha > 0.0) || !(s.font_size > 0.0) { ret ok }
    let (plain_ref, has_plain) = attr(tp_tag, "href")
    let (linked_ref, has_linked) = attr(tp_tag, "xlink:href")
    var reference = plain_ref
    if !has_plain { reference = linked_ref }
    let linked_element = find_by_id(doc.text, url_id(reference))
    if !linked_element.found { ret ok }
    let (shape, has_shape, shape_error) = shape_path(a, doc, linked_element.tag, name_of(linked_element.tag))
    if shape_error != ok { ret shape_error }
    if !has_shape { ret ok }
    var place = frame.ctm
    let (transform_text, has_transform) = attr(linked_element.tag, "transform")
    if has_transform { place = geometry.transform_multiply(frame.ctm, parse_transform(transform_text)) }
    let (flat, flat_error) = flat_of(a, shape)
    if flat_error != ok { ret flat_error }
    let (pts, pts_error) = mem.alloc[geometry.Point](a, flat.points.len + 1usize)
    if pts_error != ok { ret pts_error }
    let (lens, lens_error) = mem.alloc[f32](a, flat.points.len + 1usize)
    if lens_error != ok { ret lens_error }
    var n = 0usize
    var pi = 0usize
    var vi = 0usize
    var first: geometry.Point = zero
    var done = false
    while vi < flat.verbs.len && !done {
        let verb = flat.verbs[vi]
        if verb == .Move {
            if n > 0usize {
                done = true
            } else {
                pts[0usize] = flat.points[pi]
                first = pts[0usize]
                n = 1usize
                pi += 1usize
            }
        } else if verb == .Line {
            pts[n] = flat.points[pi]
            n += 1usize
            pi += 1usize
        } else {
            if n > 0usize {
                pts[n] = first
                n += 1usize
            }
            done = true
        }
        vi += 1usize
    }
    if n < 2usize { ret ok }
    lens[0usize] = 0.0
    var k = 1usize
    while k < n {
        lens[k] = lens[k - 1usize] + geometry.distance(pts[k - 1usize], pts[k])
        k += 1usize
    }
    let total = lens[n - 1usize]
    if !(total > 0.0) { ret ok }
    // The text: whitespace folded, entities decoded.
    let (made, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret builder_error }
    var sb = made
    var last_space = true
    try push_text(&sb, content, &last_space)
    var text = str.done(&sb)
    if text.len > 0usize && text[text.len - 1usize] == 32u8 { text = text[0usize..text.len - 1usize] }
    if text.len == 0usize { ret ok }
    var choices: [8]layout.FontChoice = zero
    let style = text_style(doc, s, choices[0usize..8usize])
    let options = layout.Options { width: 0.0, max_lines: 0u32, align: layout.Align.Start, wrap: layout.Wrap.None, ellipsis: "", notdef: true }
    // A layout's width leaves trailing spaces out, so a prefix's is its text before them plus that many spaces.
    let (nn, nn_error) = text_width(a, "nn", style, options)
    if nn_error != ok { ret nn_error }
    let (n_n, n_n_error) = text_width(a, "n n", style, options)
    if n_n_error != ok { ret n_n_error }
    let space_advance = n_n - nn
    let (whole, whole_error) = prefix_width(a, text, space_advance, style, options)
    if whole_error != ok { ret whole_error }
    var begin = 0.0f32
    let (offset_text, has_offset) = attr(tp_tag, "startOffset")
    if has_offset {
        var at = 0usize
        var v = 0.0f32
        if read_number(offset_text, &at, &v) {
            if at < offset_text.len && offset_text[at] == 37u8 { begin = total * v / 100.0 } else { begin = v }
        }
    }
    if s.anchor == 1usize { begin = begin - whole / 2.0 }
    if s.anchor == 2usize { begin = begin - whole }
    let save: scene.Command = .Save
    let restore: scene.Command = .Restore
    var i0 = 0usize
    while i0 < text.len {
        var i1 = i0 + 1usize
        while i1 < text.len && (text[i1] & 192u8) == 128u8 { i1 += 1usize }
        let (before, before_error) = prefix_width(a, text[0usize..i0], space_advance, style, options)
        if before_error != ok { ret before_error }
        let (after, after_error) = prefix_width(a, text[0usize..i1], space_advance, style, options)
        if after_error != ok { ret after_error }
        let advance = after - before
        let centre = begin + before + advance / 2.0
        if text[i0] != 32u8 && centre >= 0.0 && centre <= total {
            var seg = 1usize
            while seg + 1usize < n && lens[seg] < centre { seg += 1usize }
            let span = lens[seg] - lens[seg - 1usize]
            var t = 0.0f32
            if span > 0.0 { t = (centre - lens[seg - 1usize]) / span }
            let p0 = pts[seg - 1usize]
            let p1 = pts[seg]
            let px = p0.x + (p1.x - p0.x) * t
            let py = p0.y + (p1.y - p0.y) * t
            let angle = math.atan2[f32](p1.y - p0.y, p1.x - p0.x)
            let (laid, laid_error) = layout.layout(a, text[i0..i1], style, options)
            if laid_error != ok { ret laid_error }
            if laid.lines.len == 1usize {
                let (held, held_error) = mem.alloc[layout.Layout](a, 1usize)
                if held_error != ok { ret held_error }
                held[0usize] = laid
                try scene.push(b, save)
                try scene.push(b, scene.Command { Transform: geometry.transform_multiply(place, geometry.transform_multiply(geometry.transform_translate(px, py), geometry.transform_rotate(angle))) })
                try scene.push(b, scene.Command { Text: scene.DrawText { layout: &held[0usize], origin: pt(0.0 - advance / 2.0, 0.0 - laid.lines[0usize].baseline), brush: paint.Brush { Solid: color_with(s.fill, fill_alpha) } } })
                try scene.push(b, restore)
            }
        }
        i0 = i1
    }
    ret ok
}

// Draw one `<text>` element: its chunks, each a one-line layout set at its anchor.
fn draw_text(a: *mem.Arena, b: *scene.Builder, doc: Doc, frame: Frame, tag: str, body: str) -> err {
    if !doc.has_font { ret ok }
    let s = frame.style
    let fill_alpha = s.opacity * s.fill_opacity
    if !s.fill_on || !(fill_alpha > 0.0) || !(s.font_size > 0.0) { ret ok }
    let x = first_number(tag, "x", 0.0) + first_number(tag, "dx", 0.0)
    let y = first_number(tag, "y", 0.0) + first_number(tag, "dy", 0.0)
    var chunks: [16]Chunk = zero
    var count = 0usize
    let (made, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret builder_error }
    var sb = made
    var last_space = true
    var from = 0usize
    var i = 0usize
    var pending_x = x
    var pending_y = y
    while true {
        var at_end = i >= body.len
        if !at_end && body[i] != 60u8 {
            i += 1usize
            continue
        }
        try push_text(&sb, body[from..i], &last_space)
        if at_end { break }
        let end = tag_end(body, i)
        let inner = body[i + 1usize..end]
        if begins(inner, 0usize, "tspan") {
            let (x_text, has_x) = attr(inner, "x")
            let (y_text, has_y) = attr(inner, "y")
            if has_x || has_y {
                // A positioned span ends the chunk so far and starts another.
                let so_far = str.done(&sb)
                if so_far.len > 0usize && count < 16usize {
                    chunks[count] = Chunk { x: pending_x, y: pending_y, text: so_far }
                    count += 1usize
                }
                if has_x { pending_x = length_value(x_text, 0.0, doc.vw) }
                if has_y { pending_y = length_value(y_text, 0.0, doc.vh) }
                let (again, again_error) = str.builder(a, 0usize)
                if again_error != ok { ret again_error }
                sb = again
                last_space = true
            }
        }
        if begins(inner, 0usize, "textPath") {
            // Text on a path: its content is set along the path the element names and is not a chunk.
            var close = find(body, end + 1usize, "</textPath")
            try draw_path_text(a, b, doc, frame, inner, body[end + 1usize..close])
            var resume = close
            if close < body.len { resume = tag_end(body, close) + 1usize }
            from = resume
            i = resume
            continue
        }
        from = end + 1usize
        i = end + 1usize
    }
    let tail = str.done(&sb)
    if tail.len > 0usize && count < 16usize {
        chunks[count] = Chunk { x: pending_x, y: pending_y, text: tail }
        count += 1usize
    }
    var choices: [8]layout.FontChoice = zero
    let style = text_style(doc, s, choices[0usize..8usize])
    let options = layout.Options { width: 0.0, max_lines: 0u32, align: layout.Align.Start, wrap: layout.Wrap.None, ellipsis: "", notdef: true }
    let save: scene.Command = .Save
    let restore: scene.Command = .Restore
    var c = 0usize
    while c < count {
        var content = chunks[c].text
        // The whitespace fold can leave one space at the end of a chunk; it takes no part.
        if content.len > 0usize && content[content.len - 1usize] == 32u8 { content = content[0usize..content.len - 1usize] }
        if content.len > 0usize {
            let (laid, laid_error) = layout.layout(a, content, style, options)
            if laid_error != ok { ret laid_error }
            if laid.lines.len == 1usize {
                let (held, held_error) = mem.alloc[layout.Layout](a, 1usize)
                if held_error != ok { ret held_error }
                held[0usize] = laid
                var origin_x = chunks[c].x
                if s.anchor == 1usize { origin_x = origin_x - laid.bounds.width / 2.0 }
                if s.anchor == 2usize { origin_x = origin_x - laid.bounds.width }
                try scene.push(b, save)
                try scene.push(b, scene.Command { Transform: frame.ctm })
                try scene.push(b, scene.Command { Text: scene.DrawText { layout: &held[0usize], origin: pt(origin_x, chunks[c].y - laid.lines[0usize].baseline), brush: paint.Brush { Solid: color_with(s.fill, fill_alpha) } } })
                try scene.push(b, restore)
            }
        }
        c += 1usize
    }
    ret ok
}

// The index just past the element whose open tag ends at `end`: its matching close tag counting
// nested elements of the same name, or `end + 1` for a self-closing one.
fn element_end(text: str, end: usize, name: str, self_closing: bool) -> usize {
    if self_closing { ret end + 1usize }
    var depth = 1usize
    var j = end + 1usize
    while j < text.len {
        if text[j] != 60u8 {
            j += 1usize
            continue
        }
        let close = tag_end(text, j)
        if j + 1usize < text.len && text[j + 1usize] == 47u8 {
            if same(name_of(text[j + 2usize..close]), name) {
                depth -= 1usize
                if depth == 0usize { ret close + 1usize }
            }
        } else if j + 1usize < text.len && text[j + 1usize] != 33u8 && text[j + 1usize] != 63u8 {
            let inner = text[j + 1usize..close]
            if same(name_of(inner), name) && !(inner.len > 0usize && inner[inner.len - 1usize] == 47u8) { depth += 1usize }
        }
        j = close + 1usize
    }
    ret text.len
}

fn sib_push(list: []str, n: *usize, tag: str) {
    if *n >= list.len {
        var k = 1usize
        while k < list.len {
            list[k - 1usize] = list[k]
            k += 1usize
        }
        *n = list.len - 1usize
    }
    list[*n] = tag
    *n += 1usize
}

// One pass over the elements of `text` (the document, or the part a `use` names) from
// `first`. `root` is the document pass, which opens at `<svg>` and fits it to `dest`.
fn walk(a: *mem.Arena, b: *scene.Builder, doc: Doc, text: str, first: Frame, root: bool, dest: geometry.Rect, level: usize) -> err {
    var frames: [16]Frame = zero
    frames[0usize] = first
    // The open elements' raw tags (for selectors): what a replay was started under, then each
    // group opened here; and at each depth the siblings seen so far.
    var anc: [28]str = zero
    var anc_n = 0usize
    while anc_n < doc.base_anc.len && anc_n < 8usize {
        anc[anc_n] = doc.base_anc[anc_n]
        anc_n += 1usize
    }
    var sib: [16][8]str = zero
    var sib_n: [16]usize = zero
    var depth = 0usize
    var opened = !root
    var i = 0usize
    let restore: scene.Command = .Restore
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
        let tag_start = i
        let end = tag_end(text, i)
        if i + 1usize < text.len && text[i + 1usize] == 47u8 {
            let closing = name_of(text[i + 2usize..end])
            if (same(closing, "g") || same(closing, "a") || same(closing, "svg")) && depth > 0usize {
                if frames[depth].opens { try scene.push(b, restore) }
                depth -= 1usize
                if anc_n > 0usize { anc_n -= 1usize }
            }
            i = end + 1usize
            continue
        }
        let raw = text[i + 1usize..end]
        let name = name_of(raw)
        let self_closing = raw.len > 0usize && raw[raw.len - 1usize] == 47u8
        i = end + 1usize
        if same(name, "text") && opened && !self_closing {
            let text_end = element_end(text, end, name, false)
            var body_end = text_end
            while body_end > end + 1usize && text[body_end - 1usize] != 60u8 { body_end -= 1usize }
            if body_end > end + 1usize { body_end -= 1usize }
            let (tag, tag_error) = styled(a, doc, raw, anc[0usize..anc_n], sib[depth][0usize..sib_n[depth]])
            if tag_error != ok { ret tag_error }
            sib_push(sib[depth][0usize..8usize], &sib_n[depth], raw)
            if !doc.has_job {
                let frame = child_of(tag, frames[depth])
                try draw_text(a, b, doc, frame, tag, text[end + 1usize..body_end])
            }
            i = text_end
            continue
        }
        if skipped(name) {
            sib_push(sib[depth][0usize..8usize], &sib_n[depth], raw)
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
        let (tag, tag_error) = styled(a, doc, raw, anc[0usize..anc_n], sib[depth][0usize..sib_n[depth]])
        if tag_error != ok { ret tag_error }
        if same(name, "svg") {
            if !opened {
                opened = true
                anc[anc_n] = raw
                anc_n += 1usize
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
                var fx = 0.5f32
                var fy = 0.5f32
                var stretch = false
                var slice = false
                let (aspect, has_aspect) = attr(tag, "preserveAspectRatio")
                if has_aspect {
                    if find(aspect, 0usize, "none") < aspect.len { stretch = true }
                    if find(aspect, 0usize, "xMin") < aspect.len { fx = 0.0 }
                    if find(aspect, 0usize, "xMax") < aspect.len { fx = 1.0 }
                    if find(aspect, 0usize, "YMin") < aspect.len { fy = 0.0 }
                    if find(aspect, 0usize, "YMax") < aspect.len { fy = 1.0 }
                    if find(aspect, 0usize, "slice") < aspect.len { slice = true }
                }
                var scale_x = dest.width / vw
                var scale_y = dest.height / vh
                if !stretch {
                    var scale = scale_x
                    if slice { if scale_y > scale { scale = scale_y } } else { if scale_y < scale { scale = scale_y } }
                    scale_x = scale
                    scale_y = scale
                }
                let fit = geometry.transform_multiply(geometry.transform_translate(dest.x + (dest.width - vw * scale_x) * fx, dest.y + (dest.height - vh * scale_y) * fy), geometry.transform_multiply(geometry.transform_scale(scale_x, scale_y), geometry.transform_translate(0.0 - vx, 0.0 - vy)))
                *doc.fit = fit
                let save: scene.Command = .Save
                try scene.push(b, save)
                if slice { try scene.push(b, scene.Command { Clip: scene.Clip { Rect: dest } }) }
                try scene.push(b, scene.Command { Transform: fit })
            } else {
                if depth + 1usize >= MAX_DEPTH { ret TooComplex }
                sib_push(sib[depth][0usize..8usize], &sib_n[depth], raw)
                if !self_closing {
                    frames[depth + 1usize] = child_of(tag, frames[depth])
                    depth += 1usize
                    anc[anc_n] = raw
                    anc_n += 1usize
                    sib_n[depth] = 0usize
                }
            }
            continue
        }
        if !opened { continue }
        sib_push(sib[depth][0usize..8usize], &sib_n[depth], raw)
        var frame = child_of(tag, frames[depth])
        // A filter draws the element's whole source through its primitives, before clip, mask and opacity.
        let (filter_text, has_filter) = prop(tag, "filter")
        if has_filter && !frames[depth].style.filter_skip && url_id(filter_text).len > 0usize {
            let filter_end = element_end(text, end, name, self_closing)
            let (filtered, filter_error) = draw_filtered_element(a, b, doc, frames[depth], frame, tag, url_id(filter_text), text[tag_start..filter_end], dest, level)
            if filter_error != ok { ret filter_error }
            if filtered {
                i = filter_end
                continue
            }
        }
        // A mask replays the element (its whole source) under each piece of the mask's content.
        let (mask_text, has_mask) = prop(tag, "mask")
        if has_mask && !frames[depth].style.mask_skip && url_id(mask_text).len > 0usize {
            let span_end = element_end(text, end, name, self_closing)
            let (applied, mask_error) = draw_masked(a, b, doc, frames[depth], frame, url_id(mask_text), text[tag_start..span_end], anc[0usize..anc_n], dest, level)
            if mask_error != ok { ret mask_error }
            if applied {
                i = span_end
                continue
            }
        }
        if same(name, "g") || same(name, "a") {
            if !self_closing {
                if depth + 1usize >= MAX_DEPTH { ret TooComplex }
                try open_layer(b, doc, tag, frames[depth], &frame)
                frames[depth + 1usize] = frame
                depth += 1usize
                anc[anc_n] = raw
                anc_n += 1usize
                sib_n[depth] = 0usize
            }
            continue
        }
        try open_layer(b, doc, tag, frames[depth], &frame)
        if same(name, "use") {
            // `use` draws the element its href names, translated by x and y, under the
            // use element's own style; a symbol contributes its children.
            let (plain, has_plain) = attr(tag, "href")
            let (linked, has_linked) = attr(tag, "xlink:href")
            var reference = plain
            if !has_plain { reference = linked }
            let used_element = find_by_id(doc.text, url_id(reference))
            if (has_plain || has_linked) && used_element.found {
                if level + 1usize >= 8usize { ret TooComplex }
                frame.ctm = geometry.transform_multiply(frame.ctm, geometry.transform_translate(len_x(doc, tag, "x"), len_y(doc, tag, "y")))
                var inner = doc.text[used_element.start..used_element.end]
                if same(name_of(used_element.tag), "symbol") { inner = doc.text[used_element.body_start..used_element.body_end] }
                try walk(a, b, doc, inner, frame, false, dest, level + 1usize)
            }
            if frame.opens { try scene.push(b, restore) }
            continue
        }
        let (path, has_path, path_error) = shape_path(a, doc, tag, name)
        if path_error != ok { ret path_error }
        if has_path {
            // Markers belong to the line-like shapes only.
            if !(same(name, "path") || same(name, "line") || same(name, "polyline") || same(name, "polygon")) {
                frame.style.marker_start = ""
                frame.style.marker_mid = ""
                frame.style.marker_end = ""
            }
            try emit(a, b, doc, frame, path, !same(name, "line"), level)
        }
        if frame.opens { try scene.push(b, restore) }
    }
    if !opened { ret BadSvg }
    while depth > 0usize {
        if frames[depth].opens { try scene.push(b, restore) }
        depth -= 1usize
    }
    if root {
        try scene.push(b, restore)
    }
    ret ok
}
