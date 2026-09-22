// Internationalized domain names over caller storage: RFC 3492 Punycode with the exact
// parameters (base 36, tmin 1, tmax 26, skew 38, damp 700, initial bias 72, initial
// n 128) and the RFC 5891 A-label / U-label conversions on top.
//
// `to_ascii` splits a domain on `.` and the ideographic full stops (U+3002, U+FF0E,
// U+FF61), NFC-normalizes each label through `e.text.normalize`, lowercases it with the
// simple case mapping of `e.text.unicode`, passes an all-ASCII label through and encodes
// anything else as `xn--` + Punycode. It enforces the hyphen rules (none leading or
// trailing, none in positions 3-4 unless the label is already an `xn--` A-label), the
// LDH alphabet for ASCII labels, 1..63 bytes a label and 253 bytes a domain.
// `to_unicode` decodes `xn--` labels back to UTF-8.
//
// The mapping is the simple lowercase mapping, not the UTS #46 table: ß stays ß, which
// is what non-transitional processing (and the Python `idna` package) answers
// (`straße.de` -> `xn--strae-oqa.de`); ẞ, ﬁ-style ligatures, Ⅷ and other compatibility
// characters are neither folded nor rejected.
// ponytail: no IDNA 2008 PVALID / CONTEXTJ / CONTEXTO tables and no Bidi rule (RFC 5893):
// a U-label is accepted if it is NFC, lowercased and passes the hyphen rules. Add the
// derived-property table beside `e.text.unicode` when a resolver needs the full check.

use e.text.normalize
use e.text.unicode
use e.text.utf8

error Invalid
error TooLong
error TooSmall

fn base() -> u64 { ret 36u64 }
fn tmin() -> u64 { ret 1u64 }
fn tmax() -> u64 { ret 26u64 }
fn skew() -> u64 { ret 38u64 }
fn damp() -> u64 { ret 700u64 }
fn initial_bias() -> u64 { ret 72u64 }
fn initial_n() -> u64 { ret 128u64 }
fn max_label() -> usize { ret 63usize }
fn max_domain() -> usize { ret 253usize }

// RFC 3492 6.1: the bias for the next delta.
fn adapt(delta_in: u64, num_points: u64, first: bool) -> u64 {
    var delta = delta_in
    if first { delta = delta / damp() } else { delta = delta / 2u64 }
    delta += delta / num_points
    var k = 0u64
    while delta > ((base() - tmin()) * tmax()) / 2u64 {
        delta = delta / (base() - tmin())
        k += base()
    }
    ret k + ((base() - tmin() + 1u64) * delta) / (delta + skew())
}

// The threshold t(k) for the digit position `k` under `bias`.
fn threshold(k: u64, bias: u64) -> u64 {
    if k <= bias { ret tmin() }
    if k >= bias + tmax() { ret tmax() }
    ret k - bias
}

// 0..25 -> a..z, 26..35 -> 0..9; the encoder always answers lowercase.
fn digit_char(d: u64) -> u8 {
    if d < 26u64 { ret u8(97u64 + d) }
    ret u8(22u64 + d)
}

// A-Z and a-z are 0..25, 0-9 are 26..35; anything else is not a digit.
fn digit_value(c: u8) -> (u64, bool) {
    if c >= 48u8 && c <= 57u8 { ret (u64(c - 48u8) + 26u64, true) }
    if c >= 65u8 && c <= 90u8 { ret (u64(c - 65u8), true) }
    if c >= 97u8 && c <= 122u8 { ret (u64(c - 97u8), true) }
    ret (0u64, false)
}

fn is_scalar(n: u64) -> bool {
    if n > 1114111u64 { ret false }
    ret n < 55296u64 || n > 57343u64
}

// RFC 3492 6.3: the Punycode of `points` written to `out`; answers how many bytes.
// `TooSmall` when `out` cannot hold it, `Invalid` for a value that is not a scalar.
fn punycode_encode(points: []const u32, out: []u8) -> (usize, err) {
    var used = 0usize
    var j = 0usize
    while j < points.len {
        if !is_scalar(u64(points[j])) { ret (0usize, Invalid) }
        if points[j] < 128u32 {
            if used >= out.len { ret (0usize, TooSmall) }
            out[used] = u8(points[j])
            used += 1usize
        }
        j += 1usize
    }
    let basic = used
    var h = basic
    if basic > 0usize {
        if used >= out.len { ret (0usize, TooSmall) }
        out[used] = 45u8
        used += 1usize
    }
    var n = initial_n()
    var delta = 0u64
    var bias = initial_bias()
    while h < points.len {
        // The smallest code point not yet handled.
        var m = 1114112u64
        j = 0usize
        while j < points.len {
            let c = u64(points[j])
            if c >= n && c < m { m = c }
            j += 1usize
        }
        delta += (m - n) * u64(h + 1usize)
        n = m
        j = 0usize
        while j < points.len {
            let c = u64(points[j])
            if c < n { delta += 1u64 }
            if c == n {
                var q = delta
                var k = base()
                var more = true
                while more {
                    let t = threshold(k, bias)
                    if q < t {
                        more = false
                    } else {
                        if used >= out.len { ret (0usize, TooSmall) }
                        out[used] = digit_char(t + (q - t) % (base() - t))
                        used += 1usize
                        q = (q - t) / (base() - t)
                        k += base()
                    }
                }
                if used >= out.len { ret (0usize, TooSmall) }
                out[used] = digit_char(q)
                used += 1usize
                bias = adapt(delta, u64(h + 1usize), h == basic)
                delta = 0u64
                h += 1usize
            }
            j += 1usize
        }
        delta += 1u64
        n += 1u64
    }
    ret (used, ok)
}

// RFC 3492 6.2: the code points of Punycode `text` written to `out`; answers how many.
// `Invalid` for a non-ASCII basic part, a bad digit, a truncated digit run, a value
// that overflows 32 bits or lands outside the scalar range; `TooSmall` when `out`
// cannot hold the result.
fn punycode_decode(text: []const u8, out: []u32) -> (usize, err) {
    var basic = 0usize
    var j = 0usize
    while j < text.len {
        if text[j] == 45u8 { basic = j }
        j += 1usize
    }
    if basic > out.len { ret (0usize, TooSmall) }
    j = 0usize
    while j < basic {
        if text[j] >= 128u8 { ret (0usize, Invalid) }
        out[j] = u32(text[j])
        j += 1usize
    }
    var used = basic
    var pos = 0usize
    if basic > 0usize { pos = basic + 1usize }
    var n = initial_n()
    var i = 0u64
    var bias = initial_bias()
    let limit = 4294967295u64
    while pos < text.len {
        let old_i = i
        var w = 1u64
        var k = base()
        var more = true
        while more {
            if pos >= text.len { ret (0usize, Invalid) }
            let (digit, is_digit) = digit_value(text[pos])
            if !is_digit { ret (0usize, Invalid) }
            pos += 1usize
            if digit > (limit - i) / w { ret (0usize, Invalid) }
            i += digit * w
            let t = threshold(k, bias)
            if digit < t {
                more = false
            } else {
                if w > limit / (base() - t) { ret (0usize, Invalid) }
                w = w * (base() - t)
                k += base()
            }
        }
        let count = u64(used + 1usize)
        bias = adapt(i - old_i, count, old_i == 0u64)
        if i / count > limit - n { ret (0usize, Invalid) }
        n += i / count
        i = i % count
        if n < initial_n() || !is_scalar(n) { ret (0usize, Invalid) }
        if used >= out.len { ret (0usize, TooSmall) }
        var p = used
        while p > usize(i) {
            out[p] = out[p - 1usize]
            p -= 1usize
        }
        out[usize(i)] = u32(n)
        used += 1usize
        i += 1u64
    }
    ret (used, ok)
}

fn is_ascii_label(label: str) -> bool {
    var j = 0usize
    while j < label.len {
        if label[j] >= 128u8 { ret false }
        j += 1usize
    }
    ret true
}

fn is_ldh(c: u8) -> bool {
    if c >= 48u8 && c <= 57u8 { ret true }
    if c >= 65u8 && c <= 90u8 { ret true }
    if c >= 97u8 && c <= 122u8 { ret true }
    ret c == 45u8
}

fn has_xn_prefix(label: str) -> bool {
    if label.len < 4usize { ret false }
    let x = label[0usize] == 120u8 || label[0usize] == 88u8
    let n = label[1usize] == 110u8 || label[1usize] == 78u8
    ret x && n && label[2usize] == 45u8 && label[3usize] == 45u8
}

// An ASCII label a DNS resolver accepts: 1..63 letters, digits and hyphens, no hyphen
// first or last, and `--` in positions 3-4 only as the `xn--` prefix.
fn label_valid(label: str) -> bool {
    if label.len == 0usize || label.len > max_label() { ret false }
    var j = 0usize
    while j < label.len {
        if !is_ldh(label[j]) { ret false }
        j += 1usize
    }
    if label[0usize] == 45u8 || label[label.len - 1usize] == 45u8 { ret false }
    if label.len >= 4usize && label[2usize] == 45u8 && label[3usize] == 45u8 {
        ret has_xn_prefix(label)
    }
    ret true
}

// The hyphen rules of RFC 5891 4.2.3.1 over a U-label's code points.
fn hyphens_ok(points: []const u32) -> bool {
    if points[0usize] == 45u32 || points[points.len - 1usize] == 45u32 { ret false }
    if points.len >= 4usize && points[2usize] == 45u32 && points[3usize] == 45u32 { ret false }
    ret true
}

fn is_label_separator(scalar: u32) -> bool {
    ret scalar == 46u32 || scalar == 12290u32 || scalar == 65294u32 || scalar == 65377u32
}

// One label of `to_ascii`, written at the start of `out`; answers how many bytes.
fn label_to_ascii(label: str, out: []u8, scratch: []u32) -> (usize, err) {
    if label.len == 0usize { ret (0usize, Invalid) }
    // NFD grows a scalar to at most four; `normalize_into` folds a short buffer into
    // Invalid, so the room is checked here to answer TooSmall.
    if scratch.len < 4usize * label.len { ret (0usize, TooSmall) }
    let (count, norm_error) = normalize.normalize_into(label, scratch, .Nfc)
    if norm_error != ok { ret (0usize, Invalid) }
    if count == 0usize { ret (0usize, Invalid) }
    var ascii = true
    var j = 0usize
    while j < count {
        scratch[j] = unicode.to_lower_simple(scratch[j])
        if scratch[j] >= 128u32 { ascii = false }
        j += 1usize
    }
    let points = scratch[..count]
    if ascii {
        if count > max_label() { ret (0usize, TooLong) }
        if count > out.len { ret (0usize, TooSmall) }
        j = 0usize
        while j < count {
            out[j] = u8(points[j])
            j += 1usize
        }
        if !label_valid(out[..count]) { ret (0usize, Invalid) }
        ret (count, ok)
    }
    if !hyphens_ok(points) { ret (0usize, Invalid) }
    if out.len < 4usize { ret (0usize, TooSmall) }
    out[0usize] = 120u8
    out[1usize] = 110u8
    out[2usize] = 45u8
    out[3usize] = 45u8
    // Cap the room at the label limit so an oversize label answers TooLong, not TooSmall.
    var room = out.len
    if room > max_label() + 1usize { room = max_label() + 1usize }
    let (encoded, encode_error) = punycode_encode(points, out[4usize..room])
    if encode_error == TooSmall && out.len > max_label() { ret (0usize, TooLong) }
    if encode_error != ok { ret (0usize, encode_error) }
    if 4usize + encoded > max_label() { ret (0usize, TooLong) }
    ret (4usize + encoded, ok)
}

// The A-label form of `domain` written to `out`; answers how many bytes. `scratch`
// holds one label's code points and needs four slots a byte of the longest label.
// `Invalid` for malformed UTF-8, an empty label, a bad hyphen or a non-LDH ASCII
// character; `TooLong` past 63 bytes a label or 253 a domain; `TooSmall` for `out`
// or `scratch`.
fn to_ascii(domain: str, out: []u8, scratch: []u32) -> (usize, err) {
    var used = 0usize
    var start = 0usize
    var off = 0usize
    var labels = 0usize
    var more = true
    while more {
        var separator = 0usize
        var width = 0usize
        if off < domain.len {
            let (d, decode_error) = utf8.decode(domain, off)
            if decode_error != ok { ret (0usize, Invalid) }
            width = usize(d.width)
            if is_label_separator(d.scalar) { separator = width }
        }
        if off >= domain.len || separator > 0usize {
            if labels > 0usize {
                if used >= out.len { ret (0usize, TooSmall) }
                out[used] = 46u8
                used += 1usize
            }
            let (n, label_error) = label_to_ascii(domain[start..off], out[used..], scratch)
            if label_error != ok { ret (0usize, label_error) }
            used += n
            labels += 1usize
            if used > max_domain() { ret (0usize, TooLong) }
            if off >= domain.len { more = false }
            start = off + separator
            off = start
        } else {
            off += width
        }
    }
    ret (used, ok)
}

// The U-label form of an A-label domain as UTF-8 written to `out`; answers how many
// bytes. Labels split on `.`; an `xn--` label is Punycode-decoded, any other label is
// copied with ASCII letters lowercased. `Invalid` for a bad label or Punycode.
fn to_unicode(domain: str, out: []u8) -> (usize, err) {
    var points: [64]u32 = zero
    var used = 0usize
    var j = 0usize
    var start = 0usize
    var off = 0usize
    var more = true
    while more {
        if off >= domain.len || domain[off] == 46u8 {
            let label = domain[start..off]
            if !label_valid(label) { ret (0usize, Invalid) }
            if start > 0usize {
                if used >= out.len { ret (0usize, TooSmall) }
                out[used] = 46u8
                used += 1usize
            }
            if has_xn_prefix(label) {
                let (count, decode_error) = punycode_decode(label[4usize..], points[..])
                if decode_error != ok { ret (0usize, Invalid) }
                j = 0usize
                while j < count {
                    let (w, encode_error) = utf8.encode(points[j], out[used..])
                    if encode_error != ok { ret (0usize, encode_error) }
                    used += usize(w)
                    j += 1usize
                }
            } else {
                if used + label.len > out.len { ret (0usize, TooSmall) }
                j = 0usize
                while j < label.len {
                    var c = label[j]
                    if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
                    out[used] = c
                    used += 1usize
                    j += 1usize
                }
            }
            if off >= domain.len { more = false }
            start = off + 1usize
        }
        off += 1usize
    }
    ret (used, ok)
}
