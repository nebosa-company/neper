// `e.fmt.css.selector` against Vaper's own selector parser and specificity (selector_parser.dart, selector.dart):
// scripts/css_selector_vectors.mjs builds random selector lists, parses them with Vaper's code
// (scripts/css_selector_reference.dart) and writes `{"src", "e"}` lines. The fixture tokenizes and parses each source
// with the Neper modules and compares the canonical text of the selectors, their combinators, pseudo-elements and
// specificity.
use e.algo.chain as chain
use e.algo.ir as ir
use e.fmt.css.selector as selector
use e.fmt.css.syntax as syntax
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn text_field(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn num(a: *mem.Arena, n: i64) -> json.Value {
    let (v, e) = json.number_from_i64(a, n)
    if e != ok { os.exit(81i32) }
    ret json.Value{ Number: v }
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { os.exit(82i32) }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn simple_value(a: *mem.Arena, s: selector.Simple) -> json.Value {
    var o = obj(a)
    put(&o, "k", json.Value{ String: selector.kind_name(s.kind) })
    put(&o, "n", json.Value{ String: s.name })
    if s.argument.len > 0usize { put(&o, "a", json.Value{ String: s.argument }) }
    if s.attr_ci { put(&o, "i", json.Value{ Bool: true }) }
    if s.subs.len > 0usize { put(&o, "s", selectors_value(a, s.subs)) }
    ret ir.obj_value(&o)
}

fn selector_value(a: *mem.Arena, sel: selector.Selector) -> json.Value {
    let (cs, ce) = mem.alloc[json.Value](a, sel.compounds.len + 1usize)
    let (ks, ke) = mem.alloc[json.Value](a, sel.combinators.len + 1usize)
    if ce != ok || ke != ok { os.exit(83i32) }
    var c = 0usize
    while c < sel.compounds.len {
        let parts = sel.compounds[c].parts
        let (ps, pe) = mem.alloc[json.Value](a, parts.len + 1usize)
        if pe != ok { os.exit(84i32) }
        var p = 0usize
        while p < parts.len {
            ps[p] = simple_value(a, parts[p])
            p += 1usize
        }
        cs[c] = json.Value{ Array: ps[0usize..parts.len] }
        c += 1usize
    }
    var k = 0usize
    while k < sel.combinators.len {
        ks[k] = json.Value{ String: selector.combinator_name(sel.combinators[k]) }
        k += 1usize
    }
    let spec = selector.specificity(sel)
    let (sp, se) = mem.alloc[json.Value](a, 3usize)
    if se != ok { os.exit(85i32) }
    sp[0] = num(a, spec.ids)
    sp[1] = num(a, spec.classes)
    sp[2] = num(a, spec.types)
    var o = obj(a)
    put(&o, "c", json.Value{ Array: cs[0usize..sel.compounds.len] })
    put(&o, "k", json.Value{ Array: ks[0usize..sel.combinators.len] })
    put(&o, "sp", json.Value{ Array: sp[0usize..3usize] })
    ret ir.obj_value(&o)
}

fn selectors_value(a: *mem.Arena, sels: []const selector.Selector) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, sels.len + 1usize)
    if e != ok { os.exit(86i32) }
    var at = 0usize
    while at < sels.len {
        out[at] = selector_value(a, sels[at])
        at += 1usize
    }
    ret json.Value{ Array: out[0usize..sels.len] }
}

fn run_one(a: *mem.Arena, src: str) -> str {
    let (tokens, te) = syntax.tokenize(a, src)
    if te != ok { os.exit(87i32) }
    let (rules, re) = selector.parse_selector_list_for_rule(a, src, tokens)
    if re != ok { os.exit(88i32) }
    let (out, oe) = mem.alloc[json.Value](a, rules.len + 1usize)
    if oe != ok { os.exit(89i32) }
    var at = 0usize
    while at < rules.len {
        var o = obj(a)
        put(&o, "sel", selector_value(a, rules[at].selector))
        if rules[at].has_pseudo { put(&o, "p", json.Value{ String: selector.pseudo_element_name(rules[at].pseudo) }) }
        out[at] = ir.obj_value(&o)
        at += 1usize
    }
    let (text, ce) = chain.canonical_json(a, json.Value{ Array: out[0usize..rules.len] })
    if ce != ok { os.exit(90i32) }
    ret text
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
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                want = text_field(root, "e")
                got = run_one(a, text_field(root, "src"))
                good = str.eq(got, want)
            }
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(join(a, "\ngot ", got))
                let shown_want = io.print(join(a, "\nwant ", want))
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
    try io.print("css selector ok")
    ret ok
}
