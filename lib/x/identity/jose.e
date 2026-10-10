// The JOSE subset an OpenID Connect relying party needs (L045), after Appdor's `src/identity/jose.js`: lenient base64url,
// JWT decoding without verification, and RS256 verification over `e.crypto.sign`'s PKCS#1 v1.5 check, plus key
// selection from a JWKS. A verifier only: `alg: none`, PSS and the EC families are refused by name, because accepting an
// unverified token is the failure this exists to stop. `decode_jwt` reports a malformed token as `malformed JWT` (the
// reference appends its JSON engine's own message).
//
// ponytail: a modulus over 4096 bits is not verified (the bignum buffer), and a modulus encoded with a leading zero byte
// is measured by its value, not its text, so a signature the reference's length check refuses may verify here.
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.algo.ir as ir
use e.crypto.sign as sign
use e.fmt.json as json
use e.mem
use e.str

type Decoded = struct { valid: bool, message: str, header: json.Value, payload: json.Value, signature: str, signing_input: str }

fn b64_index(c: u8) -> i32 {
    if c >= 65u8 && c <= 90u8 { ret i32(c) - 65i32 }
    if c >= 97u8 && c <= 122u8 { ret i32(c) - 71i32 }
    if c >= 48u8 && c <= 57u8 { ret i32(c) + 4i32 }
    if c == 45u8 || c == 43u8 { ret 62i32 }
    if c == 95u8 || c == 47u8 { ret 63i32 }
    ret -1i32
}

// base64url to bytes, as the reference reads it: trailing `=` dropped, `+` and `/` taken as `-` and `_`, anything else
// outside the alphabet skipped, leftover bits discarded.
fn base64url_decode(a: *mem.Arena, s: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret out }
    var end = s.len
    while end > 0usize && s[end - 1usize] == 61u8 { end -= 1usize }
    var buffer = 0u32
    var bits = 0u32
    var n = 0usize
    var i = 0usize
    while i < end {
        let v = b64_index(s[i])
        i += 1usize
        if v < 0i32 { continue }
        buffer = ((buffer << 6u32) | u32(v)) & 16777215u32
        bits += 6u32
        if bits >= 8u32 {
            bits -= 8u32
            out[n] = u8((buffer >> bits) & 255u32)
            n += 1usize
        }
    }
    ret out[0usize..n]
}

// Unpadded base64url of `bytes`.
fn base64url_encode(a: *mem.Arena, bytes: []const u8) -> str {
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    let (out, e) = mem.alloc[u8](a, bytes.len / 3usize * 4usize + 5usize)
    if e != ok { ret "" }
    var n = 0usize
    var i = 0usize
    while i < bytes.len {
        let b0 = u32(bytes[i])
        var b1 = 0u32
        var b2 = 0u32
        let has1 = i + 1usize < bytes.len
        let has2 = i + 2usize < bytes.len
        if has1 { b1 = u32(bytes[i + 1usize]) }
        if has2 { b2 = u32(bytes[i + 2usize]) }
        out[n] = alphabet[usize(b0 >> 2u32)]
        out[n + 1usize] = alphabet[usize(((b0 & 3u32) << 4u32) | (b1 >> 4u32))]
        n += 2usize
        if !has1 { break }
        out[n] = alphabet[usize(((b1 & 15u32) << 2u32) | (b2 >> 6u32))]
        n += 1usize
        if !has2 { break }
        out[n] = alphabet[usize(b2 & 63u32)]
        n += 1usize
        i += 3usize
    }
    ret out[0usize..n]
}

fn failed(msg: str) -> Decoded {
    ret Decoded { valid: false, message: msg, header: .Null, payload: .Null, signature: "", signing_input: "" }
}

// A JWT's header and payload without verifying anything.
fn decode_jwt(a: *mem.Arena, token: str) -> Decoded {
    var dots = 0usize
    var first = 0usize
    var second = 0usize
    var i = 0usize
    while i < token.len {
        if token[i] == 46u8 {
            dots += 1usize
            if dots == 1usize { first = i }
            if dots == 2usize { second = i }
        }
        i += 1usize
    }
    if dots != 2usize { ret failed("not a three-part JWT") }
    let head_bytes = base64url_decode(a, token[0usize..first])
    let body_bytes = base64url_decode(a, token[first + 1usize..second])
    let (header, he) = json.parse(a, head_bytes, json.Options { allow_duplicate_keys: true, max_depth: 64u16 })
    if he != ok { ret failed("malformed JWT") }
    let (payload, pe) = json.parse(a, body_bytes, json.Options { allow_duplicate_keys: true, max_depth: 64u16 })
    if pe != ok { ret failed("malformed JWT") }
    ret Decoded { valid: true, message: "", header: header, payload: payload, signature: token[second + 1usize..], signing_input: token[0usize..second] }
}

// An RSASSA-PKCS1-v1_5 SHA-256 signature over `message`, against a JWK's base64url modulus and exponent.
fn verify_rs256(a: *mem.Arena, message: []const u8, signature: []const u8, n: str, e: str) -> bool {
    if n.len == 0usize || e.len == 0usize { ret false }
    let modulus = base64url_decode(a, n)
    let exponent = base64url_decode(a, e)
    if modulus.len == 0usize || exponent.len == 0usize { ret false }
    ret sign.rsa_pkcs1v15_verify(a, modulus, exponent, message, signature)
}

fn text_of(v: json.Value, key: str) -> (str, bool) {
    let (x, found) = ir.get(v, key)
    if !found { ret ("", false) }
    let (s, is_text) = ir.string_of(x)
    ret (s, is_text)
}

// `String(value)` for what an `alg` or `kty` can be in a token a test sends: a string, number or boolean.
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
    default:
        ret "[object Object]"
    }
}

fn lowered_is_none(s: str) -> bool {
    if s.len != 4usize { ret false }
    let want = "none"
    var i = 0usize
    while i < 4usize {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        if c != want[i] { ret false }
        i += 1usize
    }
    ret true
}

// A token's signature against a JWK (`jwk` an object value; `has_jwk` false for none).
fn verify_jwt_signature(a: *mem.Arena, token: str, jwk: json.Value, has_jwk: bool) -> (bool, str) {
    let d = decode_jwt(a, token)
    if !d.valid { ret (false, d.message) }
    let alg = ir.value_of(d.header, "alg")
    if !ir.truthy(alg) { ret (false, "unsigned token rejected (alg=none)") }
    let alg_text = js_string(a, alg)
    if lowered_is_none(alg_text) { ret (false, "unsigned token rejected (alg=none)") }
    var is_text = false
    switch alg {
    case .String as s:
        is_text = str.eq(s, "RS256")
    default:
        is_text = false
    }
    if !is_text { ret (false, f.join(a, "unsupported-algorithm: ", alg_text)) }
    if !has_jwk || !ir.truthy(jwk) { ret (false, "no key") }
    let kty = ir.value_of(jwk, "kty")
    var rsa = false
    switch kty {
    case .String as s:
        rsa = str.eq(s, "RSA")
    default:
        rsa = false
    }
    if !rsa {
        var shown = "undefined"
        let (found_kty, has_kty) = ir.get(jwk, "kty")
        if has_kty { shown = js_string(a, found_kty) }
        ret (false, f.join(a, "unsupported key type: ", shown))
    }
    let (n, has_n) = text_of(jwk, "n")
    let (e, has_e) = text_of(jwk, "e")
    if !has_n || !has_e { ret (false, "signature does not verify") }
    let sig = base64url_decode(a, d.signature)
    if verify_rs256(a, d.signing_input, sig, n, e) { ret (true, "") }
    ret (false, "signature does not verify")
}

// The key for a token from a JWKS: the `kid` match, else the only RSA key; false when there is none.
fn select_jwk(jwks: json.Value, header: json.Value) -> (json.Value, bool) {
    let (keys, is_array) = ir.items_of(ir.value_of(jwks, "keys"))
    let kid = ir.value_of(header, "kid")
    if ir.truthy(kid) {
        var i = 0usize
        while i < keys.len {
            let (k, has) = ir.get(keys[i], "kid")
            if has {
                var same = false
                switch k {
                case .String as ks:
                    switch kid {
                    case .String as hs:
                        same = str.eq(ks, hs)
                    default:
                        same = false
                    }
                default:
                    same = false
                }
                if same { ret (keys[i], true) }
            }
            i += 1usize
        }
        ret (.Null, false)
    }
    var found = false
    var at = 0usize
    var count = 0usize
    var i = 0usize
    while i < keys.len {
        let (kty, has) = text_of(keys[i], "kty")
        if has && str.eq(kty, "RSA") {
            count += 1usize
            at = i
        }
        i += 1usize
    }
    if count == 1usize { ret (keys[at], true) }
    ret (.Null, false)
}
