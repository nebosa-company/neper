// The `e.algo.formula.sql` compiler and pushdown classifier against appdor's own `src/formula/sql-compiler.js` and
// `pushdown.js`: scripts/formula_sql_reference.mjs compiles formulas (every function at its arities over field and
// literal arguments, operators, nested forms, the date units, the size bound) against one schema and classifies
// them, and records `pushdown|type|oversize|sql (hex)|params` or the classification. The fixture compiles the same
// text with Neper's compiler and must agree. A line is `{"s": formula, "q": 1, "e": outcome}` (`q` 0 turns the
// column quoting off) or `{"c": formula, "e": classification}`.
use e.algo.formula as f
use e.algo.formula.library as library
use e.algo.formula.sql as q
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

fn render_param(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Number { ret f.join(a, "n", f.number_text(a, v.n)) }
    if v.kind == .Text { ret f.join(a, "s", hex_text(a, v.s)) }
    if v.kind == .Bool {
        if v.n != 0.0f64 { ret "b1" }
        ret "b0"
    }
    ret "_"
}

fn render(a: *mem.Arena, r: q.Compiled) -> str {
    var out = f.join3(a, r.pushdown, "|", r.value_type)
    if r.oversize { out = f.join(a, out, "|1|") } else { out = f.join(a, out, "|0|") }
    out = f.join(a, out, hex_text(a, r.sql))
    out = f.join(a, out, "|")
    var i = 0usize
    while i < r.params.len {
        if i > 0usize { out = f.join(a, out, ",") }
        out = f.join(a, out, render_param(a, r.params[i]))
        i += 1usize
    }
    ret out
}

fn render_verdict(a: *mem.Arena, v: q.Verdict) -> str {
    var reason = "-"
    if v.has_reason { reason = v.reason }
    var out = f.join3(a, v.classification, "|", reason)
    out = f.join(a, out, "|")
    var i = 0usize
    while i < v.unsupported.len {
        if i > 0usize { out = f.join(a, out, ",") }
        out = f.join(a, out, v.unsupported[i])
        i += 1usize
    }
    if v.has_unsupported { ret f.join(a, out, "|d") }
    ret f.join(a, out, "|u")
}

fn schema(a: *mem.Arena) -> []q.Column {
    let (cols, e) = mem.alloc[q.Column](a, 11usize)
    if e != ok { os.exit(91i32) }
    cols[0usize] = q.Column { name: "Price", field_type: "number", column: "price" }
    cols[1usize] = q.Column { name: "Qty", field_type: "number", column: "qty" }
    cols[2usize] = q.Column { name: "Name", field_type: "text", column: "name" }
    cols[3usize] = q.Column { name: "Notes", field_type: "longText", column: "notes" }
    cols[4usize] = q.Column { name: "Due", field_type: "date", column: "due" }
    cols[5usize] = q.Column { name: "Done", field_type: "checkbox", column: "done" }
    cols[6usize] = q.Column { name: "Total Cost", field_type: "currency", column: "total_cost" }
    cols[7usize] = q.Column { name: "Rating", field_type: "rating", column: "rating" }
    cols[8usize] = q.Column { name: "Created", field_type: "created_time", column: "created_at" }
    cols[9usize] = q.Column { name: "Tag", field_type: "singleSelect", column: "tag" }
    cols[10usize] = q.Column { name: "We\"ird", field_type: "percent", column: "we\"ird" }
    ret cols
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

fn run(a: *mem.Arena, body: str, reg: *f.Registry, columns: []const q.Column) -> u8 {
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
                let (classify_value, is_classify) = member(members, "c")
                if is_classify {
                    switch classify_value {
                    case .String as s:
                        got = render_verdict(a, q.classify(a, reg, s))
                    default:
                        got = ""
                    }
                } else {
                    var quoted = true
                    let (flag, has_flag) = member(members, "q")
                    if has_flag {
                        switch flag {
                        case .Number as n:
                            if str.eq(n.lexeme, "0") { quoted = false }
                        default:
                            quoted = true
                        }
                    }
                    got = render(a, q.compile_formula(a, reg, text_member(members, "s"), columns, q.Options { double_quote_columns: quoted }))
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
    let columns = schema(a)
    //__VECTOR_CALLS__
    try io.print("algo formula sql ok")
    ret ok
}
