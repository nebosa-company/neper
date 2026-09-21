// Check-digit validators over identifiers as written: `luhn` (cards, IMEI)
// with `luhn_check_digit`, `isbn13` and `isbn10`, `ean13`, `ean8` and
// `upc_a`, and `iban` by mod-97 done a character at a time with a
// country-length table for the common countries. Spaces and hyphens between
// digits are ignored (IBAN: spaces only); any other stray character fails.

error Invalid

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }
fn is_separator(c: u8) -> bool { ret c == 32u8 || c == 45u8 }

// The digits of `s` without separators into `out`; answers the count, or
// `out.len + 1` on a non-digit or when `out` is full.
fn digits(s: str, out: []u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if is_digit(c) {
            if n >= out.len { ret out.len + 1usize }
            out[n] = c - 48u8
            n += 1usize
        } else if !is_separator(c) {
            ret out.len + 1usize
        }
        i += 1usize
    }
    ret n
}

// Luhn mod-10 over the digits of `s` (two or more).
fn luhn(s: str) -> bool {
    var d: [64]u8 = zero
    let n = digits(s, d[..])
    if n < 2usize || n > 64usize { ret false }
    ret luhn_sum(d[..n], false) % 10u32 == 0u32
}

// The Luhn sum of `d`; `shifted` doubles the last digit instead of the second-last.
fn luhn_sum(d: []const u8, shifted: bool) -> u32 {
    var total = 0u32
    var double = shifted
    var i = d.len
    while i > 0usize {
        i -= 1usize
        var v = u32(d[i])
        if double {
            v *= 2u32
            if v > 9u32 { v -= 9u32 }
        }
        total += v
        double = !double
    }
    ret total
}

// The digit that appended to `s` makes it pass `luhn`; `Invalid` on a stray character.
fn luhn_check_digit(s: str) -> (u8, err) {
    var d: [64]u8 = zero
    let n = digits(s, d[..])
    if n > 64usize { ret (0u8, Invalid) }
    ret (u8((10u32 - luhn_sum(d[..n], true) % 10u32) % 10u32), ok)
}

// Weighted mod-10 over exactly `count` digits, weights alternating from `first` (1 or 3).
fn weighted_mod10(s: str, count: usize, first: u32) -> bool {
    var d: [16]u8 = zero
    if digits(s, d[..]) != count { ret false }
    var total = 0u32
    var w = first
    var i = 0usize
    while i < count {
        total += u32(d[i]) * w
        w = 4u32 - w
        i += 1usize
    }
    ret total % 10u32 == 0u32
}

fn ean13(s: str) -> bool { ret weighted_mod10(s, 13usize, 1u32) }
fn ean8(s: str) -> bool { ret weighted_mod10(s, 8usize, 3u32) }
fn upc_a(s: str) -> bool { ret weighted_mod10(s, 12usize, 3u32) }
fn isbn13(s: str) -> bool { ret weighted_mod10(s, 13usize, 1u32) }

// ISBN-10: weights 10 down to 1, mod 11; the last character may be `X` (ten).
fn isbn10(s: str) -> bool {
    var total = 0u32
    var seen = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        i += 1usize
        if is_separator(c) { continue }
        if seen >= 10usize { ret false }
        var v = 0u32
        if is_digit(c) {
            v = u32(c - 48u8)
        } else if c == 88u8 && seen == 9usize {
            v = 10u32
        } else {
            ret false
        }
        total += u32(10usize - seen) * v
        seen += 1usize
    }
    ret seen == 10usize && total % 11u32 == 0u32
}

// The fixed IBAN length of a country, or 0 when the country is not in the table.
fn iban_length(a: u8, b: u8) -> usize {
    let codes = "DEGBFRESITNLBECHATPL"
    let lengths: [10]u8 = [10]u8{ 22u8, 22u8, 27u8, 24u8, 27u8, 18u8, 16u8, 21u8, 20u8, 28u8 }
    var i = 0usize
    while i < 10usize {
        if codes[2usize * i] == a && codes[2usize * i + 1usize] == b { ret usize(lengths[i]) }
        i += 1usize
    }
    ret 0usize
}

// Fold the characters of `s` (spaces skipped) into `r` mod 97; a letter is two digits.
fn mod97(r: u32, s: str) -> (u32, bool) {
    var v = r
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if is_digit(c) {
            v = (v * 10u32 + u32(c - 48u8)) % 97u32
        } else if c >= 65u8 && c <= 90u8 {
            v = (v * 100u32 + u32(c) - 55u32) % 97u32
        } else if c != 32u8 {
            ret (v, false)
        }
        i += 1usize
    }
    ret (v, true)
}

// IBAN: two upper-case letters, two check digits, 15..34 characters (the
// country's fixed length when known), and the rearranged string is 1 mod 97.
fn iban(s: str) -> bool {
    var d: [34]u8 = zero
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] != 32u8 {
            if n >= 34usize { ret false }
            d[n] = s[i]
            n += 1usize
        }
        i += 1usize
    }
    if n < 15usize { ret false }
    if d[0usize] < 65u8 || d[0usize] > 90u8 || d[1usize] < 65u8 || d[1usize] > 90u8 { ret false }
    if !is_digit(d[2usize]) || !is_digit(d[3usize]) { ret false }
    let expected = iban_length(d[0usize], d[1usize])
    if expected != 0usize && expected != n { ret false }
    let (body, body_ok) = mod97(0u32, d[4usize..n])
    if !body_ok { ret false }
    let (tail, tail_ok) = mod97(body, d[..4usize])
    ret tail_ok && tail == 1u32
}
