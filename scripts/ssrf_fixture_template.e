// `e.net.ssrf` against Appdor's own src/io/ssrf-guard.js: scripts/ssrf_vectors.mjs writes one JSON line per case
// (`{"op", ..., "e": answer}`) over URL spellings (integer, hex and octal IPv4, mapped IPv6), literal addresses and resolver
// answers; the fixture computes the same verdict and compares canonical JSON.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.net.ssrf as ssrf
use e.os
use e.str

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn flag_of(v: json.Value, key: str) -> bool {
    let x = ir.value_of(v, key)
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
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

fn strings_of(a: *mem.Arena, v: json.Value) -> []const str {
    let (xs, is_array) = ir.items_of(v)
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { os.exit(85i32) }
    var i = 0usize
    while i < xs.len {
        let (s, is_text) = ir.string_of(xs[i])
        out[i] = s
        i += 1usize
    }
    ret out[0usize..xs.len]
}

fn verdict_json(a: *mem.Arena, v: ssrf.Verdict) -> json.Value {
    var o = obj(a)
    put(&o, "ok", json.Value{ Bool: v.valid })
    if !v.valid {
        put(&o, "error", sv(v.message))
        ret ir.obj_value(&o)
    }
    var shown = v.host
    if str.contains(v.host, ":") { shown = f.join(a, f.join(a, "[", v.host), "]") }
    put(&o, "hostname", sv(shown))
    if v.resolved {
        let (out, e) = mem.alloc[json.Value](a, v.addresses.len + 1usize)
        if e != ok { os.exit(86i32) }
        var i = 0usize
        while i < v.addresses.len {
            out[i] = sv(v.addresses[i])
            i += 1usize
        }
        put(&o, "addresses", json.Value{ Array: out[0usize..v.addresses.len] })
    } else {
        put(&o, "addresses", .Null)
    }
    put(&o, "resolved", json.Value{ Bool: v.resolved })
    ret ir.obj_value(&o)
}

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "sync") { ret verdict_json(a, ssrf.check_url_sync(a, text_of(c, "url"))) }
    if str.eq(op, "full") {
        let lookup = ir.value_of(c, "lookup")
        ret verdict_json(a, ssrf.check_url(a, text_of(c, "url"), flag_of(lookup, "present"), flag_of(lookup, "failed"), strings_of(a, ir.value_of(lookup, "answers"))))
    }
    let ip = text_of(c, "ip")
    var o = obj(a)
    put(&o, "blocked", json.Value{ Bool: ssrf.is_blocked_address(a, ip) })
    put(&o, "reason", sv(ssrf.block_reason(a, ip)))
    ret ir.obj_value(&o)
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let (got, ge) = chain.canonical_json(a, answer(a, c))
    let (want, we) = chain.canonical_json(a, ir.value_of(c, "e"))
    if ge != ok || we != ok { ret false }
    if !str.eq(got, want) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", got), f.join(a, "\nWANT ", want)))
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
    try io.print("net ssrf ok")
    ret ok
}
