// `e.fmt.css.syntax` against Vaper's own CSS Syntax 3 tokenizer and grammar (css_tokenizer.dart, css_syntax.dart):
// scripts/css_syntax_vectors.mjs builds random CSS from well-formed and malformed fragments, runs Vaper's code over it
// (scripts/css_syntax_reference.dart) and writes `{"src", "e"}` lines. The fixture tokenizes and parses each source and
// compares the canonical text of tokens, rules, declarations and each rule's declarations.
use e.algo.chain as chain
use e.algo.ir as ir
use e.data.list as list
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

fn num(a: *mem.Arena, n: usize) -> json.Value {
    let (v, e) = json.number_from_i64(a, i64(n))
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

fn token_value(a: *mem.Arena, t: syntax.Token) -> json.Value {
    var o = obj(a)
    put(&o, "t", json.Value{ String: syntax.kind_name(t.kind) })
    put(&o, "s", num(a, t.start))
    put(&o, "e", num(a, t.end))
    if t.value.len > 0usize { put(&o, "v", json.Value{ String: t.value }) }
    if t.kind == .Number || t.kind == .Percentage || t.kind == .Dimension {
        var shown = t.number
        if shown == 0.0f64 { shown = 0.0f64 }
        let (n, e) = json.number_from_f64(a, shown)
        if e != ok { os.exit(83i32) }
        put(&o, "nv", json.Value{ Number: n })
        if t.kind != .Number { put(&o, "u", json.Value{ String: t.unit }) }
        if t.integer { put(&o, "i", json.Value{ Bool: true }) }
    }
    if t.hash_id { put(&o, "h", json.Value{ Bool: true }) }
    ret ir.obj_value(&o)
}

fn tokens_value(a: *mem.Arena, ts: []const syntax.Token) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, ts.len + 1usize)
    if e != ok { os.exit(84i32) }
    var at = 0usize
    while at < ts.len {
        out[at] = token_value(a, ts[at])
        at += 1usize
    }
    ret json.Value{ Array: out[0usize..ts.len] }
}

fn block_value(a: *mem.Arena, b: syntax.Block) -> json.Value {
    var o = obj(a)
    put(&o, "o", json.Value{ String: syntax.kind_name(b.open) })
    put(&o, "i", tokens_value(a, b.inner))
    ret ir.obj_value(&o)
}

fn rules_value(a: *mem.Arena, rs: []const syntax.Rule) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, rs.len + 1usize)
    if e != ok { os.exit(85i32) }
    var at = 0usize
    while at < rs.len {
        var o = obj(a)
        if rs[at].at {
            put(&o, "k", json.Value{ String: "a" })
            put(&o, "n", json.Value{ String: rs[at].name })
        } else {
            put(&o, "k", json.Value{ String: "q" })
        }
        put(&o, "p", tokens_value(a, rs[at].prelude))
        if rs[at].has_block || !rs[at].at { put(&o, "b", block_value(a, rs[at].block)) }
        out[at] = ir.obj_value(&o)
        at += 1usize
    }
    ret json.Value{ Array: out[0usize..rs.len] }
}

fn decls_value(a: *mem.Arena, ds: []const syntax.Declaration) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, ds.len + 1usize)
    if e != ok { os.exit(86i32) }
    var at = 0usize
    while at < ds.len {
        var o = obj(a)
        put(&o, "n", json.Value{ String: ds[at].name })
        put(&o, "v", tokens_value(a, ds[at].value))
        put(&o, "i", json.Value{ Bool: ds[at].important })
        out[at] = ir.obj_value(&o)
        at += 1usize
    }
    ret json.Value{ Array: out[0usize..ds.len] }
}

fn run_one(a: *mem.Arena, src: str) -> str {
    let (tokens, te) = syntax.tokenize(a, src)
    if te != ok { os.exit(87i32) }
    let (rules, re) = syntax.parse_rules(a, tokens, true)
    if re != ok { os.exit(88i32) }
    let (decls, de) = syntax.parse_declarations(a, tokens)
    if de != ok { os.exit(89i32) }
    let (made, me) = mem.alloc[json.Value](a, rules.len + 1usize)
    if me != ok { os.exit(90i32) }
    var count = 0usize
    var at = 0usize
    while at < rules.len {
        if !rules[at].at {
            let (inner, ie) = syntax.parse_declarations(a, rules[at].block.inner)
            if ie != ok { os.exit(91i32) }
            made[count] = decls_value(a, inner)
            count += 1usize
        }
        at += 1usize
    }
    var o = obj(a)
    put(&o, "tokens", tokens_value(a, tokens))
    put(&o, "rules", rules_value(a, rules))
    put(&o, "decls", decls_value(a, decls))
    put(&o, "ruleDecls", json.Value{ Array: made[0usize..count] })
    let (text, ce) = chain.canonical_json(a, ir.obj_value(&o))
    if ce != ok { os.exit(92i32) }
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
    try io.print("css syntax ok")
    ret ok
}
