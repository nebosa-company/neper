// `x.net.webhook`, `x.net.authscheme`, `x.mcp.protocol` and `x.api.openapi` against Appdor's own sources:
// scripts/protocols_vectors.mjs writes one JSON line per case (`{"op", ..., "e": answer}`) with `Date.now` pinned at
// 1,800,000,000,000 ms; the fixture computes the same answer and compares canonical JSON (stdio framing as text).
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.api.openapi as openapi
use x.mcp.protocol as mcp
use x.net.authscheme as auth
use x.net.webhook as webhook

fn now_ms() -> f64 { ret 1800000000000.0f64 }

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

fn number_of(v: json.Value, key: str) -> f64 {
    let x = ir.value_of(v, key)
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret value
    default:
        ret 0.0f64
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

fn check_json(a: *mem.Arena, c: webhook.Check) -> json.Value {
    var o = obj(a)
    put(&o, "ok", bv(c.valid))
    if c.valid {
        if c.secret_index >= 0i64 { put(&o, "matchedSecretIndex", json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(c.secret_index)) } }) }
    } else {
        put(&o, "reason", sv(c.reason))
    }
    ret ir.obj_value(&o)
}

fn tolerance_of(c: json.Value) -> f64 {
    if ir.is_null(ir.value_of(c, "tol")) { ret 300.0f64 }
    ret number_of(c, "tol")
}

fn token_value(a: *mem.Arena, t: auth.Token) -> json.Value {
    var o = obj(a)
    if t.valid {
        put(&o, "value", t.value)
    } else {
        put(&o, "threw", sv(t.message))
    }
    ret ir.obj_value(&o)
}

fn handled_json(h: mcp.Handled) -> json.Value {
    if h.kind == 1u8 { ret .Null }
    if h.kind == 2u8 { ret sv("delegate") }
    ret h.response
}

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "hmac") { ret sv(webhook.hmac_sha256(a, text_of(c, "key"), text_of(c, "message"))) }
    if str.eq(op, "signBody") { ret sv(webhook.sign_body(a, text_of(c, "body"), text_of(c, "secret"))) }
    if str.eq(op, "signV1") { ret sv(webhook.sign_body_v1(a, text_of(c, "body"), text_of(c, "secret"), number_of(c, "ts"))) }
    if str.eq(op, "headers") {
        let h = webhook.signature_headers(a, text_of(c, "body"), text_of(c, "secret"), number_of(c, "ts"))
        var o = obj(a)
        put(&o, "X-Neposer-Signature", sv(h.signature))
        put(&o, "X-Neposer-Timestamp", sv(h.timestamp))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "verifyHeaders") {
        ret check_json(a, webhook.verify_signature_headers(a, text_of(c, "body"), text_of(c, "secret"), text_of(c, "signature"), text_of(c, "timestamp"), tolerance_of(c), now_ms()))
    }
    if str.eq(op, "verifyV1") {
        ret check_json(a, webhook.verify_v1(a, text_of(c, "body"), text_of(c, "secret"), text_of(c, "header"), tolerance_of(c), now_ms()))
    }
    if str.eq(op, "rotated") {
        let secrets = items(ir.value_of(c, "secrets"))
        let (texts, e) = mem.alloc[str](a, secrets.len + 1usize)
        if e != ok { os.exit(85i32) }
        var i = 0usize
        while i < secrets.len {
            let (s, is_text) = ir.string_of(secrets[i])
            texts[i] = s
            i += 1usize
        }
        ret check_json(a, webhook.verify_v1_rotated(a, text_of(c, "body"), texts[0usize..secrets.len], text_of(c, "header"), 300.0f64, now_ms()))
    }
    if str.eq(op, "apply") { ret auth.apply_auth(a, ir.value_of(c, "connection"), ir.value_of(c, "request"), now_ms()) }
    if str.eq(op, "needsRefresh") { ret bv(auth.needs_refresh(a, ir.value_of(c, "connection"), number_of(c, "now"))) }
    if str.eq(op, "buildRefresh") {
        let r = auth.build_refresh(a, ir.value_of(c, "connection"))
        var o = obj(a)
        if !r.present {
            put(&o, "none", bv(true))
        } else if r.failed {
            put(&o, "threw", sv(r.message))
        } else {
            put(&o, "request", ir.value_of(r.request, "request"))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "redact") { ret auth.redact_connection(a, ir.value_of(c, "connection")) }
    if str.eq(op, "token") {
        ret token_value(a, auth.parse_token_response(a, ir.value_of(c, "response"), ir.value_of(c, "connection"), now_ms(), flag_of(c, "oidc")))
    }
    if str.eq(op, "inbound") {
        let (body, has_body) = ir.get(c, "body")
        let r = auth.verify_inbound(a, ir.value_of(c, "connection"), ir.value_of(c, "headers"), body, has_body, now_ms())
        var o = obj(a)
        put(&o, "ok", bv(r.valid))
        if !r.valid { put(&o, "reason", sv(r.reason)) }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "authorize") {
        let options = ir.value_of(c, "options")
        let r = auth.build_authorize_url(a, ir.value_of(c, "connection"), text_of(options, "redirectUri"), text_of(options, "scope"), text_of(options, "state"), text_of(options, "codeChallenge"), text_of(options, "prompt"))
        var o = obj(a)
        if r.valid {
            put(&o, "value", sv(r.value))
        } else {
            put(&o, "threw", bv(true))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "server") {
        var s = mcp.new_server()
        let messages = items(ir.value_of(c, "messages"))
        let (out, e) = mem.alloc[json.Value](a, messages.len + 1usize)
        if e != ok { os.exit(86i32) }
        var i = 0usize
        while i < messages.len {
            let (method, has_method) = ir.get(messages[i], "method")
            out[i] = handled_json(mcp.handle(a, &s, messages[i], text_of(c, "instructions")))
            i += 1usize
        }
        ret json.Value{ Array: out[0usize..messages.len] }
    }
    if str.eq(op, "classify") {
        let r = mcp.classify_message(ir.value_of(c, "message"))
        var o = obj(a)
        put(&o, "ok", bv(r.valid))
        if r.valid {
            if r.notification {
                put(&o, "kind", sv("notification"))
            } else {
                put(&o, "kind", sv("request"))
            }
            put(&o, "method", sv(r.method))
            let (idv, has_id_key) = ir.get(ir.value_of(c, "message"), "id")
            if has_id_key { put(&o, "id", idv) }
        } else {
            put(&o, "code", json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(r.code)) } })
            put(&o, "reason", sv(r.reason))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "negotiate") { ret sv(mcp.negotiate_version(text_of(c, "version"))) }
    if str.eq(op, "capabilities") {
        let opts = ir.value_of(c, "opts")
        var resources = true
        var with_prompts = true
        let (rv, has_r) = ir.get(opts, "resources")
        if has_r { resources = !(ir.is_null(rv) || !ir.truthy(rv)) }
        let (pv, has_p) = ir.get(opts, "prompts")
        if has_p { with_prompts = !(ir.is_null(pv) || !ir.truthy(pv)) }
        ret mcp.capabilities(a, resources, with_prompts, flag_of(opts, "toolListChanged"))
    }
    if str.eq(op, "prompt") {
        let p = mcp.render_prompt(a, text_of(c, "name"), ir.value_of(c, "args"))
        var o = obj(a)
        put(&o, "ok", bv(p.valid))
        if p.valid {
            put(&o, "description", sv(p.description))
            var content = obj(a)
            put(&content, "type", sv("text"))
            put(&content, "text", sv(p.text))
            var m = obj(a)
            put(&m, "role", sv("user"))
            put(&m, "content", ir.obj_value(&content))
            let (arr, e) = mem.alloc[json.Value](a, 1usize)
            arr[0] = ir.obj_value(&m)
            put(&o, "messages", json.Value{ Array: arr[0usize..1usize] })
        } else {
            put(&o, "error", sv(p.message))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "uri") {
        let r = mcp.parse_resource_uri(a, text_of(c, "uri"))
        var o = obj(a)
        put(&o, "ok", bv(r.valid))
        if r.valid {
            put(&o, "tableId", sv(r.table_id))
            put(&o, "kind", sv(r.kind))
        } else {
            put(&o, "error", sv(r.message))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "tableUri") { ret sv(mcp.table_resource_uri(a, text_of(c, "id"))) }
    if str.eq(op, "encode") { ret sv(mcp.encode_stdio_message(a, ir.value_of(c, "message"))) }
    if str.eq(op, "decode") {
        let r = mcp.decode_stdio_chunk(a, text_of(c, "buffer"))
        var o = obj(a)
        put(&o, "messages", json.Value{ Array: r.messages })
        put(&o, "errors", strings_json(a, r.errors))
        put(&o, "remainder", sv(r.remainder))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "notification") {
        var o = obj(a)
        put(&o, "jsonrpc", sv("2.0"))
        put(&o, "method", sv("notifications/tools/list_changed"))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "rpcError") { ret mcp.rpc_error(a, ir.value_of(c, "id"), i64(number_of(c, "code")), text_of(c, "message")) }
    if str.eq(op, "openapi") {
        var spec = openapi.create_spec(a, ir.value_of(c, "info"))
        let steps = items(ir.value_of(c, "steps"))
        var i = 0usize
        while i < steps.len {
            if str.eq(text_of(steps[i], "k"), "path") {
                spec = openapi.add_path(a, spec, text_of(steps[i], "path"), text_of(steps[i], "method"), ir.value_of(steps[i], "operation"))
            } else {
                spec = openapi.add_schema(a, spec, text_of(steps[i], "name"), ir.value_of(steps[i], "schema"))
            }
            i += 1usize
        }
        let v = openapi.validate_spec(a, spec)
        var vo = obj(a)
        put(&vo, "valid", bv(v.valid))
        put(&vo, "errors", strings_json(a, v.errors))
        var o = obj(a)
        put(&o, "spec", spec)
        put(&o, "validation", ir.obj_value(&vo))
        ret ir.obj_value(&o)
    }
    // validate
    let v = openapi.validate_spec(a, ir.value_of(c, "spec"))
    var o = obj(a)
    put(&o, "valid", bv(v.valid))
    put(&o, "errors", strings_json(a, v.errors))
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
    try io.print("x api protocols ok")
    ret ok
}
