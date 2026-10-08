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
