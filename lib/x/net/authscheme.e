// Outbound authentication schemes (L049), after Appdor's `src/auth-schemes/index.js`: fourteen schemes turn a stored
// connection (an object) into the headers, query parameters, body and transport hints a request needs, with no I/O.
// `apply_auth` is the dispatcher (a missing credential, an unsafe header name or value, an unknown scheme are
// `error` fields on the request, as the reference returns them); `needs_refresh`, `build_refresh` and
// `parse_token_response` describe the token refresh as a request to make and a function to read its answer;
// `redact_connection` masks secrets; `verify_inbound` authenticates a webhook caller by HMAC; `build_authorize_url` is
// the authorization-code redirect. Clocks are parameters in milliseconds. Values are JSON.
//
// ponytail: `build_authorize_url` serialises the URL for http(s) with an ASCII path (it does not percent-normalise a path
// the way WHATWG does); `pathOf` reads the path the same way.
//
// Memory: the arena is retained.

use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.encode as encode
use e.fmt.json as json
use e.mem
use e.str
use x.identity.jose as jose
use x.net.webhook as webhook

type Applied = struct { request: json.Value, message: str, failed: bool }

type Refresh = struct { present: bool, failed: bool, message: str, request: json.Value }

type Token = struct { valid: bool, message: str, value: json.Value }

type Url = struct { valid: bool, message: str, value: str }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn skew_ms() -> f64 { ret 60000.0f64 }

// --- value helpers ---------------------------------------------------------------------------------------------

// `String(v)` for a scalar; `null` and objects as JavaScript prints them.
fn js_string(a: *mem.Arena, v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    case .Number as n:
        let (x, e) = json.number_f64(n)
        ret f.number_text(a, x)
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    case .Null:
        ret "null"
    case .Array as xs:
        var out = ""
        var i = 0usize
        while i < xs.len {
            if i > 0usize { out = join(a, out, ",") }
            if !ir.is_null(xs[i]) { out = join(a, out, js_string(a, xs[i])) }
            i += 1usize
        }
        ret out
    default:
        ret "[object Object]"
    }
}

// `a || b` for a member: the member's text when it is truthy, else `fallback`.
fn or_text(a: *mem.Arena, obj: json.Value, key: str, fallback: str) -> str {
    let v = ir.value_of(obj, key)
    if ir.truthy(v) { ret js_string(a, v) }
    ret fallback
}

fn present(obj: json.Value, key: str) -> bool {
    let (v, found) = ir.get(obj, key)
    if !found || ir.is_null(v) { ret false }
    switch v {
    case .String as s:
        ret s.len > 0usize
    default:
        ret true
    }
}

fn text_member(a: *mem.Arena, obj: json.Value, key: str) -> str {
    let (v, found) = ir.get(obj, key)
    if !found || ir.is_null(v) { ret "" }
    ret js_string(a, v)
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn new_obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    ret o
}

fn obj_of(a: *mem.Arena, v: json.Value) -> ir.Obj {
    var o = new_obj(a)
    let e = ir.assign(&o, v)
    ret o
}

fn missing(a: *mem.Arena, scheme: str, field: str) -> str {
    ret join(a, join(a, "missing-credential: ", scheme), join(a, ".", field))
}

fn json_quote(a: *mem.Arena, s: str) -> str {
    let (text, e) = encode.json_encode(a, sv(s))
    ret text
}

fn is_tchar(c: u8) -> bool {
    ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 33u8 || c == 35u8 || c == 36u8 || c == 37u8 || c == 38u8 || c == 39u8 || c == 42u8 || c == 43u8 || c == 45u8 || c == 46u8 || c == 94u8 || c == 95u8 || c == 96u8 || c == 124u8 || c == 126u8
}

// An empty string when the header name and value are safe, else the refusal.
fn header_problem(a: *mem.Arena, name: str, value: str, scheme: str) -> str {
    var ok_name = name.len > 0usize
    var i = 0usize
    while i < name.len {
        if !is_tchar(name[i]) { ok_name = false }
        i += 1usize
    }
    if !ok_name { ret join(a, join(a, join(a, "invalid-header-name: ", scheme), " "), json_quote(a, name)) }
    if str.contains(value, "\r") || str.contains(value, "\n") {
        ret join(a, join(a, join(a, "header-value-contains-crlf: ", scheme), " "), json_quote(a, name))
    }
    ret ""
}

fn base64(a: *mem.Arena, s: str) -> str {
    let (out, e) = encode.base64_encode(a, s)
    ret out
}

// `encodeURIComponent`.
fn uri_component(a: *mem.Arena, s: str) -> str {
    let hex = "0123456789ABCDEF"
    let (out, e) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 45u8 || c == 95u8 || c == 46u8 || c == 33u8 || c == 126u8 || c == 42u8 || c == 39u8 || c == 40u8 || c == 41u8 {
            out[n] = c
            n += 1usize
        } else {
            out[n] = 37u8
            out[n + 1usize] = hex[usize(c >> 4u8)]
            out[n + 2usize] = hex[usize(c & 15u8)]
            n += 3usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// `k=v` pairs, dropping undefined, null and empty values, percent-encoded and `&`-joined.
fn encode_form(a: *mem.Arena, keys: []const str, values: []const json.Value, count: usize) -> str {
    var out = ""
    var n = 0usize
    var i = 0usize
    while i < count {
        let v = values[i]
        var skip = ir.is_null(v)
        switch v {
        case .String as s:
            if s.len == 0usize { skip = true }
        default:
            i += 0usize
        }
        if !skip {
            if n > 0usize { out = join(a, out, "&") }
            out = join(a, out, join(a, uri_component(a, keys[i]), join(a, "=", uri_component(a, js_string(a, v)))))
            n += 1usize
        }
        i += 1usize
    }
    ret out
}

fn body_text(a: *mem.Arena, request: json.Value) -> str {
    let (b, has) = ir.get(request, "body")
    if has {
        switch b {
        case .String as s:
            ret s
        default:
            let (text, e) = encode.json_encode(a, b)
            ret text
        }
    }
    let (text, e) = encode.json_encode(a, sv(""))
    ret text
}

fn replace_first(a: *mem.Arena, s: str, needle: str, with: str) -> str {
    var i = 0usize
    while i + needle.len <= s.len {
        if str.eq(s[i..i + needle.len], needle) {
            ret join(a, join(a, s[0usize..i], with), s[i + needle.len..])
        }
        i += 1usize
    }
    ret s
}

// The path of an absolute URL, `/` when it is not one.
fn path_of(url: str) -> str {
    var i = 0usize
    var colon = -1i64
    while i < url.len {
        if url[i] == 58u8 {
            colon = i64(i)
            break
        }
        i += 1usize
    }
    if colon < 1i64 { ret "/" }
    let rest = url[usize(colon) + 1usize..]
    if !str.starts_with(rest, "//") { ret "/" }
    var k = 2usize
    while k < rest.len && rest[k] != 47u8 && rest[k] != 63u8 && rest[k] != 35u8 { k += 1usize }
    if k == 2usize { ret "/" }
    var end = k
    while end < rest.len && rest[end] != 63u8 && rest[end] != 35u8 { end += 1usize }
    if end == k { ret "/" }
    ret rest[k..end]
}

fn host_of(a: *mem.Arena, url: str) -> str {
    var i = 0usize
    var colon = -1i64
    while i < url.len {
        if url[i] == 58u8 {
            colon = i64(i)
            break
        }
        i += 1usize
    }
    if colon < 1i64 { ret "" }
    let rest = url[usize(colon) + 1usize..]
    if !str.starts_with(rest, "//") { ret "" }
    var k = 2usize
    while k < rest.len && rest[k] != 47u8 && rest[k] != 63u8 && rest[k] != 35u8 { k += 1usize }
    var authority = rest[2usize..k]
    var at = authority.len
    while at > 0usize {
        if authority[at - 1usize] == 64u8 {
            authority = authority[at..]
            break
        }
        at -= 1usize
    }
    var end = authority.len
    var j = authority.len
    while j > 0usize {
        if authority[j - 1usize] == 58u8 {
            end = j - 1usize
            break
        }
        if authority[j - 1usize] == 93u8 { break }
        j -= 1usize
    }
    ret lower(a, authority[0usize..end])
}

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn infer_aws_service(a: *mem.Arena, url: str) -> str {
    let host = host_of(a, url)
    var end = 0usize
    while end < host.len && ((host[end] >= 97u8 && host[end] <= 122u8) || (host[end] >= 48u8 && host[end] <= 57u8) || host[end] == 45u8) { end += 1usize }
    if end > 0usize && end < host.len && host[end] == 46u8 {
        var label = host[0usize..end]
        // strip a trailing -<digits>
        var k = label.len
        while k > 0usize && label[k - 1usize] >= 48u8 && label[k - 1usize] <= 57u8 { k -= 1usize }
        if k < label.len && k > 0usize && label[k - 1usize] == 45u8 { label = label[0usize..k - 1usize] }
        ret label
    }
    ret "execute-api"
}

// --- the schemes ----------------------------------------------------------------------------------------------

fn known_scheme(t: str) -> bool {
    let all = [14]str{ "none", "basic", "bearer", "apiKey", "jwt", "oauth2", "oidc", "saml-bearer", "hmac", "awsSigV4", "mtls", "session", "custom", "webhook" }
    var i = 0usize
    while i < 14usize {
        if str.eq(all[i], t) { ret true }
        i += 1usize
    }
    ret false
}

// The request with an `error` and (unless the scheme is unknown) its headers and query copied, as `applyAuth` returns it.
fn with_error(a: *mem.Arena, request: json.Value, message: str) -> json.Value {
    var o = obj_of(a, request)
    put(&o, "error", sv(message))
    ret ir.obj_value(&o)
}

// The request with the connection's credentials applied, or with an `error` member naming why not.
fn apply_auth(a: *mem.Arena, connection: json.Value, request: json.Value, now_ms: f64) -> json.Value {
    var t = "none"
    let tv = ir.value_of(connection, "type")
    if ir.truthy(tv) { t = js_string(a, tv) }
    if !known_scheme(t) { ret with_error(a, request, join(a, "unknown-auth-scheme: ", t)) }
    var out = obj_of(a, request)
    var headers = obj_of(a, ir.value_of(request, "headers"))
    var query = obj_of(a, ir.value_of(request, "query"))
    var failed = ""
    if str.eq(t, "basic") {
        if !present(connection, "username") {
            failed = missing(a, "basic", "username")
        } else {
            var password = ""
            let (pv, has_pv) = ir.get(connection, "password")
            if has_pv && !ir.is_null(pv) { password = js_string(a, pv) }
            put(&headers, "Authorization", sv(join(a, "Basic ", base64(a, join(a, join(a, text_member(a, connection, "username"), ":"), password)))))
        }
    } else if str.eq(t, "bearer") {
        if !present(connection, "token") {
            failed = missing(a, "bearer", "token")
        } else {
            put(&headers, "Authorization", sv(join(a, join(a, or_text(a, connection, "prefix", "Bearer"), " "), text_member(a, connection, "token"))))
        }
    } else if str.eq(t, "apiKey") {
        if !present(connection, "key") {
            failed = missing(a, "apiKey", "key")
        } else {
            let key = text_member(a, connection, "key")
            let in_query = str.eq(or_text(a, connection, "in", ""), "query")
            var name = or_text(a, connection, "name", "")
            if name.len == 0usize {
                if in_query {
                    name = "api_key"
                } else {
                    name = "X-API-Key"
                }
            }
            if in_query {
                put(&query, name, connection_value(connection, "key"))
            } else {
                var value = key
                if ir.truthy(ir.value_of(connection, "template")) {
                    value = replace_first(a, js_string(a, ir.value_of(connection, "template")), "{key}", key)
                }
                let problem = header_problem(a, name, value, "apiKey")
                if problem.len > 0usize {
                    failed = problem
                } else {
                    put(&headers, name, sv(value))
                }
            }
        }
    } else if str.eq(t, "custom") {
        let (members, is_object) = ir.members_of(ir.value_of(connection, "headers"))
        var i = 0usize
        while i < members.len && failed.len == 0usize {
            let problem = header_problem(a, members[i].key, js_string(a, members[i].value), "custom")
            if problem.len > 0usize {
                failed = problem
            } else {
                put(&headers, members[i].key, members[i].value)
            }
            i += 1usize
        }
        if failed.len == 0usize {
            let (qm, qo) = ir.members_of(ir.value_of(connection, "query"))
            var k = 0usize
            while k < qm.len {
                put(&query, qm[k].key, qm[k].value)
                k += 1usize
            }
        }
    } else if str.eq(t, "jwt") {
        if !present(connection, "token") {
            failed = missing(a, "jwt", "token")
        } else {
            let token = text_member(a, connection, "token")
            let header = or_text(a, connection, "header", "")
            if header.len > 0usize {
                put(&headers, header, sv(token))
            } else {
                put(&headers, "Authorization", sv(join(a, join(a, or_text(a, connection, "prefix", "Bearer"), " "), token)))
            }
        }
    } else if str.eq(t, "oauth2") || str.eq(t, "oidc") {
        if !present(connection, "accessToken") {
            failed = missing(a, "oauth2", "accessToken")
        } else {
            put(&headers, "Authorization", sv(join(a, join(a, or_text(a, connection, "tokenType", "Bearer"), " "), text_member(a, connection, "accessToken"))))
        }
    } else if str.eq(t, "saml-bearer") {
        if !present(connection, "accessToken") {
            failed = missing(a, "saml-bearer", "accessToken")
        } else {
            put(&headers, "Authorization", sv(join(a, "Bearer ", text_member(a, connection, "accessToken"))))
        }
    } else if str.eq(t, "webhook") {
        if !present(connection, "url") {
            failed = missing(a, "webhook", "url")
        } else {
            put(&out, "url", connection_value(connection, "url"))
            if ir.truthy(ir.value_of(connection, "signingSecret")) {
                let timestamp = timestamp_text(a, connection, now_ms)
                let body = body_text(a, request)
                let signature = webhook.hmac_sha256(a, text_member(a, connection, "signingSecret"), join(a, join(a, timestamp, "."), body))
                put(&headers, or_text(a, connection, "header", "X-Appdor-Signature"), sv(signature))
                put(&headers, or_text(a, connection, "timestampHeader", "X-Appdor-Timestamp"), sv(timestamp))
            }
        }
    } else if str.eq(t, "hmac") {
        if !present(connection, "secret") {
            failed = missing(a, "hmac", "secret")
        } else {
            let timestamp = timestamp_text(a, connection, now_ms)
            let body = body_text(a, request)
            var canonical = or_text(a, connection, "canonical", "{timestamp}.{body}")
            canonical = replace_first(a, canonical, "{timestamp}", timestamp)
            canonical = replace_first(a, canonical, "{body}", body)
            var method = "POST"
            let mv = ir.value_of(request, "method")
            if ir.truthy(mv) { method = js_string(a, mv) }
            canonical = replace_first(a, canonical, "{method}", upper(a, method))
            canonical = replace_first(a, canonical, "{path}", path_of(js_string(a, ir.value_of(request, "url"))))
            let signature = webhook.hmac_sha256(a, text_member(a, connection, "secret"), canonical)
            var shown = signature
            let prefix = or_text(a, connection, "prefix", "")
            if prefix.len > 0usize { shown = join(a, prefix, signature) }
            put(&headers, or_text(a, connection, "header", "X-Signature"), sv(shown))
            let (th, has_th) = ir.get(connection, "timestampHeader")
            var emit = true
            if has_th {
                switch th {
                case .Bool as b:
                    if !b { emit = false }
                default:
                    emit = true
                }
            }
            if emit { put(&headers, or_text(a, connection, "timestampHeader", "X-Timestamp"), sv(timestamp)) }
        }
    } else if str.eq(t, "awsSigV4") {
        if !present(connection, "accessKeyId") {
            failed = missing(a, "awsSigV4", "accessKeyId")
        } else if !present(connection, "secretAccessKey") {
            failed = missing(a, "awsSigV4", "secretAccessKey")
        } else {
            var transport = obj_of(a, ir.value_of(request, "transport"))
            var sig = new_obj(a)
            put(&sig, "accessKeyId", connection_value(connection, "accessKeyId"))
            put(&sig, "secretAccessKey", connection_value(connection, "secretAccessKey"))
            let (st, has_st) = ir.get(connection, "sessionToken")
            if has_st { put(&sig, "sessionToken", st) }
            put(&sig, "region", sv(or_text(a, connection, "region", "us-east-1")))
            var service = or_text(a, connection, "service", "")
            if service.len == 0usize { service = infer_aws_service(a, js_string(a, ir.value_of(request, "url"))) }
            put(&sig, "service", sv(service))
            put(&transport, "sigv4", ir.obj_value(&sig))
            put(&out, "transport", ir.obj_value(&transport))
        }
    } else if str.eq(t, "mtls") {
        var transport = obj_of(a, ir.value_of(request, "transport"))
        var m = new_obj(a)
        let (c1, h1) = ir.get(connection, "certificate")
        let (c2, h2) = ir.get(connection, "privateKey")
        let (c3, h3) = ir.get(connection, "ca")
        if h1 { put(&m, "certificate", c1) }
        if h2 { put(&m, "privateKey", c2) }
        if h3 { put(&m, "ca", c3) }
        put(&transport, "mtls", ir.obj_value(&m))
        put(&out, "transport", ir.obj_value(&transport))
    } else if str.eq(t, "session") {
        if !present(connection, "cookie") {
            failed = missing(a, "session", "cookie")
        } else {
            put(&headers, "Cookie", connection_value(connection, "cookie"))
        }
    }
    put(&out, "headers", ir.obj_value(&headers))
    put(&out, "query", ir.obj_value(&query))
    if failed.len > 0usize { put(&out, "error", sv(failed)) }
    ret ir.obj_value(&out)
}

fn connection_value(connection: json.Value, key: str) -> json.Value { ret ir.value_of(connection, key) }

fn upper(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 97u8 && c <= 122u8 { c -= 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn timestamp_text(a: *mem.Arena, connection: json.Value, now_ms: f64) -> str {
    let (v, has) = ir.get(connection, "timestamp")
    if has && !ir.is_null(v) { ret js_string(a, v) }
    var t = f64(i64(now_ms / 1000.0f64))
    if t > now_ms / 1000.0f64 { t -= 1.0f64 }
    ret f.number_text(a, t)
}

fn number_member(connection: json.Value, key: str) -> (f64, bool) {
    switch ir.value_of(connection, key) {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        ret (x, true)
    default:
        ret (0.0f64, false)
    }
}

// Whether the stored token needs refreshing at `now_ms`.
fn needs_refresh(a: *mem.Arena, connection: json.Value, now_ms: f64) -> bool {
    let t = text_member(a, connection, "type")
    if str.eq(t, "jwt") {
        if !ir.truthy(ir.value_of(connection, "token")) { ret false }
        let d = jose.decode_jwt(a, text_member(a, connection, "token"))
        if !d.valid { ret false }
        let (exp, has) = number_member(d.payload, "exp")
        ret has && exp * 1000.0f64 - skew_ms() <= now_ms
    }
    if str.eq(t, "oauth2") || str.eq(t, "oidc") {
        if !ir.truthy(ir.value_of(connection, "accessToken")) { ret true }
        if !ir.truthy(ir.value_of(connection, "expiresAt")) { ret false }
        let (exp, has) = number_member(connection, "expiresAt")
        ret has && exp - skew_ms() <= now_ms
    }
    if str.eq(t, "saml-bearer") {
        if !ir.truthy(ir.value_of(connection, "accessToken")) { ret true }
        let (exp, has) = number_member(connection, "expiresAt")
        ret ir.truthy(ir.value_of(connection, "expiresAt")) && has && exp - skew_ms() <= now_ms
    }
    if str.eq(t, "session") {
        if !ir.truthy(ir.value_of(connection, "cookie")) { ret true }
        let (exp, has) = number_member(connection, "expiresAt")
        ret ir.truthy(ir.value_of(connection, "expiresAt")) && has && exp <= now_ms
    }
    ret false
}

fn refresh_failed(message: str) -> Refresh { ret Refresh { present: true, failed: true, message: message, request: .Null } }

fn form_request(a: *mem.Arena, url: str, headers: json.Value, body: str) -> json.Value {
    var req = new_obj(a)
    put(&req, "url", sv(url))
    put(&req, "method", sv("POST"))
    put(&req, "headers", headers)
    put(&req, "body", sv(body))
    var wrapper = new_obj(a)
    put(&wrapper, "request", ir.obj_value(&req))
    ret ir.obj_value(&wrapper)
}

// The token request for a connection that has one: its URL, form body and headers, or a refusal.
fn build_refresh(a: *mem.Arena, connection: json.Value) -> Refresh {
    let t = text_member(a, connection, "type")
    if str.eq(t, "oauth2") || str.eq(t, "oidc") {
        var scope = ir.value_of(connection, "scope")
        if str.eq(t, "oidc") && !ir.truthy(scope) { scope = sv("openid profile email") }
        var grant = or_text(a, connection, "grant", "")
        if grant.len == 0usize {
            if ir.truthy(ir.value_of(connection, "refreshToken")) {
                grant = "refresh_token"
            } else {
                grant = "client_credentials"
            }
        }
        let in_body = str.eq(text_member(a, connection, "clientAuth"), "body")
        let (keys, ke) = mem.alloc[str](a, 12usize)
        let (values, ve) = mem.alloc[json.Value](a, 12usize)
        var n = 0usize
        keys[n] = "grant_type"
        values[n] = sv(grant)
        n += 1usize
        keys[n] = "client_id"
        values[n] = ir.value_of(connection, "clientId")
        n += 1usize
        if in_body {
            keys[n] = "client_secret"
            values[n] = ir.value_of(connection, "clientSecret")
            n += 1usize
        }
        keys[n] = "scope"
        values[n] = scope
        n += 1usize
        if str.eq(grant, "refresh_token") {
            keys[n] = "refresh_token"
            values[n] = ir.value_of(connection, "refreshToken")
            n += 1usize
        }
        if str.eq(grant, "authorization_code") {
            keys[n] = "code"
            values[n] = ir.value_of(connection, "code")
            n += 1usize
            keys[n] = "redirect_uri"
            values[n] = ir.value_of(connection, "redirectUri")
            n += 1usize
            keys[n] = "code_verifier"
            values[n] = ir.value_of(connection, "codeVerifier")
            n += 1usize
        }
        if str.eq(grant, "password") {
            keys[n] = "username"
            values[n] = ir.value_of(connection, "username")
            n += 1usize
            keys[n] = "password"
            values[n] = ir.value_of(connection, "password")
            n += 1usize
        }
        if str.eq(grant, "device_code") {
            keys[n] = "device_code"
            values[n] = ir.value_of(connection, "deviceCode")
            n += 1usize
        }
        var headers = new_obj(a)
        put(&headers, "Content-Type", sv("application/x-www-form-urlencoded"))
        put(&headers, "Accept", sv("application/json"))
        if ir.truthy(ir.value_of(connection, "clientId")) && ir.truthy(ir.value_of(connection, "clientSecret")) && !in_body {
            put(&headers, "Authorization", sv(join(a, "Basic ", base64(a, join(a, join(a, text_member(a, connection, "clientId"), ":"), text_member(a, connection, "clientSecret"))))))
        }
        if !present(connection, "tokenUrl") { ret refresh_failed(missing(a, "oauth2", "tokenUrl")) }
        let body = encode_form(a, keys[0usize..n], values[0usize..n], n)
        ret Refresh { present: true, failed: false, message: "", request: form_request(a, text_member(a, connection, "tokenUrl"), ir.obj_value(&headers), body) }
    }
    if str.eq(t, "saml-bearer") {
        if !present(connection, "tokenUrl") { ret refresh_failed(missing(a, "saml-bearer", "tokenUrl")) }
        if !present(connection, "assertion") { ret refresh_failed(missing(a, "saml-bearer", "assertion")) }
        let keys = [4]str{ "grant_type", "assertion", "client_id", "scope" }
        let values = [4]json.Value{ sv("urn:ietf:params:oauth:grant-type:saml2-bearer"), ir.value_of(connection, "assertion"), ir.value_of(connection, "clientId"), ir.value_of(connection, "scope") }
        var headers = new_obj(a)
        put(&headers, "Content-Type", sv("application/x-www-form-urlencoded"))
        put(&headers, "Accept", sv("application/json"))
        let body = encode_form(a, keys[0usize..4usize], values[0usize..4usize], 4usize)
        ret Refresh { present: true, failed: false, message: "", request: form_request(a, text_member(a, connection, "tokenUrl"), ir.obj_value(&headers), body) }
    }
    if str.eq(t, "session") {
        if !present(connection, "loginUrl") { ret refresh_failed(missing(a, "session", "loginUrl")) }
        let keys = [2]str{ "username", "password" }
        let values = [2]json.Value{ ir.value_of(connection, "username"), ir.value_of(connection, "password") }
        var headers = new_obj(a)
        put(&headers, "Content-Type", sv("application/x-www-form-urlencoded"))
        let body = encode_form(a, keys[0usize..2usize], values[0usize..2usize], 2usize)
        ret Refresh { present: true, failed: false, message: "", request: form_request(a, text_member(a, connection, "loginUrl"), ir.obj_value(&headers), body) }
    }
    ret Refresh { present: false, failed: false, message: "", request: .Null }
}

// An OAuth token endpoint's answer as the fields to store; `oidc` adds `idToken` and its `claims`.
fn parse_token_response(a: *mem.Arena, response: json.Value, connection: json.Value, now_ms: f64, oidc: bool) -> Token {
    let (members, is_object) = ir.members_of(response)
    if !is_object { ret Token { valid: false, message: "token-endpoint-no-json", value: .Null } }
    let refusal = ir.value_of(response, "error")
    if ir.truthy(refusal) {
        var message = join(a, "token-endpoint-refused: ", js_string(a, refusal))
        let desc = ir.value_of(response, "error_description")
        if ir.truthy(desc) { message = join(a, message, join(a, " — ", js_string(a, desc))) }
        ret Token { valid: false, message: message, value: .Null }
    }
    if !ir.truthy(ir.value_of(response, "access_token")) { ret Token { valid: false, message: "token-endpoint-no-access_token", value: .Null } }
    var next = new_obj(a)
    put(&next, "accessToken", ir.value_of(response, "access_token"))
    put(&next, "tokenType", sv(or_text(a, response, "token_type", "Bearer")))
    var scope = ir.value_of(response, "scope")
    if !ir.truthy(scope) {
        let (cs, has) = ir.get(connection, "scope")
        if has { scope = cs }
    }
    if ir.truthy(scope) || ir.truthy(ir.value_of(response, "scope")) { put(&next, "scope", scope) }
    if ir.truthy(ir.value_of(response, "refresh_token")) { put(&next, "refreshToken", ir.value_of(response, "refresh_token")) }
    if ir.truthy(ir.value_of(response, "expires_in")) {
        let (secs, good) = webhook.js_number(js_string(a, ir.value_of(response, "expires_in")))
        if good { put(&next, "expiresAt", json.Value{ Number: json.Number{ lexeme: f.number_text(a, now_ms + secs * 1000.0f64) } }) }
    }
    if oidc && ir.truthy(ir.value_of(response, "id_token")) {
        put(&next, "idToken", ir.value_of(response, "id_token"))
        let d = jose.decode_jwt(a, js_string(a, ir.value_of(response, "id_token")))
        if d.valid { put(&next, "claims", d.payload) }
    }
    ret Token { valid: true, message: "", value: ir.obj_value(&next) }
}

fn is_secret_field(t: str, key: str) -> bool {
    if str.eq(t, "basic") { ret str.eq(key, "password") }
    if str.eq(t, "bearer") || str.eq(t, "jwt") { ret str.eq(key, "token") }
    if str.eq(t, "apiKey") { ret str.eq(key, "key") }
    if str.eq(t, "custom") { ret str.eq(key, "headers") }
    if str.eq(t, "oauth2") { ret str.eq(key, "clientSecret") || str.eq(key, "accessToken") || str.eq(key, "refreshToken") }
    if str.eq(t, "oidc") { ret str.eq(key, "clientSecret") || str.eq(key, "accessToken") || str.eq(key, "idToken") || str.eq(key, "refreshToken") }
    if str.eq(t, "saml-bearer") { ret str.eq(key, "assertion") || str.eq(key, "accessToken") }
    if str.eq(t, "webhook") { ret str.eq(key, "url") || str.eq(key, "signingSecret") }
    if str.eq(t, "hmac") { ret str.eq(key, "secret") }
    if str.eq(t, "awsSigV4") { ret str.eq(key, "secretAccessKey") || str.eq(key, "sessionToken") }
    if str.eq(t, "mtls") { ret str.eq(key, "privateKey") }
    if str.eq(t, "session") { ret str.eq(key, "cookie") || str.eq(key, "password") }
    ret false
}

// The connection with secret-looking and scheme-declared secret members masked as `***`.
fn redact_connection(a: *mem.Arena, connection: json.Value) -> json.Value {
    let t = text_member(a, connection, "type")
    let (members, is_object) = ir.members_of(connection)
    var out = new_obj(a)
    var i = 0usize
    while i < members.len {
        let key = members[i].key
        var secret = is_secret_field(t, key)
        if !secret {
            let lowered = lower(a, key)
            if str.contains(lowered, "secret") || str.contains(lowered, "password") || str.contains(lowered, "token") || str.contains(lowered, "key") || str.contains(lowered, "assertion") { secret = true }
        }
        if secret {
            put(&out, key, sv("***"))
        } else {
            put(&out, key, members[i].value)
        }
        i += 1usize
    }
    ret ir.obj_value(&out)
}

type Inbound = struct { valid: bool, reason: str }

// An inbound webhook's HMAC signature (the `hmac` scheme only), with an optional timestamp tolerance.
fn verify_inbound(a: *mem.Arena, connection: json.Value, headers: json.Value, body: json.Value, has_body: bool, now_ms: f64) -> Inbound {
    let t = text_member(a, connection, "type")
    if !str.eq(t, "hmac") { ret Inbound { valid: false, reason: join(a, "cannot-verify-inbound: ", js_string(a, ir.value_of(connection, "type"))) } }
    let secret = text_member(a, connection, "secret")
    if !ir.truthy(ir.value_of(connection, "secret")) { ret Inbound { valid: false, reason: "no-secret-configured" } }
    let header_name = lower(a, or_text(a, connection, "header", "X-Signature"))
    // a case-insensitive view of the headers, a later duplicate winning
    let (members, is_object) = ir.members_of(headers)
    var presented = ""
    var timestamp = ""
    let ts_name = lower(a, or_text(a, connection, "timestampHeader", "X-Timestamp"))
    var i = 0usize
    while i < members.len {
        let k = lower(a, members[i].key)
        if str.eq(k, header_name) {
            if ir.truthy(members[i].value) { presented = js_string(a, members[i].value) } else { presented = "" }
        }
        if str.eq(k, ts_name) {
            if ir.truthy(members[i].value) { timestamp = js_string(a, members[i].value) } else { timestamp = "" }
        }
        i += 1usize
    }
    if presented.len == 0usize { ret Inbound { valid: false, reason: "missing-signature" } }
    let tol = ir.value_of(connection, "toleranceSec")
    if ir.truthy(tol) && timestamp.len > 0usize {
        let (stamp, good) = webhook.js_number(timestamp)
        var tolerance = 0.0f64
        switch tol {
        case .Number as n:
            let (x, e) = json.number_f64(n)
            tolerance = x
        default:
            tolerance = 0.0f64
        }
        var age = now_ms / 1000.0f64 - stamp
        if age < 0.0f64 { age = 0.0f64 - age }
        if !good || age > tolerance { ret Inbound { valid: false, reason: "stale-timestamp" } }
    }
    var body_str = ""
    if has_body {
        switch body {
        case .String as s:
            body_str = s
        default:
            let (text, e) = encode.json_encode(a, body)
            body_str = text
        }
    }
    var canonical = or_text(a, connection, "canonical", "{timestamp}.{body}")
    canonical = replace_first(a, canonical, "{timestamp}", timestamp)
    canonical = replace_first(a, canonical, "{body}", body_str)
    let expected = webhook.hmac_sha256(a, secret, canonical)
    var stripped = presented
    let prefix = or_text(a, connection, "prefix", "")
    if prefix.len > 0usize && str.starts_with(presented, prefix) { stripped = presented[prefix.len..] }
    if webhook.timing_safe_equal(stripped, expected) { ret Inbound { valid: true, reason: "" } }
    ret Inbound { valid: false, reason: "signature-mismatch" }
}

// `application/x-www-form-urlencoded` of one component (space as `+`).
fn form_component(a: *mem.Arena, s: str) -> str {
    let hex = "0123456789ABCDEF"
    let (out, e) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 42u8 || c == 45u8 || c == 46u8 || c == 95u8 {
            out[n] = c
            n += 1usize
        } else if c == 32u8 {
            out[n] = 43u8
            n += 1usize
        } else {
            out[n] = 37u8
            out[n + 1usize] = hex[usize(c >> 4u8)]
            out[n + 2usize] = hex[usize(c & 15u8)]
            n += 3usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn form_decode(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 43u8 {
            out[n] = 32u8
            n += 1usize
            i += 1usize
        } else if c == 37u8 && i + 2usize < s.len + 0usize + 0usize && hex_val(s[i + 1usize]) >= 0i32 && hex_val(s[i + 2usize]) >= 0i32 {
            out[n] = u8(hex_val(s[i + 1usize]) * 16i32 + hex_val(s[i + 2usize]))
            n += 1usize
            i += 3usize
        } else {
            out[n] = c
            n += 1usize
            i += 1usize
        }
    }
    ret out[0usize..n]
}

fn hex_val(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 }
    if c >= 97u8 && c <= 102u8 { ret i32(c) - 87i32 }
    if c >= 65u8 && c <= 70u8 { ret i32(c) - 55i32 }
    ret -1i32
}

// The WHATWG path percent-encode set: controls, space, `"`, `<`, `>`, `` ` ``, `{`, `}` and non-ASCII bytes.
fn path_encode(a: *mem.Arena, s: str) -> str {
    let hex = "0123456789ABCDEF"
    let (out, e) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c <= 32u8 || c >= 127u8 || c == 34u8 || c == 60u8 || c == 62u8 || c == 96u8 || c == 123u8 || c == 125u8 {
            out[n] = 37u8
            out[n + 1usize] = hex[usize(c >> 4u8)]
            out[n + 2usize] = hex[usize(c & 15u8)]
            n += 3usize
        } else if c == 92u8 {
            out[n] = 47u8
            n += 1usize
        } else {
            out[n] = c
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// The authorization-code redirect URL: the endpoint with the standard parameters set (existing query kept, re-encoded).
fn build_authorize_url(a: *mem.Arena, connection: json.Value, redirect_uri: str, scope: str, state: str, code_challenge: str, prompt: str) -> Url {
    if !present(connection, "authorizeUrl") { ret Url { valid: false, message: missing(a, "oauth2", "authorizeUrl"), value: "" } }
    if !present(connection, "clientId") { ret Url { valid: false, message: missing(a, "oauth2", "clientId"), value: "" } }
    let raw = text_member(a, connection, "authorizeUrl")
    // scheme://authority path ?query #fragment
    var colon = -1i64
    var i = 0usize
    while i < raw.len {
        if raw[i] == 58u8 {
            colon = i64(i)
            break
        }
        i += 1usize
    }
    if colon < 1i64 || !str.starts_with(raw[usize(colon) + 1usize..], "//") { ret Url { valid: false, message: "Invalid URL", value: "" } }
    let scheme = lower(a, raw[0usize..usize(colon)])
    var rest = raw[usize(colon) + 3usize..]
    var fragment = ""
    var has_fragment = false
    var h = 0usize
    while h < rest.len {
        if rest[h] == 35u8 {
            fragment = rest[h + 1usize..]
            has_fragment = true
            rest = rest[0usize..h]
            break
        }
        h += 1usize
    }
    var query = ""
    var q = 0usize
    while q < rest.len {
        if rest[q] == 63u8 {
            query = rest[q + 1usize..]
            rest = rest[0usize..q]
            break
        }
        q += 1usize
    }
    var slash = 0usize
    while slash < rest.len && rest[slash] != 47u8 { slash += 1usize }
    var authority = rest[0usize..slash]
    var path = rest[slash..]
    if path.len == 0usize { path = "/" }
    path = path_encode(a, path)
    var userinfo = ""
    var at = authority.len
    while at > 0usize {
        if authority[at - 1usize] == 64u8 {
            userinfo = join(a, authority[0usize..at], "")
            authority = authority[at..]
            break
        }
        at -= 1usize
    }
    var host = authority
    var port = ""
    var j = authority.len
    while j > 0usize {
        if authority[j - 1usize] == 58u8 {
            host = authority[0usize..j - 1usize]
            port = authority[j..]
            break
        }
        if authority[j - 1usize] == 93u8 { break }
        j -= 1usize
    }
    host = lower(a, host)
    if host.len == 0usize { ret Url { valid: false, message: "Invalid URL", value: "" } }
    if (str.eq(scheme, "http") && str.eq(port, "80")) || (str.eq(scheme, "https") && str.eq(port, "443")) { port = "" }
    // existing pairs (form-decoded), then the parameters set in order
    let (names, e1) = mem.alloc[str](a, query.len + 16usize)
    let (vals, e2) = mem.alloc[str](a, query.len + 16usize)
    var count = 0usize
    var start = 0usize
    var k = 0usize
    while k <= query.len {
        if k == query.len || query[k] == 38u8 {
            let piece = query[start..k]
            start = k + 1usize
            if piece.len > 0usize {
                var eq = piece.len
                var m = 0usize
                while m < piece.len {
                    if piece[m] == 61u8 {
                        eq = m
                        break
                    }
                    m += 1usize
                }
                names[count] = form_decode(a, piece[0usize..eq])
                if eq < piece.len {
                    vals[count] = form_decode(a, piece[eq + 1usize..])
                } else {
                    vals[count] = ""
                }
                count += 1usize
            }
        }
        k += 1usize
    }
    let set_keys = [8]str{ "response_type", "client_id", "redirect_uri", "scope", "state", "code_challenge", "code_challenge_method", "access_type" }
    var set_vals: [8]str = zero
    var set_has: [8]bool = zero
    set_vals[0] = "code"
    set_has[0] = true
    set_vals[1] = text_member(a, connection, "clientId")
    set_has[1] = true
    var redirect = redirect_uri
    if redirect.len == 0usize { redirect = text_member(a, connection, "redirectUri") }
    set_vals[2] = redirect
    set_has[2] = redirect.len > 0usize
    var scope_text = scope
    if scope_text.len == 0usize { scope_text = text_member(a, connection, "scope") }
    set_vals[3] = scope_text
    set_has[3] = scope_text.len > 0usize
    set_vals[4] = state
    set_has[4] = state.len > 0usize
    if code_challenge.len > 0usize {
        set_vals[5] = code_challenge
        set_has[5] = true
        set_vals[6] = "S256"
        set_has[6] = true
    }
    set_vals[7] = text_member(a, connection, "accessType")
    set_has[7] = set_vals[7].len > 0usize
    var s = 0usize
    while s < 8usize {
        if set_has[s] { set_param(names, vals, &count, set_keys[s], set_vals[s]) }
        s += 1usize
    }
    if prompt.len > 0usize { set_param(names, vals, &count, "prompt", prompt) }
    var out = join(a, join(a, scheme, "://"), join(a, userinfo, host))
    if port.len > 0usize { out = join(a, out, join(a, ":", port)) }
    out = join(a, out, path)
    if count > 0usize {
        out = join(a, out, "?")
        var p = 0usize
        while p < count {
            if p > 0usize { out = join(a, out, "&") }
            out = join(a, out, join(a, form_component(a, names[p]), join(a, "=", form_component(a, vals[p]))))
            p += 1usize
        }
    }
    if has_fragment { out = join(a, out, join(a, "#", fragment)) }
    ret Url { valid: true, message: "", value: out }
}

fn set_param(names: []str, vals: []str, count: *usize, key: str, value: str) {
    var found = -1i64
    var i = 0usize
    while i < *count {
        if str.eq(names[i], key) {
            if found < 0i64 {
                found = i64(i)
                vals[i] = value
            } else {
                // remove later duplicates
                var k = i + 1usize
                while k < *count {
                    names[k - 1usize] = names[k]
                    vals[k - 1usize] = vals[k]
                    k += 1usize
                }
                *count -= 1usize
                i -= 1usize
            }
        }
        i += 1usize
    }
    if found < 0i64 {
        names[*count] = key
        vals[*count] = value
        *count += 1usize
    }
}
