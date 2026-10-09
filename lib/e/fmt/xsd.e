// XML Schema 1.0 built-in datatypes: the lexical space of each primitive and derived simple type,
// checked after the type's whitespace handling (preserve for string, replace for normalizedString,
// collapse for every other type). `valid` answers whether a text is a legal lexical form of the
// type; value-space comparisons and facets belong to the schema validator that builds on this.
// The tables follow the Schema 1.0 Part 2 grammar (and its errata), including the details that
// are easy to get wrong: a `+` or an exponent where decimal allows neither, year 0000, 24:00:00,
// the 14:00 time-zone limit, leap days, base64 padding bits, and the XML 1.0 (5th edition) name
// characters. Dates are checked lexically only; `-0001` is accepted as a year and counted as a
// leap year by the astronomical rule.

use e.text.utf8

type Type = enum u8 {
    String, NormalizedString, Token, Language, Name, NCName, NMToken, ID, IDREF, AnyURI, QName,
    Boolean, Decimal, Integer, NonPositiveInteger, NegativeInteger, NonNegativeInteger, PositiveInteger,
    Long, Int, Short, Byte, UnsignedLong, UnsignedInt, UnsignedShort, UnsignedByte,
    Float, Double, Duration, DateTime, Time, Date, GYearMonth, GYear, GMonthDay, GDay, GMonth,
    HexBinary, Base64Binary,
}

type Whitespace = enum u8 { Preserve, Replace, Collapse }

// The type for a built-in's local name (`int`, `dateTime`, ...).
fn type_named(local: str) -> (Type, bool) {
    if same(local, "string") { ret (Type.String, true) }
    if same(local, "normalizedString") { ret (Type.NormalizedString, true) }
    if same(local, "token") { ret (Type.Token, true) }
    if same(local, "language") { ret (Type.Language, true) }
    if same(local, "Name") { ret (Type.Name, true) }
    if same(local, "NCName") { ret (Type.NCName, true) }
    if same(local, "NMTOKEN") { ret (Type.NMToken, true) }
    if same(local, "ID") { ret (Type.ID, true) }
    if same(local, "IDREF") { ret (Type.IDREF, true) }
    if same(local, "anyURI") { ret (Type.AnyURI, true) }
    if same(local, "QName") { ret (Type.QName, true) }
    if same(local, "boolean") { ret (Type.Boolean, true) }
    if same(local, "decimal") { ret (Type.Decimal, true) }
    if same(local, "integer") { ret (Type.Integer, true) }
    if same(local, "nonPositiveInteger") { ret (Type.NonPositiveInteger, true) }
    if same(local, "negativeInteger") { ret (Type.NegativeInteger, true) }
    if same(local, "nonNegativeInteger") { ret (Type.NonNegativeInteger, true) }
    if same(local, "positiveInteger") { ret (Type.PositiveInteger, true) }
    if same(local, "long") { ret (Type.Long, true) }
    if same(local, "int") { ret (Type.Int, true) }
    if same(local, "short") { ret (Type.Short, true) }
    if same(local, "byte") { ret (Type.Byte, true) }
    if same(local, "unsignedLong") { ret (Type.UnsignedLong, true) }
    if same(local, "unsignedInt") { ret (Type.UnsignedInt, true) }
    if same(local, "unsignedShort") { ret (Type.UnsignedShort, true) }
    if same(local, "unsignedByte") { ret (Type.UnsignedByte, true) }
    if same(local, "float") { ret (Type.Float, true) }
    if same(local, "double") { ret (Type.Double, true) }
    if same(local, "duration") { ret (Type.Duration, true) }
    if same(local, "dateTime") { ret (Type.DateTime, true) }
    if same(local, "time") { ret (Type.Time, true) }
    if same(local, "date") { ret (Type.Date, true) }
    if same(local, "gYearMonth") { ret (Type.GYearMonth, true) }
    if same(local, "gYear") { ret (Type.GYear, true) }
    if same(local, "gMonthDay") { ret (Type.GMonthDay, true) }
    if same(local, "gDay") { ret (Type.GDay, true) }
    if same(local, "gMonth") { ret (Type.GMonth, true) }
    if same(local, "hexBinary") { ret (Type.HexBinary, true) }
    if same(local, "base64Binary") { ret (Type.Base64Binary, true) }
    ret (Type.String, false)
}

fn whitespace(t: Type) -> Whitespace {
    if t == .String { ret Whitespace.Preserve }
    if t == .NormalizedString { ret Whitespace.Replace }
    ret Whitespace.Collapse
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 }

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// The text with leading and trailing XML whitespace removed (the collapse of a lexical form that
// may not contain interior whitespace anyway).
fn trim(text: str) -> str {
    var start = 0usize
    var end = text.len
    while start < end && is_space(text[start]) { start += 1usize }
    while end > start && is_space(text[end - 1usize]) { end -= 1usize }
    ret text[start..end]
}

// An XML 1.0 Char: tab, line feed, carriage return, U+0020..U+D7FF, U+E000..U+FFFD, U+10000..U+10FFFF.
fn is_xml_char(c: u32) -> bool {
    if c == 9u32 || c == 10u32 || c == 13u32 { ret true }
    if c >= 32u32 && c <= 55295u32 { ret true }
    if c >= 57344u32 && c <= 65533u32 { ret true }
    ret c >= 65536u32 && c <= 1114111u32
}

fn all_xml_chars(text: str) -> bool {
    var at = 0usize
    while at < text.len {
        let (d, decode_error) = utf8.decode(text, at)
        if decode_error != ok || !is_xml_char(d.scalar) { ret false }
        at += usize(d.width)
    }
    ret true
}

// XML 1.0 (5th edition) NameStartChar without ':' and NameChar without ':'.
fn is_ncname_start(c: u32) -> bool {
    if (c >= 65u32 && c <= 90u32) || c == 95u32 || (c >= 97u32 && c <= 122u32) { ret true }
    if (c >= 192u32 && c <= 214u32) || (c >= 216u32 && c <= 246u32) || (c >= 248u32 && c <= 767u32) { ret true }
    if (c >= 880u32 && c <= 893u32) || (c >= 895u32 && c <= 8191u32) || c == 8204u32 || c == 8205u32 { ret true }
    if (c >= 8304u32 && c <= 8591u32) || (c >= 11264u32 && c <= 12271u32) || (c >= 12289u32 && c <= 55295u32) { ret true }
    if (c >= 63744u32 && c <= 64975u32) || (c >= 65008u32 && c <= 65533u32) { ret true }
    ret c >= 65536u32 && c <= 983039u32
}

fn is_ncname_char(c: u32) -> bool {
    if is_ncname_start(c) || c == 45u32 || c == 46u32 || (c >= 48u32 && c <= 57u32) || c == 183u32 { ret true }
    ret (c >= 768u32 && c <= 879u32) || c == 8255u32 || c == 8256u32
}

// 0 = not a name, otherwise how many `:` the name holds; `allow_colon` admits them (Name, NMTOKEN).
fn name_shape(text: str, allow_colon: bool, token: bool) -> bool {
    if text.len == 0usize { ret false }
    var at = 0usize
    var first = true
    while at < text.len {
        let (d, decode_error) = utf8.decode(text, at)
        if decode_error != ok { ret false }
        let c = d.scalar
        var good = false
        if c == 58u32 { good = allow_colon } else if first && !token { good = is_ncname_start(c) } else { good = is_ncname_char(c) }
        if !good { ret false }
        first = false
        at += usize(d.width)
    }
    ret true
}

fn is_ncname(text: str) -> bool { ret name_shape(text, false, false) }
fn is_name(text: str) -> bool { ret name_shape(text, true, false) }
fn is_nmtoken(text: str) -> bool { ret name_shape(text, true, true) }

fn is_qname(text: str) -> bool {
    var colon = 0usize
    var count = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 58u8 {
            colon = i
            count += 1usize
        }
        i += 1usize
    }
    if count == 0usize { ret is_ncname(text) }
    ret count == 1usize && is_ncname(text[..colon]) && is_ncname(text[colon + 1usize..])
}

fn is_language(text: str) -> bool {
    // [a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*
    var i = 0usize
    var run = 0usize
    var first = true
    while i <= text.len {
        if i == text.len || text[i] == 45u8 {
            if run == 0usize || run > 8usize { ret false }
            run = 0usize
            first = false
        } else {
            let c = text[i]
            let letter = (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8)
            if !(letter || (!first && is_digit(c))) { ret false }
            run += 1usize
        }
        i += 1usize
    }
    ret true
}

fn hex_value(c: u8) -> bool { ret is_digit(c) || (c >= 65u8 && c <= 70u8) || (c >= 97u8 && c <= 102u8) }

// anyURI accepts any string of XML characters (the 1.1 reading; 1.0 leaves the lexical space to
// whatever the application can turn into a URI reference, and parsers differ on what they reject).
fn is_any_uri(text: str) -> bool { ret all_xml_chars(text) }

// ---- numbers ----

// Index just past an optional sign.
fn after_sign(s: str) -> usize {
    if s.len > 0usize && (s[0usize] == 43u8 || s[0usize] == 45u8) { ret 1usize }
    ret 0usize
}

fn all_digits(s: str) -> bool {
    if s.len == 0usize { ret false }
    var i = 0usize
    while i < s.len {
        if !is_digit(s[i]) { ret false }
        i += 1usize
    }
    ret true
}

// decimal: [+-]? (digits ('.' digits?)? | '.' digits)
fn is_decimal(s: str) -> bool {
    let b = s[after_sign(s)..]
    var dot = 0usize
    var found = false
    var i = 0usize
    while i < b.len {
        if b[i] == 46u8 {
            if found { ret false }
            found = true
            dot = i
        } else if !is_digit(b[i]) { ret false }
        i += 1usize
    }
    if !found { ret b.len > 0usize }
    ret dot > 0usize || b.len > 1usize
}

fn strip_zeros(digits: str) -> str {
    var i = 0usize
    while i + 1usize < digits.len && digits[i] == 48u8 { i += 1usize }
    ret digits[i..]
}

// Whether the unsigned digit string `digits` is at most `bound` (digit strings without leading zeros).
fn at_most(digits: str, bound: str) -> bool {
    let a = strip_zeros(digits)
    if a.len != bound.len { ret a.len < bound.len }
    var i = 0usize
    while i < a.len {
        if a[i] != bound[i] { ret a[i] < bound[i] }
        i += 1usize
    }
    ret true
}

fn is_zero(digits: str) -> bool { ret same(strip_zeros(digits), "0") }

// An integer text bounded by [-max_negative, max_positive]; either bound "" means that sign is refused
// entirely (zero excepted when `zero_ok`).
fn int_in(s: str, negative_limit: str, positive_limit: str, zero_ok: bool) -> bool {
    let at = after_sign(s)
    let digits = s[at..]
    if !all_digits(digits) { ret false }
    var negative = false
    if at == 1usize && s[0usize] == 45u8 { negative = true }
    if is_zero(digits) { ret zero_ok }
    if negative {
        if negative_limit.len == 0usize { ret false }
        ret at_most(digits, negative_limit)
    }
    if positive_limit.len == 0usize { ret false }
    ret at_most(digits, positive_limit)
}

fn is_float(s: str) -> bool {
    if same(s, "INF") || same(s, "-INF") || same(s, "NaN") { ret true }
    let b = s[after_sign(s)..]
    var e = b.len
    var i = 0usize
    while i < b.len {
        if b[i] == 101u8 || b[i] == 69u8 {
            e = i
            break
        }
        i += 1usize
    }
    if !is_decimal(b[..e]) || (e < b.len && b[..e].len > 0usize && b[0usize] == 43u8) { ret false }
    if e == b.len { ret true }
    let exp = b[e + 1usize..]
    ret all_digits(exp[after_sign(exp)..])
}

// ---- dates and times ----

fn two(s: str, at: usize) -> (u32, bool) {
    if at + 2usize > s.len || !is_digit(s[at]) || !is_digit(s[at + 1usize]) { ret (0u32, false) }
    ret (u32(s[at] - 48u8) * 10u32 + u32(s[at + 1usize] - 48u8), true)
}

fn leap_year(y: u64, negative: bool) -> bool {
    var year = y
    if negative && year > 0u64 { year = year - 1u64 }
    if year % 4u64 != 0u64 { ret false }
    if year % 100u64 != 0u64 { ret true }
    ret year % 400u64 == 0u64
}

fn days_in(month: u32, year: u64, negative: bool) -> u32 {
    if month == 2u32 {
        if leap_year(year, negative) { ret 29u32 }
        ret 28u32
    }
    if month == 4u32 || month == 6u32 || month == 9u32 || month == 11u32 { ret 30u32 }
    ret 31u32
}

// -?YYYY+ : at least four digits, no leading zero beyond four, not zero. Answers the index after it.
fn scan_year(s: str, at: usize) -> (usize, u64, bool, bool) {
    var i = at
    var negative = false
    if i < s.len && s[i] == 45u8 {
        negative = true
        i += 1usize
    }
    let start = i
    var value = 0u64
    while i < s.len && is_digit(s[i]) {
        if i - start < 18usize { value = value * 10u64 + u64(s[i] - 48u8) }
        i += 1usize
    }
    let digits = i - start
    if digits < 4usize { ret (at, 0u64, negative, false) }
    if digits > 4usize && s[start] == 48u8 { ret (at, 0u64, negative, false) }
    if is_zero(s[start..i]) { ret (at, 0u64, negative, false) }
    ret (i, value, negative, true)
}

// An optional time zone to the end of the text: Z, or [+-]hh:mm with hh up to 14 and 14:00 the limit.
fn is_zone(s: str, at: usize) -> bool {
    if at == s.len { ret true }
    if s[at] == 90u8 { ret at + 1usize == s.len }
    if s[at] != 43u8 && s[at] != 45u8 { ret false }
    let (hours, hours_ok) = two(s, at + 1usize)
    if !hours_ok || at + 3usize >= s.len || s[at + 3usize] != 58u8 { ret false }
    let (minutes, minutes_ok) = two(s, at + 4usize)
    if !minutes_ok || at + 6usize != s.len || minutes > 59u32 { ret false }
    ret hours < 14u32 || (hours == 14u32 && minutes == 0u32)
}

// hh:mm:ss(.s+)? at `at`, then the zone to the end.
fn is_time_then_zone(s: str, at: usize) -> bool {
    let (hour, hour_ok) = two(s, at)
    if !hour_ok || at + 2usize >= s.len || s[at + 2usize] != 58u8 { ret false }
    let (minute, minute_ok) = two(s, at + 3usize)
    if !minute_ok || at + 5usize >= s.len || s[at + 5usize] != 58u8 { ret false }
    let (second, second_ok) = two(s, at + 6usize)
    if !second_ok || minute > 59u32 || second > 59u32 { ret false }
    var i = at + 8usize
    var fraction = false
    if i < s.len && s[i] == 46u8 {
        i += 1usize
        let start = i
        while i < s.len && is_digit(s[i]) { i += 1usize }
        if i == start { ret false }
        var nonzero = false
        var k = start
        while k < i {
            if s[k] != 48u8 { nonzero = true }
            k += 1usize
        }
        fraction = nonzero
    }
    if hour == 24u32 {
        if minute != 0u32 || second != 0u32 || fraction { ret false }
    } else if hour > 23u32 {
        ret false
    }
    ret is_zone(s, i)
}

fn is_date_then(s: str, at: usize, want_time: bool, want_day: bool) -> bool {
    let (year_end, year, negative, year_ok) = scan_year(s, at)
    if !year_ok { ret false }
    if year_end >= s.len || s[year_end] != 45u8 {
        ret false
    }
    let (month, month_ok) = two(s, year_end + 1usize)
    if !month_ok || month < 1u32 || month > 12u32 { ret false }
    var i = year_end + 3usize
    if !want_day { ret is_zone(s, i) }
    if i >= s.len || s[i] != 45u8 { ret false }
    let (day, day_ok) = two(s, i + 1usize)
    if !day_ok || day < 1u32 || day > days_in(month, year, negative) { ret false }
    i += 3usize
    if want_time {
        if i >= s.len || s[i] != 84u8 { ret false }
        ret is_time_then_zone(s, i + 1usize)
    }
    ret is_zone(s, i)
}

fn is_g_year(s: str) -> bool {
    let (end, _, _, ok_year) = scan_year(s, 0usize)
    ret ok_year && is_zone(s, end)
}

// --MM-DD, ---DD and --MM(--)? : the day checked against the longest month, February 29 allowed.
fn is_g_month_day(s: str) -> bool {
    if s.len < 7usize || s[0usize] != 45u8 || s[1usize] != 45u8 { ret false }
    let (month, month_ok) = two(s, 2usize)
    if !month_ok || month < 1u32 || month > 12u32 || s[4usize] != 45u8 { ret false }
    let (day, day_ok) = two(s, 5usize)
    if !day_ok || day < 1u32 { ret false }
    if day > days_in(month, 4u64, false) { ret false }
    ret is_zone(s, 7usize)
}

fn is_g_day(s: str) -> bool {
    if s.len < 5usize || s[0usize] != 45u8 || s[1usize] != 45u8 || s[2usize] != 45u8 { ret false }
    let (day, day_ok) = two(s, 3usize)
    if !day_ok || day < 1u32 || day > 31u32 { ret false }
    ret is_zone(s, 5usize)
}

fn is_g_month(s: str) -> bool {
    if s.len < 4usize || s[0usize] != 45u8 || s[1usize] != 45u8 { ret false }
    let (month, month_ok) = two(s, 2usize)
    if !month_ok || month < 1u32 || month > 12u32 { ret false }
    ret is_zone(s, 4usize)
}

// -?P(nY)?(nM)?(nD)?(T(nH)?(nM)?(n(.n)?S)?)?, with at least one component and a T that is followed by one.
fn is_duration(s: str) -> bool {
    var i = 0usize
    if i < s.len && s[i] == 45u8 { i += 1usize }
    if i >= s.len || s[i] != 80u8 { ret false }
    i += 1usize
    var components = 0usize
    var in_time = false
    var time_components = 0usize
    var stage = 0usize
    while i < s.len {
        if s[i] == 84u8 {
            if in_time { ret false }
            in_time = true
            stage = 10usize
            i += 1usize
            continue
        }
        let start = i
        while i < s.len && is_digit(s[i]) { i += 1usize }
        if i == start || i >= s.len { ret false }
        var fraction = false
        if s[i] == 46u8 {
            fraction = true
            i += 1usize
            let digits_start = i
            while i < s.len && is_digit(s[i]) { i += 1usize }
            if i == digits_start || i >= s.len { ret false }
        }
        let designator = s[i]
        i += 1usize
        if !in_time {
            if fraction { ret false }
            var rank = 0usize
            if designator == 89u8 { rank = 1usize } else if designator == 77u8 { rank = 2usize } else if designator == 68u8 { rank = 3usize } else { ret false }
            if rank <= stage { ret false }
            stage = rank
            components += 1usize
        } else {
            var rank = 0usize
            if designator == 72u8 { rank = 11usize } else if designator == 77u8 { rank = 12usize } else if designator == 83u8 { rank = 13usize } else { ret false }
            if fraction && rank != 13usize { ret false }
            if rank <= stage { ret false }
            stage = rank
            components += 1usize
            time_components += 1usize
        }
    }
    if in_time && time_components == 0usize { ret false }
    ret components > 0usize
}

// ---- binary ----

fn is_hex_binary(s: str) -> bool {
    if s.len % 2usize != 0usize { ret false }
    var i = 0usize
    while i < s.len {
        if !hex_value(s[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn base64_value(c: u8) -> i32 {
    if c >= 65u8 && c <= 90u8 { ret i32(c) - 65i32 }
    if c >= 97u8 && c <= 122u8 { ret i32(c) - 97i32 + 26i32 }
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 + 52i32 }
    if c == 43u8 { ret 62i32 }
    if c == 47u8 { ret 63i32 }
    ret -1i32
}

// Base64 with XML whitespace allowed between characters (it is collapsed away), full groups of four,
// '=' only as the last one or two characters, and the unused low bits of the last group zero.
fn is_base64(s: str) -> bool {
    var count = 0usize
    var pad = 0usize
    var last = 0i32
    var before_last = 0i32
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if is_space(c) {
            i += 1usize
            continue
        }
        if c == 61u8 {
            pad += 1usize
            if pad > 2usize { ret false }
        } else {
            if pad > 0usize { ret false }
            let v = base64_value(c)
            if v < 0i32 { ret false }
            before_last = last
            last = v
        }
        count += 1usize
        i += 1usize
    }
    if count % 4usize != 0usize { ret false }
    if pad == 2usize { ret count >= 4usize && (last & 15i32) == 0i32 }
    if pad == 1usize { ret count >= 4usize && (last & 3i32) == 0i32 }
    ret true
}

// ---- the dispatch ----

// Whether `text` is a legal lexical form of `t` after the type's whitespace handling.
fn valid(t: Type, text: str) -> bool {
    if t == .String || t == .NormalizedString || t == .Token { ret all_xml_chars(text) }
    let s = trim(text)
    if t == .Language { ret is_language(s) }
    if t == .Name { ret is_name(s) }
    if t == .NCName || t == .ID || t == .IDREF { ret is_ncname(s) }
    if t == .NMToken { ret is_nmtoken(s) }
    if t == .AnyURI { ret is_any_uri(s) }
    if t == .QName { ret is_qname(s) }
    if t == .Boolean { ret same(s, "true") || same(s, "false") || same(s, "1") || same(s, "0") }
    if t == .Decimal { ret is_decimal(s) }
    if t == .Integer { ret all_digits(s[after_sign(s)..]) }
    if t == .NonPositiveInteger { ret int_in(s, "99999999999999999999999999999999999999999999999999999999", "", true) && all_digits(s[after_sign(s)..]) }
    if t == .NegativeInteger { ret int_in(s, "99999999999999999999999999999999999999999999999999999999", "", false) && all_digits(s[after_sign(s)..]) }
    if t == .NonNegativeInteger { ret int_in(s, "", "99999999999999999999999999999999999999999999999999999999", true) && all_digits(s[after_sign(s)..]) }
    if t == .PositiveInteger { ret int_in(s, "", "99999999999999999999999999999999999999999999999999999999", false) && all_digits(s[after_sign(s)..]) }
    if t == .Long { ret int_in(s, "9223372036854775808", "9223372036854775807", true) }
    if t == .Int { ret int_in(s, "2147483648", "2147483647", true) }
    if t == .Short { ret int_in(s, "32768", "32767", true) }
    if t == .Byte { ret int_in(s, "128", "127", true) }
    if t == .UnsignedLong { ret int_in(s, "", "18446744073709551615", true) }
    if t == .UnsignedInt { ret int_in(s, "", "4294967295", true) }
    if t == .UnsignedShort { ret int_in(s, "", "65535", true) }
    if t == .UnsignedByte { ret int_in(s, "", "255", true) }
    if t == .Float || t == .Double { ret is_float(s) }
    if t == .Duration { ret is_duration(s) }
    if t == .DateTime { ret is_date_then(s, 0usize, true, true) }
    if t == .Date { ret is_date_then(s, 0usize, false, true) }
    if t == .Time { ret is_time_then_zone(s, 0usize) }
    if t == .GYearMonth { ret is_date_then(s, 0usize, false, false) }
    if t == .GYear { ret is_g_year(s) }
    if t == .GMonthDay { ret is_g_month_day(s) }
    if t == .GDay { ret is_g_day(s) }
    if t == .GMonth { ret is_g_month(s) }
    if t == .HexBinary { ret is_hex_binary(s) }
    ret is_base64(s)
}
