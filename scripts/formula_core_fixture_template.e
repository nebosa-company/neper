// `e.algo.formula` (L026: tokenizer, parser, evaluator, registry, values, dependency graph) against appdor's own
// formula engine, run by scripts/formula_reference.mjs: hand-written formulas over every operator, coercion and
// error path, 450 seeded random formulas, the step and node budgets, sibling formulas and circular references,
// parse diagnostics with their UTF-16 offsets, reference lists, and dependency graphs (cycle and evaluation
// order). The registry holds a small set of test handlers (IF, IFERROR, ISERROR, ISBLANK, TYPEOF, SUM, UPPER,
// LEN, PI, ERROR and the language forms) written to the same contracts as the library's; the library itself is
// checked by its own fixtures. A line is a JSON case with kind `E` (evaluate), `P` (parse) or `G` (graph) and the
// outcome as the reference rendered it: `N|number`, `T|hex`, `B|1`, `_`, `D|iso`, `[..]`, `E|code|hex`.
use e.algo.formula as f
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use e.text.unicode as unicode
use e.text.utf8 as utf8

fn same_text(left: str, right: str) -> bool { ret str.eq(left, right) }

fn member(members: []const json.Member, key: str) -> (json.Value, bool) {
    var none: json.Value = zero
    var i = 0usize
    while i < members.len {
        if same_text(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    ret (none, false)
}

fn get(members: []const json.Member, key: str) -> json.Value {
    let (v, found) = member(members, key)
    ret v
}

// --- the test handlers --------------------------------------------------------------------------------------------

fn h_if(c: *f.Call) -> f.Value {
    let cond = f.eval_node(c, c.nodes[0usize])
    if f.is_error(cond) { ret cond }
    if f.to_bool(cond) { ret f.eval_node(c, c.nodes[1usize]) }
    if c.nodes.len > 2usize { ret f.eval_node(c, c.nodes[2usize]) }
    ret f.boolean(false)
}

fn h_iferror(c: *f.Call) -> f.Value {
    let v = f.eval_node(c, c.nodes[0usize])
    if f.is_error(v) { ret f.eval_node(c, c.nodes[1usize]) }
    ret v
}

fn h_iserror(c: *f.Call) -> f.Value { ret f.boolean(f.is_error(c.args[0usize])) }

fn h_isblank(c: *f.Call) -> f.Value { ret f.boolean(f.is_blank(c.args[0usize])) }

fn h_typeof(c: *f.Call) -> f.Value { ret f.text(f.type_of(c.args[0usize])) }

fn h_sum(c: *f.Call) -> f.Value {
    var numbers: [512]f64 = zero
    let (count, failure) = f.collect_numbers(c.a, c.args, numbers[0..])
    if f.is_error(failure) { ret failure }
    var total = 0.0f64
    var i = 0usize
    while i < count {
        total += numbers[i]
        i += 1usize
    }
    ret f.number(total)
}

fn h_upper(c: *f.Call) -> f.Value {
    let s = f.to_text(c.a, c.args[0usize])
    if f.is_error(s) { ret s }
    let (out, e) = mem.alloc[u8](c.a, s.s.len * 2usize + 4usize)
    if e != ok { ret f.generic_error("Out of memory") }
    var w = 0usize
    var it = utf8.iterator(s.s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            var piece: [4]u8 = zero
            let (width, we) = utf8.encode(unicode.to_upper_simple(scalar), piece[0..])
            var k = 0usize
            while k < usize(width) {
                out[w] = piece[k]
                w += 1usize
                k += 1usize
            }
        }
    }
    ret f.text(out[0usize..w])
}

fn h_len(c: *f.Call) -> f.Value {
    let s = f.to_text(c.a, c.args[0usize])
    if f.is_error(s) { ret s }
    var units = 0usize
    var it = utf8.iterator(s.s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            units += 1usize
            if scalar >= 65536u32 { units += 1usize }
        }
    }
    ret f.number(f64(units))
}

fn h_pi(c: *f.Call) -> f.Value { ret f.number(3.141592653589793f64) }

fn h_error(c: *f.Call) -> f.Value {
    if c.args.len > 0usize {
        let t = f.to_text(c.a, c.args[0usize])
        if f.is_error(t) { ret f.generic_error("Error") }
        ret f.generic_error(t.s)
    }
    ret f.generic_error("Error")
}

fn add(r: *f.Registry, a: *mem.Arena, name: str, aliases: []const str, lazy: bool, pass: bool, low: i32, high: i32, handler: f.Handler) -> err {
    ret f.register(r, a, f.Entry { name: name, key: "", aliases: aliases, category: "test", lazy: lazy, pass_errors: pass, volatile_fn: false, generate_once: false, min_args: low, max_args: high, handler: handler })
}

fn build_registry(a: *mem.Arena) -> f.Registry {
    let (r, e) = f.registry(a, 40usize)
    var reg = r
    var none: []const str = zero
    var upper_aliases: [1]str = zero
    upper_aliases[0usize] = "UPPERCASE"
    var len_aliases: [1]str = zero
    len_aliases[0usize] = "LENGTH"
    if f.register_core(&reg, a) != ok { os.exit(90i32) }
    if add(&reg, a, "IF", none, true, false, 2i32, 3i32, h_if) != ok { os.exit(91i32) }
    if add(&reg, a, "IFERROR", none, true, false, 2i32, 2i32, h_iferror) != ok { os.exit(91i32) }
    if add(&reg, a, "ISERROR", none, false, true, 1i32, 1i32, h_iserror) != ok { os.exit(91i32) }
    if add(&reg, a, "ISBLANK", none, false, true, 1i32, 1i32, h_isblank) != ok { os.exit(91i32) }
    if add(&reg, a, "TYPEOF", none, false, true, 1i32, 1i32, h_typeof) != ok { os.exit(91i32) }
    if add(&reg, a, "SUM", none, false, false, 1i32, -1i32, h_sum) != ok { os.exit(91i32) }
    if add(&reg, a, "UPPER", upper_aliases[0..], false, false, 1i32, 1i32, h_upper) != ok { os.exit(91i32) }
    if add(&reg, a, "LEN", len_aliases[0..], false, false, 1i32, 1i32, h_len) != ok { os.exit(91i32) }
    if add(&reg, a, "PI", none, false, false, 0i32, 0i32, h_pi) != ok { os.exit(91i32) }
    if add(&reg, a, "ERROR", none, false, true, 0i32, 1i32, h_error) != ok { os.exit(91i32) }
    ret reg
}

// --- rendering ----------------------------------------------------------------------------------------------------

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

fn render(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Error { ret f.join(a, f.join(a, f.join(a, "E|", f.code_text(v.code)), "|"), hex_text(a, v.s)) }
    if v.kind == .Blank { ret "_" }
    if v.kind == .Number { ret f.join(a, "N|", f.number_text(a, v.n)) }
    if v.kind == .Text {
        if v.s.len == 0usize { ret "T|_" }
        ret f.join(a, "T|", hex_text(a, v.s))
    }
    if v.kind == .Bool {
        if v.n != 0.0f64 { ret "B|1" }
        ret "B|0"
    }
    if v.kind == .Date { ret f.join(a, "D|", f.date_iso(a, v.n)) }
    var out = "["
    var i = 0usize
    while i < v.items.len {
        if i > 0usize { out = f.join(a, out, ",") }
        out = f.join(a, out, render(a, v.items[i]))
        i += 1usize
    }
    ret f.join(a, out, "]")
}

// --- JSON to values -----------------------------------------------------------------------------------------------

fn value_of(a: *mem.Arena, v: json.Value) -> f.Value {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        ret f.number(x)
    case .String as s:
        ret f.text(s)
    case .Bool as b:
        ret f.boolean(b)
    case .Array as items:
        if items.len == 0usize { ret f.array(f.zero_items()) }
        let (out, e) = mem.alloc[f.Value](a, items.len)
        if e != ok { ret f.blank() }
        var i = 0usize
        while i < items.len {
            out[i] = value_of(a, items[i])
            i += 1usize
        }
        ret f.array(out)
    default:
        ret f.blank()
    }
}

fn text_of(v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    default:
        ret ""
    }
}

fn int_of(v: json.Value) -> usize {
    switch v {
    case .Number as n:
        let (x, e) = json.number_u64(n)
        if e != ok { ret 0usize }
        ret usize(x)
    default:
        ret 0usize
    }
}

fn bool_of(v: json.Value) -> bool {
    switch v {
    case .Bool as b:
        ret b
    default:
        ret false
    }
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

// --- the cases ----------------------------------------------------------------------------------------------------

fn check_evaluate(a: *mem.Arena, c: []const json.Member, reg: *f.Registry) -> bool {
    var ctx: f.Context = zero
    let fields_json = members_of(get(c, "fields"))
    let (fields, fe) = mem.alloc[f.Field](a, fields_json.len + 8usize)
    if fe != ok { ret false }
    var n = 0usize
    var i = 0usize
    while i < fields_json.len {
        fields[n] = f.Field { name: fields_json[i].key, value: value_of(a, fields_json[i].value) }
        n += 1usize
        i += 1usize
    }
    let dates_json = members_of(get(c, "dates"))
    i = 0usize
    while i < dates_json.len {
        let (ms, good) = f.parse_iso(text_of(dates_json[i].value))
        if !good { ret false }
        fields[n] = f.Field { name: dates_json[i].key, value: f.date(ms) }
        n += 1usize
        i += 1usize
    }
    ctx.fields = fields[0usize..n]
    let formulas_json = members_of(get(c, "formulas"))
    if formulas_json.len > 0usize {
        let (formulas, e) = mem.alloc[f.Formula](a, formulas_json.len)
        if e != ok { ret false }
        i = 0usize
        while i < formulas_json.len {
            formulas[i] = f.Formula { name: formulas_json[i].key, source: text_of(formulas_json[i].value) }
            i += 1usize
        }
        ctx.formulas = formulas
    }
    let field_name = text_of(get(c, "fieldName"))
    if field_name.len > 0usize {
        ctx.field_name = field_name
        ctx.has_field_name = true
    }
    ctx.strict_refs = bool_of(get(c, "strict"))
    ctx.max_steps = int_of(get(c, "maxSteps"))
    ctx.max_nodes = int_of(get(c, "maxNodes"))
    let v = f.evaluate(a, text_of(get(c, "src")), &ctx, reg)
    ret same_text(render(a, v), text_of(get(c, "expect")))
}

fn check_parse(a: *mem.Arena, c: []const json.Member) -> bool {
    let src = text_of(get(c, "src"))
    let expect = text_of(get(c, "expect"))
    let (node, diag) = f.parse(a, src, int_of(get(c, "maxNodes")))
    var got = ""
    if diag.good {
        let refs = f.collect_references(a, node)
        var joined = "ok|"
        var i = 0usize
        while i < refs.len {
            if i > 0usize { joined = f.join(a, joined, ",") }
            joined = f.join(a, joined, hex_text(a, refs[i]))
            i += 1usize
        }
        got = joined
    } else {
        var offset = "undefined"
        if diag.offset != f.no_offset() { offset = f.number_text(a, f64(diag.offset)) }
        var flag = "0"
        if diag.complexity { flag = "1" }
        got = f.join(a, f.join(a, f.join(a, f.join(a, "err|", offset), "|"), hex_text(a, diag.message)), f.join(a, "|", flag))
    }
    ret same_text(got, expect)
}

fn names_text(a: *mem.Arena, names: []const str, present: bool) -> str {
    if !present { ret "-" }
    var out = ""
    var i = 0usize
    while i < names.len {
        if i > 0usize { out = f.join(a, out, ",") }
        out = f.join(a, out, hex_text(a, names[i]))
        i += 1usize
    }
    if out.len == 0usize { ret "" }
    ret out
}

fn check_graph(a: *mem.Arena, c: []const json.Member) -> bool {
    let graph_json = members_of(get(c, "graph"))
    var formulas: []f.Formula = zero
    if graph_json.len > 0usize {
        let (storage, e) = mem.alloc[f.Formula](a, graph_json.len)
        if e != ok { ret false }
        formulas = storage
        var i = 0usize
        while i < graph_json.len {
            formulas[i] = f.Formula { name: graph_json[i].key, source: text_of(graph_json[i].value) }
            i += 1usize
        }
    }
    let (cycle, cyclic) = f.detect_cycle(a, formulas)
    let (order, ordered) = f.evaluation_order(a, formulas)
    let got = f.join(a, f.join(a, names_text(a, cycle, cyclic), "|"), names_text(a, order, ordered))
    ret same_text(got, text_of(get(c, "expect")))
}

fn check(a: *mem.Arena, line: str, reg: *f.Registry) -> bool {
    let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 16u16 })
    if parse_error != ok { ret false }
    let c = members_of(root)
    let kind = text_of(get(c, "k"))
    if same_text(kind, "E") { ret check_evaluate(a, c, reg) }
    if same_text(kind, "P") { ret check_parse(a, c) }
    ret check_graph(a, c)
}

fn run(a: *mem.Arena, text: str, reg: *f.Registry) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let mark = mem.mark(a)
            let good = check(a, text[start..i], reg)
            if !good {
                let shown = io.print(text[start..i])
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
    var registry = build_registry(a)
    //__VECTOR_CALLS__
    try io.print("algo formula ok")
    ret ok
}
