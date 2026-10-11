// HOTP (RFC 4226) and TOTP (RFC 6238) one-time codes over HMAC-SHA1, HMAC-SHA256 and
// HMAC-SHA512, with look-ahead and clock-skew verification. A code is the 31-bit dynamic
// truncation of HMAC(key, counter as 8 big-endian bytes) modulo 10^digits, 6 to 9 digits.
// The key is the raw secret bytes (a Base32 `secret=` from an otpauth URI is decoded by the
// caller); where a secret is stored is the host's decision, not this module's. Verification
// compares every candidate counter without stopping at the first match and reports the matching
// counter, so a caller can refuse a replay by remembering the last counter it accepted.
// SHA-1 is here because RFC 4226 and every deployed authenticator app use it for HOTP/TOTP.

use e.crypto.mac as mac

error Invalid

type Algorithm = enum u8 { Sha1, Sha256, Sha512 }

fn pow10(digits: u32) -> u32 {
    var value = 1u32
    var i = 0u32
    while i < digits {
        value *= 10u32
        i += 1u32
    }
    ret value
}

// The HMAC of the counter, left in `out`; answers its length.
fn digest(algorithm: Algorithm, key: []const u8, counter: u64, out: []u8) -> usize {
    var message: [8]u8 = zero
    var i = 0usize
    while i < 8usize {
        message[i] = u8((counter >> u64(8usize * (7usize - i))) & 255u64)
        i += 1usize
    }
    if algorithm == .Sha1 {
        let tag = mac.legacy_hmac_sha1(key, message[..])
        i = 0usize
        while i < 20usize {
            out[i] = tag[i]
            i += 1usize
        }
        ret 20usize
    }
    if algorithm == .Sha256 {
        let tag = mac.hmac_sha256(key, message[..])
        i = 0usize
        while i < 32usize {
            out[i] = tag[i]
            i += 1usize
        }
        ret 32usize
    }
    let tag = mac.hmac_sha512(key, message[..])
    i = 0usize
    while i < 64usize {
        out[i] = tag[i]
        i += 1usize
    }
    ret 64usize
}

// The code for `counter`. Refused: an empty key or a digit count outside 6..9.
fn hotp(algorithm: Algorithm, key: []const u8, counter: u64, digits: u32) -> (u32, err) {
    if key.len == 0usize || digits < 6u32 || digits > 9u32 { ret (0u32, Invalid) }
    var tag: [64]u8 = zero
    let length = digest(algorithm, key, counter, tag[..])
    let offset = usize(tag[length - 1usize] & 15u8)
    let truncated = (u32(tag[offset] & 127u8) << 24u32) | (u32(tag[offset + 1usize]) << 16u32) | (u32(tag[offset + 2usize]) << 8u32) | u32(tag[offset + 3usize])
    ret (truncated % pow10(digits), ok)
}

// The time step of `seconds` since the epoch: (seconds - start) / period. `period` is the step in
// seconds (30 for authenticator apps) and `start` is T0; a time before T0 or a zero period is refused.
fn time_step(seconds: u64, start: u64, period: u32) -> (u64, err) {
    if period == 0u32 || seconds < start { ret (0u64, Invalid) }
    ret ((seconds - start) / u64(period), ok)
}

fn totp(algorithm: Algorithm, key: []const u8, seconds: u64, start: u64, period: u32, digits: u32) -> (u32, err) {
    let (step, step_error) = time_step(seconds, start, period)
    if step_error != ok { ret (0u32, step_error) }
    let (code, code_error) = hotp(algorithm, key, step, digits)
    ret (code, code_error)
}

// Whether `candidate` is the code for any of the `window + 1` counters starting at `counter`
// (RFC 4226 look-ahead). Answers the counter that matched, or the first counter when none did.
fn verify_hotp(algorithm: Algorithm, key: []const u8, counter: u64, window: u32, digits: u32, candidate: u32) -> (u64, bool, err) {
    if key.len == 0usize || digits < 6u32 || digits > 9u32 { ret (0u64, false, Invalid) }
    var found = false
    var matched = counter
    var i = 0u32
    while i <= window {
        let (code, code_error) = hotp(algorithm, key, counter + u64(i), digits)
        if code_error != ok { ret (0u64, false, code_error) }
        if code == candidate && !found {
            found = true
            matched = counter + u64(i)
        }
        i += 1u32
    }
    ret (matched, found, ok)
}

// Whether `candidate` is the code for the step of `seconds` or any of `skew` steps either side of it
// (never below step 0). Answers the step that matched, or the current step when none did.
fn verify_totp(algorithm: Algorithm, key: []const u8, seconds: u64, start: u64, period: u32, digits: u32, skew: u32, candidate: u32) -> (u64, bool, err) {
    let (step, step_error) = time_step(seconds, start, period)
    if step_error != ok { ret (0u64, false, step_error) }
    var first = step
    if u64(skew) > step { first = 0u64 } else { first = step - u64(skew) }
    var found = false
    var matched = step
    var at = first
    while at <= step + u64(skew) {
        let (code, code_error) = hotp(algorithm, key, at, digits)
        if code_error != ok { ret (0u64, false, code_error) }
        if code == candidate && !found {
            found = true
            matched = at
        }
        at += 1u64
    }
    ret (matched, found, ok)
}

// The code as zero-padded decimal text in `out` (`out.len >= digits`); a code with more digits than
// `digits` is refused.
fn format(code: u32, digits: u32, out: []u8) -> (str, err) {
    if digits < 1u32 || digits > 9u32 || out.len < usize(digits) || code >= pow10(digits) { ret ("", Invalid) }
    var value = code
    var i = usize(digits)
    while i > 0usize {
        i -= 1usize
        out[i] = 48u8 + u8(value % 10u32)
        value /= 10u32
    }
    ret (out[..usize(digits)], ok)
}

// ---- otpauth:// URIs (C140) -----------------------------------------------------------------------------------

// What an otpauth URI carries. The strings are views into the URI as written (percent-escapes not yet decoded;
// `percent_decode` does that); `counter` is the HOTP counter, `period` and `digits` default to 30 and 6.
type Provisioning = struct { totp: bool, label: str, issuer: str, secret: str, algorithm: Algorithm, digits: u32, period: u32, counter: u64 }

fn starts_with(text: str, prefix: str) -> bool {
    if text.len < prefix.len { ret false }
    var i = 0usize
    while i < prefix.len {
        if text[i] != prefix[i] { ret false }
        i += 1usize
    }
    ret true
}

fn same_text(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        var x = a[i]
        var y = b[i]
        if x >= 65u8 && x <= 90u8 { x = x + 32u8 }
        if y >= 65u8 && y <= 90u8 { y = y + 32u8 }
        if x != y { ret false }
        i += 1usize
    }
    ret true
}

fn parse_number(text: str) -> (u64, bool) {
    if text.len == 0usize || text.len > 18usize { ret (0u64, false) }
    var v = 0u64
    var i = 0usize
    while i < text.len {
        if text[i] < 48u8 || text[i] > 57u8 { ret (0u64, false) }
        v = v * 10u64 + u64(text[i] - 48u8)
        i += 1usize
    }
    ret (v, true)
}

// `otpauth://totp/Label?secret=...&issuer=...&algorithm=SHA256&digits=8&period=60` (or hotp with counter).
fn parse_uri(uri: str) -> (Provisioning, err) {
    var p = Provisioning { totp: true, label: "", issuer: "", secret: "", algorithm: .Sha1, digits: 6u32, period: 30u32, counter: 0u64 }
    let head = "otpauth://"
    if !starts_with(uri, head) { ret (p, Invalid) }
    var at = head.len
    var kind_end = at
    while kind_end < uri.len && uri[kind_end] != 47u8 { kind_end += 1usize }
    let kind = uri[at..kind_end]
    if same_text(kind, "totp") {
        p.totp = true
    } else if same_text(kind, "hotp") {
        p.totp = false
    } else {
        ret (p, Invalid)
    }
    at = kind_end + 1usize
    var label_end = at
    while label_end < uri.len && uri[label_end] != 63u8 { label_end += 1usize }
    if at > uri.len { ret (p, Invalid) }
    p.label = uri[at..label_end]
    var pos = label_end + 1usize
    var have_secret = false
    var have_counter = false
    while pos < uri.len {
        var key_end = pos
        while key_end < uri.len && uri[key_end] != 61u8 && uri[key_end] != 38u8 { key_end += 1usize }
        let key = uri[pos..key_end]
        var value_end = key_end
        var value = ""
        if key_end < uri.len && uri[key_end] == 61u8 {
            value_end = key_end + 1usize
            while value_end < uri.len && uri[value_end] != 38u8 { value_end += 1usize }
            value = uri[key_end + 1usize..value_end]
        }
        if same_text(key, "secret") {
            p.secret = value
            have_secret = value.len > 0usize
        } else if same_text(key, "issuer") {
            p.issuer = value
        } else if same_text(key, "algorithm") {
            if same_text(value, "SHA1") {
                p.algorithm = .Sha1
            } else if same_text(value, "SHA256") {
                p.algorithm = .Sha256
            } else if same_text(value, "SHA512") {
                p.algorithm = .Sha512
            } else {
                ret (p, Invalid)
            }
        } else if same_text(key, "digits") {
            let (d, d_ok) = parse_number(value)
            if !d_ok || d < 6u64 || d > 9u64 { ret (p, Invalid) }
            p.digits = u32(d)
        } else if same_text(key, "period") {
            let (period, period_ok) = parse_number(value)
            if !period_ok || period == 0u64 || period > 86400u64 { ret (p, Invalid) }
            p.period = u32(period)
        } else if same_text(key, "counter") {
            let (c, c_ok) = parse_number(value)
            if !c_ok { ret (p, Invalid) }
            p.counter = c
            have_counter = true
        }
        pos = value_end + 1usize
    }
    if !have_secret { ret (p, Invalid) }
    if !p.totp && !have_counter { ret (p, Invalid) }
    ret (p, ok)
}

// A percent-encoded string decoded into `out` (+ as a space): the length, or Invalid on a bad escape or no room.
fn percent_decode(text: str, out: []u8) -> (usize, err) {
    var n = 0usize
    var i = 0usize
    while i < text.len {
        var c = text[i]
        if c == 37u8 {
            if i + 2usize >= text.len { ret (0usize, Invalid) }
            let hi = hex_nibble(text[i + 1usize])
            let lo = hex_nibble(text[i + 2usize])
            if hi > 15u8 || lo > 15u8 { ret (0usize, Invalid) }
            c = hi * 16u8 + lo
            i += 3usize
        } else {
            if c == 43u8 { c = 32u8 }
            i += 1usize
        }
        if n >= out.len { ret (0usize, Invalid) }
        out[n] = c
        n += 1usize
    }
    ret (n, ok)
}

fn hex_nibble(c: u8) -> u8 {
    if c >= 48u8 && c <= 57u8 { ret c - 48u8 }
    if c >= 97u8 && c <= 102u8 { ret c - 87u8 }
    if c >= 65u8 && c <= 70u8 { ret c - 55u8 }
    ret 255u8
}
