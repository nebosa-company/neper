// `e.gfx.cssvalue` against Vaper's own CSS value parsers (value.dart): scripts/css_values_vectors.mjs writes random
// values with the Dart answers (`e`: null, a number, an array of numbers, a text or, for a length, `{v, u, o, p}`); the
// fixture parses each with the Neper module and compares numbers within 1e-9 relative and colours exactly.
use e.algo.ir as ir
use e.fmt.json as json
use e.gfx.cssvalue as css
use e.io
use e.mem
use e.os
use e.str

fn field(v: json.Value, key: str) -> json.Value { ret ir.value_of(v, key) }

fn real(v: json.Value) -> f64 {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e == ok { ret x }
        ret 0.0f64
    default:
        ret 0.0f64
    }
}

fn is_number(v: json.Value) -> bool {
    switch v {
    case .Number as n:
        ret true
    default:
        ret false
    }
}

fn close(got: f64, want: f64) -> bool {
    if got != got && want != want { ret true }
    var scale = 1.0f64
    if want > 1.0f64 || want < -1.0f64 {
        scale = want
        if scale < 0.0f64 { scale = -scale }
    }
    var d = got - want
    if d < 0.0f64 { d = -d }
    ret d <= 1.0e-9f64 * scale
}

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn want_null(v: json.Value) -> bool { ret ir.is_null(v) }

fn bases_of(v: json.Value, include_percent: bool) -> css.Bases {
    var b = css.no_bases()
    let (em, have_em) = ir.get(v, "em")
    if have_em { b.has_em = true
        b.em = real(em) }
    let (rem, have_rem) = ir.get(v, "rem")
    if have_rem { b.has_rem = true
        b.rem = real(rem) }
    let (vw, have_vw) = ir.get(v, "vw")
    if have_vw { b.has_viewport_width = true
        b.viewport_width = real(vw) }
    let (vh, have_vh) = ir.get(v, "vh")
    if have_vh { b.has_viewport_height = true
        b.viewport_height = real(vh) }
    if include_percent {
        let (p, have_p) = ir.get(v, "percent")
        if have_p { b.has_percent = true
            b.percent = real(p) }
    }
    ret b
}

fn unit_name(u: css.LengthUnit) -> str {
    switch u {
    case .Px:
        ret "px"
    case .Pt:
        ret "pt"
    case .Em:
        ret "em"
    case .Rem:
        ret "rem"
    case .Ex:
        ret "ex"
    case .Percent:
        ret "percent"
    case .Vw:
        ret "vw"
    case .Vh:
        ret "vh"
    case .Vmin:
        ret "vmin"
    case .Vmax:
        ret "vmax"
    }
}

fn check_pair(want: json.Value, x: f64, y: f64) -> bool {
    let (xs, is_array) = ir.items_of(want)
    ret is_array && xs.len == 2usize && close(x, real(xs[0])) && close(y, real(xs[1]))
}

fn check(a: *mem.Arena, root: json.Value) -> bool {
    let op = text_of(root, "op")
    let raw = text_of(root, "raw")
    let want = field(root, "e")
    if str.eq(op, "length") {
        let (len, good) = css.parse_length(a, raw, bases_of(field(root, "bases"), false))
        if !good { ret want_null(want) }
        if want_null(want) { ret false }
        if !close(len.value, real(field(want, "v"))) { ret false }
        if !str.eq(unit_name(len.unit), text_of(want, "u")) && len.op == .None { ret false }
        if !close(len.px_offset, real(field(want, "o"))) { ret false }
        let (px, px_ok) = css.to_px(len, bases_of(field(root, "eval"), true))
        let want_px = field(want, "p")
        if !px_ok { ret want_null(want_px) }
        if want_null(want_px) { ret false }
        ret close(px, real(want_px))
    }
    if str.eq(op, "number") {
        let (v, good) = css.parse_css_number(a, raw)
        if !good { ret want_null(want) }
        ret is_number(want) && close(v, real(want))
    }
    if str.eq(op, "angle") {
        let (v, good) = css.parse_css_angle_radians(a, raw)
        if !good { ret want_null(want) }
        ret is_number(want) && close(v, real(want))
    }
    if str.eq(op, "time") {
        let (v, good) = css.parse_css_time_seconds(a, raw)
        if !good { ret want_null(want) }
        ret is_number(want) && close(v, real(want))
    }
    if str.eq(op, "lightdark") {
        var dark = false
        switch field(root, "dark") {
        case .Bool as b:
            dark = b
        default:
            dark = false
        }
        let (picked, good) = css.pick_light_dark(a, raw, dark)
        if !good { ret want_null(want) }
        let (w, is_text) = ir.string_of(want)
        ret is_text && str.eq(w, picked)
    }
    if str.eq(op, "color") {
        let (c, good) = css.parse_color(a, raw)
        if !good { ret want_null(want) }
        ret is_number(want) && f64(c) == real(want)
    }
    if str.eq(op, "mix") || str.eq(op, "contrast") {
        let current = field(root, "current")
        let has_current = is_number(current)
        var cur = 0u32
        if has_current { cur = u32(real(current)) }
        var c = 0u32
        var good = false
        if str.eq(op, "mix") {
            let (v, ok_v) = css.parse_color_mix(a, raw, has_current, cur)
            c = v
            good = ok_v
        } else {
            let (v, ok_v) = css.parse_contrast_color(a, raw, has_current, cur)
            c = v
            good = ok_v
        }
        if !good { ret want_null(want) }
        ret is_number(want) && f64(c) == real(want)
    }
    if str.eq(op, "transform") {
        let (m, good) = css.parse_transform(a, raw)
        if !good { ret want_null(want) }
        let (xs, is_array) = ir.items_of(want)
        if !is_array || xs.len != 6usize { ret false }
        var i = 0usize
        while i < 6usize {
            if !close(m[i], real(xs[i])) { ret false }
            i += 1usize
        }
        ret true
    }
    if str.eq(op, "translatePercent") {
        let (x, y) = css.parse_translate_percent(a, raw)
        ret check_pair(want, x, y)
    }
    if str.eq(op, "origin") {
        let (x, y) = css.parse_transform_origin(a, raw)
        ret check_pair(want, x, y)
    }
    ret false
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
            if parse_error != ok || !check(a, root) {
                let shown = io.print(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("gfx cssvalue ok")
    ret ok
}
