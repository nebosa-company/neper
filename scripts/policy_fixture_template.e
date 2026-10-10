// `e.net.policy` against Vaper's own HTTP cache, cookie jar, CORS/CORP/COEP/COOP, CSP, private-network and filter-list code:
// scripts/policy_vectors.mjs writes one JSON line per case (`{"op", ..., "e": answer}`, `e` as the Dart reference gave it);
// the fixture computes the same answer and compares canonical JSON. Time is a fixed millisecond clock.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.net.policy as policy
use e.os
use e.str

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn has_text(v: json.Value, key: str) -> bool {
    let (x, found) = ir.get(v, key)
    if !found { ret false }
    let (s, is_text) = ir.string_of(x)
    ret is_text
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

fn number_of(v: json.Value, key: str) -> i64 {
    let x = ir.value_of(v, key)
    switch x {
    case .Number as n:
        let (value, e) = json.number_i64(n)
        ret value
    default:
        ret 0i64
    }
}

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
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

fn iv(a: *mem.Arena, n: i64) -> json.Value { ret json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(n)) } } }

fn strings_json(a: *mem.Arena, xs: []const str) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
    if e != ok { os.exit(84i32) }
    var i = 0usize
    while i < xs.len {
        out[i] = sv(xs[i])
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..xs.len] }
}

fn strings_of(a: *mem.Arena, v: json.Value) -> []const str {
    let xs = items(v)
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

fn headers_of(a: *mem.Arena, v: json.Value) -> policy.Headers {
    let (members, is_object) = ir.members_of(v)
    let (names, e1) = mem.alloc[str](a, members.len + 1usize)
    let (values, e2) = mem.alloc[str](a, members.len + 1usize)
    var i = 0usize
    while i < members.len {
        names[i] = members[i].key
        let (s, is_text) = ir.string_of(members[i].value)
        values[i] = s
        i += 1usize
    }
    ret policy.Headers { names: names[0usize..members.len], values: values[0usize..members.len] }
}

fn reason_json(r: policy.Reason) -> json.Value {
    if r.blocked { ret sv(r.text) }
    ret .Null
}

fn sources_json(a: *mem.Arena, s: policy.SourceSet) -> json.Value {
    if !s.present { ret .Null }
    ret strings_json(a, s.items)
}

fn bools_json(a: *mem.Arena, xs: []const bool) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
    if e != ok { os.exit(86i32) }
    var i = 0usize
    while i < xs.len {
        out[i] = bv(xs[i])
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..xs.len] }
}

fn nullable_text(has: bool, s: str) -> json.Value {
    if has { ret sv(s) }
    ret .Null
}

fn corp_name(n: i32) -> str {
    if n == 1i32 { ret "sameOrigin" }
    if n == 2i32 { ret "sameSite" }
    if n == 3i32 { ret "crossOrigin" }
    ret "none"
}

fn coep_name(n: i32) -> str {
    if n == 1i32 { ret "requireCorp" }
    if n == 2i32 { ret "credentialless" }
    ret "unsafeNone"
}

fn coop_name(n: i32) -> str {
    if n == 1i32 { ret "sameOrigin" }
    if n == 2i32 { ret "sameOriginAllowPopups" }
    ret "unsafeNone"
}

fn ms_of(v: json.Value, key: str) -> i64 { ret number_of(v, key) }

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "cc") {
        let d = policy.parse_cache_control(a, text_of(c, "value"), has_text(c, "value"))
        var o = obj(a)
        var i = 0usize
        while i < d.names.len {
            put(&o, d.names[i], sv(d.values[i]))
            i += 1usize
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "cacheable") { ret bv(policy.http_is_cacheable(a, number_of(c, "status"), headers_of(a, ir.value_of(c, "headers")))) }
    if str.eq(op, "freshness") {
        let r = policy.http_freshness(a, headers_of(a, ir.value_of(c, "headers")), ms_of(c, "created"), ms_of(c, "now"))
        var o = obj(a)
        put(&o, "fresh", bv(r.fresh))
        put(&o, "must", bv(r.must_revalidate))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "age") { ret iv(a, policy.current_age(headers_of(a, ir.value_of(c, "headers")), ms_of(c, "created"), ms_of(c, "now"))) }
    if str.eq(op, "lifetime") {
        let (v, has) = policy.freshness_lifetime(a, headers_of(a, ir.value_of(c, "headers")), ms_of(c, "now"))
        if !has { ret .Null }
        ret iv(a, v)
    }
    if str.eq(op, "heuristic") {
        let (v, has) = policy.heuristic_lifetime(headers_of(a, ir.value_of(c, "headers")), ms_of(c, "now"))
        if !has { ret .Null }
        ret iv(a, v)
    }
    if str.eq(op, "stale") { ret bv(policy.http_can_serve_stale_on_error(a, headers_of(a, ir.value_of(c, "headers")), ms_of(c, "created"), ms_of(c, "now"))) }
    if str.eq(op, "conditional") {
        let r = policy.conditional_headers(headers_of(a, ir.value_of(c, "headers")))
        var o = obj(a)
        if r.has_none_match { put(&o, "if-none-match", sv(r.if_none_match)) }
        if r.has_modified_since { put(&o, "if-modified-since", sv(r.if_modified_since)) }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "private") { ret bv(policy.is_private_network_host(a, text_of(c, "host"))) }
    if str.eq(op, "filters") {
        let r = policy.parse_filter_list(a, text_of(c, "text"))
        var o = obj(a)
        put(&o, "domains", strings_json(a, r.domains))
        put(&o, "selectors", strings_json(a, r.selectors))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "csp") {
        let p = policy.parse_csp(a, text_of(c, "header"), has_text(c, "header"), text_of(c, "doc"))
        let urls = strings_of(a, ir.value_of(c, "urls"))
        let (b1, e1) = mem.alloc[bool](a, urls.len + 1usize)
        let (b2, e2) = mem.alloc[bool](a, urls.len + 1usize)
        let (b3, e3) = mem.alloc[bool](a, urls.len + 1usize)
        let (b4, e4) = mem.alloc[bool](a, urls.len + 1usize)
        var i = 0usize
        while i < urls.len {
            b1[i] = policy.csp_blocks_connect(a, p, urls[i])
            b2[i] = policy.csp_blocks_image(a, p, urls[i])
            b3[i] = policy.csp_blocks_style(a, p, urls[i])
            b4[i] = policy.csp_blocks_font(a, p, urls[i])
            i += 1usize
        }
        var blocked = obj(a)
        put(&blocked, "connect", bools_json(a, b1[0usize..urls.len]))
        put(&blocked, "image", bools_json(a, b2[0usize..urls.len]))
        put(&blocked, "style", bools_json(a, b3[0usize..urls.len]))
        put(&blocked, "font", bools_json(a, b4[0usize..urls.len]))
        var o = obj(a)
        put(&o, "blocksScripts", bv(p.blocks_scripts))
        put(&o, "connect", sources_json(a, p.connect))
        put(&o, "img", sources_json(a, p.image))
        put(&o, "style", sources_json(a, p.style))
        put(&o, "font", sources_json(a, p.font))
        put(&o, "blocked", ir.obj_value(&blocked))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "safelisted") { ret bv(policy.is_cors_safelisted_request_header(a, text_of(c, "name"), text_of(c, "value"))) }
    if str.eq(op, "unsafe") { ret strings_json(a, policy.cors_unsafe_header_names(a, headers_of(a, ir.value_of(c, "headers")))) }
    if str.eq(op, "simple") { ret bv(policy.is_simple_cors_request(a, text_of(c, "method"), headers_of(a, ir.value_of(c, "headers")))) }
    if str.eq(op, "preflight") {
        ret reason_json(policy.cors_preflight_block_reason(a, text_of(c, "origin"), text_of(c, "method"), strings_of(a, ir.value_of(c, "unsafe")), number_of(c, "status"), headers_of(a, ir.value_of(c, "headers")), flag_of(c, "credentialed")))
    }
    if str.eq(op, "response") {
        ret reason_json(policy.cors_response_block_reason(a, text_of(c, "origin"), headers_of(a, ir.value_of(c, "headers")), flag_of(c, "credentialed")))
    }
    if str.eq(op, "serialize") {
        let (o, has) = policy.cors_serialize_origin(a, text_of(c, "url"))
        ret nullable_text(has, o)
    }
    if str.eq(op, "corp") {
        ret reason_json(policy.corp_block_reason(a, text_of(c, "doc"), has_text(c, "doc"), text_of(c, "url"), text_of(c, "corp"), has_text(c, "corp"), flag_of(c, "requires")))
    }
    if str.eq(op, "nocors") {
        ret reason_json(policy.no_cors_response_block_reason(a, text_of(c, "doc"), has_text(c, "doc"), text_of(c, "url"), headers_of(a, ir.value_of(c, "headers")), flag_of(c, "requires")))
    }
    if str.eq(op, "parse") {
        let value = text_of(c, "value")
        let has = has_text(c, "value")
        var o = obj(a)
        put(&o, "corp", sv(corp_name(policy.parse_corp(a, value, has))))
        put(&o, "coep", sv(coep_name(policy.parse_coep(a, value, has))))
        put(&o, "coop", sv(coop_name(policy.parse_coop(a, value, has))))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "pcache") {
        var cache = policy.new_preflight_cache(a)
        let steps = items(ir.value_of(c, "steps"))
        let (out, e) = mem.alloc[json.Value](a, steps.len + 1usize)
        if e != ok { os.exit(87i32) }
        var i = 0usize
        while i < steps.len {
            let s = steps[i]
            let now = ms_of(s, "t")
            let k = text_of(s, "k")
            if str.eq(k, "store") {
                policy.preflight_store(a, &cache, text_of(s, "origin"), text_of(s, "url"), headers_of(a, ir.value_of(s, "headers")), flag_of(s, "credentialed"), now)
                out[i] = .Null
            } else if str.eq(k, "allowed") {
                out[i] = bv(policy.preflight_is_allowed(a, &cache, text_of(s, "origin"), text_of(s, "url"), text_of(s, "method"), strings_of(a, ir.value_of(s, "unsafe")), flag_of(s, "credentialed"), now))
            } else {
                out[i] = iv(a, i64(cache.count))
            }
            i += 1usize
        }
        ret json.Value{ Array: out[0usize..steps.len] }
    }
    // jar
    var jar = policy.new_cookie_jar(a, flag_of(c, "block"))
    let steps = items(ir.value_of(c, "steps"))
    let (out, e) = mem.alloc[json.Value](a, steps.len + 1usize)
    if e != ok { os.exit(88i32) }
    let now = 1800000000000i64
    var i = 0usize
    while i < steps.len {
        let s = steps[i]
        let k = text_of(s, "k")
        if str.eq(k, "set") {
            policy.jar_process_response(a, &jar, text_of(s, "url"), text_of(s, "header"), text_of(s, "pk"), has_text(s, "pk"), now)
            out[i] = .Null
        } else if str.eq(k, "get") {
            let h = policy.jar_cookie_header(a, &jar, text_of(s, "url"), flag_of(s, "top"), text_of(s, "pk"), has_text(s, "pk"), now)
            out[i] = nullable_text(h.present, h.value)
        } else if str.eq(k, "key") {
            let u = policy.parse_url(a, text_of(s, "url"))
            let (key, has) = policy.partition_key_for(a, u)
            out[i] = nullable_text(has, key)
        } else if str.eq(k, "clearOrigin") {
            policy.jar_clear_origin(a, &jar, text_of(s, "host"))
            out[i] = .Null
        } else {
            policy.jar_clear(&jar)
            out[i] = .Null
        }
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..steps.len] }
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
    try io.print("net policy ok")
    ret ok
}
