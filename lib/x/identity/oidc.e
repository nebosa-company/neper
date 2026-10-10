// OpenID Connect relying party, authorization code flow with PKCE (L045), after Appdor's `src/identity/oidc.js`: the
// discovery document, the authorization request and the token request as values (the host fetches and redirects), the
// callback check, and ID token validation in the order of OpenID Connect Core 3.1.3.7 -- signature, issuer, audience,
// time, nonce, `max_age` -- through `x.identity.jose`. Also the profile read from claims and the account-link policy.
// Query strings use the `application/x-www-form-urlencoded` rules of `URLSearchParams` (space is `+`, `*-._` and
// alphanumerics stay, the rest is `%XX`), in the reference's parameter order.
//
// ponytail: claim values that a token can carry as numbers, arrays or objects are read as strings where the reference
// reads them as JavaScript values (`groups`, `email`), and an `extra` authorization parameter is a string.
//
// Memory: the arena is retained.

use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.crypto.hash as hash
use e.fmt.encode as encode
use e.fmt.json as json
use e.mem
use e.str
use x.identity.jose as jose

fn default_skew_seconds() -> f64 { ret 60.0f64 }

type Config = struct { issuer: str, authorization_endpoint: str, token_endpoint: str, jwks_uri: str, has_userinfo: bool, userinfo_endpoint: str, has_end_session: bool, end_session_endpoint: str, scopes_supported: []const str, response_types_supported: []const str, id_token_signing_alg_values_supported: []const str, code_challenge_methods_supported: []const str }

type Discovery = struct { valid: bool, missing: []const str, config: Config }

type Pair = struct { key: str, value: str }

type AuthRequest = struct { client_id: str, redirect_uri: str, scope: str, state: str, nonce: str, code_challenge: str, prompt: str, login_hint: str, extra: []const Pair }

type Url = struct { valid: bool, missing: []const str, url: str }

type Callback = struct { valid: bool, error_code: str, has_description: bool, description: str, code: str, state: str }

type TokenRequest = struct { valid: bool, missing: []const str, url: str, body: str, has_authorization: bool, authorization: str }

type Expectations = struct { issuer: str, client_id: str, nonce: str, jwks: json.Value, now_ms: f64, has_max_age: bool, max_age_seconds: f64, has_skew: bool, skew_seconds: f64 }

type Validation = struct { valid: bool, message: str, claims: json.Value }

type Profile = struct { has_subject: bool, subject: str, has_email: bool, email: str, email_verified: bool, has_name: bool, name: str, has_given_name: bool, given_name: str, has_family_name: bool, family_name: str, groups: []const str, has_issuer: bool, issuer: str }

type Link = struct { action: str, reason: str }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn text_of(v: json.Value, key: str) -> (str, bool) {
    let (x, found) = ir.get(v, key)
    if !found { ret ("", false) }
    let (s, is_text) = ir.string_of(x)
    ret (s, is_text)
}

// The strings of an array value, or `fallback` when the value is absent or falsy.
fn strings_or(a: *mem.Arena, v: json.Value, key: str, fallback: []const str) -> []const str {
    let x = ir.value_of(v, key)
    if !ir.truthy(x) { ret fallback }
    let (xs, is_array) = ir.items_of(x)
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { ret fallback }
    var i = 0usize
    while i < xs.len {
        let (s, is_text) = ir.string_of(xs[i])
        out[i] = s
        i += 1usize
    }
    ret out[0usize..xs.len]
}

fn list_of(a: *mem.Arena, xs: []const str) -> []const str {
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { ret xs }
    var i = 0usize
    while i < xs.len {
        out[i] = xs[i]
        i += 1usize
    }
    ret out[0usize..xs.len]
}

// The OpenID Provider discovery document: `valid` false with the missing keys, or the configuration.
fn parse_discovery(a: *mem.Arena, document: json.Value) -> Discovery {
    let (missing, me) = mem.alloc[str](a, 5usize)
    if me != ok { ret Discovery { valid: false, missing: zero, config: zero } }
    var n = 0usize
    let keys = [4]str{ "issuer", "authorization_endpoint", "token_endpoint", "jwks_uri" }
    var k = 0usize
    while k < 4usize {
        let v = ir.value_of(document, keys[k])
        if !ir.truthy(v) {
            missing[n] = keys[k]
            n += 1usize
        }
        k += 1usize
    }
    if n > 0usize { ret Discovery { valid: false, missing: missing[0usize..n], config: zero } }
    let (issuer, i1) = text_of(document, "issuer")
    let (auth, i2) = text_of(document, "authorization_endpoint")
    let (token, i3) = text_of(document, "token_endpoint")
    let (jwks, i4) = text_of(document, "jwks_uri")
    let (userinfo, has_userinfo) = text_of(document, "userinfo_endpoint")
    let (end_session, has_end) = text_of(document, "end_session_endpoint")
    let default_scopes = [3]str{ "openid", "profile", "email" }
    let default_types = [1]str{ "code" }
    let default_algs = [1]str{ "RS256" }
    let none: []const str = zero
    let cfg = Config {
        issuer: issuer,
        authorization_endpoint: auth,
        token_endpoint: token,
        jwks_uri: jwks,
        has_userinfo: has_userinfo && userinfo.len > 0usize,
        userinfo_endpoint: userinfo,
        has_end_session: has_end && end_session.len > 0usize,
        end_session_endpoint: end_session,
        scopes_supported: strings_or(a, document, "scopes_supported", list_of(a, default_scopes[0usize..3usize])),
        response_types_supported: strings_or(a, document, "response_types_supported", list_of(a, default_types[0usize..1usize])),
        id_token_signing_alg_values_supported: strings_or(a, document, "id_token_signing_alg_values_supported", list_of(a, default_algs[0usize..1usize])),
        code_challenge_methods_supported: strings_or(a, document, "code_challenge_methods_supported", none),
    }
    ret Discovery { valid: true, missing: none, config: cfg }
}

// The well-known discovery URL for an issuer.
fn discovery_url(a: *mem.Arena, issuer: str) -> str {
    var end = issuer.len
    while end > 0usize && issuer[end - 1usize] == 47u8 { end -= 1usize }
    ret join(a, issuer[0usize..end], "/.well-known/openid-configuration")
}

// base64url(SHA-256(verifier)).
fn pkce_challenge(a: *mem.Arena, verifier: str) -> str {
    let digest = hash.sha256(verifier)
    ret jose.base64url_encode(a, digest[0usize..32usize])
}

fn same_text(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var r = 0u8
    var i = 0usize
    while i < x.len {
        r = r | (x[i] ^ y[i])
        i += 1usize
    }
    ret r == 0u8
}

// A presented verifier against a stored challenge, in constant time.
fn verify_pkce(a: *mem.Arena, code_verifier: str, code_challenge: str) -> bool {
    ret same_text(pkce_challenge(a, code_verifier), code_challenge)
}

// The verifier for 32 random bytes the caller supplies, and its S256 challenge.
fn create_pkce_pair(a: *mem.Arena, random: []const u8) -> Pair {
    let verifier = jose.base64url_encode(a, random)
    ret Pair { key: verifier, value: pkce_challenge(a, verifier) }
}

fn form_hex(n: u8) -> u8 {
    if n < 10u8 { ret 48u8 + n }
    ret 55u8 + n
}

// `application/x-www-form-urlencoded` text of one component.
fn form_encode(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    if e != ok { ret "" }
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
            out[n + 1usize] = form_hex(c >> 4u8)
            out[n + 2usize] = form_hex(c & 15u8)
            n += 3usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// Ordered parameters with `URLSearchParams.set`: an existing key keeps its place, a new one is appended.
type Params = struct { keys: []str, values: []str, count: usize }

fn params_new(a: *mem.Arena, capacity: usize) -> Params {
    let (keys, ke) = mem.alloc[str](a, capacity + 1usize)
    let (values, ve) = mem.alloc[str](a, capacity + 1usize)
    ret Params { keys: keys, values: values, count: 0usize }
}

fn params_set(p: *Params, key: str, value: str) {
    var i = 0usize
    while i < p.count {
        if str.eq(p.keys[i], key) {
            p.values[i] = value
            ret
        }
        i += 1usize
    }
    p.keys[p.count] = key
    p.values[p.count] = value
    p.count += 1usize
}

fn params_text(a: *mem.Arena, p: *const Params) -> str {
    var out = ""
    var i = 0usize
    while i < p.count {
        if i > 0usize { out = join(a, out, "&") }
        out = join(a, join(a, out, form_encode(a, p.keys[i])), join(a, "=", form_encode(a, p.values[i])))
        i += 1usize
    }
    ret out
}

fn missing_list(a: *mem.Arena, names: []const str, present: []const bool) -> []const str {
    let (out, e) = mem.alloc[str](a, names.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < names.len {
        if !present[i] {
            out[n] = names[i]
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// The authorization request URL; `missing` names the required inputs that were empty.
fn build_authorization_url(a: *mem.Arena, config: Config, r: AuthRequest) -> Url {
    let names = [5]str{ "clientId", "redirectUri", "state", "nonce", "codeChallenge" }
    let present = [5]bool{ r.client_id.len > 0usize, r.redirect_uri.len > 0usize, r.state.len > 0usize, r.nonce.len > 0usize, r.code_challenge.len > 0usize }
    let missing = missing_list(a, names[0usize..5usize], present[0usize..5usize])
    if missing.len > 0usize { ret Url { valid: false, missing: missing, url: "" } }
    var p = params_new(a, 10usize + r.extra.len)
    params_set(&p, "response_type", "code")
    params_set(&p, "client_id", r.client_id)
    params_set(&p, "redirect_uri", r.redirect_uri)
    if r.scope.len > 0usize {
        params_set(&p, "scope", r.scope)
    } else {
        params_set(&p, "scope", "openid profile email")
    }
    params_set(&p, "state", r.state)
    params_set(&p, "nonce", r.nonce)
    params_set(&p, "code_challenge", r.code_challenge)
    params_set(&p, "code_challenge_method", "S256")
    if r.prompt.len > 0usize { params_set(&p, "prompt", r.prompt) }
    if r.login_hint.len > 0usize { params_set(&p, "login_hint", r.login_hint) }
    var i = 0usize
    while i < r.extra.len {
        params_set(&p, r.extra[i].key, r.extra[i].value)
        i += 1usize
    }
    let query = params_text(a, &p)
    ret Url { valid: true, missing: zero, url: join(a, join(a, config.authorization_endpoint, "?"), query) }
}

// The callback query (an object of strings) against the state the request carried.
fn parse_callback(a: *mem.Arena, params: json.Value, expected_state: str) -> Callback {
    let err_value = ir.value_of(params, "error")
    if ir.truthy(err_value) {
        let (code, c) = text_of(params, "error")
        let (description, has) = text_of(params, "error_description")
        ret Callback { valid: false, error_code: code, has_description: has && description.len > 0usize, description: description, code: "", state: "" }
    }
    let (state, has_state) = text_of(params, "state")
    if !has_state || state.len == 0usize || !same_text(state, expected_state) {
        ret Callback { valid: false, error_code: "state-mismatch", has_description: true, description: "the callback state does not match the request", code: "", state: "" }
    }
    let (code, has_code) = text_of(params, "code")
    if !has_code || code.len == 0usize {
        ret Callback { valid: false, error_code: "missing-code", has_description: false, description: "", code: "", state: "" }
    }
    ret Callback { valid: true, error_code: "", has_description: false, description: "", code: code, state: state }
}

// The token request body, and `client_secret_basic` authorization when a secret is supplied.
fn build_token_request(a: *mem.Arena, config: Config, client_id: str, client_secret: str, code: str, redirect_uri: str, code_verifier: str) -> TokenRequest {
    let names = [4]str{ "clientId", "code", "redirectUri", "codeVerifier" }
    let present = [4]bool{ client_id.len > 0usize, code.len > 0usize, redirect_uri.len > 0usize, code_verifier.len > 0usize }
    let missing = missing_list(a, names[0usize..4usize], present[0usize..4usize])
    if missing.len > 0usize {
        ret TokenRequest { valid: false, missing: missing, url: "", body: "", has_authorization: false, authorization: "" }
    }
    var p = params_new(a, 5usize)
    params_set(&p, "grant_type", "authorization_code")
    params_set(&p, "code", code)
    params_set(&p, "redirect_uri", redirect_uri)
    params_set(&p, "client_id", client_id)
    params_set(&p, "code_verifier", code_verifier)
    var authorization = ""
    var has = false
    if client_secret.len > 0usize {
        let (b, e) = encode.base64_encode(a, join(a, join(a, client_id, ":"), client_secret))
        authorization = join(a, "Basic ", b)
        has = true
    }
    ret TokenRequest { valid: true, missing: zero, url: config.token_endpoint, body: params_text(a, &p), has_authorization: has, authorization: authorization }
}

fn absent_or(a: *mem.Arena, v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "undefined" }
    let (s, is_text) = ir.string_of(x)
    if is_text { ret s }
    let (text, e) = chain.canonical_json(a, x)
    ret text
}

fn rejected(msg: str) -> Validation {
    ret Validation { valid: false, message: msg, claims: .Null }
}

fn number_claim(v: json.Value, key: str) -> (f64, bool) {
    let (x, found) = ir.get(v, key)
    if !found { ret (0.0f64, false) }
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret (value, true)
    default:
        ret (0.0f64, false)
    }
}

fn floor_f64(x: f64) -> f64 {
    var t = f64(i64(x))
    if t > x { t -= 1.0f64 }
    ret t
}

// An ID token against what the request expected, in the order of Core 3.1.3.7.
fn validate_id_token(a: *mem.Arena, id_token: str, ex: Expectations) -> Validation {
    let d = jose.decode_jwt(a, id_token)
    if !d.valid { ret rejected(d.message) }
    let (jwk, has_jwk) = jose.select_jwk(ex.jwks, d.header)
    if !has_jwk { ret rejected("no-matching-key") }
    let (sig_ok, sig_error) = jose.verify_jwt_signature(a, id_token, jwk, true)
    if !sig_ok { ret rejected(sig_error) }
    var claims = d.payload
    if !ir.truthy(claims) {
        let (o, oe) = ir.new_obj(a)
        var obj = o
        claims = ir.obj_value(&obj)
    }
    var skew = default_skew_seconds()
    if ex.has_skew { skew = ex.skew_seconds }
    let now = floor_f64(ex.now_ms / 1000.0f64)
    let (iss, has_iss) = text_of(claims, "iss")
    if ex.issuer.len == 0usize || !has_iss || !str.eq(iss, ex.issuer) {
        ret rejected(join(a, "issuer mismatch: ", absent_or(a, claims, "iss")))
    }
    // The audience: one string or an array of them.
    var listed = false
    var count = 1usize
    let aud = ir.value_of(claims, "aud")
    let (auds, is_array) = ir.items_of(aud)
    if is_array {
        count = auds.len
        var i = 0usize
        while i < auds.len {
            let (s, is_text) = ir.string_of(auds[i])
            if is_text && str.eq(s, ex.client_id) { listed = true }
            i += 1usize
        }
    } else {
        let (s, is_text) = ir.string_of(aud)
        if is_text && str.eq(s, ex.client_id) { listed = true }
    }
    if ex.client_id.len == 0usize || !listed {
        var shown = "undefined"
        let (found_aud, has_aud) = ir.get(claims, "aud")
        if has_aud {
            let (text, te) = chain.canonical_json(a, found_aud)
            shown = text
        }
        ret rejected(join(a, "audience mismatch: ", shown))
    }
    if count > 1usize {
        let azp = ir.value_of(claims, "azp")
        if ir.truthy(azp) {
            let (s, is_text) = ir.string_of(azp)
            if !is_text || !str.eq(s, ex.client_id) { ret rejected("azp is not this client") }
        }
    }
    let (exp, has_exp) = number_claim(claims, "exp")
    if !has_exp { ret rejected("missing exp") }
    if now > exp + skew { ret rejected("token expired") }
    let (nbf, has_nbf) = number_claim(claims, "nbf")
    if has_nbf && now + skew < nbf { ret rejected("token not yet valid") }
    let (iat, has_iat) = number_claim(claims, "iat")
    if has_iat && iat - skew > now { ret rejected("issued in the future") }
    if ex.nonce.len > 0usize {
        var seen = ""
        let nv = ir.value_of(claims, "nonce")
        if ir.truthy(nv) {
            let (s, is_text) = ir.string_of(nv)
            if is_text { seen = s }
        }
        if !same_text(seen, ex.nonce) { ret rejected("nonce mismatch") }
    }
    if ex.has_max_age {
        let (auth_time, has_auth) = number_claim(claims, "auth_time")
        if !has_auth { ret rejected("max_age requested but auth_time is absent") }
        if now - auth_time > ex.max_age_seconds + skew { ret rejected("authentication too old for max_age") }
    }
    ret Validation { valid: true, message: "", claims: claims }
}

fn mapped(claims: json.Value, mapping: []const Pair, key: str, fallback: str) -> (str, bool) {
    var name = fallback
    var i = 0usize
    while i < mapping.len {
        if str.eq(mapping[i].key, key) && mapping[i].value.len > 0usize { name = mapping[i].value }
        i += 1usize
    }
    let (s, found) = text_of(claims, name)
    ret (s, found)
}

fn truthy_text(claims: json.Value, name: str) -> (str, bool) {
    let (s, is_text) = text_of(claims, name)
    if is_text && s.len > 0usize { ret (s, true) }
    ret ("", false)
}

// Validated claims as the profile the product provisions from; `mapping` renames `email`, `name` or `groups`.
fn profile_from_claims(a: *mem.Arena, claims: json.Value, mapping: []const Pair) -> Profile {
    let (subject, has_subject) = text_of(claims, "sub")
    let (email, email_found) = mapped(claims, mapping, "email", "email")
    let has_email = email_found && email.len > 0usize
    let (mapped_name, name_found) = mapped(claims, mapping, "name", "name")
    var name = mapped_name
    var has_name = name_found && name.len > 0usize
    if !has_name {
        let (pu, has_pu) = truthy_text(claims, "preferred_username")
        name = pu
        has_name = has_pu
    }
    let (given, has_given) = truthy_text(claims, "given_name")
    let (family, has_family) = truthy_text(claims, "family_name")
    let (issuer, has_issuer) = text_of(claims, "iss")
    var verified = false
    let verified_value = ir.value_of(claims, "email_verified")
    switch verified_value {
    case .Bool as b:
        verified = b
    default:
        verified = false
    }
    // groups ?? roles: an array is the list, a truthy string a one-element list.
    var groups: []const str = zero
    var raw = ir.value_of(claims, "groups")
    var i = 0usize
    while i < mapping.len {
        if str.eq(mapping[i].key, "groups") && mapping[i].value.len > 0usize {
            raw = ir.value_of(claims, mapping[i].value)
        }
        i += 1usize
    }
    if ir.is_null(raw) { raw = ir.value_of(claims, "roles") }
    let (items, is_array) = ir.items_of(raw)
    if is_array {
        let (out, e) = mem.alloc[str](a, items.len + 1usize)
        var k = 0usize
        while k < items.len {
            let (s, is_text) = ir.string_of(items[k])
            out[k] = s
            k += 1usize
        }
        groups = out[0usize..items.len]
    } else if ir.truthy(raw) {
        let (s, is_text) = ir.string_of(raw)
        let (out, e) = mem.alloc[str](a, 1usize)
        out[0] = s
        groups = out[0usize..1usize]
    }
    ret Profile {
        has_subject: has_subject,
        subject: subject,
        has_email: has_email,
        email: email,
        email_verified: verified,
        has_name: has_name,
        name: name,
        has_given_name: has_given,
        given_name: given,
        has_family_name: has_family,
        family_name: family,
        groups: groups,
        has_issuer: has_issuer,
        issuer: issuer,
    }
}

fn lower_ascii(a: *mem.Arena, s: str) -> str {
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

// Whether an assertion may be linked to, or provisioned as, a local account.
fn link_policy(a: *mem.Arena, p: Profile, verified_domains: []const str, existing_account: bool, allow_unverified_email_link: bool) -> Link {
    if !p.has_email { ret Link { action: "deny", reason: "no-email-in-assertion" } }
    // The text after the first `@` and before the next, or empty.
    var domain = ""
    var at = 0usize
    while at < p.email.len && p.email[at] != 64u8 { at += 1usize }
    if at < p.email.len {
        var end = at + 1usize
        while end < p.email.len && p.email[end] != 64u8 { end += 1usize }
        domain = p.email[at + 1usize..end]
    }
    let want = lower_ascii(a, domain)
    var verified = false
    var i = 0usize
    while i < verified_domains.len {
        if str.eq(lower_ascii(a, verified_domains[i]), want) { verified = true }
        i += 1usize
    }
    if !existing_account {
        if !verified { ret Link { action: "deny", reason: "unverified-domain" } }
        ret Link { action: "provision", reason: "new-user-in-verified-domain" }
    }
    if !p.email_verified && !allow_unverified_email_link {
        ret Link { action: "deny", reason: "unverified-email-cannot-claim-existing-account" }
    }
    if !verified { ret Link { action: "deny", reason: "unverified-domain" } }
    ret Link { action: "link", reason: "verified-domain-and-email" }
}

// The RP-initiated logout URL; `valid` false when the provider has no end-session endpoint.
fn build_logout_url(a: *mem.Arena, config: Config, id_token_hint: str, post_logout_redirect_uri: str, state: str) -> Url {
    if !config.has_end_session { ret Url { valid: false, missing: zero, url: "" } }
    var p = params_new(a, 3usize)
    if id_token_hint.len > 0usize { params_set(&p, "id_token_hint", id_token_hint) }
    if post_logout_redirect_uri.len > 0usize { params_set(&p, "post_logout_redirect_uri", post_logout_redirect_uri) }
    if state.len > 0usize { params_set(&p, "state", state) }
    let query = params_text(a, &p)
    if query.len == 0usize { ret Url { valid: true, missing: zero, url: config.end_session_endpoint } }
    ret Url { valid: true, missing: zero, url: join(a, join(a, config.end_session_endpoint, "?"), query) }
}
