// `x.identity.xml` and `x.identity.saml` against Appdor's own src/identity/{xml,saml}.js: scripts/saml_vectors.mjs writes one
// JSON line per case (`{"op", ..., "e": answer}`) over random documents and SAML responses really signed with RSA-SHA256,
// tampered, wrapped, expired and replayed; the fixture computes the same answer and compares canonical JSON.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.identity.saml as saml
use x.identity.xml as xml

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

// A string, or null when it is empty (the reference's `|| null`).
fn sn(s: str) -> json.Value {
    if s.len == 0usize { ret .Null }
    ret sv(s)
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

fn has_number(v: json.Value, key: str) -> bool {
    let x = ir.value_of(v, key)
    switch x {
    case .Number as n:
        ret true
    default:
        ret false
    }
}

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

fn tree_json(a: *mem.Arena, d: xml.Doc, at: usize) -> json.Value {
    let n = d.nodes[at]
    var o = obj(a)
    put(&o, "name", sv(n.name))
    put(&o, "prefix", sv(n.prefix))
    put(&o, "local", sv(n.local))
    var attrs = obj(a)
    var i = 0usize
    while i < n.attr_names.len {
        put(&attrs, n.attr_names[i], sv(n.attr_values[i]))
        i += 1usize
    }
    put(&o, "attributes", ir.obj_value(&attrs))
    put(&o, "attributeOrder", strings_json(a, n.attr_names))
    var nss = obj(a)
    i = 0usize
    while i < n.ns_prefixes.len {
        put(&nss, n.ns_prefixes[i], sv(n.ns_uris[i]))
        i += 1usize
    }
    put(&o, "namespaces", ir.obj_value(&nss))
    put(&o, "text", sv(n.text))
    let (nodes, e) = mem.alloc[json.Value](a, n.entries.len + 1usize)
    if e != ok { os.exit(86i32) }
    i = 0usize
    while i < n.entries.len {
        var en = obj(a)
        if n.entries[i].is_text {
            put(&en, "type", sv("text"))
            put(&en, "value", sv(n.entries[i].text))
        } else {
            put(&en, "type", sv("element"))
            put(&en, "node", tree_json(a, d, n.entries[i].node))
        }
        nodes[i] = ir.obj_value(&en)
        i += 1usize
    }
    put(&o, "nodes", json.Value{ Array: nodes[0usize..n.entries.len] })
    ret ir.obj_value(&o)
}

fn indexes_json(a: *mem.Arena, xs: []const usize) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
    if e != ok { os.exit(87i32) }
    var i = 0usize
    while i < xs.len {
        out[i] = json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(xs[i])) } }
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..xs.len] }
}

fn assertion_json(a: *mem.Arena, s: saml.Assertion) -> json.Value {
    if !s.present { ret .Null }
    var o = obj(a)
    put(&o, "id", sn(s.id))
    put(&o, "issuer", sn(s.issuer))
    if s.has_name_id {
        put(&o, "nameId", sv(s.name_id))
    } else {
        put(&o, "nameId", .Null)
    }
    put(&o, "nameIdFormat", sn(s.name_id_format))
    put(&o, "sessionIndex", sn(s.session_index))
    put(&o, "authnInstant", sn(s.authn_instant))
    put(&o, "notBefore", sn(s.not_before))
    put(&o, "notOnOrAfter", sn(s.not_on_or_after))
    put(&o, "audiences", strings_json(a, s.audiences))
    put(&o, "recipient", sn(s.recipient))
    put(&o, "confirmationNotOnOrAfter", sn(s.confirmation_not_on_or_after))
    put(&o, "confirmationInResponseTo", sn(s.confirmation_in_response_to))
    put(&o, "attributes", attributes_json(a, s))
    ret ir.obj_value(&o)
}

fn attributes_json(a: *mem.Arena, s: saml.Assertion) -> json.Value {
    var o = obj(a)
    var i = 0usize
    while i < s.attr_names.len {
        put(&o, s.attr_names[i], strings_json(a, s.attr_values[i]))
        i += 1usize
    }
    ret ir.obj_value(&o)
}

fn fail_json(a: *mem.Arena, msg: str) -> json.Value {
    var o = obj(a)
    put(&o, "ok", bv(false))
    put(&o, "error", sv(msg))
    ret ir.obj_value(&o)
}

fn config_of(a: *mem.Arena, c: json.Value) -> saml.Config {
    let jwk = ir.value_of(c, "jwk")
    var key = saml.Key { has: false, n: "", e: "" }
    if ir.truthy(jwk) { key = saml.Key { has: true, n: text_of(jwk, "n"), e: text_of(jwk, "e") } }
    ret saml.Config {
        issuer: text_of(c, "issuer"),
        audience: text_of(c, "audience"),
        acs_url: text_of(c, "acsUrl"),
        key: key,
        expected_in_response_to: text_of(c, "expectedInResponseTo"),
        now: number_of(c, "now"),
        has_skew: has_number(c, "skewMs"),
        skew_ms: number_of(c, "skewMs"),
        seen: strings_of(a, ir.value_of(c, "seenAssertionIds")),
    }
}

fn preorder(d: xml.Doc, at: usize, out: []usize, n: *usize) {
    out[*n] = at
    *n += 1usize
    var i = 0usize
    while i < d.nodes[at].children.len {
        preorder(d, d.nodes[at].children[i], out, n)
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "xml") {
        let d = xml.parse_xml(a, text_of(c, "src"))
        var o = obj(a)
        put(&o, "ok", bv(d.valid))
        if d.valid {
            put(&o, "tree", tree_json(a, d, d.root))
        } else {
            put(&o, "error", sv(d.message))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "c14n") {
        let d = xml.parse_xml(a, text_of(c, "src"))
        if !d.valid { ret sv("parse failed") }
        let at = usize(number_of(c, "at"))
        ret sv(xml.canonicalize(a, d, at, strings_of(a, ir.value_of(c, "inclusive"))))
    }
    if str.eq(op, "entities") { ret sv(xml.decode_entities(a, text_of(c, "text"))) }
    if str.eq(op, "find") {
        let d = xml.parse_xml(a, text_of(c, "src"))
        if !d.valid { ret sv("parse failed") }
        let found = xml.find_elements(a, d, d.root, text_of(c, "ns"), text_of(c, "local"))
        let (hit, has_hit) = xml.find_by_id(d, d.root, text_of(c, "id"))
        var o = obj(a)
        put(&o, "found", indexes_json(a, found))
        if has_hit {
            put(&o, "byId", json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(hit)) } })
        } else {
            put(&o, "byId", json.Value{ Number: json.Number{ lexeme: "-1" } })
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "parse") {
        let r = saml.parse_saml_response(a, text_of(c, "response"))
        if !r.valid { ret fail_json(a, r.message) }
        var o = obj(a)
        put(&o, "ok", bv(true))
        put(&o, "id", sn(r.id))
        put(&o, "inResponseTo", sn(r.in_response_to))
        put(&o, "destination", sn(r.destination))
        put(&o, "issueInstant", sn(r.issue_instant))
        put(&o, "issuer", sn(r.issuer))
        if !r.status_present {
            put(&o, "statusCode", .Null)
        } else if r.status_has_value {
            put(&o, "statusCode", sv(r.status_code))
        }
        put(&o, "statusMessage", sn(r.status_message))
        put(&o, "assertion", assertion_json(a, r.assertion))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "validate") {
        let parsed = saml.parse_saml_response(a, text_of(c, "response"))
        let v = saml.validate_saml_response(a, parsed, config_of(a, ir.value_of(c, "config")))
        if !v.valid {
            var o = obj(a)
            put(&o, "ok", bv(false))
            put(&o, "error", sv(v.message))
            if str.starts_with(v.message, "IdP-status") {
                if v.has_detail {
                    put(&o, "detail", sv(v.detail))
                } else {
                    put(&o, "detail", .Null)
                }
            }
            ret ir.obj_value(&o)
        }
        var o = obj(a)
        put(&o, "ok", bv(true))
        put(&o, "assertionId", sn(v.assertion_id))
        put(&o, "signedElement", sv(v.signed_element))
        var subject = obj(a)
        if v.assertion.has_name_id {
            put(&subject, "nameId", sv(v.assertion.name_id))
        } else {
            put(&subject, "nameId", .Null)
        }
        put(&subject, "nameIdFormat", sn(v.assertion.name_id_format))
        put(&subject, "sessionIndex", sn(v.assertion.session_index))
        put(&subject, "attributes", attributes_json(a, v.assertion))
        put(&o, "subject", ir.obj_value(&subject))
        if v.has_expiry {
            put(&o, "expiresAt", json.Value{ Number: json.Number{ lexeme: f.number_text(a, v.expires_at) } })
        } else {
            put(&o, "expiresAt", .Null)
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "authn") {
        let p = ir.value_of(c, "p")
        var binding = text_of(p, "binding")
        if binding.len == 0usize { binding = saml.binding_redirect() }
        let r = saml.build_authn_request(a, text_of(p, "id"), text_of(p, "issueInstant"), text_of(p, "destination"), text_of(p, "issuer"), text_of(p, "acsUrl"), text_of(p, "nameIdFormat"), flag_of(p, "forceAuthn"), text_of(p, "relayState"), binding)
        var o = obj(a)
        put(&o, "ok", bv(r.valid))
        if !r.valid {
            put(&o, "missing", strings_json(a, r.missing))
            ret ir.obj_value(&o)
        }
        put(&o, "binding", sv(r.binding))
        put(&o, "xml", sv(r.xml))
        if str.eq(r.binding, saml.binding_post()) {
            put(&o, "formAction", sv(r.form_action))
            put(&o, "samlRequest", sv(r.saml_request))
            put(&o, "relayState", sn(r.relay_state))
        } else {
            put(&o, "url", sv(r.url))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "b64") {
        let t = text_of(c, "text")
        var o = obj(a)
        put(&o, "std", sv(saml.to_base64(a, t)))
        let stored = saml.deflate_raw_stored(a, t)
        let (out, e) = mem.alloc[json.Value](a, stored.len + 1usize)
        if e != ok { os.exit(88i32) }
        var i = 0usize
        while i < stored.len {
            out[i] = sv(f.number_text(a, f64(stored[i])))
            i += 1usize
        }
        put(&o, "stored", json.Value{ Array: out[0usize..stored.len] })
        put(&o, "id", sv(saml.saml_id(a, t)))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "stored") {
        let n = usize(number_of(c, "length"))
        let (data, e) = mem.alloc[u8](a, n)
        if e != ok { os.exit(89i32) }
        var i = 0usize
        while i < n {
            data[i] = u8((i * 7usize) & 255usize)
            i += 1usize
        }
        let stored = saml.deflate_raw_stored(a, data)
        var o = obj(a)
        put(&o, "total", sv(f.number_text(a, f64(stored.len))))
        let (head, he) = mem.alloc[json.Value](a, 8usize)
        let (second, se) = mem.alloc[json.Value](a, 5usize)
        i = 0usize
        while i < 8usize {
            head[i] = sv(f.number_text(a, f64(stored[i])))
            i += 1usize
        }
        i = 0usize
        while i < 5usize {
            second[i] = sv(f.number_text(a, f64(stored[5usize + 65535usize + i])))
            i += 1usize
        }
        put(&o, "head", json.Value{ Array: head[0usize..8usize] })
        put(&o, "second", json.Value{ Array: second[0usize..5usize] })
        ret ir.obj_value(&o)
    }
    if str.eq(op, "metadata") {
        let p = ir.value_of(c, "p")
        var format = text_of(p, "nameIdFormat")
        if format.len == 0usize { format = saml.nameid_email() }
        var want = true
        let (wv, has_w) = ir.get(p, "wantAssertionsSigned")
        if has_w {
            switch wv {
            case .Bool as b:
                want = b
            default:
                want = true
            }
        }
        let (xml_text, missing) = saml.build_sp_metadata(a, text_of(p, "entityId"), text_of(p, "acsUrl"), text_of(p, "sloUrl"), format, want)
        var o = obj(a)
        if missing.len > 0usize {
            put(&o, "ok", bv(false))
            put(&o, "missing", strings_json(a, missing))
        } else {
            put(&o, "ok", bv(true))
            put(&o, "xml", sv(xml_text))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "idp") {
        let r = saml.parse_idp_metadata(a, text_of(c, "xml"))
        if !r.valid { ret fail_json(a, r.message) }
        var cfg = obj(a)
        put(&cfg, "entityId", sn(r.entity_id))
        put(&cfg, "ssoUrl", sn(r.sso_url))
        put(&cfg, "postUrl", sn(r.post_url))
        put(&cfg, "certificates", strings_json(a, r.certificates))
        var o = obj(a)
        put(&o, "ok", bv(true))
        put(&o, "config", ir.obj_value(&cfg))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "cert") {
        let (key, good) = saml.certificate_to_jwk(a, text_of(c, "cert"))
        if !good { ret fail_json(a, "no-RSA-public-key-in-certificate") }
        var jwk = obj(a)
        put(&jwk, "kty", sv("RSA"))
        put(&jwk, "n", sv(key.n))
        put(&jwk, "e", sv(key.e))
        var o = obj(a)
        put(&o, "ok", bv(true))
        put(&o, "jwk", ir.obj_value(&jwk))
        ret ir.obj_value(&o)
    }
    // replay
    let steps = items(ir.value_of(c, "steps"))
    var cache = saml.new_replay_cache(a, 32usize)
    let (out, e) = mem.alloc[json.Value](a, steps.len + 1usize)
    if e != ok { os.exit(90i32) }
    var i = 0usize
    while i < steps.len {
        let now = number_of(steps[i], "t")
        let kind = text_of(steps[i], "kind")
        let id = text_of(steps[i], "id")
        if str.eq(kind, "has") {
            if saml.replay_has(&cache, id, now) {
                out[i] = sv("true")
            } else {
                out[i] = sv("false")
            }
        } else if str.eq(kind, "size") {
            out[i] = sv(f.number_text(a, f64(saml.replay_size(&cache, now))))
        } else {
            let expires = number_of(steps[i], "expires")
            saml.replay_remember(&cache, id, expires, expires != 0.0f64, now)
            out[i] = sv("-")
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
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 80u16 })
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
    try io.print("x identity saml ok")
    ret ok
}
