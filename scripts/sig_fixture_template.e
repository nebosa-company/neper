// `e.text.sig` against an independent implementation (scripts/sig_vectors.py): rules are rendered from a syntax tree, the
// expected matches come from Python's `re` and its own literal matcher, and the fixture compiles the rule text and scans the
// same bytes -- per rule whether it matched, per string the match count and its first three offsets.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use e.text.sig as sig

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { os.exit(81i32) }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn bv(b: bool) -> json.Value { ret json.Value{ Bool: b } }

fn nv(a: *mem.Arena, n: f64) -> json.Value { ret json.Value{ Number: json.Number{ lexeme: f.number_text(a, n) } } }

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(a: *mem.Arena, h: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, h.len / 2usize + 1usize)
    if e != ok { os.exit(90i32) }
    var i = 0usize
    while i + 1usize < h.len {
        out[i / 2usize] = (nibble(h[i]) << 4u8) | nibble(h[i + 1usize])
        i += 2usize
    }
    ret out[0usize..h.len / 2usize]
}

fn seal(a: *mem.Arena, items: []const json.Value) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, items.len + 1usize)
    if e != ok { os.exit(92i32) }
    var i = 0usize
    while i < items.len {
        out[i] = items[i]
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..items.len] }
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let rules = text_of(c, "rules")
    let data = unhex(a, text_of(c, "h"))
    let want = ir.value_of(c, "e")
    var o = obj(a)
    let (set, ce) = sig.compile(a, rules)
    if ce != ok {
        put(&o, "ok", bv(false))
        if ce == sig.Syntax {
            put(&o, "error", sv("syntax"))
        } else {
            put(&o, "error", sv("limit"))
        }
    } else {
        let (counts, e1) = mem.alloc[u32](a, set.pattern_count + 1usize)
        let (matched, e2) = mem.alloc[bool](a, set.rule_count + 1usize)
        if e1 != ok || e2 != ok { ret false }
        let se = sig.scan(&set, data, counts, matched)
        if se != ok { ret false }
        var v = obj(a)
        var rule_list: [64]json.Value = zero
        var i = 0usize
        while i < set.rule_count {
            rule_list[i] = bv(matched[i])
            i += 1usize
        }
        put(&v, "rules", seal(a, rule_list[0usize..set.rule_count]))
        var count_list: [256]json.Value = zero
        var offs_list: [256]json.Value = zero
        i = 0usize
        while i < set.pattern_count {
            count_list[i] = nv(a, f64(counts[i]))
            var offs: [3]json.Value = zero
            var k = 0usize
            while k < 3usize {
                let (at, has) = sig.nth_match(&set, i, data, k)
                if !has { break }
                offs[k] = nv(a, f64(at))
                k += 1usize
            }
            offs_list[i] = seal(a, offs[0usize..k])
            i += 1usize
        }
        put(&v, "counts", seal(a, count_list[0usize..set.pattern_count]))
        put(&v, "offs", seal(a, offs_list[0usize..set.pattern_count]))
        put(&o, "ok", bv(true))
        put(&o, "v", ir.obj_value(&v))
    }
    let (g, ge) = chain.canonical_json(a, ir.obj_value(&o))
    let (w, we) = chain.canonical_json(a, want)
    if ge != ok || we != ok { ret false }
    if !str.eq(g, w) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", g), f.join(a, "\nWANT ", w)))
        ret false
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
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 60u16 })
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
    try io.print("text sig ok")
    ret ok
}
