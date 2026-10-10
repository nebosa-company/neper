// `e.fmt.css.container` against Vaper's own container-query conditions (container_query.dart): scripts/
// css_container_vectors.mjs writes random condition trees with, per container size, Vaper's three-valued answer
// (`e.e`: true, false or null) and `usesBlockAxis` (`e.block`); the fixture builds the same tree and compares.
use e.algo.ir as ir
use e.fmt.css.container as container
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn number_of(v: json.Value, key: str) -> (f64, bool) {
    let (x, found) = ir.get(v, key)
    if !found { ret (0.0f64, false) }
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        if e == ok { ret (value, true) }
        ret (0.0f64, false)
    default:
        ret (0.0f64, false)
    }
}

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn build(a: *mem.Arena, j: json.Value) -> container.Condition {
    let t = text_of(j, "t")
    if str.eq(t, "and") || str.eq(t, "or") {
        let (ps, is_array) = ir.items_of(ir.value_of(j, "p"))
        let (out, e) = mem.alloc[container.Condition](a, ps.len + 1usize)
        if e != ok { os.exit(80i32) }
        var at = 0usize
        while at < ps.len {
            out[at] = build(a, ps[at])
            at += 1usize
        }
        var kind: container.CondKind = .And
        if str.eq(t, "or") { kind = .Or }
        ret container.Condition { kind: kind, parts: out[0usize..ps.len], feature: .Width, op: .Eq, value: 0.0f64 }
    }
    if str.eq(t, "not") {
        let (out, e) = mem.alloc[container.Condition](a, 1usize)
        if e != ok { os.exit(81i32) }
        out[0] = build(a, ir.value_of(j, "p"))
        ret container.Condition { kind: .Not, parts: out[0usize..1usize], feature: .Width, op: .Eq, value: 0.0f64 }
    }
    if str.eq(t, "unknown") { ret container.unknown_condition() }
    var feature: container.FeatureKind = .Width
    let f = text_of(j, "f")
    if str.eq(f, "height") { feature = .Height }
    if str.eq(f, "aspectRatio") { feature = .AspectRatio }
    if str.eq(f, "orientationPortrait") { feature = .OrientationPortrait }
    if str.eq(f, "orientationLandscape") { feature = .OrientationLandscape }
    var op: container.Op = .Eq
    let o = text_of(j, "o")
    if str.eq(o, "lt") { op = .Lt }
    if str.eq(o, "le") { op = .Le }
    if str.eq(o, "gt") { op = .Gt }
    if str.eq(o, "ge") { op = .Ge }
    let (value, have) = number_of(j, "v")
    ret container.Condition { kind: .Feature, parts: zero, feature: feature, op: op, value: value }
}

fn run_one(a: *mem.Arena, root: json.Value) -> bool {
    let c = build(a, ir.value_of(root, "c"))
    let want = ir.value_of(root, "e")
    let (sizes, sizes_array) = ir.items_of(ir.value_of(root, "sizes"))
    let (answers, answers_array) = ir.items_of(ir.value_of(want, "e"))
    if !sizes_array || !answers_array || sizes.len != answers.len { ret false }
    var block = false
    switch ir.value_of(want, "block") {
    case .Bool as b:
        block = b
    default:
        block = false
    }
    if container.uses_block_axis(c) != block { ret false }
    var at = 0usize
    while at < sizes.len {
        let (w, have_w) = number_of(sizes[at], "w")
        let (h, have_h) = number_of(sizes[at], "h")
        let got = container.evaluate(c, container.Size { has_width: have_w, width: w, has_height: have_h, height: h })
        var ok_answer = false
        switch answers[at] {
        case .Null:
            ok_answer = got == .Unknown
        case .Bool as b:
            if b { ok_answer = got == .True } else { ok_answer = got == .False }
        default:
            ok_answer = false
        }
        if !ok_answer { ret false }
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
            if parse_error != ok || !run_one(a, root) {
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
    try io.print("css container ok")
    ret ok
}
