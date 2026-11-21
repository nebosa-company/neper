// YAML, the subset the fence names: block mappings and sequences by indentation,
// flow collections, plain, single- and double-quoted scalars, literal and folded
// blocks with their chomping indicators, and the core schema's null, bool, integer
// and float forms; comments and one leading `---`. The source is split into logical
// lines once -- indent and content with the comment stripped, quotes respected --
// and parsed by recursive descent on indentation; a sequence item that begins a
// mapping is re-read as that mapping two columns in. Anchors, aliases, tags,
// directives and a second document are `Unsupported`; nesting past `max_depth` is
// `TooDeep`; a repeated key is `DuplicateKey` unless the options allow it. The
// writer emits block style, quoting a string that would otherwise read as another
// type; the typed codec follows the other codecs, a struct being a mapping of its
// fields.
// Plain and quoted scalar continuations are Unsupported; flow collections are
// single-line. `parse_r` and `write_r` are R's `yaml.load` and `as.yaml` (libyaml with the
// 1.1 implicit tags, `!!` tags, anchors, merge keys; see the section marked R's yaml package).
// Block collections are limited to 256 entries and flow collections to 64; both
// report TooLarge. A zero max_depth means 16, and larger requests are capped at 16
// so the fixed parser frames stay within a bounded stack.
use e.io
use e.mem
use e.meta
use e.str
use e.fmt.cfloat as cfloat
use e.text.utf8 as utf8

type Pair = struct { key: Value, value: Value }
// NA is R's typed missing value (0 logical, 1 integer, 2 real, 3 character); only `parse_r` makes one.
type Value = union enum u8 { Null, Bool: bool, Integer: i64, Float: f64, String: str, Sequence: []const Value, Mapping: []const Pair, NA: u8 }
type Options = struct { max_depth: u16, allow_duplicate_keys: bool }
const MAX_DEPTH: u16 = 16u16
const MAX_ANCHORS: usize = 64usize
error Invalid
error TooDeep
error TooLarge
error DuplicateKey
error Unsupported
error InvalidTag

type Line = struct { indent: usize, text: str, raw: str }
// `rmode` is the R `yaml` package's loader: libyaml's 1.1 implicit tags, `!!` tags, anchors and
// aliases, `<<` merge keys, and R's list simplification (see parse_r).
type Parser = struct { a: *mem.Arena, lines: []Line, at: usize, options: Options, rmode: bool, anchor_names: [64]str, anchor_values: [64]Value, anchor_count: usize, collapsed: bool, in_item: bool }

// --- Lines.

fn is_blank(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        if text[i] != 32u8 && text[i] != 9u8 && text[i] != 13u8 { ret false }
        i += 1usize
    }
    ret true
}

// YAML permits both ASCII space and tab as inline separation. Tabs remain invalid
// when they begin indentation; that is checked from the raw line separately.
fn is_inline_space(byte: u8) -> bool {
    ret byte == 32u8 || byte == 9u8
}

// The content of a line up to a `#` that starts a comment: one preceded by inline
// separation and outside quotes.
fn strip_comment(text: str) -> str {
    var quote = 0u8
    var scalar_start = true
    var flow_depth = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if quote != 0u8 {
            // A backslash escapes the next byte only in a double-quoted scalar.
            // Do not let an escaped quote expose a following # as a comment.
            if quote == 34u8 && c == 92u8 && i + 1usize < text.len {
                i += 1usize
            } else {
                if quote == 39u8 && c == 39u8 && i + 1usize < text.len && text[i + 1usize] == 39u8 {
                    i += 1usize
                } else {
                    if c == quote {
                        quote = 0u8
                        scalar_start = false
                    }
                }
            }
        } else {
            if scalar_start && (c == 34u8 || c == 39u8) {
                quote = c
            } else {
                if c == 35u8 && (i == 0usize || text[i - 1usize] == 32u8 || text[i - 1usize] == 9u8) { ret str.trim_end(text[..i]) }
                if scalar_start && (c == 91u8 || c == 123u8) {
                    flow_depth += 1usize
                    scalar_start = true
                } else {
                if flow_depth > 0usize && (c == 93u8 || c == 125u8) {
                    flow_depth -= 1usize
                    scalar_start = false
                } else {
                if flow_depth > 0usize && c == 44u8 {
                    scalar_start = true
                } else {
                if c == 58u8 && ((i + 1usize == text.len || text[i + 1usize] == 32u8 || text[i + 1usize] == 9u8) || flow_depth > 0usize) {
                    scalar_start = true
                } else {
                if scalar_start && c == 45u8 && (i + 1usize == text.len || text[i + 1usize] == 32u8 || text[i + 1usize] == 9u8) {
                    scalar_start = true
                } else {
                if c != 32u8 && c != 9u8 {
                    scalar_start = false
                }
                }
                }
                }
                }
                }
            }
        }
        i += 1usize
    }
    ret str.trim_end(text)
}

// YAML's presentation stream is UTF-8, but valid UTF-8 is not enough: C0/DEL and
// most C1 scalars must be escaped. Physical CR/LF line breaks remain legal here.
fn is_yaml_printable(scalar: u32) -> bool {
    if scalar == 9u32 || scalar == 10u32 || scalar == 13u32 { ret true }
    if scalar >= 32u32 && scalar <= 126u32 { ret true }
    if scalar == 133u32 { ret true }
    if scalar >= 160u32 && scalar <= 55295u32 { ret true }
    if scalar >= 57344u32 && scalar <= 65533u32 { ret true }
    ret scalar >= 65536u32 && scalar <= 1114111u32
}

fn valid_yaml_presentation(text: str) -> bool {
    var at = 0usize
    while at < text.len {
        let (decoded, decode_error) = utf8.decode(text, at)
        if decode_error != ok || !is_yaml_printable(decoded.scalar) { ret false }
        at += usize(decoded.width)
    }
    ret true
}

fn split_lines(a: *mem.Arena, source: str) -> ([]Line, err) {
    var count = 1usize
    var i = 0usize
    while i < source.len {
        if source[i] == 10u8 { count += 1usize } else {
            if source[i] == 13u8 {
                count += 1usize
                if i + 1usize < source.len && source[i + 1usize] == 10u8 { i += 1usize }
            }
        }
        i += 1usize
    }
    let (lines, lines_error) = mem.alloc[Line](a, count)
    if lines_error != ok { ret (zero, lines_error) }
    var used = 0usize
    var at = 0usize
    while at <= source.len {
        var stop = at
        while stop < source.len && source[stop] != 10u8 && source[stop] != 13u8 { stop += 1usize }
        var raw = source[at..stop]
        var indent = 0usize
        while indent < raw.len && raw[indent] == 32u8 { indent += 1usize }
        lines[used] = Line { indent: indent, text: strip_comment(raw[indent..]), raw: raw }
        used += 1usize
        if stop >= source.len { break }
        at = stop + 1usize
        if source[stop] == 13u8 && at < source.len && source[at] == 10u8 { at += 1usize }
    }
    ret (lines[..used], ok)
}

// --- Scalars.

fn all_digits(text: str, from: usize) -> bool {
    if from >= text.len { ret false }
    var i = from
    while i < text.len {
        if !str.is_ascii_digit(text[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn parse_plain_float(a: *mem.Arena, text: str, from: usize, has_point: bool, point_at: usize, exponent_at: usize) -> (f64, err) {
    var normalize = text.len > 0usize && text[0] == 43u8
    if has_point && (point_at == from || point_at + 1usize == exponent_at) { normalize = true }
    if has_point && point_at + 1usize == text.len { normalize = true }
    var probe = 0usize
    while probe < text.len {
        if text[probe] == 69u8 { normalize = true }
        probe += 1usize
    }
    if !normalize {
        let (number, number_error) = str.parse_f64(text)
        ret (number, number_error)
    }
    let (out, out_error) = mem.alloc[u8](a, text.len + 2usize)
    if out_error != ok { ret (0.0, out_error) }
    var used = 0usize
    var i = 0usize
    while i < text.len {
        if i == point_at && has_point && point_at == from {
            out[used] = 48u8
            used += 1usize
        }
        if i == 0usize && text[i] == 43u8 {
            i += 1usize
            continue
        }
        let c = text[i]
        if c == 69u8 { out[used] = 101u8 } else { out[used] = c }
        used += 1usize
        if has_point && c == 46u8 && (i + 1usize == text.len || i + 1usize == exponent_at) {
            out[used] = 48u8
            used += 1usize
        }
        i += 1usize
    }
    let (number, number_error) = str.parse_f64(out[..used])
    ret (number, number_error)
}

// A plain scalar by the core schema: null, bool, integer, float, else a string.
fn resolve_plain(a: *mem.Arena, text: str) -> (Value, err) {
    if text.len == 0usize || str.eq(text, "~") || str.eq(text, "null") || str.eq(text, "Null") || str.eq(text, "NULL") { ret (.Null, ok) }
    if str.eq(text, "true") || str.eq(text, "True") || str.eq(text, "TRUE") { ret (Value{ Bool: true }, ok) }
    if str.eq(text, "false") || str.eq(text, "False") || str.eq(text, "FALSE") { ret (Value{ Bool: false }, ok) }
    var from = 0usize
    var negative = false
    if text[0] == 43u8 || text[0] == 45u8 {
        negative = text[0] == 45u8
        from = 1usize
    }
    let body = text[from..]
    if str.eq(body, ".inf") || str.eq(body, ".Inf") || str.eq(body, ".INF") {
        var inf = mem.bitcast[f64](9218868437227405312u64)
        if negative { inf = 0.0 - inf }
        ret (Value{ Float: inf }, ok)
    }
    if from == 0usize && (str.eq(body, ".nan") || str.eq(body, ".NaN") || str.eq(body, ".NAN")) { ret (Value{ Float: mem.bitcast[f64](9221120237041090560u64) }, ok) }
    if from == 0usize && body.len > 2usize && body[0] == 48u8 && (body[1] == 120u8 || body[1] == 111u8) {
        var radix = 16u8
        if body[1] == 111u8 { radix = 8u8 }
        let (magnitude, radix_error) = str.parse_u64_radix(body[2usize..], radix)
        if radix_error == ok && magnitude <= 9223372036854775807u64 {
            var number = i64(magnitude)
            if negative { number = 0i64 - number }
            ret (Value{ Integer: number }, ok)
        }
        ret (Value{ String: text }, ok)
    }
    if all_digits(body, 0usize) {
        var decimal = text
        if text[0] == 43u8 { decimal = body }
        let (number, number_error) = str.parse_i64(decimal)
        if number_error == ok { ret (Value{ Integer: number }, ok) }
        ret (Value{ String: text }, ok)
    }
    // A float has digits with a point or an exponent and nothing else.
    var mantissa_digits = 0usize
    var exponent_digits = 0usize
    var points = 0usize
    var exponents = 0usize
    var point_at = 0usize
    var exponent_at = text.len
    var shape_ok = body.len > 0usize
    var i = 0usize
    while i < body.len {
        let c = body[i]
        if str.is_ascii_digit(c) {
            if exponents == 0usize { mantissa_digits += 1usize } else { exponent_digits += 1usize }
        } else {
        if c == 46u8 {
            points += 1usize
            point_at = from + i
            if exponents > 0usize { shape_ok = false }
        } else {
        if c == 101u8 || c == 69u8 {
            exponents += 1usize
            exponent_at = from + i
            if mantissa_digits == 0usize || i + 1usize >= body.len { shape_ok = false }
            if i + 1usize < body.len && (body[i + 1usize] == 43u8 || body[i + 1usize] == 45u8) { i += 1usize }
        } else {
            shape_ok = false
        }
        }
        }
        i += 1usize
    }
    if exponents > 0usize && exponent_digits == 0usize { shape_ok = false }
    if shape_ok && mantissa_digits > 0usize && points <= 1usize && exponents <= 1usize && (points == 1usize || exponents == 1usize) {
        let (number, number_error) = parse_plain_float(a, text, from, points == 1usize, point_at, exponent_at)
        if number_error == ok { ret (Value{ Float: number }, ok) }
        if number_error == mem.Exhausted { ret (zero, number_error) }
    }
    ret (Value{ String: text }, ok)
}

fn hex_value(c: u8) -> (u32, bool) {
    if c >= 48u8 && c <= 57u8 { ret (u32(c - 48u8), true) }
    if c >= 97u8 && c <= 102u8 { ret (u32(c - 87u8), true) }
    if c >= 65u8 && c <= 70u8 { ret (u32(c - 55u8), true) }
    ret (0u32, false)
}

fn push_utf8(out: []u8, at: usize, scalar: u32) -> usize {
    if scalar < 128u32 {
        out[at] = u8(scalar)
        ret at + 1usize
    }
    if scalar < 2048u32 {
        out[at] = u8(192u32 | (scalar >> 6u32))
        out[at + 1usize] = u8(128u32 | (scalar & 63u32))
        ret at + 2usize
    }
    if scalar < 65536u32 {
        out[at] = u8(224u32 | (scalar >> 12u32))
        out[at + 1usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
        out[at + 2usize] = u8(128u32 | (scalar & 63u32))
        ret at + 3usize
    }
    out[at] = u8(240u32 | (scalar >> 18u32))
    out[at + 1usize] = u8(128u32 | ((scalar >> 12u32) & 63u32))
    out[at + 2usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
    out[at + 3usize] = u8(128u32 | (scalar & 63u32))
    ret at + 4usize
}

// A double-quoted body with its escapes decoded into the arena.
fn unescape_double(a: *mem.Arena, body: str) -> (str, err) {
    let (slash, has_slash) = str.find(body, "\\")
    if !has_slash { ret (body, ok) }
    var capacity = body.len
    var scan = 0usize
    while scan + 1usize < body.len {
        if body[scan] == 92u8 && (body[scan + 1usize] == 76u8 || body[scan + 1usize] == 80u8) {
            capacity += 1usize
            scan += 2usize
        } else {
            scan += 1usize
        }
    }
    let (out, out_error) = mem.alloc[u8](a, capacity)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var i = 0usize
    while i < body.len {
        let c = body[i]
        if c != 92u8 {
            out[used] = c
            used += 1usize
            i += 1usize
            continue
        }
        i += 1usize
        if i >= body.len { ret ("", Invalid) }
        let e = body[i]
        i += 1usize
        if e == 97u8 { out[used] = 7u8 } else {
        if e == 98u8 { out[used] = 8u8 } else {
        if e == 102u8 { out[used] = 12u8 } else {
        if e == 101u8 { out[used] = 27u8 } else {
        if e == 118u8 { out[used] = 11u8 } else {
        if e == 110u8 { out[used] = 10u8 } else {
        if e == 116u8 { out[used] = 9u8 } else {
        if e == 114u8 { out[used] = 13u8 } else {
        if e == 48u8 { out[used] = 0u8 } else {
        if e == 78u8 {
            used = push_utf8(out, used, 133u32)
            continue
        } else {
        if e == 95u8 {
            used = push_utf8(out, used, 160u32)
            continue
        } else {
        if e == 76u8 {
            used = push_utf8(out, used, 8232u32)
            continue
        } else {
        if e == 80u8 {
            used = push_utf8(out, used, 8233u32)
            continue
        } else {
        if e == 34u8 || e == 92u8 || e == 47u8 || e == 32u8 { out[used] = e } else {
        if e == 120u8 || e == 117u8 || e == 85u8 {
            var width = 2usize
            if e == 117u8 { width = 4usize }
            if e == 85u8 { width = 8usize }
            if i + width > body.len { ret ("", Invalid) }
            var scalar = 0u32
            var k = 0usize
            while k < width {
                let (digit, is_hex) = hex_value(body[i + k])
                if !is_hex { ret ("", Invalid) }
                scalar = (scalar << 4u32) | digit
                k += 1usize
            }
            i += width
            if scalar > 1114111u32 || (scalar >= 55296u32 && scalar <= 57343u32) { ret ("", Invalid) }
            used = push_utf8(out, used, scalar)
            continue
        } else {
            ret ("", Invalid)
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        used += 1usize
    }
    ret (out[..used], ok)
}

// The single-quoted body, `''` folded to one quote.
fn unescape_single(a: *mem.Arena, body: str) -> (str, err) {
    let (pair, has_pair) = str.find(body, "''")
    if !has_pair { ret (body, ok) }
    let (out, out_error) = mem.alloc[u8](a, body.len)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var i = 0usize
    while i < body.len {
        out[used] = body[i]
        used += 1usize
        if body[i] == 39u8 && i + 1usize < body.len && body[i + 1usize] == 39u8 { i += 1usize }
        i += 1usize
    }
    ret (out[..used], ok)
}

// Where a scalar starting at `at` ends inside flow context: at an unquoted `,`, `]`,
// `}` or `: `; (end, error).
fn scalar_end(text: str, at: usize, in_flow: bool) -> (usize, err) {
    if at < text.len && (text[at] == 34u8 || text[at] == 39u8) {
        let quote = text[at]
        var i = at + 1usize
        while i < text.len {
            if text[i] == 92u8 && quote == 34u8 {
                i += 2usize
                continue
            }
            if text[i] == quote {
                if quote == 39u8 && i + 1usize < text.len && text[i + 1usize] == 39u8 {
                    i += 2usize
                    continue
                }
                ret (i + 1usize, ok)
            }
            i += 1usize
        }
        ret (0usize, Invalid)
    }
    var i = at
    while i < text.len {
        let c = text[i]
        if in_flow && (c == 44u8 || c == 93u8 || c == 125u8) { break }
        if c == 58u8 && (i + 1usize == text.len || is_inline_space(text[i + 1usize])) { break }
        i += 1usize
    }
    ret (i, ok)
}

fn scalar_value(p: *Parser, text: str) -> (Value, err) {
    let a = p.a
    let trimmed = str.trim(text)
    if p.rmode && trimmed.len > 0usize && (trimmed[0] == 38u8 || trimmed[0] == 42u8 || trimmed[0] == 33u8) {
        let (v, e) = r_property_scalar(p, trimmed)
        ret (v, e)
    }
    if trimmed.len >= 2usize && trimmed[0] == 34u8 && trimmed[trimmed.len - 1usize] == 34u8 {
        let (decoded, decode_error) = unescape_double(a, trimmed[1usize..trimmed.len - 1usize])
        if decode_error != ok { ret (zero, decode_error) }
        ret (Value{ String: decoded }, ok)
    }
    if trimmed.len >= 2usize && trimmed[0] == 39u8 && trimmed[trimmed.len - 1usize] == 39u8 {
        let (decoded, decode_error) = unescape_single(a, trimmed[1usize..trimmed.len - 1usize])
        if decode_error != ok { ret (zero, decode_error) }
        ret (Value{ String: decoded }, ok)
    }
    if trimmed.len > 0usize && (trimmed[0] == 38u8 || trimmed[0] == 42u8 || trimmed[0] == 33u8 || trimmed[0] == 37u8) { ret (zero, Unsupported) }
    if trimmed.len > 0usize && (trimmed[0] == 34u8 || trimmed[0] == 39u8) { ret (zero, Invalid) }
    if p.rmode {
        let (resolved, resolve_error) = r_resolve(a, trimmed)
        ret (resolved, resolve_error)
    }
    let (resolved, resolve_error) = resolve_plain(a, trimmed)
    ret (resolved, resolve_error)
}

// --- R's yaml package (libyaml with Syck's implicit tags): `parse_r`.
// Plain scalars take the implicit tag the package's re2c scanner gives them; the loader then
// converts by tag as handle_scalar does: strtol for `int` (a comma, an overflow or INT_MIN is NA),
// strtod for `float` (overflow is NA), sexagesimal and timestamps stay strings. `!!tag`s convert
// explicitly, an unknown tag leaves the text, `&anchor`/`*alias` copy the first definition of a
// name, `<<` merges in order (an earlier key wins, two explicit equal keys are DuplicateKey), keys
// become strings, and a sequence of one primitive type is simplified the way coerceVector does.

const T_NULL: u8 = 0u8
const T_YES: u8 = 1u8
const T_NO: u8 = 2u8
const T_MERGE: u8 = 3u8
const T_BNA: u8 = 4u8
const T_INT: u8 = 5u8
const T_HEX: u8 = 6u8
const T_OCT: u8 = 7u8
const T_FLOAT: u8 = 8u8
const T_INF: u8 = 9u8
const T_NEGINF: u8 = 10u8
const T_NAN: u8 = 11u8
const T_FNA: u8 = 12u8
const T_INA: u8 = 13u8
const T_SNA: u8 = 14u8
const T_STR: u8 = 15u8
// A type the loader leaves as a string (sexagesimal, timestamp) but the writer still quotes.
const T_OTHER: u8 = 16u8

fn r_digits(t: str, at: usize, count: usize) -> bool {
    if at + count > t.len { ret false }
    var i = 0usize
    while i < count {
        if !str.is_ascii_digit(t[at + i]) { ret false }
        i += 1usize
    }
    ret true
}

// int#base60 and float#base60: digits (and commas) then one or more `:` groups of 1-2 digits, the
// first of two at most 5, and for the float a point and digits.
fn r_base60(body: str) -> bool {
    if body.len == 0usize || !str.is_ascii_digit(body[0]) { ret false }
    var i = r_span(body, 1usize, 0u8)
    var groups = 0usize
    while i < body.len && body[i] == 58u8 {
        if i + 1usize >= body.len || !str.is_ascii_digit(body[i + 1usize]) { ret false }
        if i + 2usize < body.len && str.is_ascii_digit(body[i + 2usize]) {
            if body[i + 1usize] > 53u8 { ret false }
            i += 3usize
        } else {
            i += 2usize
        }
        groups += 1usize
    }
    if groups == 0usize { ret false }
    if i == body.len { ret true }
    ret body[i] == 46u8 && r_span(body, i + 1usize, 3u8) == body.len
}

// A time hh:mm:ss with an optional fraction; the index after it, or 0.
fn r_time_end(t: str, at: usize) -> usize {
    if !r_digits(t, at, 2usize) || at + 2usize >= t.len || t[at + 2usize] != 58u8 { ret 0usize }
    if !r_digits(t, at + 3usize, 2usize) || at + 5usize >= t.len || t[at + 5usize] != 58u8 { ret 0usize }
    if !r_digits(t, at + 6usize, 2usize) { ret 0usize }
    var i = at + 8usize
    if i < t.len && t[i] == 46u8 { i = r_span(t, i + 1usize, 3u8) }
    ret i
}

fn r_zone_ok(t: str, at: usize) -> bool {
    if at >= t.len { ret false }
    if t[at] == 90u8 { ret at + 1usize == t.len }
    if t[at] != 43u8 && t[at] != 45u8 { ret false }
    if !r_digits(t, at + 1usize, 2usize) { ret false }
    if at + 3usize == t.len { ret true }
    ret t[at + 3usize] == 58u8 && r_digits(t, at + 4usize, 2usize) && at + 6usize == t.len
}

// timestamp#ymd, #iso8601 and #spaced as the package's scanner takes them.
fn r_timestamp(t: str) -> bool {
    if t.len < 10usize || !r_digits(t, 0usize, 4usize) || t[4] != 45u8 || !r_digits(t, 5usize, 2usize) || t[7] != 45u8 || !r_digits(t, 8usize, 2usize) { ret false }
    if t.len == 10usize { ret true }
    var i = 10usize
    if t[i] == 84u8 || t[i] == 116u8 {
        let end = r_time_end(t, i + 1usize)
        if end == 0usize { ret false }
        ret r_zone_ok(t, end)
    }
    if t[i] != 32u8 { ret false }
    while i < t.len && t[i] == 32u8 { i += 1usize }
    let end = r_time_end(t, i)
    if end == 0usize || end >= t.len || t[end] != 32u8 { ret false }
    i = end
    while i < t.len && t[i] == 32u8 { i += 1usize }
    ret r_zone_ok(t, i)
}

fn r_is_yes(t: str) -> bool {
    ret str.eq(t, "y") || str.eq(t, "Y") || str.eq(t, "yes") || str.eq(t, "Yes") || str.eq(t, "YES") || str.eq(t, "true") || str.eq(t, "True") || str.eq(t, "TRUE") || str.eq(t, "on") || str.eq(t, "On") || str.eq(t, "ON")
}

fn r_is_no(t: str) -> bool {
    ret str.eq(t, "n") || str.eq(t, "N") || str.eq(t, "no") || str.eq(t, "No") || str.eq(t, "NO") || str.eq(t, "false") || str.eq(t, "False") || str.eq(t, "FALSE") || str.eq(t, "off") || str.eq(t, "Off") || str.eq(t, "OFF")
}

// The end of the run of digits from `from`; kind 0 is [0-9,], 1 is [0-7,], 2 is [0-9a-fA-F,], 3 is [0-9].
fn r_span(t: str, from: usize, kind: u8) -> usize {
    var i = from
    while i < t.len {
        let c = t[i]
        var member = str.is_ascii_digit(c)
        if kind == 0u8 && c == 44u8 { member = true }
        if kind == 1u8 { member = (c >= 48u8 && c <= 55u8) || c == 44u8 }
        if kind == 2u8 { member = str.is_ascii_digit(c) || (c >= 97u8 && c <= 102u8) || (c >= 65u8 && c <= 70u8) || c == 44u8 }
        if !member { break }
        i += 1usize
    }
    ret i
}

fn r_tag(t: str) -> u8 {
    if t.len == 0usize || str.eq(t, "~") || str.eq(t, "null") || str.eq(t, "Null") || str.eq(t, "NULL") { ret T_NULL }
    if r_is_yes(t) { ret T_YES }
    if r_is_no(t) { ret T_NO }
    if str.eq(t, "<<") { ret T_MERGE }
    if str.eq(t, "=") { ret T_OTHER }
    if str.eq(t, ".na") { ret T_BNA }
    if str.eq(t, ".na.real") { ret T_FNA }
    if str.eq(t, ".na.integer") { ret T_INA }
    if str.eq(t, ".na.character") { ret T_SNA }
    var from = 0usize
    if t[0] == 43u8 || t[0] == 45u8 { from = 1usize }
    let body = t[from..]
    if body.len > 2usize && body[0] == 48u8 && body[1] == 120u8 && r_span(body, 2usize, 2u8) == body.len { ret T_HEX }
    if body.len > 1usize && body[0] == 48u8 && r_span(body, 1usize, 1u8) == body.len { ret T_OCT }
    if str.eq(body, "0") { ret T_INT }
    if body.len > 0usize && body[0] >= 49u8 && body[0] <= 57u8 && r_span(body, 1usize, 0u8) == body.len { ret T_INT }
    let whole = r_span(body, 0usize, 0u8)
    if whole < body.len && body[whole] == 46u8 {
        if r_span(body, whole + 1usize, 0u8) == body.len { ret T_FLOAT }
        let digits = r_span(body, whole + 1usize, 3u8)
        if digits + 2usize < body.len && (body[digits] == 101u8 || body[digits] == 69u8) && (body[digits + 1usize] == 43u8 || body[digits + 1usize] == 45u8) && r_span(body, digits + 2usize, 3u8) == body.len { ret T_FLOAT }
    }
    if r_base60(body) || r_timestamp(t) { ret T_OTHER }
    if str.eq(body, ".inf") || str.eq(body, ".Inf") || str.eq(body, ".INF") {
        if from == 1usize && t[0] == 45u8 { ret T_NEGINF }
        ret T_INF
    }
    if from == 0usize && (str.eq(body, ".nan") || str.eq(body, ".NaN") || str.eq(body, ".NAN")) { ret T_NAN }
    ret T_STR
}

fn r_infinity() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

fn r_na(kind: u8) -> Value { ret Value{ NA: kind } }

// strtol on a tagged int: digits in `radix` after the sign and, for hex, the 0x; past INT_MAX is NA.
fn r_int(t: str, tag: u8) -> Value {
    if str.contains(t, ",") { ret r_na(1u8) }
    var i = 0usize
    var negative = false
    if t[0] == 43u8 || t[0] == 45u8 {
        negative = t[0] == 45u8
        i = 1usize
    }
    var radix = 10u64
    if tag == T_HEX {
        radix = 16u64
        i += 2usize
    }
    if tag == T_OCT { radix = 8u64 }
    var acc = 0u64
    while i < t.len {
        let (digit, digit_ok) = hex_value(t[i])
        acc = acc * radix + u64(digit)
        if acc > 2147483647u64 { ret r_na(1u8) }
        i += 1usize
    }
    var n = i64(acc)
    if negative { n = 0i64 - n }
    ret Value{ Integer: n }
}

fn r_lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn r_word(t: str, word: str) -> bool {
    if t.len != word.len { ret false }
    var i = 0usize
    while i < t.len {
        if r_lower(t[i]) != word[i] { ret false }
        i += 1usize
    }
    ret true
}

// strtod on a decimal or inf/nan word; false when the whole text is not one or it overflows.
fn r_decimal(a: *mem.Arena, t: str) -> (f64, bool) {
    var i = 0usize
    var negative = false
    if t.len > 0usize && (t[0] == 43u8 || t[0] == 45u8) {
        negative = t[0] == 45u8
        i = 1usize
    }
    let from = i
    if r_word(t[from..], "inf") || r_word(t[from..], "infinity") {
        if negative { ret (0.0f64 - r_infinity(), true) }
        ret (r_infinity(), true)
    }
    if r_word(t[from..], "nan") { ret (mem.bitcast[f64](9221120237041090560u64), true) }
    var digits = 0usize
    while i < t.len && str.is_ascii_digit(t[i]) {
        i += 1usize
        digits += 1usize
    }
    var has_point = false
    var point_at = 0usize
    if i < t.len && t[i] == 46u8 {
        has_point = true
        point_at = i
        i += 1usize
        while i < t.len && str.is_ascii_digit(t[i]) {
            i += 1usize
            digits += 1usize
        }
    }
    if digits == 0usize { ret (0.0f64, false) }
    var exponent_at = t.len
    if i < t.len && (t[i] == 101u8 || t[i] == 69u8) {
        var j = i + 1usize
        if j < t.len && (t[j] == 43u8 || t[j] == 45u8) { j += 1usize }
        let start = j
        while j < t.len && str.is_ascii_digit(t[j]) { j += 1usize }
        if j == start { ret (0.0f64, false) }
        exponent_at = i
        i = j
    }
    if i != t.len { ret (0.0f64, false) }
    let (number, number_error) = parse_plain_float(a, t, from, has_point, point_at, exponent_at)
    if number_error != ok { ret (0.0f64, false) }
    if number == r_infinity() || number == 0.0f64 - r_infinity() { ret (0.0f64, false) }
    ret (number, true)
}

fn r_float(a: *mem.Arena, t: str) -> Value {
    if str.contains(t, ",") { ret r_na(2u8) }
    let (number, found) = r_decimal(a, t)
    if !found { ret r_na(2u8) }
    ret Value{ Float: number }
}

// A plain scalar by its implicit tag.
fn r_resolve(a: *mem.Arena, t: str) -> (Value, err) {
    let tag = r_tag(t)
    if tag == T_NULL { ret (.Null, ok) }
    if tag == T_YES { ret (Value{ Bool: true }, ok) }
    if tag == T_NO { ret (Value{ Bool: false }, ok) }
    if tag == T_MERGE { ret (Value{ String: "_yaml.merge_" }, ok) }
    if tag == T_BNA { ret (r_na(0u8), ok) }
    if tag == T_INA { ret (r_na(1u8), ok) }
    if tag == T_FNA { ret (r_na(2u8), ok) }
    if tag == T_SNA { ret (r_na(3u8), ok) }
    if tag == T_INT || tag == T_HEX || tag == T_OCT { ret (r_int(t, tag), ok) }
    if tag == T_FLOAT { ret (r_float(a, t), ok) }
    if tag == T_INF { ret (Value{ Float: r_infinity() }, ok) }
    if tag == T_NEGINF { ret (Value{ Float: 0.0f64 - r_infinity() }, ok) }
    if tag == T_NAN { ret (Value{ Float: mem.bitcast[f64](9221120237041090560u64) }, ok) }
    ret (Value{ String: t }, ok)
}

// `!!str` and `tag:yaml.org,2002:str` are `str`; `!local` is `local`.
fn r_tag_name(tag: str) -> str {
    if str.starts_with(tag, "tag:yaml.org,2002:") { ret tag[18usize..] }
    var i = 0usize
    while i < tag.len && tag[i] == 33u8 { i += 1usize }
    ret tag[i..]
}

// strtol base 10 over the whole text (empty reads as 0).
fn r_strtol(t: str) -> Value {
    if t.len == 0usize { ret Value{ Integer: 0i64 } }
    var i = 0usize
    var negative = false
    if t[0] == 43u8 || t[0] == 45u8 {
        negative = t[0] == 45u8
        i = 1usize
    }
    if i >= t.len { ret r_na(1u8) }
    var acc = 0u64
    while i < t.len {
        if !str.is_ascii_digit(t[i]) { ret r_na(1u8) }
        acc = acc * 10u64 + u64(t[i] - 48u8)
        if acc > 2147483647u64 { ret r_na(1u8) }
        i += 1usize
    }
    var n = i64(acc)
    if negative { n = 0i64 - n }
    ret Value{ Integer: n }
}

// A scalar under an explicit tag: the text converts by the tag, not by what it looks like.
fn r_tagged_scalar(a: *mem.Arena, name: str, t: str) -> (Value, err) {
    if str.eq(name, "seq") || str.eq(name, "omap") { ret (zero, InvalidTag) }
    if str.eq(name, "int") { ret (r_strtol(t), ok) }
    if str.eq(name, "float") {
        if t.len == 0usize { ret (Value{ Float: 0.0f64 }, ok) }
        // as.numeric reads hexadecimal too.
        var hex_from = 0usize
        if t[0] == 43u8 || t[0] == 45u8 { hex_from = 1usize }
        if t.len > hex_from + 2usize && t[hex_from] == 48u8 && (t[hex_from + 1usize] == 120u8 || t[hex_from + 1usize] == 88u8) {
            var hex_value_total = 0.0f64
            var hex_ok = true
            var k = hex_from + 2usize
            while k < t.len {
                let (digit, digit_ok) = hex_value(t[k])
                if !digit_ok { hex_ok = false }
                hex_value_total = hex_value_total * 16.0f64 + f64(digit)
                k += 1usize
            }
            if hex_ok {
                if hex_from == 1usize && t[0] == 45u8 { hex_value_total = 0.0f64 - hex_value_total }
                ret (Value{ Float: hex_value_total }, ok)
            }
        }
        let (number, found) = r_decimal(a, t)
        if !found { ret (r_na(2u8), ok) }
        ret (Value{ Float: number }, ok)
    }
    if str.eq(name, "bool") {
        let tag = r_tag(t)
        if tag == T_YES { ret (Value{ Bool: true }, ok) }
        if tag == T_NO { ret (Value{ Bool: false }, ok) }
        ret (r_na(0u8), ok)
    }
    if str.eq(name, "null") { ret (.Null, ok) }
    if str.eq(name, "merge") { ret (Value{ String: "_yaml.merge_" }, ok) }
    ret (Value{ String: t }, ok)
}

fn r_collection_tag_fails(name: str, is_seq: bool) -> bool {
    if str.eq(name, "str") || str.eq(name, "int") || str.starts_with(name, "int#") || str.eq(name, "float") || str.eq(name, "float#fix") || str.eq(name, "float#exp") { ret true }
    if str.eq(name, "bool#yes") || str.eq(name, "bool#no") || str.eq(name, "bool#na") || str.eq(name, "merge") || str.eq(name, "expr") { ret true }
    if str.eq(name, "float#na") || str.eq(name, "float#nan") || str.eq(name, "float#inf") || str.eq(name, "float#neginf") || str.eq(name, "str#na") { ret true }
    if str.eq(name, "omap") { ret true }
    if str.eq(name, "seq") && !is_seq { ret true }
    ret false
}

// A tag on a value that is already built: a collection keeps itself or becomes null; a scalar
// converts from its text.
fn r_apply_tag(p: *Parser, v: Value, name: str) -> (Value, err) {
    switch v {
    case .Sequence as items:
        if str.eq(name, "null") { ret (.Null, ok) }
        if str.eq(name, "omap") {
            let (ordered, ordered_error) = r_omap(p, items)
            ret (ordered, ordered_error)
        }
        if r_collection_tag_fails(name, true) { ret (zero, InvalidTag) }
        ret (v, ok)
    case .Mapping as pairs:
        if str.eq(name, "null") { ret (.Null, ok) }
        if r_collection_tag_fails(name, false) { ret (zero, InvalidTag) }
        ret (v, ok)
    case .String as text:
        let (tagged, tagged_error) = r_tagged_scalar(p.a, name, text)
        ret (tagged, tagged_error)
    default:
        let (tagged, tagged_error) = r_tagged_scalar(p.a, name, "")
        ret (tagged, tagged_error)
    }
}

// `&anchor` and `!tag` words before a node; the anchor name, the tag as written, the rest.
fn r_split_props(text: str) -> (str, str, str) {
    var anchor = ""
    var tag = ""
    var i = 0usize
    while true {
        while i < text.len && text[i] == 32u8 { i += 1usize }
        if i < text.len && (text[i] == 38u8 || text[i] == 33u8) {
            var j = i + 1usize
            while j < text.len && text[j] != 32u8 { j += 1usize }
            if text[i] == 38u8 { anchor = text[i + 1usize..j] } else { tag = text[i..j] }
            i = j
            continue
        }
        break
    }
    ret (anchor, tag, text[i..])
}

fn r_anchor_put(p: *Parser, name: str, v: Value) -> err {
    if name.len == 0usize { ret ok }
    if p.anchor_count == MAX_ANCHORS { ret TooLarge }
    p.anchor_names[p.anchor_count] = name
    p.anchor_values[p.anchor_count] = v
    p.anchor_count += 1usize
    ret ok
}

fn r_alias(p: *Parser, name: str) -> Value {
    var i = 0usize
    while i < p.anchor_count {
        if str.eq(p.anchor_names[i], name) { ret p.anchor_values[i] }
        i += 1usize
    }
    ret Value{ String: "_yaml.bad-anchor_" }
}

// `rest` (a plain or quoted scalar as written) read under an explicit tag.
fn r_tag_text(p: *Parser, tag: str, rest: str) -> (Value, err) {
    var text = rest
    if rest.len >= 2usize && rest[0] == 34u8 && rest[rest.len - 1usize] == 34u8 {
        let (decoded, decode_error) = unescape_double(p.a, rest[1usize..rest.len - 1usize])
        if decode_error != ok { ret (zero, decode_error) }
        text = decoded
    }
    if rest.len >= 2usize && rest[0] == 39u8 && rest[rest.len - 1usize] == 39u8 {
        let (decoded, decode_error) = unescape_single(p.a, rest[1usize..rest.len - 1usize])
        if decode_error != ok { ret (zero, decode_error) }
        text = decoded
    }
    let (tagged, tagged_error) = r_tagged_scalar(p.a, r_tag_name(tag), text)
    ret (tagged, tagged_error)
}

// Properties before a flow collection, a block scalar or nothing (a node on the lines below).
fn r_props_open(text: str) -> bool {
    let trimmed = str.trim(text)
    if trimmed.len == 0usize || (trimmed[0] != 38u8 && trimmed[0] != 33u8) { ret false }
    let (anchor, tag, after) = r_split_props(trimmed)
    ret after.len == 0usize || after[0] == 91u8 || after[0] == 123u8 || after[0] == 124u8 || after[0] == 62u8
}

// A block mapping's explicit key line: `?` alone or followed by blank.
fn r_question(text: str) -> bool {
    ret text.len > 0usize && text[0] == 63u8 && (text.len == 1usize || is_inline_space(text[1]))
}

// `!!omap` on a sequence of mappings: the one ordered mapping they make together.
fn r_omap(p: *Parser, items: []const Value) -> (Value, err) {
    var pairs: [256]Pair = zero
    var merged: [256]bool = zero
    var count = 0usize
    var i = 0usize
    while i < items.len {
        switch items[i] {
        case .Mapping as entries:
            var k = 0usize
            while k < entries.len {
                let (next, put_error) = r_put(pairs[..256usize], merged[..256usize], count, r_key_of(entries[k].key), entries[k].value, false)
                if put_error != ok { ret (zero, put_error) }
                count = next
                k += 1usize
            }
        default:
            ret (zero, InvalidTag)
        }
        i += 1usize
    }
    let (copy, copy_error) = mem.alloc[Pair](p.a, count)
    if copy_error != ok { ret (zero, copy_error) }
    mem.copy[Pair](copy, pairs[..count])
    ret (Value{ Mapping: copy[0..] }, ok)
}

// A scalar token that starts with `*`, `&` or `!`.
fn r_property_scalar(p: *Parser, trimmed: str) -> (Value, err) {
    if trimmed[0] == 42u8 { ret (r_alias(p, trimmed[1usize..]), ok) }
    let (anchor, tag, rest) = r_split_props(trimmed)
    // Properties on an alias, or an empty `!!` tag, are libyaml errors.
    if rest.len > 0usize && rest[0] == 42u8 { ret (zero, Invalid) }
    if str.eq(tag, "!!") { ret (zero, Invalid) }
    var value: Value = zero
    if tag.len > 0usize && !str.eq(tag, "!") {
        let (tagged, tagged_error) = r_tag_text(p, tag, rest)
        if tagged_error != ok { ret (zero, tagged_error) }
        value = tagged
    } else {
        let (plain, plain_error) = scalar_value(p, rest)
        if plain_error != ok { ret (zero, plain_error) }
        value = plain
    }
    let put_error = r_anchor_put(p, anchor, value)
    if put_error != ok { ret (zero, put_error) }
    ret (value, ok)
}

fn r_kind(v: Value) -> u8 {
    switch v {
    case .Bool as flag:
        ret 0u8
    case .Integer as n:
        ret 1u8
    case .Float as x:
        ret 2u8
    case .String as s:
        ret 3u8
    case .NA as k:
        ret k
    default:
        ret 4u8
    }
}

// coerceVector's rule: items all of one primitive type are a vector, and a vector of one is the
// item itself; anything else stays a list.
fn r_simplify(p: *Parser, items: []const Value) -> Value {
    if items.len == 0usize { ret Value{ Sequence: items } }
    let kind = r_kind(items[0])
    var i = 1usize
    while i < items.len {
        if r_kind(items[i]) != kind { ret Value{ Sequence: items } }
        i += 1usize
    }
    if kind > 3u8 { ret Value{ Sequence: items } }
    if items.len == 1usize {
        p.collapsed = true
        ret items[0]
    }
    ret Value{ Sequence: items }
}

// A mapping key as as.character gives it.
fn r_key_text(a: *mem.Arena, v: Value) -> (str, err) {
    switch v {
    case .String as s:
        ret (s, ok)
    case .Integer as n:
        let (b0, builder_error) = str.builder(a, 24usize)
        if builder_error != ok { ret ("", builder_error) }
        var b = b0
        let push_error = str.push_i64(&b, n)
        if push_error != ok { ret ("", push_error) }
        ret (str.done(&b), ok)
    case .Bool as flag:
        if flag { ret ("TRUE", ok) }
        ret ("FALSE", ok)
    case .Null:
        ret ("", ok)
    case .NA as k:
        ret ("NA", ok)
    case .Float as x:
        let (b0, builder_error) = str.builder(a, 32usize)
        if builder_error != ok { ret ("", builder_error) }
        var b = b0
        let push_error = str.push_f64(&b, x)
        if push_error != ok { ret ("", push_error) }
        ret (str.done(&b), ok)
    default:
        ret ("", Invalid)
    }
}

fn r_key_of(v: Value) -> str {
    switch v {
    case .String as s:
        ret s
    default:
        ret ""
    }
}

// One entry of a map being built; `merged[i]` marks entries that came from a `<<`.
fn r_put(pairs: []Pair, merged: []bool, count: usize, key: str, value: Value, from_merge: bool) -> (usize, err) {
    var i = 0usize
    while i < count {
        if str.eq(r_key_of(pairs[i].key), key) {
            if from_merge || merged[i] { ret (count, ok) }
            ret (count, DuplicateKey)
        }
        i += 1usize
    }
    if count == pairs.len { ret (count, TooLarge) }
    pairs[count] = Pair { key: Value{ String: key }, value: value }
    merged[count] = from_merge
    ret (count + 1usize, ok)
}

fn r_merge(pairs: []Pair, merged: []bool, count_in: usize, v: Value) -> (usize, err) {
    var count = count_in
    switch v {
    case .Mapping as entries:
        var i = 0usize
        while i < entries.len {
            let (next, put_error) = r_put(pairs, merged, count, r_key_of(entries[i].key), entries[i].value, true)
            if put_error != ok { ret (count, put_error) }
            count = next
            i += 1usize
        }
        ret (count, ok)
    case .Sequence as items:
        var j = 0usize
        while j < items.len {
            switch items[j] {
            case .Mapping as entries:
                var i = 0usize
                while i < entries.len {
                    let (next, put_error) = r_put(pairs, merged, count, r_key_of(entries[i].key), entries[i].value, true)
                    if put_error != ok { ret (count, put_error) }
                    count = next
                    i += 1usize
                }
            default:
                ret (count, Invalid)
            }
            j += 1usize
        }
        ret (count, ok)
    default:
        ret (count, Invalid)
    }
}

// --- Flow collections, on one line.

fn flow_value(p: *Parser, text: str, at_in: usize, depth: usize) -> (Value, usize, err) {
    var at = at_in
    while at < text.len && is_inline_space(text[at]) { at += 1usize }
    if at >= text.len { ret (zero, at, Invalid) }
    if text[at] == 91u8 {
        if depth >= usize(p.options.max_depth) { ret (zero, at, TooDeep) }
        var items: [64]Value = zero
        var count = 0usize
        at += 1usize
        while true {
            while at < text.len && is_inline_space(text[at]) { at += 1usize }
            if at >= text.len { ret (zero, at, Invalid) }
            if text[at] == 93u8 {
                at += 1usize
                break
            }
            if count == 64usize { ret (zero, at, TooLarge) }
            let (item, after, item_error) = flow_value(p, text, at, depth + 1usize)
            if item_error != ok { ret (zero, at, item_error) }
            items[count] = item
            count += 1usize
            at = after
            while at < text.len && is_inline_space(text[at]) { at += 1usize }
            if at < text.len && text[at] == 44u8 { at += 1usize }
        }
        let (copy, copy_error) = mem.alloc[Value](p.a, count)
        if copy_error != ok { ret (zero, at, copy_error) }
        mem.copy[Value](copy, items[..count])
        if p.rmode { ret (r_simplify(p, copy[0..]), at, ok) }
        ret (Value{ Sequence: copy[0..] }, at, ok)
    }
    if text[at] == 123u8 {
        if depth >= usize(p.options.max_depth) { ret (zero, at, TooDeep) }
        var pairs: [64]Pair = zero
        var merged: [64]bool = zero
        var count = 0usize
        at += 1usize
        while true {
            while at < text.len && is_inline_space(text[at]) { at += 1usize }
            if at >= text.len { ret (zero, at, Invalid) }
            if text[at] == 125u8 {
                at += 1usize
                break
            }
            if count == 64usize { ret (zero, at, TooLarge) }
            let key_start = at
            let (key, after_key, key_error) = flow_value(p, text, at, depth + 1usize)
            if key_error != ok { ret (zero, at, key_error) }
            at = after_key
            let raw_key = str.trim(text[key_start..after_key])
            while at < text.len && is_inline_space(text[at]) { at += 1usize }
            var value: Value = .Null
            if at < text.len && text[at] == 58u8 {
                at += 1usize
                while at < text.len && is_inline_space(text[at]) { at += 1usize }
                if at < text.len && text[at] != 44u8 && text[at] != 125u8 {
                    let (parsed, after_value, value_error) = flow_value(p, text, at, depth + 1usize)
                    if value_error != ok { ret (zero, at, value_error) }
                    value = parsed
                    at = after_value
                }
            }
            if p.rmode {
                var next = count
                var put_error: err = ok
                if str.eq(raw_key, "<<") {
                    let (merged_count, merge_error) = r_merge(pairs[..64usize], merged[..64usize], count, value)
                    next = merged_count
                    put_error = merge_error
                } else {
                    let (key_name, name_error) = r_key_text(p.a, key)
                    if name_error != ok { ret (zero, at, name_error) }
                    let (put_count, entry_error) = r_put(pairs[..64usize], merged[..64usize], count, key_name, value, false)
                    next = put_count
                    put_error = entry_error
                }
                if put_error != ok { ret (zero, at, put_error) }
                count = next
                while at < text.len && is_inline_space(text[at]) { at += 1usize }
                if at < text.len && text[at] == 44u8 { at += 1usize }
                continue
            }
            if !p.options.allow_duplicate_keys && has_key(pairs[..count], key) { ret (zero, at, DuplicateKey) }
            pairs[count] = Pair { key: key, value: value }
            count += 1usize
            while at < text.len && is_inline_space(text[at]) { at += 1usize }
            if at < text.len && text[at] == 44u8 { at += 1usize }
        }
        let (copy, copy_error) = mem.alloc[Pair](p.a, count)
        if copy_error != ok { ret (zero, at, copy_error) }
        mem.copy[Pair](copy, pairs[..count])
        ret (Value{ Mapping: copy[0..] }, at, ok)
    }
    let (stop, stop_error) = scalar_end(text, at, true)
    if stop_error != ok { ret (zero, at, stop_error) }
    let (scalar, scalar_error) = scalar_value(p, text[at..stop])
    if scalar_error != ok { ret (zero, at, scalar_error) }
    ret (scalar, stop, ok)
}

fn same_key(a: Value, b: Value) -> bool {
    switch a {
    case .String as x:
        switch b {
        case .String as y:
            ret str.eq(x, y)
        default:
            ret false
        }
    case .Integer as x:
        switch b {
        case .Integer as y:
            ret x == y
        default:
            ret false
        }
    case .Bool as x:
        switch b {
        case .Bool as y:
            ret x == y
        default:
            ret false
        }
    case .Float as x:
        switch b {
        case .Float as y:
            ret x == y || (x != x && y != y)
        default:
            ret false
        }
    case .Null:
        switch b {
        case .Null:
            ret true
        default:
            ret false
        }
    case .Sequence as x:
        switch b {
        case .Sequence as y:
            if x.len != y.len { ret false }
            var i = 0usize
            while i < x.len {
                if !same_key(x[i], y[i]) { ret false }
                i += 1usize
            }
            ret true
        default:
            ret false
        }
    case .Mapping as x:
        switch b {
        case .Mapping as y:
            if x.len != y.len { ret false }
            var i = 0usize
            while i < x.len {
                var matched = false
                var j = 0usize
                while j < y.len {
                    if same_key(x[i].key, y[j].key) && same_key(x[i].value, y[j].value) {
                        matched = true
                        break
                    }
                    j += 1usize
                }
                if !matched { ret false }
                i += 1usize
            }
            ret true
        default:
            ret false
        }
    default:
        ret false
    }
}

fn has_key(pairs: []const Pair, key: Value) -> bool {
    var i = 0usize
    while i < pairs.len {
        if same_key(pairs[i].key, key) { ret true }
        i += 1usize
    }
    ret false
}

// --- Block structure.

fn has_indent_tab(line: Line) -> bool {
    ret line.indent < line.raw.len && line.raw[line.indent] == 9u8
}

fn has_indented_continuation(p: *Parser, parent_indent: usize) -> bool {
    var probe = p.at
    while probe < p.lines.len && is_blank(p.lines[probe].text) { probe += 1usize }
    ret probe < p.lines.len && p.lines[probe].indent > parent_indent
}

// Skips blank lines; false at the end.
fn skip_blank(p: *Parser) -> bool {
    while p.at < p.lines.len && is_blank(p.lines[p.at].text) { p.at += 1usize }
    ret p.at < p.lines.len
}

// A value that begins on this line after `prefix` columns: inline, or on the lines
// below when the rest of the line is empty or a block scalar indicator.
fn parse_inline_or_below(p: *Parser, rest: str, parent_indent: usize, depth: usize) -> (Value, err) {
    let item_context = p.in_item
    p.in_item = false
    let trimmed = str.trim(rest)
    if p.rmode && trimmed.len > 0usize && (trimmed[0] == 38u8 || trimmed[0] == 33u8) {
        let (anchor, tag, after) = r_split_props(trimmed)
        if str.eq(tag, "!!") { ret (zero, Invalid) }
        if tag.len > 0usize && !str.eq(tag, "!") && after.len == 0usize {
            // A scalar on the line below takes the tag by its text.
            var j = p.at + 1usize
            while j < p.lines.len && is_blank(p.lines[j].text) { j += 1usize }
            if j < p.lines.len && p.lines[j].indent > parent_indent {
                let below = str.trim(p.lines[j].text)
                let (below_colon, below_key) = key_end(below)
                let below_item = below[0] == 45u8 && (below.len == 1usize || is_inline_space(below[1]))
                let below_node = below[0] == 91u8 || below[0] == 123u8 || below[0] == 124u8 || below[0] == 62u8 || below[0] == 38u8 || below[0] == 33u8 || below[0] == 42u8 || below[0] == 63u8
                if !below_key && !below_item && !below_node {
                    p.at = j + 1usize
                    let (tagged, tagged_error) = r_tag_text(p, tag, below)
                    if tagged_error != ok { ret (zero, tagged_error) }
                    let put_error = r_anchor_put(p, anchor, tagged)
                    if put_error != ok { ret (zero, put_error) }
                    ret (tagged, ok)
                }
            }
        }
        if after.len == 0usize || after[0] == 91u8 || after[0] == 123u8 || after[0] == 124u8 || after[0] == 62u8 {
            p.collapsed = false
            p.in_item = item_context
            let (inner, inner_error) = parse_inline_or_below(p, after, parent_indent, depth)
            if inner_error != ok { ret (zero, inner_error) }
            var value = inner
            if tag.len > 0usize && !str.eq(tag, "!") {
                var wrap = false
                switch inner {
                case .Sequence as items:
                    wrap = false
                case .Mapping as pairs:
                    wrap = false
                default:
                    wrap = p.collapsed
                }
                if wrap {
                    // A one-item list the default tag would have reduced to its item: another tag keeps the list.
                    let (items, items_error) = mem.alloc[Value](p.a, 1usize)
                    if items_error != ok { ret (zero, items_error) }
                    items[0] = inner
                    let (tagged, tagged_error) = r_apply_tag(p, Value{ Sequence: items[0..] }, r_tag_name(tag))
                    if tagged_error != ok { ret (zero, tagged_error) }
                    value = tagged
                    if str.eq(r_tag_name(tag), "seq") { value = inner }
                } else {
                    let (tagged, tagged_error) = r_apply_tag(p, inner, r_tag_name(tag))
                    if tagged_error != ok { ret (zero, tagged_error) }
                    value = tagged
                }
            }
            let put_error = r_anchor_put(p, anchor, value)
            if put_error != ok { ret (zero, put_error) }
            ret (value, ok)
        }
    }
    if trimmed.len > 0usize && (trimmed[0] == 124u8 || trimmed[0] == 62u8) {
        p.at += 1usize
        let (block, block_error) = parse_block_scalar(p, trimmed, parent_indent)
        ret (block, block_error)
    }
    if trimmed.len > 0usize {
        p.at += 1usize
        if trimmed[0] == 91u8 || trimmed[0] == 123u8 {
            let (flow, after, flow_error) = flow_value(p, trimmed, 0usize, depth)
            if flow_error != ok { ret (zero, flow_error) }
            if after != trimmed.len { ret (zero, Invalid) }
            ret (flow, ok)
        }
        let (scalar, scalar_error) = scalar_value(p, trimmed)
        if scalar_error == Invalid && (trimmed[0] == 34u8 || trimmed[0] == 39u8) && has_indented_continuation(p, parent_indent) {
            ret (zero, Unsupported)
        }
        if scalar_error == ok && has_indented_continuation(p, parent_indent) { ret (zero, Unsupported) }
        ret (scalar, scalar_error)
    }
    p.at += 1usize
    if !skip_blank(p) { ret (.Null, ok) }
    if p.lines[p.at].indent > parent_indent {
        let (nested, nested_error) = parse_node(p, p.lines[p.at].indent, depth + 1usize)
        ret (nested, nested_error)
    }
    // A sequence may sit at the parent's own indent under a mapping key.
    if !item_context && p.lines[p.at].indent == parent_indent && str.starts_with(p.lines[p.at].text, "-") {
        let (nested, nested_error) = parse_node(p, parent_indent, depth + 1usize)
        ret (nested, nested_error)
    }
    ret (.Null, ok)
}

// A literal or folded block: the lines indented past the parent, joined by newlines
// or spaces, chomped as the indicator says.
fn parse_block_scalar(p: *Parser, indicator: str, parent_indent: usize) -> (Value, err) {
    let folded = indicator[0] == 62u8
    var chomp = 0u8
    if indicator.len > 1usize && indicator[1] == 45u8 { chomp = 1u8 }
    if indicator.len > 1usize && indicator[1] == 43u8 { chomp = 2u8 }
    if indicator.len > 2usize || (indicator.len == 2usize && chomp == 0u8) { ret (zero, Invalid) }
    var block_indent = 0usize
    var probe = p.at
    while probe < p.lines.len && is_blank(p.lines[probe].raw) { probe += 1usize }
    if probe < p.lines.len && p.lines[probe].indent > parent_indent { block_indent = p.lines[probe].indent }
    var total = 0usize
    var stop = p.at
    while stop < p.lines.len && (is_blank(p.lines[stop].raw) || p.lines[stop].indent >= block_indent) {
        if block_indent == 0usize && !is_blank(p.lines[stop].raw) { break }
        total += p.lines[stop].raw.len + 1usize
        stop += 1usize
    }
    let (out, out_error) = mem.alloc[u8](p.a, total + 1usize)
    if out_error != ok { ret (zero, out_error) }
    var used = 0usize
    var trailing = 0usize
    var i = p.at
    while i < stop {
        let raw = p.lines[i].raw
        if is_blank(raw) {
            // Folded: the break before the first empty line is the newline it becomes.
            if folded && trailing == 0usize && used > 0usize {
                trailing = 1usize
            } else {
                out[used] = 10u8
                used += 1usize
                trailing += 1usize
            }
        } else {
            let body = raw[block_indent..]
            if folded && trailing == 0usize && used > 0usize && out[used - 1usize] == 10u8 && body.len > 0usize && body[0] != 32u8 {
                out[used - 1usize] = 32u8
            }
            mem.copy[u8](out[used..used + body.len], body)
            used += body.len
            out[used] = 10u8
            used += 1usize
            trailing = 0usize
        }
        i += 1usize
    }
    p.at = stop
    if used == 0usize { ret (Value{ String: "" }, ok) }
    // Chomping: strip keeps no final break, clip one, keep all.
    var stop_at = used
    if chomp != 2u8 {
        while stop_at > 0usize && out[stop_at - 1usize] == 10u8 { stop_at -= 1usize }
        if chomp == 0u8 && stop_at < used { stop_at += 1usize }
    }
    ret (Value{ String: out[..stop_at] }, ok)
}

fn parse_node(p: *Parser, indent: usize, depth: usize) -> (Value, err) {
    if depth > usize(p.options.max_depth) { ret (zero, TooDeep) }
    if !skip_blank(p) { ret (.Null, ok) }
    let first = p.lines[p.at]
    if has_indent_tab(first) { ret (zero, Invalid) }
    if first.indent != indent { ret (zero, Invalid) }
    if first.text.len > 0usize && first.text[0] == 45u8 && (first.text.len == 1usize || is_inline_space(first.text[1])) {
        // A sequence at this indent.
        var items: [256]Value = zero
        var count = 0usize
        while skip_blank(p) && p.lines[p.at].indent == indent && p.lines[p.at].text.len > 0usize && p.lines[p.at].text[0] == 45u8 && (p.lines[p.at].text.len == 1usize || is_inline_space(p.lines[p.at].text[1])) {
            if has_indent_tab(p.lines[p.at]) { ret (zero, Invalid) }
            if count == 256usize { ret (zero, TooLarge) }
            let text = p.lines[p.at].text
            var rest = ""
            if text.len > 1usize { rest = text[2usize..] }
            let trimmed = str.trim(rest)
            let nested_sequence = trimmed.len > 0usize && trimmed[0] == 45u8 && (trimmed.len == 1usize || is_inline_space(trimmed[1]))
            if trimmed.len > 0usize && trimmed[0] != 91u8 && trimmed[0] != 123u8 && trimmed[0] != 124u8 && trimmed[0] != 62u8 {
                let (colon, found_colon) = key_end(trimmed)
                var has_colon = found_colon
                if p.rmode && r_props_open(trimmed) { has_colon = false }
                if has_colon || nested_sequence {
                    // The item is a mapping or sequence whose first entry sits on this line.
                    let shifted = indent + 2usize + (text.len - 2usize - str.trim_start(rest).len)
                    p.lines[p.at] = Line { indent: shifted, text: str.trim_start(rest), raw: p.lines[p.at].raw }
                    let (item, item_error) = parse_node(p, shifted, depth + 1usize)
                    if item_error != ok { ret (zero, item_error) }
                    items[count] = item
                    count += 1usize
                    continue
                }
            }
            p.in_item = true
            let (item, item_error) = parse_inline_or_below(p, rest, indent, depth)
            if item_error != ok { ret (zero, item_error) }
            items[count] = item
            count += 1usize
        }
        let (copy, copy_error) = mem.alloc[Value](p.a, count)
        if copy_error != ok { ret (zero, copy_error) }
        mem.copy[Value](copy, items[..count])
        if p.rmode { ret (r_simplify(p, copy[0..]), ok) }
        ret (Value{ Sequence: copy[0..] }, ok)
    }
    let (colon, found_colon) = key_end(first.text)
    var has_colon = found_colon
    if p.rmode && r_props_open(first.text) { has_colon = false }
    if p.rmode && r_question(first.text) { has_colon = true }
    if has_colon {
        var pairs: [256]Pair = zero
        var merged: [256]bool = zero
        var count = 0usize
        while skip_blank(p) && p.lines[p.at].indent == indent {
            if has_indent_tab(p.lines[p.at]) { ret (zero, Invalid) }
            let text = p.lines[p.at].text
            var key_stop = 0usize
            var key: Value = zero
            var value: Value = zero
            if p.rmode && r_question(text) {
                // `? key` and an optional `: value` line at the same indent (scalar keys only).
                if count == 256usize { ret (zero, TooLarge) }
                key_stop = text.len
                let (explicit, explicit_error) = scalar_value(p, str.trim(text[1usize..]))
                if explicit_error != ok { ret (zero, explicit_error) }
                key = explicit
                p.at += 1usize
                if skip_blank(p) && p.lines[p.at].indent == indent && p.lines[p.at].text.len > 0usize && p.lines[p.at].text[0] == 58u8 && (p.lines[p.at].text.len == 1usize || is_inline_space(p.lines[p.at].text[1])) {
                    let value_text = p.lines[p.at].text
                    var value_rest = ""
                    if value_text.len > 1usize { value_rest = value_text[1usize..] }
                    let (explicit_value, explicit_value_error) = parse_inline_or_below(p, value_rest, indent, depth)
                    if explicit_value_error != ok { ret (zero, explicit_value_error) }
                    value = explicit_value
                }
            } else {
                let (stop, is_entry) = key_end(text)
                if !is_entry { ret (zero, Invalid) }
                if count == 256usize { ret (zero, TooLarge) }
                key_stop = stop
                let (plain_key, key_error) = scalar_value(p, text[..key_stop])
                if key_error != ok { ret (zero, key_error) }
                key = plain_key
                var rest = ""
                if key_stop + 1usize < text.len { rest = text[key_stop + 1usize..] }
                let (plain_value, value_error) = parse_inline_or_below(p, rest, indent, depth)
                if value_error != ok { ret (zero, value_error) }
                value = plain_value
            }
            if p.rmode {
                var next = count
                var put_error: err = ok
                if str.eq(str.trim(text[..key_stop]), "<<") {
                    let (merged_count, merge_error) = r_merge(pairs[..256usize], merged[..256usize], count, value)
                    next = merged_count
                    put_error = merge_error
                } else {
                    let (key_name, name_error) = r_key_text(p.a, key)
                    if name_error != ok { ret (zero, name_error) }
                    let (put_count, entry_error) = r_put(pairs[..256usize], merged[..256usize], count, key_name, value, false)
                    next = put_count
                    put_error = entry_error
                }
                if put_error != ok { ret (zero, put_error) }
                count = next
                continue
            }
            if !p.options.allow_duplicate_keys && has_key(pairs[..count], key) { ret (zero, DuplicateKey) }
            pairs[count] = Pair { key: key, value: value }
            count += 1usize
        }
        if p.at < p.lines.len && !is_blank(p.lines[p.at].text) && p.lines[p.at].indent > indent { ret (zero, Invalid) }
        let (copy, copy_error) = mem.alloc[Pair](p.a, count)
        if copy_error != ok { ret (zero, copy_error) }
        mem.copy[Pair](copy, pairs[..count])
        ret (Value{ Mapping: copy[0..] }, ok)
    }
    // A lone scalar or flow collection.
    let (value, value_error) = parse_inline_or_below(p, first.text, indent, depth)
    ret (value, value_error)
}

// The end of a mapping key on a line: the `:` that ends it, outside quotes and
// followed by inline separation or the end.
fn key_end(text: str) -> (usize, bool) {
    if text.len == 0usize { ret (0usize, false) }
    if text[0] == 91u8 || text[0] == 123u8 { ret (0usize, false) }
    let (stop, stop_error) = scalar_end(text, 0usize, false)
    if stop_error != ok { ret (0usize, false) }
    var i = stop
    while i < text.len && is_inline_space(text[i]) { i += 1usize }
    if i < text.len && text[i] == 58u8 && (i + 1usize == text.len || is_inline_space(text[i + 1usize])) { ret (i, true) }
    ret (0usize, false)
}

fn parse(a: *mem.Arena, source: str, options: Options) -> (Value, err) {
    let (v, e) = parse_with(a, source, options, false)
    ret (v, e)
}

// The document as R's `yaml.load` reads it; Unsupported is still the answer past the block/flow subset.
fn parse_r(a: *mem.Arena, source: str) -> (Value, err) {
    let (v, e) = parse_with(a, source, Options { max_depth: 0u16, allow_duplicate_keys: false }, true)
    ret (v, e)
}

fn parse_with(a: *mem.Arena, source: str, options: Options, rmode: bool) -> (Value, err) {
    if !utf8.validate(source) { ret (zero, Invalid) }
    if !valid_yaml_presentation(source) { ret (zero, Invalid) }
    let (lines, lines_error) = split_lines(a, source)
    if lines_error != ok { ret (zero, lines_error) }
    var effective = options
    if effective.max_depth == 0u16 || effective.max_depth > MAX_DEPTH { effective.max_depth = MAX_DEPTH }
    var p = Parser { a: a, lines: lines, at: 0usize, options: effective, rmode: rmode, anchor_names: zero, anchor_values: zero, anchor_count: 0usize, collapsed: false, in_item: false }
    // Directives and a second document are beyond the subset; one `---` is allowed.
    var i = 0usize
    var markers = 0usize
    while i < lines.len {
        let text = lines[i].text
        if lines[i].indent == 0usize {
            if text.len > 0usize && text[0] == 37u8 { ret (zero, Unsupported) }
            if str.eq(text, "---") || str.starts_with(text, "--- ") {
                markers += 1usize
                if markers > 1usize || i > 0usize && has_content(lines[..i]) { ret (zero, Unsupported) }
                lines[i] = Line { indent: 0usize, text: str.trim(text[3usize..]), raw: lines[i].raw }
            }
            if str.eq(text, "...") {
                var after = i + 1usize
                while after < lines.len {
                    if !is_blank(lines[after].text) { ret (zero, Unsupported) }
                    after += 1usize
                }
                lines[i] = Line { indent: 0usize, text: "", raw: lines[i].raw }
                break
            }
        }
        i += 1usize
    }
    if !skip_blank(&p) { ret (.Null, ok) }
    let (root, root_error) = parse_node(&p, p.lines[p.at].indent, 0usize)
    if root_error != ok { ret (zero, root_error) }
    if skip_blank(&p) { ret (zero, Invalid) }
    ret (root, ok)
}

fn has_content(lines: []const Line) -> bool {
    var i = 0usize
    while i < lines.len {
        if !is_blank(lines[i].text) { ret true }
        i += 1usize
    }
    ret false
}

// --- Writing, block style.

fn needs_quotes(text: str) -> bool {
    if text.len == 0usize { ret true }
    var scratch: [1024]u8 = zero
    var arena = mem.arena_from(scratch[0..])
    let (resolved, resolve_error) = resolve_plain(&arena, text)
    if resolve_error != ok { ret true }
    var stays_text = false
    switch resolved {
    case .String as same:
        stays_text = true
    default:
        stays_text = false
    }
    if !stays_text { ret true }
    if is_inline_space(text[0]) || is_inline_space(text[text.len - 1usize]) { ret true }
    let first = text[0]
    if first == 45u8 || first == 63u8 || first == 58u8 || first == 44u8 || first == 91u8 || first == 93u8 || first == 123u8 || first == 125u8 || first == 35u8 || first == 38u8 || first == 42u8 || first == 33u8 || first == 124u8 || first == 62u8 || first == 39u8 || first == 34u8 || first == 37u8 || first == 64u8 || first == 96u8 { ret true }
    var i = 0usize
    while i < text.len {
        let c = text[i]
        let (decoded, decode_error) = utf8.decode(text, i)
        if decode_error != ok || !is_yaml_printable(decoded.scalar) { ret true }
        // Presentation characters are not all legal in a plain scalar. Preserve
        // line breaks and tabs through the quoted escape path.
        if c == 9u8 || c == 10u8 || c == 13u8 { ret true }
        if c == 34u8 || c == 92u8 { ret true }
        if c == 58u8 && (i + 1usize == text.len || is_inline_space(text[i + 1usize])) { ret true }
        if c == 35u8 && i > 0usize && is_inline_space(text[i - 1usize]) { ret true }
        i += usize(decoded.width)
    }
    ret false
}

fn write_hex_escape(writer: *io.Writer, byte: u8) -> err {
    let digits = "0123456789abcdef"
    var escaped: [4]u8 = zero
    escaped[0usize] = 92u8
    escaped[1usize] = 120u8
    escaped[2usize] = digits[usize(byte) / 16usize]
    escaped[3usize] = digits[usize(byte) % 16usize]
    ret io.write_all(writer, escaped[..])
}

fn write_unicode_escape(writer: *io.Writer, scalar: u32) -> err {
    if scalar <= 255u32 { ret write_hex_escape(writer, u8(scalar)) }
    let digits = "0123456789abcdef"
    if scalar <= 65535u32 {
        var escaped: [6]u8 = zero
        escaped[0usize] = 92u8
        escaped[1usize] = 117u8
        var at = 2usize
        var shift = 12u32
        while at < escaped.len {
            escaped[at] = digits[usize((scalar >> shift) & 15u32)]
            shift -= 4u32
            at += 1usize
        }
        ret io.write_all(writer, escaped[..])
    }
    var escaped: [10]u8 = zero
    escaped[0usize] = 92u8
    escaped[1usize] = 85u8
    var at = 2usize
    var shift = 28u32
    while at < escaped.len {
        escaped[at] = digits[usize((scalar >> shift) & 15u32)]
        shift -= 4u32
        at += 1usize
    }
    ret io.write_all(writer, escaped[..])
}

fn write_string(writer: *io.Writer, text: str) -> err {
    if !utf8.validate(text) { ret Invalid }
    if !needs_quotes(text) { ret io.write_all(writer, text) }
    try io.write_all(writer, "\"")
    var run = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        let (decoded, decode_error) = utf8.decode(text, i)
        if decode_error != ok { ret Invalid }
        let width = usize(decoded.width)
        var escape = ""
        if c == 34u8 { escape = "\\\"" }
        if c == 92u8 { escape = "\\\\" }
        if c == 10u8 { escape = "\\n" }
        if c == 13u8 { escape = "\\r" }
        if c == 9u8 { escape = "\\t" }
        if escape.len > 0usize {
            try io.write_all(writer, text[run..i])
            try io.write_all(writer, escape)
            run = i + width
        } else {
            if !is_yaml_printable(decoded.scalar) {
                try io.write_all(writer, text[run..i])
                try write_unicode_escape(writer, decoded.scalar)
                run = i + width
            }
        }
        i += width
    }
    try io.write_all(writer, text[run..])
    ret io.write_all(writer, "\"")
}

fn write_u64(writer: *io.Writer, value: u64) -> err {
    var scratch: [32]u8 = zero
    var arena = mem.arena_from(scratch[0..])
    let (builder0, builder_error) = str.builder(&arena, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = builder0
    try str.push_u64(&builder, value)
    ret io.write_all(writer, str.done(&builder))
}

fn write_scalar(writer: *io.Writer, value: *const Value) -> err {
    var scratch: [64]u8 = zero
    var arena = mem.arena_from(scratch[0..])
    switch *value {
    case .Null:
        ret io.write_all(writer, "null")
    case .Bool as flag:
        if flag { ret io.write_all(writer, "true") }
        ret io.write_all(writer, "false")
    case .Integer as number:
        let (b0, builder_error) = str.builder(&arena, 64usize)
        if builder_error != ok { ret builder_error }
        var b = b0
        try str.push_i64(&b, number)
        ret io.write_all(writer, str.done(&b))
    case .Float as number:
        let (b0, builder_error) = str.builder(&arena, 64usize)
        if builder_error != ok { ret builder_error }
        var b = b0
        try str.push_f64(&b, number)
        let text = str.done(&b)
        if str.eq(text, "inf") { ret io.write_all(writer, ".inf") }
        if str.eq(text, "-inf") { ret io.write_all(writer, "-.inf") }
        if str.eq(text, "nan") { ret io.write_all(writer, ".nan") }
        try io.write_all(writer, text)
        if !str.contains(text, ".") && !str.contains(text, "e") { ret io.write_all(writer, ".0") }
        ret ok
    case .String as text:
        ret write_string(writer, text)
    default:
        ret Invalid
    }
}

fn write_indent(writer: *io.Writer, columns: usize) -> err {
    var i = 0usize
    while i < columns {
        try io.write_all(writer, " ")
        i += 1usize
    }
    ret ok
}

fn is_collection(value: *const Value) -> bool {
    switch *value {
    case .Sequence as items:
        ret items.len > 0usize
    case .Mapping as pairs:
        ret pairs.len > 0usize
    default:
        ret false
    }
}

// Writes `value` where the cursor already stands at column `columns` of a fresh line.
fn write_at(writer: *io.Writer, value: *const Value, columns: usize, indent: usize) -> err {
    switch *value {
    case .Sequence as items:
        if items.len == 0usize { ret io.write_all(writer, "[]\n") }
        var i = 0usize
        while i < items.len {
            if i > 0usize { try write_indent(writer, columns) }
            try io.write_all(writer, "- ")
            if is_collection(&items[i]) {
                try write_at(writer, &items[i], columns + 2usize, indent)
            } else {
                try write_scalar_or_empty(writer, &items[i])
                try io.write_all(writer, "\n")
            }
            i += 1usize
        }
        ret ok
    case .Mapping as pairs:
        if pairs.len == 0usize { ret io.write_all(writer, "{}\n") }
        var i = 0usize
        while i < pairs.len {
            if i > 0usize { try write_indent(writer, columns) }
            try write_scalar(writer, &pairs[i].key)
            try io.write_all(writer, ":")
            if is_collection(&pairs[i].value) {
                try io.write_all(writer, "\n")
                try write_indent(writer, columns + indent)
                try write_at(writer, &pairs[i].value, columns + indent, indent)
            } else {
                try io.write_all(writer, " ")
                try write_scalar_or_empty(writer, &pairs[i].value)
                try io.write_all(writer, "\n")
            }
            i += 1usize
        }
        ret ok
    default:
        try write_scalar(writer, value)
        ret io.write_all(writer, "\n")
    }
}

fn write_scalar_or_empty(writer: *io.Writer, value: *const Value) -> err {
    switch *value {
    case .Sequence as items:
        ret io.write_all(writer, "[]")
    case .Mapping as pairs:
        ret io.write_all(writer, "{}")
    default:
        ret write_scalar(writer, value)
    }
}

fn write(writer: *io.Writer, value: *const Value, indent: u8) -> err {
    if indent == 0u8 { ret Invalid }
    ret write_at(writer, value, 0usize, usize(indent))
}

// --- The typed codec.

fn pair_of(pairs: []const Pair, name: str) -> (Value, bool) {
    var i = 0usize
    while i < pairs.len {
        var matched = false
        switch pairs[i].key {
        case .String as key:
            matched = str.eq(key, name)
        default:
            matched = false
        }
        if matched { ret (pairs[i].value, true) }
        i += 1usize
    }
    ret (.Null, false)
}

// The parser stores integers as `i64`, but a typed field can be narrower or
// unsigned. Decide that conversion's range before making it: a direct narrowing
// cast traps in debug and wraps in release.
fn integer_into[T: type](number: i64) -> (T, err) {
    var out: T = zero
    let bits = u64(mem.size_of[T]() * 8usize)
    if meta.signed[T]() {
        if bits < 64u64 {
            let high = i64((1u64 << (bits - 1u64)) - 1u64)
            if number > high || number < 0i64 - high - 1i64 { ret (out, Invalid) }
        }
        out = T(number)
        ret (out, ok)
    }
    if number < 0i64 { ret (out, Invalid) }
    if bits < 64u64 && number > i64((1u64 << bits) - 1u64) { ret (out, Invalid) }
    out = T(number)
    ret (out, ok)
}

// A finite source must stay finite in the field. This still permits YAML's
// explicit `.inf` and `.nan` scalars, while rejecting a finite `f64` that
// overflows a narrower floating-point field.
fn float_into[T: type](number: f64) -> (T, err) {
    var out: T = zero
    let input_finite = number == number && number - number == 0.0f64
    out = T(number)
    let widened = f64(out)
    if input_finite && (widened != widened || widened - widened != 0.0f64) { ret (out, Invalid) }
    ret (out, ok)
}

fn decode[T: type](a: *mem.Arena, source: str, options: Options) -> (T, err) {
    var out: T = zero
    let (root, parse_error) = parse(a, source, options)
    if parse_error != ok { ret (out, parse_error) }
    var pairs: []const Pair = zero
    switch root {
    case .Mapping as found:
        pairs = found
    default:
        ret (out, Invalid)
    }
    for f in meta.fields[T]() {
        let (found, present) = pair_of(pairs, f.name)
        if present {
            if meta.kind[f.ty]() == .Slice {
                var text = ""
                switch found {
                case .String as written:
                    text = written
                default:
                    ret (out, Invalid)
                }
                meta.set[f, T](&out, text)
            } else {
            if meta.kind[f.ty]() == .Bool {
                var flag = false
                switch found {
                case .Bool as written:
                    flag = written
                default:
                    ret (out, Invalid)
                }
                meta.set[f, T](&out, flag)
            } else {
            if meta.kind[f.ty]() == .Int {
                var number = 0i64
                switch found {
                case .Integer as written:
                    number = written
                default:
                    ret (out, Invalid)
                }
                let (slot, slot_error) = integer_into[f.ty](number)
                if slot_error != ok { ret (out, slot_error) }
                meta.set[f, T](&out, slot)
            } else {
            if meta.kind[f.ty]() == .Float {
                var number: f64 = 0.0
                switch found {
                case .Float as written:
                    number = written
                case .Integer as written:
                    number = f64(written)
                default:
                    ret (out, Invalid)
                }
                let (slot, slot_error) = float_into[f.ty](number)
                if slot_error != ok { ret (out, slot_error) }
                meta.set[f, T](&out, slot)
            } else {
                ret (out, Invalid)
            }
            }
            }
            }
        }
    }
    ret (out, ok)
}

fn encode[T: type](writer: *io.Writer, value: *const T) -> err {
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        try write_string(writer, f.name)
        try io.write_all(writer, ": ")
        if meta.kind[f.ty]() == .Slice {
            try write_string(writer, slot)
        } else {
        if meta.kind[f.ty]() == .Bool {
            let item: Value = Value{ Bool: slot }
            try write_scalar(writer, &item)
        } else {
        if meta.kind[f.ty]() == .Int {
            // `Value.Integer` is deliberately signed. Do not cast an unsigned
            // field above that representation's range and turn it negative.
            if meta.signed[f.ty]() {
                let item: Value = Value{ Integer: i64(slot) }
                try write_scalar(writer, &item)
            } else {
                try write_u64(writer, u64(slot))
            }
        } else {
        if meta.kind[f.ty]() == .Float {
            let item: Value = Value{ Float: f64(slot) }
            try write_scalar(writer, &item)
        } else {
            ret Invalid
        }
        }
        }
        }
        try io.write_all(writer, "\n")
    }
    ret ok
}

// --- The writer R's `as.yaml` has: block style, a sequence under a mapping key at the key's own
// column, `yes`/`no` for a logical, reals at 7 significant digits with trailing zeros dropped
// (`2.0`, `1.0e+10`), a string that would read as another type single-quoted, a string with a
// newline a literal block, and libyaml's rules for when plain style is not allowed. Lines are not
// folded at column 80, and a multi-line mapping key is not supported.

const S_PLAIN: u8 = 0u8
const S_SINGLE: u8 = 1u8
const S_DOUBLE: u8 = 2u8
const S_LITERAL: u8 = 3u8

fn w_blankz(text: str, at: usize) -> bool {
    if at >= text.len { ret true }
    let c = text[at]
    ret c == 32u8 || c == 9u8 || c == 13u8 || c == 10u8
}

// The scalar at `at` of valid UTF-8 and its width.
fn w_scalar_at(text: str, at: usize) -> (u32, usize) {
    let c = text[at]
    if c < 128u8 { ret (u32(c), 1usize) }
    var width = 2usize
    var scalar = u32(c & 31u8)
    if c >= 240u8 {
        width = 4usize
        scalar = u32(c & 7u8)
    } else {
        if c >= 224u8 {
            width = 3usize
            scalar = u32(c & 15u8)
        }
    }
    var i = 1usize
    while i < width && at + i < text.len {
        scalar = (scalar << 6u32) | u32(text[at + i] & 63u8)
        i += 1usize
    }
    ret (scalar, width)
}

fn w_printable(scalar: u32) -> bool {
    if scalar == 10u32 { ret true }
    if scalar >= 32u32 && scalar <= 126u32 { ret true }
    if scalar >= 160u32 && scalar <= 55295u32 { ret true }
    if scalar >= 57344u32 && scalar <= 65533u32 && scalar != 65279u32 { ret true }
    ret scalar >= 65536u32 && scalar <= 1114111u32
}

// The style the emitter ends up with for a string: R's pick (single when the text has an implicit
// type, literal when it has a newline), then libyaml's analysis of what the text allows.
fn w_text_style(text: str) -> u8 {
    let tag = r_tag(text)
    var wanted = S_PLAIN
    if tag != T_STR && tag != T_SNA { wanted = S_SINGLE }
    if wanted == S_PLAIN && str.contains(text, "\n") { wanted = S_LITERAL }
    var block_indicators = false
    var line_breaks = false
    var special = false
    var leading_space = false
    var leading_break = false
    var trailing_space = false
    var trailing_break = false
    var break_space = false
    var space_break = false
    var previous_space = false
    var previous_break = false
    var preceded = true
    if text.len == 0usize {
        if wanted == S_PLAIN { ret S_SINGLE }
        ret wanted
    }
    if str.starts_with(text, "---") || str.starts_with(text, "...") { block_indicators = true }
    var at = 0usize
    while at < text.len {
        let (scalar, width) = w_scalar_at(text, at)
        let first = at == 0usize
        let last = at + width >= text.len
        let followed = w_blankz(text, at + width)
        if first {
            if scalar == 35u32 || scalar == 44u32 || scalar == 91u32 || scalar == 93u32 || scalar == 123u32 || scalar == 125u32 || scalar == 38u32 || scalar == 42u32 || scalar == 33u32 || scalar == 124u32 || scalar == 62u32 || scalar == 39u32 || scalar == 34u32 || scalar == 37u32 || scalar == 64u32 || scalar == 96u32 { block_indicators = true }
            if scalar == 63u32 || scalar == 58u32 {
                if followed { block_indicators = true }
            }
            if scalar == 45u32 && followed { block_indicators = true }
        } else {
            if scalar == 58u32 && followed { block_indicators = true }
            if scalar == 35u32 && preceded { block_indicators = true }
        }
        if !w_printable(scalar) { special = true }
        if scalar == 10u32 || scalar == 13u32 { line_breaks = true }
        if scalar == 32u32 {
            if first { leading_space = true }
            if last { trailing_space = true }
            if previous_break { break_space = true }
            previous_space = true
            previous_break = false
        } else {
            if scalar == 10u32 || scalar == 13u32 {
                if first { leading_break = true }
                if last { trailing_break = true }
                if previous_space { space_break = true }
                previous_space = false
                previous_break = true
            } else {
                previous_space = false
                previous_break = false
            }
        }
        preceded = scalar == 32u32 || scalar == 9u32 || scalar == 13u32 || scalar == 10u32
        at += width
    }
    var plain_allowed = true
    var single_allowed = true
    var block_allowed = true
    if leading_space || leading_break || trailing_space || trailing_break { plain_allowed = false }
    if trailing_space { block_allowed = false }
    if break_space {
        plain_allowed = false
        single_allowed = false
    }
    if space_break || special {
        plain_allowed = false
        single_allowed = false
        block_allowed = false
    }
    if line_breaks { plain_allowed = false }
    if block_indicators { plain_allowed = false }
    var style = wanted
    if style == S_PLAIN && !plain_allowed { style = S_SINGLE }
    if style == S_SINGLE && !single_allowed { style = S_DOUBLE }
    if style == S_LITERAL && !block_allowed { style = S_DOUBLE }
    ret style
}

fn w_hex_digit(n: u32) -> u8 {
    if n < 10u32 { ret 48u8 + u8(n) }
    ret 55u8 + u8(n)
}

fn w_escape_scalar(writer: *io.Writer, scalar: u32) -> err {
    var e = ""
    if scalar == 0u32 { e = "\\0" }
    if scalar == 7u32 { e = "\\a" }
    if scalar == 8u32 { e = "\\b" }
    if scalar == 9u32 { e = "\\t" }
    if scalar == 10u32 { e = "\\n" }
    if scalar == 11u32 { e = "\\v" }
    if scalar == 12u32 { e = "\\f" }
    if scalar == 13u32 { e = "\\r" }
    if scalar == 27u32 { e = "\\e" }
    if scalar == 34u32 { e = "\\\"" }
    if scalar == 92u32 { e = "\\\\" }
    if scalar == 133u32 { e = "\\N" }
    if scalar == 160u32 { e = "\\_" }
    if e.len > 0usize { ret io.write_all(writer, e) }
    var buf: [10]u8 = zero
    var digits = 2usize
    buf[0] = 92u8
    buf[1] = 120u8
    if scalar > 255u32 {
        digits = 4usize
        buf[1] = 117u8
    }
    if scalar > 65535u32 {
        digits = 8usize
        buf[1] = 85u8
    }
    var k = 0usize
    while k < digits {
        let shift = u32((digits - 1usize - k) * 4usize)
        buf[2usize + k] = w_hex_digit((scalar >> shift) & 15u32)
        k += 1usize
    }
    ret io.write_all(writer, buf[..2usize + digits])
}

// A string in the style chosen for it; true when it ended with its own line break (a literal block).
fn w_write_text(writer: *io.Writer, text: str, block_indent: usize) -> (bool, err) {
    let style = w_text_style(text)
    if style == S_PLAIN {
        let e = io.write_all(writer, text)
        ret (false, e)
    }
    if style == S_SINGLE {
        let open_error = io.write_all(writer, "'")
        if open_error != ok { ret (false, open_error) }
        var i = 0usize
        while i < text.len {
            var e = ok
            if text[i] == 39u8 { e = io.write_all(writer, "''") } else { e = io.write_all(writer, text[i..i + 1usize]) }
            if e != ok { ret (false, e) }
            i += 1usize
        }
        let close_error = io.write_all(writer, "'")
        ret (false, close_error)
    }
    if style == S_DOUBLE {
        let open_error = io.write_all(writer, "\"")
        if open_error != ok { ret (false, open_error) }
        var at = 0usize
        while at < text.len {
            let (scalar, width) = w_scalar_at(text, at)
            var e = ok
            if !w_printable(scalar) || scalar == 34u32 || scalar == 92u32 || scalar == 10u32 || scalar == 13u32 || scalar == 65279u32 {
                e = w_escape_scalar(writer, scalar)
            } else {
                e = io.write_all(writer, text[at..at + width])
            }
            if e != ok { ret (false, e) }
            at += width
        }
        let close_error = io.write_all(writer, "\"")
        ret (false, close_error)
    }
    var header = "|"
    if text.len > 0usize && (text[0] == 32u8 || text[0] == 10u8) { header = "|2" }
    var chomp = "-"
    if text.len > 0usize && text[text.len - 1usize] == 10u8 {
        chomp = ""
        if text.len > 1usize && text[text.len - 2usize] == 10u8 { chomp = "+" }
    }
    var e = io.write_all(writer, header)
    if e != ok { ret (true, e) }
    e = io.write_all(writer, chomp)
    if e != ok { ret (true, e) }
    e = io.write_all(writer, "\n")
    if e != ok { ret (true, e) }
    var line_start = true
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            e = io.write_all(writer, "\n")
            line_start = true
        } else {
            if line_start {
                e = write_indent(writer, block_indent)
                if e != ok { ret (true, e) }
                line_start = false
            }
            e = io.write_all(writer, text[i..i + 1usize])
        }
        if e != ok { ret (true, e) }
        i += 1usize
    }
    if !line_start {
        e = io.write_all(writer, "\n")
        if e != ok { ret (true, e) }
    }
    ret (true, ok)
}

// `%.Ne` of a positive number (N = frac) with trailing zeros dropped past the first.
fn w_sci(writer: *io.Writer, ax: f64, frac: usize) -> err {
    var kept: [32]u8 = zero
    let (exponent_in, digits_error) = cfloat.exp_digits(ax, frac, kept[..])
    if digits_error != ok { ret digits_error }
    var exponent = exponent_in
    var shown = frac + 1usize
    while shown > 2usize && kept[shown - 1usize] == 0u8 { shown -= 1usize }
    var out: [48]u8 = zero
    var n = 0usize
    out[n] = 48u8 + kept[0]
    n += 1usize
    out[n] = 46u8
    n += 1usize
    var d = 1usize
    while d < shown {
        out[n] = 48u8 + kept[d]
        n += 1usize
        d += 1usize
    }
    if shown == 1usize {
        out[n] = 48u8
        n += 1usize
    }
    out[n] = 101u8
    n += 1usize
    var magnitude = exponent
    if exponent < 0i64 {
        out[n] = 45u8
        magnitude = 0i64 - exponent
    } else {
        out[n] = 43u8
    }
    n += 1usize
    if magnitude >= 100i64 {
        out[n] = 48u8 + u8(magnitude / 100i64)
        n += 1usize
    }
    out[n] = 48u8 + u8(magnitude / 10i64 % 10i64)
    n += 1usize
    out[n] = 48u8 + u8(magnitude % 10i64)
    n += 1usize
    ret io.write_all(writer, out[..n])
}

fn w_real(writer: *io.Writer, x: f64, sci: *bool) -> err {
    if x != x { ret io.write_all(writer, ".nan") }
    if x == r_infinity() { ret io.write_all(writer, ".inf") }
    if x == 0.0f64 - r_infinity() { ret io.write_all(writer, "-.inf") }
    var ax = x
    if x < 0.0f64 { ax = 0.0f64 - x }
    if x != 0.0f64 && (ax < 0.0001f64 || ax >= 10000000.0f64) { *sci = true }
    if *sci {
        if (mem.bitcast[u64](x) >> 63u64) == 1u64 { try io.write_all(writer, "-") }
        if x == 0.0f64 { ret io.write_all(writer, "0.0e+00") }
        ret w_sci(writer, ax, 7usize)
    }
    var scratch: [512]u8 = zero
    var arena = mem.arena_from(scratch[0..])
    let (b0, builder_error) = str.builder(&arena, 400usize)
    if builder_error != ok { ret builder_error }
    var b = b0
    // The exact expansion, rounded at the 7th decimal with a tie going away from zero.
    try str.push_f64_fixed(&b, ax, 99u8)
    let t = str.done(&b)
    var point = 0usize
    while point < t.len && t[point] != 46u8 { point += 1usize }
    var out: [40]u8 = zero
    var n = 0usize
    if (mem.bitcast[u64](x) >> 63u64) == 1u64 {
        out[0] = 45u8
        n = 1usize
    }
    let sign_length = n
    var k = 0usize
    while k < point {
        out[n] = t[k]
        n += 1usize
        k += 1usize
    }
    out[n] = 46u8
    n += 1usize
    var d = 0usize
    while d < 7usize {
        out[n] = t[point + 1usize + d]
        n += 1usize
        d += 1usize
    }
    if t[point + 8usize] >= 53u8 {
        var j = n
        var carry = true
        while carry && j > sign_length {
            j -= 1usize
            if out[j] != 46u8 {
                if out[j] == 57u8 {
                    out[j] = 48u8
                } else {
                    out[j] += 1u8
                    carry = false
                }
            }
        }
        if carry {
            // 9.9999999 -> 10.0000000: shift right and write the leading one.
            var m = n
            while m > sign_length {
                out[m] = out[m - 1usize]
                m -= 1usize
            }
            out[sign_length] = 49u8
            n += 1usize
        }
    }
    var end = n
    while end > 1usize && out[end - 1usize] == 48u8 && out[end - 2usize] != 46u8 { end -= 1usize }
    ret io.write_all(writer, out[..end])
}

// A scalar or an empty collection; true when it wrote its own final line break.
fn w_scalar(writer: *io.Writer, value: *const Value, block_indent: usize, sci: *bool) -> (bool, err) {
    switch *value {
    case .Null:
        let e = io.write_all(writer, "~")
        ret (false, e)
    case .Bool as flag:
        var e = ok
        if flag { e = io.write_all(writer, "yes") } else { e = io.write_all(writer, "no") }
        ret (false, e)
    case .Integer as number:
        var scratch: [64]u8 = zero
        var arena = mem.arena_from(scratch[0..])
        let (b0, builder_error) = str.builder(&arena, 64usize)
        if builder_error != ok { ret (false, builder_error) }
        var b = b0
        let push_error = str.push_i64(&b, number)
        if push_error != ok { ret (false, push_error) }
        let e = io.write_all(writer, str.done(&b))
        ret (false, e)
    case .Float as number:
        let e = w_real(writer, number, sci)
        ret (false, e)
    case .NA as kind:
        var name = ".na"
        if kind == 1u8 { name = ".na.integer" }
        if kind == 2u8 { name = ".na.real" }
        if kind == 3u8 { name = ".na.character" }
        let e = io.write_all(writer, name)
        ret (false, e)
    case .String as text:
        let (block, e) = w_write_text(writer, text, block_indent)
        ret (block, e)
    case .Sequence as items:
        let e = io.write_all(writer, "[]")
        ret (false, e)
    case .Mapping as pairs:
        let e = io.write_all(writer, "{}")
        ret (false, e)
    }
}

// A value after a dash or a key's colon: a scalar or an empty collection, then its line break.
fn w_item(writer: *io.Writer, value: *const Value, col: usize, sci: *bool) -> err {
    let (block, e) = w_scalar(writer, value, col + 2usize, sci)
    if e != ok { ret e }
    if !block { ret io.write_all(writer, "\n") }
    ret ok
}

fn w_seq(writer: *io.Writer, items: []const Value, col: usize, inline_first: bool) -> err {
    // Ryaml_format_real keeps its `e` format once one element picks it, for the rest of a vector.
    var real_vector = items.len > 1usize
    var k = 0usize
    while k < items.len {
        if r_kind(items[k]) != 2u8 { real_vector = false }
        k += 1usize
    }
    var sticky = false
    var i = 0usize
    while i < items.len {
        var unused = false
        if !real_vector { sticky = false }
        if !(i == 0usize && inline_first) { try write_indent(writer, col) }
        try io.write_all(writer, "- ")
        switch items[i] {
        case .Sequence as inner:
            if inner.len > 0usize { try w_seq(writer, inner, col + 2usize, true) } else { try w_item(writer, &items[i], col, &unused) }
        case .Mapping as inner:
            if inner.len > 0usize { try w_map(writer, inner, col + 2usize, true) } else { try w_item(writer, &items[i], col, &unused) }
        default:
            try w_item(writer, &items[i], col, &sticky)
        }
        i += 1usize
    }
    ret ok
}

fn w_map(writer: *io.Writer, pairs: []const Pair, col: usize, inline_first: bool) -> err {
    var unused = false
    var i = 0usize
    while i < pairs.len {
        unused = false
        if !(i == 0usize && inline_first) { try write_indent(writer, col) }
        let (key_block, key_error) = w_scalar(writer, &pairs[i].key, col + 2usize, &unused)
        if key_error != ok { ret key_error }
        try io.write_all(writer, ":")
        switch pairs[i].value {
        case .Sequence as inner:
            if inner.len > 0usize {
                try io.write_all(writer, "\n")
                try w_seq(writer, inner, col, false)
            } else {
                try io.write_all(writer, " ")
                try w_item(writer, &pairs[i].value, col, &unused)
            }
        case .Mapping as inner:
            if inner.len > 0usize {
                try io.write_all(writer, "\n")
                try w_map(writer, inner, col + 2usize, false)
            } else {
                try io.write_all(writer, " ")
                try w_item(writer, &pairs[i].value, col, &unused)
            }
        default:
            try io.write_all(writer, " ")
            try w_item(writer, &pairs[i].value, col, &unused)
        }
        i += 1usize
    }
    ret ok
}

// R's `as.yaml` of the value `parse_r` gives back.
fn write_r(writer: *io.Writer, value: *const Value) -> err {
    var unused = false
    switch *value {
    case .Sequence as items:
        if items.len > 0usize { ret w_seq(writer, items, 0usize, false) }
    case .Mapping as pairs:
        if pairs.len > 0usize { ret w_map(writer, pairs, 0usize, false) }
    default:
        ret w_item(writer, value, 0usize, &unused)
    }
    ret w_item(writer, value, 0usize, &unused)
}
