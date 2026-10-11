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

// Card networks by the number's prefix and length (the check digit is `luhn`'s business): the answer
// is one of the BRAND_ constants. Separators between digits are ignored.
const BRAND_UNKNOWN: usize = 0usize
const BRAND_VISA: usize = 1usize
const BRAND_MASTERCARD: usize = 2usize
const BRAND_AMEX: usize = 3usize
const BRAND_DISCOVER: usize = 4usize
const BRAND_DINERS: usize = 5usize
const BRAND_JCB: usize = 6usize
const BRAND_UNIONPAY: usize = 7usize

fn card_brand(s: str) -> usize {
    var d: [24]u8 = zero
    let n = digits(s, d[..])
    if n < 12usize || n > 19usize { ret BRAND_UNKNOWN }
    let p1 = usize(d[0usize])
    let p2 = p1 * 10usize + usize(d[1usize])
    let p3 = p2 * 10usize + usize(d[2usize])
    let p4 = p3 * 10usize + usize(d[3usize])
    if p1 == 4usize && (n == 13usize || n == 16usize || n == 19usize) { ret BRAND_VISA }
    if ((p2 >= 51usize && p2 <= 55usize) || (p4 >= 2221usize && p4 <= 2720usize)) && n == 16usize { ret BRAND_MASTERCARD }
    if (p2 == 34usize || p2 == 37usize) && n == 15usize { ret BRAND_AMEX }
    if (p4 == 6011usize || p2 == 65usize || (p3 >= 644usize && p3 <= 649usize)) && n >= 16usize { ret BRAND_DISCOVER }
    if ((p3 >= 300usize && p3 <= 305usize) || p2 == 36usize || p2 == 38usize || p2 == 39usize) && n >= 14usize { ret BRAND_DINERS }
    if p4 >= 3528usize && p4 <= 3589usize && n >= 16usize { ret BRAND_JCB }
    if p2 == 62usize && n >= 16usize { ret BRAND_UNIONPAY }
    ret BRAND_UNKNOWN
}

fn card_brand_name(brand: usize) -> str {
    if brand == BRAND_VISA { ret "Visa" }
    if brand == BRAND_MASTERCARD { ret "Mastercard" }
    if brand == BRAND_AMEX { ret "American Express" }
    if brand == BRAND_DISCOVER { ret "Discover" }
    if brand == BRAND_DINERS { ret "Diners Club" }
    if brand == BRAND_JCB { ret "JCB" }
    if brand == BRAND_UNIONPAY { ret "UnionPay" }
    ret "Card"
}

// ---- more identifiers (C121): ISIN, LEI, VIN, Verhoeff, BIC and a card's expiry ---------------------------------

fn is_upper(c: u8) -> bool { ret c >= 65u8 && c <= 90u8 }
fn is_alnum_upper(c: u8) -> bool { ret is_digit(c) || is_upper(c) }

// ISIN: two letters (the country), nine letters or digits, a check digit; the letters become two digits each
// and the whole is a Luhn number. Upper case, no separators.
fn isin(s: str) -> bool {
    if s.len != 12usize { ret false }
    if !is_upper(s[0usize]) || !is_upper(s[1usize]) || !is_digit(s[11usize]) { ret false }
    var expanded: [24]u8 = zero
    var n = 0usize
    var i = 0usize
    while i < 12usize {
        let c = s[i]
        if !is_alnum_upper(c) { ret false }
        if is_digit(c) {
            expanded[n] = c
            n += 1usize
        } else {
            let v = c - 55u8
            expanded[n] = 48u8 + v / 10u8
            expanded[n + 1usize] = 48u8 + v % 10u8
            n += 2usize
        }
        i += 1usize
    }
    ret luhn(expanded[0usize..n])
}

// LEI (ISO 17442): twenty letters or digits whose last two are check digits, the whole 1 mod 97 (ISO 7064
// MOD 97-10). Upper case, no separators.
fn lei(s: str) -> bool {
    if s.len != 20usize { ret false }
    var i = 0usize
    while i < 20usize {
        if !is_alnum_upper(s[i]) { ret false }
        i += 1usize
    }
    if !is_digit(s[18usize]) || !is_digit(s[19usize]) { ret false }
    let (rest, good) = mod97(0u32, s)
    ret good && rest == 1u32
}

// VIN (ISO 3779, the North American check): seventeen letters or digits without I, O and Q; the ninth is the
// check digit (0 to 9 or X) of the weighted sum of the transliterated characters mod 11.
fn vin(s: str) -> bool {
    if s.len != 17usize { ret false }
    let weights = "\x08\x07\x06\x05\x04\x03\x02\x0a\x00\x09\x08\x07\x06\x05\x04\x03\x02"
    // A to Z (I, O and Q as zero, they are refused below).
    let letters = "\x01\x02\x03\x04\x05\x06\x07\x08\x00\x01\x02\x03\x04\x05\x00\x07\x00\x09\x02\x03\x04\x05\x06\x07\x08\x09"
    var total = 0usize
    var i = 0usize
    while i < 17usize {
        let c = s[i]
        var v = 0usize
        if is_digit(c) {
            v = usize(c - 48u8)
        } else if is_upper(c) && c != 73u8 && c != 79u8 && c != 81u8 {
            v = usize(letters[usize(c - 65u8)])
        } else {
            ret false
        }
        total += v * usize(weights[i])
        i += 1usize
    }
    let check = total % 11usize
    if check == 10usize { ret s[8usize] == 88u8 }
    ret s[8usize] == 48u8 + u8(check)
}

// Verhoeff: the digits (separators ignored), at least two, whose dihedral-group checksum is zero.
fn verhoeff(s: str) -> bool {
    var d: [40]u8 = zero
    let n = digits(s, d[..])
    if n < 2usize || n > 40usize { ret false }
    let multiply = "0123456789123406789523401789563401289567401239567859876043216598710432765982104387659321049876543210"
    let permute = "01234567891576283094580379614289160435279453126870428657390127938064157046913258"
    var c = 0usize
    var i = 0usize
    while i < n {
        let digit = usize(d[n - 1usize - i])
        let p = usize(permute[(i % 8usize) * 10usize + digit]) - 48usize
        c = usize(multiply[c * 10usize + p]) - 48usize
        i += 1usize
    }
    ret c == 0usize
}

// BIC / SWIFT (ISO 9362): four letters (the bank), two letters (the country), two letters or digits (the
// place), and optionally three letters or digits (the branch). Upper case.
fn bic(s: str) -> bool {
    if s.len != 8usize && s.len != 11usize { ret false }
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if i < 6usize {
            if !is_upper(c) { ret false }
        } else if !is_alnum_upper(c) {
            ret false
        }
        i += 1usize
    }
    ret true
}

// A card's expiry (month 1 to 12, a two- or four-digit year) is still good in `now_month` of `now_year`: the
// last day of the month counts, and a date more than twenty years out is not a card's.
fn card_expiry(month: u32, year: u32, now_month: u32, now_year: u32) -> bool {
    if month < 1u32 || month > 12u32 { ret false }
    var full = year
    if year < 100u32 { full = 2000u32 + year }
    if full < now_year || full > now_year + 20u32 { ret false }
    if full == now_year && month < now_month { ret false }
    ret true
}
