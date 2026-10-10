// Webhook signatures (L049), after Appdor's `src/webhooks/sign.js`: HMAC-SHA-256 over the body (`sha256=<hex>`), the
// timestamped v1 envelope `t=<unix>,v1=<hex>` over `"{t}.{body}"`, the two-header form (`X-Neposer-Signature: v1=<hex>`
// and `X-Neposer-Timestamp`), verification with a replay window (300 seconds either side by default) and a constant-time
// comparison, and the current-and-previous secret overlap used while a secret rotates. The clock is a parameter in
// milliseconds since the epoch.
//
// ponytail: `Number(timestamp)` is read for decimal, signed, `0x` and `0b`/`0o` text; exotic JavaScript numeric
// literals (`1e3`) are read as decimal exponents only.
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.crypto.mac as mac
use e.mem
use e.str

type Check = struct { valid: bool, reason: str, secret_index: i64 }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn hex_of(a: *mem.Arena, digest: []const u8) -> str {
    let digits = "0123456789abcdef"
    let (out, e) = mem.alloc[u8](a, digest.len * 2usize + 1usize)
    var i = 0usize
    while i < digest.len {
        out[i * 2usize] = digits[usize(digest[i] >> 4u8)]
        out[i * 2usize + 1usize] = digits[usize(digest[i] & 15u8)]
        i += 1usize
    }
    ret out[0usize..digest.len * 2usize]
}

// HMAC-SHA-256(key, message) as lower-case hex.
fn hmac_sha256(a: *mem.Arena, key: str, message: str) -> str {
    let d = mac.hmac_sha256(key, message)
    ret hex_of(a, d[0usize..32usize])
}

fn sign_body(a: *mem.Arena, body: str, secret: str) -> str { ret join(a, "sha256=", hmac_sha256(a, secret, body)) }

fn floor_text(a: *mem.Arena, x: f64) -> str {
    var t = f64(i64(x))
    if t > x { t -= 1.0f64 }
    ret f.number_text(a, t)
}

// `t=<unix>,v1=<hex>` for a body at `ts` seconds (fractions floored).
fn sign_body_v1(a: *mem.Arena, body: str, secret: str, ts: f64) -> str {
    let t = floor_text(a, ts)
    let sig = hmac_sha256(a, secret, join(a, join(a, t, "."), body))
    ret join(a, join(a, "t=", t), join(a, ",v1=", sig))
}

fn signature_header_name() -> str { ret "X-Neposer-Signature" }
fn timestamp_header_name() -> str { ret "X-Neposer-Timestamp" }
fn legacy_signature_header_name() -> str { ret "X-Webhook-Signature" }

type Headers = struct { signature: str, timestamp: str }

// The two-header form: `v1=<hex>` over `"{t}.{body}"`, and `t` as text.
fn signature_headers(a: *mem.Arena, body: str, secret: str, ts: f64) -> Headers {
    let t = floor_text(a, ts)
    let sig = hmac_sha256(a, secret, join(a, join(a, t, "."), body))
    ret Headers { signature: join(a, "v1=", sig), timestamp: t }
}

// Constant-time equality of two texts (by their bytes): unequal lengths answer false at once.
fn timing_safe_equal(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var r = 0u8
    var i = 0usize
    while i < x.len {
        r = r | (x[i] ^ y[i])
        i += 1usize
    }
    ret r == 0u8
}

fn is_ws(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 11u8 || c == 12u8 || c == 13u8 }

fn trim(s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && is_ws(s[from]) { from += 1usize }
    while to > from && is_ws(s[to - 1usize]) { to -= 1usize }
    ret s[from..to]
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

// JavaScript's `Number(text)`: blank is 0, decimal with sign and fraction, `0x`/`0b`/`0o`; false when NaN or infinite.
fn js_number(text: str) -> (f64, bool) {
    let s = trim(text)
    if s.len == 0usize { ret (0.0f64, true) }
    if s.len > 2usize && s[0] == 48u8 && (s[1] == 120u8 || s[1] == 88u8 || s[1] == 98u8 || s[1] == 66u8 || s[1] == 111u8 || s[1] == 79u8) {
        var radix = 16.0f64
        if s[1] == 98u8 || s[1] == 66u8 { radix = 2.0f64 }
        if s[1] == 111u8 || s[1] == 79u8 { radix = 8.0f64 }
        var value = 0.0f64
        var i = 2usize
        while i < s.len {
            let c = s[i]
            var d = -1i32
            if c >= 48u8 && c <= 57u8 { d = i32(c) - 48i32 }
            if c >= 97u8 && c <= 102u8 { d = i32(c) - 87i32 }
            if c >= 65u8 && c <= 70u8 { d = i32(c) - 55i32 }
            if d < 0i32 || f64(d) >= radix { ret (0.0f64, false) }
            value = value * radix + f64(d)
            i += 1usize
        }
        ret (value, true)
    }
    // the decimal grammar: sign? digits [. digits] [e sign? digits]
    var i = 0usize
    if s[0] == 43u8 || s[0] == 45u8 { i = 1usize }
    var digits = 0usize
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        i += 1usize
        digits += 1usize
    }
    if i < s.len && s[i] == 46u8 {
        i += 1usize
        while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
            i += 1usize
            digits += 1usize
        }
    }
    if digits == 0usize { ret (0.0f64, false) }
    if i < s.len && (s[i] == 101u8 || s[i] == 69u8) {
        i += 1usize
        if i < s.len && (s[i] == 43u8 || s[i] == 45u8) { i += 1usize }
        var exp_digits = 0usize
        while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
            i += 1usize
            exp_digits += 1usize
        }
        if exp_digits == 0usize { ret (0.0f64, false) }
    }
    if i != s.len { ret (0.0f64, false) }
    let (x, e) = str.parse_f64(s)
    if e != ok { ret (0.0f64, false) }
    if x - x != 0.0f64 { ret (0.0f64, false) }
    ret (x, true)
}

fn abs_f64(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn refused(reason: str) -> Check { ret Check { valid: false, reason: reason, secret_index: -1i64 } }

fn tolerance_text(a: *mem.Arena, tolerance: f64) -> str {
    ret join(a, join(a, "timestamp outside tolerance (±", f.number_text(a, tolerance)), "s)")
}

// The two-header form, checked at `now_ms`. `signature` may be `v1=<hex>` or bare hex.
fn verify_signature_headers(a: *mem.Arena, body: str, secret: str, signature: str, timestamp: str, tolerance: f64, now_ms: f64) -> Check {
    if signature.len == 0usize || secret.len == 0usize { ret refused("missing header or secret") }
    let (t, good) = js_number(timestamp)
    if !good { ret refused("missing or malformed timestamp") }
    var now = f64(i64(now_ms / 1000.0f64))
    if now > now_ms / 1000.0f64 { now -= 1.0f64 }
    if abs_f64(now - t) > tolerance { ret refused(tolerance_text(a, tolerance)) }
    var provided = lower(a, trim(signature))
    if str.starts_with(provided, "v1=") { provided = provided[3usize..] }
    let expected = lower(a, hmac_sha256(a, secret, join(a, join(a, f.number_text(a, t), "."), body)))
    if !timing_safe_equal(expected, provided) { ret refused("signature mismatch") }
    ret Check { valid: true, reason: "", secret_index: -1i64 }
}

fn is_hex_digit(c: u8) -> bool { ret (c >= 48u8 && c <= 57u8) || (c >= 97u8 && c <= 102u8) || (c >= 65u8 && c <= 70u8) }

// A `t=<digits>,v1=<hex>` header at `now_ms`.
fn verify_v1(a: *mem.Arena, body: str, secret: str, header: str, tolerance: f64, now_ms: f64) -> Check {
    if header.len == 0usize || secret.len == 0usize { ret refused("missing header or secret") }
    let h = trim(header)
    // ^t=(\d+),v1=([a-f0-9]+)$ with the i flag
    var ok_shape = h.len > 5usize && (h[0] == 116u8 || h[0] == 84u8) && h[1] == 61u8
    var i = 2usize
    var digits = 0usize
    while ok_shape && i < h.len && h[i] >= 48u8 && h[i] <= 57u8 {
        i += 1usize
        digits += 1usize
    }
    if digits == 0usize { ok_shape = false }
    var t_text = ""
    if ok_shape { t_text = h[2usize..i] }
    if ok_shape && !(i + 4usize <= h.len && h[i] == 44u8 && (h[i + 1usize] == 118u8 || h[i + 1usize] == 86u8) && h[i + 2usize] == 49u8 && h[i + 3usize] == 61u8) { ok_shape = false }
    var sig = ""
    if ok_shape {
        let start = i + 4usize
        var k = start
        while k < h.len && is_hex_digit(h[k]) { k += 1usize }
        if k == start || k != h.len { ok_shape = false }
        if ok_shape { sig = lower(a, h[start..k]) }
    }
    if !ok_shape { ret refused("malformed v1 signature") }
    let (t, good) = js_number(t_text)
    var now = f64(i64(now_ms / 1000.0f64))
    if now > now_ms / 1000.0f64 { now -= 1.0f64 }
    if abs_f64(now - t) > tolerance { ret refused(tolerance_text(a, tolerance)) }
    let expected = hmac_sha256(a, secret, join(a, join(a, f.number_text(a, t), "."), body))
    if !timing_safe_equal(lower(a, expected), sig) { ret refused("signature mismatch") }
    ret Check { valid: true, reason: "", secret_index: -1i64 }
}

// The first of `secrets` (current, then previous) that verifies.
fn verify_v1_rotated(a: *mem.Arena, body: str, secrets: []const str, header: str, tolerance: f64, now_ms: f64) -> Check {
    if secrets.len == 0usize { ret refused("no secrets") }
    var i = 0usize
    while i < secrets.len {
        let r = verify_v1(a, body, secrets[i], header, tolerance, now_ms)
        if r.valid { ret Check { valid: true, reason: "", secret_index: i64(i) } }
        i += 1usize
    }
    ret refused("no secret matches")
}
