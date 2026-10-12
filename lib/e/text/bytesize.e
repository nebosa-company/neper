// Byte-size text: parse `1.5 GiB`, `10MB`, `512k`, `42` into a byte count and format a count
// as `1.5 MB` or `1.5 MiB`, the conventions of Go's go-humanize `ParseBytes` / `Bytes` /
// `IBytes`, in exact integer arithmetic.
//
// Parsing: optional surrounding spaces, a decimal number (digits, optionally `.` and digits),
// optional spaces, an optional unit, case-insensitive. Units: `b`; the decimal `k kb m mb g gb
// t tb p pb e eb` (powers of 1000) and the binary `ki kib mi mib gi gib ti tib pi pib ei eib`
// (powers of 1024). A bare number is bytes. A fractional count is truncated toward zero after
// scaling (`1.5 KiB` is 1536, `1.5 B` is 1). More than 18 fractional digits are ignored; a
// result past `u64` is `Overflow`; an unknown unit, a sign or an empty string is `Invalid`.
//
// Formatting: a count under 10 is `N B`; otherwise the largest unit not above it, the value
// rounded half up to one decimal and printed with the decimal when it is under 10 (`9.5 kB`)
// and without it otherwise (`83 MB`; a value ending in exactly .5 rounds half to even, as
// Go's `%.0f` does). A value that rounds up to 1000 (999999 -> `1000 kB`) is left as is.

error Invalid
error Overflow
error TooSmall

fn fold(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn power(base: u64, e: u32) -> u64 {
    var v = 1u64
    var i = 0u32
    while i < e {
        v = v * base
        i += 1u32
    }
    ret v
}

// The multiplier of a (lower-cased) unit name, or 0 when unknown.
fn unit_scale(name: str) -> u64 {
    if name.len == 0usize || (name.len == 1usize && name[0usize] == 98u8) { ret 1u64 }
    var index = 0u32
    let c = name[0usize]
    if c == 107u8 { index = 1u32 }
    if c == 109u8 { index = 2u32 }
    if c == 103u8 { index = 3u32 }
    if c == 116u8 { index = 4u32 }
    if c == 112u8 { index = 5u32 }
    if c == 101u8 { index = 6u32 }
    if index == 0u32 { ret 0u64 }
    let rest = name[1usize..name.len]
    if rest.len == 0usize || (rest.len == 1usize && rest[0usize] == 98u8) { ret power(1000u64, index) }
    if rest.len == 1usize && rest[0usize] == 105u8 { ret power(1024u64, index) }
    if rest.len == 2usize && rest[0usize] == 105u8 && rest[1usize] == 98u8 { ret power(1024u64, index) }
    ret 0u64
}

// 64x64 -> 128 bit product as (high, low).
fn mul_wide(a: u64, b: u64) -> (u64, u64) {
    let a0 = a & 4294967295u64
    let a1 = a >> 32u64
    let b0 = b & 4294967295u64
    let b1 = b >> 32u64
    let p00 = a0 * b0
    let p01 = a0 * b1
    let p10 = a1 * b0
    let p11 = a1 * b1
    let mid = (p00 >> 32u64) + (p01 & 4294967295u64) + (p10 & 4294967295u64)
    let low = (p00 & 4294967295u64) | ((mid & 4294967295u64) << 32u64)
    let high = p11 + (p01 >> 32u64) + (p10 >> 32u64) + (mid >> 32u64)
    ret (high, low)
}

// floor((high:low) / d) when the quotient fits u64 (high < d); bitwise long division.
fn div_wide(high: u64, low: u64, d: u64) -> u64 {
    var rem = high
    var q = 0u64
    var bit = 64u64
    while bit > 0u64 {
        bit -= 1u64
        let top = rem >> 63u64
        rem = (rem << 1u64) | ((low >> bit) & 1u64)
        q = q << 1u64
        if top == 1u64 || rem >= d {
            rem = rem -% d
            q = q | 1u64
        }
    }
    ret q
}

fn parse(s: str) -> (u64, err) {
    var i = 0usize
    while i < s.len && s[i] == 32u8 { i += 1usize }
    var end = s.len
    while end > i && s[end - 1usize] == 32u8 { end -= 1usize }
    if i >= end { ret (0u64, Invalid) }
    var whole = 0u64
    var digits = 0usize
    while i < end && is_digit(s[i]) {
        let d = u64(s[i] - 48u8)
        if whole > (18446744073709551615u64 - d) / 10u64 { ret (0u64, Overflow) }
        whole = whole * 10u64 + d
        digits += 1usize
        i += 1usize
    }
    if digits == 0usize { ret (0u64, Invalid) }
    var frac = 0u64
    var frac_digits = 0u32
    if i < end && s[i] == 46u8 {
        i += 1usize
        var seen = 0usize
        while i < end && is_digit(s[i]) {
            if frac_digits < 18u32 {
                frac = frac * 10u64 + u64(s[i] - 48u8)
                frac_digits += 1u32
            }
            seen += 1usize
            i += 1usize
        }
        if seen == 0usize { ret (0u64, Invalid) }
    }
    while i < end && s[i] == 32u8 { i += 1usize }
    var name_buf: [4]u8 = zero
    var n = 0usize
    while i < end {
        if n >= 4usize { ret (0u64, Invalid) }
        name_buf[n] = fold(s[i])
        n += 1usize
        i += 1usize
    }
    let unit = unit_scale(name_buf[0usize..n])
    if unit == 0u64 { ret (0u64, Invalid) }
    if whole > 0u64 && unit > 18446744073709551615u64 / whole { ret (0u64, Overflow) }
    var total = whole * unit
    if frac > 0u64 {
        let (hi, lo) = mul_wide(unit, frac)
        let scaled = div_wide(hi, lo, power(10u64, frac_digits))
        if total > 18446744073709551615u64 - scaled { ret (0u64, Overflow) }
        total += scaled
    }
    ret (total, ok)
}

fn put_number(dst: []u8, n: usize, v: u64) -> (usize, bool) {
    var digits: [20]u8 = zero
    var count = 0usize
    var x = v
    if x == 0u64 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while x > 0u64 {
        digits[count] = u8(48u64 + x % 10u64)
        count += 1usize
        x = x / 10u64
    }
    if n + count > dst.len { ret (n, false) }
    var k = 0usize
    while k < count {
        dst[n + k] = digits[count - 1usize - k]
        k += 1usize
    }
    ret (n + count, true)
}

fn put_text(dst: []u8, n: usize, s: str) -> (usize, bool) {
    if n + s.len > dst.len { ret (n, false) }
    var k = 0usize
    while k < s.len {
        dst[n + k] = s[k]
        k += 1usize
    }
    ret (n + s.len, true)
}

fn unit_name(index: u32, iec: bool) -> str {
    if index == 0u32 { ret "B" }
    if iec {
        if index == 1u32 { ret "KiB" }
        if index == 2u32 { ret "MiB" }
        if index == 3u32 { ret "GiB" }
        if index == 4u32 { ret "TiB" }
        if index == 5u32 { ret "PiB" }
        ret "EiB"
    }
    if index == 1u32 { ret "kB" }
    if index == 2u32 { ret "MB" }
    if index == 3u32 { ret "GB" }
    if index == 4u32 { ret "TB" }
    if index == 5u32 { ret "PB" }
    ret "EB"
}

fn format(size: u64, iec: bool, dst: []u8) -> (str, err) {
    var n = 0usize
    var fits = true
    if size < 10u64 {
        let (n1, f1) = put_number(dst, 0usize, size)
        let (n2, f2) = put_text(dst, n1, " B")
        if !f1 || !f2 { ret ("", TooSmall) }
        ret (dst[..n2], ok)
    }
    var base = 1000u64
    if iec { base = 1024u64 }
    var index = 0u32
    var unit = 1u64
    while index < 6u32 && size / unit >= base {
        unit = unit * base
        index += 1u32
    }
    // value in tenths, rounded half up: (size * 10 + unit / 2) / unit without overflow.
    let q = size / unit
    let r = size % unit
    let val10 = q * 10u64 + (r * 10u64 + unit / 2u64) / unit
    var whole = val10 / 10u64
    let tenth = val10 % 10u64
    if val10 < 100u64 {
        let (n1, f1) = put_number(dst, 0usize, whole)
        let (n2, f2) = put_text(dst, n1, ".")
        let (n3, f3) = put_number(dst, n2, tenth)
        n = n3
        fits = f1 && f2 && f3
    } else {
        // %.0f of whole.tenth: half to even
        if tenth > 5u64 || (tenth == 5u64 && whole % 2u64 == 1u64) { whole += 1u64 }
        let (n1, f1) = put_number(dst, 0usize, whole)
        n = n1
        fits = f1
    }
    let (n4, f4) = put_text(dst, n, " ")
    let (n5, f5) = put_text(dst, n4, unit_name(index, iec))
    if !fits || !f4 || !f5 { ret ("", TooSmall) }
    ret (dst[..n5], ok)
}
