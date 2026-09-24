// JSON Web Tokens (RFC 7519) in JWS compact serialisation (RFC 7515): `split` cuts a
// token into its three base64url segments, `header` and `payload` decode them into caller
// storage, `algorithm` reads the header's `alg`, `verify` checks an HMAC (HS256/384/512)
// or Ed25519 signature against the algorithm the CALLER expects -- the header's `alg` is
// only ever compared with that expectation, never trusted, and `none` is always refused --
// and `claims_check` applies exp/nbf/iat/iss/aud with a leeway. `sign_hmac` and
// `sign_ed25519` build tokens from a header and payload text so the round trip is byte
// for byte what PyJWT produces. Header and payload are read by a flat scanner over the
// JSON text rather than a tree, so nothing here allocates.

use e.bytes
use e.crypto.hash as hash
use e.crypto.mac as mac
use e.crypto.sign as sign
use e.mem
use e.str

type Alg = enum u8 { None, HS256, HS384, HS512, EdDSA }
type Parts = struct { header: str, payload: str, signature: str }

error Malformed
error Unsupported
error TooSmall
error Expired
error NotYetValid
error WrongIssuer
error WrongAudience

// --- Segments.

// The three segments of `token`; the signature may be empty (an unsecured JWS).
fn split(token: str) -> (Parts, err) {
    var first = 0usize
    var second = 0usize
    var dots = 0usize
    var i = 0usize
    while i < token.len {
        if token[i] == 46u8 {
            if dots == 0usize { first = i } else if dots == 1usize { second = i }
            dots += 1usize
        }
        i += 1usize
    }
    if dots != 2usize || first == 0usize || second == first + 1usize { ret (zero, Malformed) }
    ret (Parts { header: token[..first], payload: token[first + 1usize..second], signature: token[second + 1usize..] }, ok)
}

// base64url without padding (RFC 7515 section 2) into `dst`.
fn decode_segment(segment: str, dst: []u8) -> ([]u8, err) {
    var i = 0usize
    while i < segment.len {
        if segment[i] == 61u8 { ret (zero, Malformed) }
        i += 1usize
    }
    let (out, e) = bytes.base64_decode(dst, segment, .Url)
    if e == bytes.TooLarge { ret (zero, TooSmall) }
    if e != ok { ret (zero, Malformed) }
    ret (out, ok)
}

fn header(token: str, dst: []u8) -> (str, err) {
    let (parts, split_error) = split(token)
    if split_error != ok { ret ("", split_error) }
    let (out, e) = decode_segment(parts.header, dst)
    ret (out, e)
}

fn payload(token: str, dst: []u8) -> (str, err) {
    let (parts, split_error) = split(token)
    if split_error != ok { ret ("", split_error) }
    let (out, e) = decode_segment(parts.payload, dst)
    ret (out, e)
}

// --- A flat JSON scanner: the raw text of one top-level member.

fn skip_space(s: str, from: usize) -> usize {
    var i = from
    while i < s.len && str.is_ascii_space(s[i]) { i += 1usize }
    ret i
}

// `from` is the opening quote; answers the index after the closing one.
fn skip_string(s: str, from: usize) -> (usize, err) {
    var i = from + 1usize
    while i < s.len {
        if s[i] == 34u8 { ret (i + 1usize, ok) }
        if s[i] == 92u8 { i += 1usize }
        i += 1usize
    }
    ret (0usize, Malformed)
}

fn skip_value(s: str, from: usize, depth: usize) -> (usize, err) {
    if from >= s.len || depth > 32usize { ret (0usize, Malformed) }
    let c = s[from]
    if c == 34u8 {
        let (end, e) = skip_string(s, from)
        ret (end, e)
    }
    if c == 123u8 || c == 91u8 {
        let closer = c + 2u8
        var i = skip_space(s, from + 1usize)
        if i < s.len && s[i] == closer { ret (i + 1usize, ok) }
        while true {
            if c == 123u8 {
                if i >= s.len || s[i] != 34u8 { ret (0usize, Malformed) }
                let (key_end, key_error) = skip_string(s, i)
                if key_error != ok { ret (0usize, key_error) }
                i = skip_space(s, key_end)
                if i >= s.len || s[i] != 58u8 { ret (0usize, Malformed) }
                i = skip_space(s, i + 1usize)
            }
            let (value_end, value_error) = skip_value(s, i, depth + 1usize)
            if value_error != ok { ret (0usize, value_error) }
            i = skip_space(s, value_end)
            if i >= s.len { ret (0usize, Malformed) }
            if s[i] == closer { ret (i + 1usize, ok) }
            if s[i] != 44u8 { ret (0usize, Malformed) }
            i = skip_space(s, i + 1usize)
        }
    }
    // A number or literal: everything up to a delimiter.
    var i = from
    while i < s.len && s[i] != 44u8 && s[i] != 125u8 && s[i] != 93u8 && !str.is_ascii_space(s[i]) { i += 1usize }
    if i == from { ret (0usize, Malformed) }
    ret (i, ok)
}

// The raw text of the top-level member `name` of the object `object` (a string
// keeps its quotes), and whether it was present. Escaped member names are refused
// rather than given a second spelling, and a requested member must occur once.
fn member(object: str, name: str) -> (str, bool, err) {
    var i = skip_space(object, 0usize)
    if i >= object.len || object[i] != 123u8 { ret ("", false, Malformed) }
    i = skip_space(object, i + 1usize)
    if i < object.len && object[i] == 125u8 { ret ("", false, ok) }
    var found = false
    var found_value: str = ""
    while true {
        if i >= object.len || object[i] != 34u8 { ret ("", false, Malformed) }
        let (key_end, key_error) = skip_string(object, i)
        if key_error != ok { ret ("", false, key_error) }
        let key = object[i + 1usize..key_end - 1usize]
        var key_at = 0usize
        while key_at < key.len {
            if key[key_at] == 92u8 { ret ("", false, Malformed) }
            key_at += 1usize
        }
        i = skip_space(object, key_end)
        if i >= object.len || object[i] != 58u8 { ret ("", false, Malformed) }
        i = skip_space(object, i + 1usize)
        let (value_end, value_error) = skip_value(object, i, 0usize)
        if value_error != ok { ret ("", false, value_error) }
        if str.eq(key, name) {
            if found { ret ("", false, Malformed) }
            found = true
            found_value = object[i..value_end]
        }
        i = skip_space(object, value_end)
        if i >= object.len { ret ("", false, Malformed) }
        if object[i] == 125u8 { ret (found_value, found, ok) }
        if object[i] != 44u8 { ret ("", false, Malformed) }
        i = skip_space(object, i + 1usize)
    }
    ret ("", false, Malformed)
}

// The content of a raw string value, or `false` when `raw` is not a string.
fn string_of(raw: str) -> (str, bool) {
    if raw.len < 2usize || raw[0usize] != 34u8 { ret ("", false) }
    ret (raw[1usize..raw.len - 1usize], true)
}

// ponytail: NumericDate as whole seconds; `1.7e9` and fractions are refused as Malformed.
fn time_of(raw: str) -> (i64, err) {
    let (value, e) = str.parse_i64(raw)
    if e != ok { ret (0i64, Malformed) }
    ret (value, ok)
}

// --- Algorithms.

fn algorithm(header_json: str) -> (Alg, err) {
    let (raw, present, e) = member(header_json, "alg")
    if e != ok { ret (.None, e) }
    if !present { ret (.None, Malformed) }
    let (name, is_string) = string_of(raw)
    if !is_string { ret (.None, Malformed) }
    if str.eq(name, "HS256") { ret (.HS256, ok) }
    if str.eq(name, "HS384") { ret (.HS384, ok) }
    if str.eq(name, "HS512") { ret (.HS512, ok) }
    if str.eq(name, "EdDSA") { ret (.EdDSA, ok) }
    if str.eq(name, "none") { ret (.None, ok) }
    ret (.None, Unsupported)
}

// SHA-384 is SHA-512 with its own initial state, cut to 48 bytes (FIPS 180-4 5.3.4).
fn sha384_init() -> hash.Sha512 {
    var s = hash.sha512_init()
    s.h[0] = 14680500436340154072u64
    s.h[1] = 7105036623409894663u64
    s.h[2] = 10473403895298186519u64
    s.h[3] = 1526699215303891257u64
    s.h[4] = 7436329637833083697u64
    s.h[5] = 10282925794625328401u64
    s.h[6] = 15784041429090275239u64
    s.h[7] = 5167115440072839076u64
    ret s
}

fn hmac_sha384(key: []const u8, message: []const u8) -> [48]u8 {
    var block: [128]u8 = zero
    if key.len > 128usize {
        var k = sha384_init()
        hash.sha512_update(&k, key)
        let digest = hash.sha512_done(&k)
        mem.copy[u8](block[..48usize], digest[..48usize])
    } else {
        mem.copy[u8](block[..key.len], key)
    }
    var inner = sha384_init()
    var outer = sha384_init()
    var pad: [128]u8 = zero
    var i = 0usize
    while i < 128usize {
        pad[i] = block[i] ^ 54u8
        i += 1usize
    }
    hash.sha512_update(&inner, pad[0..])
    i = 0usize
    while i < 128usize {
        pad[i] = block[i] ^ 92u8
        i += 1usize
    }
    hash.sha512_update(&outer, pad[0..])
    hash.sha512_update(&inner, message)
    let inner_digest = hash.sha512_done(&inner)
    hash.sha512_update(&outer, inner_digest[..48usize])
    let full = hash.sha512_done(&outer)
    var out: [48]u8 = zero
    mem.copy[u8](out[0..], full[..48usize])
    ret out
}

// The HMAC tag of `message` under `alg`, and its length (0 for a non-HMAC algorithm).
fn hmac_tag(alg: Alg, key: []const u8, message: []const u8) -> ([64]u8, usize) {
    var out: [64]u8 = zero
    if alg == .HS256 {
        let tag = mac.hmac_sha256(key, message)
        mem.copy[u8](out[..32usize], tag[0..])
        ret (out, 32usize)
    }
    if alg == .HS384 {
        let tag = hmac_sha384(key, message)
        mem.copy[u8](out[..48usize], tag[0..])
        ret (out, 48usize)
    }
    if alg == .HS512 {
        let tag = mac.hmac_sha512(key, message)
        mem.copy[u8](out[0..], tag[0..])
        ret (out, 64usize)
    }
    ret (out, 0usize)
}

// --- Verification.

// The header's `alg` must be `expected` and the signature must verify under `key`:
// an HMAC secret for HS256/HS384/HS512, the 32 raw public key bytes for EdDSA.
// `.None` is refused with Unsupported. A header the scanner cannot read, a bad
// base64url segment or a signature of the wrong length is Malformed; a header
// naming another algorithm, or a tag that differs, answers `false`.
fn verify(token: str, key: []const u8, expected: Alg) -> (bool, err) {
    if expected == .None { ret (false, Unsupported) }
    let (parts, split_error) = split(token)
    if split_error != ok { ret (false, split_error) }
    var header_buffer: [1024]u8 = zero
    let (header_json, header_error) = decode_segment(parts.header, header_buffer[0..])
    if header_error != ok { ret (false, header_error) }
    let (alg, alg_error) = algorithm(header_json)
    if alg_error == Malformed { ret (false, Malformed) }
    if alg_error != ok || alg != expected { ret (false, ok) }
    var signature: [64]u8 = zero
    let (tag, tag_error) = decode_segment(parts.signature, signature[0..])
    if tag_error != ok { ret (false, tag_error) }
    let signed = token[..parts.header.len + 1usize + parts.payload.len]
    if alg == .EdDSA {
        if key.len != 32usize || tag.len != 64usize { ret (false, Malformed) }
        var public: sign.Ed25519PublicKey = zero
        mem.copy[u8](public.bytes[0..], key)
        var sig: sign.Ed25519Signature = zero
        mem.copy[u8](sig.bytes[0..], tag)
        ret (sign.ed25519_verify(public, signed, sig), ok)
    }
    let (computed, length) = hmac_tag(alg, key, signed)
    if tag.len != length { ret (false, Malformed) }
    ret (hash.equal_constant_time(computed[..length], tag), ok)
}

fn verify_ed25519(token: str, public: sign.Ed25519PublicKey) -> (bool, err) {
    let (good, e) = verify(token, public.bytes[0..], .EdDSA)
    ret (good, e)
}

// --- Claims (RFC 7519 section 4.1).

// `now` is seconds since the epoch, `leeway` the clock skew tolerated. An empty
// `issuer` or `audience` skips that claim; `aud` may be a string or an array.
fn claims_check(payload_json: str, now: i64, issuer: str, audience: str, leeway: i64) -> err {
    let (exp_raw, has_exp, exp_error) = member(payload_json, "exp")
    if exp_error != ok { ret exp_error }
    if has_exp {
        let (exp, e) = time_of(exp_raw)
        if e != ok { ret e }
        if now - leeway >= exp { ret Expired }
    }
    let (nbf_raw, has_nbf, nbf_error) = member(payload_json, "nbf")
    if nbf_error != ok { ret nbf_error }
    if has_nbf {
        let (nbf, e) = time_of(nbf_raw)
        if e != ok { ret e }
        if nbf > now + leeway { ret NotYetValid }
    }
    let (iat_raw, has_iat, iat_error) = member(payload_json, "iat")
    if iat_error != ok { ret iat_error }
    if has_iat {
        let (iat, e) = time_of(iat_raw)
        if e != ok { ret e }
        if iat > now + leeway { ret NotYetValid }
    }
    if issuer.len > 0usize {
        let (iss_raw, has_iss, iss_error) = member(payload_json, "iss")
        if iss_error != ok { ret iss_error }
        if !has_iss { ret WrongIssuer }
        let (iss, is_string) = string_of(iss_raw)
        if !is_string || !str.eq(iss, issuer) { ret WrongIssuer }
    }
    if audience.len > 0usize {
        let (aud_raw, has_aud, aud_error) = member(payload_json, "aud")
        if aud_error != ok { ret aud_error }
        if !has_aud { ret WrongAudience }
        let (aud, is_string) = string_of(aud_raw)
        if is_string {
            if str.eq(aud, audience) { ret ok }
            ret WrongAudience
        }
        if aud_raw.len < 2usize || aud_raw[0usize] != 91u8 { ret Malformed }
        var i = skip_space(aud_raw, 1usize)
        while i < aud_raw.len && aud_raw[i] != 93u8 {
            let (item_end, item_error) = skip_value(aud_raw, i, 1usize)
            if item_error != ok { ret item_error }
            let (item, item_is_string) = string_of(aud_raw[i..item_end])
            if item_is_string && str.eq(item, audience) { ret ok }
            i = skip_space(aud_raw, item_end)
            if i < aud_raw.len && aud_raw[i] == 44u8 { i = skip_space(aud_raw, i + 1usize) }
        }
        ret WrongAudience
    }
    ret ok
}

// --- Signing.

fn put_segment(dst: []u8, from: usize, data: []const u8) -> (usize, err) {
    if from > dst.len { ret (from, TooSmall) }
    let (encoded, e) = bytes.base64_encode(dst[from..], data, .Url, false)
    if e != ok { ret (from, TooSmall) }
    ret (from + encoded.len, ok)
}

// `header_json "." payload_json` base64url-encoded into `dst`; answers the length so far.
fn compose(header_json: str, payload_json: str, dst: []u8) -> (usize, err) {
    let (after_header, header_error) = put_segment(dst, 0usize, header_json)
    if header_error != ok { ret (0usize, header_error) }
    if after_header + 1usize > dst.len { ret (0usize, TooSmall) }
    dst[after_header] = 46u8
    let (after_payload, payload_error) = put_segment(dst, after_header + 1usize, payload_json)
    ret (after_payload, payload_error)
}

fn finish(dst: []u8, signed_len: usize, tag: []const u8) -> (usize, err) {
    if signed_len + 1usize > dst.len { ret (0usize, TooSmall) }
    dst[signed_len] = 46u8
    let (total, e) = put_segment(dst, signed_len + 1usize, tag)
    ret (total, e)
}

// A compact token signed with HMAC under `alg` (HS256/HS384/HS512); answers its
// length in `dst`. The header text is taken as given and must name the same `alg`.
fn sign_hmac(header_json: str, payload_json: str, key: []const u8, alg: Alg, dst: []u8) -> (usize, err) {
    let (declared, declared_error) = algorithm(header_json)
    if declared_error != ok { ret (0usize, declared_error) }
    if declared != alg || alg == .None || alg == .EdDSA { ret (0usize, Unsupported) }
    let (signed_len, compose_error) = compose(header_json, payload_json, dst)
    if compose_error != ok { ret (0usize, compose_error) }
    let (tag, length) = hmac_tag(alg, key, dst[..signed_len])
    let (total, e) = finish(dst, signed_len, tag[..length])
    ret (total, e)
}

fn sign_hs256(header_json: str, payload_json: str, key: []const u8, dst: []u8) -> (usize, err) {
    let (total, e) = sign_hmac(header_json, payload_json, key, .HS256, dst)
    ret (total, e)
}

fn sign_ed25519(header_json: str, payload_json: str, secret: sign.Ed25519SecretKey, dst: []u8) -> (usize, err) {
    let (declared, declared_error) = algorithm(header_json)
    if declared_error != ok { ret (0usize, declared_error) }
    if declared != .EdDSA { ret (0usize, Unsupported) }
    let (signed_len, compose_error) = compose(header_json, payload_json, dst)
    if compose_error != ok { ret (0usize, compose_error) }
    let (sig, sign_error) = sign.ed25519_sign(secret, dst[..signed_len])
    if sign_error != ok { ret (0usize, sign_error) }
    let (total, e) = finish(dst, signed_len, sig.bytes[0..])
    ret (total, e)
}
