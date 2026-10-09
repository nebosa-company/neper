// The `e.algo.transpile` dialect translator against appdor's own `src/formula/compat`: scripts/
// transpile_reference.mjs translates formulas of every dialect with appdor's `translate` and ranks pasted text
// with its `detectDialect`, and records `status|canonical (hex)|diagnostics` (each `category:message:function`,
// the text hex). The fixture runs the same inputs through Neper's translator and must agree. A line is
// `{"d": dialect, "s": source, "c": [columns], "e": outcome}`, or `{"detect": source, "e": "airtable:3,..."}`.
use e.algo.formula as f
use e.algo.formula.library as library
use e.algo.transpile as t
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn hex_text(a: *mem.Arena, s: str) -> str {
    if s.len == 0usize { ret "_" }
    let (out, e) = mem.alloc[u8](a, s.len * 2usize)
    if e != ok { ret "?" }
    var i = 0usize
    while i < s.len {
        let hi = s[i] >> 4u8
        let lo = s[i] & 15u8
        var h = 48u8 + hi
        if hi > 9u8 { h = 87u8 + hi }
        var l = 48u8 + lo
        if lo > 9u8 { l = 87u8 + lo }
        out[i * 2usize] = h
        out[i * 2usize + 1usize] = l
        i += 1usize
    }
    ret out[0usize..s.len * 2usize]
}

fn render(a: *mem.Arena, r: t.Result) -> str {
    var out = r.status
    if r.has_canonical {
        out = f.join3(a, out, "|", hex_text(a, r.canonical))
    } else {
        out = f.join(a, out, "|-")
    }
    out = f.join(a, out, "|")
    var i = 0usize
    while i < r.diagnostics.len {
        if i > 0usize { out = f.join(a, out, ";") }
        let d = r.diagnostics[i]
        var fn_text = "-"
        if d.has_function { fn_text = hex_text(a, d.function) }
        out = f.join(a, out, f.join3(a, d.category, ":", f.join3(a, hex_text(a, d.message), ":", fn_text)))
        i += 1usize
    }
    ret out
}

fn render_detect(a: *mem.Arena, ranked: []const t.Ranked) -> str {
    var out = ""
    var i = 0usize
    while i < ranked.len {
        if i > 0usize { out = f.join(a, out, ",") }
        out = f.join(a, out, f.join3(a, ranked[i].dialect, ":", f.number_text(a, f64(ranked[i].score))))
        i += 1usize
    }
    ret out
}

fn members_of(v: json.Value) -> []const json.Member {
    var none: []const json.Member = zero
    switch v {
    case .Object as m:
        ret m
    default:
        ret none
    }
}

fn member(members: []const json.Member, key: str) -> (json.Value, bool) {
    var i = 0usize
    while i < members.len {
        if str.eq(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    var null_value: json.Value = .Null
    ret (null_value, false)
}

fn text_member(members: []const json.Member, key: str) -> str {
    let (v, found) = member(members, key)
    if !found { ret "" }
    switch v {
    case .String as s:
        ret s
    default:
        ret ""
    }
}

fn columns_of(a: *mem.Arena, members: []const json.Member) -> []const str {
    var none: []const str = zero
    let (v, found) = member(members, "c")
    if !found { ret none }
    switch v {
    case .Array as items:
        let (out, e) = mem.alloc[str](a, items.len + 1usize)
        if e != ok { ret none }
        var n = 0usize
        var i = 0usize
        while i < items.len {
            switch items[i] {
            case .String as s:
                out[n] = s
                n += 1usize
            default:
                n += 0usize
            }
            i += 1usize
        }
        ret out[0usize..n]
    default:
        ret none
    }
}

fn run(a: *mem.Arena, body: str, reg: *f.Registry) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
            var good = false
            var got = ""
            if parse_error == ok {
                let members = members_of(root)
                let (detect_value, is_detect) = member(members, "detect")
                if is_detect {
                    switch detect_value {
                    case .String as s:
                        got = render_detect(a, t.detect(a, s))
                    default:
                        got = ""
                    }
                } else {
                    let r = t.translate(a, reg, text_member(members, "s"), text_member(members, "d"), columns_of(a, members))
                    got = render(a, r)
                }
                good = str.eq(got, text_member(members, "e"))
            }
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(f.join(a, "\ngot ", got))
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    let (built, build_error) = library.build(a)
    if build_error != ok { os.exit(90i32) }
    var registry = built
    //__VECTOR_CALLS__
    try io.print("algo transpile ok")
    ret ok
}
