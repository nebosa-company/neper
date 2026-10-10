// `x.identity.jose` and `x.identity.oidc` against Appdor's own src/identity/{jose,oidc}.js: scripts/oidc_vectors.mjs writes one
// JSON line per case (`{"op", ..., "e": answer}`) over real RS256 tokens and requests; the fixture computes the same answer
// and compares canonical JSON. A malformed JWT's message is reduced to `malformed JWT`.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.identity.jose as jose
use x.identity.oidc as oidc

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

fn optional_text(v: json.Value, key: str) -> json.Value {
    if has_text(v, key) { ret sv(text_of(v, key)) }
    ret .Null
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

fn config_json(a: *mem.Arena, c: oidc.Config) -> json.Value {
    var o = obj(a)
    put(&o, "issuer", sv(c.issuer))
    put(&o, "authorizationEndpoint", sv(c.authorization_endpoint))
    put(&o, "tokenEndpoint", sv(c.token_endpoint))
    put(&o, "jwksUri", sv(c.jwks_uri))
    if c.has_userinfo {
        put(&o, "userinfoEndpoint", sv(c.userinfo_endpoint))
    } else {
        put(&o, "userinfoEndpoint", .Null)
    }
    if c.has_end_session {
        put(&o, "endSessionEndpoint", sv(c.end_session_endpoint))
    } else {
        put(&o, "endSessionEndpoint", .Null)
    }
    put(&o, "scopesSupported", strings_json(a, c.scopes_supported))
    put(&o, "responseTypesSupported", strings_json(a, c.response_types_supported))
    put(&o, "idTokenSigningAlgValuesSupported", strings_json(a, c.id_token_signing_alg_values_supported))
    put(&o, "codeChallengeMethodsSupported", strings_json(a, c.code_challenge_methods_supported))
    ret ir.obj_value(&o)
}

fn pairs_of(a: *mem.Arena, v: json.Value) -> []const oidc.Pair {
    let (members, is_object) = ir.members_of(v)
    let (out, e) = mem.alloc[oidc.Pair](a, members.len + 1usize)
    if e != ok { os.exit(86i32) }
    var i = 0usize
    while i < members.len {
        let (s, is_text) = ir.string_of(members[i].value)
        out[i] = oidc.Pair { key: members[i].key, value: s }
        i += 1usize
    }
    ret out[0usize..members.len]
}

fn config_of(a: *mem.Arena, no_end: bool) -> oidc.Config {
    let (o, e) = ir.new_obj(a)
    var d = o
    let ee = ir.put(&d, "issuer", sv("https://idp"))
    let e2 = ir.put(&d, "authorization_endpoint", sv("https://idp/auth"))
    let e3 = ir.put(&d, "token_endpoint", sv("https://idp/token"))
    let e4 = ir.put(&d, "jwks_uri", sv("https://idp/jwks"))
    if !no_end {
        let e5 = ir.put(&d, "end_session_endpoint", sv("https://idp/logout"))
    }
    let dis = oidc.parse_discovery(a, ir.obj_value(&d))
    ret dis.config
}

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "b64") {
        let t = text_of(c, "text")
        let bytes = jose.base64url_decode(a, t)
        let (out, e) = mem.alloc[json.Value](a, bytes.len + 1usize)
        if e != ok { os.exit(87i32) }
        var i = 0usize
        while i < bytes.len {
            out[i] = sv(f.number_text(a, f64(bytes[i])))
            i += 1usize
        }
        var o = obj(a)
        put(&o, "bytes", json.Value{ Array: out[0usize..bytes.len] })
        put(&o, "roundtrip", sv(jose.base64url_encode(a, bytes)))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "decode") {
        let d = jose.decode_jwt(a, text_of(c, "token"))
        var o = obj(a)
        put(&o, "ok", bv(d.valid))
        if d.valid {
            put(&o, "header", d.header)
            put(&o, "payload", d.payload)
            put(&o, "signature", sv(d.signature))
            put(&o, "signingInput", sv(d.signing_input))
        } else {
            put(&o, "error", sv(d.message))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "verify") {
        let jwk = ir.value_of(c, "jwk")
        let (good, message) = jose.verify_jwt_signature(a, text_of(c, "token"), jwk, ir.truthy(jwk))
        var o = obj(a)
        put(&o, "ok", bv(good))
        if !good { put(&o, "error", sv(message)) }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "select") {
        let (k, found) = jose.select_jwk(ir.value_of(c, "jwks"), ir.value_of(c, "header"))
        if found { ret k }
        ret .Null
    }
    if str.eq(op, "discovery_url") { ret sv(oidc.discovery_url(a, text_of(c, "issuer"))) }
    if str.eq(op, "discovery") {
        let d = oidc.parse_discovery(a, ir.value_of(c, "doc"))
        var o = obj(a)
        put(&o, "ok", bv(d.valid))
        if d.valid {
            put(&o, "config", config_json(a, d.config))
        } else {
            put(&o, "missing", strings_json(a, d.missing))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "pkce") {
        let verifier = text_of(c, "verifier")
        var o = obj(a)
        put(&o, "challenge", sv(oidc.pkce_challenge(a, verifier)))
        put(&o, "verified", bv(oidc.verify_pkce(a, verifier, text_of(c, "challenge"))))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "pair") {
        let nums = items(ir.value_of(c, "bytes"))
        let (raw, e) = mem.alloc[u8](a, nums.len + 1usize)
        if e != ok { os.exit(88i32) }
        var i = 0usize
        while i < nums.len {
            let (s, is_text) = ir.string_of(nums[i])
            var v = 0u32
            var k = 0usize
            while k < s.len {
                v = v * 10u32 + u32(s[k] - 48u8)
                k += 1usize
            }
            raw[i] = u8(v)
            i += 1usize
        }
        let p = oidc.create_pkce_pair(a, raw[0usize..nums.len])
        var o = obj(a)
        put(&o, "codeVerifier", sv(p.key))
        put(&o, "codeChallenge", sv(p.value))
        put(&o, "codeChallengeMethod", sv("S256"))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "authurl") {
        let p = ir.value_of(c, "p")
        let r = oidc.AuthRequest {
            client_id: text_of(p, "clientId"),
            redirect_uri: text_of(p, "redirectUri"),
            scope: text_of(p, "scope"),
            state: text_of(p, "state"),
            nonce: text_of(p, "nonce"),
            code_challenge: text_of(p, "codeChallenge"),
            prompt: text_of(p, "prompt"),
            login_hint: text_of(p, "loginHint"),
            extra: pairs_of(a, ir.value_of(p, "extra")),
        }
        let u = oidc.build_authorization_url(a, config_of(a, false), r)
        var o = obj(a)
        put(&o, "ok", bv(u.valid))
        if u.valid {
            put(&o, "url", sv(u.url))
        } else {
            put(&o, "missing", strings_json(a, u.missing))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "callback") {
        let r = oidc.parse_callback(a, ir.value_of(c, "q"), text_of(c, "expected"))
        var o = obj(a)
        put(&o, "ok", bv(r.valid))
        if r.valid {
            put(&o, "code", sv(r.code))
            put(&o, "state", sv(r.state))
        } else {
            put(&o, "error", sv(r.error_code))
            if r.has_description {
                put(&o, "description", sv(r.description))
            } else if str.eq(r.error_code, "missing-code") == false {
                put(&o, "description", .Null)
            }
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "tokenreq") {
        let p = ir.value_of(c, "p")
        let r = oidc.build_token_request(a, config_of(a, false), text_of(p, "clientId"), text_of(p, "clientSecret"), text_of(p, "code"), text_of(p, "redirectUri"), text_of(p, "codeVerifier"))
        var o = obj(a)
        put(&o, "ok", bv(r.valid))
        if r.valid {
            put(&o, "url", sv(r.url))
            put(&o, "method", sv("POST"))
            var h = obj(a)
            put(&h, "Content-Type", sv("application/x-www-form-urlencoded"))
            put(&h, "Accept", sv("application/json"))
            if r.has_authorization { put(&h, "Authorization", sv(r.authorization)) }
            put(&o, "headers", ir.obj_value(&h))
            put(&o, "body", sv(r.body))
        } else {
            put(&o, "missing", strings_json(a, r.missing))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "logout") {
        let p = ir.value_of(c, "p")
        let no_end = ir.truthy(ir.value_of(c, "noEnd"))
        let u = oidc.build_logout_url(a, config_of(a, no_end), text_of(p, "idTokenHint"), text_of(p, "postLogoutRedirectUri"), text_of(p, "state"))
        var o = obj(a)
        put(&o, "ok", bv(u.valid))
        if u.valid {
            put(&o, "url", sv(u.url))
        } else {
            put(&o, "error", sv("provider has no end_session_endpoint"))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "validate") {
        let ex = ir.value_of(c, "ex")
        let e = oidc.Expectations {
            issuer: text_of(ex, "issuer"),
            client_id: text_of(ex, "clientId"),
            nonce: text_of(ex, "nonce"),
            jwks: ir.value_of(ex, "jwks"),
            now_ms: number_of(ex, "now"),
            has_max_age: has_number(ex, "maxAgeSeconds"),
            max_age_seconds: number_of(ex, "maxAgeSeconds"),
            has_skew: has_number(ex, "skewSeconds"),
            skew_seconds: number_of(ex, "skewSeconds"),
        }
        let r = oidc.validate_id_token(a, text_of(c, "token"), e)
        var o = obj(a)
        put(&o, "ok", bv(r.valid))
        if r.valid {
            put(&o, "claims", r.claims)
        } else {
            put(&o, "error", sv(r.message))
        }
        ret ir.obj_value(&o)
    }
    if str.eq(op, "profile") {
        let p = oidc.profile_from_claims(a, ir.value_of(c, "claims"), pairs_of(a, ir.value_of(c, "mapping")))
        var o = obj(a)
        if p.has_subject { put(&o, "subject", sv(p.subject)) }
        if p.has_email {
            put(&o, "email", sv(p.email))
        } else {
            put(&o, "email", .Null)
        }
        put(&o, "emailVerified", bv(p.email_verified))
        if p.has_name {
            put(&o, "name", sv(p.name))
        } else {
            put(&o, "name", .Null)
        }
        if p.has_given_name {
            put(&o, "givenName", sv(p.given_name))
        } else {
            put(&o, "givenName", .Null)
        }
        if p.has_family_name {
            put(&o, "familyName", sv(p.family_name))
        } else {
            put(&o, "familyName", .Null)
        }
        put(&o, "groups", strings_json(a, p.groups))
        if p.has_issuer { put(&o, "issuer", sv(p.issuer)) }
        ret ir.obj_value(&o)
    }
    // link
    let pr = ir.value_of(c, "profile")
    let opts = ir.value_of(c, "opts")
    var email = ""
    var has_email = false
    if has_text(pr, "email") {
        email = text_of(pr, "email")
        has_email = email.len > 0usize
    }
    var verified = false
    switch ir.value_of(pr, "emailVerified") {
    case .Bool as b:
        verified = b
    default:
        verified = false
    }
    let profile = oidc.Profile {
        has_subject: false,
        subject: "",
        has_email: has_email,
        email: email,
        email_verified: verified,
        has_name: false,
        name: "",
        has_given_name: false,
        given_name: "",
        has_family_name: false,
        family_name: "",
        groups: zero,
        has_issuer: false,
        issuer: "",
    }
    var allow = false
    switch ir.value_of(opts, "allowUnverifiedEmailLink") {
    case .Bool as b:
        allow = b
    default:
        allow = false
    }
    let existing = ir.truthy(ir.value_of(opts, "existingAccount"))
    let r = oidc.link_policy(a, profile, strings_of(a, ir.value_of(opts, "verifiedDomains")), existing, allow)
    var o = obj(a)
    put(&o, "action", sv(r.action))
    put(&o, "reason", sv(r.reason))
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
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
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
    try io.print("x identity oidc ok")
    ret ok
}
