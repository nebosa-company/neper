// `e.ui.interpolate` against Vaper's own interpolation kernels (interpolate.dart): scripts/ui_interpolate_vectors.mjs
// writes random operations with the Dart answers (`e`, an array of numbers); the fixture computes the same and compares
// within 1e-9 relative, since the two libms need not agree to the last bit.
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use e.ui.interpolate as interp

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

fn reals6(v: json.Value) -> [6]f64 {
    var out: [6]f64 = zero
    let (xs, is_array) = ir.items_of(v)
    var at = 0usize
    while at < 6usize && at < xs.len {
        out[at] = real(xs[at])
        at += 1usize
    }
    ret out
}

fn close(got: f64, want: f64) -> bool {
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

fn check(root: json.Value) -> bool {
    let (ws, is_array) = ir.items_of(field(root, "e"))
    let name = text_of(root, "op")
    var got: [6]f64 = zero
    var count = 1usize
    if str.eq(name, "lerp") {
        got[0] = interp.lerp(real(field(root, "a")), real(field(root, "b")), real(field(root, "t")))
    } else if str.eq(name, "color") {
        let a = u32(real(field(root, "a")))
        let b = u32(real(field(root, "b")))
        got[0] = f64(interp.lerp_color_argb(a, b, real(field(root, "t"))))
    } else if str.eq(name, "bezier") {
        got[0] = interp.cubic_bezier(real(field(root, "x1")), real(field(root, "y1")), real(field(root, "x2")), real(field(root, "y2")), real(field(root, "t")))
    } else if str.eq(name, "affine") {
        got = interp.lerp_affine(reals6(field(root, "a")), reals6(field(root, "b")), real(field(root, "t")))
        count = 6usize
    } else if str.eq(name, "decompose") {
        let d = interp.decompose2d(reals6(field(root, "m")))
        got[0] = d.translate_x
        got[1] = d.translate_y
        got[2] = d.scale_x
        got[3] = d.scale_y
        got[4] = d.angle
        got[5] = d.skew
        count = 6usize
    } else {
        ret false
    }
    if ws.len != count { ret false }
    var at = 0usize
    while at < count {
        if !close(got[at], real(ws[at])) { ret false }
        at += 1usize
    }
    ret true
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
            if parse_error != ok || !check(root) {
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
    try io.print("ui interpolate ok")
    ret ok
}
